class_name Loft
extends RefCounted
## Smooth shapes for the rider's body, built up into one mesh: tubes (rings
## round a path, each its own size, joined into one surface, so a limb bends
## without a seam) and ellipsoids.
##
## For shaders/rider.gdshader: UV.x goes round each shape from the side its
## `side` points to (0), past the other way (0.25), to the opposite side
## (0.5); UV.y is metres along. COLOR is what the shader paints on it. With
## bones, each ring is skinned to up to two of them (Skeleton3D).

const AROUND := 24  # points round each ring

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var idx := PackedInt32Array()


## A tube through `path`. At each point: radii (across, the other way), the
## across one lying towards `side`; a colour (as above); and with bones,
## Vector3(bone, other bone, the other's weight). squareness 2 makes ellipses,
## more makes them squarer. The ends are rounded off: cap 1 the start, 2 the
## end, 3 both.
func tube(path: PackedVector3Array, radii: PackedVector2Array, cols: PackedColorArray,
		side := Vector3.RIGHT, squareness := 2.0, cap := 3,
		skin := PackedVector3Array()) -> void:
	var n := path.size()
	# Each ring: centre, its two axes, radii, how far its normals tilt along
	# the path (the caps), colour, skin, metres along.
	var rings := []
	var along := 0.0
	for k in n:
		if k > 0:
			along += path[k].distance_to(path[k - 1])
		var t := (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		var s := (side - t * t.dot(side)).normalized()
		var bone := skin[k] if not skin.is_empty() else Vector3(-1, -1, 0)
		rings.append([path[k], s, t.cross(s), radii[k], Vector2(1.0, 0.0), t, cols[k], bone, along])
	for end in [0, 1]:
		if cap & (1 << end) == 0:
			continue
		var r: Array = rings[0 if end == 0 else rings.size() - 1]
		var out: Vector3 = -r[5] if end == 0 else r[5]
		var length := minf(r[3].x, r[3].y)
		var extra := []
		for step in 3:
			var phi := PI / 2.0 * (step + 1) / 3.0
			var ring: Array = r.duplicate()
			ring[0] = r[0] + out * length * sin(phi)
			ring[3] = r[3] * cos(phi)
			ring[4] = Vector2(cos(phi), sin(phi))
			ring[5] = out
			ring[8] = r[8] + (length * sin(phi) * (-1.0 if end == 0 else 1.0))
			extra.append(ring)
		if end == 0:
			extra.reverse()
			rings = extra + rings
		else:
			rings = rings + extra
	# The shape of a ring, as a unit "superellipse": points and normals.
	var shape := []
	var e := 2.0 / squareness
	for j in AROUND + 1:
		var a := TAU * j / AROUND
		var c := cos(a)
		var sn := sin(a)
		shape.append([Vector2(signf(c) * pow(absf(c), e), signf(sn) * pow(absf(sn), e)),
			Vector2(signf(c) * pow(absf(c), 2.0 - e), signf(sn) * pow(absf(sn), 2.0 - e))])
	var first := verts.size()
	for ring in rings:
		var centre: Vector3 = ring[0]
		var s: Vector3 = ring[1]
		var m: Vector3 = ring[2]
		var rad: Vector2 = ring[3]
		var tilt: Vector2 = ring[4]
		for j in AROUND + 1:
			var p: Vector2 = shape[j][0]
			var q: Vector2 = shape[j][1]
			verts.append(centre + s * (p.x * rad.x) + m * (p.y * rad.y))
			var radial := (s * (q.x / maxf(rad.x, 1e-4)) + m * (q.y / maxf(rad.y, 1e-4))).normalized()
			normals.append((radial * tilt.x + (ring[5] as Vector3) * tilt.y).normalized())
			uvs.append(Vector2(float(j) / AROUND, ring[8]))
			colors.append(ring[6])
			if ring[7].x >= 0.0:
				bones.append_array([int(ring[7].x), int(ring[7].y), 0, 0])
				weights.append_array([1.0 - ring[7].z, ring[7].z, 0.0, 0.0])
	_join(first, rings.size())


## An ellipsoid of the given radii, turned by basis.
func ellipsoid(centre: Vector3, radii: Vector3, basis: Basis, color: Color,
		bone := Vector3(-1, -1, 0)) -> void:
	var first := verts.size()
	var rows := 10
	for i in rows + 1:
		var lat := PI * i / rows - PI / 2.0
		for j in AROUND + 1:
			var a := TAU * j / AROUND
			var unit := Vector3(cos(lat) * cos(a), sin(lat), -cos(lat) * sin(a))
			verts.append(centre + basis * (unit * radii))
			normals.append((basis * (unit / radii)).normalized())
			uvs.append(Vector2(float(j) / AROUND, (lat + PI / 2.0) * radii.y))
			colors.append(color)
			if bone.x >= 0.0:
				bones.append_array([int(bone.x), int(bone.y), 0, 0])
				weights.append_array([1.0 - bone.z, bone.z, 0.0, 0.0])
	_join(first, rows + 1)


## Triangles between each ring and the next: clockwise seen from outside, as
## Godot draws front faces. (Each ring goes round its path right-handed.)
func _join(first: int, count: int) -> void:
	var w := AROUND + 1
	for r in count - 1:
		for j in AROUND:
			var a := first + r * w + j
			var b := a + w
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])


func mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	if not bones.is_empty():
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
