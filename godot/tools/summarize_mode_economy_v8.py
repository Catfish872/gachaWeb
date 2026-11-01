"""Summarize actual route outcomes; all per-minute rates are ratios of means."""
import json,sys,collections,statistics,pathlib
src=pathlib.Path(sys.argv[1]);j=json.loads(src.read_text());groups=collections.defaultdict(list)
for r in j['rows']:
 k=(r['profile'],r['mode'],r['risk'],r.get('kit',''),r.get('targetAct',0),r.get('recycling',False));groups[k].append(r)
summary=[]
for k,rs in sorted(groups.items()):
 d=dict(zip(['profile','mode','risk','kit','targetAct','recycling'],k));d['n']=len(rs);d['successes']=sum(r['success'] for r in rs)
 for key in ['gold','goldLiquidation','keyRetainedCapital','keyRetainedCapitalSale','keyConsumedCost','goldDirect','relicSell','diamonds','xpAwardedPerCharacter','xpAppliedTotal','secondsFast','secondsDeliberate','capital','walletDelta','directGoldGross','retainedAssets','repairReserve','salvageCount','salvageGold','salvageItems','fullRooms','peakCells','deposits','keyPurchaseCost','keysUsed','keysRetained','keysRetainedValue','battles']:
  if key in rs[0]:d[key]=statistics.mean(r[key] for r in rs)
 if 'retainedByKind' in rs[0]:
  kinds=set().union(*(r['retainedByKind'] for r in rs));d['retainedByKind']={k:statistics.mean(r['retainedByKind'].get(k,0) for r in rs) for k in sorted(kinds)}
 for key in ['goldFound','redFound','goldLootFound','redLootFound']:
  if key in rs[0]:d[key]=[statistics.mean(r[key][a] for r in rs) for a in range(3)]
 d['goldMedian']=statistics.median(r['gold'] for r in rs)
 d['goldMin']=min(r['gold'] for r in rs);d['goldMax']=max(r['gold'] for r in rs)
 d['rateFast']=d['gold']*60/d['secondsFast'];d['rateDeliberate']=d['gold']*60/d['secondsDeliberate']
 if 'goldDirect' in d:
  d['directRateFast']=d['goldDirect']*60/d['secondsFast'];d['directRateDeliberate']=d['goldDirect']*60/d['secondsDeliberate']
 summary.append(d)
out=src.with_name(src.stem+'-summary.json');out.write_text(json.dumps({'source':str(src),'errors':j['errors'],'groups':summary},ensure_ascii=False,indent=2))
print('profile mode kit act recycle n win gold fast/min slow/min salvage pressure')
for d in summary:print(d['profile'],d['mode'],d['kit'],d['targetAct'],d['recycling'],d['n'],d['successes'],round(d['gold']),round(d['rateFast']),round(d['rateDeliberate']),round(d.get('salvageGold',0)),round(d.get('fullRooms',0),1))
print('Errors:',j['errors'])
