class_name Bicycle
extends Node3D
## A road bike and its rider, in the neon style. Faces -Z; its origin is the
## road surface under the middle of the bike. The wheels turn with the speed,
## the cranks with the cadence, and the legs follow the pedals.
##
## The bike has a dark body whose edges glow, with thin glowing lines along
## the frame, deep-section rims and disc brakes. The rider is smooth shapes
## (Loft), in a kit in the rider's colour (shaders/rider.gdshader): jersey
## and helmet, dark shorts with glowing seams, glowing cuffs, socks and
## visor. The upper body is one mesh, made once; the legs are another, bent
## by a skeleton (thigh, shin and foot bones for each leg), so they bend
## smoothly at the knee and cost nothing to pose.

const WHEEL_R := 0.345  # to the outside of the tyre
const TYRE := 0.04  # tyre height
const CRANK := 0.17
const THIGH := 0.45
const SHIN := 0.46
const UPPER_ARM := 0.28
const FOREARM := 0.28

# The frame, side view: +y up, -z forward. Stays and fork blades are drawn in
# pairs either side of the middle. A compact aero frame: the top tube slopes
# down to a long seat post, the seat stays meet the seat tube low. The front
# hub is ahead of the steering axis, as a fork's offset puts it, so the tyre
# clears the down tube, the fork crown and the rider's toes.
const REAR_HUB := Vector3(0.0, WHEEL_R, 0.5)
const FRONT_HUB := Vector3(0.0, WHEEL_R, -0.58)
const BB := Vector3(0.0, 0.28, 0.08)
const SEAT_TOP := Vector3(0.0, 0.75, 0.216)  # top of the seat tube
const STAY_TOP := Vector3(0.0, 0.6, 0.172)  # where the seat stays meet the seat tube
const SADDLE := Vector3(0.0, 0.875, 0.23)
const HEAD_TOP := Vector3(0.0, 0.85, -0.39)
const HEAD_BOTTOM := Vector3(0.0, 0.7, -0.44)
const STEM := Vector3(0.0, 0.93, -0.47)  # where the stem meets the bar
const HOOD := Vector3(0.2, 0.93, -0.55)  # the right hood; the left mirrors it

# The rider.
const HIP := Vector3(0.0, 0.97, 0.25)  # between the hip joints
const SHOULDER := Vector3(0.0, 1.35, -0.13)  # between the shoulder joints
const HEAD := Vector3(0.0, 1.495, -0.255)  # the middle of the head
# The spine, a curve from the bottom of the pelvis to the base of the neck,
# bowed up a little as a rider's back is.
const SPINE_FROM := Vector3(0.0, 0.93, 0.29)
const SPINE_BOW := Vector3(0.0, 1.186, 0.126)
const SPINE_TO := Vector3(0.0, 1.39, -0.1)
const REST_CRANK := PI / 2.0  # the legs are made with the cranks here: knees half bent
const SWAY := 0.035  # radians the upper body rocks either way with each turn of the cranks

# What rider.gdshader paints (Loft): g lines down both sides, r lines along
# the other two (the spine and the middle of the chest), b glowing all over.
const SUIT := Color(0, 1, 0, 0)
const TORSO := Color(1, 1, 0, 0)
const PLAIN := Color(0, 0, 0, 0)
const BAND := Color(0, 0, 1, 0)

var _frame_mat: ShaderMaterial  # glowing lines and rings
var _body_mat: ShaderMaterial  # the frame, rims and parts: dark with glowing edges
var _dim_mat: ShaderMaterial
var _tyre_mat: ShaderMaterial
var _disc_mat: ShaderMaterial  # the rear disc: flat dark, as the frame's edge glow would fill it
var _rider_mat: ShaderMaterial
var _ghost := false
var _wheels: Array[Node3D] = []
var _crank := Node3D.new()
var _skeleton := Skeleton3D.new()  # bones: thigh, shin, foot of the left leg, then the right
var _upper_body: MeshInstance3D  # hidden in the rider's-eyes view
var _sway := Node3D.new()  # the upper body rocks about it, at the hips
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
	_disc_mat = _material()
	_rider_mat = ShaderMaterial.new()
	_rider_mat.shader = preload("res://shaders/ghost.gdshader") if ghost \
			else preload("res://shaders/rider.gdshader")
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
				[_dim_mat, 0.2, frame_color], [_tyre_mat, 0.25, frame_color], [_disc_mat, 0.06, frame_color],
				[_rider_mat, 0.3, rider_color]]:
			part[0].set_shader_parameter("color", part[2])
			part[0].set_shader_parameter("brightness", part[1])
		return
	_frame_mat.set_shader_parameter("color", frame_color)
	_frame_mat.set_shader_parameter("brightness", 1.7)
	_body_mat.set_shader_parameter("base", Color(0.03, 0.05, 0.07))
	_body_mat.set_shader_parameter("rim", frame_color)
	_body_mat.set_shader_parameter("power", 1.6)
	_body_mat.set_shader_parameter("strength", 1.9)
	_disc_mat.set_shader_parameter("color", frame_color)
	_disc_mat.set_shader_parameter("brightness", 0.05)
	_dim_mat.set_shader_parameter("color", frame_color)
	_dim_mat.set_shader_parameter("brightness", 0.55)
	_tyre_mat.set_shader_parameter("base", Color(0.03, 0.03, 0.04))
	_tyre_mat.set_shader_parameter("rim", frame_color)
	_tyre_mat.set_shader_parameter("power", 3.0)
	_tyre_mat.set_shader_parameter("strength", 0.9)
	_rider_mat.set_shader_parameter("kit", rider_color)
	_rider_mat.set_shader_parameter("dark", Color(0.035, 0.04, 0.065).lerp(rider_color, 0.04))
	_rider_mat.set_shader_parameter("glow", rider_color.lerp(Color.WHITE, 0.25))


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


## A tapered tube 1 long, Y up, radius ra at the bottom and rb at the top.
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


## A thin band along a curve (short tubes end to end), e.g. along the saddle.
func _band(points: Array, radius: float, mat: Material) -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for k in points.size() - 1:
		parts.append(_tube(points[k], points[k + 1], radius, mat))
	return parts


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


## Wheels, turning, as on a time-trial bike: a disc behind and three aero
## blades in front, each dark with glowing edges; a slim dark tyre with a
## glowing line round its tread; a deep dark rim with glowing edges; glowing
## hub caps, and a disc brake rotor on the left.
func _build_wheels() -> void:
	var rim_in := WHEEL_R - TYRE - 0.05  # the inside of the deep rim
	for hub in [REAR_HUB, FRONT_HUB]:
		var wheel := Node3D.new()
		wheel.position = hub
		add_child(wheel)
		_wheel_ring(WHEEL_R, WHEEL_R - TYRE, _tyre_mat, 0.7, Vector3.ZERO, wheel)
		_wheel_ring(WHEEL_R + 0.001, WHEEL_R - 0.007, _frame_mat, 0.45, Vector3.ZERO, wheel)
		_wheel_ring(WHEEL_R - TYRE, rim_in, _body_mat, 0.55, Vector3.ZERO, wheel)
		_wheel_ring(WHEEL_R - TYRE + 0.003, WHEEL_R - TYRE - 0.006, _frame_mat, 0.9, Vector3.ZERO, wheel)
		_wheel_ring(rim_in + 0.003, rim_in - 0.003, _frame_mat, 0.6, Vector3.ZERO, wheel)
		if hub == REAR_HUB:
			var disc := _cone(rim_in, rim_in, _disc_mat, wheel, true)
			disc.transform = Transform3D(Basis(Vector3.BACK, PI / 2) * Basis.from_scale(Vector3(1.0, 0.018, 1.0)),
					Vector3.ZERO)
			for face in [-1.0, 1.0]:
				for r in [0.1, 0.19]:
					_wheel_ring(r, r - 0.005, _frame_mat, 0.3, Vector3(face * 0.01, 0, 0), wheel)
		else:
			for k in 3:
				var a := TAU * k / 3.0
				var out := Vector3(0.0, cos(a), sin(a))
				var along := Vector3(0.0, -sin(a), cos(a))
				var blade := _cone(0.03, 0.022, _body_mat, wheel, true)
				blade.transform = Transform3D(_towards(out) * Basis.from_scale(Vector3(0.3, rim_in, 1.0)),
						out * rim_in * 0.5)
				for edge in [-1.0, 1.0]:
					_tube(out * 0.04 + along * edge * 0.029, out * rim_in + along * edge * 0.021, 0.003,
							_frame_mat, wheel)
		_tube(Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0), 0.02, _body_mat, wheel)
		for x in [-0.052, 0.052]:
			_wheel_ring(0.026, 0.0, _frame_mat, 0.3, Vector3(x, 0, 0), wheel)
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
		_frame_tube(REAR_HUB + o * side, STAY_TOP + o * side * 0.3, 0.008, 0.012, Vector2.ONE, 1)
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


## The rider: the upper body is one mesh, hidden in the rider's-eyes view and
## rocking a little with the pedalling (_sway); the legs are another, skinned
## to the skeleton that _update_legs poses. Dark, with glowing lines.
func _build_rider() -> void:
	var body := Loft.new()
	# Torso: narrow at the waist, broad across the lats and shoulders, slim
	# front to back. [along the spine 0-1, half width, half depth, paint]
	var torso := [[0.0, 0.1, 0.065, TORSO], [0.07, 0.128, 0.08, TORSO], [0.16, 0.132, 0.082, TORSO],
		[0.3, 0.112, 0.075, TORSO], [0.45, 0.122, 0.082, TORSO], [0.6, 0.145, 0.09, TORSO],
		[0.74, 0.175, 0.09, TORSO], [0.85, 0.198, 0.082, TORSO], [0.93, 0.19, 0.068, TORSO],
		[1.0, 0.1, 0.055, TORSO]]
	_tube_of(body, torso, func(t: float) -> Vector3:
		return SPINE_FROM.lerp(SPINE_BOW, t).lerp(SPINE_BOW.lerp(SPINE_TO, t), t), 2.2, 3, 0.04)
	# The neck, with a glowing collar where it leaves the suit, and the head.
	var neck_from := SPINE_TO + Vector3(0.0, -0.03, 0.0)
	var neck_to := HEAD + Vector3(0.0, -0.05, 0.05)
	_tube_of(body, [[0.0, 0.052, 0.052, BAND], [0.25, 0.051, 0.051, BAND],
		[0.25, 0.051, 0.051, PLAIN], [1.0, 0.047, 0.047, PLAIN]],
		func(f: float) -> Vector3: return neck_from.lerp(neck_to, f), 2.0, 0, 0.1)
	# The head: an aero time-trial helmet over the whole of it, a smooth
	# teardrop from the face to a tail behind, a glowing line along its crest
	# (its side is up) and a glowing visor round the front.
	# [back from the head's middle, half height, half width]
	var helmet := [[-0.09, 0.05, 0.05, SUIT], [-0.055, 0.09, 0.08, SUIT], [0.0, 0.11, 0.095, SUIT],
		[0.07, 0.098, 0.088, SUIT], [0.14, 0.065, 0.06, SUIT], [0.21, 0.028, 0.025, SUIT]]
	var rise := [Vector2(-0.09, -0.02), Vector2(-0.055, -0.008), Vector2(0.0, 0.005),
		Vector2(0.07, 0.008), Vector2(0.14, -0.002), Vector2(0.21, -0.02)]
	_tube_of(body, helmet, func(back: float) -> Vector3:
		return HEAD + Vector3(0.0, _along(rise, back), back), 2.1, 3, 0.012, Vector3.UP)
	# The visor follows the helmet's outline at its widest, round the front.
	var visor := PackedVector3Array()
	var front: Array = helmet[0]
	var round_front: float = minf(front[1], front[2])
	for side in [1.0, -1.0]:
		var half := PackedVector3Array()
		for back in [-0.03, -0.045, -0.06, -0.075, front[0]]:
			var k := 0 if back <= -0.055 else 1
			var w := lerpf(helmet[k][2], helmet[k + 1][2], inverse_lerp(helmet[k][0], helmet[k + 1][0], back))
			half.append(HEAD + Vector3(side * (w + 0.004), _along(rise, back), back))
		for deg in [20.0, 40.0, 60.0, 75.0]:
			var a := deg_to_rad(deg)
			half.append(HEAD + Vector3(side * (front[2] * cos(a) + 0.004), _along(rise, front[0]),
					front[0] - (round_front * sin(a) + 0.004)))
		if side < 0.0:
			half.reverse()
		visor.append_array(half)
		if side > 0.0:
			visor.append(HEAD + Vector3(0.0, _along(rise, front[0]), front[0] - round_front - 0.004))
	var visor_r := PackedVector2Array()
	visor_r.resize(visor.size())
	visor_r.fill(Vector2(0.017, 0.006))
	var visor_c := PackedColorArray()
	visor_c.resize(visor.size())
	visor_c.fill(BAND)
	body.tube(visor, visor_r, visor_c, Vector3.UP)
	# Arms, bent at the elbow, from round shoulders to dark gloves on the
	# hoods, a glowing cuff at each wrist.
	for side in [-1.0, 1.0]:
		var sh := SHOULDER + Vector3(side * 0.175, -0.035, 0.0)
		var hand := Vector3(HOOD.x * side, HOOD.y + 0.035, HOOD.z + 0.005)
		var wrist := hand + Vector3(0, 0.012, 0.055)
		var elbow := _joint(sh, wrist, UPPER_ARM, FOREARM, false) + Vector3(side * 0.04, 0, 0)
		var l1 := sh.distance_to(elbow)
		var l := l1 + elbow.distance_to(wrist)
		var arm := [[0.0, 0.056, 0.056, SUIT], [0.05, 0.055, 0.052, SUIT], [0.12, 0.048, 0.046, SUIT],
			[l1 - 0.05, 0.042, 0.04, SUIT], [l1, 0.038, 0.037, SUIT], [l1 + 0.05, 0.043, 0.039, SUIT],
			[l1 + 0.12, 0.04, 0.035, SUIT], [l - 0.04, 0.031, 0.027, SUIT],
			[l - 0.02, 0.03, 0.026, SUIT], [l - 0.02, 0.03, 0.026, BAND], [l, 0.03, 0.026, BAND]]
		_tube_of(body, arm, func(s: float) -> Vector3: return _bent(sh, elbow, wrist, s, 0.05),
				2.0, 2, 0.02)
		body.ellipsoid(sh, Vector3(0.05, 0.05, 0.055), Basis(), PLAIN)
		body.ellipsoid(hand, Vector3(0.034, 0.03, 0.055), Basis(), PLAIN)
	_sway.position = HIP
	add_child(_sway)
	_upper_body = _add(body.mesh(), _rider_mat, Transform3D(Basis(), -HIP), _sway)

	# Legs, made with the cranks at REST_CRANK, glowing at the ankles. Each
	# ring belongs to the thigh or the shin, blending over the knee; the shoe
	# to the foot.
	add_child(_skeleton)
	var legs := Loft.new()
	for side in [-1.0, 1.0]:
		var j := _leg_at(side, REST_CRANK)
		var first := _skeleton.get_bone_count()
		for b in [["thigh", j["hip"], j["knee"]], ["shin", j["knee"], j["ankle"]],
				["foot", j["heel"], j["toe"]]]:
			_skeleton.add_bone("%s%d" % [b[0], side])
			_skeleton.set_bone_rest(_skeleton.get_bone_count() - 1, _bone(b[1], b[2]))
		var l1 := THIGH
		var l := THIGH + SHIN
		var leg := [[0.0, 0.075, 0.08, SUIT], [0.1, 0.074, 0.078, SUIT], [0.22, 0.066, 0.07, SUIT],
			[0.33, 0.058, 0.062, SUIT], [l1 - 0.04, 0.05, 0.052, SUIT], [l1, 0.047, 0.05, SUIT],
			[l1 + 0.07, 0.05, 0.058, SUIT], [l1 + 0.16, 0.048, 0.057, SUIT],
			[l1 + 0.3, 0.035, 0.04, SUIT], [l - 0.04, 0.03, 0.033, SUIT],
			[l - 0.04, 0.03, 0.033, BAND], [l, 0.03, 0.032, BAND]]
		_tube_of(legs, leg, func(s: float) -> Vector3: return _bent(j["hip"], j["knee"], j["ankle"], s, 0.06),
				2.0, 2, 0.02, Vector3.RIGHT, func(s: float) -> Vector3:
					return Vector3(first, first + 1, smoothstep(l1 - 0.08, l1 + 0.05, s)))
		var shoe := [[0.0, 0.034, 0.036, SUIT], [0.3, 0.043, 0.042, SUIT],
			[0.65, 0.041, 0.033, SUIT], [1.0, 0.026, 0.017, SUIT]]
		_tube_of(legs, shoe, func(f: float) -> Vector3: return (j["heel"] as Vector3).lerp(j["toe"], f),
				2.0, 3, 0.1, Vector3.RIGHT, func(_f: float) -> Vector3: return Vector3(first + 2, first + 2, 0.0))
	var mi := MeshInstance3D.new()
	mi.mesh = legs.mesh()
	mi.material_override = _rider_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.skin = _skeleton.create_skin_from_rest_transforms()
	mi.custom_aabb = AABB(Vector3(-0.4, 0.0, -0.8), Vector3(0.8, 1.2, 1.6))
	mi.skeleton = NodePath("..")  # its parent; the default is none
	_skeleton.add_child(mi)
	_update_legs()


## A tube through the points that `at` gives for the keys' first values: keys
## are [where, across, the other way, paint]. Between keys come rings every
## `step` (in the keys' units), sized smoothly from key to key; two keys at the
## same place change the paint there sharply. skin_at, if given, gives each
## ring's bones (Loft.tube).
static func _tube_of(loft: Loft, keys: Array, at: Callable, squareness := 2.0, cap := 3,
		step := 0.02, side := Vector3.RIGHT, skin_at := Callable()) -> void:
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var paint := PackedColorArray()
	var skin := PackedVector3Array()
	var n := keys.size()
	for k in n:
		var key: Array = keys[k]
		var count := 1
		if k + 1 < n and keys[k + 1][0] > key[0]:
			count = ceili((keys[k + 1][0] - key[0]) / step)
		for i in count:
			var f := float(i) / count
			var w: float = key[0] if i == 0 else lerpf(key[0], keys[k + 1][0], f)
			path.append(at.call(w))
			paint.append(key[3] if i == 0 else (key[3] as Color).lerp(keys[k + 1][3], f))
			if i == 0:
				radii.append(Vector2(key[1], key[2]))
			else:
				var before: Array = keys[maxi(k - 1, 0)]
				var after: Array = keys[mini(k + 2, n - 1)]
				radii.append(Vector2(key[1], key[2]).cubic_interpolate(Vector2(keys[k + 1][1], keys[k + 1][2]),
						Vector2(before[1], before[2]), Vector2(after[1], after[2]), f))
			if skin_at.is_valid():
				skin.append(skin_at.call(w))
	loft.tube(path, radii, paint, side, squareness, cap, skin)


## y at x along a smooth curve through the points (x, y).
static func _along(points: Array, x: float) -> float:
	var n := points.size()
	for k in n - 1:
		if x <= points[k + 1].x:
			return cubic_interpolate(points[k].y, points[k + 1].y, points[maxi(k - 1, 0)].y,
					points[mini(k + 2, n - 1)].y, inverse_lerp(points[k].x, points[k + 1].x, x))
	return points[n - 1].y


## The point `s` m along a limb from a, bending at joint towards b, the bend
## rounded off over `round_by` m either side of the joint.
static func _bent(a: Vector3, joint: Vector3, b: Vector3, s: float, round_by: float) -> Vector3:
	var l1 := a.distance_to(joint)
	var d1 := (joint - a) / l1
	var d2 := (b - joint).normalized()
	if s <= l1 - round_by:
		return a + d1 * s
	if s >= l1 + round_by:
		return joint + d2 * (s - l1)
	var u := (s - (l1 - round_by)) / (2.0 * round_by)
	return (joint - d1 * round_by).lerp(joint, u).lerp(joint.lerp(joint + d2 * round_by, u), u)


## A bone from `from` towards `to`: its y axis along it, x across the bike.
static func _bone(from: Vector3, to: Vector3) -> Transform3D:
	var y := (to - from).normalized()
	var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), from)


## Where a leg is with the cranks at `crank`: hip, knee and ankle, and the
## shoe's heel and toe, with the ball of the foot on the pedal.
func _leg_at(side: float, crank: float) -> Dictionary:
	var hip := HIP + Vector3(side * 0.085, -0.01, 0.0)
	var pedal := BB + Basis(Vector3.RIGHT, crank) * Vector3(side * 0.13, -CRANK * side, 0.0)
	pedal.x = side * 0.13
	var ankle := pedal + Vector3(0, 0.065, 0.035)
	return {"hip": hip, "knee": _joint(hip, ankle, THIGH, SHIN, true), "ankle": ankle,
		"heel": pedal + Vector3(0, 0.05, 0.1), "toe": pedal + Vector3(0, 0.03, -0.09)}


func set_first_person(on: bool) -> void:
	_upper_body.visible = not on


## Turn the wheels and cranks. speed in m/s, cadence in rpm.
func animate(speed: float, cadence: float, delta: float) -> void:
	_wheel_angle = fmod(_wheel_angle - speed / WHEEL_R * delta, TAU)
	for w in _wheels:
		w.rotation.x = _wheel_angle
	_crank_angle = fmod(_crank_angle - cadence / 60.0 * TAU * delta, TAU)
	_crank.rotation.x = _crank_angle
	_update_legs()
	# The upper body rocks about the line from the hips to the hands, so the
	# hands stay on the hoods.
	var axis := (Vector3(0.0, HOOD.y + 0.035, HOOD.z) - HIP).normalized()
	_sway.basis = Basis(axis, SWAY * sin(_crank_angle))


## The legs follow the pedals: each leg's three bones, where the cranks are.
func _update_legs() -> void:
	for k in 2:
		var j := _leg_at(-1.0 if k == 0 else 1.0, _crank_angle)
		var poses := [_bone(j["hip"], j["knee"]), _bone(j["knee"], j["ankle"]), _bone(j["heel"], j["toe"])]
		for b in 3:
			var xf: Transform3D = poses[b]
			_skeleton.set_bone_pose_position(k * 3 + b, xf.origin)
			_skeleton.set_bone_pose_rotation(k * 3 + b, xf.basis.get_rotation_quaternion())


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
