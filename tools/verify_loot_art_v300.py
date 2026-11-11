"""Read-only rebuilt loot resource regression."""
import json,hashlib
from pathlib import Path
from PIL import Image
R=Path(__file__).resolve().parents[1];G=R/'godot';m=json.loads((R/'docs/loot_art_v300_manifest.json').read_text());d=json.loads((G/'data/extraction.json').read_text())['items'];assert m['count']==233 and len(m['atlases'])==12 and not m['missing'];ims={}
for a in m['atlases']:
 p=G/a['atlas'];assert hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256'];im=Image.open(p);assert im.mode=='RGBA' and list(im.size)==a['size'];assert im.getchannel('A').histogram()[0]>.2*im.width*im.height;ims[a['atlas']]=im
seen=set()
for a in m['items']:
 assert d[a['id']]['icon']==a['icon'];s=(G/a['icon'].removeprefix('res://')).read_text();assert 'filter_clip = true' in s and 'path="res://'+a['atlas']+'"' in s and 'region = Rect2('+', '.join(map(str,a['region']))+')' in s
 x,y,w,h=a['region'];sx,sy,sw,sh=a['sourceCell'];assert sx<=x<x+w<=sx+sw and sy<=y<y+h<=sy+sh;im=ims[a['atlas']];assert x+w<=im.width and y+h<=im.height;c=im.crop((x,y,x+w,y+h));hsh=hashlib.sha256(c.tobytes()).hexdigest();assert hsh==a['pixelSha256'] and hsh not in seen;seen.add(hsh);box=c.getchannel('A').point(lambda v:255 if v>32 else 0).getbbox();assert box and min(box[0],box[1],w-box[2],h-box[3])>=1
print('PASS 233 unique icons; 11 transparent rebuilt atlases + portrait flute; hashes/references/bounds/unique pixels')
