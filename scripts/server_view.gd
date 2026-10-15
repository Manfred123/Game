extends Control
# Anzeige, während diese Instanz als Server läuft: Spieler, Ereignisse und das
# Netzwerk-Protokoll (gesendete/empfangene Nachrichten mit Typ, Client-ID, Inhalt).

const Cfg = preload("res://scripts/config.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const Assets = preload("res://scripts/assets.gd")

signal stop_requested

var info_label: Label
var players_label: Label
var log_box: RichTextLabel
var net_box: RichTextLabel
var _timer := 0.0


func _ready() -> void:
	UiTheme.full_rect(self)
	theme = UiTheme.build()
	var bg := TextureRect.new()
	bg.texture = Assets.tex("res://assets/ui/menu_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UiTheme.full_rect(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	UiTheme.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	v.add_child(UiTheme.heading("MISSION CONTROL  ·  SERVER LÄUFT", 30, UiTheme.GOOD))
	v.add_child(UiTheme.hazard(9))
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 17)
	v.add_child(info_label)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	v.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	cols.add_child(left)
	left.add_child(UiTheme.heading("SPIELER IN DIESER WELT", 18))
	var pp := PanelContainer.new()
	pp.theme_type_variation = "InnerPanel"
	pp.custom_minimum_size = Vector2(0, 120)
	left.add_child(pp)
	players_label = Label.new()
	players_label.add_theme_font_size_override("font_size", 15)
	pp.add_child(players_label)
	left.add_child(UiTheme.heading("EREIGNISSE", 18))
	log_box = _log_box()
	left.add_child(log_box)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.2
	cols.add_child(right)
	right.add_child(UiTheme.heading("NETZWERK-PROTOKOLL  (SEND / RECV / DROP)", 18))
	net_box = _log_box()
	net_box.add_theme_font_size_override("normal_font_size", 13)
	right.add_child(net_box)
	var path := Label.new()
	path.text = "Vollständige Datei (alle Nachrichten): %s" % Net.log_path
	path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	path.add_theme_font_size_override("font_size", 12)
	path.add_theme_color_override("font_color", UiTheme.MUTED)
	right.add_child(path)

	var stop := UiTheme.accent_button("SERVER BEENDEN UND ZURÜCK ZUM MENÜ")
	stop.custom_minimum_size = Vector2(0, 46)
	stop.pressed.connect(func(): stop_requested.emit())
	v.add_child(stop)

	Net.server_log.connect(_on_log)
	Net.net_log_line.connect(_on_net_log)
	_on_log("Server '%s' läuft auf Port %d (UDP)." % [Net.server_name, Net.server_port])
	_refresh()


func _log_box() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.scroll_following = true
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.custom_minimum_size = Vector2(0, 120)
	return r


func _on_log(line: String) -> void:
	log_box.add_text("[%s] %s\n" % [Time.get_time_string_from_system(), line])


func _on_net_log(line: String) -> void:
	net_box.add_text(line + "\n")
	if net_box.get_line_count() > 600:
		net_box.clear()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var ips := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			ips.append(a)
	var up := 0
	if Net.sim != null:
		up = int(Net.sim.uptime)
	info_label.text = "Welt: %s   ·   UDP-Port %d (Spiel) + %d (Server-Suche)   ·   Laufzeit %d:%02d min\nAdressen für „Direkt verbinden“ im LAN: %s" % [
		Net.server_name, Net.server_port, Net.server_port + Cfg.DISCOVERY_OFFSET, floori(up / 60.0), up % 60,
		", ".join(ips) if ips.size() > 0 else "-"]
	if Net.sim == null:
		return
	var rows: Array = Net.sim.get_player_rows()
	if rows.is_empty():
		players_label.text = "Noch niemand hier ..."
		return
	var t := ""
	for r in rows:
		t += "%s  |  %d Coins  |  %s  |  %d m/s  |  Rumpf %d\n" % [r["name"], r["coins"], r["where"], r["speed"], r["hp"]]
	players_label.text = t.strip_edges()
