extends Node2D
# Zeichnet eine Rakete aus übereinandergelegten Sprites (ein Sprite pro Teil und Stufe).
# Sprites: res://assets/parts/<kategorie>_<stufe>.png (160x240, Mittelpunkt = Drehpunkt)
# Flammen: res://assets/fx/flame_<düsenstufe>.png

const Parts = preload("res://scripts/parts.gd")
const Assets = preload("res://scripts/assets.gd")
const Cfg = preload("res://scripts/config.gd")

const SPRITE_SCALE := 0.6
const NOZZLE_Y := 52.0       # Ort der Düsenöffnung (unterhalb der Mitte)

var is_remote := false       # Fremde Spieler werden weich zur Serverposition bewegt
var body: Node2D
var layers: Dictionary = {}
var flame: Sprite2D
var retro_l: Sprite2D
var retro_r: Sprite2D
var chute_sprite: Sprite2D
var shield_sprite: Sprite2D
var name_label: Label

var levels: Dictionary = {}
var nozzle_level := 0
var thrust := 0.0            # 1 = Hauptschub, -1 = Bremsschub, 0 = aus
var chute_on := false
var shield_on := false
var boost_on := false
var _t := 0.0

# Für fremde Spieler (Interpolation)
var target_pos := Vector2.ZERO
var target_rot := 0.0
var target_vel := Vector2.ZERO
var snap_time := 0.0
var has_state := false
var landed_flag := false
var emp_on := false
var base_name := ""
var faction := -1


func _init() -> void:
	body = Node2D.new()
	add_child(body)

	chute_sprite = Sprite2D.new()
	chute_sprite.texture = Assets.tex("res://assets/fx/parachute.png")
	chute_sprite.centered = false
	var cw := float(chute_sprite.texture.get_width())
	var ch := float(chute_sprite.texture.get_height())
	chute_sprite.offset = Vector2(-cw / 2.0, -ch)
	chute_sprite.position = Vector2(0, -52)
	chute_sprite.scale = Vector2.ONE * 0.75
	chute_sprite.visible = false
	body.add_child(chute_sprite)

	flame = _make_flame()
	body.add_child(flame)
	retro_l = _make_flame()
	retro_r = _make_flame()
	for r in [retro_l, retro_r]:
		r.rotation = PI
		r.scale = Vector2(0.2, 0.2)
		r.visible = false
		body.add_child(r)
	retro_l.position = Vector2(-9, -38)
	retro_r.position = Vector2(9, -38)

	for cat in Parts.DRAW_ORDER:
		var sp := Sprite2D.new()
		sp.scale = Vector2.ONE * SPRITE_SCALE
		body.add_child(sp)
		layers[cat] = sp

	shield_sprite = Sprite2D.new()
	shield_sprite.texture = Assets.tex("res://assets/fx/shield.png")
	shield_sprite.scale = Vector2.ONE * (130.0 / float(shield_sprite.texture.get_width()))
	shield_sprite.visible = false
	body.add_child(shield_sprite)

	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(200, 0)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.position = Vector2(-100, -100)
	name_label.pivot_offset = Vector2(100, 50)
	add_child(name_label)

	set_levels(Parts.default_levels())


func _make_flame() -> Sprite2D:
	var f := Sprite2D.new()
	f.texture = Assets.tex(Assets.flame_path(0))
	f.centered = false
	f.offset = Vector2(-f.texture.get_width() / 2.0, 0)
	f.position = Vector2(0, NOZZLE_Y - 8.0)
	f.visible = false
	return f


func set_levels(lv: Dictionary) -> void:
	levels = lv.duplicate()
	for cat in Parts.DRAW_ORDER:
		var sp: Sprite2D = layers[cat]
		sp.texture = Assets.tex(Assets.part_path(cat, int(lv.get(cat, 0))))
	nozzle_level = int(lv.get("nozzle", 0))
	var ftex := Assets.tex(Assets.flame_path(nozzle_level))
	flame.texture = ftex
	flame.offset = Vector2(-ftex.get_width() / 2.0, 0)
	retro_l.texture = ftex
	retro_r.texture = ftex
	retro_l.offset = Vector2(-ftex.get_width() / 2.0, 0)
	retro_r.offset = Vector2(-ftex.get_width() / 2.0, 0)


# Lackierung: färbt nur Rumpf/Nase/Tank/Flügel/Beine; Motor, Düse und Waffe bleiben eigenfarbig.
func set_paint(idx: int) -> void:
	var c := Color(1.0, 1.0, 1.0)
	if idx >= 0 and idx < Parts.PAINTS.size():
		c = Parts.PAINTS[idx]["color"]
	for cat in ["hull", "nose", "tank", "fins", "legs", "weapon"]:
		if layers.has(cat):
			layers[cat].modulate = c


func set_player_name(n: String) -> void:
	base_name = n
	_refresh_label()


# Fraktion: Kürzel vor dem Namen und Namensfarbe
func set_faction(f: int) -> void:
	faction = f
	_refresh_label()


func _refresh_label() -> void:
	if faction >= 0 and faction < Cfg.FACTIONS.size():
		var fd: Dictionary = Cfg.FACTIONS[faction]
		name_label.text = "[%s] %s" % [fd["short"], base_name]
		name_label.add_theme_color_override("font_color", fd["color"])
	else:
		name_label.text = base_name
		name_label.add_theme_color_override("font_color", Color.WHITE)


func set_body_rotation(r: float) -> void:
	body.rotation = r


# Skaliert das Namensschild gegen den Kamera-Zoom, damit es lesbar bleibt.
func set_label_zoom(z: float) -> void:
	var s := clampf(1.0 / maxf(z, 0.05), 0.8, 3.5)
	name_label.scale = Vector2(s, s)
	name_label.position = Vector2(-100, -70.0 - 40.0 * s)


func apply_flags(flags: int) -> void:
	if flags & 1:
		thrust = 1.0
	elif flags & 2:
		thrust = -1.0
	else:
		thrust = 0.0
	chute_on = (flags & 4) != 0
	shield_on = (flags & 8) != 0
	boost_on = (flags & 16) != 0
	landed_flag = (flags & 64) != 0
	emp_on = (flags & 128) != 0


# ------------------------------------------------ Fremde Spieler
func remote_update(pos: Vector2, rot: float, vel: Vector2) -> void:
	target_pos = pos
	target_rot = rot
	target_vel = vel
	snap_time = Time.get_ticks_msec() / 1000.0
	if not has_state:
		has_state = true
		position = pos
		body.rotation = rot


func _process(delta: float) -> void:
	_t += delta

	if is_remote and has_state:
		var age := clampf(Time.get_ticks_msec() / 1000.0 - snap_time, 0.0, 0.25)
		var predicted := target_pos + target_vel * age
		var k := 1.0 - exp(-18.0 * delta)
		if position.distance_to(predicted) > 400.0:
			position = predicted
		else:
			position = position.lerp(predicted, k)
		body.rotation = lerp_angle(body.rotation, target_rot, k)

	# ---- Flammen
	var flick := 1.0 + 0.10 * sin(_t * 43.0) + 0.07 * sin(_t * 71.0)
	var size_mul := 0.45 + 0.07 * float(nozzle_level)
	if boost_on:
		size_mul *= 1.5
	flame.visible = thrust > 0.0
	if flame.visible:
		flame.scale = Vector2(size_mul * (1.0 + 0.05 * flick), size_mul * flick)
		flame.modulate = Color(1.3, 1.15, 1.0) if boost_on else Color.WHITE
	var retro_on := thrust < 0.0
	retro_l.visible = retro_on
	retro_r.visible = retro_on
	if retro_on:
		var rs := 0.2 * flick
		retro_l.scale = Vector2(rs, rs)
		retro_r.scale = Vector2(rs, rs)

	body.modulate = Color(0.55, 0.65, 1.0) if emp_on and int(_t * 8.0) % 2 == 0 else Color.WHITE

	# ---- Fallschirm / Schild
	chute_sprite.visible = chute_on
	if chute_on:
		chute_sprite.rotation = sin(_t * 1.6) * 0.05
	shield_sprite.visible = shield_on
	if shield_on:
		shield_sprite.modulate.a = 0.6 + 0.25 * sin(_t * 6.0)
