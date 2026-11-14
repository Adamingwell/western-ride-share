import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const origin = 'https://adamingwell.github.io';
const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': origin,
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};
const reply = (status: number, body: object) => new Response(JSON.stringify(body), { status, headers });
const unavailable = 'Contact is temporarily unavailable. Please try again later.';

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return reply(405, { error: 'Method not allowed.' });
  if (request.headers.get('origin') !== origin) return reply(403, { error: 'Open the contact form from Western Ride Share.' });

  let body;
  try {
    const reader = request.body?.getReader();
    if (!reader) return reply(400, { error: 'Enter an email address and message.' });
    const decoder = new TextDecoder();
    let text = '';
    let bytes = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.length;
      if (bytes > 12000) {
        await reader.cancel();
        return reply(413, { error: 'Message is too long.' });
      }
      text += decoder.decode(value, { stream: true });
    }
    body = JSON.parse(text + decoder.decode());
  } catch {
    return reply(400, { error: 'Invalid request.' });
  }

  const email = typeof body?.email === 'string' ? body.email.trim() : '';
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !message || message.length > 2000) {
    return reply(400, { error: 'Enter a valid reply email and a message of up to 2,000 characters.' });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!url || !serviceKey || !resendKey) return reply(503, { error: unavailable });

  const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  let recipient = Deno.env.get('RIDE_SHARE_SUPPORT_EMAIL');
  if (!recipient) {
    const { data: admins, error } = await db.from('site_administrators').select('user_id').limit(2);
    if (error || admins?.length !== 1) return reply(503, { error: unavailable });
    const { data, error: lookupError } = await db.auth.admin.getUserById(admins[0].user_id);
    if (lookupError || !data.user?.email_confirmed_at || !data.user.email) return reply(503, { error: unavailable });
    recipient = data.user.email;
  }
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  const digest = await crypto.subtle.sign('HMAC', await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(serviceKey), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  ), new TextEncoder().encode(ip));
  const clientKey = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
  const now = Date.now();
  const windowStart = new Date(Math.floor(now / 120000) * 120000).toISOString();
  const dayStart = new Date(Math.floor(now / 86400000) * 86400000).toISOString();
  const { error: limitError } = await db.from('support_contact_rate_limits').insert([
    { client_key: clientKey, window_start: windowStart },
  ]);
  if (limitError?.code === '23505') return reply(429, { error: 'Please wait two minutes before sending another message.' });
  if (limitError) return reply(503, { error: unavailable });
  // Cap total daily mail even if requests come from many addresses.
  let reserved = false;
  for (let slot = 0; slot < 20; slot++) {
    const { error } = await db.from('support_contact_rate_limits').insert({ client_key: 'daily-' + slot, window_start: dayStart });
    if (!error) {
      reserved = true;
      break;
    }
    if (error.code !== '23505') return reply(503, { error: unavailable });
  }
  if (!reserved) return reply(429, { error: 'The contact form has reached its daily limit. Please try again tomorrow.' });

  try {
    const result = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + resendKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Western Ride Share Support <notifications@adamingwell.westernstudent.com>',
        to: [recipient],
        reply_to: email,
        subject: 'Western Ride Share support request',
        text: 'Reply address: ' + email + '\n\n' + message,
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!result.ok) return reply(502, { error: unavailable });
  } catch {
    return reply(502, { error: unavailable });
  }

  return reply(200, { sent: true });
});
