extends RefCounted
# Shared visual contract for actual model rarity; no probability or power edits.
class Frame extends Control:
 var rank:int=0
 var tint:Color=Color.WHITE
 func _ready():
  mouse_filter=Control.MOUSE_FILTER_IGNORE
  resized.connect(queue_redraw)
 func _draw():
  var inset:=-8.0
  var length:=14.0+rank*5.0
  for corner in [Vector2(inset,inset),Vector2(size.x-inset,inset),Vector2(inset,size.y-inset),Vector2(size.x-inset,size.y-inset)]:
   var dx:=1.0 if corner.x<size.x*.5 else -1.0
   var dy:=1.0 if corner.y<size.y*.5 else -1.0
   draw_line(corner,corner+Vector2(dx*length,0),tint,1.0+rank*.5,true)
   draw_line(corner,corner+Vector2(0,dy*length),tint,1.0+rank*.5,true)
   if rank>=1:draw_line(corner+Vector2(dx*5,dy*12),corner+Vector2(dx*12,dy*5),tint,1.0,true)
  if rank>=2:
   var c:=Vector2(size.x*.5,-7)
   draw_polyline(PackedVector2Array([c+Vector2(-12,0),c+Vector2(0,6),c+Vector2(12,0)]),tint,2,true)
static func tier(rarity:String)->Dictionary:
 match rarity.to_lower():
  'gold','legendary','legend','5':return {'rank':2,'label':'传说','color':Color('e8bd70'),'icon':'crown'}
  'purple','epic','4':return {'rank':2,'label':'史诗','color':Color('c1a1ed'),'icon':'star'}
  'blue','rare','3':return {'rank':1,'label':'稀有','color':Color('79bcea'),'icon':'gem'}
  _:return {'rank':0,'label':'普通','color':Color('abb6c5'),'icon':'check'}
static func decorate(app,panel:PanelContainer,content:VBoxContainer,rarity:String)->void:
 if panel.has_meta('reward_rarity'):return
 var data:=tier(rarity)
 var color:Color=data.color
 panel.set_meta('reward_rarity',rarity)
 var style:=StyleBoxFlat.new()
 style.bg_color=Color('111b2b').lerp(color,.035+.025*int(data.rank))
 style.border_color=color.darkened(.25)
 style.set_border_width_all(1+int(data.rank))
 style.set_corner_radius_all(8)
 style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=12;style.content_margin_bottom=12
 panel.add_theme_stylebox_override('panel',style)
 var badge:=HBoxContainer.new();badge.name='RewardRarityBadge';badge.add_theme_constant_override('separation',6)
 content.add_child(badge);content.move_child(badge,0)
 app._rune_icon(badge,str(data.icon),16,color)
 var text=app._label(badge,str(data.label),12,color)
 text.name='RewardRarityLabel';text.tooltip_text='回响品质'
 var bar:=Control.new();bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;badge.add_child(bar)
 for i in range(int(data.rank)+1):
  var pip:=ColorRect.new();pip.color=color;pip.custom_minimum_size=Vector2(4,10);pip.size_flags_vertical=Control.SIZE_SHRINK_CENTER;pip.mouse_filter=Control.MOUSE_FILTER_IGNORE;badge.add_child(pip)
 var trim:=Frame.new();trim.rank=int(data.rank);trim.tint=Color(color,.75)
 trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 # Zero-minimum overlay shares the panel content rectangle without adding a VBox row.
 panel.add_child(trim)
 trim.mouse_filter=Control.MOUSE_FILTER_IGNORE
