// Supabase Edge Function: send a ride-message email after a successful message RPC.
// Deploy with JWT verification enabled. Secrets: RESEND_API_KEY, SUPABASE_SERVICE_ROLE_KEY.
// SUPABASE_URL is supplied by Supabase. Never expose secrets in GitHub Pages.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async (request) => {
  const headers = { 'Content-Type':'application/json', 'Access-Control-Allow-Origin':'https://adamingwell.github.io', 'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods':'POST, OPTIONS' };
  const reply = (status:number, body:unknown) => new Response(JSON.stringify(body),{status,headers});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply(405,{error:'Method not allowed'});
  const token=request.headers.get('authorization')?.replace(/^Bearer /i,'');
  if(!token)return reply(401,{error:'Authentication required'});
  const url=Deno.env.get('SUPABASE_URL')!;
  const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const resendKey=Deno.env.get('RESEND_API_KEY');
  const siteUrl=Deno.env.get('RIDE_SHARE_SITE_URL') || 'https://adamingwell.github.io/western-ride-share-preview';
  if(!resendKey)return reply(503,{error:'Email notifications not configured'});
  const admin=createClient(url,serviceKey,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:{user},error:authError}=await admin.auth.getUser(token);
  if(authError||!user)return reply(401,{error:'Invalid session'});
  let threadId:string;
  try{({threadId}=await request.json());}catch{return reply(400,{error:'Invalid JSON'});}
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(threadId||''))return reply(400,{error:'Invalid thread'});
  const {data:message,error:messageError}=await admin.from('ride_messages')
    .select('id,thread_id,poster_id,visitor_id,sender_id,subject,body')
    .eq('thread_id',threadId).eq('sender_id',user.id).order('sent_at',{ascending:false}).limit(1).maybeSingle();
  if(messageError) {
    console.error('Notification message lookup failed', {code:messageError.code, message:messageError.message});
    return reply(500,{error:'Message lookup failed',code:messageError.code||'unknown'});
  }
  if(!message)return reply(404,{error:'No message found for this sender in the conversation'});
  if(message.sender_id!==user.id)return reply(403,{error:'Message sender mismatch'});
  const recipientId=message.sender_id===message.poster_id?message.visitor_id:message.poster_id;
  const {data:pref,error:prefError}=await admin.from('notification_preferences').select('email_enabled').eq('user_id',recipientId).maybeSingle();
  if(prefError)return reply(500,{error:'Unable to read notification preference'});
  if(pref?.email_enabled===false)return reply(200,{status:'disabled'});
  // Unique message id prevents retries from sending duplicates.
  const {data:claimed,error:claimError}=await admin.from('message_email_deliveries')
    .insert({message_id:message.id,recipient_id:recipientId,status:'pending'})
    .select('message_id').maybeSingle();
  if(claimError){
    if(claimError.code==='23505')return reply(200,{status:'already_processed'});
    return reply(500,{error:'Unable to record delivery'});
  }
  const {data:recipient,error:recipientError}=await admin.auth.admin.getUserById(recipientId);
  if(recipientError||!recipient?.user?.email){
    await admin.from('message_email_deliveries').update({status:'failed'}).eq('message_id',message.id);
    return reply(500,{error:'Recipient email unavailable'});
  }
  const response=await fetch('https://api.resend.com/emails',{
    method:'POST',
    headers:{Authorization:'Bearer '+resendKey,'Content-Type':'application/json'},
    body:JSON.stringify({
      from:'Western Ride Share <notifications@adamingwell.westernstudent.com>',
      to:[recipient.user.email],
      subject:'New message on Western Ride Share',
      text:'You have a new private message about a ride. Sign in to read and reply: '+(siteUrl.endsWith('/')?siteUrl.slice(0,-1):siteUrl)+'/board.html',
    })
  });
  const result=await response.json().catch(()=>({}));
  await admin.from('message_email_deliveries').update({status:response.ok?'sent':'failed',provider_id:response.ok?(result.id||null):null}).eq('message_id',message.id);
  return response.ok?reply(200,{status:'accepted'}):reply(502,{error:'Email provider rejected notification'});
});
