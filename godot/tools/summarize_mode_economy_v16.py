"""Independent parcel geometry, cash-ledger and group audit for v2.5.0 simulations."""
import collections, copy, gzip, hashlib, json, math, pathlib, random, statistics as st, sys
daily_claims={};daily_rates=json.loads(pathlib.Path('data/rogue_v2.json').read_text())['dailyDiamondsPer10']
input_path=pathlib.Path(sys.argv[1]);p=input_path.with_suffix('') if input_path.suffix=='.gz' else input_path;raw_data=gzip.decompress(input_path.read_bytes()) if input_path.suffix=='.gz' else input_path.read_bytes();j=json.loads(raw_data); errors=list(j['errors']); groups=collections.defaultdict(list); definitions=json.loads(pathlib.Path('data/extraction.json').read_text())['items'];catalog=json.loads(pathlib.Path('data/catalog.json').read_text())
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
def audit_relic(item,context):
 slot=item['slotId'];rarity=int(item['rarity']);level=int(item['level']);subs=item['subStats'];main=item['mainStat']
 if slot not in catalog['RelicMainStatPool'] or main not in catalog['RelicMainStatPool'][slot]:errors.append(('legal relic main pool',context))
 definitions={d['stat']:d for d in catalog['RelicSubStatPool']}
 if len(subs)!=int(catalog['RelicRarityConfig'][str(rarity)]['initSubStats']) or len({v['stat'] for v in subs})!=len(subs) or any(v['stat']==main['stat'] for v in subs):errors.append(('legal distinct relic substats',context))
 def rounded(value,stat):return math.floor(value+.5) if stat in ['spd','hp_flat','atk_flat','def_flat','energy_rate_flat'] else math.floor(value*1000+.5)/1000
 for sub in subs:
  definition=definitions.get(sub['stat'])
  if definition is None:errors.append(('legal relic substat pool',context));continue
  low,high=definition['range'];low=rounded(low,sub['stat']);high=rounded(high,sub['stat'])+(level//4)*rounded(definition['range'][1]*.8,sub['stat'])
  if not low-1e-8<=sub['value']<=high+1e-8:errors.append(('legal generated/reinforced substat bound',context))
fixture_matches=0
for fixture_key,fixture in j['fixtures'].items():
 for actor in fixture['actors']:
  relics=actor['relics'];counts=collections.Counter(r.get('setId','') for r in relics if r.get('setId',''));expected=[]
  if len({r['uid'] for r in relics})!=len(relics) or len({r['slotId'] for r in relics})!=len(relics):errors.append(('unique fixture slots/UIDs',fixture_key,actor['charId']))
  for item in relics:
   audit_relic(item,(fixture_key,actor['charId']))
   if item['rarity']!=5 or item['level']!=25:errors.append(('legal max fixture rarity/level',fixture_key))
  if fixture['kind']=='legacy_no_sets' and counts:errors.append(('legacy fixture has accidental random set',fixture_key))
  if fixture['kind']=='theme_four_piece':
   wanted=catalog['CharacterData'][actor['charId']]['relicObjective']['recommendedSets'][0]['setId']
   if counts!={wanted:4} or len(relics)!=5:errors.append(('theme exactly four pieces plus one legacy offpiece',fixture_key,actor['charId']))
  for set_id,definition in catalog['RelicSets'].items():
   for bonus in definition['bonuses']:
    if counts[set_id]>=bonus['pieces']:
     for effect in bonus['effects']:
      if effect['type']!='stat':expected.append(dict(effect,setId=set_id,pieces=bonus['pieces']))
  if actor['ownerEffects']!=expected or fixture['ownerEffects'][actor['charId']]!=expected:errors.append(('catalog-scoped personal effects',fixture_key,actor['charId']))
  permanent={key:0 for key in actor['statBonuses']}
  for set_id,definition in catalog['RelicSets'].items():
   for bonus in definition['bonuses']:
    if counts[set_id]>=bonus['pieces']:
     for effect in bonus['effects']:
      if effect['type']=='stat':permanent[effect['stat']]+=effect['value']
  if any(abs(permanent[key]-actor['statBonuses'][key])>1e-8 for key in permanent):errors.append(('set permanent stats counted once',fixture_key,actor['charId']))
  character=next(a for a in fixture['attributes'] if a['id']==actor['charId']);level=character['level'];growth=actor['growthSnapshot'];definition=catalog['CharacterData'][actor['charId']];base=definition['baseStats'];rate=definition['growthRate'];mult=1.1**(level-1);rb=dict(growth['relics'])
  rolled={key:0 for key in rb}
  for item in relics:
   main=item['mainStat'];rolled[main['stat']]+=main['base']+main['perLevel']*item['level']
   for sub in item['subStats']:rolled[sub['stat']]+=sub['value']
  if any(abs(rb[key]-rolled[key])>1e-7 for key in rb):errors.append(('old legal relic main/sub attribute sums unchanged',fixture_key,actor['charId']))
  for key,value in permanent.items():rb[key]=rb.get(key,0)+value
  expected_stats={}
  for stat in ['hp','atk','def']:
   start=math.floor(math.floor(base[stat]+rate[stat]*(level-1))*mult);percent=growth['constellation'][stat+'Percent']+(growth['awakening']*.05 if stat=='hp' else 0);value=(start*(1+percent)+rb[stat+'_flat'])*(1+rb[stat+'_pct']);minimum=0 if stat=='def' else 1;integer=max(minimum,math.floor(value));allowed={integer}
   if abs(value-round(value))<1e-7:allowed={max(minimum,round(value)-1),max(minimum,round(value))}
   if actor['stats']['maxHp' if stat=='hp' else stat] not in allowed:errors.append(('legacy attribute formula plus exactly one personal set bonus',fixture_key,actor['charId'],stat))
  expected_stats={'spd':(math.floor(base['spd']*mult)+rb['spd'])*(1+rb.get('spd_pct',0)),'cri':min(1,base['cri']*mult+rb['cri_rate']),'criDmg':base['criDmg']*mult+rb['cri_dmg'],'energyRate':rb['energy_rate']}
  if any(abs(actor['stats'][key]-value)>1e-7 for key,value in expected_stats.items()):errors.append(('speed crit and old level crit-damage formulas retained',fixture_key,actor['charId']))

 if fixture['kind']=='theme_four_piece':
  legacy=j['fixtures'].get(f"{fixture['legacyProfile']}:{fixture['seed']}")
  if legacy:
   if fixture['attributes']!=legacy['attributes'] or fixture['rngAfterGear']!=legacy['rngAfterGear']:errors.append(('theme/legacy identical legal attribute rolls and gear RNG',fixture_key))
   fixture_matches+=1
for r in j['rows']:
 fixture=j['fixtures'][r['fixtureKey']]
 err(fixture['profile']==r['profile'] and fixture['seed']==r['seed'],'row real fixture identity',r)
 err(r['observedOwnerEffects']==fixture['ownerEffects'],'observed actor-owned battle effects',r)
 err(r['ownerEffectChecks']==2*r['battles']*len(fixture['actors']),'model and Battle owner-effect snapshots each battle',r)
 err(set(r['electrify'])=={'ally','boss','enemy'},'complete electrify observer categories',r)
 for target,v in r['electrify'].items():
  err(target in ['ally','boss','enemy'] and 0<=v['skips']<=v['opportunities'],'actual electrify outcome counts',r)
  err(abs(v['expectedSkips']-.35*v['opportunities'])<1e-7,'current default 35 percent effective electrify chance',r)
 err(r['maxBlessingCopies']==max(r['blessingPeakCounts'].values(),default=0),'observed blessing copy count',r)
 err(r['peakBlessingsTotal']>=r['maxBlessingCopies'],'observed blessing total count',r)
 key=(r['profile'],r['mode'],r['risk'],r.get('camp',''),r.get('attempt',''),r.get('supplyPolicy','shared'),r.get('series','main'));groups[key].append(r)
 if r['mode']=='abyss':
  r['relicFourStar']=sum(d['item']['rarity']==4 for d in r['relicDrops']);r['relicFiveStar']=sum(d['item']['rarity']==5 for d in r['relicDrops'])
  drops=r['relicDrops'];plans=r['relicPlanHistory'];by_floor={d['floor']:d for d in drops};uids={d['item']['uid'] for d in drops}
  err(len(drops)==len(by_floor)==len(uids)==r['relicCount'],'unique actual new relic drops',r)
  err(len(plans)==r['battles']==r['targetSetLockedChecks'],'locked target on every signed battle plan',r)
  for plan in plans:
   f=plan['floor'];milestone=f%5==0;rarity=plan['rarity'];has_drop=rarity>0
   err(plan['targetSetId']==r['targetRelicSetId'],'signed target remains fixed',r)
   if milestone:err(rarity==(5 if f%10==0 else 4),'original five/ten floor guarantees retained',r)
   elif r['risk']==0:err(not has_drop,'rank zero no ordinary extra drops',r)
   else:err(rarity in [0,4,5],'extra drop only legal four or five star',r)
   if has_drop:err(plan['setId']==r['targetRelicSetId'] and bool(plan['plannedUID']),'signed set and complete item UID',r)
   err((f in by_floor)==(plan['victory'] and has_drop),'only victory realizes signed reward',r)
   if f in by_floor:
    drop=by_floor[f];item=drop['item'];audit_relic(item,(r['profile'],r['seed'],f))
    err(item['uid']==plan['plannedUID'] and item['slotId']==plan['slotId'] and item['rarity']==rarity and item.get('setId')==r['targetRelicSetId'],'actual drop is signed target item',r)
    err(item['level']==0 and item.get('equippedBy') is None and drop['sellValue']=={4:120,5:480}[rarity],'fresh relic actual sale value',r)
  err(r['relicExtraCount']==sum(not d['milestone'] for d in drops) and r['relicMilestoneCount']==sum(d['milestone'] for d in drops),'extra versus milestone count',r)
  err(r['extraRelicSell']==sum(d['sellValue'] for d in drops if not d['milestone']) and r['milestoneRelicSell']==sum(d['sellValue'] for d in drops if d['milestone']),'extra versus milestone realized gold',r)
  sold=[]
  for sale in r['relicSales']:
   sold+=sale['uids'];err(sale['walletAfter']-sale['walletBefore']==sale['gold'] and sale['count']==len(sale['uids']),'actual relic sale wallet/UID count',r)
  err(set(sold)==uids and len(sold)==len(uids) and sum(v['gold'] for v in r['relicSales'])==r['relicSell']==sum(d['sellValue'] for d in drops),'all and only new relics actually sold once',r)
  err(r['gold']==r['goldDirect']+r['relicSell'],'abyss direct versus actual relic liquidation',r)
  err(r['goldDirect']==0,'abyss direct gold',r)
  daily_key=(r.get('series','main'),r['profile'],r['risk'],r.get('raidReferenceRisk'),r['seed'],r['camp'])
  paid=daily_claims.setdefault(daily_key,{})
  rate=daily_rates[r['risk']]
  expected_awards=[]
  for plan in plans:
   if plan['victory'] and plan['floor']%10==0:
    floor_number=plan['floor'];expected_awards.append({'floor':floor_number,'amount':max(0,rate-paid.get(floor_number,0))});paid[floor_number]=max(rate,paid.get(floor_number,0))
  err(r['dailyAwards']==expected_awards and r['dailyDiamonds']==sum(a['amount'] for a in expected_awards),'actual first/repeat daily entitlement and floor ledger',r)
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
  err(len(r['encounterHistory'])==r['battles'],'actual encounter record count',r)
  for target in ['ally','boss','enemy']:
   for field in ['opportunities','skips','expectedSkips']:
    err(abs(r['electrify'][target][field]-sum(b['electrify'][target][field] for b in r['encounterHistory']))<1e-7,'per-battle electrify totals',r)
  for battle in r['encounterHistory']:
   expected_depth=1 if battle['kind']=='boss' else 1+.02*(max(1,min(4,battle['depthTier']))-1)
   expected_final=1.15 if battle['kind']=='boss' and battle['act']==3 else 1
   err(1<=battle['depthTier']<=4 and abs(battle['depthStatMultiplier']-expected_depth)<1e-9,'fixed depth tier multiplier',r)
   err(abs(battle['finalBossStatMultiplier']-expected_final)<1e-9,'only final boss extra 15 percent',r)
   err(battle['result'] in ['victory','defeat'] and battle['steps']<3000,'encounter terminal within safety bound',r)
   for unit in battle['enemies']:
    definition=catalog['EnemyData'][unit['id']];base=definition['baseStats'];mods=battle['scaleMult'];is_final=battle['kind']=='boss' and battle['act']==3 and definition.get('isBoss',False);factor=1.15 if is_final else 1
    stats_ok=True
    # JSON serializes the multiplier, not its full in-memory binary representation.
    # At an integer truncation boundary only, the original product can lie on either side.
    for key,basekey,modkey,minimum in [('maxHp','hp','hpMod',1),('atk','atk','atkMod',1),('def','def','defMod',0)]:
     product=base[basekey]*mods[modkey]*factor;nearest=round(product);allowed={max(minimum,int(product))}
     if abs(product-nearest)<1e-7:allowed={max(minimum,nearest-1),max(minimum,nearest)}
     stats_ok=stats_ok and unit['stats'][key] in allowed
    speed=min(138 if is_final else 120,max(1,base['spd']*mods['spdMod']*factor));stats_ok=stats_ok and abs(unit['stats']['spd']-speed)<1e-7
    err(stats_ok,'actual four stats: only final boss body +15 percent; guards unchanged',r)

  err(len(r['usedSupplyUIDs'])==r['suppliesUsed'] and len(set(r['usedSupplyUIDs']))==len(r['usedSupplyUIDs']),'unique actual consumed supply UIDs',r)
  err(len(r['keyPurchaseLines'])==r['keyBought'] and sum(k['price'] for k in r['keyPurchaseLines'])==r['keyPurchaseCost'],'actual key purchase debit',r)
  err(all(k['price']==500 for k in r['keyPurchaseLines']),'keys each cost 500',r)
  err(r['keysUsed']==len(r['keyVaultHistory']),'key vault open count',r)
  err(len({v['keyUID'] for v in r['keyVaultHistory']})==len(r['keyVaultHistory']),'key UID consumed at most once',r)
  vault_uids=set()
  for visit in r['keyVaultHistory']:
   offered={i['uid']:i for i in visit['items']};realized=set(offered).intersection(r['retainedUIDs']);used=set(offered).intersection(r['usedSupplyUIDs'])
   err(len(offered)==len(visit['items']) and not vault_uids.intersection(offered),'key vault distinct original items',r);vault_uids.update(offered)
   err(visit['keyBuyPrice']==500 and visit['purchasedKeyCost']==next((k['price'] for k in r['keyPurchaseLines'] if k['uid']==visit['keyUID']),0),'key consumed replacement and actual costs',r)
   err(visit['foundValue']==sum(i['value'] for i in visit['items']) and visit['foundLootValue']==sum(i['value'] for i in visit['items'] if i['kind']=='loot'),'key vault generated value',r)
   err(set(visit['realizedUIDs'])==realized and visit['realizedValue']==sum(offered[u]['value'] for u in realized),'key vault actually retained and sold original UIDs',r)
   err(visit['realizedLootValue']==sum(offered[u]['value'] for u in realized if offered[u]['kind']=='loot'),'key vault actual pure loot sales',r)
   err(set(visit['usedConsumableUIDs'])==used and not used.intersection(realized),'key vault used items not monetized',r)
   err(visit['realizedMinusReplacementCost']==visit['realizedValue']-500 and visit['realizedMinusActualPurchaseCost']==visit['realizedValue']-visit['purchasedKeyCost'],'key vault cost deduction',r)
   err(visit['coversReplacementCost']==(visit['realizedValue']>=500),'key vault cash payback',r)
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
   err((width,height)==((6,6) if packet['phase']=='boss_exit' else (5,5)),'source-sized dimensions',r)
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
 expected_samples=int(j.get('dropEfficiencySamples',j.get('sampleCount',32))) if key[-1]=='drop_efficiency' else (int(sys.argv[2]) if len(sys.argv)>2 else len(rs))
 if len(rs)!=expected_samples:errors.append(('sample count',key,len(rs),expected_samples))
 d=dict(zip(['profile','mode','risk','camp','attempt','supplyPolicy','series'],key));d['n']=len(rs);wins=[r for r in rs if r['success']];dead=[r for r in rs if not r['success']];d['completed']=len(wins);d['maxObservedBlessingCopies']=max(r['maxBlessingCopies'] for r in rs);d['runsAboveThreeBlessingCopies']=sum(r['maxBlessingCopies']>3 for r in rs)
 fields=['maxBlessingCopies','peakBlessingsTotal','shopVisits','shopSpend','shopPurchases','gold','goldLiquidation','goldDirect','relicSell','relicCount','relicFourStar','relicFiveStar','relicExtraCount','relicMilestoneCount','extraRelicSell','milestoneRelicSell','ownerEffectChecks','floors','dailyDiamonds','memoryEarned','memoryBattle','memoryEvent','memoryConverted','diamonds','secondsFast','secondsDeliberate','xpAwardedPerCharacter','xpAppliedTotal','capital','keyPurchaseCost','keyConsumedCost','keyRetainedCapital','keyRetainedCapitalSale','suppliesUsed','manualSuppliesUsed','autoSuppliesUsed','autoSuppliesValue','autoUnusedSuppliesReturned','lockActions','fullRooms','deposits','retainedAssets','realizedAssetGold','repairReserve','battles','guardBattles','guardVictories','guardServiceVisits','guardXP','guardSteps','parcelCount','parcelCells','parcelItems','parcelValue','parcelFees','parcelSoldValue','walletDeltaBeforeSale','walletDelta','saleActions','searches','choices']
 for f in fields:
  if f in rs[0]:d[f]=st.mean(r[f] for r in rs)
 for f in ['gold','goldLiquidation','relicCount','relicFourStar','relicFiveStar','relicExtraCount','relicSell','extraRelicSell','diamonds','dailyDiamonds','memoryEarned','battles','guardBattles','parcelValue','xpAppliedTotal']:
  if f in rs[0]:
   d['completeMean_'+f]=st.mean(r[f] for r in wins) if wins else None
   d['failedMean_'+f]=st.mean(r[f] for r in dead) if dead else None
   if len(wins)>1:d['completeSE_'+f]=st.stdev(r[f] for r in wins)/len(wins)**.5
 d['goldRateFast']=d['gold']*60/d['secondsFast'];d['goldRateDeliberate']=d['gold']*60/d['secondsDeliberate']
 if d['mode']=='abyss':
  d['relicRateFast']=d['relicCount']*60/d['secondsFast'];d['relicRateDeliberate']=d['relicCount']*60/d['secondsDeliberate'];d['diamondRateFast']=d['diamonds']*60/d['secondsFast'];d['raidReferenceRisk']=rs[0]['raidReferenceRisk']
 else:
  vaults=[v for r in rs for v in r['keyVaultHistory']];failed_vaults=[v for r in dead for v in r['keyVaultHistory']]
  d['keyVaultCount']=len(vaults);d['keyVaultVisits']=len(vaults)/len(rs)
  for f in ['foundValue','foundLootValue','realizedValue','realizedLootValue','realizedMinusReplacementCost','realizedMinusActualPurchaseCost','purchasedKeyCost']:
   d['keyVaultMean_'+f]=st.mean(v[f] for v in vaults) if vaults else None
  d['keyVaultCashPaybackRate']=sum(v['coversReplacementCost'] for v in vaults)/len(vaults) if vaults else None
  d['failedKeyVaultCount']=len(failed_vaults);d['failedKeyVaultMeanRealizedValue']=st.mean(v['realizedValue'] for v in failed_vaults) if failed_vaults else None
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
  d['firstFullObservedCount']=len(bags);d['firstFullNeverCount']=len(rs)-len(bags)
  d['firstFullAct1Fraction']=sum(b['act']==1 for b in bags)/len(rs)
  d['firstFullAct1ConditionalFraction']=sum(b['act']==1 for b in bags)/len(bags) if bags else 0
  d['firstFullWhiteGreenValue']=st.mean(sum(v.get('value',0) for k,v in b['byRarity'].items() if int(float(k))<=1) for b in bags) if bags else 0
  for f in ['goldLootFound','redLootFound']:d[f]=[st.mean(r[f][a] for r in rs) for a in range(3)]
 summary.append(d)
comparisons=[]
for d in summary:
 if d['mode']!='abyss' or d['camp']!='maxed' or d['attempt']!='first' or d['series']!='main':continue
 for raid in [r for r in summary if r['mode']=='extraction' and r['profile']==d['profile'] and r['risk']==d['raidReferenceRisk']]:
  value=raid['completeMean_gold'];daily=d['completeMean_dailyDiamonds'];total=d['completeMean_diamonds']
  comparison={'profile':d['profile'],'supplyPolicy':raid['supplyPolicy'],'abyssRisk':d['risk'],'raidRisk':raid['risk'],'raidCompletions':raid['completed'],'raidFullGold':value,'abyssDaily':daily,'abyssTotal':total,'dailyRatio':daily/(value*.1) if value and daily else None,'totalRatio':total/(value*.1) if value and total else None}
  if value and raid.get('completeMeanGoldBootstrap95'):
   low,high=raid['completeMeanGoldBootstrap95'];comparison['fullGoldBootstrap95']=[low,high];comparison['dailyRatioBootstrap95']=[daily/(high*.1),daily/(low*.1)];comparison['totalRatioBootstrap95']=[total/(high*.1),total/(low*.1)]
  loot=raid.get('completeMeanRetainedLoot')
  if value and loot:
   comparison['retainedLootFullMean']=loot
  comparison.update(abyssRelicGold=d['completeMean_relicSell'],abyssExtraRelicGold=d['completeMean_extraRelicSell'],abyssRelicCount=d['completeMean_relicCount'],abyssRelicGoldRaidRatio=d['completeMean_relicSell']/value if value else None,abyssExtraRelicGoldRaidRatio=d['completeMean_extraRelicSell']/value if value else None)
  comparison.update(abyssRelicGoldRateFast=d['goldRateFast'],abyssRelicGoldRateDeliberate=d['goldRateDeliberate'],raidGoldRateFast=raid['goldRateFast'],raidGoldRateDeliberate=raid['goldRateDeliberate'],abyssRelicGoldRateShareFast=d['goldRateFast']/raid['goldRateFast'],abyssRelicGoldRateShareDeliberate=d['goldRateDeliberate']/raid['goldRateDeliberate'])
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
theme_pairs=[]
for risk in [4,5]:
 for policy in ['reserve_locked','default_unlocked']:
  legacy={r['seed']:r for r in j['rows'] if r['mode']=='extraction' and r['profile']=='limited_c6_gear25' and r['risk']==risk and r['supplyPolicy']==policy};theme={r['seed']:r for r in j['rows'] if r['mode']=='extraction' and r['profile']=='theme_limited_c6_gear25' and r['risk']==risk and r['supplyPolicy']==policy};seeds=sorted(set(legacy)&set(theme))
  if not seeds:continue
  deltas=[theme[k]['gold']-legacy[k]['gold'] for k in seeds];rng=random.Random(20261103);boot=sorted(st.mean(rng.choices(deltas,k=len(deltas))) for _ in range(10000));both=[k for k in seeds if legacy[k]['success'] and theme[k]['success']]
  theme_pairs.append({'risk':risk,'supplyPolicy':policy,'n':len(seeds),'legacyWins':sum(legacy[k]['success'] for k in seeds),'themeWins':sum(theme[k]['success'] for k in seeds),'bothCleared':len(both),'onlyLegacyCleared':sum(legacy[k]['success'] and not theme[k]['success'] for k in seeds),'onlyThemeCleared':sum(theme[k]['success'] and not legacy[k]['success'] for k in seeds),'themeMinusLegacyAllGold':st.mean(deltas),'themeMinusLegacyAllGoldBootstrap95':[boot[250],boot[9750]],'bothClearedMeanGoldDifference':st.mean(theme[k]['gold']-legacy[k]['gold'] for k in both) if both else None})
farm_rows=[r for r in j['rows'] if r.get('series')=='drop_efficiency'];farm_comparisons=[]
for rank in [1,2,3]:
 base={(r['seed'],r['attempt']):r for r in farm_rows if r['risk']==0};high={(r['seed'],r['attempt']):r for r in farm_rows if r['risk']==rank};keys=sorted(set(base)&set(high))
 if not keys:continue
 clusters=collections.defaultdict(lambda:[0,0,0,0,0,0])
 for key in keys:
  b,h=base[key],high[key];a=clusters[key[0]]
  for i,v in enumerate([b['relicCount'],h['relicCount'],b['secondsFast'],h['secondsFast'],b['secondsDeliberate'],h['secondsDeliberate']]):a[i]+=v
 def ratios(values):
  totals=[sum(v[i] for v in values) for i in range(6)]
  return [totals[1]/totals[0],(totals[1]/totals[3])/(totals[0]/totals[2]),(totals[1]/totals[5])/(totals[0]/totals[4])]
 values=list(clusters.values());point=ratios(values);intervals=None
 if len(values)>1:
  rng=random.Random(20261104);boots=[ratios(rng.choices(values,k=len(values))) for _ in range(10000)];intervals=[]
  for i in range(3):ordered=sorted(v[i] for v in boots);intervals.append([ordered[250],ordered[9750]])
 farm_comparisons.append({'rank':rank,'baselineRank':0,'nPairedRuns':len(keys),'seedClusters':len(values),'countRatio':point[0],'fastRelicRateRatio':point[1],'deliberateRelicRateRatio':point[2],'seedClusterBootstrap95':intervals,'baseCompleted':sum(base[k]['success'] for k in keys),'highCompleted':sum(high[k]['success'] for k in keys)})
electrify_summary=[]
for mode,policy in [('extraction','reserve_locked'),('extraction','default_unlocked'),('abyss','shared')]:
 for target in ['ally','boss','enemy']:
  rs=[r for r in j['rows'] if r['mode']==mode and r.get('supplyPolicy','shared')==policy];n=sum(r['electrify'][target]['opportunities'] for r in rs);k=sum(r['electrify'][target]['skips'] for r in rs);expected=sum(r['electrify'][target]['expectedSkips'] for r in rs);ci=None;cluster_ci=None
  clusters=collections.defaultdict(lambda:[0,0])
  for r in rs:clusters[r['seed']][0]+=r['electrify'][target]['opportunities'];clusters[r['seed']][1]+=r['electrify'][target]['skips']
  if n:
   phat=k/n;z=1.959963984540054;center=(phat+z*z/(2*n))/(1+z*z/n);half=z*math.sqrt(phat*(1-phat)/n+z*z/(4*n*n))/(1+z*z/n);ci=[center-half,center+half]
   if len(clusters)>1:
    rng=random.Random(20261102);values=list(clusters.values());boots=[]
    for _ in range(10000):
     sample=rng.choices(values,k=len(values));den=sum(v[0] for v in sample)
     if den:boots.append(sum(v[1] for v in sample)/den)
    boots.sort();cluster_ci=[boots[int(len(boots)*.025)],boots[min(len(boots)-1,int(len(boots)*.975))]] if boots else None
  electrify_summary.append({'mode':mode,'supplyPolicy':policy,'target':target,'seedClusters':len(clusters),'opportunities':n,'skips':k,'expectedSkips':expected,'skipRate':k/n if n else None,'expectedRate':expected/n if n else None,'wilson95Nominal':ci,'seedClusterBootstrap95':cluster_ci})
vault_groups=collections.defaultdict(list)
for r in j['rows']:
 if r['mode']=='extraction':
  for v in r['keyVaultHistory']:vault_groups[(r['profile'],r['risk'],r['supplyPolicy'],v['act'],v['keyId'])].append((r,v))
vault_summary=[]
for key,pairs in sorted(vault_groups.items()):
 values=[v for r,v in pairs];failed=[v for r,v in pairs if not r['success']]
 d=dict(zip(['profile','risk','supplyPolicy','act','keyId'],key));d.update(n=len(values),foundValue=st.mean(v['foundValue'] for v in values),realizedValue=st.mean(v['realizedValue'] for v in values),realizedMinus500=st.mean(v['realizedMinusReplacementCost'] for v in values),paybackRate=sum(v['coversReplacementCost'] for v in values)/len(values),failedN=len(failed),failedRealizedValue=st.mean(v['realizedValue'] for v in failed) if failed else None);vault_summary.append(d)
all_drops=[d for r in j['rows'] if r['mode']=='abyss' for d in r['relicDrops']]
relic_audit={'actualDropped':len(all_drops),'targetSetMatched':sum(d['item'].get('setId')==r['targetRelicSetId'] for r in j['rows'] if r['mode']=='abyss' for d in r['relicDrops']),'actualFourStar':sum(d['item']['rarity']==4 for d in all_drops),'actualFiveStar':sum(d['item']['rarity']==5 for d in all_drops),'actualSoldGold':sum(r.get('relicSell',0) for r in j['rows']),'directAbyssGold':sum(r.get('goldDirect',0) for r in j['rows'] if r['mode']=='abyss'),'byTargetSet':dict(collections.Counter(d['item'].get('setId','') for d in all_drops)),'ownerEffectSnapshotChecks':sum(r['ownerEffectChecks'] for r in j['rows']),'mainRoutes':sum(r.get('series','main')=='main' for r in j['rows']),'efficiencyRoutes':sum(r.get('series')=='drop_efficiency' for r in j['rows'])}
current_mismatches=[]
for name,expected in j['hashes'].items():
 if hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()!=expected:current_mismatches.append(name)
out=p.with_name(p.stem+'-summary.json');out.write_text(json.dumps({'source':str(input_path),'sourceUncompressedSha256':hashlib.sha256(raw_data).hexdigest(),'matchedThemeFixturePairs':fixture_matches,'relicAudit':relic_audit,'dropEfficiencyDesign':{'sameAttributesAcrossRanksWithinSeed':True,'sameAttributesAcrossAllSeeds':False,'description':'Fixed roster and legal legacy generation rules. Each seed generates one legal equipment fixture shared by all four ranks and both attempts; legal rolls may differ between seeds.'},'themePairedComparisons':theme_pairs,'dropEfficiencyComparisons':farm_comparisons,'groups':summary,'comparisons':comparisons,'pairedPolicyComparisons':paired,'keyVaultGroups':vault_summary,'electrify':electrify_summary,'errors':errors,'currentSourceMismatches':current_mismatches},ensure_ascii=False,indent=2))
print('rows',len(j['rows']),'battles',sum(r['battles'] for r in j['rows']),'errors',len(errors),'currentSourceMismatches',current_mismatches)
for d in summary:
 if d['mode']=='extraction':print(d['profile'],d['risk'],d['supplyPolicy'],f"{d['completed']}/{d['n']}",'all',round(d['gold']),'full',round(d['completeMean_gold'] or 0),'guard',round(d['guardBattles'],2),'parcel',round(d['parcelValue']), 'cells',round(d['firstBossBeforeCells'],1),round(d['firstBossAfterCells'],1))
for c in comparisons:print(c)
if errors:print(errors[:30])
raise SystemExit(bool(errors or current_mismatches))
