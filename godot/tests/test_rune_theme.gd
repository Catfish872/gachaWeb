extends SceneTree
const Rune=preload('res://scripts/ui/rune_theme.gd')
var checks:=0
var failures:=0
func check(ok:bool,what:String):
 checks+=1
 if not ok:failures+=1;push_error(what)
func _initialize():call_deferred('run')
func run():
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/catalog.json'))
 var keys={}
 for entry in data.AbyssData.rogue.rewards+data.SkillData.values():
  var key:=Rune.effect_key(entry)
  keys[key]=true
  check(ResourceLoader.exists('res://assets/ui/runes/'+key+'.svg'),'semantic icon exists '+str(entry.id))
 check(keys.size()>=12,'effects remain visually distinct')
 check(Rune.effect_key({'icon':'⚔️'})=='sword','web attack maps to sword')
 check(Rune.effect_key({'icon':'❤️'})=='heart','web life maps to heart')
 check(Rune.effect_key({'icon':'🛡️'})=='shield','web shield preserved')
 for primary in [false,true]:
  for state in ['normal','hover','pressed','disabled']:
   var style=Rune.button_style(primary,state)
   check(style.texture!=null,'rune frame texture')
   check(style.content_margin_top==8 and style.content_margin_bottom==8,'frame preserves touch layout')
 print('RUNE THEME: %d checks, %d failures' % [checks,failures])
 quit(0 if failures==0 else 1)
