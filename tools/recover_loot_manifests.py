import json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
d=json.loads((ROOT/'godot/data/extraction.json').read_text())['items']
for group in ['expansion','lowtier','narrow','final_gaps']:
 p=ROOT/f'docs/general_loot_{group}_recovered_rows.txt'
 if not p.exists():continue
 entries=[]
 for line in p.read_text().strip().splitlines():
  anchor,*peers=line.split('|');a=d[anchor]
  for j,peer in enumerate(peers):
   name,desc=peer.split(':',1)
   suffix=' 独立实物游戏图标，无文字无边框，完整物件可辨识。' if group=='expansion' else (' 独立实物图标，无文字无边框，轮廓清楚。' if group=='final_gaps' else ' 独立实物图标，无文字无边框，轮廓清晰。')
   entries.append({'id':f'general_{anchor}_{j+1}','anchor':anchor,'name':name,'description':desc,'artDescription':name+'。'+desc+suffix,'rarity':a['rarity'],'width':a['width'],'height':a['height'],'kind':a['kind']})
 (ROOT/f'docs/general_loot_{group}_manifest.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n')
 print(group,len(entries))
