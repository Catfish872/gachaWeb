"""Replay recovered approved loot manifests; preserve every old economic bucket."""
import copy,json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=ROOT/'godot/data/extraction.json'
d=json.loads(p.read_text()); manifests=[]
for f in ['general_loot_expansion_manifest.json','general_loot_lowtier_manifest.json','general_loot_narrow_manifest.json','general_loot_final_gaps_manifest.json']:
 manifests+=json.loads((ROOT/'docs'/f).read_text())
for anchor in {e['anchor'] for e in manifests}:
 a=d['items'][anchor]
 old_weight=a.get('preExpansionDropWeight',a.get('dropWeight',1.0))
 a['preExpansionDropWeight']=old_weight;a['dropWeight']=old_weight/4
 peers=[e for e in manifests if e['anchor']==anchor]
 value=a['value'];low=max(1,round(value*.11));high=max(1,round(value*.04))
 for e,off in zip(peers,[-low,-high,low+high]):
  item=copy.deepcopy(a)
  for key in ['legacyValue','v6Value','v7Value','previousValue','preExpansionDropWeight','buyPrice','buyMinRisk']:item.pop(key,None)
  item.update(name=e['name'],description=e['description'],value=value+off,icon=f"res://assets/extraction/v300/general_loot/{e['id']}.tres",economyAnchor=anchor)
  if a['kind']!='loot':item['description']+=' '+a['description']
  d['items'][e['id']]=item
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
print(f'Integrated {len(manifests)} new independently selectable items; total {len(d["items"])}')
