extends RefCounted
# Gemeinsame Raketen-Physik. Wird vom SERVER (autoritativ) und vom CLIENT
# (Vorhersage, damit sich die Steuerung sofort anfühlt) mit exakt derselben Funktion
# und derselben festen Schrittweite (Cfg.DT) ausgeführt.
#
# Eingabe-Bits (inp):  1 = Schub (Leertaste / ui_up)   2 = Bremsschub (ui_down)
#                      4 = links drehen (ui_left)      8 = rechts drehen (ui_right)

const Cfg = preload("res://scripts/config.gd")


class State:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var rot: float = 0.0          # 0 = Nase zeigt nach oben
	var angvel: float = 0.0
	var fuel: float = 60.0
	var hp: float = 100.0
	var landed: int = -1          # -1 = fliegt, sonst Index des Planeten
	var boost_t: float = 0.0
	var shield_t: float = 0.0
	var chute: bool = false
	var chute_t: float = 0.0
	var emp_t: float = 0.0        # >0 = Antrieb durch EMP ausgefallen
	var thrusting: float = 0.0    # nur für Grafik: 1 = Hauptschub, -1 = Bremsschub


# Ein Physik-Schritt. Gibt Ereignisse zurück (Landung, Absturz ...).
static func step(s: State, inp: int, st: Dictionary, dt: float) -> Dictionary:
	var ev := {}

	if s.boost_t > 0.0:
		s.boost_t = maxf(0.0, s.boost_t - dt)
	if s.shield_t > 0.0:
		s.shield_t = maxf(0.0, s.shield_t - dt)
	if s.emp_t > 0.0:
		s.emp_t = maxf(0.0, s.emp_t - dt)

	var want_thrust: bool = (inp & 1) != 0
	var want_retro: bool = (inp & 2) != 0
	var turn_left: bool = (inp & 4) != 0
	var turn_right: bool = (inp & 8) != 0

	# ------------------------------------------------------ gelandet: Start?
	if s.landed >= 0:
		var lpl: Dictionary = Cfg.PLANETS[s.landed]
		var lpos: Vector2 = lpl["pos"]
		var ln: Vector2 = (s.pos - lpos).normalized()
		if want_thrust and s.fuel > 0.0 and s.emp_t <= 0.0:
			s.landed = -1
			ev["takeoff"] = true
		else:
			s.pos = lpos + ln * (float(lpl["radius"]) + Cfg.LAND_RADIUS)
			s.vel = Vector2.ZERO
			s.angvel = 0.0
			s.rot = ln.angle() + PI / 2.0
			s.thrusting = 0.0
			s.chute = false
			return ev

	# ------------------------------------------------------------- Drehen
	var turn_target := 0.0
	if turn_left:
		turn_target -= 1.0
	if turn_right:
		turn_target += 1.0
	s.angvel = move_toward(s.angvel, turn_target * float(st["turn_rate"]), float(st["turn_accel"]) * dt)
	s.rot = wrapf(s.rot + s.angvel * dt, -PI, PI)
	var up := Vector2.UP.rotated(s.rot)

	# --------------------------------------------------------------- Schub
	var thr := 0.0
	if s.fuel > 0.0 and s.emp_t <= 0.0:
		if want_thrust:
			thr = 1.0
		elif want_retro:
			thr = -0.5
	s.thrusting = thr
	var boosted: bool = s.boost_t > 0.0
	var accel := Vector2.ZERO
	if thr != 0.0:
		var power: float = float(st["thrust"])
		if boosted:
			power *= Cfg.BOOST_THRUST
		accel += up * power * thr
		s.fuel = maxf(0.0, s.fuel - absf(thr) * float(st["burn"]) * dt)

	# ------------------------------------------------- Schwerkraft/Atmosphäre
	var atmo_idx := -1
	for i in Cfg.PLANETS.size():
		var pl: Dictionary = Cfg.PLANETS[i]
		var ppos: Vector2 = pl["pos"]
		var d: Vector2 = s.pos - ppos
		var dist: float = d.length()
		var rng: float = pl["range"]
		var r: float = pl["radius"]
		if dist < rng and dist > 0.001:
			var g: float = float(pl["g"]) * pow(r / maxf(dist, r), 2.0)
			var fade: float = clampf((rng - dist) / (rng * 0.35), 0.0, 1.0)
			accel -= d / dist * g * fade
		if float(pl["atmo"]) > 0.0 and dist - r < float(pl["atmo"]):
			atmo_idx = i

	# ------------------------------------------------------------ Fallschirm
	if s.chute:
		s.chute_t += dt
		if atmo_idx >= 0:
			var apl: Dictionary = Cfg.PLANETS[atmo_idx]
			var apos: Vector2 = apl["pos"]
			var anrm: Vector2 = (s.pos - apos).normalized()
			s.vel -= s.vel * minf(1.0, Cfg.CHUTE_DRAG * dt)
			s.rot = lerp_angle(s.rot, anrm.angle() + PI / 2.0, minf(1.0, 3.0 * dt))
			s.angvel = 0.0
		if s.chute_t > Cfg.CHUTE_MAX_TIME:
			s.chute = false

	# ------------------------------------------------------------ Integrieren
	s.vel += accel * dt
	var max_speed: float = float(st["max_speed"])
	if boosted:
		max_speed *= Cfg.BOOST_SPEED
	var sp: float = s.vel.length()
	if sp > max_speed:
		s.vel = s.vel.move_toward(s.vel / sp * max_speed, Cfg.OVERSPEED_DECEL * dt)
	s.pos += s.vel * dt

	# Rand der Welt
	var from_origin: float = s.pos.length()
	if from_origin > Cfg.WORLD_RADIUS:
		var wn: Vector2 = s.pos / from_origin
		s.pos = wn * Cfg.WORLD_RADIUS
		var vo: float = s.vel.dot(wn)
		if vo > 0.0:
			s.vel -= wn * vo

	# ------------------------------------------------------ Planeten-Kollision
	for i in Cfg.PLANETS.size():
		var cpl: Dictionary = Cfg.PLANETS[i]
		var cpos: Vector2 = cpl["pos"]
		var cd: Vector2 = s.pos - cpos
		var min_d: float = float(cpl["radius"]) + Cfg.LAND_RADIUS
		if cd.length_squared() >= min_d * min_d:
			continue
		var cdist: float = cd.length()
		var nn: Vector2 = Vector2.UP
		if cdist > 0.001:
			nn = cd / cdist
		var vn: float = s.vel.dot(nn)
		var approach: float = maxf(0.0, -vn)
		var vt: Vector2 = s.vel - nn * vn
		var tang: float = vt.length()
		var up_now := Vector2.UP.rotated(s.rot)
		var aligned: bool = up_now.dot(nn) >= Cfg.LAND_ALIGN
		var safe_v: float = float(st["safe_v"])
		var armor: float = float(st["armor"])
		s.pos = cpos + nn * min_d

		if approach <= safe_v and tang <= safe_v * 1.5 and aligned:
			# --- sichere Landung
			s.landed = i
			s.vel = Vector2.ZERO
			s.angvel = 0.0
			s.chute = false
			s.thrusting = 0.0
			s.rot = nn.angle() + PI / 2.0
			ev["landed"] = i
			ev["impact"] = approach
			break
		elif approach <= safe_v:
			# --- sanftes Aufsetzen / Schrammen: kein Aufprallschaden, aber Reibung
			s.vel = vt * maxf(0.0, 1.0 - 6.0 * dt)
			if tang > safe_v * 2.0 and s.shield_t <= 0.0:
				var scrape: float = (tang - safe_v * 2.0) * 0.15 * dt * (1.0 - armor)
				s.hp -= scrape
				ev["dmg"] = float(ev.get("dmg", 0.0)) + scrape
			ev["scrape"] = true
		else:
			# --- Absturz
			var dmg: float = (approach - safe_v) * Cfg.CRASH_DMG_FACTOR
			if not aligned:
				dmg *= 1.4
			dmg *= (1.0 - armor)
			if s.shield_t > 0.0:
				dmg = 0.0
			s.hp -= dmg
			ev["crash"] = approach
			ev["impact"] = approach
			ev["dmg"] = float(ev.get("dmg", 0.0)) + dmg
			s.vel = vt * 0.7 + nn * approach * Cfg.BOUNCE
			s.angvel += 1.5 if s.angvel >= 0.0 else -1.5

	return ev


# Spawn-Platz auf einem beliebigen Himmelskörper (slot 0 = Mitte, 1 = rechts, 2 = links ...).
# Genutzt für die Erd-Station (idx 0) und für Fraktions-Außenposten auf eroberten Planeten.
static func make_spawn_at(planet_idx: int, slot: int) -> State:
	var s := State.new()
	var pl: Dictionary = Cfg.PLANETS[planet_idx]
	var pos: Vector2 = pl["pos"]
	var radius: float = pl["radius"]
	var k: int = int(ceil(float(slot) / 2.0))
	var sgn: float = 1.0 if slot % 2 == 1 else -1.0
	var ang: float = -PI / 2.0 + sgn * float(k) * (Cfg.SPAWN_SPACING / radius)
	var n := Vector2(cos(ang), sin(ang))
	s.pos = pos + n * (radius + Cfg.LAND_RADIUS)
	s.rot = ang + PI / 2.0
	s.landed = planet_idx
	return s


static func make_spawn(slot: int) -> State:
	return make_spawn_at(0, slot)


# Steht die Rakete gelandet an der Erd-Station (Shop + Reparatur)?
static func at_station(s: State) -> bool:
	if s.landed != 0:
		return false
	var pl: Dictionary = Cfg.PLANETS[0]
	var pos: Vector2 = pl["pos"]
	var n: Vector2 = (s.pos - pos).normalized()
	var ang: float = absf(angle_difference(n.angle(), -PI / 2.0))
	return ang * float(pl["radius"]) <= Cfg.STATION_RADIUS


# Index des Planeten, in dessen Atmosphäre man gerade ist (-1 = keiner)
static func atmosphere_planet(p: Vector2) -> int:
	for i in Cfg.PLANETS.size():
		var pl: Dictionary = Cfg.PLANETS[i]
		var ppos: Vector2 = pl["pos"]
		var atmo: float = pl["atmo"]
		if atmo > 0.0 and p.distance_to(ppos) - float(pl["radius"]) < atmo:
			return i
	return -1


# Nächster Planet (für die Anzeige): Index, Entfernung zur Oberfläche der Rakete, Normale
static func nearest_planet(p: Vector2) -> Dictionary:
	var best := -1
	var best_alt := INF
	var best_n := Vector2.UP
	for i in Cfg.PLANETS.size():
		var pl: Dictionary = Cfg.PLANETS[i]
		var ppos: Vector2 = pl["pos"]
		var d: Vector2 = p - ppos
		var alt: float = d.length() - float(pl["radius"]) - Cfg.LAND_RADIUS
		if alt < best_alt:
			best_alt = alt
			best = i
			best_n = d.normalized() if d.length() > 0.001 else Vector2.UP
	return {"idx": best, "alt": best_alt, "n": best_n}
