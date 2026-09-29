class_name CameraRig
extends Camera3D
## Follows the bike: from behind, from the side, or from the rider's eyes.

enum View { BEHIND, SIDE, EYES, CLOSE }  # CLOSE: for checking the model, not in the cycle

var view := View.BEHIND
var _look := Vector3.ZERO
var _placed := false


func _init() -> void:
	fov = 68.0
	near = 0.1
	far = 4200.0


func cycle_view() -> void:
	view = ((view + 1) % 3) as View
	_placed = false


func follow(pos: Vector3, fwd: Vector3, right: Vector3, delta: float) -> void:
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var want: Vector3
	var look: Vector3
	match view:
		View.SIDE:
			want = pos + right * 2.8 - flat * 0.9 + Vector3.UP * 1.05
			look = pos + fwd * 1.0 + Vector3.UP * 0.8
		View.CLOSE:
			want = pos + right * 1.5 - flat * 0.15 + Vector3.UP * 1.05
			look = pos + Vector3.UP * 0.85 - flat * 0.05
		View.EYES:
			want = pos + flat * 0.32 + Vector3.UP * 1.6
			look = pos + fwd * 25.0 + Vector3.UP * 1.1
		_:
			# Behind and a little to the inside, so the bike reads as a bike.
			want = pos - flat * 3.7 - right * 1.0 + Vector3.UP * 1.85
			look = pos + fwd * 8.0 + Vector3.UP * 0.95
	var k := 1.0 if not _placed or view == View.CLOSE else 1.0 - exp(-6.0 * delta)
	_placed = true
	global_position = global_position.lerp(want, k)
	_look = _look.lerp(look, k)
	if global_position.distance_squared_to(_look) > 1e-4:
		look_at(_look, Vector3.UP)
