"""Prepare original rebuilt loot AtlasTextures. Production PNGs are never modified."""
import json,hashlib,math,argparse
from pathlib import Path
from PIL import Image
R=Path(__file__).resolve().parents[1];G=R/'godot'
def read(p):return json.loads((R/p).read_text())
def batches():
 a=read('docs/general_loot_expansion_manifest.json')
 for i in range(5):yield f'assets/extraction/v300/general_loot/atlas_{i+1:02}.png',a[i*24:(i+1)*24],6,4
 for n,k in [(6,'lowtier'),(7,'narrow')]:yield f'assets/extraction/v300/general_loot/atlas_{n:02}.png',read(f'docs/general_loot_{k}_manifest.json'),6,4
 a=read('docs/general_loot_final_gaps_manifest.json')
 yield 'assets/extraction/v300/general_loot/atlas_08.png',a[:24],6,4
 yield 'assets/extraction/v300/general_loot/atlas_09.png',a[24:],4,3
 yield 'assets/extraction/v300/thunder_loot/atlas.png',read('docs/thunder_city_art_24.json'),6,4
 yield 'assets/extraction/v300/thunder_loot/legacy_redesign.png',read('docs/thunder_city_legacy_redesign_8.json'),4,2

def main(partial=False):
 d=read('godot/data/extraction.json')['items'];entries=[];atlases=[];missing=[];seen=set();qa=R/'validation/loot_art_v300';qa.mkdir(parents=True,exist_ok=True)
 for rel,items,cols,rows in batches():
  p=G/rel
  if not p.exists():
   if partial:missing.append(rel);continue
   raise AssertionError(rel)
  im=Image.open(p);w,h=im.size;assert im.mode=='RGBA';assert abs(w/cols-h/rows)<1
  a=im.getchannel('A');assert a.histogram()[0]>w*h*.20,(rel,'alpha')
  xs=[round(i*w/cols) for i in range(cols+1)];ys=[round(i*h/rows) for i in range(rows+1)]
  sheets={z:Image.new('RGB',(cols*(z+16),rows*(z+16)),(20,25,37)) for z in [48,70]}
  ids=[]
  for i,item in enumerate(items):
   key=item['id']
   if key=='thunder_city_boundary':continue
   assert key in d and key not in seen;seen.add(key);ids.append(key)
   x,y=xs[i%cols],ys[i//cols];cw,ch=xs[i%cols+1]-x,ys[i//cols+1]-y
   cell=im.crop((x,y,x+cw,y+ch));box=cell.getchannel('A').point(lambda t:255 if t>32 else 0).getbbox();assert box
   assert min(box[0],box[1],cw-box[2],ch-box[3])>=1,(key,box)
   side=min(cw,ch,math.ceil(max(box[2]-box[0],box[3]-box[1])/.82));ox=max(0,min(cw-side,round((box[0]+box[2]-side)/2)));oy=max(0,min(ch-side,round((box[1]+box[3]-side)/2)))
   reg=[x+ox,y+oy,side,side];crop=im.crop((reg[0],reg[1],reg[0]+side,reg[1]+side));icon=d[key]['icon'];assert icon.endswith('.tres');t=G/icon.removeprefix('res://');t.parent.mkdir(parents=True,exist_ok=True)
   t.write_text('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://'+rel+'" id="1"]\n\n[resource]\natlas = ExtResource("1")\nregion = Rect2('+', '.join(map(str,reg))+')\nfilter_clip = true\n')
   entries.append({'id':key,'name':d[key]['name'],'icon':icon,'atlas':rel,'region':reg,'sourceCell':[x,y,cw,ch],'visibleBounds':list(box),'pixelSha256':hashlib.sha256(crop.tobytes()).hexdigest()})
   for z,sheet in sheets.items():
    small=crop.resize((z,z),Image.Resampling.LANCZOS);sheet.paste(small,(i%cols*(z+16)+8,i//cols*(z+16)+8),small)
  for z,sheet in sheets.items():sheet.save(qa/f'{p.parent.name}_{p.stem}_{z}px.png')
  atlases.append({'atlas':rel,'size':[w,h],'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'alphaZeroPixels':a.histogram()[0],'items':ids})
 # Standalone portrait replacement: original atlas bytes and other seven regions stay unchanged.
 key='thunder_city_boundary';rel='assets/extraction/v300/thunder_loot/ceremonial_flute_vertical.png';p=G/rel
 if p.exists():
  im=Image.open(p);w,h=im.size;a=im.getchannel('A');box=a.point(lambda t:255 if t>32 else 0).getbbox();assert box and a.histogram()[0]>.2*w*h
  x=max(0,box[0]-20);y=max(0,box[1]-20);right=min(w,box[2]+20);bottom=min(h,box[3]+20);reg=[x,y,right-x,bottom-y];crop=im.crop((x,y,right,bottom));icon=d[key]['icon']
  (G/icon.removeprefix('res://')).write_text('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://'+rel+'" id="1"]\n\n[resource]\natlas = ExtResource("1")\nregion = Rect2('+', '.join(map(str,reg))+')\nfilter_clip = true\n')
  entries.append({'id':key,'name':d[key]['name'],'icon':icon,'atlas':rel,'region':reg,'sourceCell':[0,0,w,h],'visibleBounds':list(box),'pixelSha256':hashlib.sha256(crop.tobytes()).hexdigest()})
  atlases.append({'atlas':rel,'size':[w,h],'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'alphaZeroPixels':a.histogram()[0],'items':[key]})
  thumb=crop.copy();thumb.thumbnail((48,144),Image.Resampling.LANCZOS);preview=Image.new('RGB',(64,160),(20,25,37));preview.paste(thumb,((64-thumb.width)//2,(160-thumb.height)//2),thumb);preview.save(qa/'flute_vertical_1x3_48px.png')
 else:missing.append(rel)
 assert len({e['pixelSha256'] for e in entries})==len(entries)
 if not partial:assert len(entries)==233
 report={'method':'Newly regenerated original art after workspace loss; not recovered original pixels. Native image generation and editing only.','license':'Generated for project, no third-party artwork supplied.','count':len(entries),'missing':missing,'atlases':atlases,'items':entries,'totalSourceBytes':sum(a['bytes'] for a in atlases)}
 (R/'docs/loot_art_v300_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print({'count':len(entries),'atlases':len(atlases),'bytes':report['totalSourceBytes'],'missing':missing})
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--allow-missing',action='store_true');main(p.parse_args().allow_missing)
