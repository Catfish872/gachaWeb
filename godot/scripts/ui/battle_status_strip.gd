extends Control
## Fixed-height, pointer-transparent status summary. Details remain in unit inspection.
const Battle = preload("res://scripts/battle_model.gd")
const STRIP_HEIGHT := 26.0
const CELL_WIDTH := 58.0
const COMPACT_CELL_WIDTH := 44.0
const COMPACT_THRESHOLD := 220.0
const MAX_VISIBLE := 5
const DEFINITIONS := {
 "wind_armor":["破甲","防御力降低35%"],
 "wind_oath":["风誓","角色被动的贯穿追击倍率提高40%"],
 "ember_oath":["烬灯誓约","对燃烧目标伤害加深80%"],
 "ember_lantern_burn":["织焰","燃烧伤害提高40%"],
 "ember_lantern_direct":["引火","对燃烧目标的攻击和追击造成的伤害提高25%"],
 "burn":["燃烧","回合末按施加者攻击造成伤害"], "freeze":["冰冻","无法行动"],
 "stun":["眩晕","无法行动，防御降低30%"], "electrify":["感电","行动时可能跳过本次行动"],
 "poison":["中毒","战斗内永久叠层，层数越高伤害越高"], "regen":["再生","回合末恢复最大生命值8%"],
 "atk_up":["攻强","攻击力提升"], "def_up":["防强","防御力提升"],
 "spd_down":["减速","速度降低"], "shield":["护盾","吸收伤害"],
 "invincible":["无敌","免疫所有伤害"], "taunt":["嘲讽","强制敌方攻击此目标"],
 "bleed":["流血","持续流血伤害"], "vulnerable":["易伤","受到伤害提高"]
}
var states: Array = []
var visible_count := 0
var hidden_count := 0
var reduced_motion := false
var compact_mode := false
var cell_width := CELL_WIDTH
var _textures: Dictionary = {}

func _init() -> void:
 name = "BattleStatusStrip"
 custom_minimum_size = Vector2(0, STRIP_HEIGHT)
 size_flags_vertical = Control.SIZE_SHRINK_CENTER
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 clip_contents = true
 set_process(false)

func _ready() -> void:
 resized.connect(_refresh_capacity)
 _refresh_capacity()

static func status_description(state: Dictionary, data: Dictionary) -> String:
 var id := str(state.get("id", state.get("statusId", state.get("status", state.get("type", "unknown")))))
 if id == "shock": id = "electrify"
 if id == "wind_armor": return "防御力降低%d%%" % roundi(float(state.get("value",0.35))*100.0)
 if id == "wind_oath": return "角色被动的贯穿追击倍率提高%d%%" % roundi(float(state.get("value",0.40))*100.0)
 if id == "electrify":
  var chance: float = Battle.electrify_chance_for_status(data, state)
  return "每次行动时有 %s%% 概率跳过本次行动" % ("%.1f" % (chance * 100.0)).trim_suffix(".0")
 return str(DEFINITIONS.get(id, [id, "状态效果"])[1])

func configure(statuses: Array, motion_reduced: bool = false, data: Dictionary = {}) -> void:
 if data.is_empty():
  var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
  if parsed is Dictionary: data = parsed
 reduced_motion = motion_reduced
 states = statuses.duplicate(true)
 # The model stores each poison layer independently; show one readable stack badge.
 var grouped: Array = []
 var poison_index := -1
 for state in states:
  if status_id(state) == "poison":
   if poison_index >= 0:
    var stack: Dictionary = grouped[poison_index]
    stack.stacks = int(stack.get("stacks", 1)) + int(state.get("stacks", 1))
    stack.persistent = bool(stack.get("persistent", false)) or bool(state.get("persistent", false))
    stack.max_duration = maxi(int(stack.get("max_duration", stack.get("duration", 0))), int(state.get("duration", 0)))
    stack.duration = mini(int(stack.get("duration", 0)), int(state.get("duration", 0)))
    continue
   poison_index = grouped.size()
  grouped.append(state)
 states = grouped
 var descriptions := PackedStringArray()
 for state in states:
  var id := status_id(state)
  var definition: Array = DEFINITIONS.get(id, [id, "状态效果"])
  var persistent := bool(state.get("persistent", false))
  var duration := "持续生效" if persistent else "剩余%d回合" % int(state.get("duration", state.get("turns", 0)))
  var detail := "%s：%s；%d层；%s" % [definition[0], status_description(state, data), int(state.get("stacks", 1)), duration]
  if id == "shield": detail += "；耐久%d" % int(state.get("shieldHp", 0))
  if state.get("value") != null and id in ["atk_up", "def_up", "spd_down", "vulnerable"]: detail += "（%d%%）" % roundi(float(state.value)*100)
  descriptions.append(detail)
  if not _textures.has(id):
   var asset := id if DEFINITIONS.has(id) else "unknown"
   var path := "res://assets/content_v280/icons/status/%s.png" % asset if id in ["wind_armor", "wind_oath"] else "res://assets/ui/status/%s.svg" % asset
   _textures[id] = load(path) if ResourceLoader.exists(path) else load("res://assets/ui/status/unknown.svg")
 tooltip_text = "\n".join(descriptions)
 _refresh_capacity()

func set_states(statuses: Array, motion_reduced: bool = false, data: Dictionary = {}) -> void:
 configure(statuses, motion_reduced, data)

func status_id(state: Dictionary) -> String:
 var id := str(state.get("id", state.get("statusId", state.get("status", state.get("type", "unknown")))))
 return "electrify" if id == "shock" else id

func counter_text(state: Dictionary) -> String:
 if bool(state.get("persistent", false)):
  if status_id(state) == "poison": return "%d·∞" % int(state.get("stacks", 1))
  return str(int(state.get("shieldHp", 0))) if status_id(state) == "shield" else "∞"
 var turns := str(int(state.get("duration", state.get("turns", 0))))
 if int(state.get("max_duration", 0)) > int(state.get("duration", 0)): turns += "+"
 return "%s·%s" % [int(state.get("stacks", 1)), turns] if int(state.get("stacks", 1)) > 1 else turns

func compact_counter_text(state: Dictionary) -> String:
 if bool(state.get("persistent", false)): return "∞"
 var turns := int(state.get("duration", state.get("turns", 0)))
 if turns > 9: return "9+"
 return str(turns) + ("+" if int(state.get("max_duration", 0)) > turns else "")

func _refresh_capacity() -> void:
 compact_mode = size.x < COMPACT_THRESHOLD
 cell_width = COMPACT_CELL_WIDTH if compact_mode else CELL_WIDTH
 var overflow_width := 22.0 if compact_mode else 26.0
 var capacity := mini(MAX_VISIBLE, maxi(0, floori(size.x / cell_width)))
 visible_count = mini(states.size(), capacity)
 if states.size() > capacity: visible_count = maxi(0, mini(MAX_VISIBLE, floori((size.x-overflow_width)/cell_width)))
 hidden_count = states.size()-visible_count
 queue_redraw()

func _draw() -> void:
 var font := get_theme_default_font()
 for i in range(visible_count):
  var state: Dictionary = states[i]
  var x := float(i)*cell_width
  draw_style_box(_chip_style(), Rect2(x, 1, cell_width-3, 24))
  var texture: Texture2D = _textures.get(status_id(state))
  if texture: draw_texture_rect(texture, Rect2(x+3, 4, 18, 18), false)
  if status_id(state) == "poison" and bool(state.get("persistent", false)):
   var stack_text := str(int(state.get("stacks", 1)))
   draw_string(font, Vector2(x+23, 12), stack_text, HORIZONTAL_ALIGNMENT_LEFT, cell_width-26, 10 if stack_text.length() < 4 else 8, Color("ffd99c"))
   draw_string(font, Vector2(x+23, 23), "∞", HORIZONTAL_ALIGNMENT_LEFT, cell_width-26, 10, Color("e0e8f0"))
  elif compact_mode:
   # Main glyph stays 18px; the right corner separates gold stacks from turn count.
   var stacks := int(state.get("stacks", 1))
   if stacks > 1:
    draw_string(font, Vector2(x+21, 10), str(stacks), HORIZONTAL_ALIGNMENT_LEFT, 21, 10 if stacks < 1000 else 8, Color("ffd99c"))
   draw_string(font, Vector2(x+21, 22 if stacks > 1 else 18), compact_counter_text(state), HORIZONTAL_ALIGNMENT_LEFT, 21, 9, Color("e0e8f0"))
  else:
   draw_string(font, Vector2(x+24, 18), counter_text(state), HORIZONTAL_ALIGNMENT_LEFT, CELL_WIDTH-27, 9 if counter_text(state).length() > 4 else 11, Color("e0e8f0"))
 if hidden_count > 0:
  draw_string(font, Vector2(visible_count*cell_width+1,18), "+%d"%hidden_count, HORIZONTAL_ALIGNMENT_LEFT, 25, 11, Color("c4d9e5"))

func _chip_style() -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = Color("172534")
 style.set_corner_radius_all(4)
 return style
