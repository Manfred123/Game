extends Control
# Hangar (nur an der Erdstation): Rakete frei aus Teilen zusammenbauen, Einmal-Addons kaufen
# (auch PvP) und einer Fraktion beitreten.

const Cfg = preload("res://scripts/config.gd")
const Parts = preload("res://scripts/parts.gd")
const Assets = preload("res://scripts/assets.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")

signal buy_part(cat: String, idx: int)
signal equip_part(cat: String, idx: int)
signal buy_item(item: String)
signal join_faction(f: int)
signal buy_paint(idx: int)
signal equip_paint(idx: int)
signal closed

const CAT_LABEL := {"engine": "Triebwerk", "nozzle": "Düse", "tank": "Tank", "hull": "Rumpf",
	"nose": "Nase", "fins": "Flügel", "legs": "Beine", "weapon": "Waffe", "radar": "Radar", "rcs": "Steuerdüsen"}

var preview
var preview_holder: Control
var coin_label: Label
var stats_label: Label
var cat_bar: VBoxContainer
var list_box: VBoxContainer
var _profile: Dictionary = {}
var _fstate: Dictionary = {}
var tab := 0                  # 0 = Bauen, 1 = Addons, 2 = Fraktion
var cur_cat := "engine"


func _ready() -> void:
	UiTheme.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.72)
	UiTheme.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UiTheme.full_rect(center)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1040, 620)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var title := UiTheme.heading("HANGAR  ·  ROCKET-BAUKASTEN", 28, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var coin_box := PanelContainer.new()
	coin_box.theme_type_variation = "InnerPanel"
	head.add_child(coin_box)
	var cb := HBoxContainer.new()
	coin_box.add_child(cb)
	var ci := TextureRect.new()
	ci.texture = Assets.tex("res://assets/ui/coin.png")
	ci.custom_minimum_size = Vector2(28, 28)
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cb.add_child(ci)
	coin_label = UiTheme.heading("", 24, UiTheme.GOLD)
	coin_label.custom_minimum_size = Vector2(90, 0)
	cb.add_child(coin_label)
	var close_btn := UiTheme.accent_button("Schließen (E)")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	root.add_child(UiTheme.hazard(9))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	preview_holder = Control.new()
	preview_holder.custom_minimum_size = Vector2(250, 330)
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_holder.clip_contents = true
	left.add_child(preview_holder)
	var pbg := TextureRect.new()
	pbg.texture = Assets.tex("res://assets/ui/preview_bg.png")
	pbg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pbg.stretch_mode = TextureRect.STRETCH_SCALE
	UiTheme.full_rect(pbg)
	preview_holder.add_child(pbg)
	preview = RocketVisual.new()
	preview.name_label.visible = false
	preview.thrust = 1.0
	preview.scale = Vector2(1.7, 1.7)
	preview_holder.add_child(preview)
	var sp := PanelContainer.new()
	sp.theme_type_variation = "InnerPanel"
	left.add_child(sp)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", UiTheme.MUTED)
	sp.add_child(stats_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	right.add_child(tabs)
	var grp := ButtonGroup.new()
	var names := ["RAKETE BAUEN", "ADDONS (+PvP)", "FRAKTION", "LACKIERUNG"]
	for i in 4:
		var b := _toggle(names[i], grp, 190)
		b.button_pressed = i == 0
		b.pressed.connect(_set_tab.bind(i))
		tabs.add_child(b)

	cat_bar = VBoxContainer.new()
	cat_bar.add_theme_constant_override("separation", 4)
	right.add_child(cat_bar)
	var cgrp := ButtonGroup.new()
	for group in Parts.CATEGORY_GROUPS:
		var grow := HBoxContainer.new()
		grow.add_theme_constant_override("separation", 4)
		cat_bar.add_child(grow)
		var gl := Label.new()
		gl.text = str(group["title"]).to_upper()
		gl.custom_minimum_size = Vector2(78, 0)
		gl.add_theme_font_size_override("font_size", 13)
		gl.add_theme_color_override("font_color", UiTheme.MUTED)
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grow.add_child(gl)
		for cat in group["cats"]:
			var cb2 := _toggle(CAT_LABEL[cat], cgrp, 0)
			cb2.custom_minimum_size = Vector2(0, 32)
			cb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb2.button_pressed = cat == cur_cat
			cb2.pressed.connect(_set_cat.bind(cat))
			grow.add_child(cb2)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	sc.add_child(list_box)


func _toggle(text: String, grp: ButtonGroup, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "TabButton"
	b.toggle_mode = true
	b.button_group = grp
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 40)
	return b


func _set_tab(i: int) -> void:
	tab = i
	refresh(_profile)


func _set_cat(cat: String) -> void:
	cur_cat = cat
	refresh(_profile)


func _process(_delta: float) -> void:
	if visible and preview_holder != null:
		preview.position = preview_holder.size / 2.0 + Vector2(0, -22)


func open(profile: Dictionary) -> void:
	visible = true
	refresh(profile)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func set_faction_state(state: Dictionary) -> void:
	_fstate = state
	if visible and tab == 2:
		refresh(_profile)


func refresh(profile: Dictionary) -> void:
	_profile = profile
	var coins: int = int(profile.get("coins", 0))
	var levels: Dictionary = profile.get("levels", Parts.default_levels())
	coin_label.text = " %d" % coins
	preview.set_levels(levels)
	preview.set_paint(int(profile.get("paint", 0)))
	preview.set_faction(int(profile.get("faction", -1)))
	preview.set_player_name(str(profile.get("name", "")))
	preview.name_label.visible = false

	var st: Dictionary = Parts.compute_stats(levels)
	stats_label.text = "Schub %d · Tempo %d · Masse %.1f\nTank %d · Rumpf %d · Panzerung %d %%\nDrehrate %.1f · Landung ≤ %d\nVerbrauch %.1f/s\nWaffe: %s\nAbschüsse %d · Abschüsse erlitten %d" % [
		int(st["thrust"]), int(st["max_speed"]), float(st["mass"]), int(st["max_fuel"]), int(st["max_hp"]),
		int(round(float(st["armor"]) * 100.0)), float(st["turn_rate"]), int(st["safe_v"]), float(st["burn"]),
		Parts.tier("weapon", int(levels.get("weapon", 0)))["name"], int(profile.get("kills", 0)), int(profile.get("deaths", 0))]

	cat_bar.visible = tab == 0
	for c in list_box.get_children():
		c.queue_free()
	if tab == 0:
		var owned: Array = profile.get("owned", Parts.default_owned()).get(cur_cat, [0])
		var eq: int = int(levels.get(cur_cat, 0))
		var d: Dictionary = Parts.UPGRADES[cur_cat]
		var info := Label.new()
		info.text = str(d["desc"])
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_size_override("font_size", 14)
		info.add_theme_color_override("font_color", UiTheme.MUTED)
		list_box.add_child(info)
		for i in Parts.max_level(cur_cat) + 1:
			list_box.add_child(_part_row(cur_cat, i, owned.has(i), eq == i, coins))
	elif tab == 1:
		var items: Dictionary = profile.get("items", Parts.default_items())
		for item in Parts.ITEM_ORDER:
			list_box.add_child(_item_row(item, int(items.get(item, 0)), coins))
	elif tab == 2:
		_faction_tab()
	else:
		_paint_tab(coins)


func _icon_frame(tex: Texture2D, size: Vector2) -> PanelContainer:
	var f := PanelContainer.new()
	f.theme_type_variation = "InnerPanel"
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	f.add_child(t)
	return f


func _price_button(price: int, disabled: bool) -> Button:
	var b := UiTheme.accent_button("%d" % price)
	b.icon = Assets.tex("res://assets/ui/coin.png")
	b.expand_icon = true
	b.custom_minimum_size = Vector2(120, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = disabled
	return b


func _row_frame() -> Array:
	var row := PanelContainer.new()
	row.theme_type_variation = "InnerPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	return [row, h]


func _part_row(cat: String, idx: int, owned: bool, equipped: bool, coins: int) -> Control:
	var part: Dictionary = Parts.tier(cat, idx)
	var fh := _row_frame()
	var row: PanelContainer = fh[0]
	var h: HBoxContainer = fh[1]
	if cat == "weapon" and idx == 0:
		h.add_child(_icon_frame(Assets.tex("res://assets/ui/no_weapon.png"), Vector2(92, 66)))
	else:
		h.add_child(_icon_frame(Assets.part_icon(cat, idx), Vector2(92, 66)))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiTheme.heading(str(part["name"]).to_upper(), 18, UiTheme.GOOD if equipped else UiTheme.CYAN))
	var d := Label.new()
	d.text = Parts.tier_info(cat, idx)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(300, 0)
	d.add_theme_font_size_override("font_size", 14)
	v.add_child(d)
	if equipped:
		var m := UiTheme.heading("AUSGERÜSTET", 16, UiTheme.GOOD)
		m.custom_minimum_size = Vector2(120, 0)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(m)
	elif owned:
		var b := Button.new()
		b.text = "Ausrüsten"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 44)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): equip_part.emit(cat, idx))
		h.add_child(b)
	else:
		var price: int = Parts.price_for(int(part["price"]), int(_profile.get("faction", -1)))
		var b2 := _price_button(price, coins < price)
		b2.pressed.connect(func(): buy_part.emit(cat, idx))
		h.add_child(b2)
	return row


func _item_row(item: String, count: int, coins: int) -> Control:
	var data: Dictionary = Parts.ITEMS[item]
	var fh := _row_frame()
	var row: PanelContainer = fh[0]
	var h: HBoxContainer = fh[1]
	h.add_child(_icon_frame(Assets.tex(data["icon"]), Vector2(56, 56)))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var tag := "  ⚔ PvP" if data["pvp"] else ""
	v.add_child(UiTheme.heading("%s   [%s]%s" % [str(data["name"]).to_upper(), data["key"], tag], 18,
		UiTheme.BAD if data["pvp"] else UiTheme.CYAN))
	var d := Label.new()
	d.text = "%s   Im Besitz: %d/%d" % [data["desc"], count, Cfg.MAX_ITEM_STACK]
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(320, 0)
	d.add_theme_font_size_override("font_size", 13)
	d.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(d)
	var price: int = Parts.price_for(int(data["price"]), int(_profile.get("faction", -1)))
	var b := _price_button(price, coins < price or count >= Cfg.MAX_ITEM_STACK)
	b.pressed.connect(func(): buy_item.emit(item))
	h.add_child(b)
	return row


func _faction_tab() -> void:
	var my: int = int(_profile.get("faction", -1))
	var info := Label.new()
	info.text = "In einer Fraktion können sich Mitglieder nie gegenseitig beschießen oder verletzen.\nJe %d Abschüsse an anderen Fraktionen = 1 Bonusstufe (max. %d): +%d %% Flug-Coins und +%d %% Landeprämie pro Stufe.\nWechsel nur an der Station (Pause %d s). Kapazität pro Fraktion richtet sich nach der Spielerzahl - so kann nicht jeder in dieselbe Fraktion." % [
		Cfg.FACTION_KILLS_PER_LEVEL, Cfg.FACTION_MAX_LEVEL, int(Cfg.FACTION_FLIGHT_BONUS * 100.0), int(Cfg.FACTION_LANDING_BONUS * 100.0), int(Cfg.FACTION_SWITCH_COOLDOWN)]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", UiTheme.MUTED)
	list_box.add_child(info)
	var kills: Array = _fstate.get("kills", [])
	var members: Array = _fstate.get("members", [])
	var lvls: Array = _fstate.get("levels", [])
	var limit: int = int(_fstate.get("limit", 99))
	for i in Cfg.FACTIONS.size():
		var f: Dictionary = Cfg.FACTIONS[i]
		var fh := _row_frame()
		var row: PanelContainer = fh[0]
		var h: HBoxContainer = fh[1]
		h.add_child(_icon_frame(Assets.tex("res://assets/ui/faction_%d.png" % i), Vector2(60, 60)))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var count: int = int(members[i]) if i < members.size() else 0
		var full: bool = count >= limit
		v.add_child(UiTheme.heading(str(f["name"]).to_upper(), 17, f["color"]))
		var d := Label.new()
		d.text = "%s\nMitglieder: %d / %d%s · Abschüsse: %d · Bonusstufe: %d" % [f["desc"], count, limit,
			"  (VOLL)" if full and my != i else "", int(kills[i]) if i < kills.size() else 0, int(lvls[i]) if i < lvls.size() else 0]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(320, 0)
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", UiTheme.BAD if (full and my != i) else UiTheme.TEXT)
		v.add_child(d)
		var b := UiTheme.accent_button("Beitreten") if my != i else UiTheme.accent_button("Aktiv")
		b.disabled = my == i or full
		b.custom_minimum_size = Vector2(120, 44)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): join_faction.emit(i))
		h.add_child(b)
		list_box.add_child(row)
	if my >= 0:
		var leave := Button.new()
		leave.text = "Fraktion verlassen (wieder fraktionslos)"
		leave.focus_mode = Control.FOCUS_NONE
		leave.pressed.connect(func(): join_faction.emit(-1))
		list_box.add_child(leave)


func _paint_tab(coins: int) -> void:
	var owned: Array = _profile.get("owned_paints", Parts.default_paints())
	var cur: int = int(_profile.get("paint", 0))
	var info := Label.new()
	info.text = "Rein optisch: färbt Rumpf, Nase, Tank, Flügel und Beine. Motor, Düse und Waffe behalten ihre Eigenfarbe."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", UiTheme.MUTED)
	list_box.add_child(info)
	for i in Parts.PAINTS.size():
		var d: Dictionary = Parts.PAINTS[i]
		var fh := _row_frame()
		var row: PanelContainer = fh[0]
		var h: HBoxContainer = fh[1]
		var swatch := PanelContainer.new()
		swatch.theme_type_variation = "InnerPanel"
		var cr := ColorRect.new()
		cr.color = d["color"]
		cr.custom_minimum_size = Vector2(64, 64)
		swatch.add_child(cr)
		h.add_child(swatch)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UiTheme.heading(str(d["name"]).to_upper(), 18, UiTheme.GOOD if i == cur else UiTheme.CYAN))
		if i == cur:
			var m := UiTheme.heading("ANGELEGT", 16, UiTheme.GOOD)
			m.custom_minimum_size = Vector2(120, 0)
			m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(m)
		elif (owned as Array).has(i):
			var b := Button.new()
			b.text = "Anlegen"
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(120, 44)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func(): equip_paint.emit(i))
			h.add_child(b)
		else:
			var price: int = Parts.price_for(int(d["price"]), int(_profile.get("faction", -1)))
			var b2 := _price_button(price, coins < price)
			b2.pressed.connect(func(): buy_paint.emit(i))
			h.add_child(b2)
		list_box.add_child(row)
