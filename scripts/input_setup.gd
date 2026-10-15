extends RefCounted
# Legt die Tastenbelegung an.
#  - ui_up / ui_down / ui_left / ui_right sind die eingebauten Godot-Aktionen (Pfeiltasten);
#    hier kommt zusätzlich WASD dazu.
#  - Alle weiteren Aktionen werden hier angelegt.

static var _done := false


static func setup() -> void:
	if _done:
		return
	_done = true
	_add_keys("ui_up", [KEY_W])
	_add_keys("ui_down", [KEY_S])
	_add_keys("ui_left", [KEY_A])
	_add_keys("ui_right", [KEY_D])
	_add_keys("thrust", [KEY_SPACE])
	_add_keys("use_boost", [KEY_SHIFT])
	_add_keys("use_parachute", [KEY_F])
	_add_keys("use_repair", [KEY_R])
	_add_keys("use_fuel", [KEY_T])
	_add_keys("use_shield", [KEY_G])
	_add_keys("toggle_map", [KEY_M])
	_add_keys("toggle_shop", [KEY_E])
	_add_keys("toggle_help", [KEY_H])
	_add_keys("map_center", [KEY_C])
	_add_keys("reset_rocket", [KEY_K])
	_add_keys("fire", [KEY_X])
	_add_keys("use_torpedo", [KEY_Q])
	_add_keys("use_emp", [KEY_V])
	_add_keys("use_mine", [KEY_B])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", click)
	_add_keys("toggle_fullscreen", [KEY_F11])


static func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
