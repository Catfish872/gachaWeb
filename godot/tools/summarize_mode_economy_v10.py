"""Independent parcel geometry, cash-ledger and group audit for v2.4.1 simulations."""
import collections, hashlib, json, pathlib, random, statistics as st, sys
p=pathlib.Path(sys.argv[1]); j=json.loads(p.read_text()); errors=list(j['errors']); groups=collections.defaultdict(list)
def exact_pack_value(candidates):
 states={0:0};placements={}
 for item in candidates:
  w,h=item['width'],item['height'];shape=tuple(sorted((w,h)))
  if shape not in placements:
   bits=set()
   for w,h in {(w,h),(h,w)}:
    for y in range(4-h):
     for x in range(4-w):bits.add(sum(1<<((y+dy)*3+x+dx) for dy in range(h) for dx in range(w)))
   placements[shape]=bits
  previous=states.copy()
  for mask,value in previous.items():
   for bits in placements[shape]:
    if mask&bits:continue
    combined=mask|bits;amount=value+item['value']
    if amount>states.get(combined,-1):states[combined]=amount
 return max(states.values())
def err(test, label, r):
 if not test: errors.append((label,r.get('profile'),r.get('risk'),r.get('seed')))
for r in j['rows']:
 key=(r['profile'],r['mode'],r['risk'],r.get('camp',''),r.get('attempt',''));groups[key].append(r)
 if r['mode']=='abyss':
  err(r['goldDirect']==0,'abyss direct gold',r)
  err(r['diamonds']==r['dailyDiamonds']+r['memoryConverted'],'diamond ledger',r)
  err(r['memoryEarned']==r['memoryBattle']+r['memoryEvent'],'memory ledger',r)
  err(r['camp']!='empty' or r['memoryConverted']==0,'unmaxed exchange',r)
 else:
  err(r['realizedAssetGold']==r['retainedAssets'],'actual asset sales',r)
  err(r['walletDelta']==r['walletDeltaBeforeSale']+r['realizedAssetGold'],'wallet ledger',r)
  err(r['goldLiquidation']==r['walletDelta']-r['repairReserve'],'liquidation ledger',r)
  err(r['gold']==r['goldLiquidation']+r['keyRetainedCapital']-r['keyRetainedCapitalSale'],'operating capital adjustment',r)
  err(r['parcelSoldValue']==r['parcelValue'],'parcel realization',r)
  err(r['guardVictories']<=r['guardBattles']<=r['guardServiceVisits'],'guard count',r)
  err(r['guardBattles']<=r['battles'],'battle classification',r)
  err(len(r['retainedUIDs'])==len(set(r['retainedUIDs'])),'duplicate retained UID',r)
  seen=set(); sources=set()
  for packet in r['parcelHistory']:
   occupied=set(); total=0
   if 'candidates' in packet:err(exact_pack_value(packet['candidates'])==packet['value'],'independent highest-value spatial packing',r)
   # Each opportunity is an actual room visit; current policy visits each type once per act at most.
   for item in packet['items']:
    uid=item['uid'];err(uid not in seen,'duplicate mailed UID',r);seen.add(uid)
    cells={(x,y) for x in range(item['x'],item['x']+item['width']) for y in range(item['y'],item['y']+item['height'])}
    err(all(0<=x<3 and 0<=y<3 for x,y in cells),'parcel 3x3 bounds',r)
    err(not occupied.intersection(cells),'parcel overlap',r);occupied.update(cells);total+=item['value']
   err(len(occupied)==packet['cells']<=9,'parcel occupied cells',r)
   err(packet['beforeCells']-packet['remainingCells']==packet['cells'],'parcel bag removal',r)
   err(total==packet['value'],'parcel item valuation',r)
  err(sum(h['value'] for h in r['parcelHistory'])==r['parcelValue'],'parcel sum',r)
  err(sum(h['fee'] for h in r['parcelHistory'])==r['parcelFees'],'parcel fees',r)
  err(sum(len(h['items']) for h in r['parcelHistory'])==r['parcelItems'],'parcel item count',r)
  err(len(seen)==r['parcelItems'],'parcel UID count',r)
  err(seen.issubset(set(r['retainedUIDs'])),'parcel actual retained UID',r)
summary=[]
for key,rs in sorted(groups.items()):
 if len({r['seed'] for r in rs})!=len(rs):errors.append(('duplicate seed',key))
 if len(sys.argv)>2 and len(rs)!=int(sys.argv[2]):errors.append(('sample count',key,len(rs)))
 d=dict(zip(['profile','mode','risk','camp','attempt'],key));d['n']=len(rs);wins=[r for r in rs if r['success']];dead=[r for r in rs if not r['success']];d['completed']=len(wins)
 fields=['gold','goldLiquidation','goldDirect','relicSell','relicCount','floors','dailyDiamonds','memoryEarned','memoryBattle','memoryEvent','memoryConverted','diamonds','secondsFast','secondsDeliberate','xpAwardedPerCharacter','xpAppliedTotal','capital','keyPurchaseCost','keyConsumedCost','keyRetainedCapital','keyRetainedCapitalSale','suppliesUsed','fullRooms','deposits','retainedAssets','realizedAssetGold','repairReserve','battles','guardBattles','guardVictories','guardServiceVisits','guardXP','guardSteps','parcelCount','parcelCells','parcelItems','parcelValue','parcelFees','parcelSoldValue','walletDeltaBeforeSale','walletDelta','saleActions','searches','choices']
 for f in fields:
  if f in rs[0]:d[f]=st.mean(r[f] for r in rs)
 for f in ['gold','goldLiquidation','diamonds','dailyDiamonds','memoryEarned','battles','guardBattles','parcelValue','xpAppliedTotal']:
  if f in rs[0]:
   d['completeMean_'+f]=st.mean(r[f] for r in wins) if wins else None
   d['failedMean_'+f]=st.mean(r[f] for r in dead) if dead else None
   if len(wins)>1:d['completeSE_'+f]=st.stdev(r[f] for r in wins)/len(wins)**.5
 d['goldRateFast']=d['gold']*60/d['secondsFast'];d['goldRateDeliberate']=d['gold']*60/d['secondsDeliberate']
 if d['mode']=='abyss':
  d['diamondRateFast']=d['diamonds']*60/d['secondsFast'];d['raidReferenceRisk']=rs[0]['raidReferenceRisk']
 else:
  gold_values=[r['gold'] for r in wins]
  if len(gold_values)>1:
   rng=random.Random(20261101);means=sorted(sum(rng.choices(gold_values,k=len(gold_values)))/len(gold_values) for _ in range(10000));d['completeMeanGoldBootstrap95']=[means[250],means[9750]]
  d['completeMeanRetainedLoot']=st.mean(r['retainedByKind'].get('loot',0) for r in wins) if wins else None
  d['guardServiceRate']=d['guardBattles']/d['guardServiceVisits'] if d['guardServiceVisits'] else 0
  d['guardAdditionalToOrdinaryRate']=d['guardBattles']/(d['battles']-d['guardBattles']) if d['battles']>d['guardBattles'] else 0
  packets=[h for r in rs for h in r['parcelHistory']];first=[h for h in packets if h['act']==1 and h['phase']=='boss_exit']
  d['parcelMeanCells']=st.mean(h['cells'] for h in packets) if packets else 0
  d['parcelMeanValue']=st.mean(h['value'] for h in packets) if packets else 0
  d['firstBossBeforeCells']=st.mean(h['beforeCells'] for h in first) if first else 0
  d['firstBossAfterCells']=st.mean(h['remainingCells'] for h in first) if first else 0
  bags=[r['firstFullBag'] for r in rs if r['firstFullBag']]
  d['firstFullMeanCells']=st.mean(b['cells'] for b in bags) if bags else 0
  d['firstFullWhiteGreenCells']=st.mean(sum(v.get('cells',0) for k,v in b['byRarity'].items() if int(float(k))<=1) for b in bags) if bags else 0
  d['firstFullLowRarityLootCells']=st.mean(sum(i['cells'] for i in b['items'] if i['kind']=='loot' and int(i['rarity'])<=1) for b in bags) if bags else 0
  d['firstFullLowRarityLootValue']=st.mean(sum(i['value'] for i in b['items'] if i['kind']=='loot' and int(i['rarity'])<=1) for b in bags) if bags else 0
  d['firstFullAct1Fraction']=sum(b['act']==1 for b in bags)/len(bags) if bags else 0
  d['firstFullWhiteGreenValue']=st.mean(sum(v.get('value',0) for k,v in b['byRarity'].items() if int(float(k))<=1) for b in bags) if bags else 0
  for f in ['goldLootFound','redLootFound']:d[f]=[st.mean(r[f][a] for r in rs) for a in range(3)]
 summary.append(d)
comparisons=[]
for d in summary:
 if d['mode']!='abyss' or d['camp']!='maxed' or d['attempt']!='first':continue
 raid=next(r for r in summary if r['mode']=='extraction' and r['profile']==d['profile'] and r['risk']==d['raidReferenceRisk'])
 value=raid['completeMean_gold'];daily=d['completeMean_dailyDiamonds'];total=d['completeMean_diamonds']
 comparison={'profile':d['profile'],'abyssRisk':d['risk'],'raidRisk':raid['risk'],'raidCompletions':raid['completed'],'raidFullGold':value,'abyssDaily':daily,'abyssTotal':total,'dailyRatio':daily/(value*.1) if value and daily else None,'totalRatio':total/(value*.1) if value and total else None,'dailyPer10For2p5Total':(value*.25-d['completeMean_memoryEarned'])/5 if value else None}
 if value and raid.get('completeMeanGoldBootstrap95'):
  low,high=raid['completeMeanGoldBootstrap95'];comparison['fullGoldBootstrap95']=[low,high];comparison['totalRatioBootstrap95']=[total/(high*.1),total/(low*.1)]
 loot=raid.get('completeMeanRetainedLoot')
 if value and loot:
  comparison['retainedLootFullMean']=loot;comparison['lootFactorForTotalRatio3']=max(1,1+(total/.3-value)/loot);comparison['lootFactorForTotalRatio2p5']=max(1,1+(total/.25-value)/loot)
 comparisons.append(comparison)
current_mismatches=[]
for name,expected in j['hashes'].items():
 if hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()!=expected:current_mismatches.append(name)
out=p.with_name(p.stem+'-summary.json');out.write_text(json.dumps({'source':str(p),'groups':summary,'comparisons':comparisons,'errors':errors,'currentSourceMismatches':current_mismatches},ensure_ascii=False,indent=2))
print('rows',len(j['rows']),'battles',sum(r['battles'] for r in j['rows']),'errors',len(errors),'currentSourceMismatches',current_mismatches)
for d in summary:
 if d['mode']=='extraction':print(d['profile'],d['risk'],f"{d['completed']}/{d['n']}",'all',round(d['gold']),'full',round(d['completeMean_gold'] or 0),'guard',round(d['guardBattles'],2),'parcel',round(d['parcelValue']), 'cells',round(d['firstBossBeforeCells'],1),round(d['firstBossAfterCells'],1))
for c in comparisons:print(c)
if errors:print(errors[:30])
raise SystemExit(bool(errors))
