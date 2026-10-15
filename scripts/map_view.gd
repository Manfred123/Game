extends Control
# Große Karte (Taste M). Standard: deckend. Knopf oben rechts schaltet auf durchsichtig um.
# Mausrad = zoomen, mit gedrückter Maustaste ziehen = verschieben, C = auf mich zentrieren.
# Spieler werden als ihre echte Rakete (mit ihren Teilen) dargestellt.

const Cfg = preload("res://scripts/config.gd")
const Parts = preload("res://scripts/parts.gd")
const Assets = preload("res://scripts/assets.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

const ZOOM_MIN := 0.003
const ZOOM_MAX := 0.8
const ROCKET_MAP_SCALE := 0.3         # Größe der Raketen-Symbole auf der Karte

var game = null                       # muss get_map_players() -> Array anbieten
var center := Vector2.ZERO
var zoom := 0.012
var dragging := false
var transparent := false
var font: Font
var see_btn: Button


func _ready() -> void:
	UiTheme.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	visible = false
	font = ThemeDB.fallback_font

	# Werkzeugleiste oben rechts
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -520.0
	bar.offset_right = -16.0
	bar.offset_top = 14.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	see_btn = Button.new()
	see_btn.focus_mode = Control.FOCUS_NONE
	see_btn.pressed.connect(_toggle_transparent)
	bar.add_child(see_btn)
	var center_btn := Button.new()
	center_btn.text = "Auf mich zentrieren"
	center_btn.focus_mode = Control.FOCUS_NONE
	center_btn.pressed.connect(recenter)
	bar.add_child(center_btn)
	var close_btn := UiTheme.accent_button("Schließen (M)")
	close_btn.pressed.connect(close)
	bar.add_child(close_btn)
	_update_button()


func _update_button() -> void:
	see_btn.text = "Deckend schalten" if transparent else "Durchsichtig schalten"


func _toggle_transparent() -> void:
	transparent = not transparent
	_update_button()


func open(at: Vector2) -> void:
	center = at
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	dragging = false


func recenter() -> void:
	if game == null:
		return
	for p in game.get_map_players():
		if p["me"]:
			center = p["pos"]


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _w2s(w: Vector2) -> Vector2:
	return (w - center) * zoom + size / 2.0


func _s2w(s: Vector2) -> Vector2:
	return (s - size / 2.0) / zoom + center


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _s2w(screen_pos)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var after := _s2w(screen_pos)
	center += before - after


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.2)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mb.pressed
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		center -= mm.relative / zoom
		accept_event()


func _text(pos: Vector2, text: String, col: Color, fsize: int = 16, width: float = 200.0) -> void:
	var p := pos + Vector2(-width / 2.0, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, 5, Color.BLACK)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, col)


func _draw_rocket(pos: Vector2, rot: float, levels: Dictionary) -> void:
	draw_set_transform(pos, rot, Vector2.ONE)
	for cat in Parts.DRAW_ORDER:
		var tex := Assets.tex(Assets.part_path(cat, int(levels.get(cat, 0))))
		var sz := Vector2(tex.get_width(), tex.get_height()) * ROCKET_MAP_SCALE
		draw_texture_rect(tex, Rect2(-sz / 2.0, sz), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var sz := size
	var bg := Color(0.02, 0.035, 0.08, 0.32) if transparent else Color(0.02, 0.035, 0.08, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), bg)
	if not transparent:
		var st := Assets.tex("res://assets/world/stars_far.png")
		draw_texture_rect(st, Rect2(Vector2.ZERO, sz), true, Color(1, 1, 1, 0.55))

	# --- Gitter
	var grid := 10000.0
	while grid * zoom < 60.0:
		grid *= 5.0
	var top_left := _s2w(Vector2.ZERO)
	var bottom_right := _s2w(sz)
	var gx := floorf(top_left.x / grid) * grid
	while gx < bottom_right.x:
		var sx := _w2s(Vector2(gx, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, sz.y), Color(1, 1, 1, 0.05), 1.0)
		gx += grid
	var gy := floorf(top_left.y / grid) * grid
	while gy < bottom_right.y:
		var sy := _w2s(Vector2(0, gy)).y
		draw_line(Vector2(0, sy), Vector2(sz.x, sy), Color(1, 1, 1, 0.05), 1.0)
		gy += grid

	draw_arc(_w2s(Vector2.ZERO), Cfg.WORLD_RADIUS * zoom, 0.0, TAU, 160, Color(0.9, 0.3, 0.3, 0.5), 2.0)

	# --- Planeten
	var disc: Dictionary = {"planets": [], "pois": []}
	if game != null:
		disc = game.get_discovery()
	for i in Cfg.PLANETS.size():
		var pl: Dictionary = Cfg.PLANETS[i]
		var wpos: Vector2 = pl["pos"]
		var p := _w2s(wpos)
		var r: float = maxf(float(pl["radius"]) * zoom, 9.0)
		var known: bool = (disc["planets"] as Array).has(i)
		if known:
			var grange: float = float(pl["range"]) * zoom
			if grange > 14.0:
				draw_arc(p, grange, 0.0, TAU, 64, Color(1, 1, 1, 0.14), 1.0)
			draw_texture_rect(Assets.tex(pl["tex"]), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false)
			_text(p + Vector2(0, -r - 8.0), str(pl["name"]), Color(1, 1, 1), 17)
			var y_off := r + 20.0
			if int(pl["reward"]) > 0 and r > 10.0:
				_text(p + Vector2(0, y_off), "Landeprämie %d" % int(pl["reward"]), UiTheme.GOLD, 13)
				y_off += 16.0
			if i > 0 and game != null:
				var owners: Array = game.fstate.get("planet_owner", [])
				var prog: Array = game.fstate.get("planet_progress", [])
				var prog_f: Array = game.fstate.get("planet_progress_faction", [])
				var owner: int = int(owners[i]) if i < owners.size() else -1
				if owner >= 0:
					var fcol: Color = Cfg.FACTIONS[owner]["color"]
					draw_arc(p, r + 6.0, 0.0, TAU, 48, fcol, 3.0)
					_text(p + Vector2(0, y_off), "Außenposten: %s" % Cfg.FACTIONS[owner]["short"], fcol, 13)
				else:
					var pf: int = int(prog_f[i]) if i < prog_f.size() else -1
					var pp: float = float(prog[i]) if i < prog.size() else 0.0
					if pf >= 0 and pp > 0.02:
						var fcol2: Color = Cfg.FACTIONS[pf]["color"]
						draw_arc(p, r + 6.0, 0.0, TAU * pp, 32, fcol2, 3.0)
						_text(p + Vector2(0, y_off), "Wird erobert: %s (%d %%)" % [Cfg.FACTIONS[pf]["short"], int(pp * 100.0)], fcol2, 13)
		else:
			# unerforscht: grauer Schatten mit Fragezeichen - hinfliegen, um ihn zu entdecken
			draw_circle(p, r, Color(0.25, 0.3, 0.4, 0.55))
			draw_arc(p, r, 0.0, TAU, 40, Color(0.6, 0.7, 0.85, 0.6), 1.5)
			_text(p + Vector2(0, 8.0), "?", Color(0.85, 0.9, 1.0), maxi(20, int(r * 0.9)))
			_text(p + Vector2(0, -r - 8.0), "Unerforscht", Color(0.7, 0.78, 0.9), 14)

	# Entdeckte Fundorte
	for i in Cfg.POIS.size():
		if (disc["pois"] as Array).has(i):
			var poi: Dictionary = Cfg.POIS[i]
			var pp := _w2s(poi["pos"])
			draw_texture_rect(Assets.tex("res://assets/world/poi_%s.png" % poi["kind"]), Rect2(pp - Vector2(14, 14), Vector2(28, 28)), false, Color(1, 1, 1, 0.75))
			_text(pp + Vector2(0, -20), str(poi["name"]) + " ✓", Color(0.7, 0.9, 1.0), 13)

	var sp := _w2s(Cfg.station_pos())
	draw_circle(sp, 4.0, UiTheme.ACCENT)
	if zoom > 0.03:
		_text(sp + Vector2(0, -12), "Station / Shop", UiTheme.ACCENT, 14)

	# --- Spieler als Raketen
	if game != null:
		for pdata in game.get_map_players():
			var ppos: Vector2 = _w2s(pdata["pos"])
			var is_me: bool = pdata["me"]
			var col := Color(0.4, 1.0, 0.55) if is_me else Color(1.0, 0.65, 0.3)
			var pf: int = int(pdata.get("faction", -1))
			if pf >= 0 and not is_me:
				col = Cfg.FACTIONS[pf]["color"]
			if is_me:
				var pulse := 30.0 + 3.0 * sin(Time.get_ticks_msec() / 250.0)
				draw_arc(ppos, pulse, 0.0, TAU, 40, Color(0.4, 1.0, 0.55, 0.85), 2.5)
			_draw_rocket(ppos, float(pdata["rot"]), pdata["levels"])
			_text(ppos + Vector2(0, -44.0), str(pdata["name"]), col, 17, 240.0)

	# --- Beschriftung
	draw_string(font, Vector2(20, 36), "KARTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UiTheme.ACCENT)
	draw_string(font, Vector2(20, 62), "Ziehen = Verschieben  ·  Mausrad = Zoom  ·  C = auf mich zentrieren  ·  M / Esc = schließen",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.MUTED)

	# --- Maßstab
	var len_world := 140.0 / zoom
	var p10 := pow(10.0, floorf(log(len_world) / log(10.0)))
	var nice := p10
	if len_world >= p10 * 5.0:
		nice = p10 * 5.0
	elif len_world >= p10 * 2.0:
		nice = p10 * 2.0
	var bar_px := nice * zoom
	var y := sz.y - 30.0
	draw_line(Vector2(20, y), Vector2(20 + bar_px, y), Color.WHITE, 2.0)
	draw_line(Vector2(20, y - 5), Vector2(20, y + 5), Color.WHITE, 2.0)
	draw_line(Vector2(20 + bar_px, y - 5), Vector2(20 + bar_px, y + 5), Color.WHITE, 2.0)
	draw_string(font, Vector2(30 + bar_px, y + 5), "%d m" % int(nice), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
