"""Structural/economic regression. Use --assets after all artwork exists."""
import json,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[1]
a=json.loads((root/'godot/data/extraction.json').read_text())
b=json.loads(subprocess.check_output(['git','show','86fb4d30e68655d6970ff3f2bedccd181a0e2e01:godot/data/extraction.json'],cwd=root))
items=a['items'];old=b['items']
assert len(items)==(452 if '--common-only' in sys.argv else 476)
assert len({x['name'] for x in items.values()})==len(items)
for key in ['rarityWeightsByAct','lootEconomy','mapEconomy','serviceGuards','balance']:assert a[key]==b[key],key
for key,x in old.items():
 for field in ['width','height','value','kind','effects','rarity']:assert items[key].get(field)==x.get(field),(key,field)
for anchor,base in old.items():
 if base.get('variantOf'):continue
 family=[v for k,v in items.items() if k==anchor or (k.startswith('general_') and v.get('economyAnchor')==anchor)]
 assert abs(sum(x.get('dropWeight',1) for x in family)-base.get('dropWeight',1))<1e-9,anchor
 assert abs(sum(x['value']*x.get('dropWeight',1) for x in family)-base['value']*base.get('dropWeight',1))<1e-8,anchor
 for x in family:
  for field in ['width','height','kind','effects','category','rarity','heal','energy','revive','repair','cooldown']:assert x.get(field)==base.get(field),(anchor,field)
for key,x in items.items():
 if key in old:continue
 assert x['value']>0 and x['width']>0 and x['height']>0
 assert x['description'] and x['icon'] and not x.get('variantOf')
 if '--assets' in sys.argv:assert (root/'godot'/x['icon'].removeprefix('res://')).is_file(),(key,x['icon'])
print('PASS: recovered loot structural/economic invariants; old dimensions/value/function and rarity settings preserved')
