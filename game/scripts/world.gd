class_name World
extends Node3D
## Everything in 3D apart from the bikes: the island (Island) with its land,
## roads, scenery and landmarks; the gates along the way being ridden; the
## horizon and the sun.
##
## The island is made once. Its land is drawn in tiles around the camera,
## raised by the island's baked heights in the land shader; roads, scenery
## and landmarks exist for the whole island, and Godot leaves out what's out
## of sight. Only the gates (START, the kilometres, FINISH) belong to a ride.

const TILE := 512.0
const TILE_QUADS := 64  # 8 m apart: the baked heights' spacing
const TILES_AROUND := [2, 3, 3]  # tiles each way from the camera's, by graphics quality
const ROAD_PIECE := 80  # road points per road mesh
const LINE_HALF := 0.1  # m: half the width of a roundabout's glowing edges
const GATE_CHUNK := 400.0
const GATES_AHEAD := 6
const SCENERY_GRID := 40.0  # m between spots where scenery might stand
const SCENERY_DENSITY := [0.2, 0.4, 0.65]  # by graphics quality
const FAR_SHOW := 2600.0  # scenery and roads further away than this aren't drawn
const FAR_LIGHT := 3600.0  # landmark lights beyond this are drawn at this distance
const FOG_DENSITY := 0.0011
const SUN_DISTANCE := 3300.0
const SUN_SIZE := 1250.0

var route: Route
var island: Island
var palette := {}
var quality := 1
var _built_quality := -1
var _route_changes := 0
var _tiles: Array[MeshInstance3D] = []
var _tile_at := Vector2i(1 << 30, 0)
var _scenery := Node3D.new()
var _gates := {}
var _env: Environment
var _land_mat := ShaderMaterial.new()
var _road_mat := ShaderMaterial.new()
var _scenery_mat := ShaderMaterial.new()
var _horizon_mats: Array[ShaderMaterial] = []
var _gate_mats := {}
var _sun := MeshInstance3D.new()
var _sun_mat := ShaderMaterial.new()
var _sky_mat := ShaderMaterial.new()
var _horizon := Node3D.new()
var _lights: Array = []  # [{"at": Vector3, "node": MeshInstance3D, "size": float}]
var _scenery_meshes := {}
var _font: Font = preload("res://fonts/Orbitron.ttf")


func _ready() -> void:
	_land_mat.shader = preload("res://shaders/land.gdshader")
	_road_mat.shader = preload("res://shaders/road.gdshader")
	_scenery_mat.shader = preload("res://shaders/scenery.gdshader")
	_sun_mat.shader = preload("res://shaders/sun.gdshader")

	_sky_mat.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.fog_enabled = true
	_env.fog_density = FOG_DENSITY
	_env.fog_sky_affect = 0.0
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.glow_intensity = 0.9
	_env.glow_strength = 1.1
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 0.85
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_sun.mesh = quad
	_sun.material_override = _sun_mat
	_sun.scale = Vector3.ONE * SUN_SIZE
	_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sun)

	add_child(_horizon)
	_horizon.add_child(_mountain_ring(2600.0, 90.0, 430.0, 5))
	_horizon.add_child(_mountain_ring(1900.0, 30.0, 170.0, 9))
	add_child(_scenery)


func setup(route_: Route, quality_: int) -> void:
	for g in _gates.values():
		g.queue_free()
	_gates.clear()
	route = route_
	quality = quality_
	_route_changes = route.changes
	_last_palette = -INF
	if island == null:
		_build_island()
	if _built_quality != quality:
		_make_tiles()
		_build_scenery()
		_built_quality = quality
	palette = palette_at(0.0)
	apply_palette(palette)
	_env.glow_enabled = quality > 0


# --- the island, made once ---------------------------------------------------

func _build_island() -> void:
	island = Island.main()
	var img := Image.create_from_data(island.width, island.depth, false, Image.FORMAT_RF,
			island.heights.to_byte_array())
	_land_mat.set_shader_parameter("heights", ImageTexture.create_from_image(img))
	_land_mat.set_shader_parameter("heights_origin", island.origin)
	_land_mat.set_shader_parameter("heights_size", Vector2(island.width, island.depth))
	_land_mat.set_shader_parameter("heights_cell", Island.CELL)
	_land_mat.set_shader_parameter("outside", Island.OUTSIDE)
	# Each road up to where its way on to a roundabout begins, then the
	# roundabouts.
	for id in island.road_ids:
		var pts: PackedVector3Array = island.roads[id].points
		var span := island.road_span(id)
		var i := span[0]
		while i < span[1]:
			var j := mini(i + ROAD_PIECE, span[1])
			var mi := _instance(_road_mesh(pts, i, j), _road_mat)
			mi.visibility_range_end = FAR_SHOW
			add_child(mi)
			i = j
	for id in Island.PLACES:
		for mesh in _roundabout_meshes(id):
			var mi := _instance(mesh, _road_mat)
			mi.visibility_range_end = FAR_SHOW
			add_child(mi)
	# Landmarks: a beacon on the summit and a tower at West Gate, whose
	# lights can be seen from anywhere.
	_landmark("summit", 70.0, Color("ff2bd6"), 26.0)
	_landmark("west-gate", 28.0, Color("fff0b3"), 16.0)


func _landmark(place: String, height: float, color: Color, light_size: float) -> void:
	var at: Vector2 = Island.PLACES[place]["at"]
	# Beside the road, not on it: the first spot round the place that's clear.
	var spot := at + Vector2(30.0, 0.0)
	for k in 12:
		var tryat := at + Vector2.from_angle(TAU * k / 12.0) * 30.0
		if island.road_distance_at(tryat.x, tryat.y) >= 14.0:
			spot = tryat
			break
	var base := Vector3(spot.x, island.height_at(spot.x, spot.y), spot.y)
	var mast := BoxMesh.new()
	mast.size = Vector3(1.6, height, 1.6)
	var mi := _instance(mast, _gate_mat(color))
	mi.position = base + Vector3(0.0, height * 0.5, 0.0)
	add_child(mi)
	var light := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	light.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/beacon.gdshader")
	mat.set_shader_parameter("color", color)
	light.material_override = mat
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(light)
	_lights.append({"at": base + Vector3(0.0, height + 1.0, 0.0), "node": light, "size": light_size})


func _make_tiles() -> void:
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(TILE, TILE)
	mesh.subdivide_width = TILE_QUADS - 1
	mesh.subdivide_depth = TILE_QUADS - 1
	var r: int = TILES_AROUND[quality]
	for k in (2 * r + 1) * (2 * r + 1):
		var mi := _instance(mesh, _land_mat)
		# Raised in the shader: tell culling how high it might be.
		mi.custom_aabb = AABB(Vector3(-TILE * 0.5, -20.0, -TILE * 0.5),
				Vector3(TILE, 600.0, TILE))
		add_child(mi)
		_tiles.append(mi)
	_tile_at = Vector2i(1 << 30, 0)


func _place_tiles(cam: Vector3) -> void:
	var c := Vector2i(floori(cam.x / TILE), floori(cam.z / TILE))
	if c == _tile_at:
		return
	_tile_at = c
	var r: int = TILES_AROUND[quality]
	var k := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_tiles[k].position = Vector3((c.x + dx + 0.5) * TILE, 0.0, (c.y + dz + 0.5) * TILE)
			k += 1


## Scenery for the whole island, in each area's kind and colours, on a
## jittered grid, never on a road.
func _build_scenery() -> void:
	for c in _scenery.get_children():
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var themes := Catalog.themes()
	var groups := {}  # "x,z,kind" -> [[Transform3D, Color], ...]
	var x0 := island.origin.x
	var z0 := island.origin.y
	var x1 := x0 + island.width * Island.CELL
	var z1 := z0 + island.depth * Island.CELL
	var city: Vector2 = Island.PLACES["city"]["at"]
	var z := z0
	while z < z1:
		var x := x0
		while x < x1:
			var px := x + rng.randf() * SCENERY_GRID
			var pz := z + rng.randf() * SCENERY_GRID
			var roll := rng.randf()
			x += SCENERY_GRID
			if roll > SCENERY_DENSITY[quality]:
				continue
			var ground := island.height_at(px, pz)
			var theme: Dictionary = themes[Island.AREAS[island.area_at(Vector2(px, pz))]["theme"]]
			var kind: String = theme["scenery"]
			var size := _scenery_size(kind, rng, Vector2(px, pz).distance_to(city))
			if island.road_distance_at(px, pz) < size.x * 0.6 + 7.0:
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(size.x, size.y, size.x))
			if kind == "crystal":
				var axis := Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized()
				basis = Basis(axis, rng.randf_range(-0.3, 0.3)) * basis
			var col: Color = theme["accent"] if rng.randf() < 0.45 else theme["grid"]
			if kind == "tree":
				col = Color("1fd672").lerp(Color("d4ff3f"), rng.randf() * 0.6)
			col = col.lerp(theme["edge"], rng.randf() * 0.3)
			var key := "%d,%d,%s" % [floori(px / TILE), floori(pz / TILE), kind]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([Transform3D(basis, Vector3(px, ground + size.y * 0.5 - 0.4, pz)), col])
		z += SCENERY_GRID
	for key in groups:
		var items: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _scenery_mesh(key.get_slice(",", 2))
		mm.instance_count = items.size()
		for k in items.size():
			mm.set_instance_transform(k, items[k][0])
			mm.set_instance_color(k, items[k][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _scenery_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = FAR_SHOW
		_scenery.add_child(mi)


## Width and height of one piece of scenery. Towers are tallest in the city
## centre.
func _scenery_size(kind: String, rng: RandomNumberGenerator, from_city: float) -> Vector2:
	var h: float
	var w: float
	match kind:
		"tower":
			var centre := 1.0 - smoothstep(300.0, 2200.0, from_city)
			h = rng.randf_range(12.0, 30.0) + rng.randf_range(20.0, 90.0) * centre
			w = rng.randf_range(10.0, 26.0)
		"cube":
			h = rng.randf_range(2.0, 12.0)
			w = h * rng.randf_range(0.5, 1.0)
		"pyramid":
			h = rng.randf_range(4.0, 14.0)
			w = h * rng.randf_range(0.9, 1.3)
		"tree":
			h = rng.randf_range(4.0, 11.0)
			w = h * rng.randf_range(0.35, 0.5)
		"crystal":
			h = rng.randf_range(4.0, 18.0)
			w = h * rng.randf_range(0.12, 0.25)
		_:
			h = rng.randf_range(4.0, 16.0)
			w = h * rng.randf_range(0.18, 0.32)
	return Vector2(w, h)


# --- colours -----------------------------------------------------------------

## The colours at `distance` along the way: the area's, blending into the
## next area's as it's reached.
func palette_at(distance: float) -> Dictionary:
	var themes := Catalog.themes()
	if route == null:
		return themes["cyan"]
	var t: Array = route.theme_at(distance)
	return _mix(themes[t[0]], themes[t[1]], smoothstep(0.0, 1.0, t[2]))


static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in a:
		if a[key] is Color:
			out[key] = (a[key] as Color).lerp(b[key], k)
		else:
			out[key] = a[key] if k < 0.5 else b[key]
	return out


func apply_palette(p: Dictionary) -> void:
	var sky: Color = p["sky"]
	_env.background_color = sky
	_env.fog_light_color = p["fog"]
	_sky_mat.set_shader_parameter("top", sky.lerp(Color.BLACK, 0.4))
	_sky_mat.set_shader_parameter("horizon", (p["fog"] as Color).lerp(p["sun_bottom"], 0.12))
	_land_mat.set_shader_parameter("base_color", sky.lerp(p["fog"], 0.4))
	_land_mat.set_shader_parameter("line_color", p["grid"])
	_land_mat.set_shader_parameter("contour_color", p["accent"])
	_road_mat.set_shader_parameter("surface", sky.lerp(Color.BLACK, 0.3))
	_road_mat.set_shader_parameter("edge", p["edge"])
	_sun_mat.set_shader_parameter("top", p["sun_top"])
	_sun_mat.set_shader_parameter("bottom", p["sun_bottom"])
	for i in _horizon_mats.size():
		_horizon_mats[i].set_shader_parameter("fill", sky.lerp(p["fog"], 0.35 + 0.35 * i))
		_horizon_mats[i].set_shader_parameter("ridge", p["accent"] if i == 0 else p["grid"])


# --- every frame ---------------------------------------------------------------

var _last_palette := -INF


func update(distance: float, camera: Camera3D) -> void:
	if route == null:
		return
	# Colours only change between areas; a few times a second is plenty.
	if absf(distance - _last_palette) > 10.0:
		_last_palette = distance
		palette = palette_at(distance)
		apply_palette(palette)
	var cam := camera.global_position
	_place_tiles(cam)
	_update_gates(distance)
	_horizon.global_position = Vector3(cam.x, cam.y - 60.0, cam.z)
	_sun.global_position = cam + Vector3(0.0, SUN_SIZE * 0.42, -SUN_DISTANCE)
	_sun.look_at(cam, Vector3.UP)
	for l in _lights:
		var to: Vector3 = l["at"] - cam
		var d := to.length()
		var k := minf(1.0, FAR_LIGHT / maxf(d, 1.0))
		var node: MeshInstance3D = l["node"]
		node.global_position = cam + to * k
		node.scale = Vector3.ONE * l["size"] * k * maxf(1.0, d / 1500.0)
		node.look_at(cam, Vector3.UP)


func _update_gates(distance: float) -> void:
	if route.changes != _route_changes:  # the road ahead was laid afresh
		_route_changes = route.changes
		for g in _gates.values():
			g.queue_free()
		_gates.clear()
	var here := int(distance / GATE_CHUNK)
	var first := maxi(0, here - 1)
	var last := mini(here + GATES_AHEAD, int(route.visual_end() / GATE_CHUNK))
	for i in _gates.keys():
		if i < first or i > last:
			_gates[i].queue_free()
			_gates.erase(i)
	for i in range(first, last + 1):
		if not _gates.has(i):
			_gates[i] = _gates_for(i)


func _gates_for(i: int) -> Node3D:
	var node := Node3D.new()
	var s0 := i * GATE_CHUNK
	var s1 := minf((i + 1) * GATE_CHUNK, route.visual_end())
	var p := palette_at(s0)
	var km := int(ceil(s0 / 1000.0))
	while km * 1000.0 < s1:
		var at := km * 1000.0
		if not route.endless and at >= route.length:
			break
		if at == 0.0:
			node.add_child(_gate(at + 6.0, "START", p["edge"]))
		else:
			node.add_child(_gate(at, "%d KM" % km, p["edge"]))
		km += 1
	if not route.endless and route.length >= s0 and route.length < s1:
		node.add_child(_gate(route.length, "FINISH", p["accent"]))
	add_child(node)
	return node


# --- meshes --------------------------------------------------------------------

func _instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _array_mesh(verts: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, colors := PackedColorArray()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A stretch of road, points i0 to i1. UV.x runs across it, UV.y is metres
## along it (the dashes and the marks across).
func _road_mesh(pts: PackedVector3Array, i0: int, i1: int) -> ArrayMesh:
	var along := PackedFloat32Array()
	for i in range(i0, i1 + 1):
		along.append(i * Route.STEP)
	return _ribbon(pts, i0, i1, along, 0.0)


## A place's roundabout, in three layers so none flickers over another: the
## ring, with a dashed line round its middle and marks across; each road's
## ways on and off, and the road on in to the ring, as plain surface over
## it; and glowing edges only where the roundabout really ends (round the
## island, along the outside of each way on and off, and round the outside
## between one road's and the next's).
func _roundabout_meshes(place: String) -> Array[ArrayMesh]:
	var rb := island.roundabout(place)
	var way := 1.0 if Island.CLOCKWISE else -1.0
	var shift: float = rb["shift"]
	var ring: float = rb["ring"]
	var out: Array[ArrayMesh] = []
	# The ring. UV.x 0.1 to 0.9 keeps the road's own edges off it: they'd
	# cross the mouth of every road.
	var circle := island.ring_arc(place, 0.0, 0.0)
	var along := PackedFloat32Array()
	for k in circle.size():
		along.append(TAU * ring * k / (circle.size() - 1))
	out.append(_ribbon(_closed(circle), 1, circle.size(), along, 0.01, Route.ROAD_HALF, 0.1, 0.9))
	# Plain surface, and the edges along the outside of each way on and off.
	var arms: Array = rb["arms"]
	for arm in arms:
		var road: PackedVector3Array = island.roads[arm["road"]].points
		var inward := -1 if arm["end"] == "from" else 1
		var stub := PackedVector3Array([road[arm["index"] - inward]])
		var i: int = arm["index"]
		while i >= 0 and i < road.size() and Vector2(road[i].x, road[i].z).distance_to(rb["centre"]) > ring:
			stub.append(road[i])
			i += inward
		stub.append(road[clampi(i, 0, road.size() - 1)])
		out.append(_plain(stub, 0.02))
		for ramp in [island.ramp_on(place, arm), island.ramp_off(place, arm)]:
			var ends := _extended(ramp)
			out.append(_plain(ends, 0.02))
			out.append(_line(_kerb(ends, rb["centre"]), 0.03))
	# Round the outside between one road's ways and the next's, and round
	# the island.
	for k in arms.size():
		var next: Dictionary = arms[(k + 1) % arms.size()]
		var arc := island.ring_arc(place, arms[k]["angle"] + way * shift, next["angle"] - way * shift)
		out.append(_line(_extended(_widened(arc, rb, Route.ROAD_HALF - LINE_HALF)), 0.03))
	out.append(_line(_closed(_widened(circle, rb, -Route.ROAD_HALF + LINE_HALF)), 0.03))
	return out


## A closed loop (first point == last) with the points either side of the
## join added at the ends, so it's drawn from 1 to size - 2 without a seam.
static func _closed(loop: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array([loop[loop.size() - 2]])
	out.append_array(loop)
	out.append(loop[1])
	return out


## Points with one added beyond each end, straight on, so all of them are
## drawn (from 1 to size - 2) and the ends line up with what they meet.
static func _extended(ramp: PackedVector3Array) -> PackedVector3Array:
	var n := ramp.size()
	var out := PackedVector3Array([ramp[0] * 2.0 - ramp[1]])
	out.append_array(ramp)
	out.append(ramp[n - 1] * 2.0 - ramp[n - 2])
	return out


## Points on a roundabout's ring moved `by` m outwards (inwards if negative).
static func _widened(arc: PackedVector3Array, rb: Dictionary, by: float) -> PackedVector3Array:
	var c: Vector2 = rb["centre"]
	var out := PackedVector3Array()
	for p in arc:
		var d := (Vector2(p.x, p.z) - c).normalized() * by
		out.append(p + Vector3(d.x, 0.0, d.y))
	return out


## The outside edge of a way on or off (as _extended()): the side away from
## the roundabout where it meets the ring.
static func _kerb(ramp: PackedVector3Array, centre: Vector2) -> PackedVector3Array:
	var n := ramp.size()
	var sides := PackedVector3Array()
	for i in n:
		var a := ramp[maxi(i - 1, 0)]
		var b := ramp[mini(i + 1, n - 1)]
		var d := Vector2(b.x - a.x, b.z - a.z).normalized()
		sides.append(Vector3(-d.y, 0.0, d.x))
	# Where it meets the ring: its point nearer the centre, of its two ends.
	var ring_end := 1 if Vector2(ramp[1].x, ramp[1].z).distance_to(centre) \
			< Vector2(ramp[n - 2].x, ramp[n - 2].z).distance_to(centre) else n - 2
	var away := Vector2(ramp[ring_end].x, ramp[ring_end].z) - centre
	var sign := signf(Vector2(sides[ring_end].x, sides[ring_end].z).dot(away))
	var out := PackedVector3Array()
	for i in n:
		out.append(ramp[i] + sides[i] * sign * (Route.ROAD_HALF - LINE_HALF))
	return out


## Plain road surface along points (drawn from 1 to size - 2): no edges, no
## marks.
func _plain(pts: PackedVector3Array, lift: float) -> ArrayMesh:
	var along := PackedFloat32Array()
	along.resize(pts.size() - 2)
	along.fill(1.0)
	return _ribbon(pts, 1, pts.size() - 2, along, lift, Route.ROAD_HALF, 0.25, 0.25)


## A glowing edge line along points (drawn from 1 to size - 2).
func _line(pts: PackedVector3Array, lift: float) -> ArrayMesh:
	var along := PackedFloat32Array()
	along.resize(pts.size() - 2)
	along.fill(1.0)
	return _ribbon(pts, 1, pts.size() - 2, along, lift, LINE_HALF, 0.0, 0.0)


## Road through points i0 to i1, `half` m either side, `lift` m above the
## road's surface, `along[i - i0]` m along at each; UV.x from u0 on one side
## to u1 on the other (the road shader draws edges at 0 and 1, and the
## dashed middle line at 0.5).
func _ribbon(pts: PackedVector3Array, i0: int, i1: int, along: PackedFloat32Array,
		lift: float, half := Route.ROAD_HALF, u0 := 0.0, u1 := 1.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in range(i0, i1 + 1):
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var d := Vector2(b.x - a.x, b.z - a.z).normalized()
		var right := Vector3(-d.y, 0.0, d.x) * half
		var c := pts[i] + Vector3(0.0, Route.SURFACE + lift, 0.0)
		verts.append(c - right)
		verts.append(c + right)
		uvs.append(Vector2(u0, along[i - i0]))
		uvs.append(Vector2(u1, along[i - i0]))
		if i > i0:
			var k := (i - i0 - 1) * 2
			idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
	return _array_mesh(verts, uvs, idx)


func _scenery_mesh(kind: String) -> Mesh:
	if _scenery_meshes.has(kind):
		return _scenery_meshes[kind]
	var m: Mesh
	match kind:
		"cube", "tower":
			m = BoxMesh.new()
		"pyramid":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.7
			c.radial_segments = 4
			c.rings = 1
			m = c
		"tree":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.5
			c.radial_segments = 7
			c.rings = 1
			m = c
		_:  # prism, crystal
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.5
			c.radial_segments = 4 if kind == "prism" else 6
			c.rings = 1
			m = c
	_scenery_meshes[kind] = m
	return m


func _gate_mat(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _gate_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/glow.gdshader")
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("brightness", 1.8)
		_gate_mats[key] = m
	return _gate_mats[key]


## An arch across the road with a label: START, the kilometres, FINISH.
func _gate(s: float, text: String, color: Color) -> Node3D:
	var g := Node3D.new()
	var f := route.forward_at(s)
	var back := -Vector3(f.x, 0.0, f.z).normalized()
	g.transform = Transform3D(Basis(route.right_at(s), Vector3.UP, back), route.position_at(s))
	var mat := _gate_mat(color)
	var half := Route.ROAD_HALF + 0.7
	for x in [-half, half]:
		var post := BoxMesh.new()
		post.size = Vector3(0.35, 6.0, 0.35)
		var mi := _instance(post, mat)
		mi.position = Vector3(x, 3.0, 0.0)
		g.add_child(mi)
	var beam := BoxMesh.new()
	beam.size = Vector3(half * 2.0 + 0.35, 0.35, 0.35)
	var bi := _instance(beam, mat)
	bi.position = Vector3(0.0, 6.0, 0.0)
	g.add_child(bi)
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = 160
	label.pixel_size = 0.012
	label.outline_size = 0
	label.modulate = color * 1.6
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0.0, 7.4, 0.0)
	g.add_child(label)
	return g


## A jagged ring of mountains on the horizon, dark with a glowing ridge.
func _mountain_ring(radius: float, low: float, high: float, seed_: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var n := 160
	var phases := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for k in n + 1:
		var a := float(k) / n * TAU
		var wiggle := 0.5 + 0.25 * sin(3.0 * a + phases[0]) + 0.15 * sin(7.0 * a + phases[1]) \
				+ 0.1 * sin(17.0 * a + phases[2])
		var peak := rng.randf_range(-0.12, 0.12) if k % n != 0 else 0.0
		var h := lerpf(low, high, clampf(wiggle + peak, 0.0, 1.0))
		var dir := Vector3(sin(a), 0.0, cos(a))
		verts.append(dir * radius + Vector3(0.0, -500.0, 0.0))
		verts.append(dir * radius + Vector3(0.0, h, 0.0))
		colors.append(Color(0.0, 0.0, 0.0))
		colors.append(Color(1.0, 1.0, 1.0))
		if k > 0:
			var b := (k - 1) * 2
			idx.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/horizon.gdshader")
	_horizon_mats.append(mat)
	var mi := _instance(_array_mesh(verts, PackedVector2Array(), idx, colors), mat)
	mi.extra_cull_margin = 16384.0
	return mi
