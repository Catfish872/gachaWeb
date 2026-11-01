extends SceneTree
var failures: Array[String]=[]
var checks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var fx=load("res://scripts/ui/battle_fx.gd").new()
	root.add_child(fx)
	check(fx.mouse_filter==Control.MOUSE_FILTER_IGNORE,"effects cannot consume taps")
	check(not fx.is_processing(),"idle effects do not redraw continuously")
	for i in range(100):
		fx.burst(Vector2(100,100),Color.RED,true)
		fx.streak(Vector2.ZERO,Vector2(100,100),Color.CYAN)
		fx.heal_ring(Vector2(100,100))
		fx.ultimate("kaldi","fire",Vector2.ZERO,Vector2(100,100))
	check(fx.bursts.size()<=160,"bounded particle count")
	check(fx.streaks.size()<=16,"bounded streak count")
	check(fx.rings.size()<=16,"bounded heal ring count")
	check(fx.ultimates.size()<=4,"bounded ultimate count")
	fx._process(2.0)
	check(fx.bursts.is_empty() and fx.streaks.is_empty() and fx.rings.is_empty() and fx.ultimates.is_empty(),"effects expire")
	check(not fx.is_processing(),"expired effects stop redraw work")
	fx.reduced_motion=true
	fx.burst(Vector2.ZERO,Color.RED,true);fx.flash(Color.RED)
	fx.heal_ring(Vector2.ZERO);fx.shield_ring(Vector2.ZERO)
	fx.streak(Vector2.ZERO,Vector2.ONE,Color.CYAN)
	fx.ultimate("ayla","water",Vector2.ZERO,Vector2.ONE)
	check(fx.bursts.is_empty() and fx.streaks.is_empty() and fx.rings.is_empty() and fx.ultimates.is_empty() and fx.flash_life==0,"reduced motion suppresses added movement")
	fx.reduced_motion=false
	fx.flash(Color.RED);fx.heal_ring(Vector2.ZERO);fx.clear_effects()
	check(not fx.is_processing() and fx.flash_life==0 and fx.rings.is_empty(),"navigation clears transient effects")
	for id in ["wolf","goblin","fire_imp","stone_golem","ice_wolf","thunder_hawk","dark_knight","boss_flame_lord","boss_storm_witch"]:
		var texture=load("res://assets/enemies/%s.png"%id)
		check(texture is Texture2D,"enemy sprite loads: "+id)
		if texture is Texture2D:
			check(texture.get_width()>200 and texture.get_height()>200,"enemy sprite has detail: "+id)
	check(load("res://assets/characters/kaldi-battle.png") is Texture2D,"Kaldi full-body sprite loads")
	fx.queue_free()
	await process_frame
	print("BATTLE PRESENTATION: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
