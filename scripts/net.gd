extends Node
# Autoload "Net": kümmert sich um Verbindungen, die Server-Suche und alle RPCs.
# Server und Client benutzen dasselbe Skript (Godot verlangt gleiche RPC-Listen auf
# beiden Seiten). Die Spiellogik des Servers steckt in server_sim.gd.

const Cfg = preload("res://scripts/config.gd")
const ServerSim = preload("res://scripts/server_sim.gd")

# ----- Signale für die Oberfläche / das Spiel
signal server_list_changed
signal join_accepted(info: Dictionary)
signal join_rejected(reason: String)
signal connect_failed
signal server_lost
signal snapshot_received(tick: int, ids: PackedInt32Array, data: PackedFloat32Array)
signal remote_player_joined(id: int, info: Dictionary)
signal remote_player_left(id: int)
signal remote_parts_changed(id: int, levels: Dictionary)
signal profile_received(profile: Dictionary)
signal notice(text: String, kind: String)
signal fx_event(kind: String, id: int, pos: Vector2, value: float)
signal projectiles_received(data: PackedFloat32Array)
signal player_faction_changed(id: int, faction: int)
signal player_paint_changed(id: int, paint: int)
signal faction_state_received(state: Dictionary)
signal server_log(line: String)
signal net_log_line(line: String)

enum Role { NONE, SERVER, CLIENT }

var role: int = Role.NONE
var sim = null

# Servereinstellungen
var server_name := ""
var server_port := 0
var server_uid := ""

# Clienteinstellungen
var my_id := 0
var player_name := "Pilot"
var last_ip := "127.0.0.1"
var host_name := "Meine Welt"
var fullscreen := true

# Server-Suche
var servers: Dictionary = {}          # uid -> Dictionary
var scanning := false
var _scan_sock: PacketPeerUDP = null
var _scan_timer := 0.0
var _disc_srv: PacketPeerUDP = null

# Netzwerk-Protokoll
const HIGH_FREQ := ["rpc_send_input", "rpc_snapshot", "rpc_projectiles"]
var log_file: FileAccess = null
var log_path := ""
var _log_counts: Dictionary = {}
var _log_flush_t := 0.0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	_load_settings()


func _process(delta: float) -> void:
	_log_flush_t += delta
	if _log_flush_t > 1.0 and log_file != null:
		_log_flush_t = 0.0
		log_file.flush()
	if _disc_srv != null:
		_poll_discovery_server()
	if scanning:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = 2.0
			_send_scan()
		_poll_scan_replies()
		_prune_servers()


# =========================================================== Einstellungen
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		player_name = str(cf.get_value("player", "name", player_name))
		last_ip = str(cf.get_value("player", "last_ip", last_ip))
		host_name = str(cf.get_value("host", "name", host_name))
		fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "name", player_name)
	cf.set_value("player", "last_ip", last_ip)
	cf.set_value("host", "name", host_name)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.save("user://settings.cfg")


# ====================================================== Netzwerk-Protokoll
# Jede gesendete/empfangene Nachricht wird mit Richtung, Typ, Client-ID und Inhalt
# in die Datei user://netlog_<rolle>_<zeit>.log geschrieben (und teilweise in die Konsole).
func _open_log(kind: String) -> void:
	_close_log()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://netlog_%s_%s_%d.log" % [kind, stamp, OS.get_process_id()]
	log_file = FileAccess.open(path, FileAccess.WRITE)
	if log_file != null:
		log_path = ProjectSettings.globalize_path(path)
		print("[Netzwerk-Log] ", log_path)


func _close_log() -> void:
	if log_file != null:
		log_file.flush()
		log_file = null


# direction: "SEND", "RECV", "DROP" (vom Server verworfen) oder "EVENT"; client_id: beteiligter Client (0 = alle)
func net_log(direction: String, method: String, client_id: int, content: String) -> void:
	var mtype := method.trim_prefix("rpc_").to_upper()
	var who := "ALL" if client_id == 0 else str(client_id)
	var line := "[%s] %-5s %-14s client=%-10s | %s" % [Time.get_time_string_from_system(), direction, mtype, who, content]
	if log_file != null:
		log_file.store_line(line)
	var n: int = int(_log_counts.get(method, 0)) + 1
	_log_counts[method] = n
	if method in HIGH_FREQ and direction != "DROP" and (n - 1) % Cfg.LOG_SAMPLE != 0:
		return
	print(line)
	net_log_line.emit(line)


func _fmt_args(method: String, args: Array) -> String:
	if method == "rpc_snapshot":
		var ids: PackedInt32Array = args[1]
		var data: PackedFloat32Array = args[2]
		var t := "tick=%d spieler=%d " % [args[0], ids.size()]
		for i in mini(ids.size(), 4):
			var o: int = i * Cfg.SNAP_STRIDE
			t += "[%d: pos=(%.0f,%.0f) v=(%.0f,%.0f) hp=%.0f] " % [ids[i], data[o], data[o + 1], data[o + 3], data[o + 4], data[o + 7]]
		return t
	if method == "rpc_projectiles":
		var pd: PackedFloat32Array = args[0]
		return "objekte=%d" % int(pd.size() / 5)
	if method == "rpc_send_input":
		return "seq=%d flags=%s" % [args[0], String.num_int64(int(args[1]), 2).pad_zeros(5)]
	return ", ".join(PackedStringArray(args.map(func(a): return str(a))))


# Alle ausgehenden Nachrichten laufen hier durch (damit sie protokolliert werden).
func send_to(peer: int, method: String, args: Array) -> void:
	net_log("SEND", method, peer if peer != 1 else my_id, _fmt_args(method, args))
	callv("rpc_id", [peer, method] + args)


func send_all(method: String, args: Array) -> void:
	net_log("SEND", method, 0, _fmt_args(method, args))
	callv("rpc", [method] + args)


func log_recv(method: String, sender: int, args: Array) -> void:
	net_log("RECV", method, sender if sender != 1 else my_id, _fmt_args(method, args))


# ================================================================ Vollbild
func apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# get_tree().root ist immer das echte Betriebssystem-Fenster (anders als get_window(),
	# das je nach Godot-Version/Kontext auch mal ein eingebettetes Sub-Viewport liefern kann).
	var w: Window = get_tree().root
	w.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	print("[Vollbild] ", "an" if fullscreen else "aus", " -> Fenstermodus jetzt: ", w.mode)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_fullscreen()
	save_settings()


# ================================================================== Server
# Startet einen Server auf dem ersten freien Port ab start_port.
func host_server(sname: String, start_port: int = Cfg.BASE_PORT) -> int:
	stop()
	var port := start_port
	var last := start_port + Cfg.MAX_SERVERS_PER_PC
	while port < last:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, Cfg.MAX_PLAYERS)
		if err == OK:
			var udp := PacketPeerUDP.new()
			if udp.bind(port + Cfg.DISCOVERY_OFFSET) == OK:
				multiplayer.multiplayer_peer = peer
				_disc_srv = udp
				role = Role.SERVER
				_open_log("server")
				server_port = port
				server_name = sname.strip_edges()
				if server_name == "":
					server_name = "Welt auf Port %d" % port
				server_uid = "%08x%08x" % [randi(), randi()]
				sim = ServerSim.new()
				sim.net = self
				sim.log_line.connect(_on_sim_log)
				add_child(sim)
				_on_sim_log("Server '%s' läuft auf Port %d." % [server_name, port])
				return OK
			udp.close()
			peer.close()
		port += 1
	return ERR_CANT_CREATE


func _on_sim_log(text: String) -> void:
	print("[Server] ", text)
	server_log.emit(text)


func _poll_discovery_server() -> void:
	while _disc_srv.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _disc_srv.get_packet()
		var ip: String = _disc_srv.get_packet_ip()
		var port: int = _disc_srv.get_packet_port()
		if pkt.get_string_from_utf8() != Cfg.DISCOVER_MAGIC:
			continue
		var count := 0
		if sim != null:
			count = sim.players.size()
		var info := {
			"g": Cfg.GAME_ID, "v": Cfg.VERSION, "uid": server_uid, "name": server_name,
			"port": server_port, "players": count, "max": Cfg.MAX_PLAYERS,
		}
		_disc_srv.set_dest_address(ip, port)
		_disc_srv.put_packet(JSON.stringify(info).to_utf8_buffer())


# ================================================================== Client
func join_server(ip: String, port: int) -> int:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_open_log("client")
	last_ip = "%s:%d" % [ip, port]
	return OK


# Trennt alles und geht zurück in den Offline-Zustand.
func stop() -> void:
	var p: MultiplayerPeer = multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if sim != null:
		sim.queue_free()
		sim = null
	if _disc_srv != null:
		_disc_srv.close()
		_disc_srv = null
	role = Role.NONE
	my_id = 0
	_close_log()


func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	net_log("EVENT", "rpc_connected", my_id, "Verbindung zum Server steht")
	send_to(1, "rpc_join_request", [player_name, Cfg.VERSION])


func _on_connection_failed() -> void:
	stop()
	connect_failed.emit()


func _on_server_disconnected() -> void:
	if role == Role.CLIENT:
		stop()
		server_lost.emit()


func _on_peer_connected(id: int) -> void:
	if role == Role.SERVER:
		net_log("EVENT", "rpc_peer_connected", id, "Client verbunden (UDP/ENet)")


func _on_peer_disconnected(id: int) -> void:
	if role == Role.SERVER:
		net_log("EVENT", "rpc_peer_disconnected", id, "Client getrennt")
	if role == Role.SERVER and sim != null:
		sim.remove_player(id)


# ============================================================= Server-Suche
func set_scanning(on: bool) -> void:
	scanning = on
	if on:
		_scan_timer = 0.0
	elif _scan_sock != null:
		_scan_sock.close()
		_scan_sock = null


func refresh_now() -> void:
	servers.clear()
	server_list_changed.emit()
	_scan_timer = 0.0


# Fragt alle möglichen Ports auf diesem PC (127.0.0.1) und im LAN (Broadcast) ab.
func _send_scan() -> void:
	if _scan_sock == null:
		_scan_sock = PacketPeerUDP.new()
		_scan_sock.set_broadcast_enabled(true)
	var msg: PackedByteArray = Cfg.DISCOVER_MAGIC.to_utf8_buffer()
	for i in Cfg.MAX_SERVERS_PER_PC:
		var dport: int = Cfg.BASE_PORT + i + Cfg.DISCOVERY_OFFSET
		_scan_sock.set_dest_address("127.0.0.1", dport)
		_scan_sock.put_packet(msg)
		_scan_sock.set_dest_address("255.255.255.255", dport)
		_scan_sock.put_packet(msg)
		for bc in _lan_broadcasts():
			_scan_sock.set_dest_address(bc, dport)
			_scan_sock.put_packet(msg)


# Gerichtete Broadcast-Adressen (z. B. 192.168.0.255) aller lokalen IPv4-Netze
func _lan_broadcasts() -> PackedStringArray:
	var res := PackedStringArray()
	for a in IP.get_local_addresses():
		var parts := a.split(".")
		if parts.size() == 4 and not a.begins_with("127.") and not a.begins_with("169.254."):
			var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not res.has(b):
				res.append(b)
	return res


func _poll_scan_replies() -> void:
	if _scan_sock == null:
		return
	while _scan_sock.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _scan_sock.get_packet()
		var ip: String = _scan_sock.get_packet_ip()
		var parsed = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed
		if str(d.get("g", "")) != Cfg.GAME_ID:
			continue
		var uid: String = str(d.get("uid", ""))
		if uid == "":
			continue
		var entry := {
			"uid": uid, "name": str(d.get("name", "?")), "ip": ip,
			"port": int(d.get("port", 0)), "players": int(d.get("players", 0)),
			"max": int(d.get("max", 0)), "version": int(d.get("v", 0)),
			"seen": Time.get_ticks_msec(),
		}
		var changed := true
		if servers.has(uid):
			entry["ip"] = servers[uid]["ip"]      # erste gültige Adresse behalten
			changed = servers[uid]["players"] != entry["players"] or servers[uid]["name"] != entry["name"]
		servers[uid] = entry
		if changed:
			server_list_changed.emit()


func _prune_servers() -> void:
	var now := Time.get_ticks_msec()
	var gone: Array = []
	for uid in servers:
		if now - int(servers[uid]["seen"]) > 7000:
			gone.append(uid)
	for uid in gone:
		servers.erase(uid)
	if gone.size() > 0:
		server_list_changed.emit()


# =================================================================== RPCs
# ----- Client -> Server
@rpc("any_peer", "call_remote", "reliable")
func rpc_join_request(pname: String, version: int) -> void:
	log_recv("rpc_join_request", multiplayer.get_remote_sender_id(), [pname, version])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_join(multiplayer.get_remote_sender_id(), pname, version)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_send_input(seq: int, flags: int) -> void:
	log_recv("rpc_send_input", multiplayer.get_remote_sender_id(), [seq, flags])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_input(multiplayer.get_remote_sender_id(), seq, flags)


@rpc("any_peer", "call_remote", "reliable")
func rpc_buy_part(cat: String, idx: int) -> void:
	log_recv("rpc_buy_part", multiplayer.get_remote_sender_id(), [cat, idx])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_buy_part(multiplayer.get_remote_sender_id(), cat, idx)


@rpc("any_peer", "call_remote", "reliable")
func rpc_equip_part(cat: String, idx: int) -> void:
	log_recv("rpc_equip_part", multiplayer.get_remote_sender_id(), [cat, idx])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_equip_part(multiplayer.get_remote_sender_id(), cat, idx)


@rpc("any_peer", "call_remote", "reliable")
func rpc_join_faction(f: int) -> void:
	log_recv("rpc_join_faction", multiplayer.get_remote_sender_id(), [f])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_join_faction(multiplayer.get_remote_sender_id(), f)


@rpc("any_peer", "call_remote", "reliable")
func rpc_buy_paint(idx: int) -> void:
	log_recv("rpc_buy_paint", multiplayer.get_remote_sender_id(), [idx])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_buy_paint(multiplayer.get_remote_sender_id(), idx)


@rpc("any_peer", "call_remote", "reliable")
func rpc_equip_paint(idx: int) -> void:
	log_recv("rpc_equip_paint", multiplayer.get_remote_sender_id(), [idx])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_equip_paint(multiplayer.get_remote_sender_id(), idx)


@rpc("any_peer", "call_remote", "reliable")
func rpc_buy_item(item: String) -> void:
	log_recv("rpc_buy_item", multiplayer.get_remote_sender_id(), [item])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_buy_item(multiplayer.get_remote_sender_id(), item)


@rpc("any_peer", "call_remote", "reliable")
func rpc_use_item(item: String) -> void:
	log_recv("rpc_use_item", multiplayer.get_remote_sender_id(), [item])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_use_item(multiplayer.get_remote_sender_id(), item)


@rpc("any_peer", "call_remote", "reliable")
func rpc_reset_request() -> void:
	log_recv("rpc_reset_request", multiplayer.get_remote_sender_id(), [])
	if role != Role.SERVER or sim == null:
		return
	sim.handle_reset(multiplayer.get_remote_sender_id())


# ----- Server -> Client
@rpc("authority", "call_remote", "reliable")
func rpc_join_accepted(info: Dictionary) -> void:
	log_recv("rpc_join_accepted", multiplayer.get_remote_sender_id(), [info])
	if role == Role.CLIENT:
		join_accepted.emit(info)


@rpc("authority", "call_remote", "reliable")
func rpc_join_rejected(reason: String) -> void:
	log_recv("rpc_join_rejected", multiplayer.get_remote_sender_id(), [reason])
	if role == Role.CLIENT:
		join_rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func rpc_player_joined(id: int, info: Dictionary) -> void:
	log_recv("rpc_player_joined", multiplayer.get_remote_sender_id(), [id, info])
	if role == Role.CLIENT:
		remote_player_joined.emit(id, info)


@rpc("authority", "call_remote", "reliable")
func rpc_player_left(id: int) -> void:
	log_recv("rpc_player_left", multiplayer.get_remote_sender_id(), [id])
	if role == Role.CLIENT:
		remote_player_left.emit(id)


@rpc("authority", "call_remote", "reliable")
func rpc_player_parts(id: int, levels: Dictionary) -> void:
	log_recv("rpc_player_parts", multiplayer.get_remote_sender_id(), [id, levels])
	if role == Role.CLIENT:
		remote_parts_changed.emit(id, levels)


@rpc("authority", "call_remote", "reliable")
func rpc_profile(profile: Dictionary) -> void:
	log_recv("rpc_profile", multiplayer.get_remote_sender_id(), [profile])
	if role == Role.CLIENT:
		profile_received.emit(profile)


@rpc("authority", "call_remote", "reliable")
func rpc_notice(text: String, kind: String) -> void:
	log_recv("rpc_notice", multiplayer.get_remote_sender_id(), [text, kind])
	if role == Role.CLIENT:
		notice.emit(text, kind)


@rpc("authority", "call_remote", "reliable")
func rpc_fx(kind: String, id: int, pos: Vector2, value: float) -> void:
	log_recv("rpc_fx", multiplayer.get_remote_sender_id(), [kind, id, pos, value])
	if role == Role.CLIENT:
		fx_event.emit(kind, id, pos, value)


@rpc("authority", "call_remote", "reliable")
func rpc_player_faction(id: int, f: int) -> void:
	log_recv("rpc_player_faction", 1, [id, f])
	if role == Role.CLIENT:
		player_faction_changed.emit(id, f)


@rpc("authority", "call_remote", "reliable")
func rpc_player_paint(id: int, idx: int) -> void:
	log_recv("rpc_player_paint", 1, [id, idx])
	if role == Role.CLIENT:
		player_paint_changed.emit(id, idx)


@rpc("authority", "call_remote", "reliable")
func rpc_faction_state(state: Dictionary) -> void:
	log_recv("rpc_faction_state", 1, [state])
	if role == Role.CLIENT:
		faction_state_received.emit(state)


@rpc("authority", "call_remote", "unreliable")
func rpc_projectiles(data: PackedFloat32Array) -> void:
	log_recv("rpc_projectiles", 1, [data])
	if role == Role.CLIENT:
		projectiles_received.emit(data)


@rpc("authority", "call_remote", "unreliable")
func rpc_snapshot(tick: int, ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	log_recv("rpc_snapshot", multiplayer.get_remote_sender_id(), [tick, ids, data])
	if role == Role.CLIENT:
		snapshot_received.emit(tick, ids, data)


func _exit_tree() -> void:
	stop()
