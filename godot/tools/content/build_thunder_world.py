#!/usr/bin/env python3
"""Add the thunder-city world contract without changing existing catalog sections.
Art was generated as new images and packed in transparent atlases. This script
creates native AtlasTexture views; it does not recolor or replace existing art.
"""
import copy, hashlib, json, os
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[3]
GODOT = ROOT / 'godot'
ART = GODOT / 'assets/content_v290'
PREFIX = 'res://assets/content_v290/'

def write_json(path, value):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    os.replace(tmp, path)

def atlas_view(kind, name, atlas, col, row, cols, rows):
    w, h = Image.open(ART/'atlases'/f'{atlas}.png').size
    # Integer boundaries cover each complete cell; filter_clip avoids adjacent-cell bleeding.
    x0, y0 = round(col*w/cols), round(row*h/rows)
    x1, y1 = round((col+1)*w/cols), round((row+1)*h/rows)
    # The generated enemy rows have a clean alpha gap at y=369..389.
    # Split inside that gap so the tall boss crown stays wholly in row two.
    if atlas == "thunder_enemies_atlas":
        y0, y1 = (0, 380) if row == 0 else (380, h)
    path = ART/kind/f'{name}.tres'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                    f'[ext_resource type="Texture2D" path="{PREFIX}atlases/{atlas}.png" id="1"]\n\n'
                    '[resource]\natlas = ExtResource("1")\n'
                    f'region = Rect2({x0}, {y0}, {x1-x0}, {y1-y0})\nfilter_clip = true\n')
    return PREFIX+kind+'/'+name+'.tres'

BG = {n: PREFIX+'backgrounds/'+n+'.png' for n in ['thunder_gate','rain_street','storm_market','ward_clinic','sealed_station','observatory','sunken_tower','rift_core']}
ENEMY_NAMES = [
 ('thunder_mane','雷鬃兽'),('charge_mayfly','蓄电蜉蝣'),('storm_patrol','巡雷机兵'),
 ('rift_shade','裂隙游影'),('storm_crossbow','鸣雷弩卫'),('breaker_cavalier','破阵重骑'),
 ('thunder_core_guard','雷核守卫'),('boss_city_sealer','封城者'),('sealer_core','导雷核心'),('sealer_ward','护城节点')]
portraits={key:atlas_view('enemies',key,'thunder_enemies_atlas',i%5,i//5,5,2) for i,(key,_) in enumerate(ENEMY_NAMES)}
CONTAINERS = [('thunder_city_supply','封城补给箱'),('thunder_city_medicine','结界药柜'),
 ('thunder_city_tools','导雷工具柜'),('thunder_city_altar','鸣雷供台'),
 ('thunder_city_archive','封存图筒'),('thunder_city_treasury','护城宝匣')]
container_defs={key:{'name':name,'sprite':atlas_view('containers',key,'thunder_containers_atlas',i%3,i//3,3,2)} for i,(key,name) in enumerate(CONTAINERS)}
LOOT=[
 ('wire','铜线卷','wire','检修导雷线路时留下的铜线，外层缠着干燥的布带。'),
 ('cloth','防雨布','cloth','城门货棚收起的防雨布，边角缝着补过的针脚。'),
 ('insulator','陶瓷绝缘子','bolts','巡雷机兵线路上的陶瓷零件，表面留着细小的烧痕。'),
 ('rod_cap','引雷杆帽','tape','从屋顶引雷杆换下的铜帽，尖端已经磨圆。'),
 ('wax','紫纹封蜡','lens','档案保管员用来封住图筒的蜡，印着旧城纹章。'),
 ('herbs','银叶草包','circuit','诊所晾干的银叶草，用柔软的布包扎得很仔细。'),
 ('contacts','铜触片','pliers','导雷装置内拆下的铜片，接合处仍然平整。'),
 ('glass','雷纹玻璃','motor','在雷雨里形成细密晶纹的玻璃，透光时泛出浅蓝色。'),
 ('coil','感应线圈','battery','按顺序绕好的铜线圈，接线端刻着旧式编号。'),
 ('gauge','测流仪表','sensor','修缮工用来检查导雷线路的仪表，指针保存完好。'),
 ('badge','城防徽章','drone_rotor','护城骑士留下的徽章，背面刻着执勤人的名字。'),
 ('ruler','折叠测绘尺','insulin_case','旧城测绘队的铜尺，展开后能看到细致的刻度。'),
 ('fork','银制调音叉','processor','检修导雷塔时使用的银叉，轻敲后会发出清亮的声音。'),
 ('blueprint','旧城线路图','silk_scroll','记录街区与地下古塔之间线路的图纸，修改处用红墨圈出。'),
 ('compass','引雷罗盘','crystal','晶针随着附近的雷流缓缓偏转，黄铜外壳仍能扣紧。'),
 ('amulet','避雷护符','rare_ore','旧城居民珍藏的护符，晶石内保留着淡紫色的光。'),
 ('wheel','鎏金导雷轮','gold_watch','古塔上拆下的导雷轮，细密铜线缠绕着镀金轮框。'),
 ('amber','凝雷琥珀','idol','透明晶石中凝结着一道金色雷纹，像停留在雨夜的一瞬。'),
 ('plans','王城营造图','crown','封存于金属图匣的旧城图册，连地下排水道都画得十分清楚。'),
 ('frame','银制控制架','quantum_server','古塔控制装置的银框，几处磨损显示它曾被长期使用。'),
 ('heart','紫霆心晶','red_core','古塔中央保存的雷晶，晶面深处映出流动的紫色光芒。'),
 ('instrument','初代引雷仪','archive','建立鸣雷城时使用的引雷仪，铜架上的工匠署名依然清晰。'),
 ('crown','护城者金冠','dragon_egg','纪念早期守城者的金冠，紫晶间镂刻着城墙与塔楼。'),
 ('boundary','晴穹界晶','phoenix_feather','用于维持古老结界的蓝晶，内部的光像雨后渐晴的天空。')]

catalog_path=GODOT/'data/catalog.json'
c=json.loads(catalog_path.read_text())
skills={}
def skill(sid,name,mult=0.0,target='single',extra=None,warning=False,cooldown=0):
    effects=[]
    if mult: effects.append({'type':'damage','target':target,'multiplier':mult,'element':'thunder'})
    effects += extra or []
    skills[sid]={'name':name,'effects':effects,'cooldown':cooldown,'animation':'thunder'}
    if warning: skills[sid]['telegraphNext']=True

def buff(status,value,target='self',duration=2):
    return {'type':'status','target':target,'statusId':status,'value':value,'duration':duration,'refreshDuration':True}
skill('thunder_mane_pounce','雷鬃扑击',1.2)
skill('thunder_mane_bite','裂爪撕咬',1.0)
skill('charge_mayfly_flash','电翅掠过',.9,extra=[buff('spd_down',.12,'single')],cooldown=2)
skill('charge_mayfly_sting','微芒刺击',1.0)
skill('storm_patrol_warning','执戟蓄势',.7,warning=True)
skill('storm_patrol_heavy','巡雷重刺',1.6)
skill('storm_patrol_strike','枪柄推击',1.0)
skill('rift_shade_slash','裂影挥击',1.0)
skill('rift_shade_veil','虚影守势',extra=[buff('def_up',.25)],cooldown=3)
skill('storm_crossbow_aim','弩架校准',.7,warning=True)
skill('storm_crossbow_bolt','贯雷弩矢',1.5)
skill('storm_crossbow_shot','短弩射击',1.0)
skill('breaker_warning','重槊回摆·蓄势',.8,warning=True)
skill('breaker_charge','破阵突刺',1.7)
skill('breaker_strike','收槊横击',1.2)
skill('core_guard_warning','雷盾充能·下次行动全体',.6,extra=[buff('shield',.04)],warning=True)
skill('core_guard_sweep','雷环横扫',.75,'all')
skill('core_guard_strike','护盾推击',1.0)
skill('sealer_warning','高塔聚雷·下次行动全体',1.3,warning=True)
skill('sealer_storm','封城雷网',1.0,'all')
skill('sealer_strike','守城重拳',1.3)
skill('sealer_warning_high','雷核过载·下次行动全体',1.5,warning=True)
skill('sealer_tempest','裂隙雷暴',1.4,'all')
skill('sealer_crush','雷霆重压',1.5)
skill('sealer_core_feed','导雷脉冲',1.2,extra=[buff('atk_up',.08,'boss_ally')])
# Status before attack matches the existing bounded auxiliary-target contract.
skills['sealer_core_feed']['effects'].reverse()
ward=buff('shield',.08,'boss_ally');ward.update(scalingStat='maxHp',multiplier=.08)
skill('sealer_ward_guard','护城屏障',1.2,extra=[ward]);skills['sealer_ward_guard']['effects'].reverse()

SPECS=[
 ('thunder_mane','normal',[2900,175,85,120],[420,80,25,115],['thunder_mane_pounce','thunder_mane_bite'],'thunder_hawk','aggressive',['thunder_gate','rain_street'],None),
 ('charge_mayfly','normal',[2700,155,80,100],[350,50,25,85],['charge_mayfly_flash','charge_mayfly_sting'],'goblin','random',['thunder_gate','storm_market'],None),
 ('storm_patrol','normal',[3800,190,125,80],[380,45,35,75],['storm_patrol_warning','storm_patrol_heavy','storm_patrol_strike'],'goblin','random',['rain_street','sealed_station'],'cycle'),
 ('rift_shade','normal',[3300,170,100,100],[500,55,60,60],['rift_shade_slash','rift_shade_veil'],'ice_wolf','random',['sunken_tower','rift_core'],None),
 ('storm_crossbow','normal',[3100,180,90,110],[380,45,25,95],['storm_crossbow_aim','storm_crossbow_bolt','storm_crossbow_shot'],'goblin','random',['storm_market','sealed_station'],'cycle'),
 ('breaker_cavalier','elite',[9800,270,145,110],[1100,90,85,105],['breaker_warning','breaker_charge','breaker_strike'],'dark_knight','random',['rain_street','sealed_station'],'cycle'),
 ('thunder_core_guard','elite',[11200,255,170,80],[1200,80,100,70],['core_guard_warning','core_guard_sweep','core_guard_strike'],'dark_knight','random',['observatory','sunken_tower'],'cycle'),
 ('boss_city_sealer','boss',[32000,340,180,110],[5500,140,55,100],['sealer_warning','sealer_storm','sealer_strike'],'boss_storm_witch','boss',['rift_core'],'boss'),
 ('sealer_core','normal',[3600,1,90,90],[350,1,25,80],['sealer_core_feed'],'furnace_lamp','support',['rift_core'],'attachment'),
 ('sealer_ward','normal',[3600,1,90,85],[350,1,25,80],['sealer_ward_guard'],'furnace_lamp','support',['rift_core'],'attachment')]
enemies={}
for key,kind,base,abyss,sids,ref,ai,bgs,mode in SPECS:
    data={'id':key,'name':dict(ENEMY_NAMES)[key],'icon':'ϟ','type':kind,'element':'thunder',
          'baseStats':dict(zip(['hp','atk','def','spd'],base)),'abyssBaseStats':dict(zip(['hp','atk','def','spd'],abyss)),
          'skills':sids,'aiPattern':ai,'drops':{'gold':[25,45],'exp':30},'color':'#bd9beb',
          'portrait':portraits[key],'environmentTheme':'thunder_city','abyssBackgrounds':[BG[b] for b in bgs],'balanceReference':ref}
    if key in ['thunder_mane','rift_shade','storm_crossbow']:data['abyssMinFloor']=4
    if mode=='cycle':data['actionCycle']=sids
    if mode=='boss':data.update(isBoss=True,phaseThreshold=.5,phase2Skills=['sealer_warning_high','sealer_tempest','sealer_crush'],
                               actionCycle=['sealer_warning','sealer_storm'],phase2ActionCycle=['sealer_warning_high','sealer_tempest'],
                               expeditionAI={'aoeChance':.5,'recoveryPolicy':'single'},abyssAttachments=[])
    if mode=='attachment':data['encounterAttachment']=True
    enemies[key]=data
patch={'EnemyData':enemies,'EnemySkillData':skills,'AbyssPools':{k:[e for e,d in enemies.items() if d['type']==kind and not d.get('encounterAttachment')] for k,kind in [('normal','normal'),('elite','elite'),('boss','boss')]}}
write_json(GODOT/'data/thunder_world_patch.json',patch)
for key in ['EnemyData','EnemySkillData']:c[key].update(patch[key])
for kind,ids in patch['AbyssPools'].items():
    for eid in ids:
        if eid not in c['AbyssData']['pools'][kind]:c['AbyssData']['pools'][kind].append(eid)
write_json(catalog_path,c)

x_path=GODOT/'data/extraction.json';x=json.loads(x_path.read_text())
x['environmentThemes']['thunder_city']={
 'name':'鸣雷城','music':'thunder_city_gate','depthMusic':['thunder_city_gate','thunder_city_street','thunder_city_core'],
 'bossMusic':'thunder_city_core','bossBackground':BG['rift_core'],'depthIds':['storm_gate','storm_city','storm_spire'],
 'depthNames':['雷雨城郊','鸣雷旧城','雷塔禁区'],
 'backgrounds':[[BG['thunder_gate'],BG['rain_street']],[BG['storm_market'],BG['ward_clinic'],BG['sealed_station']],[BG['observatory'],BG['sunken_tower'],BG['rift_core']]],
 'roomNames':{'entry':'雷雨城门','battle':'巡雷街道','cache':'封城货棚','rest':'避雨营地','event':'旧城告示亭','elite':'重骑关隘','vault':'护城宝库','hospital':'结界诊所','workshop':'导雷修缮所','shrine':'鸣雷供台','boss':'裂隙核心','key_vault':'古塔档案室','relay':'城防驿站'},
 'containers':list(container_defs),'enemies':{'battle':patch['AbyssPools']['normal'],'elite':patch['AbyssPools']['elite'],'boss':patch['AbyssPools']['boss']},
 'bossAttachments':['sealer_core','sealer_ward'],
 'encounterBudget':{'hpRatio':1.0,'atkRatio':1.0,'normalEarly':['wolf','goblin','fire_imp'],'normalLate':['ice_wolf','thunder_hawk','fire_imp'],'elite':['dark_knight'],'boss':['boss_storm_witch'],'escortAttackRatio':0.0},
 'attachmentAttackByRank':[[15,15],[15,15],[15,15],[15,15],[90,15],[90,80]]}
x['environmentContainers'].update(container_defs)
x['containerLootCategories'].update({'thunder_city_medicine':['补给','疗愈用品'],'thunder_city_tools':['工具','零件','整备','装备']})
for i,(suffix,name,base,desc) in enumerate(LOOT):
    iid='thunder_city_'+suffix;d=copy.deepcopy(x['items'][base])
    d.update(name=name,description=desc,icon=atlas_view('loot',iid,'thunder_loot_atlas',i%6,i//6,6,4),variantOf=base,environmentTheme='thunder_city')
    x['items'][iid]=d
key=copy.deepcopy(x['items']['key_ruins']);key.update(name='古塔档案室钥匙',description='开启鸣雷城的古塔档案室。',
 icon=x['items']['key_ruins']['icon'],keyTheme='thunder_city',variantOf='key_ruins',environmentTheme='thunder_city')
x['items']['key_thunder_city']=key
write_json(x_path,x)

manifest={'version':'2.9.0-working','created':'2026-11-10','method':'Built-in image generation; new original production backgrounds and transparent sprite atlases. AtlasTexture references preserve generated pixels.',
          'license':'Generated for this project; no external artwork or third-party reference images supplied to image generation.',
          'sourceRecords':'docs/thunder_world_asset_sources.json','files':[]}
for p in sorted(ART.rglob('*')):
    if p.is_file() and p.suffix in ['.png','.tres'] and p.parts[-2] in ['backgrounds','enemies','containers','loot','atlases']:
        entry={'path':str(p.relative_to(GODOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
        if p.suffix=='.png':
            im=Image.open(p);entry.update(width=im.width,height=im.height,mode=im.mode,decodedRgbaBytes=im.width*im.height*4)
        manifest['files'].append(entry)
write_json(ART/'world-art-manifest.json',manifest)
print('Thunder world: 8 backgrounds, 10 enemies including 2 attached targets, 6 containers, 24 loot variants and 1 key; patches applied.')
