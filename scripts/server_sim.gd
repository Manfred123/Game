extends Node
# Die autoritative Welt (nur auf dem Server). Der Server simuliert ALLE Raketen, Geschosse,
# Minen, Kollisionen, Schaden, Abschüsse, Coins, Erforschung, Fraktionen und Käufe.
# Clients schicken nur Tasteneingaben (Bits: 1 Schub, 2 Bremse, 4 links, 8 rechts, 16 Feuer).

const Cfg = preload("res://scripts/config.gd")
const Parts = preload("res://scripts/parts.gd")
const Sim = preload("res://scripts/sim.gd")

signal log_line(text: String)


class PD:
	var id: int = 0
	var pname: String = ""
	var coins: int = 0
	var levels: Dictionary = {}          # ausgerüstete Variante je Kategorie
	var owned: Dictionary = {}           # gekaufte Varianten je Kategorie
	var items: Dictionary = {}
	var stats: Dictionary = {}
	var s = null                         # Sim.State
	var input: int = 0
	var last_seq: int = -1
	var flight_time: float = 0.0
	var landing_cd: Dictionary = {}
	var dead_t: float = 0.0
	var joined_at: int = 0
	var last_reset_ms: int = -1000000
	var rate_window: int = 0
	var rate_count: int = 0
	var faction: int = -1
	var kills: int = 0
	var deaths: int = 0
	var fire_cd: float = 0.0
	var last_hit_by: int = 0
	var last_hit_ms: int = -1000000
	var last_faction_ms: int = -1000000
	var disc_planets: Array = []
	var disc_pois: Array = []
	var owned_paints: Array = [0]
	var paint: int = 0


var net = null                           # der Net-Autoload (für RPCs)
var players: Dictionary = {}
var tick: int = 0
var uptime: float = 0.0
var projectiles: Array = []
var mines: Array = []
var fac_kills: Array = []
var _last_proj_count: int = 0
var planet_owner: Array = []             # -1 = frei, sonst Fraktions-Index
var planet_progress: Array = []          # 0..1 Eroberungsfortschritt
var planet_progress_faction: Array = []  # welche Fraktion gerade erobert


func _ready() -> void:
	for i in Cfg.FACTIONS.size():
		fac_kills.append(0)
	for i in Cfg.PLANETS.size():
		planet_owner.append(-1)
		planet_progress.append(0.0)
		planet_progress_faction.append(-1)


func _physics_process(_delta: float) -> void:
	tick += 1
	uptime += Cfg.DT
	for id in players:
		var p: PD = players[id]
		if p.dead_t > 0.0:
			p.dead_t -= Cfg.DT
			if p.dead_t <= 0.0:
				_respawn(p)
			continue
		var ev: Dictionary = Sim.step(p.s, p.input & 15, p.stats, Cfg.DT)
		_handle_events(p, ev)
		_passive(p)
		_combat(p)
	_update_projectiles()
	_update_mines()
	if tick % 6 == 0:
		for id in players:
			var pe: PD = players[id]
			if pe.dead_t <= 0.0:
				_explore(pe)
	_player_collisions()
	for id in players:
		var p2: PD = players[id]
		if p2.dead_t <= 0.0 and p2.s.hp <= 0.0:
			_kill(p2)
	_update_planets_control(Cfg.DT)
	if tick % 180 == 0:                      # alle 3 s: Eroberungsfortschritt an alle
		net.send_all("rpc_faction_state", [faction_state()])
	if tick % Cfg.SNAPSHOT_EVERY == 0:
		_send_snapshot()
		_send_projectiles()


# ============================================================ Beitritt / Austritt
func handle_join(id: int, raw_name: String, version: int) -> void:
	if players.has(id):
		return
	if version != Cfg.VERSION:
		net.send_to(id, "rpc_join_rejected", ["Falsche Spielversion (Server %d, du %d)." % [Cfg.VERSION, version]])
		return
	if players.size() >= Cfg.MAX_PLAYERS:
		net.send_to(id, "rpc_join_rejected", ["Der Server ist voll."])
		return
	var p := PD.new()
	p.id = id
	p.pname = _unique_name(_clean_name(raw_name, id))
	p.coins = Cfg.START_COINS
	p.levels = Parts.default_levels()
	p.owned = Parts.default_owned()
	p.items = Parts.default_items()
	p.stats = Parts.compute_stats(p.levels)
	p.owned_paints = Parts.default_paints()
	p.paint = 0
	p.disc_planets = Cfg.START_DISCOVERED.duplicate()
	p.s = _spawn_state(p)
	p.s.fuel = float(p.stats["max_fuel"])
	p.s.hp = float(p.stats["max_hp"])
	p.joined_at = Time.get_ticks_msec()
	players[id] = p
	var others: Array = []
	for oid in players:
		if oid != id:
			others.append(_public_info(players[oid]))
	net.send_to(id, "rpc_join_accepted", [{
		"you": id, "name": p.pname, "server_name": net.server_name,
		"profile": _profile(p), "players": others, "factions": faction_state(),
	}])
	for oid in players:
		if oid != id:
			net.send_to(oid, "rpc_player_joined", [id, _public_info(p)])
	log_line.emit("%s ist beigetreten (ID %d). Spieler: %d" % [p.pname, id, players.size()])


func remove_player(id: int) -> void:
	if not players.has(id):
		return
	var p: PD = players[id]
	players.erase(id)
	net.send_all("rpc_player_left", [id])
	net.send_all("rpc_faction_state", [faction_state()])
	log_line.emit("%s hat den Server verlassen. Spieler: %d" % [p.pname, players.size()])


# ==================================================================== Eingaben
# Eingaben werden VALIDIERT, bevor sie die Physik erreichen:
#  - bekannter Spieler, nur Bits 0-4 erlaubt, Sequenznummer streng steigend und ohne
#    absurde Sprünge, Ratenbegrenzung pro Client, widersprüchliche Tasten werden bereinigt.
func handle_input(id: int, seq: int, flags: int) -> void:
	if not players.has(id):
		net.net_log("DROP", "rpc_send_input", id, "unbekannter Client")
		return
	var p: PD = players[id]
	var now: int = Time.get_ticks_msec()
	if now - p.rate_window >= 1000:
		p.rate_window = now
		p.rate_count = 0
	p.rate_count += 1
	if p.rate_count > Cfg.MAX_INPUT_RATE:
		if p.rate_count == Cfg.MAX_INPUT_RATE + 1:
			net.net_log("DROP", "rpc_send_input", id, "Ratenlimit überschritten (>%d/s)" % Cfg.MAX_INPUT_RATE)
		return
	if seq <= p.last_seq:
		net.net_log("DROP", "rpc_send_input", id, "veraltete/doppelte seq %d (letzte %d)" % [seq, p.last_seq])
		return
	if p.last_seq >= 0 and seq > p.last_seq + Cfg.MAX_SEQ_JUMP:
		net.net_log("DROP", "rpc_send_input", id, "seq-Sprung %d -> %d" % [p.last_seq, seq])
		return
	if flags < 0 or flags > 31:
		net.net_log("DROP", "rpc_send_input", id, "ungültige Flags %d" % flags)
		return
	if (flags & 4) != 0 and (flags & 8) != 0:
		flags &= ~12                    # links + rechts heben sich auf
	if (flags & 1) != 0 and (flags & 2) != 0:
		flags &= ~2                     # Schub hat Vorrang vor Bremsschub
	p.last_seq = seq
	p.input = flags


func handle_buy_part(id: int, cat: String, idx: int) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or not Parts.UPGRADES.has(cat):
		return
	if idx < 0 or idx > Parts.max_level(cat):
		return
	if not _can_shop(p):
		_notify(p, "Der Shop ist nur an der Erdstation erreichbar.", "warn")
		return
	var owned: Array = p.owned[cat]
	if owned.has(idx):
		return
	var part: Dictionary = Parts.tier(cat, idx)
	var price: int = Parts.price_for(int(part["price"]), p.faction)
	if p.coins < price:
		_notify(p, "Nicht genug Coins.", "warn")
		return
	p.coins -= price
	owned.append(idx)
	_equip(p, cat, idx)
	_notify(p, "%s gekauft und eingebaut." % part["name"], "info")
	log_line.emit("%s kauft %s/%d" % [p.pname, cat, idx])


func handle_equip_part(id: int, cat: String, idx: int) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or not Parts.UPGRADES.has(cat):
		return
	if not _can_shop(p):
		_notify(p, "Umbauen geht nur an der Erdstation.", "warn")
		return
	if not (p.owned[cat] as Array).has(idx):
		return
	_equip(p, cat, idx)


func _equip(p: PD, cat: String, idx: int) -> void:
	p.levels[cat] = idx
	p.stats = Parts.compute_stats(p.levels)
	p.s.hp = minf(p.s.hp, float(p.stats["max_hp"]))
	p.s.fuel = minf(p.s.fuel, float(p.stats["max_fuel"]))
	_send_profile(p)
	net.send_all("rpc_player_parts", [p.id, p.levels])


func handle_buy_item(id: int, item: String) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or not Parts.ITEMS.has(item):
		return
	if not _can_shop(p):
		_notify(p, "Der Shop ist nur an der Erdstation erreichbar.", "warn")
		return
	var have: int = int(p.items.get(item, 0))
	if have >= Cfg.MAX_ITEM_STACK:
		_notify(p, "Du kannst nicht mehr davon tragen.", "warn")
		return
	var price: int = Parts.price_for(int(Parts.ITEMS[item]["price"]), p.faction)
	if p.coins < price:
		_notify(p, "Nicht genug Coins.", "warn")
		return
	p.coins -= price
	p.items[item] = have + 1
	_send_profile(p)


# Fraktion beitreten/wechseln (f = -1: austreten). Nur an der Station, nicht im Kampf.
func handle_join_faction(id: int, f: int) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or f < -1 or f >= Cfg.FACTIONS.size():
		return
	if f == p.faction:
		return
	if not _can_shop(p):
		_notify(p, "Fraktionen wechselst du nur an der Erdstation.", "warn")
		return
	var now: int = Time.get_ticks_msec()
	if now - p.last_hit_ms < 30000:
		_notify(p, "Nicht direkt nach einem Gefecht.", "warn")
		return
	var wait: int = int(Cfg.FACTION_SWITCH_COOLDOWN * 1000.0) - (now - p.last_faction_ms)
	if wait > 0 and p.faction != -1:
		_notify(p, "Fraktionswechsel erst in %d s wieder möglich." % int(ceil(wait / 1000.0)), "warn")
		return
	if f >= 0:
		var limit: int = _faction_limit()
		var have: int = _faction_member_count(f)
		if have >= limit:
			_notify(p, "%s ist voll (%d/%d Plätze belegt). Weiche auf eine andere Fraktion aus." % [Cfg.FACTIONS[f]["name"], have, limit], "warn")
			return
	p.faction = f
	p.last_faction_ms = now
	var fname := "keiner Fraktion"
	if f >= 0:
		fname = str(Cfg.FACTIONS[f]["name"])
	_notify(p, "Du gehörst jetzt zu: %s" % fname, "info")
	net.send_all("rpc_player_faction", [id, f])
	net.send_all("rpc_faction_state", [faction_state()])
	_send_profile(p)
	log_line.emit("%s -> Fraktion %s" % [p.pname, fname])


# --------------------------------------------------------------- Lackierung
func handle_buy_paint(id: int, idx: int) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or idx < 0 or idx >= Parts.PAINTS.size():
		return
	if not _can_shop(p):
		_notify(p, "Lackierungen gibt es an der Station oder deinem Außenposten.", "warn")
		return
	if (p.owned_paints as Array).has(idx):
		return
	var price: int = Parts.price_for(int(Parts.PAINTS[idx]["price"]), p.faction)
	if p.coins < price:
		_notify(p, "Nicht genug Coins.", "warn")
		return
	p.coins -= price
	p.owned_paints.append(idx)
	_equip_paint(p, idx)
	_notify(p, "%s gekauft und angelegt." % Parts.PAINTS[idx]["name"], "info")


func handle_equip_paint(id: int, idx: int) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or idx < 0 or idx >= Parts.PAINTS.size():
		return
	if not (p.owned_paints as Array).has(idx):
		return
	_equip_paint(p, idx)


func _equip_paint(p: PD, idx: int) -> void:
	p.paint = idx
	_send_profile(p)
	net.send_all("rpc_player_paint", [p.id, idx])


# Reset: Rakete zurück zur Station (falls man festhängt oder sich verirrt hat)
func handle_reset(id: int) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0:
		return
	if p.s.landed == 0 and Sim.at_station(p.s):
		_notify(p, "Du stehst bereits an der Station.", "info")
		return
	var wait_ms: int = int(Cfg.RESET_COOLDOWN * 1000.0) - (Time.get_ticks_msec() - p.last_reset_ms)
	if wait_ms > 0:
		_notify(p, "Reset erst in %d s wieder möglich." % int(ceil(wait_ms / 1000.0)), "warn")
		return
	p.last_reset_ms = Time.get_ticks_msec()
	_respawn(p)
	_notify(p, "Rakete zurückgesetzt - du stehst wieder an der Station.", "info")
	log_line.emit("%s hat die Rakete zurückgesetzt." % p.pname)


func handle_use_item(id: int, item: String) -> void:
	var p: PD = players.get(id)
	if p == null or p.dead_t > 0.0 or not Parts.ITEMS.has(item):
		return
	if int(p.items.get(item, 0)) <= 0:
		_notify(p, "%s: keiner mehr im Inventar." % Parts.ITEMS[item]["name"], "warn")
		return
	var s = p.s
	var max_hp: float = float(p.stats["max_hp"])
	var max_fuel: float = float(p.stats["max_fuel"])
	match item:
		"boost":
			if s.boost_t > 0.0:
				return
			s.boost_t = Cfg.BOOST_TIME
		"chute":
			if s.landed >= 0:
				_notify(p, "Der Fallschirm funktioniert nur im Flug.", "warn")
				return
			if s.chute:
				return
			if Sim.atmosphere_planet(s.pos) < 0:
				_notify(p, "Hier gibt es keine Atmosphäre - der Fallschirm bleibt im Rucksack.", "warn")
				return
			s.chute = true
			s.chute_t = 0.0
		"repair":
			if s.hp >= max_hp - 0.5:
				_notify(p, "Der Rumpf ist unbeschädigt.", "info")
				return
			s.hp = minf(max_hp, s.hp + max_hp * 0.5)
		"fuel":
			if s.fuel >= max_fuel - 0.5:
				_notify(p, "Der Tank ist bereits voll.", "info")
				return
			s.fuel = minf(max_fuel, s.fuel + max_fuel * 0.5)
		"shield":
			if s.shield_t > 0.0:
				return
			s.shield_t = Cfg.SHIELD_TIME
		"torpedo":
			if s.landed >= 0:
				_notify(p, "Torpedos gibt es nur im Flug.", "warn")
				return
			var up := Vector2.UP.rotated(s.rot)
			projectiles.append({"pos": s.pos + up * 50.0, "vel": s.vel + up * Cfg.TORPEDO_SPEED, "owner": id,
				"fac": p.faction, "dmg": Cfg.TORPEDO_DMG, "life": Cfg.TORPEDO_LIFE, "kind": 3})
		"emp":
			if s.landed >= 0:
				_notify(p, "EMP nur im Flug.", "warn")
				return
			var n := 0
			for qid in players:
				var q: PD = players[qid]
				if q != p and q.dead_t <= 0.0 and q.s.landed < 0 and _can_hurt(p.faction, id, q) \
						and q.s.pos.distance_to(s.pos) < Cfg.EMP_RADIUS:
					q.s.emp_t = Cfg.EMP_TIME
					q.last_hit_by = id
					q.last_hit_ms = Time.get_ticks_msec()
					_notify(q, "EMP-Puls! Antrieb fällt aus.", "warn")
					n += 1
			net.send_all("rpc_fx", ["emp", id, s.pos, Cfg.EMP_RADIUS])
			_notify(p, "EMP ausgelöst: %d Ziel(e) getroffen." % n, "info")
		"mine":
			if s.landed >= 0:
				_notify(p, "Minen legst du im Flug.", "warn")
				return
			var mine_count := 0
			for m in mines:
				if int(m["owner"]) == id:
					mine_count += 1
			if mine_count >= 5:
				_notify(p, "Du hast schon 5 Minen ausgelegt.", "warn")
				return
			mines.append({"pos": s.pos, "owner": id, "fac": p.faction, "life": Cfg.MINE_LIFE, "arm": Cfg.MINE_ARM})
		_:
			return
	p.items[item] = int(p.items[item]) - 1
	_send_profile(p)


# ============================================================== Spielregeln
# Steht die Rakete auf einem Planeten, den die eigene Fraktion erobert hat (Außenposten)?
func _at_own_outpost(p: PD) -> bool:
	if p.faction < 0 or p.s.landed <= 0:
		return false
	return planet_owner[p.s.landed] == p.faction


func _can_shop(p: PD) -> bool:
	if Sim.at_station(p.s):
		return true
	if _at_own_outpost(p):
		return true
	return (not Cfg.SHOP_ONLY_AT_STATION) and p.s.landed >= 0


func _bonus_level(f: int) -> int:
	if f < 0:
		return 0
	return mini(Cfg.FACTION_MAX_LEVEL, floori(float(fac_kills[f]) / float(Cfg.FACTION_KILLS_PER_LEVEL)))


# Kapazität pro Fraktion, abhängig von der aktuellen Spielerzahl - so kann nicht jeder
# in dieselbe Fraktion gehen, egal wie viele Spieler online sind.
func _faction_limit() -> int:
	var total: int = maxi(1, players.size())
	return maxi(Cfg.FACTION_MIN_CAPACITY, int(ceil(float(total) * Cfg.FACTION_MAX_SHARE)))


func _faction_member_count(f: int) -> int:
	var n := 0
	for pid in players:
		if (players[pid] as PD).faction == f:
			n += 1
	return n


func _perk(p: PD, kind: String) -> float:
	if p.faction >= 0 and Cfg.FACTIONS[p.faction]["perk"] == kind:
		return 0.15 if kind == "kill" else 0.10
	return 0.0


# Darf ein Angreifer (Fraktion fac, ID owner) diesen Spieler verletzen? Gleiche Fraktion: nie.
func _can_hurt(fac: int, owner_id: int, q: PD) -> bool:
	if q.id == owner_id or q.s.landed >= 0:
		return false
	return not (fac >= 0 and q.faction == fac)


func _damage(q: PD, dmg: float, attacker: int) -> void:
	if q.s.shield_t > 0.0 or q.s.landed >= 0:
		return
	q.s.hp -= dmg * (1.0 - float(q.stats["armor"]))
	if attacker != 0:
		q.last_hit_by = attacker
		q.last_hit_ms = Time.get_ticks_msec()


func _passive(p: PD) -> void:
	var s = p.s
	var max_fuel: float = float(p.stats["max_fuel"])
	var max_hp: float = float(p.stats["max_hp"])
	if s.landed >= 0:
		if Sim.at_station(s) or _at_own_outpost(p):
			s.fuel = minf(max_fuel, s.fuel + Cfg.STATION_REFUEL * Cfg.DT)
			s.hp = minf(max_hp, s.hp + Cfg.STATION_REPAIR * Cfg.DT)
		else:
			s.fuel = minf(max_fuel, s.fuel + Cfg.LANDED_REFUEL * Cfg.DT)
	else:
		p.flight_time += Cfg.DT
		if p.flight_time >= Cfg.FLIGHT_COIN_INTERVAL:
			p.flight_time -= Cfg.FLIGHT_COIN_INTERVAL
			var mult: float = 1.0 + Cfg.FACTION_FLIGHT_BONUS * _bonus_level(p.faction) + _perk(p, "flight")
			var amount: int = int(round(Cfg.FLIGHT_COIN_AMOUNT * mult))
			p.coins += amount
			_send_profile(p)
			_notify(p, "Flugbonus: +%d Coins" % amount, "coin")
	for k in p.landing_cd.keys():
		p.landing_cd[k] = maxf(0.0, float(p.landing_cd[k]) - Cfg.DT)


func _handle_events(p: PD, ev: Dictionary) -> void:
	if ev.has("landed"):
		var idx: int = ev["landed"]
		var pl: Dictionary = Cfg.PLANETS[idx]
		var reward: int = pl["reward"]
		if reward > 0:
			var cd: float = float(p.landing_cd.get(idx, 0.0))
			if cd <= 0.0:
				p.landing_cd[idx] = Cfg.LANDING_COOLDOWN
				var mult: float = 1.0 + Cfg.FACTION_LANDING_BONUS * _bonus_level(p.faction) + _perk(p, "landing")
				var amount: int = int(round(reward * mult))
				p.coins += amount
				_send_profile(p)
				_notify(p, "Gelandet auf %s! +%d Coins" % [pl["name"], amount], "coin")
				log_line.emit("%s landet auf %s (+%d Coins)" % [p.pname, pl["name"], amount])
			else:
				_notify(p, "Gelandet auf %s (Landeprämie wieder in %d s)" % [pl["name"], int(ceil(cd))], "info")
	if ev.has("crash"):
		var dmg: float = float(ev.get("dmg", 0.0))
		net.send_all("rpc_fx", ["crash", p.id, p.s.pos, dmg])
		if dmg >= 1.0:
			_notify(p, "Aufprall! -%d Rumpf" % int(round(dmg)), "warn")


# ------------------------------------------------------------ Erforschung
func _explore(p: PD) -> void:
	var pos: Vector2 = p.s.pos
	var radar: float = float(p.stats.get("disc_range_mult", 1.0))
	for i in Cfg.PLANETS.size():
		if p.disc_planets.has(i):
			continue
		var pl: Dictionary = Cfg.PLANETS[i]
		var ppos: Vector2 = pl["pos"]
		if pos.distance_to(ppos) < float(pl["range"]) * radar:
			p.disc_planets.append(i)
			var c: int = int(float(pl["reward"]) * Cfg.DISCOVER_FACTOR) + 100
			p.coins += c
			_send_profile(p)
			_notify(p, "Neuer Himmelskörper entdeckt: %s! +%d Coins" % [pl["name"], c], "coin")
			log_line.emit("%s entdeckt %s" % [p.pname, pl["name"]])
	for i in Cfg.POIS.size():
		if p.disc_pois.has(i):
			continue
		var poi: Dictionary = Cfg.POIS[i]
		var qpos: Vector2 = poi["pos"]
		if pos.distance_to(qpos) >= Cfg.POI_RADIUS * radar:
			continue
		p.disc_pois.append(i)
		var text := "%s gefunden!" % poi["name"]
		var coins: int = int(poi["coins"])
		if poi["kind"] == "crystal":
			p.s.fuel = minf(float(p.stats["max_fuel"]), p.s.fuel + float(p.stats["max_fuel"]) * 0.3)
			text += " Tank +30 %"
		elif poi["kind"] == "cache":
			var got: PackedStringArray = PackedStringArray()
			for k in 2:
				var key: String = Parts.ITEM_ORDER[randi() % Parts.ITEM_ORDER.size()]
				p.items[key] = mini(Cfg.MAX_ITEM_STACK, int(p.items.get(key, 0)) + 1)
				got.append(str(Parts.ITEMS[key]["name"]))
			text += " Inhalt: %s" % ", ".join(got)
		if coins > 0:
			p.coins += coins
			text += " +%d Coins" % coins
		_send_profile(p)
		_notify(p, text, "coin")
		log_line.emit("%s findet %s" % [p.pname, poi["name"]])


# ------------------------------------------------------------------ Kampf
func _combat(p: PD) -> void:
	p.fire_cd = maxf(0.0, p.fire_cd - Cfg.DT)
	if (p.input & 16) == 0 or p.fire_cd > 0.0 or p.s.landed >= 0:
		return
	var dmg: float = p.stats["w_dmg"]
	if dmg <= 0.0:
		return
	p.fire_cd = p.stats["w_cd"]
	var up := Vector2.UP.rotated(p.s.rot)
	var side := up.orthogonal()
	var shots: int = p.stats["w_shots"]
	for i in shots:
		var off := 0.0
		if shots == 2:
			off = -12.0 if i == 0 else 12.0
		projectiles.append({"pos": p.s.pos + up * 46.0 + side * off, "vel": p.s.vel * 0.5 + up * float(p.stats["w_speed"]),
			"owner": p.id, "fac": p.faction, "dmg": dmg, "life": 1.6, "kind": p.stats["w_kind"]})


func _nearest_enemy(pos: Vector2, owner_id: int, fac: int, rng: float):
	var best = null
	var best_d := rng
	for qid in players:
		var q: PD = players[qid]
		if q.dead_t > 0.0 or not _can_hurt(fac, owner_id, q):
			continue
		var d: float = pos.distance_to(q.s.pos)
		if d < best_d:
			best_d = d
			best = q
	return best


func _update_projectiles() -> void:
	var keep: Array = []
	for pr in projectiles:
		pr["life"] = float(pr["life"]) - Cfg.DT
		if float(pr["life"]) <= 0.0:
			continue
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		var fac: int = pr["fac"]
		var owner_id: int = pr["owner"]
		if int(pr["kind"]) == 3:
			var tgt = _nearest_enemy(pos, owner_id, fac, Cfg.TORPEDO_RANGE)
			if tgt != null:
				var cur: Vector2 = vel.normalized()
				var want: Vector2 = (tgt.s.pos - pos).normalized()
				var ang: float = clampf(cur.angle_to(want), -Cfg.TORPEDO_TURN * Cfg.DT, Cfg.TORPEDO_TURN * Cfg.DT)
				vel = cur.rotated(ang) * maxf(vel.length(), Cfg.TORPEDO_SPEED)
		pos += vel * Cfg.DT
		pr["pos"] = pos
		pr["vel"] = vel
		var blocked := false
		for pl in Cfg.PLANETS:
			var cpos: Vector2 = pl["pos"]
			if pos.distance_to(cpos) < float(pl["radius"]):
				blocked = true
				break
		if blocked:
			continue
		var hit := false
		for qid in players:
			var q: PD = players[qid]
			if q.dead_t > 0.0 or not _can_hurt(fac, owner_id, q):
				continue
			if pos.distance_to(q.s.pos) < Cfg.ROCKET_RADIUS + 8.0:
				_damage(q, float(pr["dmg"]), owner_id)
				net.send_all("rpc_fx", ["hit", q.id, pos, float(pr["dmg"])])
				hit = true
				break
		if not hit:
			keep.append(pr)
	projectiles = keep


func _update_mines() -> void:
	var keep: Array = []
	for m in mines:
		m["life"] = float(m["life"]) - Cfg.DT
		m["arm"] = float(m["arm"]) - Cfg.DT
		if float(m["life"]) <= 0.0:
			continue
		var exploded := false
		if float(m["arm"]) <= 0.0:
			var mpos: Vector2 = m["pos"]
			for qid in players:
				var q: PD = players[qid]
				if q.dead_t > 0.0 or not _can_hurt(int(m["fac"]), int(m["owner"]), q):
					continue
				if mpos.distance_to(q.s.pos) < Cfg.MINE_RADIUS:
					_damage(q, Cfg.MINE_DMG, int(m["owner"]))
					net.send_all("rpc_fx", ["crash", q.id, mpos, Cfg.MINE_DMG])
					_notify(q, "Mine! -%d Rumpf" % int(Cfg.MINE_DMG), "warn")
					exploded = true
					break
		if not exploded:
			keep.append(m)
	mines = keep


# Rakete gegen Rakete (gleiche Fraktion: Abprall, aber kein Schaden)
func _player_collisions() -> void:
	var ids: Array = players.keys()
	for i in ids.size():
		var a: PD = players[ids[i]]
		if a.dead_t > 0.0:
			continue
		for j in range(i + 1, ids.size()):
			var b: PD = players[ids[j]]
			if b.dead_t > 0.0:
				continue
			var d: Vector2 = b.s.pos - a.s.pos
			var dist: float = d.length()
			var min_d: float = Cfg.ROCKET_RADIUS * 2.0
			if dist >= min_d:
				continue
			var a_fixed: bool = a.s.landed >= 0
			var b_fixed: bool = b.s.landed >= 0
			if a_fixed and b_fixed:
				continue
			var n: Vector2 = Vector2.RIGHT
			if dist > 0.001:
				n = d / dist
			var inv_a: float = 0.0 if a_fixed else 1.0
			var inv_b: float = 0.0 if b_fixed else 1.0
			var inv_sum: float = inv_a + inv_b
			var overlap: float = min_d - dist
			a.s.pos -= n * overlap * (inv_a / inv_sum)
			b.s.pos += n * overlap * (inv_b / inv_sum)
			var rel: float = (b.s.vel - a.s.vel).dot(n)
			if rel < 0.0:
				var jimp: float = -(1.0 + Cfg.PLAYER_RESTITUTION) * rel / inv_sum
				a.s.vel -= n * jimp * inv_a
				b.s.vel += n * jimp * inv_b
				var dmg: float = maxf(0.0, -rel - Cfg.PLAYER_CRASH_SPEED) * Cfg.PLAYER_CRASH_DMG
				var friendly: bool = a.faction >= 0 and a.faction == b.faction
				if dmg > 0.0 and not friendly:
					_damage(a, dmg, b.id)
					_damage(b, dmg, a.id)
					net.send_all("rpc_fx", ["crash", a.id, (a.s.pos + b.s.pos) * 0.5, dmg])


# ------------------------------------------------------------- Tod / Kopfgeld
func _kill(p: PD) -> void:
	p.dead_t = Cfg.RESPAWN_TIME
	p.s.hp = 0.0
	p.s.vel = Vector2.ZERO
	p.s.thrusting = 0.0
	p.s.chute = false
	p.input = 0
	p.deaths += 1
	net.send_all("rpc_fx", ["explode", p.id, p.s.pos, 0.0])
	_notify(p, "Deine Rakete wurde zerstört! Neustart an der Station ...", "warn")
	var killer: PD = null
	if p.last_hit_by != 0 and Time.get_ticks_msec() - p.last_hit_ms <= int(Cfg.COMBAT_TAG_TIME * 1000.0):
		killer = players.get(p.last_hit_by)
	p.last_hit_by = 0
	if killer != null and killer != p:
		_award_kill(killer, p)
	else:
		log_line.emit("%s wurde zerstört." % p.pname)


func _award_kill(k: PD, v: PD) -> void:
	var reward: float = Cfg.KILL_REWARD * (1.0 + _perk(k, "kill"))
	var enemy_faction: bool = k.faction >= 0 and v.faction >= 0 and k.faction != v.faction
	if enemy_faction:
		reward += Cfg.KILL_ENEMY_FACTION_BONUS
	var amount: int = int(round(reward))
	k.coins += amount
	k.kills += 1
	_send_profile(k)
	_notify(k, "Abschuss: %s  +%d Coins" % [v.pname, amount], "coin")
	_notify(v, "Abgeschossen von %s." % k.pname, "warn")
	net.send_all("rpc_fx", ["kill", k.id, v.s.pos, float(amount)])
	log_line.emit("%s schießt %s ab (+%d Coins)" % [k.pname, v.pname, amount])
	if enemy_faction:
		var before: int = _bonus_level(k.faction)
		fac_kills[k.faction] += 1
		var after: int = _bonus_level(k.faction)
		if after > before:
			var fname: String = Cfg.FACTIONS[k.faction]["name"]
			for pid in players:
				var m: PD = players[pid]
				if m.faction == k.faction:
					_notify(m, "%s: Bonusstufe %d erreicht (mehr Flug-Coins und Landeprämien)!" % [fname, after], "coin")
		net.send_all("rpc_faction_state", [faction_state()])


# -------------------------------------------------------- Planeten-Eroberung
# Eine Fraktion erobert einen Planeten, wenn NUR ihre Mitglieder dort gelandet sind
# und das exklusiv Cfg.CAPTURE_TIME Sekunden lang anhält. Ist mehr als eine Fraktion
# vor Ort (umkämpft) oder niemand, verfällt der Fortschritt langsam wieder.
func _update_planets_control(dt: float) -> void:
	for i in range(1, Cfg.PLANETS.size()):
		var present: Dictionary = {}
		for id in players:
			var pl: PD = players[id]
			if pl.dead_t > 0.0 or pl.faction < 0 or pl.s.landed != i:
				continue
			present[pl.faction] = int(present.get(pl.faction, 0)) + 1
		if present.size() == 1:
			var f: int = present.keys()[0]
			if planet_owner[i] == f:
				planet_progress[i] = 0.0
				planet_progress_faction[i] = -1
				continue
			if planet_progress_faction[i] != f:
				planet_progress_faction[i] = f
				planet_progress[i] = 0.0
			planet_progress[i] = minf(1.0, float(planet_progress[i]) + dt / Cfg.CAPTURE_TIME)
			if planet_progress[i] >= 1.0:
				_capture_planet(i, f)
		else:
			planet_progress[i] = maxf(0.0, float(planet_progress[i]) - dt * Cfg.CAPTURE_DECAY)
			if planet_progress[i] <= 0.0:
				planet_progress_faction[i] = -1


func _capture_planet(i: int, f: int) -> void:
	planet_owner[i] = f
	planet_progress[i] = 0.0
	planet_progress_faction[i] = -1
	var pname: String = str(Cfg.PLANETS[i]["name"])
	var fname: String = str(Cfg.FACTIONS[f]["name"])
	net.send_all("rpc_notice", ["%s wurde von %s erobert und dient nun als Außenposten (Tanken/Reparatur/Shop)!" % [pname, fname], "coin"])
	net.send_all("rpc_faction_state", [faction_state()])
	log_line.emit("Planet %s erobert von %s" % [pname, fname])


func faction_state() -> Dictionary:
	var members: Array = []
	for i in Cfg.FACTIONS.size():
		members.append(0)
	for pid in players:
		var m: PD = players[pid]
		if m.faction >= 0:
			members[m.faction] += 1
	var levels: Array = []
	for i in Cfg.FACTIONS.size():
		levels.append(_bonus_level(i))
	return {"kills": fac_kills.duplicate(), "members": members, "levels": levels, "limit": _faction_limit(),
		"planet_owner": planet_owner.duplicate(), "planet_progress": planet_progress.duplicate(),
		"planet_progress_faction": planet_progress_faction.duplicate()}


func _respawn(p: PD) -> void:
	p.s = _spawn_state(p)
	p.s.fuel = float(p.stats["max_fuel"])
	p.s.hp = float(p.stats["max_hp"])
	p.flight_time = 0.0
	p.input = 0


# Fraktionslos oder ohne eigenes Gebiet: Erd-Station. Sonst der eigene Außenposten,
# der der aktuellen Position am nächsten liegt (so respawnt man in der Nähe des Geschehens).
func _best_spawn_planet(p: PD) -> int:
	if p.faction < 0:
		return 0
	var owned: Array = []
	for i in range(1, Cfg.PLANETS.size()):
		if planet_owner[i] == p.faction:
			owned.append(i)
	if owned.is_empty() or p.s == null:
		return 0 if owned.is_empty() else owned[0]
	var best: int = owned[0]
	var best_d: float = INF
	for i in owned:
		var d: float = p.s.pos.distance_to(Cfg.PLANETS[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func _spawn_state(p: PD):
	var planet_idx: int = _best_spawn_planet(p)
	for slot in range(0, Cfg.MAX_PLAYERS + 4):
		var s = Sim.make_spawn_at(planet_idx, slot)
		var free := true
		for oid in players:
			var o: PD = players[oid]
			if o == p or o.dead_t > 0.0 or o.s == null:
				continue
			if o.s.pos.distance_to(s.pos) < Cfg.ROCKET_RADIUS * 2.2:
				free = false
				break
		if free:
			return s
	return Sim.make_spawn_at(planet_idx, 0)


# =================================================================== Senden
func _send_snapshot() -> void:
	var ids := PackedInt32Array()
	var data := PackedFloat32Array()
	for id in players:
		var p: PD = players[id]
		var s = p.s
		var flags := 0
		if s.thrusting > 0.0:
			flags |= 1
		elif s.thrusting < 0.0:
			flags |= 2
		if s.chute:
			flags |= 4
		if s.shield_t > 0.0:
			flags |= 8
		if s.boost_t > 0.0:
			flags |= 16
		if p.dead_t > 0.0:
			flags |= 32
		if s.landed >= 0:
			flags |= 64
		if s.emp_t > 0.0:
			flags |= 128
		ids.append(int(id))
		for v in [s.pos.x, s.pos.y, s.rot, s.vel.x, s.vel.y, s.angvel, float(flags), s.hp, s.fuel,
				float(p.last_seq), s.boost_t, s.shield_t, float(s.landed), s.chute_t, s.emp_t]:
			data.append(v)
	net.send_all("rpc_snapshot", [tick, ids, data])


# Geschosse und Minen (Stride 5: x, y, Winkel, Art, Extra)
func _send_projectiles() -> void:
	var n: int = projectiles.size() + mines.size()
	if n == 0 and _last_proj_count == 0:
		return
	_last_proj_count = n
	var data := PackedFloat32Array()
	for pr in projectiles:
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		for v in [pos.x, pos.y, vel.angle(), float(pr["kind"]), 0.0]:
			data.append(v)
	for m in mines:
		var mpos: Vector2 = m["pos"]
		for v in [mpos.x, mpos.y, 0.0, 10.0, 1.0 if float(m["arm"]) <= 0.0 else 0.0]:
			data.append(v)
	net.send_all("rpc_projectiles", [data])


func _public_info(p: PD) -> Dictionary:
	return {"id": p.id, "name": p.pname, "levels": p.levels, "faction": p.faction, "paint": p.paint}


func _profile(p: PD) -> Dictionary:
	return {"name": p.pname, "coins": p.coins, "levels": p.levels, "owned": p.owned, "items": p.items,
		"faction": p.faction, "kills": p.kills, "deaths": p.deaths, "paint": p.paint, "owned_paints": p.owned_paints,
		"disc_planets": p.disc_planets, "disc_pois": p.disc_pois}


func _send_profile(p: PD) -> void:
	net.send_to(p.id, "rpc_profile", [_profile(p)])


func _notify(p: PD, text: String, kind: String) -> void:
	net.send_to(p.id, "rpc_notice", [text, kind])


# ==================================================================== Helfer
func _clean_name(raw: String, id: int) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if out.length() >= Cfg.MAX_NAME_LEN:
			break
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges()
	if out == "":
		out = "Pilot%d" % (id % 1000)
	return out


func _unique_name(base: String) -> String:
	var taken := {}
	for oid in players:
		var o: PD = players[oid]
		taken[o.pname.to_lower()] = true
	var candidate := base
	var n := 2
	while taken.has(candidate.to_lower()):
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate



# Für die Server-Ansicht
func get_player_rows() -> Array:
	var rows: Array = []
	for id in players:
		var p: PD = players[id]
		var where := "im Flug"
		if p.dead_t > 0.0:
			where = "zerstört"
		elif p.s.landed >= 0:
			var pl: Dictionary = Cfg.PLANETS[p.s.landed]
			where = "gelandet: %s" % pl["name"]
		var fac := "-"
		if p.faction >= 0:
			fac = str(Cfg.FACTIONS[p.faction]["short"])
		rows.append({"id": id, "name": p.pname, "coins": p.coins, "where": where, "faction": fac,
			"kills": p.kills, "speed": int(p.s.vel.length()), "hp": int(round(p.s.hp))})
	return rows


# Liste "Planet: Fraktion" aller eroberten Himmelskörper (für die Server-Ansicht)
func get_territory_rows() -> Array:
	var rows: Array = []
	for i in range(1, Cfg.PLANETS.size()):
		if planet_owner[i] >= 0:
			rows.append("%s: %s" % [Cfg.PLANETS[i]["name"], Cfg.FACTIONS[planet_owner[i]]["short"]])
	return rows
