"""Combine explicitly enumerated v2.5.0 parallel holdout shards after completion."""
import gzip,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); specs=[('starter',0),('grown',2),('limited_c6_gear25',4),('limited_c6_gear25',5),('damage_c6_gear25',5),('optimized_c6',5),('theme_limited_c6_gear25',4),('theme_limited_c6_gear25',5)]; result=None
for profile,risk in specs:
 for policy,expected in [('reserve_locked',320),('default_unlocked',64)]:
  p=root/f'economy-v250-holdout-{profile}-r{risk}-{policy}.json';j=json.loads(p.read_text())
  if result is None:result={k:v for k,v in j.items() if k not in ['rows','errors','fixtures']};result['rows']=[];result['errors']=[];result['shards']=[];result['fixtures']={}
  assert j['hashes']==result['hashes'],f'hash mismatch: {p}'
  assert j['seedBase']==result['seedBase'],f'seed mismatch: {p}'
  assert len(j['rows'])==expected,f'incomplete shard: {p}'
  for key,fixture in j['fixtures'].items():
   assert key not in result['fixtures'] or result['fixtures'][key]==fixture,f'fixture mismatch: {key}'
   result['fixtures'][key]=fixture
  result['rows']+=j['rows'];result['errors']+=j['errors'];result['shards'].append(p.name)
farm_path=root/'economy-v250-drop-efficiency.json';farm=json.loads(farm_path.read_text())
assert farm['hashes']==result['hashes'],'farm source hash mismatch'
assert farm['runModes']=='abyss_sweep' and len(farm['rows'])==8*int(farm['sampleCount']),'farm sample count'
assert not set(r['seed'] for r in result['rows']).intersection(r['seed'] for r in farm['rows']),'farm seeds overlap main'
result['dropEfficiencySeedBase']=farm['seedBase'];result['dropEfficiencySamples']=farm['sampleCount'];result['rows']+=farm['rows'];result['errors']+=farm['errors'];result['shards'].append(farm_path.name)
for key,fixture in farm['fixtures'].items():
 assert key not in result['fixtures'],'farm fixture collision'
 result['fixtures'][key]=fixture
p=root/'economy-v250-final.json';p.write_text(json.dumps(result,ensure_ascii=False,indent=2));p.with_suffix('.json.gz').write_bytes(gzip.compress(p.read_bytes(),compresslevel=9,mtime=0));print(p.with_suffix('.json.gz'))
