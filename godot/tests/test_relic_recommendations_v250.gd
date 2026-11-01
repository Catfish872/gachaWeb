extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _init()->void:
	var g=Game.new("")
	var expected:Dictionary={"kaldi":"flame_oath","ember":"flame_oath","cinder":"flame_oath","gus":"thunder_hunt","bolt":"thunder_hunt","zeph":"wind_voyager","ayla":"aurora_prayer","shana":"aurora_prayer","tide":"star_watch","lorin":"stone_bastion"}
	var before:Dictionary=g.state.duplicate(true)
	var rng_before:int=g.rng.state
	for id in g.catalog.CharacterData:
		var entries:Array=g.relic_set_recommendations(id)
		ck(entries.size()==1,"one mechanism starting point "+id)
		var entry:Dictionary=entries[0]
		ck(entry.setId==expected[id] and entry.id==expected[id],"actual ID recommendation "+id)
		ck(entry.reason==g.catalog.CharacterData[id].relicObjective.recommendedSets[0].reason and not entry.reason.is_empty(),"reason comes from metadata "+id)
		ck(entry.bonuses==g.catalog.RelicSets[entry.setId].bonuses and entry.slotIcons==g.catalog.RelicSets[entry.setId].slotIcons,"exact effect and art source "+id)
		ck(entry.owned==g.state.ownedCharacters.has(id) and entry.equipEnabled==entry.owned and entry.advisory,"ownership and advisory contract "+id)
		entry.bonuses[0].description="caller change"
		entry.reason="caller change"
		ck(g.relic_set_recommendations(id)[0].bonuses[0].description!="caller change" and g.relic_set_recommendations(id)[0].reason!="caller change","read result cannot mutate catalog "+id)
	ck(g.relic_set_recommendations("missing").is_empty(),"unknown character returns empty")
	ck(g.state==before and g.rng.state==rng_before,"collection lookup leaves state and RNG unchanged")
	ck(not g.state.ownedCharacters.has("shana") and g.relic_set_recommendations("shana")[0].setId=="aurora_prayer","unowned Shana gets active-healing recommendation")
	var metadata:Dictionary=g.catalog.CharacterData.ember.relicObjective.duplicate(true)
	g.catalog.CharacterData.ember.relicObjective.recommendedSets=[{"setId":"stone_bastion","reason":"未来角色培养配置测试"},{"setId":"stone_bastion","reason":"重复"},{"setId":"missing","reason":"失效"}]
	ck(g.relic_set_recommendations("ember").size()==1 and g.relic_set_recommendations("ember")[0].setId=="stone_bastion","future metadata drives query without character mapping")
	g.catalog.CharacterData.ember.relicObjective.erase("recommendedSets")
	ck(g.relic_set_recommendations("ember").is_empty(),"missing metadata safe")
	g.catalog.CharacterData.ember.relicObjective=metadata
	print("RELIC RECOMMENDATIONS V250: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
