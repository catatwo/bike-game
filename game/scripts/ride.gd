class_name Ride
extends RefCounted
## One ride: what's being ridden (a route, a workout or a free ride), where the
## rider is, and the running totals. No drawing here, so it can be tested.

enum Kind { ROUTE, WORKOUT, FREE }

const IDLE_PAUSE := 2.0  # seconds stopped before the clock stops too
const BRAKE_AFTER := 8.0  # seconds without power before the bike brakes
const EFFORT_STEP := 0.01  # free ride: Up/Down adds or takes 1% gradient
const EFFORT_MIN := -0.04
const EFFORT_MAX := 0.10
const INTENSITY_STEP := 0.05  # workouts: Up/Down changes the targets by 5%
const INTENSITY_MIN := 0.5
const INTENSITY_MAX := 1.3
## Power records: the best average over each of these, in seconds.
const RECORD_SPANS := [5, 60, 300, 1200]
const SMOOTH := 2.0  # s: how long smooth_power and smooth_cadence average over
const SPAN_NAMES := {5: "5 s", 60: "1 min", 300: "5 min", 1200: "20 min"}

var kind: Kind = Kind.ROUTE
var route: Route
var workout: Workout
var physics := RiderPhysics.new()
var ftp := 150.0
var effort := 0.0
var intensity := 1.0
var elapsed := 0.0  # moving time, s
var energy := 0.0  # J
var max_power := 0.0
var ascent := 0.0
var finished := false
var idle := 0.0
var _unpowered := 0.0
var started_at := ""
var samples: Array = []  # once a second: [elapsed, distance, power, cadence]
var ghost := PackedFloat32Array()  # best earlier ride: distance at each second
var rival := {}  # whose best the ghost is: {"name", "time", "self"}, or {}
## Segments: the one being ridden (with "t0", when it began), the ones done
## ([{"id", "name", "time"}]), and the rider's best and the fastest of
## anyone's before this ride (id -> s; id -> {"name", "time", "self"}).
var segment_now := {}
var segments_done: Array = []
var segment_best := {}
var segment_kom := {}
## ...and the same as they stand now, this ride's laps included (the screen
## compares against these; XP against the ones before the ride).
var segment_best_now := {}
var segment_kom_now := {}
## Power: the rider's records before this ride (span -> W), and this ride's
## best average over each span so far.
var records_before := {}
var power_best := {}
## Things for the game to show, oldest first: ["segment", seg],
## ["segment_done", result], ["record", span, watts].
var events: Array = []
## Power and cadence averaged over about two seconds: what the screen
## colours and what's judged against a workout's targets (a single reading
## jumps with every pedal stroke).
var smooth_power := 0.0
var smooth_cadence := 0.0
## Workouts: seconds judged, and seconds on target, for power and cadence.
var target_time := {"power": 0.0, "power_on": 0.0, "cadence": 0.0, "cadence_on": 0.0}
var _span_sums := {}
var _told_records := {}
var _cadence_total := 0.0
var _pedalling := 0.0
var _last_elevation := 0.0


static func create(kind_: Kind, route_: Route, workout_: Workout,
		rider_kg: float, ftp_: float) -> Ride:
	var r := Ride.new()
	r.kind = kind_
	r.route = route_
	r.workout = workout_
	r.physics.rider_kg = rider_kg
	r.ftp = ftp_
	r.started_at = Time.get_datetime_string_from_system(false, true)
	r._last_elevation = route_.elevation_at(0.0)
	return r


func update(power: float, cadence: float, delta: float) -> void:
	if finished:
		return
	if power <= 0.0 and physics.speed < 0.3:
		idle += delta
		if idle > IDLE_PAUSE:
			return
	else:
		idle = 0.0
	var was_d := physics.distance
	var was_t := elapsed
	var blend := 1.0 - exp(-delta / SMOOTH)
	smooth_power = lerpf(smooth_power, power, blend)
	smooth_cadence = lerpf(smooth_cadence, cadence, blend)
	_judge_targets(delta)
	physics.step(power, physics_grade(), delta)
	# A break on a trainer shouldn't mean coasting on for a minute with the
	# clock running, so the bike brakes after a while. Not downhill, though:
	# freewheeling down a descent is part of the ride.
	_unpowered = _unpowered + delta if power <= 0.0 else 0.0
	if _unpowered > BRAKE_AFTER and physics_grade() > -0.01:
		physics.speed *= exp(-0.6 * delta)
		if physics.speed < 0.3:
			physics.speed = 0.0
	if route.endless:
		physics.distance = minf(physics.distance, route.length - Route.STEP * 2)
	if route.roaming:  # only so much road is laid out ahead (Route.keep_ahead)
		physics.distance = minf(physics.distance, (route.points.size() - 3) * Route.STEP)
	elapsed += delta
	energy += power * delta
	max_power = maxf(max_power, power)
	if cadence > 0.0:
		_cadence_total += cadence * delta
		_pedalling += delta
	var y := route.elevation_at(physics.distance)
	if y > _last_elevation:
		ascent += y - _last_elevation
	_last_elevation = y
	# One sample at every whole second, the distance interpolated to that
	# moment, however long the frames are.
	while samples.size() <= int(elapsed):
		var t := float(samples.size())
		var k := clampf((t - was_t) / maxf(elapsed - was_t, 1e-6), 0.0, 1.0)
		samples.append([t, lerpf(was_d, physics.distance, k), power, cadence])
		_track_power()
	_track_segments(was_d, was_t)
	match kind:
		Kind.ROUTE:
			if physics.distance >= route.length:
				physics.distance = route.length
				finished = true
		Kind.WORKOUT:
			if elapsed >= workout.duration:
				finished = true


func paused() -> bool:
	return idle > IDLE_PAUSE


func distance() -> float:
	return physics.distance


func speed_kmh() -> float:
	return physics.speed * 3.6


func physics_grade() -> float:
	var g := route.grade_at(physics.distance)
	return g + effort if kind == Kind.FREE else g


## The gradient to send to the bike, in percent. hill_feel scales it, like a
## trainer-difficulty setting; the speed on screen always uses the real one.
func bike_grade(hill_feel: float) -> float:
	var g := route.grade_ahead(physics.distance, 15.0)
	if kind == Kind.FREE:
		g += effort
	return g * 100.0 * hill_feel


func target_power() -> float:
	if kind != Kind.WORKOUT:
		return 0.0
	return ftp * workout.target_at(elapsed) * intensity


func change_effort(steps: int) -> void:
	effort = clampf(effort + steps * EFFORT_STEP, EFFORT_MIN, EFFORT_MAX)


func change_intensity(steps: int) -> void:
	intensity = clampf(snappedf(intensity + steps * INTENSITY_STEP, 0.01),
			INTENSITY_MIN, INTENSITY_MAX)


func average_power() -> float:
	return energy / elapsed if elapsed > 0.0 else 0.0


func average_cadence() -> float:
	return _cadence_total / _pedalling if _pedalling > 0.0 else 0.0


## Where the ghost (the best earlier ride) is now, or -1 without one.
func ghost_distance() -> float:
	if ghost.is_empty():
		return -1.0
	var i := int(elapsed)
	if i >= ghost.size() - 1:
		return ghost[ghost.size() - 1]
	return lerpf(ghost[i], ghost[i + 1], elapsed - i)


func title() -> String:
	match kind:
		Kind.WORKOUT:
			return workout.title
		Kind.FREE:
			return "Free ride: " + route.title
	return route.title


## Workouts: whether the (smoothed) power and cadence are on their targets,
## once each block has settled. Not the FTP test: that's ridden to failure.
func _judge_targets(delta: float) -> void:
	if kind != Kind.WORKOUT or workout.id == Workout.TEST_ID or workout.settling(elapsed):
		return
	var target := target_power()
	target_time["power"] += delta
	if absf(smooth_power - target) <= target * Workout.POWER_BAND:
		target_time["power_on"] += delta
	var rpm := workout.cadence_at(elapsed)
	if rpm > 0.0:
		target_time["cadence"] += delta
		if absf(smooth_cadence - rpm) <= Workout.CADENCE_BAND:
			target_time["cadence_on"] += delta


## Share of the judged time on target: {"power": 0-100, "cadence": 0-100},
## each only if there was something to judge.
func on_target() -> Dictionary:
	var out := {}
	for what in ["power", "cadence"]:
		if target_time[what] >= 10.0:
			out[what] = roundi(100.0 * target_time[what + "_on"] / target_time[what])
	return out


## Segments entered and left since the last frame, the time over each
## interpolated to where its line was crossed.
func _track_segments(was_d: float, was_t: float) -> void:
	var d := physics.distance
	if d <= was_d:
		return
	var at := func(line: float) -> float:
		return lerpf(was_t, elapsed, clampf((line - was_d) / (d - was_d), 0.0, 1.0))
	if not segment_now.is_empty() and was_d < segment_now["end"] and d >= segment_now["end"]:
		var result := {"id": segment_now["id"], "name": segment_now["name"],
			"time": snappedf(float(at.call(segment_now["end"])) - segment_now["t0"], 0.1)}
		segments_done.append(result)
		events.append(["segment_done", result])
		segment_now = {}
	if segment_now.is_empty():
		for seg in route.segments:
			if was_d < seg["start"] and d >= seg["start"]:
				segment_now = seg.duplicate()
				segment_now["t0"] = at.call(seg["start"])
				events.append(["segment", segment_now])
				break


## The best average power over each span so far, from the newest sample; a
## record beaten is told once a ride.
func _track_power() -> void:
	var n := samples.size()
	var p: float = samples[n - 1][2]
	for span in RECORD_SPANS:
		_span_sums[span] = _span_sums.get(span, 0.0) + p
		if n > span:
			_span_sums[span] -= samples[n - 1 - span][2]
		if n >= span:
			var avg: float = _span_sums[span] / span
			if avg > power_best.get(span, 0.0):
				power_best[span] = avg
				if records_before.has(span) and avg > records_before[span] and not _told_records.has(span):
					_told_records[span] = true
					events.append(["record", span, avg])


## New records this ride: [[span, W, the record before]], shortest first.
func new_records() -> Array:
	var out := []
	for span in RECORD_SPANS:
		if power_best.has(span) and records_before.has(span) and power_best[span] > records_before[span]:
			out.append([span, roundf(power_best[span]), roundf(records_before[span])])
	return out


func summary() -> Dictionary:
	var powers := {}
	for span in power_best:
		powers[str(span)] = roundf(power_best[span])
	return {
		"on_target": on_target(),
		"powers": powers,
		"segments": segments_done,
		"kind": Kind.keys()[kind].to_lower(),
		"id": workout.id if kind == Kind.WORKOUT else route.id,
		"title": title(),
		"date": started_at,
		"time": snappedf(elapsed, 0.1),
		"distance": snappedf(physics.distance, 1.0),
		"avg_power": roundf(average_power()),
		"max_power": roundf(max_power),
		"avg_cadence": roundf(average_cadence()),
		"ascent": roundf(ascent),
		"energy_kj": roundf(energy / 1000.0),
		"completed": finished,
	}
