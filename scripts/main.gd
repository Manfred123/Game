extends Node
# Wurzel-Szene: wechselt zwischen Hauptmenü, Spiel und Server-Ansicht.
#
# Dedizierter Server ohne Fenster (z. B. auf einem Rechner ohne Bildschirm):
#   godot --headless --path . -- --server --name "Welt 1" --port 7777

const InputSetup = preload("res://scripts/input_setup.gd")
const Cfg = preload("res://scripts/config.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const MenuScript = preload("res://scripts/menu.gd")
const GameScript = preload("res://scripts/game.gd")
const ServerViewScript = preload("res://scripts/server_view.gd")

var current: Node = null


func _ready() -> void:
	InputSetup.setup()
	Net.join_accepted.connect(_on_join_accepted)
	Net.join_rejected.connect(_on_join_rejected)
	Net.connect_failed.connect(_on_connect_failed)
	Net.server_lost.connect(_on_server_lost)

	var args := OS.get_cmdline_user_args()
	if not args.has("--server"):
		Net.apply_fullscreen()
	if args.has("--server"):
		var sname := "Dedizierte Welt"
		var port := Cfg.BASE_PORT
		var i := 0
		while i < args.size():
			if args[i] == "--name" and i + 1 < args.size():
				sname = args[i + 1]
			elif args[i] == "--port" and i + 1 < args.size():
				port = int(args[i + 1])
			i += 1
		if Net.host_server(sname, port) != OK:
			push_error("Server konnte nicht gestartet werden (Ports belegt?).")
			get_tree().quit(1)
			return
		show_server_view()
	else:
		show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Net.toggle_fullscreen()


func _swap(node: Node) -> void:
	if current != null:
		remove_child(current)
		current.queue_free()
	current = node
	add_child(node)


func show_menu(message: String = "") -> void:
	get_window().title = "Raketen Online"
	var m = MenuScript.new()
	m.join_requested.connect(_on_join_requested)
	m.host_requested.connect(_on_host_requested)
	_swap(m)
	if message != "":
		m.set_status(message, UiTheme.BAD)


func show_server_view() -> void:
	get_window().title = "Raketen Online - SERVER '%s' (Port %d)" % [Net.server_name, Net.server_port]
	var v = ServerViewScript.new()
	v.stop_requested.connect(_on_leave)
	_swap(v)


func show_game(info: Dictionary) -> void:
	get_window().title = "Raketen Online - %s (%s)" % [info.get("name", "Pilot"), info.get("server_name", "")]
	var g = GameScript.new()
	g.init_info = info
	g.leave_requested.connect(_on_leave)
	_swap(g)


func _on_leave() -> void:
	Net.stop()
	show_menu()


func _menu_active() -> bool:
	return current != null and current.has_method("set_status")


func _on_join_requested(ip: String, port: int) -> void:
	var err: int = Net.join_server(ip, port)
	if err != OK:
		if _menu_active():
			current.set_status("Verbindung nicht möglich (Fehler %d)." % err, UiTheme.BAD)
		return
	if _menu_active():
		current.set_status("Verbinde mit %s:%d ..." % [ip, port], UiTheme.CYAN)
		current.set_busy(true)


func _on_host_requested(sname: String) -> void:
	if Net.host_server(sname) == OK:
		show_server_view()
	elif _menu_active():
		current.set_status("Server konnte nicht gestartet werden (alle Ports %d-%d belegt?)." % [
			Cfg.BASE_PORT, Cfg.BASE_PORT + Cfg.MAX_SERVERS_PER_PC - 1], UiTheme.BAD)


func _on_join_accepted(info: Dictionary) -> void:
	show_game(info)


func _on_join_rejected(reason: String) -> void:
	Net.stop()
	show_menu("Beitritt abgelehnt: " + reason)


func _on_connect_failed() -> void:
	if _menu_active():
		current.set_busy(false)
		current.set_status("Verbindung fehlgeschlagen. Läuft der Server? Firewall?", UiTheme.BAD)


func _on_server_lost() -> void:
	show_menu("Die Verbindung zum Server wurde getrennt.")
