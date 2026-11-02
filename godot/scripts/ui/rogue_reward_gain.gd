extends PanelContainer
## Presentation only: the reward has already been committed by the model.
const Rarity=preload("res://scripts/ui/reward_rarity.gd")
const Runes=preload("res://scripts/ui/rune_theme.gd")
var app
var reward:Dictionary={}
var stack_count:=1
var remaining:=4.0
var on_dismiss:Callable
var origin_screen:=""
var origin_panel:=""
var origin_run:=""
var _closed:=false
var _held:=false
var _touch_id:=-1
var _dragged:=false
var _press:=Vector2.ZERO

static func show_gain(owner,reward_data:Dictionary,count:int,finished:Callable=Callable()) -> Control:
	var old=owner.get_node_or_null("RogueRewardGain")
	if is_instance_valid(old):old.dismiss(false)
	var card=load("res://scripts/ui/rogue_reward_gain.gd").new()
	card.configure(owner,reward_data,count,finished)
	owner.add_child(card)
	return card

func configure(owner,reward_data:Dictionary,count:int,finished:Callable) -> void:
	app=owner;reward=app._present_abyss_reward(reward_data);stack_count=count;on_dismiss=finished
	app.set_meta("rogue_gain_generation",int(app.get_meta("rogue_gain_generation",0))+1)
	name="RogueRewardGain";z_index=80;mouse_filter=Control.MOUSE_FILTER_STOP;focus_mode=Control.FOCUS_NONE
	origin_screen=str(app.current_screen);origin_panel=str(app.abyss_panel)
	origin_run=str(app.model.state.abyss.rogue.get("runId",""))
	remaining=clampf(2.8+str(reward.get("description","")).length()*.045,3.4,6.0)
	set_meta("reward_id",str(reward.get("id","")));set_meta("stack_count",count)
	var col=app._vbox(self,8)
	Rarity.decorate(app,self,col,str(reward.get("rarity","white")))
	var tier:Dictionary=Rarity.tier(str(reward.get("rarity","white")))
	var row=app._hbox(col,12)
	var icon=app._reward_art_icon(row,reward,44);icon.name="RogueRewardGainIcon"
	var copy=app._vbox(row,3);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._label(copy,"获得回响",12,app.MUTED).name="RogueRewardGainCaption"
	app._label(copy,str(reward.get("name","回响")),20,tier.color,true).name="RogueRewardGainName"
	var badge=app._panel(row,tier.color.darkened(.6),6)
	badge.size_flags_horizontal=Control.SIZE_SHRINK_END;badge.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	app._label(badge,"累计 %d 层" % count,14,tier.color).name="RogueRewardGainStacks"
	app._label(col,str(reward.get("description","")),14,app.TEXT,true).name="RogueRewardGainDescription"
	app._label(col,"轻点任意位置收起",11,app.MUTED).name="RogueRewardGainHint"
	_ignore_children(self)

func _ignore_children(node:Node) -> void:
	for child in node.get_children():
		if child is Control:child.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_ignore_children(child)

func _ready() -> void:
	_layout()
	if not app.extraction_reduced_motion:
		modulate.a=0.0
		var tween=create_tween();tween.tween_property(self,"modulate:a",1.0,.16)

func _layout() -> void:
	var safe:Rect2=app._usable_rect()
	var width:=minf(520,safe.size.x-32)
	custom_minimum_size.x=width
	size=Vector2(width,get_combined_minimum_size().y)
	position=Vector2(safe.get_center().x-width*.5,safe.position.y+minf(86,safe.size.y*.16))

func _process(delta:float) -> void:
	if _closed:return
	if not is_instance_valid(app) or str(app.current_screen)!=origin_screen or str(app.abyss_panel)!=origin_panel or str(app.model.state.abyss.rogue.get("runId",""))!=origin_run or app.overlay.get_child_count()>0:
		dismiss(false);return
	_layout()
	if bool(app.get_meta("application_paused",false)):
		_held=false;_touch_id=-1
		return
	if not _held:
		remaining-=delta
		if remaining<=0:dismiss(true)

func _claim_gesture() -> void:
	# Reward feedback owns the complete gesture, including taps outside the card.
	# Dismissing must never activate a purchase or choice underneath it.
	app._touch_scroll=null
	app._inertia_scroll=null
	app._scroll_velocity=0.0

func _input(event:InputEvent) -> void:
	if _closed:return
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or (event is InputEventMouseMotion and _held):
		get_viewport().set_input_as_handled()
		_handle_pointer(event)

func _gui_input(event:InputEvent) -> void:
	# Also supports direct GUI dispatch; normal pointer events are claimed in _input.
	_handle_pointer(event)
	accept_event()

func _handle_pointer(event:InputEvent) -> void:
	if event is InputEventMouse and event.device==-1:return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id==-1:
			_touch_id=event.index;_claim_gesture();_held=true;_dragged=false;_press=event.position
		elif not event.pressed and event.index==_touch_id:
			var tapped:bool=_held and not _dragged and event.position.distance_to(_press)<10
			_held=false;_touch_id=-1
			if tapped:dismiss.call_deferred(true)
	elif event is InputEventScreenDrag:
		if event.index==_touch_id and event.position.distance_to(_press)>10:_dragged=true
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:_claim_gesture();_held=true;_dragged=false;_press=event.position
		else:
			var tapped:bool=_held and not _dragged and event.position.distance_to(_press)<10
			_held=false
			if tapped:dismiss.call_deferred(true)
	elif event is InputEventMouseMotion and _held:
		if event.position.distance_to(_press)>10:_dragged=true

func dismiss(continue_run:bool=true) -> void:
	if _closed:return
	_closed=true
	name="RogueRewardGainRetiring"
	# Keep the node through input dispatch so this tap never reaches a lower button.
	queue_free()
	if continue_run and on_dismiss.is_valid():on_dismiss.call_deferred()
