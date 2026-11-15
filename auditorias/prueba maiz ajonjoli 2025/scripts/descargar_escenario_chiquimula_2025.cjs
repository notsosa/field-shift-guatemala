// Fuentes públicas para un hindcast, sin credenciales ni pronóstico retrospectivo.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const base='datos/escenarios/chiquimula_2025';fs.mkdirSync(base,{recursive:true});
const lat=14.8250,lon=-89.5312;
const log=[];
async function get(name,url){
 const target=path.join(base,name);
 if(fs.existsSync(target)){console.log(name+': caché');return JSON.parse(fs.readFileSync(target,'utf8'));}
 const start=Date.now();
 try{
  const r=await fetch(url,{signal:AbortSignal.timeout(60000)});const bytes=Buffer.from(await r.arrayBuffer());
  const record={archivo:name,url,status:r.status,bytes:bytes.length,fecha_utc:new Date().toISOString(),sha256:crypto.createHash('sha256').update(bytes).digest('hex'),segundos:(Date.now()-start)/1000};log.push(record);
  if(!r.ok)throw Error('HTTP '+r.status+' '+bytes.toString().slice(0,150));
  const json=JSON.parse(bytes.toString());if(json.error)throw Error(JSON.stringify(json).slice(0,200));
  fs.writeFileSync(target,bytes); console.log(name+': '+bytes.length+' bytes');return json;
 }catch(e){console.log(name+': '+e.message); log.push({archivo:name,url,error:e.message});return null;}
}
async function main(){
 if(process.argv.includes('--poll')){
  for(const key of ['imerg_v07_late','chirps_v2']){
   const jp=path.join(base,key+'_job.json');if(!fs.existsSync(jp))continue;
   const submitted=JSON.parse(fs.readFileSync(jp,'utf8'));const id=Array.isArray(submitted)?submitted[0]:submitted;
   const progressUrl='https://climateserv.servirglobal.net/api/getDataRequestProgress/?id='+encodeURIComponent(id);
   try{const r=await fetch(progressUrl,{signal:AbortSignal.timeout(30000)});const progress=await r.json();console.log(key+' progreso: '+JSON.stringify(progress));
    fs.writeFileSync(path.join(base,key+'_progreso.json'),JSON.stringify({job_id:id,fecha_utc:new Date().toISOString(),progress,status:r.status,url:progressUrl},null,2)+'\n');
    if(Number(Array.isArray(progress)?progress[0]:progress)>=100)await get(key+'_2025.json','https://climateserv.servirglobal.net/api/getDataFromRequest/?id='+encodeURIComponent(id));
   }catch(e){console.log(key+': '+e.message);}
  }
  const lp=path.join(base,'descargas.json');const old=fs.existsSync(lp)?JSON.parse(fs.readFileSync(lp,'utf8')):[];fs.writeFileSync(lp,JSON.stringify([...old,...log],null,2)+'\n');return;
 }
 const params=['T2M','T2M_MAX','T2M_MIN','T2MDEW','RH2M','WS2M','ALLSKY_SFC_SW_DWN','CLRSKY_SFC_SW_DWN','PRECTOTCORR','PS','GWETTOP','GWETROOT','GWETPROF','EVLAND'];
 const power=new URL('https://power.larc.nasa.gov/api/temporal/daily/point');power.search=new URLSearchParams({parameters:params.join(','),community:'AG',longitude:lon,latitude:lat,start:'20250101',end:'20251231',format:'JSON','time-standard':'LST'});
 const om=new URL('https://archive-api.open-meteo.com/v1/archive');om.search=new URLSearchParams({latitude:lat,longitude:lon,start_date:'2025-01-01',end_date:'2025-12-31',daily:'precipitation_sum,temperature_2m_max,temperature_2m_min,et0_fao_evapotranspiration',hourly:'soil_moisture_0_to_7cm,soil_moisture_7_to_28cm,soil_moisture_28_to_100cm',models:'era5',timezone:'America/Guatemala',elevation:'373'});
 const r=.015;const geom={type:'Polygon',coordinates:[[[lon-r,lat-r],[lon+r,lat-r],[lon+r,lat+r],[lon-r,lat+r],[lon-r,lat-r]]]};
 const jobs=[['power_2025.json',power.toString()],['era5_2025.json',om.toString()]];
 for(const [key,datatype] of [['imerg_v07_late',226],['chirps_v2',0]]){
  const u=new URL('https://climateserv.servirglobal.net/api/submitDataRequest/');u.search=new URLSearchParams({datatype:String(datatype),begintime:'01/01/2025',endtime:'12/31/2025',intervaltype:'0',operationtype:'5',geometry:JSON.stringify(geom)});jobs.push([key+'_job.json',u.toString()]);
 }
 await Promise.allSettled(jobs.map(([n,u])=>get(n,u)));
 const lp=path.join(base,'descargas.json');let old=fs.existsSync(lp)?JSON.parse(fs.readFileSync(lp,'utf8')):[];fs.writeFileSync(lp,JSON.stringify([...old,...log],null,2)+'\n');
}
main().catch(e=>{console.error(e);process.exitCode=1});
