extends SceneTree
const Fx = preload("res://scripts/ui/battle_fx.gd")
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const OUT := "res://validation/v283-limited-fx/"
var checks := 0
var failures := 0
var app

func _initialize() -> void: call_deferred("run")
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	ck(root.get_texture().get_image().save_png(OUT+name+".png") == OK, "save "+name)
func label_at(parent: Node, title: String, at: Vector2) -> void:
	var label := Label.new()
	parent.add_child(label); label.position = at; label.text = title
	label.add_theme_font_override("font", load("res://assets/fonts/NotoSansSC.otf"))
	label.add_theme_font_size_override("font_size", 16)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	app = load("res://main.tscn").instantiate(); root.add_child(app); await frames(8); app.set_process(false)
	app.sound_enabled = false; app.music_enabled = false; app.preferred_battle_auto = false
	app.extraction_reduced_motion = false; app.fx.reduced_motion = false
	var g = Game.new("")
	for id in ["tiya", "lumi"]:
		var index := 0
		for sid in g.catalog.CharacterData[id].skills:
			var skill: Dictionary = g.catalog.SkillData[sid]
			ck(not "基础回能" in skill.description and not "冷却" in skill.description and not "消耗" in skill.description, sid+" description contains mechanics without duplicate resource footer")
			ck(int(skill.energyGain) == [15,20,0][index] and int(skill.cooldown) == [0,3,0][index] and int(skill.energyCost) == [0,0,100][index], sid+" resource parameters unchanged")
			ck(skill.onHitPerActionTarget, sid+" multi-hit passive policy retained")
			var hits: Array = skill.effects.filter(func(e): return e.type == "damage")
			var expected: float = {"tiya":[.6,.45,1.4],"lumi":[.55,.4,.9]}[id][index]
			ck(hits.size() == 2 and is_equal_approx(float(hits[0].multiplier),expected) and is_equal_approx(float(hits[1].multiplier),expected), sid+" native hit multipliers unchanged")
			index += 1
	for sid in Fx.SKILL_IMPACTS:
		var event := {"skill_id":sid,"element":"wind"}
		ck(app._battle_visual_kind(event) == Fx.SKILL_IMPACTS[sid], sid+" visual route")
	ck(app._battle_effect_kind({"skill_id":"tiya_normal","element":"wind"}) == "slash", "wind blade audio fallback stays slash")
	ck(app._battle_effect_kind({"skill_id":"kaldi_normal","element":"fire"}) == "slash", "existing slash audio remains")
	var probe := Fx.new(); root.add_child(probe)
	for kind in Fx.SIGNATURE_COLORS:
		probe.impact(kind,Vector2.ZERO,Vector2(90,70))
		ck(probe.impacts.back().kind == kind, kind+" has a distinct supported silhouette")
	for i in 80: probe.impact("wind_blades",Vector2.ZERO,Vector2.ONE); probe.ultimate("tiya","wind",Vector2.ZERO,Vector2.ONE)
	ck(probe.impacts.size() == 24 and probe.ultimates.size() == 4 and probe.bursts.size() <= 160, "existing effect budgets apply to new signatures")
	probe._process(2.0)
	ck(probe.impacts.is_empty() and probe.ultimates.is_empty() and not probe.is_processing(), "new signatures expire and stop processing")
	probe.reduced_motion = true
	for kind in Fx.SIGNATURE_COLORS: probe.impact(kind,Vector2.ZERO,Vector2.ONE)
	for id in ["kaldi","selin","tiya","lumi"]: probe.ultimate(id,"wind",Vector2.ZERO,Vector2.ONE)
	ck(probe.impacts.is_empty() and probe.ultimates.is_empty() and not probe.is_processing(), "reduced motion suppresses all new signatures")
	probe.reduced_motion = false; probe.impact("wind_armor",Vector2.ZERO,Vector2.ONE); probe.clear_effects()
	ck(probe.impacts.is_empty() and not probe.is_processing(), "navigation clears signature queues")
	probe.free()
	root.size = Vector2i(960,540); root.content_scale_size = Vector2i(960,540); await frames()
	for id in ["kaldi","selin","tiya","lumi"]:
		app.model = Game.new(""); app.model.state.ownedCharacters[id] = app.model.default_character()
		app.model.state.team = [id]; app.battle = Battle.new(app.model.catalog)
		app._start_battle({"enemies":["wolf","goblin","stone_golem"],"seed":28301}); app.set_process(false); await frames()
		for enemy in app.battle.state.enemies: enemy.maxHp=1000000; enemy.currentHp=1000000; enemy.stats.maxHp=1000000
		var caster: Dictionary = app.battle.state.allies[0]
		for sid in app.model.catalog.CharacterData[id].skills:
			app.fx.clear_effects(); app.battle._events=[]
			app.battle._execute_skill(caster,sid,app.battle.state.enemies[0].uid)
			var events: Array = app.battle._events.duplicate(true)
			var state_before: Dictionary = app.battle.state.duplicate(true)
			await app._show_combat_events(events)
			ck(app.fx.impacts.any(func(e): return e.kind == Fx.SKILL_IMPACTS[sid]), sid+" actual combat event uses signature")
			ck(app.battle.state == state_before, sid+" presentation leaves combat state unchanged")
			if sid.ends_with("_ult"):
				ck(app.fx.ultimates.size() == 1 and app.fx.ultimates[0].actor == id, id+" one character ultimate per action")
				app.fx.set_process(false)
				for effect in app.fx.impacts: effect.life=.31
				for effect in app.fx.ultimates: effect.life=.55
				app.fx.queue_redraw(); await frames(2)
				if id in ["tiya","lumi"]: await capture(id+"-combat-960")
		app.battle_settled = true; app.navigate("home"); await frames(2)
		ck(app.fx.impacts.is_empty() and app.fx.ultimates.is_empty(), id+" return clears battle effects")
	app.queue_free(); await frames(3)
	root.size = Vector2i(1280,760); root.content_scale_size = Vector2i(1280,760)
	var atlas := Control.new(); root.add_child(atlas); atlas.size=Vector2(1280,760)
	var background := ColorRect.new(); atlas.add_child(background); background.color=Color("101d29"); background.size=atlas.size
	label_at(atlas,"限定角色技能特效 · 普通攻击 / 战技 / 终结技",Vector2(24,12))
	var row := 0
	for id in ["kaldi","selin","tiya","lumi"]:
		var column := 0
		for sid in g.catalog.CharacterData[id].skills:
			var cell := Control.new(); atlas.add_child(cell); cell.position=Vector2(16+column*420,44+row*176); cell.size=Vector2(410,168)
			var fx := Fx.new(); cell.add_child(fx); fx.size=cell.size
			label_at(cell,str(g.catalog.CharacterData[id].name)+" · "+str(g.catalog.SkillData[sid].name),Vector2(8,2))
			var origin := Vector2(28,96); var target := Vector2(306,96)
			if sid.ends_with("_ult"):
				fx.ultimate(id,str(g.catalog.CharacterData[id].element),origin,target)
				for effect in fx.ultimates: effect.life=.55
			else:
				fx.impact(fx.skill_impact_kind(sid),origin,target)
				for effect in fx.impacts: effect.life=.31
			fx.set_process(false); fx.queue_redraw()
			column += 1
		row += 1
	await frames(3); await capture("limited-signatures-atlas")
	atlas.queue_free(); await frames(2)
	print("LIMITED FX V283: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
