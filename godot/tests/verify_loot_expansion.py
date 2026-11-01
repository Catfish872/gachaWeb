"""Small v260 addon check. No simulation, no full regression suite."""
import json, hashlib, re
from collections import Counter
from pathlib import Path
root = Path(__file__).resolve().parents[1]
data = json.loads((root/'data/extraction.json').read_text())['items']
m = json.loads((root/'assets/extraction/v260/loot_expansion/manifest.json').read_text())
assert len(m['items']) == 36
assert hashlib.sha256((root/m['atlas']).read_bytes()).hexdigest() == m['sha256']
allowed = {'name','description','icon','variantOf','environmentTheme'}
for item in m['items']:
    v, base = data[item['id']], data[item['base']]
    assert {k:x for k,x in v.items() if k not in allowed} == {k:x for k,x in base.items() if k not in allowed}, item['id']
    assert not base.get('variantOf')
    assert sum(x.get('variantOf') == item['base'] and x.get('environmentTheme') == item['theme'] for x in data.values()) == 1
    text=(root/v['icon'].removeprefix('res://')).read_text()
    assert 'filter_clip = true' in text
    assert 'region = Rect2(%s)' % ', '.join(map(str,item['region'])) in text
    x,y,w,h=item['region']; assert x>=0 and y>=0 and w>0 and h>0 and x+w<=m['size'][0] and y+h<=m['size'][1]
for theme in ['ruins','forest','sanctum']:
    assert Counter(i['rarity'] for i in m['items'] if i['theme']==theme) == Counter({r:2 for r in range(6)})
model=(root/'scripts/extraction_model.gd').read_text()
assert 'not data.items[key].has("variantOf")' in model
print('PASS 36 variants; 6 rarities x 2 per theme; mechanical copies; unique theme/base; atlas bounds and hash; unchanged base weighted pool')
