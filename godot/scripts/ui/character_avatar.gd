extends RefCounted
## Curated source-space portraits. Bust regions are composition anchors only.
## Faces are inspected individually; this is not a shared top-center guess.

const FACE_REGIONS := {
	# These two regions use their dedicated 512px portrait assets, framing
	# the head rather than shrinking their extra shoulders into small avatars.
	"tiya": Rect2(70, 0, 360, 360),
	"lumi": Rect2(55, 0, 390, 390),
	"shana": Rect2(350, 35, 390, 390),
	"tide": Rect2(340, 85, 370, 370),
	"bolt": Rect2(310, 35, 380, 380),
	"ayla": Rect2(300, 0, 410, 410),
	"gus": Rect2(340, 0, 390, 390),
	"ember": Rect2(370, 0, 380, 380),
	"kaldi": Rect2(330, 0, 430, 430),
	"lorin": Rect2(350, 0, 390, 390),
	"cinder": Rect2(340, 0, 420, 420),
	"zeph": Rect2(290, 0, 490, 490),
}
const BUST_REGIONS := {
	# Match the legacy upper-body framing: crown through waist, centered on the face.
	# Keep the dedicated face asset and battle/full-body source independent.
	"selin": Rect2(175, 0, 650, 650),
	"tiya": Rect2(250, 25, 650, 650),
	"lumi": Rect2(145, 25, 650, 650),
	"shana": Rect2(235, 25, 600, 650),
	"tide": Rect2(215, 65, 600, 650),
	"bolt": Rect2(200, 20, 600, 650),
	"ayla": Rect2(205, 0, 600, 650),
	"gus": Rect2(220, 0, 600, 650),
	"ember": Rect2(240, 0, 600, 650),
	"kaldi": Rect2(230, 0, 600, 650),
	"lorin": Rect2(220, 0, 600, 650),
	"cinder": Rect2(240, 0, 600, 650),
	"zeph": Rect2(200, 0, 650, 700),
}
static var _cache: Dictionary = {}

static func source_path(id: String) -> String:
	if id == "selin":return "res://assets/content_v270/characters/selin.png"
	if id in ["tiya", "lumi"]:return "res://assets/content_v280/characters/%s.png" % id
	return "res://assets/characters/%s.png" % ("kaldi-battle" if id == "kaldi" else id)

static func region_for(id: String, mode: String = "face") -> Rect2:
	var regions: Dictionary = BUST_REGIONS if mode == "bust" else FACE_REGIONS
	return regions.get(id, Rect2())

static func get_texture(id: String, mode: String = "face") -> Texture2D:
	if id == "selin" and mode == "face":
		var path := "res://assets/content_v270/portraits/selin_face.png"
		return load(path) if ResourceLoader.exists(path) else null
	var regions: Dictionary = BUST_REGIONS if mode == "bust" else FACE_REGIONS
	if not regions.has(id): return null
	var key := id + ":" + ("bust" if mode == "bust" else "face")
	if _cache.has(key): return _cache[key]
	var path := source_path(id)
	if id in ["tiya", "lumi"] and mode == "face":path = "res://assets/content_v280/portraits/%s.png" % id
	if not ResourceLoader.exists(path): return null
	var source: Texture2D = load(path)
	if source == null: return null
	if mode == "bust":
		_cache[key] = source
		return source
	var region := region_for(id, mode)
	if not Rect2(Vector2.ZERO, source.get_size()).encloses(region): return null
	var avatar := AtlasTexture.new()
	avatar.atlas = source
	avatar.region = region
	avatar.filter_clip = true
	_cache[key] = avatar
	return avatar
