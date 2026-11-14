// Scheduled server-side safety alert delivery. Requires a service-role JWT supplied by pg_cron from Vault.
// Never call from the browser. Deploy with verify_jwt:true.
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async req=>{
 const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
 if(req.method!=='POST')return json(405,{error:'Method not allowed'});
 const supplied=req.headers.get('authorization')?.replace(/^Bearer /i,'');
 const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!supplied||!serviceKey||supplied!==serviceKey)return json(403,{error:'Forbidden'});
 const url=Deno.env.get('SUPABASE_URL'),resendKey=Deno.env.get('RESEND_API_KEY');
 if(!url||!resendKey)return json(503,{error:'Missing configuration'});
 const db=createClient(url,serviceKey,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data:reports,error}=await db.from('safety_reports').select('id,created_at')
  .gte('created_at',new Date(Date.now()-7*86400000).toISOString()).order('created_at',{ascending:true}).limit(100);
 if(error)return json(500,{error:'Unable to read queue'});
 const {data:admins,error:adminError}=await db.from('site_administrators').select('user_id').limit(20);
 if(adminError||!admins?.length)return json(503,{error:'No administrators'});
 const addresses:string[]=[];
 for(const a of admins){const {data}=await db.auth.admin.getUserById(a.user_id);if(data?.user?.email&&data.user.email_confirmed_at)addresses.push(data.user.email)}
 if(!addresses.length)return json(503,{error:'No confirmed administrator email'});
 let sent=0,failed=0,skipped=0;
 for(const report of reports||[]){
  const {data:existing,error:lookupError}=await db.from('safety_report_email_deliveries').select('status,attempted_at').eq('report_id',report.id).maybeSingle();
  if(lookupError){failed++;continue}
  if(existing?.status==='sent'||existing?.status==='pending'&&Date.now()-new Date(existing.attempted_at).getTime()<10*60000){skipped++;continue}
  if(existing?.status==='failed'&&Date.now()-new Date(existing.attempted_at).getTime()<5*60000){skipped++;continue}
  const claim=existing
   ?await db.from('safety_report_email_deliveries').update({status:'pending',attempted_at:new Date().toISOString()}).eq('report_id',report.id).eq('status',existing.status).select('report_id').maybeSingle()
   :await db.from('safety_report_email_deliveries').insert({report_id:report.id,status:'pending'}).select('report_id').maybeSingle();
  if(claim.error||!claim.data){skipped++;continue}
  try{
   const site=(Deno.env.get('RIDE_SHARE_SITE_URL')||'https://adamingwell.github.io/western-ride-share').replace(/\\/$/,'');
   const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+resendKey,'Content-Type':'application/json','Idempotency-Key':'safety-report-'+report.id},body:JSON.stringify({from:'Western Ride Share Safety <notifications@adamingwell.westernstudent.com>',to:addresses,subject:'New safety report — Western Ride Share',text:'A new safety report was submitted. Review it in the restricted dashboard: '+site+'/admin.html'})});
   const body=await response.json().catch(()=>({}));
   await db.from('safety_report_email_deliveries').update({status:response.ok?'sent':'failed',provider_id:response.ok?body.id||null:null,attempted_at:new Date().toISOString()}).eq('report_id',report.id);
   if(response.ok)sent++;else failed++;
  }catch{await db.from('safety_report_email_deliveries').update({status:'failed',attempted_at:new Date().toISOString()}).eq('report_id',report.id);failed++}
 }
 return json(200,{sent,failed,skipped});
});
