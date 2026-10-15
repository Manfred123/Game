extends Node2D
# Die Spielwelt auf Seiten des Clients.
#  - Die eigene Rakete wird lokal vorhergesagt (gleiche Physik wie der Server) und mit den
#    Server-Snapshots abgeglichen (Client-Side-Prediction + Reconciliation).
#  - Fremde Raketen werden weich zu den Snapshot-Positionen bewegt.
#  - Kollisionen, Schaden, Coins und Käufe entscheidet ausschließlich der Server.

const Cfg = preload("res://scripts/config.gd")
const Parts = preload("res://scripts/parts.gd")
const Sim = preload("res://scripts/sim.gd")
const Assets = preload("res://scripts/assets.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")
const HudScript = preload("res://scripts/hud.gd")
const ShopScript = preload("res://scripts/shop_ui.gd")
const MapScript = preload("res://scripts/map_view.gd")

const CLIENT_ROLE := 2               # entspricht Net.Role.CLIENT
const ZOOM_MIN := 0.3
const ZOOM_MAX := 2.5

signal leave_requested

var init_info: Dictionary = {}       # kommt von Net.join_accepted

var my_id := 0
var my_name := ""
var server_name := ""

# Zustand der eigenen Rakete
var local = null                     # Sim.State
var stats: Dictionary = {}
var levels: Dictionary = {}
var items: Dictionary = {}
var coins := 0
var profile: Dictionary = {}
var pending: Array = []
var seq := 0
var last_snap_tick := -1
var ready_local := false
var dead := false
var dead_since := 0.0
var prev_pos := Vector2.ZERO
var prev_rot := 0.0
var visual_offset := Vector2.ZERO

# Andere Spieler
var remotes: Dictionary = {}         # id -> RocketVisual
var remote_info: Dictionary = {}     # id -> {name, levels}
var remote_dead: Dictionary = {}

# Szene
var world: Node2D
var stars_root: Node2D
var star_layers: Array = []
var local_visual
var cam: Camera2D
var zoom_target := 1.0
var shake := 0.0

# Oberfläche
var ui_root: Control
var hud
var shop
var map
var pause_panel: PanelContainer

# Fraktion, Erforschung, Geschosse
var faction := -1
var paint := 0
var kills := 0
var deaths := 0
var fstate: Dictionary = {}
var disc_planets: Array = []
var disc_pois: Array = []
var poi_sprites: Array = []
var planet_flags: Array = []
var proj_pool: Array = []

const PROJ_TEX := {0: "laser", 1: "laser", 2: "plasma", 3: "torpedo", 10: "mine"}


func _ready() -> void:
	my_id = int(init_info["you"])
	my_name = str(init_info["name"])
	server_name = str(init_info.get("server_name", ""))
	for inf in init_info.get("players", []):
		remote_info[int(inf["id"])] = inf
	fstate = init_info.get("factions", {})
	_apply_profile(init_info["profile"])

	local = Sim.State.new()

	world = Node2D.new()
	add_child(world)
	_build_world()

	local_visual = RocketVisual.new()
	local_visual.z_index = 6
	local_visual.set_levels(levels)
	local_visual.set_paint(paint)
	local_visual.set_player_name(my_name)
	local_visual.set_faction(faction)
	local_visual.visible = false
	world.add_child(local_visual)

	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

	_build_ui()

	Net.snapshot_received.connect(_on_snapshot)
	Net.remote_player_joined.connect(_on_remote_joined)
	Net.remote_player_left.connect(_on_remote_left)
	Net.remote_parts_changed.connect(_on_remote_parts)
	Net.profile_received.connect(_on_profile)
	Net.notice.connect(_on_notice)
	Net.fx_event.connect(_on_fx)
	Net.projectiles_received.connect(_on_projectiles)
	Net.player_faction_changed.connect(_on_player_faction)
	Net.player_paint_changed.connect(_on_player_paint)
	Net.faction_state_received.connect(_on_faction_state)

	_refresh_players()
	_apply_faction_state(fstate)
	hud.center_message("Verbinde mit Welt '%s' ..." % server_name, UiTheme.MUTED)


# ================================================================= Aufbau
func _build_world() -> void:
	stars_root = Node2D.new()
	world.add_child(stars_root)
	star_layers.append(_make_star_layer("res://assets/world/stars_far.png", 0.12, -100))
	star_layers.append(_make_star_layer("res://assets/world/stars_near.png", 0.35, -99))

	for i in Cfg.PLANETS.size():
		var pl: Dictionary = Cfg.PLANETS[i]
		var ppos: Vector2 = pl["pos"]
		var radius: float = pl["radius"]
		var atmo: float = pl["atmo"]
		if atmo > 0.0:
			var g := Sprite2D.new()
			g.texture = Assets.tex("res://assets/world/atmo_glow.png")
			var d: float = (radius + atmo) * 2.0
			g.scale = Vector2.ONE * (d / float(g.texture.get_width()))
			g.modulate = pl["glow"]
			g.position = ppos
			g.z_index = -10
			world.add_child(g)
		var sp := Sprite2D.new()
		sp.texture = Assets.tex(pl["tex"])
		sp.scale = Vector2.ONE * (radius * 2.0 / float(sp.texture.get_width()))
		sp.position = ppos
		sp.z_index = -5
		world.add_child(sp)
		if i == 0:
			planet_flags.append(null)          # Erde hat schon die richtige Station
		else:
			var flag := Sprite2D.new()
			flag.texture = Assets.tex("res://assets/world/outpost_flag.png")
			flag.position = Cfg.planet_top(i)
			flag.centered = true
			flag.offset = Vector2(0, -float(flag.texture.get_height()) / 2.0)
			flag.scale = Vector2.ONE * Cfg.OUTPOST_FLAG_SCALE
			flag.z_index = 3
			flag.visible = false
			world.add_child(flag)
			planet_flags.append(flag)

	var st := Sprite2D.new()
	st.texture = Assets.tex("res://assets/world/station.png")
	st.centered = false
	st.position = Cfg.station_pos() + Vector2(-float(st.texture.get_width()) / 2.0, -Cfg.STATION_PAD_Y)
	st.z_index = 1
	world.add_child(st)

	for i in Cfg.POIS.size():
		var poi: Dictionary = Cfg.POIS[i]
		var ps := Sprite2D.new()
		ps.texture = Assets.tex("res://assets/world/poi_%s.png" % poi["kind"])
		ps.position = poi["pos"]
		ps.scale = Vector2.ONE * 1.4
		ps.z_index = 2
		ps.visible = not disc_pois.has(i)
		world.add_child(ps)
		poi_sprites.append(ps)


func _make_star_layer(path: String, factor: float, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Assets.tex(path)
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.z_index = z
	s.set_meta("factor", factor)
	stars_root.add_child(s)
	return s


func _update_stars() -> void:
	var vs: Vector2 = get_viewport_rect().size / maxf(cam.zoom.x, 0.05) + Vector2(300, 300)
	var c: Vector2 = cam.get_screen_center_position()
	for s in star_layers:
		var f: float = s.get_meta("factor")
		var tw := float(s.texture.get_width())
		var th := float(s.texture.get_height())
		s.global_position = c
		s.region_rect = Rect2(
			fposmod(c.x * f - vs.x / 2.0, tw), fposmod(c.y * f - vs.y / 2.0, th), vs.x, vs.y)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	UiTheme.full_rect(ui_root)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiTheme.build()
	layer.add_child(ui_root)

	hud = HudScript.new()
	ui_root.add_child(hud)
	hud.reset_requested.connect(_reset_rocket)

	map = MapScript.new()
	map.game = self
	ui_root.add_child(map)

	shop = ShopScript.new()
	ui_root.add_child(shop)
	shop.buy_part.connect(_on_buy_part)
	shop.equip_part.connect(_on_equip_part)
	shop.join_faction.connect(_on_join_faction)
	shop.buy_paint.connect(_on_buy_paint)
	shop.equip_paint.connect(_on_equip_paint)
	shop.set_faction_state(fstate)
	shop.buy_item.connect(_on_buy_item)

	pause_panel = PanelContainer.new()
	pause_panel.anchor_left = 0.5
	pause_panel.anchor_right = 0.5
	pause_panel.anchor_top = 0.5
	pause_panel.anchor_bottom = 0.5
	pause_panel.offset_left = -200.0
	pause_panel.offset_right = 200.0
	pause_panel.offset_top = -190.0
	pause_panel.offset_bottom = 190.0
	pause_panel.visible = false
	ui_root.add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	v.add_child(UiTheme.heading("PAUSE-MENÜ", 28, UiTheme.ACCENT))
	v.add_child(UiTheme.hazard(8))
	var note := Label.new()
	note.text = "Die Welt läuft im Mehrspieler weiter."
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(note)
	var b1 := UiTheme.accent_button("Weiterspielen")
	b1.custom_minimum_size = Vector2(0, 46)
	b1.pressed.connect(_hide_pause)
	v.add_child(b1)
	var b3 := Button.new()
	b3.text = "Rakete zurücksetzen (zur Station)  [K]"
	b3.focus_mode = Control.FOCUS_NONE
	b3.pressed.connect(_reset_from_pause)
	v.add_child(b3)
	var b4 := Button.new()
	b4.text = "Vollbild an/aus  [F11]"
	b4.focus_mode = Control.FOCUS_NONE
	b4.pressed.connect(func(): Net.toggle_fullscreen())
	v.add_child(b4)
	var b2 := Button.new()
	b2.text = "Zum Hauptmenü"
	b2.focus_mode = Control.FOCUS_NONE
	b2.pressed.connect(func(): leave_requested.emit())
	v.add_child(b2)


func _reset_from_pause() -> void:
	_hide_pause()
	_reset_rocket()


func _hide_pause() -> void:
	pause_panel.visible = false


# ================================================================= Eingabe
func _read_input() -> int:
	if shop.visible or pause_panel.visible:
		return 0
	var f := 0
	if Input.is_action_pressed("thrust") or Input.is_action_pressed("ui_up"):
		f |= 1
	if Input.is_action_pressed("ui_down"):
		f |= 2
	if Input.is_action_pressed("ui_left"):
		f |= 4
	if Input.is_action_pressed("ui_right"):
		f |= 8
	if Input.is_action_pressed("fire") and not map.visible:
		f |= 16
	return f


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		_toggle_map()
	elif event.is_action_pressed("map_center"):
		if map.visible:
			map.recenter()
	elif event.is_action_pressed("toggle_shop"):
		_toggle_shop()
	elif event.is_action_pressed("toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed("reset_rocket"):
		_reset_rocket()
	elif event.is_action_pressed("ui_cancel"):
		_on_escape()
	elif event.is_action_pressed("use_boost"):
		_use_item("boost")
	elif event.is_action_pressed("use_parachute"):
		_use_item("chute")
	elif event.is_action_pressed("use_repair"):
		_use_item("repair")
	elif event.is_action_pressed("use_fuel"):
		_use_item("fuel")
	elif event.is_action_pressed("use_shield"):
		_use_item("shield")
	elif event.is_action_pressed("use_torpedo"):
		_use_item("torpedo")
	elif event.is_action_pressed("use_emp"):
		_use_item("emp")
	elif event.is_action_pressed("use_mine"):
		_use_item("mine")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target * 1.15, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target / 1.15, ZOOM_MIN, ZOOM_MAX)


# Reset: Rakete zurück zur Erdstation (Server prüft und führt aus)
func _reset_rocket() -> void:
	if not ready_local or dead:
		return
	zoom_target = 1.0
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_reset_request", [])


func _use_item(item: String) -> void:
	if not ready_local or dead or shop.visible or pause_panel.visible:
		return
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_use_item", [item])


func _toggle_map() -> void:
	if map.visible:
		map.close()
	elif ready_local:
		map.open(local_visual.position)


func _toggle_shop() -> void:
	if shop.visible:
		shop.close()
		return
	if not ready_local or dead:
		return
	if Sim.at_station(local) or _at_own_outpost() or (not Cfg.SHOP_ONLY_AT_STATION and local.landed >= 0):
		shop.open(profile)
	else:
		hud.toast("Der Shop ist nur an der Erdstation oder deinem Außenposten erreichbar.", "warn")


# Steht die Rakete auf einem Planeten, den die eigene Fraktion erobert hat?
func _at_own_outpost() -> bool:
	if faction < 0 or local.landed <= 0:
		return false
	var owners: Array = fstate.get("planet_owner", [])
	return local.landed < owners.size() and int(owners[local.landed]) == faction


func _on_escape() -> void:
	if shop.visible:
		shop.close()
	elif map.visible:
		map.close()
	else:
		pause_panel.visible = not pause_panel.visible


func _on_buy_part(cat: String, idx: int) -> void:
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_buy_part", [cat, idx])


func _on_equip_part(cat: String, idx: int) -> void:
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_equip_part", [cat, idx])


func _on_join_faction(f: int) -> void:
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_join_faction", [f])


func _on_buy_paint(idx: int) -> void:
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_buy_paint", [idx])


func _on_equip_paint(idx: int) -> void:
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_equip_paint", [idx])


func _on_buy_item(item: String) -> void:
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_buy_item", [item])


# ================================================================= Physik
func _physics_process(_delta: float) -> void:
	if not ready_local or dead:
		return
	prev_pos = local.pos
	prev_rot = local.rot
	var inp := _read_input()
	seq += 1
	if Net.role == CLIENT_ROLE:
		Net.send_to(1, "rpc_send_input", [seq, inp])
	pending.append([seq, inp])
	if pending.size() > 240:
		pending.pop_front()
	Sim.step(local, inp, stats, Cfg.DT)


# ============================================================ Server-Daten
func _on_snapshot(tick: int, ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if tick <= last_snap_tick:
		return                          # veraltet (unreliable kann umsortieren)
	last_snap_tick = tick
	for i in ids.size():
		var id: int = ids[i]
		var o: int = i * Cfg.SNAP_STRIDE
		if id == my_id:
			_reconcile(data, o)
		else:
			_update_remote(id, data, o)


func _reconcile(d: PackedFloat32Array, o: int) -> void:
	var flags := int(d[o + 6])
	var now_dead := (flags & 32) != 0
	var ack := int(d[o + 9])
	var frac := Engine.get_physics_interpolation_fraction()
	var old_render := prev_pos.lerp(local.pos, frac) + visual_offset

	# 1. Zustand des Servers übernehmen
	local.pos = Vector2(d[o], d[o + 1])
	local.rot = d[o + 2]
	local.vel = Vector2(d[o + 3], d[o + 4])
	local.angvel = d[o + 5]
	local.hp = d[o + 7]
	local.fuel = d[o + 8]
	local.boost_t = d[o + 10]
	local.shield_t = d[o + 11]
	local.landed = int(d[o + 12])
	local.chute_t = d[o + 13]
	local.emp_t = d[o + 14]
	local.chute = (flags & 4) != 0

	# 2. Bereits bestätigte Eingaben verwerfen, den Rest erneut anwenden
	while pending.size() > 0 and int(pending[0][0]) <= ack:
		pending.pop_front()

	if now_dead:
		pending.clear()
	elif not now_dead:
		for e in pending:
			Sim.step(local, int(e[1]), stats, Cfg.DT)

	# 3. Tod / Wiedergeburt
	if now_dead and not dead:
		dead = true
		dead_since = Time.get_ticks_msec() / 1000.0
		shake = 2.0
		if shop.visible:
			shop.close()
	elif dead and not now_dead:
		dead = false
		hud.center_message("")

	# 4. Sanfte Korrektur der Darstellung (kein Ruckeln bei kleinen Abweichungen)
	prev_pos = local.pos - local.vel * Cfg.DT
	prev_rot = local.rot - local.angvel * Cfg.DT
	if not ready_local:
		ready_local = true
		prev_pos = local.pos
		prev_rot = local.rot
		visual_offset = Vector2.ZERO
		local_visual.position = local.pos
		local_visual.visible = true
		hud.center_message("")
	else:
		var new_render := prev_pos.lerp(local.pos, frac)
		visual_offset = old_render - new_render
		if visual_offset.length() > 250.0:
			visual_offset = Vector2.ZERO


func _update_remote(id: int, d: PackedFloat32Array, o: int) -> void:
	var v = _ensure_remote(id)
	var flags := int(d[o + 6])
	v.remote_update(Vector2(d[o], d[o + 1]), d[o + 2], Vector2(d[o + 3], d[o + 4]))
	v.apply_flags(flags)
	var is_dead := (flags & 32) != 0
	remote_dead[id] = is_dead
	v.visible = not is_dead


func _ensure_remote(id: int):
	if remotes.has(id):
		return remotes[id]
	var v = RocketVisual.new()
	v.is_remote = true
	v.z_index = 5
	var inf: Dictionary = remote_info.get(id, {})
	v.set_levels(inf.get("levels", Parts.default_levels()))
	v.set_player_name(str(inf.get("name", "...")))
	v.set_faction(int(inf.get("faction", -1)))
	world.add_child(v)
	remotes[id] = v
	_refresh_players()
	return v


func _on_remote_joined(id: int, info: Dictionary) -> void:
	remote_info[id] = info
	if remotes.has(id):
		remotes[id].set_levels(info["levels"])
		remotes[id].set_player_name(str(info["name"]))
		remotes[id].set_faction(int(info.get("faction", -1)))
	_refresh_players()
	hud.toast("%s ist der Welt beigetreten." % info["name"], "info")


func _on_remote_left(id: int) -> void:
	var nm := "Ein Pilot"
	if remote_info.has(id):
		nm = str(remote_info[id]["name"])
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)
	remote_info.erase(id)
	remote_dead.erase(id)
	_refresh_players()
	hud.toast("%s hat die Welt verlassen." % nm, "info")


func _on_remote_parts(id: int, lv: Dictionary) -> void:
	if remote_info.has(id):
		remote_info[id]["levels"] = lv
	if remotes.has(id):
		remotes[id].set_levels(lv)


func _on_profile(p: Dictionary) -> void:
	_apply_profile(p)
	if local_visual != null:
		local_visual.set_levels(levels)
	if shop != null and shop.visible:
		shop.refresh(profile)


func _apply_profile(p: Dictionary) -> void:
	profile = p
	coins = int(p.get("coins", 0))
	levels = p.get("levels", Parts.default_levels())
	items = p.get("items", Parts.default_items())
	faction = int(p.get("faction", -1))
	paint = int(p.get("paint", 0))
	kills = int(p.get("kills", 0))
	deaths = int(p.get("deaths", 0))
	disc_planets = p.get("disc_planets", [])
	disc_pois = p.get("disc_pois", [])
	stats = Parts.compute_stats(levels)
	for i in poi_sprites.size():
		poi_sprites[i].visible = not disc_pois.has(i)
	if local_visual != null:
		local_visual.set_faction(faction)
		local_visual.set_paint(paint)


func _on_player_faction(id: int, f: int) -> void:
	if remote_info.has(id):
		remote_info[id]["faction"] = f
	if remotes.has(id):
		remotes[id].set_faction(f)
	if id == my_id:
		faction = f
		local_visual.set_faction(f)


func _on_player_paint(id: int, idx: int) -> void:
	if remote_info.has(id):
		remote_info[id]["paint"] = idx
	if remotes.has(id):
		remotes[id].set_paint(idx)
	if id == my_id:
		paint = idx
		local_visual.set_paint(idx)


# Eroberungsstatus verarbeiten: Außenposten-Fahnen ein-/ausblenden und einfärben.
func _apply_faction_state(state: Dictionary) -> void:
	fstate = state
	var owners: Array = state.get("planet_owner", [])
	for i in planet_flags.size():
		var flag = planet_flags[i]
		if flag == null:
			continue
		var owner: int = int(owners[i]) if i < owners.size() else -1
		flag.visible = owner >= 0
		if owner >= 0:
			flag.modulate = Cfg.FACTIONS[owner]["color"]
	if shop != null:
		shop.set_faction_state(state)


func _on_faction_state(state: Dictionary) -> void:
	_apply_faction_state(state)


func _on_projectiles(data: PackedFloat32Array) -> void:
	var n: int = int(data.size() / 5)
	while proj_pool.size() < n:
		var sp := Sprite2D.new()
		sp.z_index = 8
		world.add_child(sp)
		proj_pool.append(sp)
	for i in proj_pool.size():
		var sp2: Sprite2D = proj_pool[i]
		if i >= n:
			sp2.visible = false
			continue
		var o: int = i * 5
		var kind: int = int(data[o + 3])
		sp2.texture = Assets.tex("res://assets/fx/%s.png" % PROJ_TEX.get(kind, "laser"))
		sp2.position = Vector2(data[o], data[o + 1])
		sp2.modulate = Color(1.0, 0.85, 0.45) if kind == 1 else Color.WHITE
		if kind == 10:
			sp2.rotation = 0.0
			sp2.modulate = Color(1, 1, 1, 1) if data[o + 4] > 0.5 else Color(1, 1, 1, 0.45)
		else:
			sp2.rotation = data[o + 2] + PI / 2.0
		sp2.visible = true


func _on_notice(text: String, kind: String) -> void:
	hud.toast(text, kind)


func _refresh_players() -> void:
	var names: Array = [my_name]
	for id in remote_info:
		names.append(str(remote_info[id]["name"]))
	hud.set_players(names)


# ============================================================ Effekte
func _on_fx(kind: String, id: int, pos: Vector2, value: float) -> void:
	if kind == "crash":
		_spawn_sparks(pos, clampf(value / 40.0, 0.6, 3.0))
		if id == my_id:
			shake = maxf(shake, clampf(value / 50.0, 0.4, 1.6))
	elif kind == "hit":
		_spawn_sparks(pos, 0.7)
		if id == my_id:
			shake = maxf(shake, 0.3)
	elif kind == "emp":
		_spawn_ring(pos, value)
	elif kind == "kill":
		_spawn_sparks(pos, 1.5)
	elif kind == "explode":
		_spawn_explosion(pos)
		if ready_local and pos.distance_to(local.pos) < 1500.0:
			shake = maxf(shake, 1.8)


func _spawn_sparks(pos: Vector2, power: float) -> void:
	var p := CPUParticles2D.new()
	p.texture = Assets.tex("res://assets/fx/spark.png")
	p.position = pos
	p.z_index = 20
	p.one_shot = true
	p.amount = int(24.0 * power)
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0 * power
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color = Color(1.0, 0.8, 0.45)
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func _spawn_ring(pos: Vector2, radius: float) -> void:
	var r := Sprite2D.new()
	r.texture = Assets.tex("res://assets/fx/shield.png")
	r.position = pos
	r.z_index = 20
	r.modulate = Color(0.6, 0.8, 1.0, 0.9)
	r.scale = Vector2.ONE * 0.1
	world.add_child(r)
	var tw := r.create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "scale", Vector2.ONE * (radius * 2.0 / 256.0), 0.6)
	tw.tween_property(r, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(r.queue_free)


func _spawn_explosion(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = Assets.tex("res://assets/fx/explosion.png")
	s.position = pos
	s.scale = Vector2.ONE * 0.3
	s.z_index = 20
	world.add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * 1.7, 0.8)
	tw.tween_property(s, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(s.queue_free)
	_spawn_sparks(pos, 3.0)


# ====================================================== Darstellung pro Frame
func _process(delta: float) -> void:
	if ready_local:
		var frac := Engine.get_physics_interpolation_fraction()
		visual_offset = visual_offset.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))
		var rp := prev_pos.lerp(local.pos, frac) + visual_offset
		var rr := lerp_angle(prev_rot, local.rot, frac)
		local_visual.position = rp
		local_visual.set_body_rotation(rr)
		local_visual.visible = not dead
		local_visual.thrust = local.thrusting
		local_visual.chute_on = local.chute
		local_visual.shield_on = local.shield_t > 0.0
		local_visual.boost_on = local.boost_t > 0.0
		cam.position = rp
	# Kamera
	cam.zoom = cam.zoom.lerp(Vector2.ONE * zoom_target, 1.0 - exp(-8.0 * delta))
	if shake > 0.0:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 14.0
		shake = maxf(0.0, shake - delta * 2.5)
	else:
		cam.offset = Vector2.ZERO
	_update_stars()

	local_visual.set_label_zoom(cam.zoom.x)
	for id in remotes:
		remotes[id].set_label_zoom(cam.zoom.x)

	if ready_local:
		_update_hud()


func _update_hud() -> void:
	var speed: float = local.vel.length()
	var info := "Tempo: %d m/s" % int(speed)
	var color: Color = UiTheme.TEXT
	var hint := ""

	if dead:
		var left := Cfg.RESPAWN_TIME - (Time.get_ticks_msec() / 1000.0 - dead_since)
		hud.center_message("RAKETE ZERSTÖRT\nNeustart in %d ..." % int(ceil(maxf(left, 0.0))), UiTheme.BAD)
	elif local.landed >= 0:
		var lp: Dictionary = Cfg.PLANETS[local.landed]
		info += "\nGelandet auf %s" % lp["name"]
		if Sim.at_station(local) or _at_own_outpost():
			hint = "[E] Shop öffnen   ·   Tanken & Reparatur laufen"
		else:
			hint = "Zum Starten: Leertaste"
		if local.landed > 0:
			var owners4: Array = fstate.get("planet_owner", [])
			var owner4: int = int(owners4[local.landed]) if local.landed < owners4.size() else -1
			if owner4 == faction and faction >= 0:
				info += "\nEigener Außenposten - Tanken/Reparatur/Shop verfügbar"
			elif owner4 >= 0:
				info += "\nAußenposten von %s" % Cfg.FACTIONS[owner4]["short"]
	else:
		var np: Dictionary = Sim.nearest_planet(local.pos)
		var pl: Dictionary = Cfg.PLANETS[int(np["idx"])]
		var alt: float = np["alt"]
		var n: Vector2 = np["n"]
		var approach: float = -local.vel.dot(n)
		info += "\n%s: Höhe %d m" % [pl["name"], int(maxf(alt, 0.0))]
		if alt < 1800.0 and approach > 5.0:
			var safe: float = stats["safe_v"]
			info += "\nSinkrate %d m/s (sicher bis %d)" % [int(approach), int(safe)]
			color = UiTheme.BAD if approach > safe else UiTheme.GOOD
			if alt < 700.0 and approach > safe:
				hint = "ABBREMSEN!"
		var up_dot: float = Vector2.UP.rotated(local.rot).dot(n)
		if alt < 250.0 and up_dot < Cfg.LAND_ALIGN:
			hint = "Nase vom Planeten weg drehen!"

	var ftext := "Fraktionslos  ·  Abschüsse %d" % kills
	var fcolor: Color = UiTheme.MUTED
	if faction >= 0:
		var fd: Dictionary = Cfg.FACTIONS[faction]
		var lv: int = 0
		if fstate.has("levels") and faction < (fstate["levels"] as Array).size():
			lv = int(fstate["levels"][faction])
		ftext = "[%s]  Bonusstufe %d  ·  Abschüsse %d" % [fd["short"], lv, kills]
		fcolor = fd["color"]
	hud.update_hud({
		"faction_text": ftext, "faction_color": fcolor,
		"name": my_name, "coins": coins,
		"hp": local.hp, "max_hp": stats["max_hp"],
		"fuel": local.fuel, "max_fuel": stats["max_fuel"],
		"items": items, "boost_t": local.boost_t, "shield_t": local.shield_t, "chute": local.chute,
		"info": info, "info_color": color, "hint": hint,
	})


# Für die Karte
func get_map_players() -> Array:
	var arr: Array = []
	if ready_local and not dead:
		arr.append({"name": my_name, "pos": local_visual.position, "rot": local_visual.body.rotation, "me": true, "levels": levels, "faction": faction})
	for id in remotes:
		var v = remotes[id]
		if not v.has_state or remote_dead.get(id, false):
			continue
		var nm := "?"
		if remote_info.has(id):
			nm = str(remote_info[id]["name"])
		var lv: Dictionary = Parts.default_levels()
		if remote_info.has(id):
			lv = remote_info[id].get("levels", lv)
		arr.append({"name": nm, "pos": v.position, "rot": v.body.rotation, "me": false, "levels": lv, "faction": int(remote_info.get(id, {}).get("faction", -1))})
	return arr


# Für die Karte: was hat dieser Spieler schon entdeckt?
func get_discovery() -> Dictionary:
	return {"planets": disc_planets, "pois": disc_pois}
