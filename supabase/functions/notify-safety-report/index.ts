// Authenticated, idempotent safety report alert; deploy with JWT verification enabled.
// Required secrets: RESEND_API_KEY, SUPABASE_SERVICE_ROLE_KEY. Supabase provides SUPABASE_URL.
// Only report owners can request an alert for their own report. No report content is emailed.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async request => {
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'https://adamingwell.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
 const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return reply(405,{error:'Method not allowed'});
 const token=request.headers.get('authorization')?.replace(/^Bearer /i,'');
 if(!token)return reply(401,{error:'Authentication required'});
 const url=Deno.env.get('SUPABASE_URL'),serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),resendKey=Deno.env.get('RESEND_API_KEY');
 if(!url||!serviceKey||!resendKey)return reply(503,{error:'Notification service not configured'});
 const db=createClient(url,serviceKey,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data:{user},error:authError}=await db.auth.getUser(token);
 if(authError||!user)return reply(401,{error:'Invalid session'});
 let reportId:string;
 try{const body=await request.json();reportId=body.reportId}catch{return reply(400,{error:'Invalid JSON'})}
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(reportId||''))return reply(400,{error:'Invalid report id'});
 const {data:report,error:reportError}=await db.from('safety_reports').select('id,reporter_id,created_at').eq('id',reportId).maybeSingle();
 if(reportError){console.error('Safety report lookup failed',{code:reportError.code,message:reportError.message});return reply(500,{error:'Unable to verify report',code:reportError.code||'unknown'});}
 if(!report||report.reporter_id!==user.id)return reply(404,{error:'Report not found'});
 // Prevent an old report from being repeatedly used to initiate notifications.
 if(Date.now()-new Date(report.created_at).getTime()>15*60*1000)return reply(409,{error:'Report notification window expired'});
 const {error:claimError}=await db.from('safety_report_email_deliveries').insert({report_id:reportId,status:'pending'});
 if(claimError){
  if(claimError.code==='23505')return reply(200,{status:'already_processed'});
  return reply(500,{error:'Unable to claim notification'});
 }
 const {data:admins,error:adminsError}=await db.from('site_administrators').select('user_id').limit(20);
 if(adminsError||!admins?.length){await db.from('safety_report_email_deliveries').update({status:'failed'}).eq('report_id',reportId);return reply(503,{error:'No safety administrators configured'})}
 const addresses:string[]=[];
 for(const admin of admins){const {data}=await db.auth.admin.getUserById(admin.user_id);if(data?.user?.email&&data.user.email_confirmed_at)addresses.push(data.user.email)}
 if(!addresses.length){await db.from('safety_report_email_deliveries').update({status:'failed'}).eq('report_id',reportId);return reply(503,{error:'No confirmed administrator email'})}
 const site='https://adamingwell.github.io/western-ride-share-preview/admin.html';
 let response:Response;
 try{response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+resendKey,'Content-Type':'application/json'},body:JSON.stringify({
 from:'Western Ride Share Safety <notifications@adamingwell.westernstudent.com>',
 to:addresses,subject:'New safety report — Western Ride Share',
 text:'A new safety report has been submitted. Sign in to the restricted administrator dashboard to review it: '+site+'\n\nDo not reply to this automated notification.'
 })})}catch(e){await db.from('safety_report_email_deliveries').update({status:'failed'}).eq('report_id',reportId);return reply(502,{error:'Email delivery unavailable'})}
 const result=await response.json().catch(()=>({}));
 await db.from('safety_report_email_deliveries').update({status:response.ok?'sent':'failed',provider_id:response.ok?result.id||null:null,attempted_at:new Date().toISOString()}).eq('report_id',reportId);
 return response.ok?reply(200,{status:'sent'}):reply(502,{error:'Email provider rejected notification'});
});
