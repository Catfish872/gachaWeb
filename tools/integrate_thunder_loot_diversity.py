import json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=ROOT/'godot/data/extraction.json';d=json.loads(p.read_text())
patch=json.loads((ROOT/'docs/thunder_city_loot_diversity_patch.json').read_text())
for key,item in patch['items'].items():
 item['themeSubstitutionChance']=0.2;d['items'][key]=item
for key,fields in patch.get('legacyTextCorrections',{}).items():
 if key in d['items']:d['items'][key].update({k:v for k,v in fields.items() if k in ['description','name','icon','category']})
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
