"""Combine explicitly enumerated v2.4.1 parallel holdout shards after completion."""
import gzip,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); specs=[('starter',0),('grown',2),('limited_c6_gear25',4),('limited_c6_gear25',5),('damage_c6_gear25',5),('optimized_c6',5)]; result=None
for profile,risk in specs:
 for policy,expected in [('reserve_locked',320),('default_unlocked',64)]:
  p=root/f'economy-v241-holdout-{profile}-r{risk}-{policy}.json';j=json.loads(p.read_text())
  if result is None:result={k:v for k,v in j.items() if k not in ['rows','errors']};result['rows']=[];result['errors']=[];result['shards']=[]
  assert j['hashes']==result['hashes'],f'hash mismatch: {p}'
  assert j['seedBase']==result['seedBase'],f'seed mismatch: {p}'
  assert len(j['rows'])==expected,f'incomplete shard: {p}'
  result['rows']+=j['rows'];result['errors']+=j['errors'];result['shards'].append(p.name)
p=root/'economy-v241-final.json';p.write_text(json.dumps(result,ensure_ascii=False,indent=2));p.with_suffix('.json.gz').write_bytes(gzip.compress(p.read_bytes(),compresslevel=9,mtime=0));print(p.with_suffix('.json.gz'))
