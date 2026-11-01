import json,sys,collections,statistics as st
j=json.load(open(sys.argv[1]));groups=collections.defaultdict(list)
for r in j['rows']:
 if r['mode']=='extraction' and r['targetAct']==1 and not r['recycling']:groups[(r['profile'],r['risk'],r['kit'])].append(r)
for key,rs in groups.items():
 print('FIRST ACT',key,'N',len(rs),'meanGold',round(st.mean(r['gold'] for r in rs)))
 for field in ['firstFullBag','firstActExitBag']:
  bags=[r[field] for r in rs if r.get(field) and r[field]['act']==1]
  print(field,'n',len(bags))
  for category in ['byKind','byRarity']:
   keys=set().union(*(b[category] for b in bags))
   print(category,{k:{m:round(st.mean(b[category].get(k,{}).get(m,0) for b in bags),2) for m in ['cells','value','count']} for k in sorted(keys)})
for r in j['rows']:
 if r['mode']=='extraction' and r['targetAct']==3 and r['recycling']:
  groups.setdefault(('cashout',r['profile'],r['kit']),[]).append(r)
for key,rs in groups.items():
 if key[0]!='cashout':continue
 dead=[r for r in rs if not r['success']]
 print(key,'complete',len(rs)-len(dead),'/',len(rs),'net',round(st.mean(r['gold'] for r in rs)),'salvaged',round(st.mean(r['salvageGold'] for r in rs)),'dead_n',len(dead),'dead_net',round(st.mean(r['gold'] for r in dead)) if dead else None,'dead_salvaged',round(st.mean(r['salvageGold'] for r in dead)) if dead else None)
