"""Independent parcel geometry, cash-ledger and group audit for v2.4.1 simulations."""
import collections, copy, gzip, hashlib, json, pathlib, random, statistics as st, sys
input_path=pathlib.Path(sys.argv[1]);p=input_path.with_suffix('') if input_path.suffix=='.gz' else input_path;raw_data=gzip.decompress(input_path.read_bytes()) if input_path.suffix=='.gz' else input_path.read_bytes();j=json.loads(raw_data); errors=list(j['errors']); groups=collections.defaultdict(list); definitions=json.loads(pathlib.Path('data/extraction.json').read_text())['items']
def exact_pack_value(candidates,width,height):
 states={0:0};placements={}
 for item in candidates:
  w,h=item['width'],item['height'];shape=tuple(sorted((w,h)))
  if shape not in placements:
   bits=set()
   for w,h in {(w,h),(h,w)}:
    for y in range(height+1-h):
     for x in range(width+1-w):bits.add(sum(1<<((y+dy)*width+x+dx) for dy in range(h) for dx in range(w)))
   placements[shape]=bits
  previous=states.copy()
  for mask,value in previous.items():
   for bits in placements[shape]:
    if mask&bits:continue
    combined=mask|bits;amount=value+item['value']
    if amount>states.get(combined,-1):states[combined]=amount
 return max(states.values())
def area_upper_bound(candidates,width,height):
 capacity=width*height;values=[0]*(capacity+1)
 for item in candidates:
  w,h=item['width'],item['height']
  if not ((w<=width and h<=height) or (h<=width and w<=height)):continue
  size=w*h
  for cells in range(capacity,size-1,-1):values[cells]=max(values[cells],values[cells-size]+item['value'])
 return max(values)
def can_help(d,snapshot):
 if d.get('repair',0)>0 and snapshot['armor']<1:return True
 for unit in snapshot['party']:
  if unit['hp']<=0:
   if d.get('revive',0)>0:return True
   continue
  if int(unit['maxHp']*d.get('heal',0))>0 and unit['hp']<unit['maxHp']:return True
  if int(d.get('energy',0))>0 and unit['energy']<100:return True
  if int(d.get('cooldown',0))>0 and any(v>0 for v in unit['cooldowns'].values()):return True
 return False
def usage_priority(item):
 d=definitions[item['itemId']]
 return 0 if d.get('revive',0)>0 else 1 if d.get('heal',0)>0 else 2 if d.get('energy',0)>0 else 3 if d.get('cooldown',0)>0 else 4 if d.get('repair',0)>0 else 5
def apply_consumable(d,snapshot):
 if d.get('repair',0)>0:snapshot['armor']=min(1,snapshot['armor']+d['repair'])
 for u in snapshot['party']:
  if u['hp']<=0:
   if d.get('revive',0)>0:u['hp']=max(1,int(u['maxHp']*d['revive']))
   else:continue
  else:u['hp']=min(u['maxHp'],u['hp']+int(u['maxHp']*d.get('heal',0)))
  u['energy']=min(100,u['energy']+int(d.get('energy',0)))
  u['cooldowns']={key:max(0,int(value)-int(d.get('cooldown',0))) for key,value in u['cooldowns'].items()}
def err(test, label, r):
 if not test: errors.append((label,r.get('profile'),r.get('risk'),r.get('seed')))
for r in j['rows']:
 err(r['maxBlessingCopies']==max(r['blessingPeakCounts'].values(),default=0),'observed blessing copy count',r)
 err(r['peakBlessingsTotal']>=r['maxBlessingCopies'],'observed blessing total count',r)
 key=(r['profile'],r['mode'],r['risk'],r.get('camp',''),r.get('attempt',''),r.get('supplyPolicy','shared'));groups[key].append(r)
 if r['mode']=='abyss':
  err(r['goldDirect']==0,'abyss direct gold',r)
  err(r['diamonds']==r['dailyDiamonds']+r['memoryConverted'],'diamond ledger',r)
  err(r['memoryEarned']==r['memoryBattle']+r['memoryEvent'],'memory ledger',r)
  err(r['camp']!='empty' or r['memoryConverted']==0,'unmaxed exchange',r)
  err(r['shopVisits']==len(r['shopHistory']),'shop visit count',r)
  spend=0;purchases=0
  for shop in r['shopHistory']:
   stock={x['id']:x for x in shop['stock']};blessings=[x for x in shop['stock'] if x['kind']=='blessing']
   err(len(stock)==5 and len(blessings)==3 and {'heal','energy'}.issubset(stock),'three blessings plus two supplies',r)
   err(len({x['rewardId'] for x in blessings})==3,'unique shop blessing stock',r)
   for x in shop['stock']:
    expected={'heal':70,'energy':60}.get(x['kind'],{'white':110,'blue':170,'gold':280}.get(x['rarity']))
    err(x['cost']==expected,'exact doubled shop price',r)
   seen=set();coins=shop['currencyBefore']
   for purchase in shop['purchases']:
    err(purchase['id'] in stock and purchase['id'] not in seen,'unique valid shop purchase',r);seen.add(purchase['id'])
    err(purchase['cost']==stock[purchase['id']]['cost'] and purchase['currencyBefore']==coins,'shop offered and paid price',r)
    coins-=purchase['cost'];err(coins>=0 and coins==purchase['currencyAfter'],'actual temporary currency debit',r);spend+=purchase['cost'];purchases+=1
   err(coins==shop['currencyAfter'],'shop end currency ledger',r)
  err(spend==r['shopSpend'] and purchases==r['shopPurchases'],'shop total spending',r)

 else:
  err(r['realizedAssetGold']==r['retainedAssets'],'actual asset sales',r)
  err(r['walletDelta']==r['walletDeltaBeforeSale']+r['realizedAssetGold'],'wallet ledger',r)
  err(r['goldLiquidation']==r['walletDelta']-r['repairReserve'],'liquidation ledger',r)
  err(r['gold']==r['goldLiquidation']+r['keyRetainedCapital']-r['keyRetainedCapitalSale'],'operating capital adjustment',r)
  err(r['parcelSoldValue']==r['parcelValue'],'parcel realization',r)
  err(r['guardVictories']<=r['guardBattles']<=r['guardServiceVisits'],'guard count',r)
  err(r['guardBattles']<=r['battles'],'battle classification',r)
  err(len(r['retainedUIDs'])==len(set(r['retainedUIDs'])),'duplicate retained UID',r)
  err(r['suppliesUsed']==r['manualSuppliesUsed']+r['autoSuppliesUsed'],'manual/automatic use accounting',r)
  err(r['supplyPolicy']!='default_unlocked' or r['lockActions']==0,'default policy has zero locks',r)
  auto_count=0;returned_supply_count=0
  for h in r['autoUseHistory']:
   state=copy.deepcopy(h['before']);expected_used=[];expected_returned=[]
   for item in sorted(h['removed'],key=usage_priority):
    d=definitions[item['itemId']]
    if d['kind']=='consumable' and not item.get('exchangeLocked',False) and can_help(d,state):
     expected_used.append(item['uid']);apply_consumable(d,state)
    else:expected_returned.append(item['uid'])
   err(expected_used==h['usedUIDs'],'independent effective automatic usage',r)
   err(expected_returned==h['returnedUIDs'],'independent automatic returned items',r)
   err(expected_used==[i['uid'] for i in h['previewWillUse']],'preview/commit used agreement',r)
   err(state['party']==h['after']['party'] and abs(state['armor']-h['after']['armor'])<1e-8,'automatic resource effect ledger',r)
   err(not set(h['usedUIDs']).intersection(h['bagAfterUIDs']+h['containerAfterUIDs']),'used UID removed once',r)
   err(set(h['returnedUIDs']).issubset(h['containerAfterUIDs']),'unused returned to actual container',r)
   auto_count+=len(h['usedUIDs']);returned_supply_count+=sum(definitions[i['itemId']]['kind']=='consumable' for i in h['returned'])
  err(auto_count==r['autoSuppliesUsed'],'automatic use count',r)
  err(returned_supply_count==r['autoUnusedSuppliesReturned'],'returned consumable count',r)
  seen=set(); sources=set()
  for packet in r['parcelHistory']:
   occupied=set(); total=0
   width,height=packet['width'],packet['height']
   upper=area_upper_bound(packet.get('candidates',[]),width,height);packet['independentAreaUpperBound']=upper
   err(packet['value']<=upper,'parcel upper value bound',r)
   if packet.get('optimal'):err(packet['value']==upper,'optimal witness equals independent area bound',r)
   err((width,height)==((5,5) if packet['phase']=='boss_exit' else (3,4)),'source-sized dimensions',r)
   err(packet['value']>=max((i['value'] for i in packet.get('candidates',[]) if (i['width']<=width and i['height']<=height) or (i['height']<=width and i['width']<=height)),default=0),'parcel at least best feasible single item',r)
   # Each opportunity is an actual room visit; current policy visits each type once per act at most.
   for item in packet['items']:
    uid=item['uid'];err(uid not in packet.get('reservedUIDs',[]),'reserved supply excluded from manual parcel',r);err(uid not in seen,'duplicate mailed UID',r);seen.add(uid)
    cells={(x,y) for x in range(item['x'],item['x']+item['width']) for y in range(item['y'],item['y']+item['height'])}
    err(all(0<=x<width and 0<=y<height for x,y in cells),'parcel source-sized bounds',r)
    err(not occupied.intersection(cells),'parcel overlap',r);occupied.update(cells);total+=item['value']
   err(len(occupied)==packet['cells']<=width*height,'parcel occupied cells',r)
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
 d=dict(zip(['profile','mode','risk','camp','attempt','supplyPolicy'],key));d['n']=len(rs);wins=[r for r in rs if r['success']];dead=[r for r in rs if not r['success']];d['completed']=len(wins);d['maxObservedBlessingCopies']=max(r['maxBlessingCopies'] for r in rs);d['runsAboveThreeBlessingCopies']=sum(r['maxBlessingCopies']>3 for r in rs)
 fields=['maxBlessingCopies','peakBlessingsTotal','shopVisits','shopSpend','shopPurchases','gold','goldLiquidation','goldDirect','relicSell','relicCount','floors','dailyDiamonds','memoryEarned','memoryBattle','memoryEvent','memoryConverted','diamonds','secondsFast','secondsDeliberate','xpAwardedPerCharacter','xpAppliedTotal','capital','keyPurchaseCost','keyConsumedCost','keyRetainedCapital','keyRetainedCapitalSale','suppliesUsed','manualSuppliesUsed','autoSuppliesUsed','autoSuppliesValue','autoUnusedSuppliesReturned','lockActions','fullRooms','deposits','retainedAssets','realizedAssetGold','repairReserve','battles','guardBattles','guardVictories','guardServiceVisits','guardXP','guardSteps','parcelCount','parcelCells','parcelItems','parcelValue','parcelFees','parcelSoldValue','walletDeltaBeforeSale','walletDelta','saleActions','searches','choices']
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
  d['parcelOptimalFraction']=sum(bool(h.get('optimal',False)) for h in packets)/len(packets) if packets else 0
  d['parcelValueToAreaBound']=st.mean(h['value']/max(1,h['independentAreaUpperBound']) for h in packets) if packets else 0
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
 for raid in [r for r in summary if r['mode']=='extraction' and r['profile']==d['profile'] and r['risk']==d['raidReferenceRisk']]:
  value=raid['completeMean_gold'];daily=d['completeMean_dailyDiamonds'];total=d['completeMean_diamonds']
  comparison={'profile':d['profile'],'supplyPolicy':raid['supplyPolicy'],'abyssRisk':d['risk'],'raidRisk':raid['risk'],'raidCompletions':raid['completed'],'raidFullGold':value,'abyssDaily':daily,'abyssTotal':total,'dailyRatio':daily/(value*.1) if value and daily else None,'totalRatio':total/(value*.1) if value and total else None}
  if value and raid.get('completeMeanGoldBootstrap95'):
   low,high=raid['completeMeanGoldBootstrap95'];comparison['fullGoldBootstrap95']=[low,high];comparison['totalRatioBootstrap95']=[total/(high*.1),total/(low*.1)]
  loot=raid.get('completeMeanRetainedLoot')
  if value and loot:
   comparison['retainedLootFullMean']=loot
  comparisons.append(comparison)
paired=[]
raid_groups=collections.defaultdict(dict)
for r in j['rows']:
 if r['mode']=='extraction':raid_groups[(r['profile'],r['risk'])].setdefault(r['supplyPolicy'],{})[r['seed']]=r
for (profile,risk),policies in sorted(raid_groups.items()):
 if set(policies)!={'reserve_locked','default_unlocked'}:continue
 reserve=policies['reserve_locked'];default=policies['default_unlocked'];seeds=sorted(set(reserve)&set(default));assert set(reserve)==set(default),(profile,risk,'unpaired seeds')
 deltas=[default[k]['gold']-reserve[k]['gold'] for k in seeds];rng=random.Random(20261101);boot=sorted(sum(rng.choices(deltas,k=len(deltas)))/len(deltas) for _ in range(10000))
 pair={'profile':profile,'risk':risk,'n':len(seeds),'defaultMinusReserveGold':st.mean(deltas),'defaultMinusReserveGoldBootstrap95':[boot[250],boot[9750]],'bothCleared':sum(default[k]['success'] and reserve[k]['success'] for k in seeds),'onlyReserveCleared':sum(reserve[k]['success'] and not default[k]['success'] for k in seeds),'onlyDefaultCleared':sum(default[k]['success'] and not reserve[k]['success'] for k in seeds),'bothFailed':sum(not default[k]['success'] and not reserve[k]['success'] for k in seeds),'defaultMinusReserveAutoUse':st.mean(default[k]['autoSuppliesUsed']-reserve[k]['autoSuppliesUsed'] for k in seeds),'defaultMinusReserveManualUse':st.mean(default[k]['manualSuppliesUsed']-reserve[k]['manualSuppliesUsed'] for k in seeds)}
 paired.append(pair)
current_mismatches=[]
for name,expected in j['hashes'].items():
 if hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()!=expected:current_mismatches.append(name)
out=p.with_name(p.stem+'-summary.json');out.write_text(json.dumps({'source':str(input_path),'sourceUncompressedSha256':hashlib.sha256(raw_data).hexdigest(),'groups':summary,'comparisons':comparisons,'pairedPolicyComparisons':paired,'errors':errors,'currentSourceMismatches':current_mismatches},ensure_ascii=False,indent=2))
print('rows',len(j['rows']),'battles',sum(r['battles'] for r in j['rows']),'errors',len(errors),'currentSourceMismatches',current_mismatches)
for d in summary:
 if d['mode']=='extraction':print(d['profile'],d['risk'],d['supplyPolicy'],f"{d['completed']}/{d['n']}",'all',round(d['gold']),'full',round(d['completeMean_gold'] or 0),'guard',round(d['guardBattles'],2),'parcel',round(d['parcelValue']), 'cells',round(d['firstBossBeforeCells'],1),round(d['firstBossAfterCells'],1))
for c in comparisons:print(c)
if errors:print(errors[:30])
raise SystemExit(bool(errors or current_mismatches))
