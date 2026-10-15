extends RefCounted
# Lädt Sprites aus res://assets/. Fehlt eine Datei, wird ein pinkes Platzhalter-Bild
# verwendet und eine Warnung ausgegeben - so stürzt das Spiel nie wegen eines Sprites ab.

const Parts = preload("res://scripts/parts.gd")

static var _cache: Dictionary = {}


static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			t = r
	if t == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.0, 1.0, 0.55))
		t = ImageTexture.create_from_image(img)
		push_warning("Sprite fehlt: " + path)
	_cache[path] = t
	return t


static func part_path(cat: String, level: int) -> String:
	return "res://assets/parts/%s_%d.png" % [cat, level]


static func flame_path(level: int) -> String:
	return "res://assets/fx/flame_%d.png" % level


# Zugeschnittenes Vorschaubild eines Raketenteils (für den Shop)
static func part_icon(cat: String, level: int) -> Texture2D:
	var at := AtlasTexture.new()
	at.atlas = tex(part_path(cat, level))
	at.region = Parts.ICON_REGION[cat]
	return at
