async function account(request, env, user, url) {
  const email = request.headers.get('oai-authenticated-user-email');
  if (request.method === 'GET') {
    const settings = await env.DB.prepare(
      'SELECT email_enabled FROM notification_recipients WHERE user_id = ?'
    ).bind(user).first();
    return json({email, emailEnabled: settings?.email_enabled !== 0});
  }
  if (request.method !== 'POST') return json({error:'Method not allowed.'}, 405);
  if (request.headers.get('origin') !== url.origin) return json({error:'Invalid origin.'}, 403);
  const settings = await request.json().catch(() => null);
  if (!email || typeof settings?.emailEnabled !== 'boolean') {
    return json({error:'A signed-in email and a notification preference are required.'}, 400);
  }
  await env.DB.prepare(
    'INSERT INTO notification_recipients (user_id, email, email_enabled) VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET email = excluded.email, email_enabled = excluded.email_enabled'
  ).bind(user, email, Number(settings.emailEnabled)).run();
  return json({ok:true});
}

async function registerNotificationRecipient(request, env, user, url) {
  if (request.headers.get('origin') !== url.origin) return json({error:'Invalid origin.'}, 403);
  const email = request.headers.get('oai-authenticated-user-email');
  if (email) {
    await env.DB.prepare(
      'INSERT INTO notification_recipients (user_id, email) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET email = excluded.email WHERE email <> excluded.email'
    ).bind(user, email).run();
  }
  return json({ok:true});
}

async function notifyRecipient(env, sequence) {
  if (!env.RESEND_API_KEY || !env.EMAIL_FROM) return 'unconfigured';
  try {
    const message = await env.DB.prepare(
      `SELECT email, email_enabled, body, subject FROM ride_messages
       JOIN notification_recipients ON user_id =
         CASE WHEN sender_id = poster_id THEN visitor_id ELSE poster_id END
       WHERE sequence = ?`
    ).bind(sequence).first();
    if (!message) return 'unregistered';
    if (!message.email_enabled) return 'disabled';

    const response = await fetch('https://api.resend.com/emails', {
      method:'POST',
      signal:AbortSignal.timeout(5000),
      headers:{
        Authorization:'Bearer ' + env.RESEND_API_KEY,
        'Content-Type':'application/json',
        'Idempotency-Key':'western-ride-message/' + sequence
      },
      body:JSON.stringify({
        from:env.EMAIL_FROM,
        to:[message.email],
        subject:'New Western Ride Share message',
        text:message.subject + '\n\n' + message.body +
          '\n\nTo reply, open Messages at https://western-rideshare.ingwella.chatgpt.site/'
      })
    });
    if (response.ok) return 'accepted';
    console.warn('Ride email delivery rejected', response.status);
    return response.status === 403 ? 'forbidden' : 'rejected';
  } catch {
    console.warn('Ride email delivery failed');
    return 'unconfirmed';
  }
}

async function messages(request, env, url, user) {
  const thread = url.pathname.match(/^\/api\/messages\/([a-f0-9-]{36})$/);
  const participant = '(poster_id = ? OR visitor_id = ?)';

  if (request.method === 'GET' && url.pathname === '/api/messages') {
    const ride = url.searchParams.get('ride');
    const {results} = await env.DB.prepare(
      `SELECT thread_id AS id, subject, MAX(sequence) AS latest
       FROM ride_messages WHERE ${participant} AND (? IS NULL OR ride_id = ?)
       GROUP BY thread_id, subject ORDER BY latest DESC`
    ).bind(user, user, ride, ride).all();
    return json(results);
  }

  if (request.method === 'GET' && thread) {
    const {results} = await env.DB.prepare(
      `SELECT body, sent_at, sender_id = ? AS mine
       FROM ride_messages WHERE thread_id = ? AND ${participant} ORDER BY sequence`
    ).bind(user, thread[1], user, user).all();
    return results.length ? json(results) : json({error:'Conversation not found.'}, 404);
  }

  if (request.method !== 'POST' || (!thread && url.pathname !== '/api/messages')) {
    return json({error:'Not found.'}, 404);
  }
  if (request.headers.get('origin') !== url.origin) {
    return json({error:'Open the ride board to send a message.'}, 403);
  }

  const input = await request.json().catch(() => null);
  const body = typeof input?.body === 'string' ? input.body.trim() : '';
  if (!body || body.length > 1000) {
    return json({error:'Enter a message between 1 and 1,000 characters.'}, 400);
  }

  if (thread) {
    const result = await env.DB.prepare(
      `INSERT INTO ride_messages (thread_id, ride_id, poster_id, visitor_id, sender_id, subject, body, sent_at)
       SELECT thread_id, ride_id, poster_id, visitor_id, ?, subject, ?, ?
       FROM ride_messages WHERE thread_id = ? AND ${participant} ORDER BY sequence LIMIT 1`
    ).bind(user, body, Date.now(), thread[1], user, user).run();
    if (!result.meta.changes) return json({error:'Conversation not found.'}, 404);
    const notification = await notifyRecipient(env, result.meta.last_row_id);
    return json({id:thread[1], notification}, 201);
  }

  if (typeof input.rideId !== 'string' || !/^[a-f0-9-]{36}$/.test(input.rideId)) {
    return json({error:'Ride post not found.'}, 404);
  }
  const id = crypto.randomUUID();
  const result = await env.DB.prepare(
    `INSERT INTO ride_messages (thread_id, ride_id, poster_id, visitor_id, sender_id, subject, body, sent_at)
     SELECT COALESCE((
       SELECT thread_id FROM ride_messages WHERE ride_id = rides.id AND visitor_id = ?
       ORDER BY sequence LIMIT 1
     ), ?), id, owner_id, ?, ?,
     CASE direction WHEN 'campus' THEN community || ' → Western' ELSE 'Western → ' || community END,
     ?, ? FROM rides WHERE id = ? AND owner_id <> ?`
  ).bind(user, id, user, user, body, Date.now(), input.rideId, user).run();
  if (!result.meta.changes) return json({error:'Ride post not found.'}, 404);
  const row = await env.DB.prepare(
    'SELECT thread_id AS id FROM ride_messages WHERE sequence = ?'
  ).bind(result.meta.last_row_id).first();
  const notification = await notifyRecipient(env, result.meta.last_row_id);
  return json({...row, notification}, 201);
}
