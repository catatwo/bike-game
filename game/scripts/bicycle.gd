class_name Bicycle
extends Node3D
## A road bike and its rider, in the neon style. Faces -Z; its origin is the
## road surface under the middle of the bike. The wheels turn with the speed,
## the cranks with the cadence, and the legs follow the pedals.
##
## The bike has a dark body whose edges glow, like the rider's suit, with thin
## glowing lines along the frame, deep-section rims and disc brakes. The rider wears a dark suit (shaders/rim.gdshader
## gives it shape with no lights in the scene) with thin glowing lines down
## the arms, legs and sides, round the helmet and along the shoes, all lying
## on the surface. Limbs taper, with rounded joints.

const WHEEL_R := 0.345  # to the outside of the tyre
const TYRE := 0.04  # tyre height
const CRANK := 0.17
const THIGH := 0.45
const SHIN := 0.46
const UPPER_ARM := 0.29
const FOREARM := 0.30

# The frame, side view: +y up, -z forward. Stays and fork blades are drawn in
# pairs either side of the middle.
const REAR_HUB := Vector3(0.0, WHEEL_R, 0.5)
const FRONT_HUB := Vector3(0.0, WHEEL_R, -0.52)
const BB := Vector3(0.0, 0.28, 0.08)
const SEAT_TOP := Vector3(0.0, 0.80, 0.23)  # top of the seat tube
const SADDLE := Vector3(0.0, 0.875, 0.23)
const HEAD_TOP := Vector3(0.0, 0.85, -0.39)
const HEAD_BOTTOM := Vector3(0.0, 0.68, -0.44)
const STEM := Vector3(0.0, 0.93, -0.47)  # where the stem meets the bar
const HOOD := Vector3(0.2, 0.93, -0.55)  # the right hood; the left mirrors it

# The rider.
const HIP := Vector3(0.0, 0.97, 0.25)
const SHOULDER := Vector3(0.0, 1.33, -0.17)
const HEAD := Vector3(0.0, 1.5, -0.29)
const HELMET := Vector3(0.12, 0.112, 0.15)  # the helmet's radii: wide, high, long
# Body shapes, as radii: across, along the spine, front to back.
const PELVIS := Vector3(0.155, 0.11, 0.105)
const CHEST := Vector3(0.185, 0.19, 0.105)
const WAIST := 0.11
const LINE := 0.0055  # the suit's glowing lines

var _frame_mat: ShaderMaterial  # glowing lines and rings
var _body_mat: ShaderMaterial  # the frame, rims and parts: dark with glowing edges
var _dim_mat: ShaderMaterial
var _tyre_mat: ShaderMaterial
var _suit_mat: ShaderMaterial
var _accent_mat: ShaderMaterial
var _ghost := false
var _wheels: Array[Node3D] = []
var _crank := Node3D.new()
var _legs := []  # one Dictionary of parts per leg
var _upper_body: Array[Node3D] = []  # hidden in the rider's-eyes view
var _wheel_angle := 0.0
var _crank_angle := 0.0


## ghost: drawn see-through, for the best earlier ride.
func _init(frame_color := Color("00f0ff"), rider_color := Color("ff3bd4"),
		ghost := false) -> void:
	_ghost = ghost
	_frame_mat = _material()
	_body_mat = _material(true)
	_dim_mat = _material()
	_tyre_mat = _material(true)
	_suit_mat = _material(true)
	_accent_mat = _material()
	set_colors(frame_color, rider_color)
	_build()


func _material(rim := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if _ghost:
		m.shader = preload("res://shaders/ghost.gdshader")
	elif rim:
		m.shader = preload("res://shaders/rim.gdshader")
	else:
		m.shader = preload("res://shaders/glow.gdshader")
	return m


func set_colors(frame_color: Color, rider_color: Color) -> void:
	if _ghost:
		# See-through: the bike in frame_color, the rider in rider_color (the
		# ghost's own rider, when racing someone else's best).
		for part in [[_frame_mat, 0.45, frame_color], [_body_mat, 0.3, frame_color],
				[_dim_mat, 0.2, frame_color], [_tyre_mat, 0.25, frame_color],
				[_suit_mat, 0.3, rider_color], [_accent_mat, 0.5, rider_color]]:
			part[0].set_shader_parameter("color", part[2])
			part[0].set_shader_parameter("brightness", part[1])
		return
	_frame_mat.set_shader_parameter("color", frame_color)
	_frame_mat.set_shader_parameter("brightness", 1.7)
	_body_mat.set_shader_parameter("base", Color(0.03, 0.05, 0.07))
	_body_mat.set_shader_parameter("rim", frame_color)
	_body_mat.set_shader_parameter("power", 1.6)
	_body_mat.set_shader_parameter("strength", 1.9)
	_dim_mat.set_shader_parameter("color", frame_color)
	_dim_mat.set_shader_parameter("brightness", 0.55)
	_tyre_mat.set_shader_parameter("base", Color(0.03, 0.03, 0.04))
	_tyre_mat.set_shader_parameter("rim", frame_color)
	_tyre_mat.set_shader_parameter("power", 3.0)
	_tyre_mat.set_shader_parameter("strength", 0.9)
	_suit_mat.set_shader_parameter("base", Color(0.035, 0.04, 0.065).lerp(rider_color, 0.05))
	_suit_mat.set_shader_parameter("rim", rider_color)
	_suit_mat.set_shader_parameter("power", 2.6)
	_suit_mat.set_shader_parameter("strength", 1.1)
	_accent_mat.set_shader_parameter("color", rider_color)
	_accent_mat.set_shader_parameter("brightness", 2.2)


# --- shapes ------------------------------------------------------------------

func _add(mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY,
		parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


## A rotation that turns +Y towards dir.
static func _towards(dir: Vector3) -> Basis:
	var n := dir.normalized()
	if n.is_equal_approx(Vector3.UP):
		return Basis()
	if n.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, n))


func _tube(a: Vector3, b: Vector3, radius: float, mat: Material,
		parent: Node3D = null) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	var d := b - a
	var xf := Transform3D(_towards(d) * Basis.from_scale(Vector3(1.0, d.length(), 1.0)), (a + b) * 0.5)
	return _add(cyl, mat, xf, parent)


## Stretch a length-1, Y-up shape (a tube or a tapered limb) from a to b.
static func _span(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	mi.transform = Transform3D(_towards(d) * Basis.from_scale(Vector3(1.0, maxf(d.length(), 1e-4), 1.0)),
			(a + b) * 0.5)


## A tapered limb, radius ra at the a end and rb at the b end; posed with _span.
func _cone(ra: float, rb: float, mat: Material, parent: Node3D = null,
		caps := false) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = ra
	cyl.top_radius = rb
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	cyl.cap_top = caps
	cyl.cap_bottom = caps
	return _add(cyl, mat, Transform3D.IDENTITY, parent)


## A frame tube from a to b, tapering from ra to rb, oval where shape isn't
## (1, 1): shape.x across the bike, shape.y the other way. trim: glowing lines
## along both sides (2), the outer side only (1, for stays and fork blades,
## which sit to one side), or none (0).
func _frame_tube(a: Vector3, b: Vector3, ra: float, rb: float, shape := Vector2.ONE,
		trim := 2) -> void:
	var mi := _cone(ra, rb, _body_mat, null, true)
	var d := b - a
	mi.transform = Transform3D(_towards(d) * Basis.from_scale(Vector3(shape.x, d.length(), shape.y)),
			(a + b) * 0.5)
	var sides := [-1.0, 1.0] if trim == 2 else ([signf(a.x + b.x)] if trim == 1 else [])
	for side in sides:
		var out := Vector3(side, 0, 0)
		_tube(a + out * (ra * shape.x + 0.002), b + out * (rb * shape.x + 0.002), 0.006, _frame_mat)


## A ring in the bike's plane, squashed across the bike by `thin` (1 = round
## section): tyres, rims, rotors.
func _wheel_ring(outer: float, inner: float, mat: Material, thin: float, at: Vector3,
		parent: Node3D) -> MeshInstance3D:
	var mi := _ring(outer, inner, mat, at, parent)
	mi.transform = Transform3D(Basis(Vector3.BACK, PI / 2) * Basis.from_scale(Vector3(1.0, thin, 1.0)), at)
	return mi


## An ellipsoid with the given radii, turned by basis.
func _ellipsoid(at: Vector3, radii: Vector3, basis: Basis, mat: Material) -> MeshInstance3D:
	var mi := _ball(Vector3.ZERO, 1.0, mat)
	mi.transform = Transform3D(basis * Basis.from_scale(radii), at)
	return mi


## A rounded limb, posed later with _pose. width stretches it sideways (x)
## and front to back (z), e.g. for a chest.
func _limb(length: float, radius: float, mat: Material, width := Vector2.ONE) -> MeshInstance3D:
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length + radius * 2.0
	cap.radial_segments = 16
	cap.rings = 8
	var mi := _add(cap, mat)
	mi.set_meta("width", width)
	return mi


## Put a limb between a and b (the centres of its round ends).
static func _pose(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var w: Vector2 = mi.get_meta("width", Vector2.ONE)
	mi.transform = Transform3D(_towards(b - a) * Basis.from_scale(Vector3(w.x, 1.0, w.y)),
			(a + b) * 0.5)


func _ball(at: Vector3, radius: float, mat: Material, stretch := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 24
	s.rings = 12
	return _add(s, mat, Transform3D(Basis.from_scale(stretch), at))


func _box(at: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(b, mat, Transform3D(Basis(), at), parent)


## A ring in the bike's plane (y-z), around the x axis.
func _ring(outer: float, inner: float, mat: Material, at: Vector3,
		parent: Node3D = null) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.outer_radius = outer
	t.inner_radius = inner
	t.rings = 40
	t.ring_segments = 8
	return _add(t, mat, Transform3D(Basis(Vector3.BACK, PI / 2), at), parent)


## A thin band along a curve (short tubes end to end), e.g. round a helmet.
func _band(points: Array, radius: float, mat: Material) -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for k in points.size() - 1:
		parts.append(_tube(points[k], points[k + 1], radius, mat))
	return parts


## Thin spokes, drawn as lines: one draw call for all of them.
static func _spokes(count: int, hub_r: float, rim_r: float) -> ArrayMesh:
	var v := PackedVector3Array()
	for k in count:
		var a := TAU * k / count
		var flange := 0.02 if k % 2 == 0 else -0.02
		v.append(Vector3(flange, cos(a) * hub_r, sin(a) * hub_r))
		v.append(Vector3(0.0, cos(a + 0.35) * rim_r, sin(a + 0.35) * rim_r))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return m


# --- building ----------------------------------------------------------------

func _build() -> void:
	# A soft shadow on the road under the bike.
	if not _ghost:
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 1.9)
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/shadow.gdshader")
		_add(q, sm, Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0.0, 0.004, 0.0)))

	_build_wheels()
	_build_frame()
	_build_drivetrain()
	_build_rider()


## Wheels, turning: a slim dark tyre, a deep dark rim with glowing edges,
## spokes, a hub, and a disc brake rotor on the left.
func _build_wheels() -> void:
	var spokes := _spokes(20, 0.03, WHEEL_R - TYRE - 0.05)
	for hub in [REAR_HUB, FRONT_HUB]:
		var wheel := Node3D.new()
		wheel.position = hub
		add_child(wheel)
		_wheel_ring(WHEEL_R, WHEEL_R - TYRE, _tyre_mat, 0.7, Vector3.ZERO, wheel)
		_wheel_ring(WHEEL_R - TYRE, WHEEL_R - TYRE - 0.05, _body_mat, 0.55, Vector3.ZERO, wheel)
		_wheel_ring(WHEEL_R - TYRE + 0.003, WHEEL_R - TYRE - 0.006, _frame_mat, 0.9, Vector3.ZERO, wheel)
		_wheel_ring(WHEEL_R - TYRE - 0.047, WHEEL_R - TYRE - 0.053, _frame_mat, 0.6, Vector3.ZERO, wheel)
		_add(spokes, _dim_mat, Transform3D.IDENTITY, wheel)
		_tube(Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0), 0.02, _body_mat, wheel)
		_wheel_ring(0.08, 0.07, _frame_mat, 0.25, Vector3(-0.045, 0, 0), wheel)
		if hub == REAR_HUB:
			for k in 3:  # cassette
				var r := 0.05 - k * 0.008
				_wheel_ring(r, r - 0.008, _frame_mat, 0.4, Vector3(0.045 + k * 0.006, 0, 0), wheel)
		_wheels.append(wheel)


## Frame, fork, cockpit and saddle.
func _build_frame() -> void:
	var o := Vector3(0.055, 0, 0)
	_frame_tube(HEAD_BOTTOM, HEAD_TOP, 0.034, 0.028, Vector2.ONE, 0)  # head tube
	_frame_tube(SEAT_TOP, HEAD_TOP + Vector3(0, -0.02, 0.01), 0.019, 0.021, Vector2(0.95, 1.15))
	_frame_tube(BB, HEAD_BOTTOM + Vector3(0, 0.03, 0.01), 0.031, 0.026, Vector2(0.75, 1.3))
	_frame_tube(BB, SEAT_TOP, 0.025, 0.02, Vector2(0.85, 1.2))
	_tube(Vector3(-0.045, 0, 0) + BB, Vector3(0.045, 0, 0) + BB, 0.032, _body_mat)  # BB shell
	_tube(SEAT_TOP, SADDLE + Vector3(0, -0.02, -0.01), 0.014, _body_mat)  # seatpost
	for side in [-1.0, 1.0]:
		_frame_tube(REAR_HUB + o * side, BB + o * side * 0.45, 0.009, 0.014, Vector2.ONE, 1)
		_frame_tube(REAR_HUB + o * side, SEAT_TOP + Vector3(0, -0.03, 0.01) + o * side * 0.25,
				0.008, 0.011, Vector2.ONE, 1)
		# Fork blades, from the crown to the front hub.
		_frame_tube(HEAD_BOTTOM + Vector3(0.052 * side, -0.01, 0), FRONT_HUB + Vector3(0.052 * side, 0, 0),
				0.018, 0.01, Vector2(0.8, 1.3), 1)
	_tube(HEAD_BOTTOM + Vector3(-0.06, -0.005, 0), HEAD_BOTTOM + Vector3(0.06, -0.005, 0), 0.02, _body_mat)
	# Stem, and drop handlebars: across the top, then forward and curling down.
	_tube(HEAD_TOP, STEM, 0.017, _body_mat)
	_tube(Vector3(-0.2, 0.93, -0.47), Vector3(0.2, 0.93, -0.47), 0.013, _body_mat)
	for x in [-1.0, 1.0]:
		var pts := [Vector3(0.2 * x, 0.93, -0.47), Vector3(0.21 * x, 0.925, -0.57),
			Vector3(0.21 * x, 0.87, -0.61), Vector3(0.21 * x, 0.8, -0.58),
			Vector3(0.21 * x, 0.79, -0.5)]
		for k in pts.size() - 1:
			_tube(pts[k], pts[k + 1], 0.012, _body_mat)
		_ellipsoid(Vector3(HOOD.x * x, HOOD.y + 0.02, HOOD.z), Vector3(0.017, 0.028, 0.035), Basis(), _body_mat)
	# Saddle, with a glowing line along its top.
	var saddle_r := Vector3(0.055, 0.0165, 0.099)
	_ellipsoid(SADDLE, saddle_r, Basis(), _body_mat)
	var top := []
	for k in 7:
		var z := lerpf(-0.85, 0.85, k / 6.0)
		top.append(SADDLE + Vector3(0, saddle_r.y * sqrt(1.0 - z * z) + 0.002, z * saddle_r.z))
	_band(top, 0.005, _frame_mat)


## Chainring, chain, rear derailleur, and the cranks (turned by _crank).
func _build_drivetrain() -> void:
	var ring_at := BB + Vector3(0.065, 0, 0)
	var disc := _cone(0.105, 0.105, _body_mat, null, true)
	disc.transform = Transform3D(Basis(Vector3.BACK, PI / 2) * Basis.from_scale(Vector3(1.0, 0.005, 1.0)), ring_at)
	_wheel_ring(0.108, 0.1, _frame_mat, 0.5, ring_at, null)
	_wheel_ring(0.06, 0.054, _frame_mat, 0.5, ring_at + Vector3(0.003, 0, 0), null)
	_tube(ring_at + Vector3(0, 0.104, 0), REAR_HUB + Vector3(0.05, 0.048, 0), 0.004, _dim_mat)
	_tube(ring_at + Vector3(0, -0.104, 0), REAR_HUB + Vector3(0.06, -0.1, -0.03), 0.004, _dim_mat)
	# Rear derailleur hanging below the cassette, with its two little wheels.
	var top_wheel := REAR_HUB + Vector3(0.062, -0.04, 0.0)
	var low_wheel := REAR_HUB + Vector3(0.062, -0.1, -0.03)
	_tube(REAR_HUB + Vector3(0.062, 0.0, 0.02), low_wheel, 0.011, _body_mat)
	for at in [top_wheel, low_wheel]:
		_wheel_ring(0.02, 0.013, _frame_mat, 0.6, at, null)
	_crank.position = BB
	add_child(_crank)
	for side in [-1.0, 1.0]:
		var arm := _cone(0.013, 0.01, _body_mat, _crank, true)
		var a := Vector3(side * 0.075, 0, 0)
		var b := Vector3(side * 0.09, -CRANK * side, 0.0)
		arm.transform = Transform3D(_towards(b - a) * Basis.from_scale(Vector3(0.8, (b - a).length(), 1.5)),
				(a + b) * 0.5)


## The rider: the upper body is hidden in the rider's-eyes view; the legs are
## posed every frame by _update_legs.
func _build_rider() -> void:
	var x := Vector3.RIGHT
	var spine := SHOULDER - HIP
	var along := _towards(spine)
	var pelvis_c := HIP + spine.normalized() * 0.02
	var chest_c := HIP.lerp(SHOULDER, 0.66)
	var waist := _limb(pelvis_c.distance_to(chest_c), WAIST, _suit_mat, Vector2(1.2, 0.95))
	_pose(waist, pelvis_c, chest_c)
	_upper_body.append_array([_ellipsoid(pelvis_c, PELVIS, along, _suit_mat),
		_ellipsoid(chest_c, CHEST, along, _suit_mat), waist])
	var neck := _limb(0.07, 0.045, _suit_mat)
	_pose(neck, SHOULDER + Vector3(0, 0.02, -0.02), HEAD + Vector3(0, -0.075, 0.035))
	_upper_body.append(neck)

	# Head: the face under the front of an egg-shaped helmet. Lines over the
	# top and round the lower edge, both on the helmet's surface.
	_upper_body.append(_ellipsoid(HEAD + Vector3(0, -0.055, -0.075), Vector3(0.075, 0.08, 0.075),
			Basis(), _suit_mat))
	_upper_body.append(_ellipsoid(HEAD, HELMET, Basis(), _suit_mat))
	var over := []
	for k in 11:
		var t := deg_to_rad(lerpf(-45.0, 100.0, k / 10.0))
		over.append(HEAD + Vector3(0.0, cos(t) * HELMET.y, sin(t) * HELMET.z) * 1.015)
	var edge := []
	var squeeze := sqrt(1.0 - pow(0.035 / HELMET.y, 2))
	for k in 17:
		var t := TAU * k / 16.0
		edge.append(HEAD + Vector3(sin(t) * HELMET.x * squeeze * 1.02, -0.035,
				-cos(t) * HELMET.z * squeeze * 1.02))
	_upper_body.append_array(_band(over, LINE * 1.6, _accent_mat))
	_upper_body.append_array(_band(edge, LINE * 1.3, _accent_mat))

	for side in [-1.0, 1.0]:
		var out: Vector3 = x * side
		# A line down each side of the body: pelvis, waist, chest.
		var body_line := [pelvis_c + out * (PELVIS.x + 0.003),
			pelvis_c.lerp(chest_c, 0.5) + out * (WAIST * 1.2 + 0.003),
			chest_c + out * (CHEST.x + 0.003),
			chest_c + along * Vector3(0, CHEST.y * 0.7, 0) + out * (CHEST.x * 0.714 + 0.003)]
		_upper_body.append_array(_band(body_line, LINE, _accent_mat))
		# Arm: shoulder, tapering upper arm, elbow, forearm, hand on the hood.
		var sh := SHOULDER + Vector3(side * 0.17, -0.03, 0.01)
		var hand := Vector3(HOOD.x * side, HOOD.y + 0.035, HOOD.z + 0.005)
		var wrist := hand + Vector3(0, 0.012, 0.055)
		var elbow := _joint(sh, wrist, UPPER_ARM, FOREARM, false) + out * 0.045
		var upper := _cone(0.052, 0.04, _suit_mat)
		_span(upper, sh, elbow)
		var fore := _cone(0.039, 0.03, _suit_mat)
		_span(fore, elbow, wrist)
		_upper_body.append_array([_ball(sh, 0.06, _suit_mat), upper, _ball(elbow, 0.04, _suit_mat),
			fore, _ellipsoid(hand, Vector3(0.034, 0.03, 0.055), Basis(), _suit_mat)])
		_upper_body.append_array(_band([sh + out * 0.061, elbow + out * 0.041, wrist + out * 0.031],
				LINE, _accent_mat))

	for side in [-1.0, 1.0]:
		var line := func() -> MeshInstance3D: return _tube(Vector3.ZERO, Vector3.UP, LINE, _accent_mat)
		_legs.append({"side": side,
			"thigh": _cone(0.082, 0.056, _suit_mat), "knee": _ball(Vector3.ZERO, 0.056, _suit_mat),
			"shin": _cone(0.055, 0.036, _suit_mat), "ankle": _ball(Vector3.ZERO, 0.037, _suit_mat),
			"shoe": _limb(0.19, 0.036, _suit_mat, Vector2(1.15, 0.8)),
			"thigh_line": line.call(), "shin_line": line.call(), "shoe_line": line.call()})
	_update_legs()


func set_first_person(on: bool) -> void:
	for part in _upper_body:
		part.visible = not on


## Turn the wheels and cranks. speed in m/s, cadence in rpm.
func animate(speed: float, cadence: float, delta: float) -> void:
	_wheel_angle = fmod(_wheel_angle - speed / WHEEL_R * delta, TAU)
	for w in _wheels:
		w.rotation.x = _wheel_angle
	_crank_angle = fmod(_crank_angle - cadence / 60.0 * TAU * delta, TAU)
	_crank.rotation.x = _crank_angle
	_update_legs()


func _update_legs() -> void:
	for leg in _legs:
		var side: float = leg["side"]
		var out := Vector3(side, 0.0, 0.0)
		var hip := HIP + Vector3(side * 0.095, -0.01, 0.0)
		# The pedal, where _crank has turned it; the ankle sits just above it.
		var pedal := BB + Basis(Vector3.RIGHT, _crank_angle) * Vector3(side * 0.13, -CRANK * side, 0.0)
		pedal.x = side * 0.13
		var ankle := pedal + Vector3(0, 0.065, 0.035)
		var knee := _joint(hip, ankle, THIGH, SHIN, true)
		_span(leg["thigh"], hip, knee)
		(leg["knee"] as Node3D).position = knee
		_span(leg["shin"], knee, ankle)
		(leg["ankle"] as Node3D).position = ankle
		_span(leg["thigh_line"], hip + out * 0.084, knee + out * 0.058)
		_span(leg["shin_line"], knee + out * 0.058, ankle + out * 0.038)
		# The ball of the foot on the pedal: heel behind and a little up. Its
		# line runs along the outside, just above the sole.
		var heel := pedal + Vector3(0, 0.05, 0.1)
		var toe := pedal + Vector3(0, 0.03, -0.09)
		_pose(leg["shoe"], heel, toe)
		_span(leg["shoe_line"], heel + Vector3(side * 0.034, -0.017, 0.0),
				toe + Vector3(side * 0.034, -0.017, 0.0))


## Two-bone joint (knee or elbow) in the side view. bend_forward: knees point
## forward; elbows (false) take the lower of the two answers, down and back.
static func _joint(a: Vector3, b: Vector3, l1: float, l2: float, bend_forward: bool) -> Vector3:
	var to := Vector2(b.z - a.z, b.y - a.y)
	var d := clampf(to.length(), 0.05, l1 + l2 - 0.001)
	var ang := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var u := to.normalized()
	var k1 := u.rotated(ang) * l1
	var k2 := u.rotated(-ang) * l1
	var k: Vector2
	if bend_forward:
		k = k1 if k1.x < k2.x else k2  # forward is -z
	else:
		k = k1 if k1.y < k2.y else k2
	return Vector3((a.x + b.x) * 0.5, a.y + k.y, a.z + k.x)
