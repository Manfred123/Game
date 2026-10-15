extends Control
# Hauptmenü im Raketen-Look: Spielername, Serverliste (automatische Suche im LAN),
# direkt verbinden, eigenen Server starten, Vollbild.

const Cfg = preload("res://scripts/config.gd")
const Parts = preload("res://scripts/parts.gd")
const Assets = preload("res://scripts/assets.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")

signal join_requested(ip: String, port: int)
signal host_requested(server_name: String)

var name_edit: LineEdit
var list: ItemList
var join_btn: Button
var refresh_btn: Button
var ip_edit: LineEdit
var direct_btn: Button
var host_edit: LineEdit
var host_btn: Button
var status: Label
var list_hint: Label
var holder: Control
var rocket

var selected_uid := ""
var _t := 0.0
var _tier := 0
var _tier_timer := 0.0


func _ready() -> void:
	UiTheme.full_rect(self)
	theme = UiTheme.build()

	var bg := TextureRect.new()
	bg.texture = Assets.tex("res://assets/ui/menu_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UiTheme.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	UiTheme.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	margin.add_child(hb)

	# ------------------------------------------------ links: Titel + Rakete
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	hb.add_child(left)
	for pair in [["RAKETEN", UiTheme.ACCENT], ["ONLINE", Color.WHITE]]:
		var title := Label.new()
		title.text = pair[0]
		title.add_theme_font_size_override("font_size", 78)
		title.add_theme_color_override("font_color", pair[1])
		title.add_theme_color_override("font_outline_color", Color(0.06, 0.08, 0.16))
		title.add_theme_constant_override("outline_size", 12)
		left.add_child(title)
	var hz := UiTheme.hazard(12)
	hz.custom_minimum_size = Vector2(300, 12)
	hz.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(hz)
	var sub := Label.new()
	sub.text = "Starte von der Erde, lande auf fremden Planeten\nund rüste deine Rakete im Shop auf."
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", UiTheme.TEXT)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 5)
	left.add_child(sub)
	holder = Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(300, 260)
	left.add_child(holder)
	rocket = RocketVisual.new()
	rocket.name_label.visible = false
	rocket.thrust = 1.0
	rocket.scale = Vector2.ONE * 2.2
	holder.add_child(rocket)

	# ------------------------------------------------ rechts: Startrampe
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	v.add_child(UiTheme.heading("STARTRAMPE", 26, UiTheme.ACCENT))
	v.add_child(UiTheme.hazard(8))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	v.add_child(name_row)
	var nl := UiTheme.heading("PILOT", 18)
	nl.custom_minimum_size = Vector2(70, 0)
	name_row.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.max_length = Cfg.MAX_NAME_LEN
	name_edit.placeholder_text = "Dein Pilotenname"
	name_edit.text = Net.player_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)

	v.add_child(UiTheme.heading("WELTEN (SERVER)", 18))
	list = ItemList.new()
	list.custom_minimum_size = Vector2(0, 130)
	list.fixed_icon_size = Vector2i(28, 28)
	list.item_selected.connect(_on_item_selected)
	list.item_activated.connect(_on_item_activated)
	v.add_child(list)
	list_hint = Label.new()
	list_hint.add_theme_font_size_override("font_size", 14)
	list_hint.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(list_hint)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	v.add_child(row1)
	refresh_btn = Button.new()
	refresh_btn.text = "Neu suchen"
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_on_refresh)
	row1.add_child(refresh_btn)
	join_btn = UiTheme.accent_button("WELT BEITRETEN")
	join_btn.disabled = true
	join_btn.custom_minimum_size = Vector2(0, 46)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	row1.add_child(join_btn)

	v.add_child(UiTheme.hazard(6))
	v.add_child(UiTheme.heading("DIREKT VERBINDEN  (IP oder IP:Port)", 18))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	v.add_child(row2)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "z. B. 192.168.0.12:7777"
	ip_edit.text = Net.last_ip
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(func(_txt): _on_direct_pressed())
	row2.add_child(ip_edit)
	direct_btn = Button.new()
	direct_btn.text = "Verbinden"
	direct_btn.focus_mode = Control.FOCUS_NONE
	direct_btn.pressed.connect(_on_direct_pressed)
	row2.add_child(direct_btn)

	v.add_child(UiTheme.hazard(6))
	v.add_child(UiTheme.heading("EIGENE WELT STARTEN  (dieser PC wird Server)", 18))
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	v.add_child(row3)
	host_edit = LineEdit.new()
	host_edit.placeholder_text = "Name der Welt"
	host_edit.text = Net.host_name
	host_edit.max_length = 24
	host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(host_edit)
	host_btn = Button.new()
	host_btn.text = "Server starten"
	host_btn.focus_mode = Control.FOCUS_NONE
	host_btn.pressed.connect(_on_host_pressed)
	row3.add_child(host_btn)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(0, 24)
	status.add_theme_font_size_override("font_size", 15)
	v.add_child(status)

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 8)
	v.add_child(row4)
	var fs := Button.new()
	fs.text = "Vollbild an/aus (F11)"
	fs.focus_mode = Control.FOCUS_NONE
	fs.pressed.connect(func(): Net.toggle_fullscreen())
	row4.add_child(fs)
	var quit_btn := Button.new()
	quit_btn.text = "Spiel beenden"
	quit_btn.focus_mode = Control.FOCUS_NONE
	quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_btn.pressed.connect(func(): get_tree().quit())
	row4.add_child(quit_btn)

	Net.server_list_changed.connect(_rebuild_list)
	Net.set_scanning(true)
	_rebuild_list()


func _exit_tree() -> void:
	Net.set_scanning(false)


func _process(delta: float) -> void:
	_t += delta
	if holder != null:
		rocket.position = holder.size / 2.0 + Vector2(0, sin(_t * 1.3) * 10.0)
		rocket.set_body_rotation(sin(_t * 0.8) * 0.12)
	# Die Rakete zeigt der Reihe nach alle Ausbaustufen
	_tier_timer += delta
	if _tier_timer > 2.2:
		_tier_timer = 0.0
		_tier = (_tier + 1) % 5
		var lv := {}
		for c in Parts.DRAW_ORDER:
			lv[c] = _tier
		rocket.set_levels(lv)


# ------------------------------------------------------------- Öffentlich
func set_status(text: String, color: Color = UiTheme.MUTED) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)


func set_busy(busy: bool) -> void:
	join_btn.disabled = busy or selected_uid == ""
	direct_btn.disabled = busy
	host_btn.disabled = busy
	refresh_btn.disabled = busy


# --------------------------------------------------------------- Liste
func _rebuild_list() -> void:
	var entries: Array = Net.servers.values()
	entries.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	list.clear()
	var sel_idx := -1
	for e in entries:
		var txt := "%s     %d/%d Spieler     %s:%d" % [e["name"], e["players"], e["max"], e["ip"], e["port"]]
		if int(e["version"]) != Cfg.VERSION:
			txt += "     (andere Version!)"
		var idx := list.add_item(txt, Assets.tex("res://assets/ui/rocket_icon.png"))
		list.set_item_metadata(idx, e["uid"])
		if e["uid"] == selected_uid:
			sel_idx = idx
	if sel_idx >= 0:
		list.select(sel_idx)
	else:
		selected_uid = ""
	join_btn.disabled = selected_uid == ""
	if entries.is_empty():
		list_hint.text = "Suche Server im LAN ... keine gefunden. Starte unten eine eigene Welt oder gib eine IP ein."
	else:
		list_hint.text = "%d Welt(en) gefunden. Doppelklick = beitreten." % entries.size()


func _on_item_selected(index: int) -> void:
	selected_uid = str(list.get_item_metadata(index))
	join_btn.disabled = false


func _on_item_activated(index: int) -> void:
	selected_uid = str(list.get_item_metadata(index))
	_on_join_pressed()


func _on_refresh() -> void:
	selected_uid = ""
	Net.refresh_now()


func _remember_name() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Pilot"
	Net.player_name = n
	Net.host_name = host_edit.text.strip_edges()
	Net.save_settings()


func _on_join_pressed() -> void:
	if selected_uid == "" or not Net.servers.has(selected_uid):
		return
	_remember_name()
	var e: Dictionary = Net.servers[selected_uid]
	join_requested.emit(str(e["ip"]), int(e["port"]))


func _on_direct_pressed() -> void:
	var t := ip_edit.text.strip_edges()
	if t == "":
		return
	var ip := t
	var port := Cfg.BASE_PORT
	if t.contains(":"):
		var parts := t.split(":")
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	_remember_name()
	join_requested.emit(ip, port)


func _on_host_pressed() -> void:
	_remember_name()
	host_requested.emit(host_edit.text.strip_edges())
