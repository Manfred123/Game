extends RefCounted
# Baukasten: Jede Kategorie hat 5 frei kombinierbare Varianten. Jede Variante hat eigene
# Stärken UND Schwächen (Masse!). Der Spieler kauft Teile einzeln und rüstet pro Kategorie
# eines aus. Sprites: res://assets/parts/<kategorie>_<variante>.png (160x240, gleiche Leinwand).
#
# Stat-Schlüssel (werden addiert): thrust, max_speed, burn (Verbrauch/s), fuel, hp, armor, turn,
# safe_v (sichere Landegeschwindigkeit), mass. Waffen: w_dmg, w_cd, w_speed, w_shots, w_kind.
# Zu viel Masse macht die Rakete träge (Schub und Drehrate sinken).

const Cfg = preload("res://scripts/config.gd")

const REF_MASS := 12.5

const DRAW_ORDER: Array = ["fins", "legs", "tank", "nozzle", "engine", "hull", "rcs", "nose", "radar", "weapon"]
const SHOP_ORDER: Array = ["engine", "nozzle", "tank", "rcs", "hull", "nose", "fins", "legs", "radar", "weapon"]

const ICON_REGION := {
	"hull": Rect2(44, 58, 72, 112), "nose": Rect2(44, 8, 72, 66), "tank": Rect2(24, 64, 112, 108),
	"engine": Rect2(40, 150, 80, 44), "nozzle": Rect2(40, 170, 80, 44), "fins": Rect2(14, 96, 132, 100),
	"legs": Rect2(24, 136, 112, 76), "weapon": Rect2(30, 6, 100, 90),
	"radar": Rect2(20, 20, 120, 70), "rcs": Rect2(10, 92, 140, 64),
}

const UPGRADES := {
	"engine": {"title": "Triebwerk", "desc": "Schub und Höchsttempo - starke Motoren sind schwer und durstig.", "tiers": [
		{"name": "Kolibri", "price": 0, "thrust": 300.0, "max_speed": 800.0, "burn": 0.0, "mass": 3.0},
		{"name": "Falke Turbo", "price": 350, "thrust": 420.0, "max_speed": 900.0, "burn": 1.5, "mass": 4.0},
		{"name": "Ionen-Driver", "price": 700, "thrust": 250.0, "max_speed": 1500.0, "burn": -1.0, "mass": 3.0},
		{"name": "Plasma-Triebwerk", "price": 2000, "thrust": 560.0, "max_speed": 1200.0, "burn": 2.5, "mass": 6.0},
		{"name": "Fusionsantrieb", "price": 4600, "thrust": 700.0, "max_speed": 1800.0, "burn": 1.0, "mass": 8.0},
		{"name": "Prototyp-Singularitätsantrieb", "price": 11000, "thrust": 900.0, "max_speed": 2200.0, "burn": 1.5, "mass": 11.0}]},
	"nozzle": {"title": "Düse", "desc": "Legt den Grundverbrauch fest und gibt etwas Zusatzschub.", "tiers": [
		{"name": "Standard-Düse", "price": 0, "burn": 6.0, "thrust": 0.0, "mass": 1.0},
		{"name": "Weitwinkel-Düse", "price": 300, "burn": 5.0, "thrust": 30.0, "mass": 1.5},
		{"name": "Bronze-Langdüse", "price": 800, "burn": 4.4, "thrust": 60.0, "mass": 2.5},
		{"name": "Aerospike", "price": 1900, "burn": 3.6, "thrust": 40.0, "mass": 2.0},
		{"name": "Plasma-Ringdüse", "price": 4200, "burn": 3.0, "thrust": 90.0, "mass": 3.5},
		{"name": "Singularitätsdüse", "price": 9500, "burn": 2.4, "thrust": 130.0, "mass": 5.0}]},
	"tank": {"title": "Tank", "desc": "Mehr Treibstoff = mehr Reichweite, aber mehr Masse.", "tiers": [
		{"name": "Mini-Tank", "price": 0, "fuel": 60.0, "mass": 2.0},
		{"name": "Doppelkanister", "price": 250, "fuel": 90.0, "mass": 3.0},
		{"name": "Weißer Großtank", "price": 700, "fuel": 140.0, "mass": 5.0},
		{"name": "Zellentank", "price": 1700, "fuel": 210.0, "mass": 7.0},
		{"name": "Energiezellen-Tank", "price": 4000, "fuel": 320.0, "mass": 10.0},
		{"name": "Antimaterie-Zelle", "price": 9000, "fuel": 480.0, "mass": 14.0}]},
	"hull": {"title": "Rumpf", "desc": "Rumpfpunkte - dicke Hüllen sind schwer.", "tiers": [
		{"name": "Aluminium-Rumpf", "price": 0, "hp": 100.0, "mass": 4.0},
		{"name": "Stahlrumpf", "price": 300, "hp": 170.0, "mass": 6.5},
		{"name": "Titanrumpf", "price": 850, "hp": 240.0, "mass": 6.0, "armor": 0.05},
		{"name": "Karbonrumpf", "price": 2000, "hp": 300.0, "mass": 5.0, "armor": 0.05},
		{"name": "Goldrumpf", "price": 4500, "hp": 520.0, "mass": 12.0, "armor": 0.1},
		{"name": "Adamant-Rumpf", "price": 10500, "hp": 780.0, "mass": 16.0, "armor": 0.15}]},
	"nose": {"title": "Nasenpanzerung", "desc": "Verringert allen Schaden (Kollision und Beschuss).", "tiers": [
		{"name": "Standard-Nase", "price": 0, "armor": 0.0, "mass": 0.5},
		{"name": "Stahlspitze", "price": 250, "armor": 0.10, "mass": 1.0},
		{"name": "Sensor-Spitze", "price": 700, "armor": 0.05, "mass": 0.5, "turn": 0.4},
		{"name": "Panzerkegel", "price": 1600, "armor": 0.30, "mass": 3.0},
		{"name": "Kristallschild", "price": 3800, "armor": 0.40, "mass": 4.0},
		{"name": "Void-Spitze", "price": 8500, "armor": 0.50, "mass": 5.0, "turn": 0.6}]},
	"fins": {"title": "Flügel / Flossen", "desc": "Drehrate und Wendigkeit.", "tiers": [
		{"name": "Kleine Flossen", "price": 0, "turn": 2.4, "mass": 1.0},
		{"name": "Große Flossen", "price": 200, "turn": 2.9, "mass": 1.5},
		{"name": "Delta-Flügel", "price": 550, "turn": 3.4, "mass": 2.0, "max_speed": 100.0},
		{"name": "Doppelflügel", "price": 1400, "turn": 4.0, "mass": 3.0},
		{"name": "Energieflügel", "price": 3200, "turn": 4.8, "mass": 2.5},
		{"name": "Quantenflügel", "price": 7500, "turn": 6.0, "mass": 3.2, "max_speed": 150.0}]},
	"legs": {"title": "Landebeine", "desc": "Höhere Aufprallgeschwindigkeit ist noch eine sichere Landung.", "tiers": [
		{"name": "Stützbeine", "price": 0, "safe_v": 90.0, "mass": 1.0},
		{"name": "Federbeine", "price": 300, "safe_v": 120.0, "mass": 1.5},
		{"name": "Hydraulikbeine", "price": 900, "safe_v": 150.0, "mass": 2.5},
		{"name": "Verstärkte Beine", "price": 2100, "safe_v": 190.0, "mass": 4.0},
		{"name": "Schwerlast-Beine", "price": 4800, "safe_v": 240.0, "mass": 6.0},
		{"name": "Gravitonstützen", "price": 9500, "safe_v": 320.0, "mass": 8.0}]},
	"radar": {"title": "Radar / Sensor", "desc": "Größere Reichweite beim Entdecken von Planeten und Fundorten.", "tiers": [
		{"name": "Standard-Sensor", "price": 0, "disc_bonus": 0.0, "mass": 0.5},
		{"name": "Erweiterter Scanner", "price": 250, "disc_bonus": 20.0, "mass": 1.0},
		{"name": "Tiefenradar", "price": 700, "disc_bonus": 40.0, "mass": 1.5},
		{"name": "Fraktions-Scanner", "price": 1600, "disc_bonus": 65.0, "mass": 2.0},
		{"name": "Quantenradar", "price": 3600, "disc_bonus": 95.0, "mass": 2.5},
		{"name": "Hypersensor-Array", "price": 8000, "disc_bonus": 140.0, "mass": 3.5}]},
	"rcs": {"title": "Steuerdüsen (RCS)", "desc": "Zusätzliche Wendigkeit und etwas Schub - kostet dafür mehr Treibstoff.", "tiers": [
		{"name": "Basis-Steuerdüsen", "price": 0, "turn": 0.0, "thrust": 0.0, "burn": 0.0, "mass": 0.5},
		{"name": "RCS Mk1", "price": 300, "turn": 0.8, "thrust": 40.0, "burn": 0.3, "mass": 1.0},
		{"name": "RCS Mk2", "price": 800, "turn": 1.3, "thrust": 70.0, "burn": 0.5, "mass": 1.3},
		{"name": "Vektor-RCS", "price": 1900, "turn": 1.9, "thrust": 110.0, "burn": 0.8, "mass": 1.8},
		{"name": "Ionen-RCS", "price": 4200, "turn": 2.6, "thrust": 160.0, "burn": 1.0, "mass": 2.2},
		{"name": "Graviton-Manövriertriebwerke", "price": 9000, "turn": 3.4, "thrust": 220.0, "burn": 1.2, "mass": 3.0}]},
	"weapon": {"title": "Waffe", "desc": "Feuern mit X oder linker Maustaste (nicht an der Station). Gleiche Fraktion wird nie getroffen.", "tiers": [
		{"name": "Unbewaffnet", "price": 0, "mass": 0.0, "w_dmg": 0.0},
		{"name": "Laser Mk1", "price": 500, "mass": 2.0, "w_dmg": 14.0, "w_cd": 0.45, "w_speed": 1300.0, "w_shots": 1.0, "w_kind": 0.0},
		{"name": "Doppellaser", "price": 1300, "mass": 3.0, "w_dmg": 11.0, "w_cd": 0.40, "w_speed": 1300.0, "w_shots": 2.0, "w_kind": 0.0},
		{"name": "Railgun", "price": 2600, "mass": 5.0, "w_dmg": 48.0, "w_cd": 1.5, "w_speed": 2600.0, "w_shots": 1.0, "w_kind": 1.0},
		{"name": "Plasmawerfer", "price": 3400, "mass": 4.0, "w_dmg": 30.0, "w_cd": 0.9, "w_speed": 800.0, "w_shots": 1.0, "w_kind": 2.0},
		{"name": "Antimateriekanone", "price": 9000, "mass": 6.0, "w_dmg": 70.0, "w_cd": 1.3, "w_speed": 1400.0, "w_shots": 1.0, "w_kind": 2.0}]},
}

# Einmal-Addons (verbrauchen sich). PvP: torpedo, emp, mine
const ITEM_ORDER: Array = ["boost", "chute", "repair", "fuel", "shield", "torpedo", "emp", "mine"]
const ITEMS := {
	"boost": {"name": "Turbo-Boost", "price": 150, "key": "Shift", "pvp": false,
		"desc": "8 Sekunden doppelter Schub und +70 % Höchsttempo.", "icon": "res://assets/items/boost.png"},
	"chute": {"name": "Fallschirm", "price": 120, "key": "F", "pvp": false,
		"desc": "Bremst in der Atmosphäre stark ab und richtet die Rakete auf. Nur mit Atmosphäre (nicht auf dem Mond).", "icon": "res://assets/items/chute.png"},
	"repair": {"name": "Reparaturkit", "price": 200, "key": "R", "pvp": false,
		"desc": "Stellt sofort 50 % der Rumpfpunkte wieder her.", "icon": "res://assets/items/repair.png"},
	"fuel": {"name": "Notfalltank", "price": 100, "key": "T", "pvp": false,
		"desc": "Füllt sofort 50 % des Tanks auf.", "icon": "res://assets/items/fuel.png"},
	"shield": {"name": "Schutzschild", "price": 250, "key": "G", "pvp": false,
		"desc": "15 Sekunden lang kein Schaden.", "icon": "res://assets/items/shield.png"},
	"torpedo": {"name": "Lenk-Torpedo", "price": 300, "key": "Q", "pvp": true,
		"desc": "Zielsuchende Rakete (55 Schaden) auf den nächsten Feind in 2500 m Reichweite.", "icon": "res://assets/items/torpedo.png"},
	"emp": {"name": "EMP-Puls", "price": 250, "key": "V", "pvp": true,
		"desc": "Feindliche Raketen im Umkreis von 800 m verlieren 4 Sekunden lang den Antrieb.", "icon": "res://assets/items/emp.png"},
	"mine": {"name": "Weltraummine", "price": 200, "key": "B", "pvp": true,
		"desc": "Bleibt liegen, 90 s lang. Feinde in der Nähe nehmen 60 Schaden. Eigene Fraktion ist sicher.", "icon": "res://assets/items/mine.png"},
}

# Gruppierung der Kategorien für die Shop-Oberfläche (Reiter "Rakete bauen").
const CATEGORY_GROUPS := [
	{"title": "Antrieb", "cats": ["engine", "nozzle", "tank", "rcs"]},
	{"title": "Struktur", "cats": ["hull", "nose", "fins", "legs"]},
	{"title": "Systeme", "cats": ["radar", "weapon"]},
]

const STAT_LABELS := {"thrust": "Schub", "max_speed": "Tempo", "fuel": "Tank", "hp": "Rumpf", "turn": "Drehrate", "safe_v": "Landung ≤"}

# Lackierungen: reine Farbtönung von Rumpf/Nase/Tank/Flügeln/Beinen (Motor/Düse/Waffe bleiben eigenfarbig).
const PAINTS := [
	{"name": "Werksfarbe", "price": 0, "color": Color(1.0, 1.0, 1.0)},
	{"name": "Feuerrot", "price": 150, "color": Color(1.0, 0.28, 0.22)},
	{"name": "Ozeanblau", "price": 150, "color": Color(0.28, 0.52, 1.0)},
	{"name": "Waldgrün", "price": 150, "color": Color(0.32, 0.85, 0.42)},
	{"name": "Sonnengelb", "price": 200, "color": Color(1.0, 0.85, 0.25)},
	{"name": "Veilchen", "price": 250, "color": Color(0.7, 0.42, 1.0)},
	{"name": "Karbonschwarz", "price": 300, "color": Color(0.4, 0.42, 0.48)},
	{"name": "Schneeweiß", "price": 300, "color": Color(1.2, 1.2, 1.25)},
	{"name": "Chrom", "price": 500, "color": Color(1.3, 1.32, 1.4)},
	{"name": "Gold-Chrom", "price": 1200, "color": Color(1.4, 1.15, 0.5)},
]


static func tiers(cat: String) -> Array:
	var d: Dictionary = UPGRADES[cat]
	return d["tiers"]


static func max_level(cat: String) -> int:
	return tiers(cat).size() - 1


static func tier(cat: String, level: int) -> Dictionary:
	var arr: Array = tiers(cat)
	return arr[clampi(level, 0, arr.size() - 1)]


static func default_levels() -> Dictionary:
	var d := {}
	for c in DRAW_ORDER:
		d[c] = 0
	return d


static func default_owned() -> Dictionary:
	var d := {}
	for c in DRAW_ORDER:
		d[c] = [0]
	return d


static func default_items() -> Dictionary:
	var d := {}
	for k in ITEM_ORDER:
		d[k] = 0
	return d


static func default_paints() -> Array:
	return [0]


# Preis unter Berücksichtigung des Fraktions-Vorteils "shop" (-8 %)
static func price_for(base: int, faction: int) -> int:
	if faction >= 0 and faction < Cfg.FACTIONS.size() and Cfg.FACTIONS[faction]["perk"] == "shop":
		return int(round(base * 0.92))
	return base


# Rechnet die ausgerüsteten Teile in Spielwerte um (Stärken, Schwächen, Masse).
static func compute_stats(levels: Dictionary) -> Dictionary:
	var sum := {"thrust": 0.0, "max_speed": 0.0, "burn": 0.0, "fuel": 0.0, "hp": 0.0, "armor": 0.0,
		"turn": 0.0, "safe_v": 0.0, "mass": 0.0, "disc_bonus": 0.0}
	for cat in DRAW_ORDER:
		var d: Dictionary = tier(cat, int(levels.get(cat, 0)))
		for k in sum:
			sum[k] += float(d.get(k, 0.0))
	var w: Dictionary = tier("weapon", int(levels.get("weapon", 0)))
	var f: float = clampf(REF_MASS / maxf(sum["mass"], 1.0), 0.5, 1.25)
	var turn: float = float(sum["turn"]) * sqrt(f)
	return {
		"thrust": float(sum["thrust"]) * f, "max_speed": float(sum["max_speed"]),
		"burn": maxf(1.5, float(sum["burn"])), "max_fuel": float(sum["fuel"]),
		"max_hp": float(sum["hp"]), "armor": minf(0.6, float(sum["armor"])),
		"turn_rate": turn, "turn_accel": turn * 3.5, "safe_v": float(sum["safe_v"]), "mass": float(sum["mass"]),
		"disc_range_mult": 1.0 + float(sum["disc_bonus"]) / 100.0,
		"w_dmg": float(w.get("w_dmg", 0.0)), "w_cd": float(w.get("w_cd", 1.0)),
		"w_speed": float(w.get("w_speed", 1000.0)), "w_shots": int(w.get("w_shots", 1.0)),
		"w_kind": int(w.get("w_kind", 0.0)),
	}


# Kurzbeschreibung der Werte einer Variante (für den Shop)
static func tier_info(cat: String, level: int) -> String:
	var d: Dictionary = tier(cat, level)
	var out: PackedStringArray = PackedStringArray()
	for k in STAT_LABELS:
		if d.has(k):
			out.append("%s %d" % [STAT_LABELS[k], int(d[k])])
	if d.has("burn"):
		out.append(("Verbrauch %.1f" % float(d["burn"])) if cat == "nozzle" else ("Verbrauch %+.1f" % float(d["burn"])))
	if d.has("armor") and float(d["armor"]) > 0.0:
		out.append("Panzerung %d %%" % int(round(float(d["armor"]) * 100.0)))
	if d.has("disc_bonus") and float(d["disc_bonus"]) > 0.0:
		out.append("Entdeckungsradius +%d %%" % int(round(float(d["disc_bonus"]))))
	if d.has("w_dmg") and float(d["w_dmg"]) > 0.0:
		out.append("%d× %d Schaden / %.1f s" % [int(d["w_shots"]), int(d["w_dmg"]), float(d["w_cd"])])
	out.append("Masse %.1f" % float(d.get("mass", 0.0)))
	return " · ".join(out)
