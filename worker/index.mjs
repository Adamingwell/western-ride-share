const daysOfWeek = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

function json(body, status = 200) {
  return Response.json(body, {status, headers: {'Cache-Control': 'no-store'}});
}

async function rides(request, env, url, owner) {
  if (request.method === 'GET' && url.pathname === '/api/rides') {
    const { results } = await env.DB.prepare(
      `SELECT id, owner_id, kind, direction, community, days, time,
        CASE WHEN owner_id = ? THEN (
          SELECT COUNT(DISTINCT thread_id) FROM ride_messages
          WHERE ride_id = rides.id AND poster_id = rides.owner_id AND sender_id = visitor_id
        ) ELSE 0 END AS conversationCount
        FROM rides ORDER BY created_at DESC, id DESC`
    ).bind(owner).all();
    return json(results.map(({owner_id, days, ...ride}) => ({
      ...ride, days: JSON.parse(days), mine: owner_id === owner
    })));
  }

  if (request.headers.get('origin') !== url.origin) {
    return json({error: 'Open the ride board to make changes.'}, 403);
  }

  if (request.method === 'POST' && url.pathname === '/api/rides') {
    const ride = await request.json().catch(() => null);
    if (!ride || !['Request','Offer'].includes(ride.kind) ||
        !['campus','home'].includes(ride.direction) || !communities.has(ride.community) ||
        typeof ride.time !== 'string' || !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(ride.time) ||
        !Array.isArray(ride.days) || !ride.days.length || ride.days.some(day => !daysOfWeek.includes(day))) {
      return json({error: 'Choose a community, direction, class day, and valid time.'}, 400);
    }
    const id = crypto.randomUUID();
    const days = daysOfWeek.filter(day => ride.days.includes(day));
    await env.DB.prepare(
      'INSERT INTO rides (id, owner_id, kind, direction, community, days, time, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind(id, owner, ride.kind, ride.direction, ride.community, JSON.stringify(days), ride.time, Date.now()).run();
    return json({id}, 201);
  }

  const match = url.pathname.match(/^\/api\/rides\/([a-f0-9-]{36})$/);
  if (request.method === 'DELETE' && match) {
    const result = await env.DB.prepare('DELETE FROM rides WHERE id = ? AND owner_id = ?')
      .bind(match[1], owner).run();
    return result.meta.changes ? json({ok: true}) : json({error: 'Post not found.'}, 404);
  }
  return json({error: 'Not found.'}, 404);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const owner = request.headers.get('oai-authenticated-user-id');
    if (url.pathname === '/' && request.method === 'GET') {
      if (!owner) return Response.redirect('https://western-ride-share-pilot.ingwella.chatgpt.site/sign-in.html', 302);
      return new Response(html, {headers: {'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store'}});
    }
    if (!url.pathname.startsWith('/api/')) return json({error: 'Not found.'}, 404);
    if (!owner) return json({error: 'Sign in to view the shared ride board.'}, 401);
    try {
      if (url.pathname === '/api/account') return await account(request, env, owner, url);
      if (request.method === 'POST' && url.pathname === '/api/notification-recipient') {
        return await registerNotificationRecipient(request, env, owner, url);
      }
      if (url.pathname === '/api/messages' || url.pathname.startsWith('/api/messages/')) {
        return await messages(request, env, url, owner);
      }
      return await rides(request, env, url, owner);
    } catch {
      return json({error: 'The ride board is temporarily unavailable.'}, 503);
    }
  }
};
