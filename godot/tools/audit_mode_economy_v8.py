"""Independent accounting and sample-integrity checks for economy simulations."""
import json,sys,collections,pathlib
p=pathlib.Path(sys.argv[1]);j=json.loads(p.read_text());errors=[];groups=collections.defaultdict(list)
for r in j['rows']:
 key=(r['profile'],r['mode'],r['risk'],r.get('kit',''),r.get('targetAct',0),r.get('recycling',False))
 groups[key].append(r)
 if r['mode']=='extraction':
  expected=r['walletDelta']+r['retainedAssets']-r['repairReserve']
  if r.get('goldLiquidation',r['gold'])!=expected:errors.append(('liquidation',key,r['seed']))
  if r['gold']!=expected+r.get('keyRetainedCapital',0)-r.get('keyRetainedCapitalSale',0):errors.append(('operating',key,r['seed']))
  if r.get('keyConsumedCost',0)<0:errors.append(('negative key cost',key,r['seed']))
  if sum(r.get('retainedByKind',{}).values()) not in (0,r['retainedAssets']):errors.append(('asset categories',key,r['seed']))
  if r['salvageGold']<0 or r['repairReserve']<0:errors.append(('negative gold',key,r['seed']))
 else:
  if r['gold']!=r['goldDirect']+r['relicSell']:errors.append(('abyss gold',key,r['seed']))
 if r['steps']<0 or r['secondsFast']>r['secondsDeliberate']:errors.append(('time',key,r['seed']))
for key,rs in groups.items():
 seeds=[r['seed'] for r in rs]
 if len(seeds)!=len(set(seeds)):errors.append(('duplicate seeds',key))
 if len(sys.argv)>2 and len(seeds)!=int(sys.argv[2]):errors.append(('sample count',key,len(seeds)))
errors+=j['errors']
print(json.dumps({'file':str(p),'trials':len(j['rows']),'conditions':len(groups),'errors':errors},ensure_ascii=False))
raise SystemExit(bool(errors))
