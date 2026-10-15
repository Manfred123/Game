extends RefCounted
# ============================================================================
#  ZENTRALE EINSTELLUNGEN
#  Hier kannst du das ganze Spiel ausbalancen (Coins, Schaden, Welt, Planeten).
# ============================================================================

const GAME_ID := "RAKETEN_ONLINE"
const VERSION := 4

# ---------------------------------------------------------------- Netzwerk
const BASE_PORT := 7777              # erster Spielport; weitere Server auf demselben PC nehmen 7778, 7779 ...
const MAX_SERVERS_PER_PC := 20       # so viele Ports werden durchprobiert bzw. gescannt
const DISCOVERY_OFFSET := 1000       # Such-Port = Spielport + 1000 (UDP)
const DISCOVER_MAGIC := "RAKETEN_ONLINE_DISCOVER_1"
const MAX_PLAYERS := 16
const MAX_NAME_LEN := 16

# Netzwerk-Protokoll (Application-Level-Logging) -> user://netlog_*.log
const LOG_SAMPLE := 60               # häufige Nachrichten (Input/Snapshot) erscheinen nur jede n-te in der Konsole; die Datei bekommt ALLE. 1 = alles auch in der Konsole
const MAX_INPUT_RATE := 150          # Server-Validierung: max. Eingabe-Pakete pro Sekunde und Client
const MAX_SEQ_JUMP := 600            # Server-Validierung: größere Sprünge der Sequenznummer werden verworfen

# -------------------------------------------------------------- Simulation
const DT := 1.0 / 60.0               # feste Physik-Schrittweite (Server + Client identisch!)
const SNAPSHOT_EVERY := 2            # alle 2 Ticks ein Snapshot = 30 pro Sekunde
const SNAP_STRIDE := 15              # Floats pro Spieler im Snapshot

# ----------------------------------------------------------------- Ökonomie
const START_COINS := 400
const FLIGHT_COIN_INTERVAL := 300.0  # alle 5 Minuten Flugzeit ...
const FLIGHT_COIN_AMOUNT := 150      # ... gibt es so viele Coins
const LANDING_COOLDOWN := 90.0       # Sekunden bis eine Planeten-Landeprämie wieder gilt
const SHOP_ONLY_AT_STATION := true   # false = Shop auch auf jedem Planeten nutzbar
const MAX_ITEM_STACK := 9

# ------------------------------------------------------------------ Rakete
const ROCKET_RADIUS := 34.0          # Kollisionsradius zwischen Spielern
const LAND_RADIUS := 52.0            # Abstand Raketenmitte -> Landebeine
const LAND_ALIGN := 0.82             # Nase muss ungefähr vom Planeten weg zeigen (cos 35°)
const CRASH_DMG_FACTOR := 0.28       # Schaden pro m/s über der sicheren Landegeschwindigkeit
const BOUNCE := 0.3
const OVERSPEED_DECEL := 900.0       # wie stark über dem Tempolimit abgebremst wird
const WORLD_RADIUS := 110000.0       # Rand der Welt (harte Grenze)
const RESPAWN_TIME := 3.0
const RESET_COOLDOWN := 10.0         # Sekunden zwischen zwei Resets (Zurück zur Station)

const PLAYER_RESTITUTION := 0.6
const PLAYER_CRASH_SPEED := 140.0    # Rammen unter diesem Tempo tut nicht weh
const PLAYER_CRASH_DMG := 0.2

# Addons (Einmal-Gegenstände)
const BOOST_TIME := 8.0
const BOOST_THRUST := 2.0
const BOOST_SPEED := 1.7
const SHIELD_TIME := 15.0
const CHUTE_DRAG := 3.0
const CHUTE_MAX_TIME := 45.0

# Station / Landen
const STATION_RADIUS := 620.0        # so nah am Nordpol der Erde gilt man als "an der Station"
const STATION_REFUEL := 40.0         # Treibstoff pro Sekunde an der Station
const STATION_REPAIR := 25.0         # Rumpf pro Sekunde an der Station
const LANDED_REFUEL := 4.0           # Treibstoff pro Sekunde auf jedem anderen Planeten
const SPAWN_SPACING := 72.0
const STATION_PAD_Y := 250.0         # Y-Position der Landefläche im station.png (von oben)

# ------------------------------------------------------------------ Planeten
# pos = Mittelpunkt, radius = Größe, g = Oberflächen-Schwerkraft (m/s²),
# range = Reichweite der Schwerkraft, atmo = Höhe der Atmosphäre (Fallschirm geht nur dort),
# reward = Coins für die erste Landung (danach Cooldown).
const PLANETS: Array = [
	{"name": "Erde", "pos": Vector2(0, 0), "radius": 1000.0, "g": 165.0, "range": 3800.0, "atmo": 380.0,
	 "reward": 0, "tex": "res://assets/world/earth.png", "glow": Color(0.35, 0.6, 1.0, 0.55)},
	{"name": "Mond", "pos": Vector2(8200, -4200), "radius": 380.0, "g": 62.0, "range": 1700.0, "atmo": 0.0,
	 "reward": 300, "tex": "res://assets/world/moon.png", "glow": Color(1, 1, 1, 0.0)},
	{"name": "Mars", "pos": Vector2(-17000, -9500), "radius": 700.0, "g": 115.0, "range": 3000.0, "atmo": 240.0,
	 "reward": 800, "tex": "res://assets/world/mars.png", "glow": Color(1.0, 0.55, 0.35, 0.45)},
	{"name": "Venus", "pos": Vector2(21000, 13500), "radius": 950.0, "g": 150.0, "range": 3600.0, "atmo": 520.0,
	 "reward": 1200, "tex": "res://assets/world/venus.png", "glow": Color(1.0, 0.85, 0.45, 0.55)},
	{"name": "Merkur", "pos": Vector2(-8500, 24000), "radius": 330.0, "g": 58.0, "range": 1500.0, "atmo": 0.0,
	 "reward": 1500, "tex": "res://assets/world/mercury.png", "glow": Color(1, 1, 1, 0.0)},
	{"name": "Jupiter", "pos": Vector2(48000, -34000), "radius": 2600.0, "g": 300.0, "range": 9000.0, "atmo": 900.0,
	 "reward": 3200, "tex": "res://assets/world/jupiter.png", "glow": Color(1.0, 0.75, 0.5, 0.45)},
	{"name": "Neptun", "pos": Vector2(-62000, 46000), "radius": 1900.0, "g": 250.0, "range": 7000.0, "atmo": 800.0,
	 "reward": 5000, "tex": "res://assets/world/neptune.png", "glow": Color(0.3, 0.5, 1.0, 0.55)},
	{"name": "Europa", "pos": Vector2(54500, -29000), "radius": 300.0, "g": 55.0, "range": 1400.0, "atmo": 0.0,
	 "reward": 1800, "tex": "res://assets/world/europa.png", "glow": Color(1, 1, 1, 0.0)},
	{"name": "Titan", "pos": Vector2(30000, -6000), "radius": 520.0, "g": 70.0, "range": 2200.0, "atmo": 300.0,
	 "reward": 2200, "tex": "res://assets/world/titan.png", "glow": Color(1.0, 0.65, 0.25, 0.5)},
	{"name": "Ceres", "pos": Vector2(-30000, -30000), "radius": 260.0, "g": 40.0, "range": 1200.0, "atmo": 0.0,
	 "reward": 1000, "tex": "res://assets/world/ceres.png", "glow": Color(1, 1, 1, 0.0)},
]

# Erforschung: Diese Planeten kennt jeder von Anfang an (Rest erscheint auf der Karte als "?")
const START_DISCOVERED: Array = [0, 1]
const DISCOVER_FACTOR := 0.3         # Entdeckungsprämie = Landeprämie * Faktor + 100
const POI_RADIUS := 170.0            # so nah muss man an einen Fundort fliegen
# Fundorte (pro Spieler einmalig): kind = wreck | crystal | cache | beacon | artifact
const POIS: Array = [
	{"name": "Alter Satellit", "kind": "wreck", "pos": Vector2(5200, 2600), "coins": 120},
	{"name": "Mondkristall", "kind": "crystal", "pos": Vector2(11500, -6500), "coins": 150},
	{"name": "Sowjet-Sonde", "kind": "wreck", "pos": Vector2(-6000, -5200), "coins": 250},
	{"name": "Vorratsdepot", "kind": "cache", "pos": Vector2(-12000, 2000), "coins": 0},
	{"name": "Signalbake", "kind": "beacon", "pos": Vector2(14000, 9000), "coins": 300},
	{"name": "Eiskristall", "kind": "crystal", "pos": Vector2(36000, -30000), "coins": 400},
	{"name": "Geisterschiff", "kind": "wreck", "pos": Vector2(-20000, 14000), "coins": 500},
	{"name": "Verlorene Fracht", "kind": "cache", "pos": Vector2(30000, 20000), "coins": 0},
	{"name": "Kometenbruch", "kind": "wreck", "pos": Vector2(-48000, 30000), "coins": 700},
	{"name": "Uraltes Artefakt", "kind": "artifact", "pos": Vector2(-42000, -20000), "coins": 1500},
	{"name": "Fremdes Signal", "kind": "artifact", "pos": Vector2(70000, 30000), "coins": 2500},
]

# ------------------------------------------------------------------ PvP / Fraktionen
const KILL_REWARD := 250             # Kopfgeld pro Abschuss
const KILL_ENEMY_FACTION_BONUS := 100
const COMBAT_TAG_TIME := 10.0        # so lange zählt der letzte Angreifer als Killer
const FACTION_KILLS_PER_LEVEL := 3   # je 3 Abschüsse an anderen Fraktionen = 1 Bonusstufe
const FACTION_MAX_LEVEL := 10
const FACTION_FLIGHT_BONUS := 0.15   # +15 % Flug-Coins pro Bonusstufe
const FACTION_LANDING_BONUS := 0.05  # +5 % Landeprämie pro Bonusstufe
const FACTION_SWITCH_COOLDOWN := 120.0
const FACTION_MAX_SHARE := 0.35      # eine Fraktion darf höchstens diesen Anteil aller Spieler stellen
const FACTION_MIN_CAPACITY := 2      # ...aber immer mindestens so viele Plätze, auch bei wenigen Spielern
const CAPTURE_TIME := 240.0          # Sekunden exklusiver Präsenz einer Fraktion, um einen Planeten zu erobern
const CAPTURE_DECAY := 0.4           # Eroberungsfortschritt/Sekunde, der bei Umkämpfung oder Leerstand verloren geht
const OUTPOST_FLAG_SCALE := 1.0
const TORPEDO_DMG := 55.0
const TORPEDO_SPEED := 650.0
const TORPEDO_LIFE := 8.0
const TORPEDO_TURN := 2.2
const TORPEDO_RANGE := 2500.0
const EMP_RADIUS := 800.0
const EMP_TIME := 4.0
const MINE_DMG := 60.0
const MINE_RADIUS := 70.0
const MINE_LIFE := 90.0
const MINE_ARM := 1.5

# perk: landing = +10 % Landeprämie, shop = -8 % Preise, kill = +15 % Kopfgeld, flight = +10 % Flug-Coins
const FACTIONS: Array = [
	{"name": "NASA", "short": "NASA", "color": Color(0.25, 0.5, 1.0), "perk": "landing",
	 "desc": "Apollo-Erbe: sichere Landungen, +10 % Landeprämie."},
	{"name": "SpaceX", "short": "SPX", "color": Color(0.85, 0.9, 0.97), "perk": "shop",
	 "desc": "Serienfertigung: 8 % günstigere Preise im Shop."},
	{"name": "Sowjetisches Raumfahrtprogramm", "short": "SOW", "color": Color(0.92, 0.18, 0.16), "perk": "kill",
	 "desc": "Pioniere der Raumfahrt: +15 % Kopfgeld."},
	{"name": "CNSA (China)", "short": "CNSA", "color": Color(1.0, 0.8, 0.15), "perk": "flight",
	 "desc": "Langer Atem: +10 % Flug-Coins."},
	{"name": "ESA (Europa)", "short": "ESA", "color": Color(0.3, 0.85, 0.95), "perk": "landing",
	 "desc": "Kooperation: +10 % Landeprämie."},
	{"name": "ISRO (Indien)", "short": "ISRO", "color": Color(1.0, 0.55, 0.15), "perk": "shop",
	 "desc": "Sparsam und klug: 8 % günstigere Preise im Shop."},
]

# Oberster Punkt eines Himmelskörpers (Nordpol) - Ort für Station/Außenposten-Fahne.
static func planet_top(idx: int) -> Vector2:
	var pl: Dictionary = PLANETS[idx]
	var p: Vector2 = pl["pos"]
	return p + Vector2(0.0, -float(pl["radius"]))


static func station_pos() -> Vector2:
	return planet_top(0)
