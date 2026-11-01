extends RefCounted
# Nine-slice rune frame: art never changes measured content or touch targets.
static func button_style(primary:bool,state:String)->StyleBoxTexture:
 var style:=StyleBoxTexture.new()
 style.texture=load('res://assets/ui/runes/'+('primary_' if primary else 'secondary_')+state+'.svg')
 style.texture_margin_left=12;style.texture_margin_right=12
 style.texture_margin_top=12;style.texture_margin_bottom=12
 style.content_margin_left=12;style.content_margin_right=12
 style.content_margin_top=8;style.content_margin_bottom=8
 return style
static func effect_key(data:Dictionary)->String:
 var icons={'☁️':'wind','🌊':'water','🌩️':'energy','🌪️':'wind','🌳':'leaf','🌿':'leaf','🏰':'shield','💧':'water','💨':'wind','🔵':'shield','🦵':'kick','⚔️':'sword','⚡':'energy','✦':'star','✨':'star','❄️':'ice','❤️':'heart','🌋':'fire','🌌':'void','🌟':'star','🎯':'crit','🏕️':'camp','🐉':'dragon','💚':'leaf','💠':'shield','💥':'burst','🔋':'energy','🔥':'fire','🛡️':'shield','🧊':'ice'}
 if icons.has(str(data.get('icon',''))):return icons[str(data.icon)]
 var id:=str(data.get('id','')).to_lower()
 for entry in [['heart',['recover','vitality','heal','health','blood']],['sword',['offense','attack','elite','forge']],['shield',['armor','shield','defense']],['energy',['energy','meditate','well']],['bag',['supply','scavenge','cache','caravan']],['path',['route','safe','path']]]:
  for token in entry[1]:
   if str(token) in id:return entry[0]
 return 'star' 
