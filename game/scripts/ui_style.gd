class_name UiStyle
extends RefCounted
## Fonts, colours and panel styles shared by the menus and the HUD, sized for
## a 1920x1080 screen read from a bike (the window scales them to fit).

const INK := Color("eaf6ff")
const DIM := Color("8ea2bb")
const FAINT := Color("56687f")
const ACCENT := Color("00f0ff")
const HOT := Color("ff2bd6")
const GOOD := Color("35d07f")
const WARN := Color("ffd23f")
const BAD := Color("ff3b5c")
const BG := Color(0.015, 0.02, 0.06, 0.82)

static var _fonts := {}


## Orbitron for titles and numbers, Exo 2 for text; both variable fonts.
static func font(title: bool, weight := 500) -> Font:
	var key := "%s%d" % [title, weight]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load("res://fonts/Orbitron.ttf") if title else load("res://fonts/Exo2.ttf")
		var ts := TextServerManager.get_primary_interface()
		f.variation_opentype = {ts.name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]


static func box(border := ACCENT, bg := BG, width := 2, radius := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(20)
	sb.shadow_color = Color(border, 0.22)
	sb.shadow_size = 10
	return sb


static func label(text: String, size: int, color := INK, title := false,
		weight := 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(title, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(child: Control, border := ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(child)
	return p


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(false, 500)
	t.default_font_size = 30
	var normal := box(Color(ACCENT, 0.22), Color(0.02, 0.035, 0.09, 0.9), 1, 10)
	normal.shadow_size = 0
	normal.content_margin_left = 24
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var focus := box(ACCENT, Color(0.0, 0.45, 0.55, 0.45), 3, 10)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", DIM)
	t.set_color("font_hover_color", "Button", DIM)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_font("font", "Button", font(false, 600))
	t.set_font_size("font_size", "Button", 32)
	return t


## 754.0 -> "12:34"; 3754.0 -> "1:02:34".
static func clock(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


static func km(metres: float, decimals := 1) -> String:
	return ("%." + str(decimals) + "f km") % (metres / 1000.0)


## Colour of a gradient: blue downhill, green flat, then yellow, orange, red.
static func grade_color(g: float) -> Color:
	if g < -0.02:
		return Color("5b8cff")
	if g < 0.02:
		return GOOD
	if g < 0.05:
		return WARN
	if g < 0.08:
		return Color("ff8a2b")
	return BAD
