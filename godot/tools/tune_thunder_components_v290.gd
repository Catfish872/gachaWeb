extends "res://tools/audit_thunder_balance_v290.gd"
func metric()->Dictionary:
 var value:Dictionary=super.metric();value.components={};value.actionCounts={};return value
func accumulate(battle,stats:Dictionary,events:Array)->void:
 super.accumulate(battle,stats,events)
 for event in events:
  if event.get("type","")=="skill":stats.actionCounts[event.skill_id]=int(stats.actionCounts.get(event.skill_id,0))+1
  if event.get("type","")!="damage":continue
  var target:Dictionary=battle.get_unit(event.get("target",""))
  if target.is_empty() or target.isAlly:continue
  var key:String=str(event.get("skill_id",event.get("status","unknown")))+"/"+str(event.get("presentationStep","proc"))
  stats.components[key]=float(stats.components.get(key,0))+float(event.amount)
func run()->void:
 var basis:Dictionary=make_basis(290031)
 var configs:Array=[];var rows:Array=[]
 for floor_number in [10,50,100]:configs.append({"label":"abyss_"+str(floor_number),"config":{"isAbyss":true,"difficulty":3,"abyssGrowthVersion":3,"floor":floor_number,"enemies":["boss_flame_lord"],"seed":290031},"blessings":0 if floor_number==10 else 12 if floor_number==50 else 36})
 for rank in [0,3,5]:configs.append({"label":"extraction_"+str(rank),"config":extraction_config(290032,rank),"blessings":0 if rank==0 else 12})
 for rank in [0,6]:
  for scenario in configs:
   for team in AUDIT_TEAMS:
    var game=audit_game(basis,rank,team);var plan:Dictionary=audit_plan(game,scenario.blessings,team)
    rows.append({"team":team,"rank":rank,"scenario":scenario.label,"output":audit_output(game,plan.effects,scenario.config)})
   for id in ["raisa","kaldi","tiya"]:
    var game=Game.new("");prepare_characters(game,[id],rank);equip(game,id,basis.tiya,AUDIT_SETS[id])
    rows.append({"team":id,"rank":rank,"scenario":scenario.label,"output":audit_output(game,[],scenario.config)})
 var file=FileAccess.open("res://validation/v290-thunder/components.json",FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "))
 print("THUNDER_COMPONENTS ",rows.size()," rows");quit()
