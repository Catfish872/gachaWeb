import json,collections,sys,hashlib
basepath='/workspace/shared/loot-audit-recovery/baseline.json'
current='/workspace/scratch/8f1fc457a062/gacha-release-recovery/godot/data/extraction.json'
pools={'generic':[],'medicine':['补给','疗愈用品'],'tools':['工具','零件','整备','装备'],'workshop':['符文构件','遗迹装置','工具','零件','装备','整备'],'shrine':['古物','王室遗物','奇珍','秘传典籍'],'vault':['珠宝','贵金属','王室遗物','奇珍','遗迹珍藏']}
def matches(v,c):return v.get('category')in c or bool(set(v.get('lootCategories',[]))&set(c))
def audit(x,new):
 items=x['items'];bases={k:v for k,v in items.items() if 'variantOf'not in v and 'lootTheme'not in v};rows=[];sums=[]
 for theme in ['',*x['environmentThemes']]:
  for pool,c in pools.items():
   for r in range(6):
    raw={k:v for k,v in bases.items() if v['rarity']==r}; chosen={k:v for k,v in raw.items() if matches(v,c)} or raw;g=collections.defaultdict(dict)
    def add(k,w):
     a=items[k]; shape=(a['width'],a['height']);g[shape][k]=g[shape].get(k,0)+w
    for k,v in chosen.items():
     rem=float(v.get('dropWeight',1))
     if new and theme:
      for tk,tv in items.items():
       if tv.get('lootTheme')==theme and tv.get('economyAnchor')==v.get('economyAnchor',k) and tv.get('kind')==v.get('kind') and (not c or matches(tv,c)):
        p=tv.get('themeSubstitutionChance',.2);add(tk,rem*p);rem*=1-p
     actual=k
     for vk,vv in items.items():
      if vv.get('variantOf')==k and vv.get('environmentTheme')==theme and (not new or not c or matches(vv,c)):actual=vk;break
     add(actual,rem)
    total=sum(sum(q.values()) for q in g.values());flat=[(items[k],w) for q in g.values() for k,w in q.items()]
    for shape,q in g.items():rows.append(dict(theme=theme or 'legacy',pool=pool,rarity=r,shape=list(shape),candidates=len(q),bestGuess=max(q.values())/sum(q.values()),ids=list(q),weight=sum(q.values())))
    sums.append(dict(theme=theme or 'legacy',pool=pool,rarity=r,weight=total,value=sum(v['value']*w for v,w in flat)/total,area=sum(v['width']*v['height']*w for v,w in flat)/total,kind={kind:sum(w for v,w in flat if v['kind']==kind)/total for kind in set(v['kind'] for v,w in flat)}))
 return rows,sums
b=json.load(open(basepath));a=json.load(open(current));bg,bs=audit(b,False);ag,ss=audit(a,True)
diffs=[]
for old,new in zip(bs,ss):
 diffs.append(dict(theme=old['theme'],pool=old['pool'],rarity=old['rarity'],valuePct=(new['value']/old['value']-1)*100,areaDiff=new['area']-old['area'],weightDiff=new['weight']-old['weight'],kindDiff=max(abs(new['kind'].get(k,0)-old['kind'].get(k,0)) for k in set(new['kind'])|set(old['kind']))))
report=dict(catalog=len(a['items']),base=sum('variantOf'not in v and 'lootTheme'not in v for v in a['items'].values()),conditional=sum('lootTheme'in v for v in a['items'].values()),groups=len(ag),singletons=sum(x['candidates']==1 for x in ag),minimumCandidates=min(x['candidates'] for x in ag),maximumGuess=max(x['bestGuess'] for x in ag),highMaximumGuess=max(x['bestGuess'] for x in ag if x['rarity']>=3),maxAreaDiff=max(abs(x['areaDiff']) for x in diffs),maxWeightDiff=max(abs(x['weightDiff']) for x in diffs),maxKindDiff=max(abs(x['kindDiff']) for x in diffs),minimumValuePct=min(x['valuePct'] for x in diffs),maximumValuePct=max(x['valuePct'] for x in diffs),nonItemConfigsChanged=[k for k in b if k!='items' and b[k]!=a.get(k)],removedIds=sorted(set(b['items'])-set(a['items'])),oldFunctionalChanges=[(k,f) for k,v in b['items'].items() for f in ['width','height','rarity','value','kind','effects','heal','energy'] if v.get(f)!=a['items'][k].get(f)],sha256=hashlib.sha256(open(current,'rb').read()).hexdigest(),scope='Fresh recovery data audit; no image/resource availability claim; source baseline Git HEAD 86fb4d3')
print(json.dumps(report,ensure_ascii=False,indent=2))
json.dump(dict(summary=report,groups=ag,economy=ss,economyDiff=diffs),open('/workspace/shared/loot-audit-recovery/recovery-audit.json','w'),ensure_ascii=False,indent=2)
