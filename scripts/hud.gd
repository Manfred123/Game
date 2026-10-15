extends Control
# Feste Anzeige an der Rakete (Coins, Rumpf, Tank, Tempo, Addons, Meldungen).

const Cfg = preload("res://scripts/config.gd")
const Parts = preload("res://scripts/parts.gd")
const Assets = preload("res://scripts/assets.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

signal reset_requested

var name_label: Label
var coin_label: Label
var hull_bar: ProgressBar
var hull_label: Label
var fuel_bar: ProgressBar
var fuel_label: Label
var info_label: Label
var faction_label: Label
var players_label: Label
var toast_box: VBoxContainer
var center_label: Label
var hint_label: Label
var help_panel: PanelContainer
var slot_labels: Dictionary = {}
var slot_panels: Dictionary = {}


func _ready() -> void:
	UiTheme.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_left()
	_build_top_right()
	_build_bottom()
	_build_center()
	_build_help()
	var help_timer := Timer.new()
	help_timer.one_shot = true
	help_timer.wait_time = 18.0
	help_timer.autostart = true
	help_timer.timeout.connect(_hide_help)
	add_child(help_timer)


func _hide_help() -> void:
	help_panel.visible = false


func _ignore(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _panel(variation: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	_ignore(p)
	return p


func _bar_row(parent: Control, title: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_ignore(row)
	parent.add_child(row)
	var t := Label.new()
	t.text = title
	t.custom_minimum_size = Vector2(56, 0)
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", UiTheme.MUTED)
	row.add_child(t)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(color))
	_ignore(bar)
	row.add_child(bar)
	var val := Label.new()
	val.custom_minimum_size = Vector2(76, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 15)
	row.add_child(val)
	return [bar, val]


func _build_top_left() -> void:
	var panel := _panel("HudPanel")
	panel.position = Vector2(14, 14)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_ignore(v)
	panel.add_child(v)

	name_label = UiTheme.heading("", 20, UiTheme.ACCENT)
	v.add_child(name_label)

	var cr := HBoxContainer.new()
	_ignore(cr)
	v.add_child(cr)
	var ci := TextureRect.new()
	ci.texture = Assets.tex("res://assets/ui/coin.png")
	ci.custom_minimum_size = Vector2(26, 26)
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ignore(ci)
	cr.add_child(ci)
	coin_label = UiTheme.heading("", 20, UiTheme.GOLD)
	cr.add_child(coin_label)

	var h := _bar_row(v, "Rumpf", Color(0.95, 0.36, 0.3))
	hull_bar = h[0]
	hull_label = h[1]
	var f := _bar_row(v, "Tank", Color(0.3, 0.8, 1.0))
	fuel_bar = f[0]
	fuel_label = f[1]

	faction_label = Label.new()
	faction_label.add_theme_font_size_override("font_size", 15)
	v.add_child(faction_label)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 16)
	v.add_child(info_label)


func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -260.0
	box.offset_right = -14.0
	box.offset_top = 14.0
	box.add_theme_constant_override("separation", 8)
	_ignore(box)
	add_child(box)

	var panel := _panel("HudPanel")
	box.add_child(panel)
	players_label = Label.new()
	players_label.add_theme_font_size_override("font_size", 15)
	_ignore(players_label)
	panel.add_child(players_label)

	var reset := Button.new()
	reset.text = "Zur Station  [K]"
	reset.focus_mode = Control.FOCUS_NONE
	reset.tooltip_text = "Rakete zurücksetzen: du startest wieder an der Erdstation (alle 10 s möglich)."
	reset.pressed.connect(func(): reset_requested.emit())
	box.add_child(reset)


func _build_bottom() -> void:
	var bar := _panel("HudPanel")
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -368.0
	bar.offset_right = 368.0
	bar.offset_top = -112.0
	bar.offset_bottom = -12.0
	add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_ignore(row)
	bar.add_child(row)
	for item in Parts.ITEM_ORDER:
		var d: Dictionary = Parts.ITEMS[item]
		var slot := _panel("InnerPanel")
		slot.custom_minimum_size = Vector2(80, 0)
		row.add_child(slot)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		_ignore(v)
		slot.add_child(v)
		var icon := TextureRect.new()
		icon.texture = Assets.tex(d["icon"])
		icon.custom_minimum_size = Vector2(38, 38)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_ignore(icon)
		v.add_child(icon)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		_ignore(l)
		v.add_child(l)
		slot_labels[item] = l
		slot_panels[item] = slot

	hint_label = Label.new()
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_left = -330.0
	hint_label.offset_right = 330.0
	hint_label.offset_top = -152.0
	hint_label.offset_bottom = -120.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 21)
	hint_label.add_theme_color_override("font_color", UiTheme.GOLD)
	hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hint_label.add_theme_constant_override("outline_size", 6)
	_ignore(hint_label)
	add_child(hint_label)

	var keys := Label.new()
	keys.text = "M Karte  ·  H Hilfe  ·  F11 Vollbild  ·  Esc Menü"
	keys.anchor_left = 1.0
	keys.anchor_right = 1.0
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.offset_left = -420.0
	keys.offset_right = -14.0
	keys.offset_top = -34.0
	keys.offset_bottom = -10.0
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.add_theme_font_size_override("font_size", 14)
	keys.add_theme_color_override("font_color", UiTheme.MUTED)
	keys.add_theme_color_override("font_outline_color", Color.BLACK)
	keys.add_theme_constant_override("outline_size", 4)
	_ignore(keys)
	add_child(keys)


func _build_center() -> void:
	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.offset_left = -330.0
	toast_box.offset_right = 330.0
	toast_box.offset_top = 70.0
	_ignore(toast_box)
	add_child(toast_box)

	center_label = Label.new()
	center_label.anchor_left = 0.5
	center_label.anchor_right = 0.5
	center_label.anchor_top = 0.28
	center_label.anchor_bottom = 0.28
	center_label.offset_left = -400.0
	center_label.offset_right = 400.0
	center_label.offset_bottom = 90.0
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 34)
	center_label.add_theme_color_override("font_outline_color", Color.BLACK)
	center_label.add_theme_constant_override("outline_size", 8)
	_ignore(center_label)
	add_child(center_label)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -330.0
	help_panel.offset_right = 330.0
	help_panel.offset_top = -245.0
	help_panel.offset_bottom = 245.0
	_ignore(help_panel)
	add_child(help_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_ignore(v)
	help_panel.add_child(v)
	v.add_child(UiTheme.heading("STEUERUNG", 26, UiTheme.ACCENT))
	v.add_child(UiTheme.hazard(8))
	var l := Label.new()
	l.text = "Leertaste / W / ↑        Schub\n" \
		+ "S / ↓                        Bremsschub (rückwärts)\n" \
		+ "A D / ← →                 Rakete drehen\n" \
		+ "Mausrad                     Kamera zoomen\n" \
		+ "M                              Karte (ziehen + Mausrad)\n" \
		+ "E                              Shop (gelandet an der Erdstation)\n" \
		+ "K                              Zurück zur Station (Reset)\n" \
		+ "X / Linksklick        Waffe feuern (falls ausgerüstet)\n" \
		+ "Q Torpedo · V EMP · B Mine  (PvP-Addons)\n" \
		+ "Shift Boost · F Fallschirm · R Reparatur\n" \
		+ "T Notfalltank · G Schutzschild\n" \
		+ "F11                           Vollbild an/aus\n\n" \
		+ "LANDEN: Nase vom Planeten weg und vorher abbremsen!\n" \
		+ "Coins: alle 5 Min. im Flug, viele bei der Landung auf Planeten.\n\n" \
		+ "[H] Hilfe ein-/ausblenden"
	l.add_theme_font_size_override("font_size", 16)
	_ignore(l)
	v.add_child(l)


# ================================================================= Updates
func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func set_players(names: Array) -> void:
	var t := "PILOTEN ONLINE (%d)\n" % names.size()
	for n in names:
		t += "• %s\n" % n
	players_label.text = t.strip_edges()


func center_message(text: String, color: Color = Color.WHITE) -> void:
	center_label.text = text
	center_label.add_theme_color_override("font_color", color)


func set_hint(text: String) -> void:
	hint_label.text = text


func toast(text: String, kind: String = "info") -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	var c := UiTheme.TEXT
	if kind == "coin":
		c = UiTheme.GOLD
	elif kind == "warn":
		c = UiTheme.BAD
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_ignore(l)
	toast_box.add_child(l)
	while toast_box.get_child_count() > 5:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_interval(3.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


# d: name, coins, hp, max_hp, fuel, max_fuel, items, boost_t, shield_t, chute,
#    info (Text), info_color, hint
func update_hud(d: Dictionary) -> void:
	name_label.text = str(d["name"])
	coin_label.text = " %d" % int(d["coins"])
	hull_bar.max_value = float(d["max_hp"])
	hull_bar.value = clampf(float(d["hp"]), 0.0, float(d["max_hp"]))
	hull_label.text = "%d/%d" % [int(round(float(d["hp"]))), int(d["max_hp"])]
	fuel_bar.max_value = float(d["max_fuel"])
	fuel_bar.value = float(d["fuel"])
	fuel_label.text = "%d/%d" % [int(round(float(d["fuel"]))), int(d["max_fuel"])]
	faction_label.text = str(d["faction_text"])
	faction_label.add_theme_color_override("font_color", d["faction_color"])
	info_label.text = str(d["info"])
	info_label.add_theme_color_override("font_color", d["info_color"])
	hint_label.text = str(d["hint"])

	var items: Dictionary = d["items"]
	for item in Parts.ITEM_ORDER:
		var count: int = int(items.get(item, 0))
		var key: String = Parts.ITEMS[item]["key"]
		var l: Label = slot_labels[item]
		var extra := ""
		if item == "boost" and float(d["boost_t"]) > 0.0:
			extra = " (%ds)" % int(ceil(float(d["boost_t"])))
		elif item == "shield" and float(d["shield_t"]) > 0.0:
			extra = " (%ds)" % int(ceil(float(d["shield_t"])))
		elif item == "chute" and bool(d["chute"]):
			extra = " (offen)"
		l.text = "[%s] ×%d%s" % [key, count, extra]
		l.add_theme_font_size_override("font_size", 12)
		var panel: PanelContainer = slot_panels[item]
		panel.modulate = Color(1, 1, 1, 1) if count > 0 else Color(1, 1, 1, 0.45)
		if extra != "":
			panel.modulate = Color(1.35, 1.15, 0.8, 1)
