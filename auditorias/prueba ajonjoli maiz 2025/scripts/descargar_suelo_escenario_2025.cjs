const fs=require('node:fs'),crypto=require('node:crypto');
const base='datos/escenarios/chiquimula_2025/suelo_wcs';fs.mkdirSync(base,{recursive:true});
const lat=14.825,lon=-89.5312,r=.003,depths=['0-5cm','5-15cm','15-30cm','30-60cm','60-100cm'];
let jobs=depths.flatMap(d=>['wv0033','wv1500','cfvo'].map(p=>[p,d]));
jobs.push(...['clay','sand','silt','phh2o','soc','bdod'].map(p=>[p,'0-5cm']));
let records=[];
async function worker(){while(jobs.length){const [p,d]=jobs.shift(),file=p+'_'+d+'.tif';if(fs.existsSync(base+'/'+file)){console.log(file+': caché');continue;}
 const u=new URL('https://maps.isric.org/mapserv');
 for(const [k,v] of [['map','/map/'+p+'.map'],['SERVICE','WCS'],['VERSION','2.0.1'],['REQUEST','GetCoverage'],['COVERAGEID',p+'_'+d+'_mean'],['FORMAT','image/tiff'],['SUBSET',`long(${lon-r},${lon+r})`],['SUBSET',`lat(${lat-r},${lat+r})`],['SUBSETTINGCRS','http://www.opengis.net/def/crs/EPSG/0/4326'],['OUTPUTCRS','http://www.opengis.net/def/crs/EPSG/0/4326']])u.searchParams.append(k,v);
 try{const resp=await fetch(u,{signal:AbortSignal.timeout(45000)}),b=Buffer.from(await resp.arrayBuffer());const valid=resp.ok&&(b.subarray(0,2).toString()==='II'||b.subarray(0,2).toString()==='MM');
 records.push({file,url:u.toString(),status:resp.status,bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex'),tiff:valid,fecha_utc:new Date().toISOString()});
 if(valid)fs.writeFileSync(base+'/'+file,b);console.log(file+': '+(valid?'TIFF '+b.length:'falló HTTP '+resp.status));
 }catch(e){records.push({file,url:u.toString(),error:e.message});console.log(file+': '+e.message);}
}}
Promise.all(Array.from({length:3},worker)).then(()=>{const lp=base+'/descargas.json';const prev=fs.existsSync(lp)?JSON.parse(fs.readFileSync(lp,'utf8')):[];fs.writeFileSync(lp,JSON.stringify([...prev,...records],null,2)+'\n');});
