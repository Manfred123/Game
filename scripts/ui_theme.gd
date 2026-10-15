extends RefCounted
# Einheitlicher "Raketen-Look" für alle Menüs: Metall-Panels, Nieten, orange Akzente,
# Warnstreifen. Alle Rahmen sind 9-Slice-PNGs in res://assets/ui/ und lassen sich austauschen.
#
# Theme-Varianten (Eigenschaft theme_type_variation):
#   PanelContainer: "InnerPanel" (Einträge), "HudPanel" (HUD, halbdurchsichtig)
#   Button:         "AccentButton" (orange Hauptknopf), "TabButton" (Umschalter)

const Assets = preload("res://scripts/assets.gd")

const ACCENT := Color(1.0, 0.62, 0.25)
const CYAN := Color(0.4, 0.82, 1.0)
const GOLD := Color(1.0, 0.82, 0.35)
const TEXT := Color(0.9, 0.94, 1.0)
const MUTED := Color(0.62, 0.7, 0.82)
const GOOD := Color(0.45, 0.95, 0.55)
const BAD := Color(1.0, 0.42, 0.36)

const UI := "res://assets/ui/"


# Sprite-Rahmen (9-Slice). margin = Rand der unveränderlichen Ecken in Pixeln.
static func tex_box(file: String, margin: int, pad_x: float, pad_y: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = Assets.tex(UI + file)
	sb.set_texture_margin_all(float(margin))
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func flat(bg: Color, border: Color, radius: int = 6, border_w: int = 1, margin: float = 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func bar_fill(color: Color) -> StyleBoxFlat:
	return flat(color, color.lightened(0.35), 4, 1, 0.0)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)

	# ------------------------------------------------------------ Panels
	t.set_stylebox("panel", "PanelContainer", tex_box("panel.png", 24, 22.0, 18.0))
	t.set_stylebox("panel", "Panel", tex_box("panel.png", 24, 12.0, 12.0))
	t.set_type_variation("InnerPanel", "PanelContainer")
	t.set_stylebox("panel", "InnerPanel", tex_box("slot.png", 12, 12.0, 8.0))
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", tex_box("hud_panel.png", 24, 16.0, 12.0))

	# ------------------------------------------------------------ Buttons
	_button_styles(t, "Button", "button_")
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.64))

	t.set_type_variation("AccentButton", "Button")
	_button_styles(t, "AccentButton", "accent_")
	t.set_color("font_color", "AccentButton", Color.WHITE)
	t.set_color("font_hover_color", "AccentButton", Color.WHITE)
	t.set_color("font_pressed_color", "AccentButton", Color(1, 0.94, 0.85))
	t.set_color("font_disabled_color", "AccentButton", Color(0.72, 0.66, 0.6))
	t.set_color("font_outline_color", "AccentButton", Color(0.32, 0.14, 0.02))
	t.set_constant("outline_size", "AccentButton", 4)

	# Umschalter (Tabs): ausgewählt = orange
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", tex_box("button_normal.png", 14, 14.0, 8.0))
	t.set_stylebox("hover", "TabButton", tex_box("button_hover.png", 14, 14.0, 8.0))
	t.set_stylebox("pressed", "TabButton", tex_box("accent_normal.png", 14, 14.0, 8.0))
	t.set_stylebox("hover_pressed", "TabButton", tex_box("accent_hover.png", 14, 14.0, 8.0))
	t.set_stylebox("focus", "TabButton", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "TabButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "TabButton", Color.WHITE)
	t.set_color("font_outline_color", "TabButton", Color(0.32, 0.14, 0.02))
	t.set_constant("outline_size", "TabButton", 3)

	# ------------------------------------------------------------ Eingabe
	var inp := tex_box("input.png", 10, 10.0, 6.0)
	t.set_stylebox("normal", "LineEdit", inp)
	t.set_stylebox("read_only", "LineEdit", inp)
	t.set_stylebox("focus", "LineEdit", tex_box("button_hover.png", 14, 10.0, 6.0))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.42, 0.5, 0.64))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(1.0, 0.62, 0.25, 0.4))

	# ------------------------------------------------------------ Balken
	t.set_stylebox("background", "ProgressBar", flat(Color(0.03, 0.05, 0.09), Color(0.22, 0.32, 0.48), 4, 1, 0.0))
	t.set_stylebox("fill", "ProgressBar", bar_fill(CYAN))

	# ------------------------------------------------------------ Liste
	t.set_stylebox("panel", "ItemList", tex_box("input.png", 10, 8.0, 8.0))
	var sel := flat(Color(0.32, 0.2, 0.08, 0.95), ACCENT, 4, 1, 4.0)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("hovered", "ItemList", flat(Color(0.14, 0.22, 0.36, 0.9), Color(0.3, 0.45, 0.65), 4, 1, 4.0))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_constant("v_separation", "ItemList", 6)

	# ------------------------------------------------------------ Sonstiges
	t.set_stylebox("separator", "HSeparator", flat(Color(1.0, 0.62, 0.25, 0.35), Color(0, 0, 0, 0), 0, 0, 0.0))
	t.set_constant("separation", "HSeparator", 10)
	t.set_stylebox("grabber", "VScrollBar", flat(Color(0.35, 0.5, 0.75, 0.8), Color(0, 0, 0, 0), 4, 0, 0.0))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(1.0, 0.62, 0.25, 0.9), Color(0, 0, 0, 0), 4, 0, 0.0))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(Color(1.0, 0.7, 0.35, 1.0), Color(0, 0, 0, 0), 4, 0, 0.0))
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 0, 0.0))
	return t


static func _button_styles(t: Theme, type_name: String, prefix: String) -> void:
	t.set_stylebox("normal", type_name, tex_box(prefix + "normal.png", 14, 14.0, 8.0))
	t.set_stylebox("hover", type_name, tex_box(prefix + "hover.png", 14, 14.0, 8.0))
	t.set_stylebox("pressed", type_name, tex_box(prefix + "pressed.png", 14, 14.0, 8.0))
	t.set_stylebox("disabled", type_name, tex_box(prefix + "disabled.png", 14, 14.0, 8.0))
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())


# ------------------------------------------------------------- Bausteine
# Füllt den Elternbereich komplett aus (richtig: Anker UND Offsets setzen).
static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func hazard(height: float = 8.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Assets.tex(UI + "hazard.png")
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.custom_minimum_size = Vector2(0, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func heading(text: String, size: int = 18, color: Color = CYAN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func accent_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "AccentButton"
	b.focus_mode = Control.FOCUS_NONE
	return b
