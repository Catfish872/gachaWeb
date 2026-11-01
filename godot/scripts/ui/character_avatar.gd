extends RefCounted
## Curated source-space portraits. Original full-body art remains unchanged.
## Faces are inspected individually; this is not a shared top-center guess.

const FACE_REGIONS := {
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
	return "res://assets/characters/%s.png" % ("kaldi-battle" if id == "kaldi" else id)

static func region_for(id: String, mode: String = "face") -> Rect2:
	var regions: Dictionary = BUST_REGIONS if mode == "bust" else FACE_REGIONS
	return regions.get(id, Rect2())

static func get_texture(id: String, mode: String = "face") -> Texture2D:
	if not FACE_REGIONS.has(id): return null
	var key := id + ":" + ("bust" if mode == "bust" else "face")
	if _cache.has(key): return _cache[key]
	var path := source_path(id)
	if not ResourceLoader.exists(path): return null
	var source: Texture2D = load(path)
	if source == null: return null
	var region := region_for(id, mode)
	if not Rect2(Vector2.ZERO, source.get_size()).encloses(region): return null
	var avatar := AtlasTexture.new()
	avatar.atlas = source
	avatar.region = region
	avatar.filter_clip = true
	_cache[key] = avatar
	return avatar
