import json,sys,pathlib,collections,statistics as st
p=pathlib.Path(sys.argv[1]);j=json.loads(p.read_text());groups=collections.defaultdict(list);errors=list(j['errors'])
for r in j['rows']:
 key=(r['profile'],r['mode'],r['risk'],r.get('camp',''),r.get('attempt',''))
 groups[key].append(r)
 if r['mode']=='abyss':
  if r['goldDirect']!=0:errors.append(('direct gold',key,r['seed']))
  if r['diamonds']!=r['dailyDiamonds']+r['memoryConverted']:errors.append(('diamonds ledger',key,r['seed']))
  if r['memoryEarned']!=r['memoryBattle']+r['memoryEvent']:errors.append(('memory ledger',key,r['seed']))
  if r['camp']=='empty' and r['memoryConverted']!=0:errors.append(('unmaxed exchange',key,r['seed']))
 else:
  if r['goldLiquidation']!=r['walletDelta']+r['retainedAssets']-r['repairReserve']:errors.append(('liquidation',key,r['seed']))
  if r['gold']!=r['goldLiquidation']+r['keyRetainedCapital']-r['keyRetainedCapitalSale']:errors.append(('capital',key,r['seed']))
summary=[]
for key,rs in sorted(groups.items()):
 if len({r['seed'] for r in rs})!=len(rs):errors.append(('duplicate seeds',key))
 if len(sys.argv)>2 and len(rs)!=int(sys.argv[2]):errors.append(('sample count',key,len(rs)))
 d=dict(zip(['profile','mode','risk','camp','attempt'],key));d['n']=len(rs);w=[r for r in rs if r['success']];d['completed']=len(w)
 numeric=['gold','goldLiquidation','goldDirect','relicSell','relicCount','floors','dailyDiamonds','memoryEarned','memoryBattle','memoryEvent','memoryConverted','diamonds','secondsFast','secondsDeliberate','xpAwardedPerCharacter','xpAppliedTotal','capital','keyPurchaseCost','keyConsumedCost','keyRetainedCapital','salvageGold','salvageItems','suppliesUsed','fullRooms','deposits','retainedAssets','repairReserve']
 for field in numeric:
  if field in rs[0]:d[field]=st.mean(r[field] for r in rs)
 for field in ['gold','diamonds','dailyDiamonds','memoryEarned']:
  if field in rs[0]:d['completeMean_'+field]=st.mean(r[field] for r in w) if w else None
 d['goldRateFast']=d['gold']*60/d['secondsFast'];d['goldRateDeliberate']=d['gold']*60/d['secondsDeliberate']
 if d['mode']=='abyss':
  d['diamondRateFast']=d['diamonds']*60/d['secondsFast'];d['repeatMemoryRateFast']=d['memoryEarned']*60/d['secondsFast']
  d['raidReferenceRisk']=rs[0]['raidReferenceRisk']
 summary.append(d)
out=p.with_name(p.stem+'-summary.json');out.write_text(json.dumps({'source':str(p),'groups':summary,'errors':errors},ensure_ascii=False,indent=2))
print('profile mode risk camp attempt complete/n meanGold fullGold floors dayDiam memory converted fullDiam gold/min')
for d in summary:print(d['profile'],d['mode'],d['risk'],d['camp'],d['attempt'],str(d['completed'])+'/'+str(d['n']),round(d['gold']),round(d['completeMean_gold'] or 0),round(d.get('floors',0),1),round(d.get('dailyDiamonds',0)),round(d.get('memoryEarned',0)),round(d.get('memoryConverted',0)),round(d.get('completeMean_diamonds') or 0),round(d['goldRateFast']))
print('Errors:',errors)
raise SystemExit(bool(errors))
