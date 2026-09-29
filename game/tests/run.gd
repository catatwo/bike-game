extends SceneTree
## Headless tests: godot --headless --path game --script res://tests/run.gd
## Exits non-zero if any check fails, so the Docker build stops.

var _failed := 0
var _checks := 0
var _current := ""


func _init() -> void:
	for m in get_method_list():
		if m["name"].begins_with("test_"):
			_current = m["name"]
			call(m["name"])
	print("%d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL %s: %s" % [_current, what])


func near(a: float, b: float, tol: float, what: String) -> void:
	check(absf(a - b) <= tol, "%s: %.3f, expected %.3f ± %.3f" % [what, a, b, tol])


func _steady(power: float, grade: float) -> float:
	var p := RiderPhysics.new()
	p.rider_kg = 80.0
	for i in 60 * 300:
		p.step(power, grade, 1.0 / 60.0)
	return p.speed * 3.6


# --- physics -----------------------------------------------------------------

func test_speed_on_the_flat_is_realistic() -> void:
	near(_steady(200.0, 0.0), 34.0, 1.5, "200 W on the flat, km/h")
	near(_steady(100.0, 0.0), 26.5, 1.5, "100 W on the flat, km/h")


func test_speed_uphill_is_realistic() -> void:
	near(_steady(200.0, 0.08), 9.5, 0.8, "200 W up 8%, km/h")


func test_no_power_means_stopping_on_the_flat_and_rolling_downhill() -> void:
	var p := RiderPhysics.new()
	p.speed = 8.0
	for i in 60 * 120:
		p.step(0.0, 0.0, 1.0 / 60.0)
	check(p.speed < 2.5, "coasting slows down on the flat")
	var d := RiderPhysics.new()
	for i in 60 * 60:
		d.step(0.0, -0.06, 1.0 / 60.0)
	check(d.speed * 3.6 > 40.0, "freewheeling down 6%% gets fast (%.1f km/h)" % (d.speed * 3.6))


# --- routes ------------------------------------------------------------------

func test_every_route_is_sane() -> void:
	for spec in Catalog.routes() + Catalog.free_rides() + [Catalog.workout_road()]:
		var r := Route.from_spec(spec)
		if r.roaming:
			check(r.points.size() * Route.STEP >= Route.ROAM_AHEAD * 0.9, "%s laid out ahead" % r.title)
		else:
			check(r.points.size() * Route.STEP >= r.length, "%s long enough" % r.title)
		var lo := 1.0
		var hi := -1.0
		for g in r.grades:
			lo = minf(lo, g)
			hi = maxf(hi, g)
		check(lo >= Route.MIN_GRADE and hi <= Route.MAX_GRADE, "%s grades in range" % r.title)
		near(r.grade_at(0.0), 0.0, 0.002, "%s starts flat" % r.title)
		if not r.endless:
			near(r.grade_at(r.length), 0.0, 0.002, "%s finishes flat" % r.title)
		check(Catalog.themes().has(r.theme), "%s theme exists" % r.title)


func test_routes_are_the_same_every_time() -> void:
	var spec: Dictionary = Catalog.routes()[3]
	var a := Route.from_spec(spec)
	var b := Route.from_spec(spec)
	check(a.points[500].is_equal_approx(b.points[500]), "same spec, same road")


func test_positions_are_continuous() -> void:
	var r := Route.from_spec(Catalog.routes()[5])
	var prev := r.position_at(0.0)
	var worst := 0.0
	for i in range(1, 2000):
		var p := r.position_at(i * 1.0)
		worst = maxf(worst, p.distance_to(prev))
		prev = p
	check(worst < 1.2, "no jumps between metres (worst %.2f m)" % worst)


func test_the_summit_climb_climbs() -> void:
	var r := Route.from_spec(Catalog.find(Catalog.routes(), "summit-climb"))
	var south: float = Island.main().roads["south-road"].length()
	near(r.grade_at(south + 2000.0), 0.055, 0.02, "climbing 2 km up the summit road")
	check(r.ascent > 280.0, "climbs over 280 m (%.0f)" % r.ascent)
	near(r.position_at(r.length).y, Island.PLACES["summit"]["elev"], 0.5, "finishes at the summit")


func test_route_times_span_ten_minutes_to_an_hour() -> void:
	# A beginner around 120 W: the list should have short and long rides.
	var times := {}
	for spec in Catalog.routes():
		times[spec["name"]] = RiderPhysics.time_for(Route.from_spec(spec), 120.0, 80.0) / 60.0
	print("route minutes at 120 W: ", times)
	var shortest := INF
	var longest := 0.0
	for v in times.values():
		shortest = minf(shortest, v)
		longest = maxf(longest, v)
	check(shortest <= 12.0, "a short route exists (%.0f min)" % shortest)
	check(longest >= 50.0 and longest <= 80.0, "the longest is about an hour (%.0f min)" % longest)


func test_the_land_meets_the_road() -> void:
	var worst := 0.0
	var edge := 0.0
	for spec in Catalog.routes():
		var r := Route.from_spec(spec)
		var s := 37.0
		while s < r.length:
			var y := r.position_at(s).y
			worst = maxf(worst, absf(r.land_point(s, 0.0).y - (y - 0.05)))
			edge = maxf(edge, absf(r.land_point(s, Route.ROAD_HALF + 0.5).y - y))
			s += 173.0
	check(worst < 0.1, "the land is just under the road (worst %.2f m)" % worst)
	check(edge < 0.4, "and level with it at its edges (worst %.2f m)" % edge)


# --- the island ----------------------------------------------------------------

func test_island_roads_are_rideable() -> void:
	var isl := Island.main()
	for id in isl.road_ids:
		var pts: PackedVector3Array = isl.roads[id].points
		var lo := 0.0
		var hi := 0.0
		var gap := 0.0
		for i in pts.size() - 1:
			var g := (pts[i + 1].y - pts[i].y) / Route.STEP
			lo = minf(lo, g)
			hi = maxf(hi, g)
			gap = maxf(gap, Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[i + 1].x, pts[i + 1].z)))
		check(lo >= Route.MIN_GRADE and hi <= Route.MAX_GRADE,
				"%s gradients %.1f%% to %.1f%%" % [id, lo * 100.0, hi * 100.0])
		check(gap < Route.STEP * 1.02, "%s points evenly spaced (%.2f m)" % [id, gap])
		var r: Island.Road = isl.roads[id]
		var start: Vector2 = Island.PLACES[r.from]["at"]
		var end: Vector2 = Island.PLACES[r.to]["at"]
		check(Vector2(pts[0].x, pts[0].z).distance_to(start) < 0.5
				and Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z).distance_to(end) < 0.5,
				"%s starts and ends at its places" % id)


func test_paths_join_up() -> void:
	for spec in Catalog.routes():
		var r := Route.from_spec(spec)
		var worst := 0.0
		for i in r.points.size() - 1:
			worst = maxf(worst, r.points[i].distance_to(r.points[i + 1]))
		check(worst < Route.STEP * 1.1, "%s has no gaps (worst %.1f m)" % [r.title, worst])
		var want: Array = spec["path"]
		var got := r.legs.slice(0, want.size()).map(func(l: Dictionary) -> String: return l["leg"])
		check(got == want and r.legs.size() > want.size(), "%s's roads, then the road past the finish" % r.title)


## Rides a roaming route's road out to `far` m, as a rider would.
func _roam_to(r: Route, far: float) -> void:
	var s := 0.0
	while s < far:
		r.keep_ahead(s)
		s += 500.0


func test_free_rides() -> void:
	var isl := Island.main()
	var levels := {}
	for spec in Catalog.free_rides():
		levels[spec["level"]] = levels.get(spec["level"], 0) + 1
		var r := Route.from_spec(spec)
		if spec.has("loop"):
			check(r.points.size() * Route.STEP >= Route.ENDLESS, "%s is endless" % spec["name"])
			var lap: Dictionary = isl.path(spec["loop"])
			check(lap["end"] == isl.leg_start(spec["loop"][0]), "%s's lap ends where it starts" % spec["name"])
		else:
			check(r.roaming, "%s roams" % spec["name"])
			_roam_to(r, 60000.0)
			check(r.points.size() * Route.STEP >= 60000.0 + Route.ROAM_TOP_UP, "%s keeps road ahead" % spec["name"])
			var avoid := Route.avoided(spec)
			var roads := {}
			for leg in r.legs:
				roads[leg["road"]] = true
			var bad := avoid.filter(func(id: String) -> bool: return roads.has(id))
			check(bad.is_empty(), "%s keeps off %s" % [spec["name"], bad])
			check(roads.size() >= 6, "%s sees a good part of the island (%d roads)" % [spec["name"], roads.size()])
			if spec.has("max_grade"):
				var steep := roads.keys().filter(func(id: String) -> bool: return isl.steepest(id) > spec["max_grade"])
				check(steep.is_empty(), "%s has nothing steeper than %d%%" % [spec["name"], spec["max_grade"] * 100])
	check(levels.size() == 3 and levels.values().min() >= 2, "two or more at each level: %s" % [levels])
	var spec: Dictionary = Catalog.find(Catalog.free_rides(), "free-rolling")
	var a := Route.from_spec(spec)
	var other := spec.duplicate()
	other["roam"] = 12345
	var b := Route.from_spec(other)
	_roam_to(a, 60000.0)
	_roam_to(b, 60000.0)
	var same := 0
	for i in 12:
		if a.legs[i]["leg"] == b.legs[i]["leg"]:
			same += 1
	check(same < 12, "another seed takes another way round")
	var all := Route.from_spec(Catalog.find(Catalog.free_rides(), "roam-all"))
	_roam_to(all, 80000.0)
	check(all.legs.any(func(l: Dictionary) -> bool: return l["road"] == "summit-road"), "roaming everywhere climbs the mountain")


func test_turns_at_a_place() -> void:
	var isl := Island.main()
	var options := isl.turn_options("city", "-hill-road", [])
	var legs: Array = options.map(func(o: Dictionary) -> String: return o["leg"])
	check(not legs.has("hill-road") and legs.size() == 4, "every way on but straight back: %s" % [legs])
	var turns: Array = options.map(func(o: Dictionary) -> float: return o["turn"])
	var sorted := turns.duplicate()
	sorted.sort()
	check(turns == sorted, "leftmost first: %s" % [turns])
	check(not isl.turn_options("city", "-hill-road", ["south-road"]).any(
			func(o: Dictionary) -> bool: return o["leg"] == "south-road"), "avoided roads aren't offered")
	var dead := isl.turn_options("summit", "summit-road", ["summit-east"])
	check(dead.size() == 1 and dead[0]["leg"] == "-summit-road", "a dead end turns back")


func test_choosing_a_turn_keeps_the_road_ridden() -> void:
	var spec: Dictionary = Catalog.find(Catalog.free_rides(), "roam-all").duplicate()
	var r: Route
	var t := {}
	# A way round whose first place has more than one way on.
	for seed in range(1, 40):
		spec["roam"] = seed
		r = Route.from_spec(spec)
		t = r.next_turn(100.0)
		if not t.is_empty() and t["options"].size() >= 2:
			break
	check(t["options"].size() >= 2, "found a place with a choice")
	var before := r.points.duplicate()
	var cut := int((float(t["s"]) - Route.STEP) / Route.STEP)
	var step := 1 if int(t["index"]) == 0 else -1
	var after := r.choose_turn(100.0, step)
	check(int(after["index"]) == int(t["index"]) + step, "the next way on is taken")
	check(r.legs[int(t["j"])]["leg"] == after["options"][after["index"]]["leg"], "and laid out")
	var same := true
	for i in cut:
		if not r.points[i].is_equal_approx(before[i]):
			same = false
			break
	check(same, "the road before the place didn't move")
	check(r.points.size() * Route.STEP >= 100.0 + Route.ROAM_AHEAD * 0.9, "road laid out ahead again")
	var s := float(t["s"]) + 20.0
	var later := r.next_turn(s)
	check(later.is_empty() or int(later["j"]) > int(t["j"]), "once there, that turn is taken")


func test_segments() -> void:
	var climb := Route.from_spec(Catalog.find(Catalog.routes(), "summit-climb"))
	var ids: Array = climb.segments.map(func(g: Dictionary) -> String: return g["id"])
	check(ids == ["switchbacks"], "the summit climb has the switchbacks: %s" % [ids])
	var sw: Dictionary = climb.segments[0]
	check(sw["end"] - sw["start"] > 4500.0 and sw["end"] <= climb.length, "over the climb (%.0f m)" % (sw["end"] - sw["start"]))
	var walls := Route.from_spec(Catalog.find(Catalog.routes(), "quarry-walls"))
	ids = walls.segments.map(func(g: Dictionary) -> String: return g["id"])
	check(ids == ["west-wall", "quarry-wall"], "quarry walls: %s" % [ids])
	var laps := Route.from_spec(Catalog.find(Catalog.free_rides(), "free-flat"))
	var sprints := laps.segments.filter(func(g: Dictionary) -> bool: return g["id"] == "valley-sprint")
	check(sprints.size() > 10, "every lap has its sprint (%d)" % sprints.size())
	var r := _ride_route(Catalog.find(Catalog.routes(), "summit-climb"), 250.0)
	check(r.segments_done.size() == 1, "the switchbacks were timed")
	var t: float = r.segments_done[0]["time"]
	var t0 := 0.0
	var t1 := 0.0
	for smp in r.samples:
		if smp[1] <= sw["start"]:
			t0 = smp[0]
		if smp[1] <= sw["end"]:
			t1 = smp[0]
	near(t, t1 - t0, 2.0, "timed from line to line")
	check(r.events.any(func(e: Array) -> bool: return e[0] == "segment_done"), "and told")


func test_power_records() -> void:
	var r := Ride.create(Ride.Kind.FREE, Route.from_spec(Catalog.find(Catalog.free_rides(), "free-flat")), null, 80.0, 200.0)
	r.records_before = {5: 400.0, 60: 150.0}
	for i in 400 * 10:
		r.update(200.0, 90.0, 0.1)
	near(r.power_best[60], 200.0, 0.5, "best minute")
	near(r.power_best[300], 200.0, 0.5, "best 5 minutes")
	check(not r.power_best.has(1200), "no 20 minutes yet")
	var told := r.events.filter(func(e: Array) -> bool: return e[0] == "record")
	check(told.size() == 1 and told[0][1] == 60, "the minute record is told, once: %s" % [told])
	check(r.new_records() == [[60, 200.0, 150.0]], "new records: %s" % [r.new_records()])
	var s := r.summary()
	check(s["powers"]["60"] == 200.0 and not s["powers"].has("1200"), "saved with the ride")
	var h := History.new()
	h.dir = _test_dir("records")
	r.elapsed = maxf(r.elapsed, 61.0)
	h.save(r)
	check(h.records()[60] == 200.0 and h.records()[300] == 200.0, "read back as records")
	Riders._remove_tree(ProjectSettings.globalize_path(h.dir))


func test_segment_and_record_xp() -> void:
	var r := _ride_route(Catalog.find(Catalog.routes(), "summit-climb"), 250.0)
	var t: float = r.segments_done[0]["time"]
	r.segment_kom = {"switchbacks": {"name": "Sam", "time": t + 30.0, "self": false}}
	r.segment_best = {"switchbacks": t + 60.0}
	var names: Array = Levels.for_ride(r, [], {})["parts"].map(func(p: Array) -> String: return p[0])
	check(names.has("King of the Mountain: The Switchbacks") and not names.has("best on The Switchbacks"),
			"taking the fastest time: %s" % [names])
	r.segment_kom = {"switchbacks": {"name": "Me", "time": t + 60.0, "self": true}}
	names = Levels.for_ride(r, [], {})["parts"].map(func(p: Array) -> String: return p[0])
	check(names.has("best on The Switchbacks"), "beating your own: %s" % [names])
	var lap: Dictionary = r.segments_done[0].duplicate()
	lap["time"] = t + 1.0
	r.segments_done.append(lap)
	names = Levels.for_ride(r, [], {})["parts"].map(func(p: Array) -> String: return p[0])
	check(names.count("best on The Switchbacks") == 1, "once, however many laps: %s" % [names])
	r.segment_best = {}
	r.segment_kom = {}
	names = Levels.for_ride(r, [], {})["parts"].map(func(p: Array) -> String: return p[0])
	check(not names.any(func(n: String) -> bool: return "Switchbacks" in n), "nothing for a first time: %s" % [names])
	r.records_before = {5: 1.0}
	names = Levels.for_ride(r, [], {})["parts"].map(func(p: Array) -> String: return p[0])
	check(names.has("new 5 s power record"), "a power record: %s" % [names])


func test_the_land_is_land_everywhere() -> void:
	var isl := Island.main()
	var lo := INF
	for k in range(0, isl.heights.size(), 97):
		lo = minf(lo, isl.heights[k])
	check(lo > -15.0, "no deep holes anywhere (lowest %.1f m)" % lo)
	var edge := isl.height_at(isl.origin.x + 4.0, isl.origin.y + 4.0)
	near(edge, Island.OUTSIDE, 3.0, "the edge meets the land beyond it")
	near(isl.height_at(isl.origin.x - 500.0, 0.0), Island.OUTSIDE, 0.01, "beyond the edge")


# --- workouts ----------------------------------------------------------------

func test_workouts_have_their_stated_length() -> void:
	var expected := {"first-spin": 10, "leg-openers": 15, "easy-endurance": 20,
		"sprint-fun": 20, "recovery-spin": 30, "tempo-30": 30, "pyramid": 33,
		"sweet-spot-40": 40, "vo2-45": 45, "over-unders": 50,
		"long-endurance": 60, "hour-of-power": 60, "cadence-builder": 24, "big-gear": 40}
	for spec in Catalog.workouts():
		var w := Workout.from_spec(spec)
		check(expected.has(w.id), "%s is expected" % w.id)
		near(w.duration / 60.0, expected.get(w.id, 0), 0.01, "%s minutes" % w.id)
		for st in w.steps:
			check(st[0] > 0 and st[1] >= 0.3 and st[2] <= 1.6, "%s step %s sane" % [w.id, st])
			check(st[3] == 0.0 or (st[3] >= 55.0 and st[3] <= 115.0), "%s cadence %s rideable" % [w.id, st[3]])


func test_workout_targets_ramp_and_step() -> void:
	var w := Workout.from_spec({"steps": [[100, 0.5, 0.7], [60, 1.2]]})
	near(w.target_at(0.0), 0.5, 0.001, "ramp start")
	near(w.target_at(50.0), 0.6, 0.001, "ramp middle")
	near(w.target_at(120.0), 1.2, 0.001, "second step")
	near(w.remaining_in_step(120.0), 40.0, 0.001, "time left in step")
	check(w.step_index(99.9) == 0 and w.step_index(100.0) == 1, "step boundaries")


func test_workout_cadence_targets() -> void:
	var w := Workout.from_spec({"steps": [[60, 0.5], [60, 0.8, 0.8, 90], [60, 0.5, 0.7]]})
	check(w.cadence_at(30.0) == 0.0 and w.cadence_at(90.0) == 90.0 and w.cadence_at(150.0) == 0.0,
			"a cadence only where one is set")
	check(w.has_cadence() and not Workout.from_spec({"steps": [[60, 0.5]]}).has_cadence(), "has_cadence")
	check(w.settling(62.0) and not w.settling(66.0), "a new block settles for %d s" % Workout.SETTLE)
	check(Workout.describe(w.steps[0], 200.0, 1.0) == "100 W", "steady: %s" % Workout.describe(w.steps[0], 200.0, 1.0))
	check(Workout.describe(w.steps[1], 200.0, 1.1) == "176 W, 90 rpm", "with rpm: %s" % Workout.describe(w.steps[1], 200.0, 1.1))
	check(Workout.describe(w.steps[2], 200.0, 1.0) == "100 to 140 W", "ramp: %s" % Workout.describe(w.steps[2], 200.0, 1.0))
	var bg := Workout.from_spec(Catalog.find(Catalog.workouts(), "big-gear"))
	check(bg.cadence_at(480.0 + 120.0) == 60.0 and bg.cadence_at(480.0 + 300.0) == 90.0, "big gear: 60 rpm blocks, 90 between")


## Rides a workout for its whole length: power `power_of(target)` and cadence
## `cadence_of(target rpm)` every tenth of a second.
func _ride_workout(id: String, power_of: Callable, cadence_of: Callable, intensity := 1.0) -> Ride:
	var w := Workout.from_spec(Catalog.find(Catalog.workouts(), id))
	var r := Ride.create(Ride.Kind.WORKOUT, Route.from_spec(Catalog.workout_road()), w, 80.0, 200.0)
	r.intensity = intensity
	while not r.finished:
		r.update(power_of.call(r.target_power()), cadence_of.call(w.cadence_at(r.elapsed)), 0.1)
	return r


func test_power_targets_follow_ftp_and_intensity() -> void:
	var w := Workout.from_spec(Catalog.find(Catalog.workouts(), "big-gear"))
	var r := Ride.create(Ride.Kind.WORKOUT, Route.from_spec(Catalog.workout_road()), w, 80.0, 250.0)
	r.elapsed = 480.0 + 100.0
	near(r.target_power(), 250.0 * 0.85, 0.01, "a block: FTP times its share")
	r.intensity = 1.1
	near(r.target_power(), 250.0 * 0.85 * 1.1, 0.01, "and the intensity")
	r.intensity = 1.0
	r.elapsed = 240.0
	near(r.target_power(), 250.0 * (0.45 + 0.25 * 0.5), 0.01, "a ramp, halfway")


func test_a_perfect_rider_is_on_target() -> void:
	var exact := func(target: float) -> float: return target
	var r := _ride_workout("big-gear", exact, func(rpm: float) -> float: return rpm if rpm > 0.0 else 85.0)
	var held := r.on_target()
	check(held.get("power", 0) >= 99 and held.get("cadence", 0) >= 99, "power and cadence on target: %s" % [held])
	var w := r.workout
	near(r.target_time["power"], w.duration - Workout.SETTLE * w.steps.size(), 1.0, "each block judged once it's settled")
	check(r.summary()["on_target"] == held, "saved with the ride")


func test_off_target_is_counted() -> void:
	var weak := func(target: float) -> float: return target * 0.75
	var always_90 := func(_rpm: float) -> float: return 90.0
	var r := _ride_workout("big-gear", weak, always_90)
	var held := r.on_target()
	check(held.get("power", 100) == 0, "25%% under the power: never on it (%s)" % [held])
	# 90 rpm is right between the blocks (90) and wrong in them (60).
	var w := r.workout
	var easy := 0.0
	var all := 0.0
	for st in w.steps:
		if st[3] > 0.0:
			all += st[0] - Workout.SETTLE
			if st[3] == 90.0:
				easy += st[0] - Workout.SETTLE
	near(held.get("cadence", -1), 100.0 * easy / all, 1.0, "cadence right only between the blocks")
	var none := _ride_workout("first-spin", func(t: float) -> float: return t, always_90)
	check(not none.on_target().has("cadence"), "no cadence target, nothing judged")
	var test := Ride.create(Ride.Kind.WORKOUT, Route.from_spec(Catalog.workout_road()), Workout.ftp_test(200.0), 80.0, 200.0)
	for i in 3000:
		test.update(100.0, 90.0, 0.1)
	check(test.on_target().is_empty(), "the FTP test isn't judged")


# --- rides -------------------------------------------------------------------

func _ride_route(spec: Dictionary, power: float) -> Ride:
	var r := Ride.create(Ride.Kind.ROUTE, Route.from_spec(spec), null, 80.0, 200.0)
	var guard := 0
	while not r.finished and guard < 60 * 60 * 30:
		r.update(power, 90.0, 1.0 / 30.0)
		guard += 1
	return r


func test_a_route_ride_finishes_with_sensible_totals() -> void:
	var r := _ride_route(Catalog.find(Catalog.routes(), "city-sprint"), 200.0)
	check(r.finished, "finished")
	near(r.distance(), r.route.length, 0.1, "distance")
	near(r.average_power(), 200.0, 0.5, "average power")
	near(r.elapsed, r.route.length / (34.0 / 3.6), 40.0, "time at 200 W on the flat")
	check(r.samples.size() >= int(r.elapsed), "a sample a second")
	var s := r.summary()
	check(s["kind"] == "route" and s["id"] == "city-sprint" and s["completed"], "summary")


func test_samples_are_exact_even_with_long_frames() -> void:
	# Two rides already cruising at 200 W on the flat, one in 1/60 s frames and
	# one in 2.5 s frames. At a steady speed the physics agree whatever the
	# frame length, so any difference comes from how samples are taken.
	var spec := Catalog.find(Catalog.routes(), "city-sprint")
	var cruise := _steady(200.0, 0.0) / 3.6
	var fine := Ride.create(Ride.Kind.ROUTE, Route.from_spec(spec), null, 80.0, 200.0)
	var coarse := Ride.create(Ride.Kind.ROUTE, Route.from_spec(spec), null, 80.0, 200.0)
	fine.physics.speed = cruise
	coarse.physics.speed = cruise
	for i in 60 * 60:
		fine.update(200.0, 90.0, 1.0 / 60.0)
	for i in 24:
		coarse.update(200.0, 90.0, 2.5)
	var worst := 0.0
	for t in range(1, 60):
		worst = maxf(worst, absf(fine.samples[t][1] - coarse.samples[t][1]))
	check(worst < 1.0, "each second's distance agrees (worst %.2f m)" % worst)


func test_the_clock_stops_when_the_rider_stops() -> void:
	var r := Ride.create(Ride.Kind.FREE, Route.from_spec(Catalog.find(Catalog.free_rides(), "free-flat")), null, 80.0, 200.0)
	for i in 300:
		r.update(150.0, 85.0, 0.1)
	var moving := r.elapsed
	for i in 600:
		r.update(0.0, 0.0, 0.1)
	check(r.paused(), "paused")
	check(r.elapsed - moving < 25.0, "only the coast-down counted (%.1f s)" % (r.elapsed - moving))


func test_free_ride_effort_changes_the_gradient() -> void:
	var r := Ride.create(Ride.Kind.FREE, Route.from_spec(Catalog.find(Catalog.free_rides(), "free-flat")), null, 80.0, 200.0)
	var base := r.bike_grade(1.0)
	r.change_effort(3)
	near(r.bike_grade(1.0) - base, 3.0, 0.001, "three steps up is +3%")
	r.change_effort(100)
	near(r.effort, Ride.EFFORT_MAX, 0.0001, "effort is capped")
	near(r.bike_grade(0.5), (r.route.grade_ahead(0.0, 15.0) + r.effort) * 50.0, 0.001,
		"hill feel scales what the bike gets")


func test_workout_ride_targets_follow_ftp_and_intensity() -> void:
	var w := Workout.from_spec(Catalog.find(Catalog.workouts(), "first-spin"))
	var r := Ride.create(Ride.Kind.WORKOUT, Route.from_spec(Catalog.workout_road()), w, 80.0, 200.0)
	near(r.target_power(), 80.0, 0.5, "40% of 200 W at the start")
	r.change_intensity(2)
	near(r.target_power(), 88.0, 0.5, "+10% intensity")
	var guard := 0
	while not r.finished and guard < 60 * 30 * 20:
		r.update(r.target_power(), 90.0, 1.0 / 30.0)
		guard += 1
	check(r.finished, "workout ends")
	near(r.elapsed, 600.0, 0.1, "after ten minutes")


func test_ghost_is_interpolated() -> void:
	var r := Ride.create(Ride.Kind.ROUTE, Route.from_spec(Catalog.routes()[0]), null, 80.0, 200.0)
	check(r.ghost_distance() < 0.0, "no ghost yet")
	r.ghost = PackedFloat32Array([0.0, 10.0, 30.0])
	r.elapsed = 1.5
	near(r.ghost_distance(), 20.0, 0.001, "halfway between seconds")
	r.elapsed = 10.0
	near(r.ghost_distance(), 30.0, 0.001, "stays at the ghost's finish")


# --- saved data --------------------------------------------------------------

func test_settings_round_trip() -> void:
	var path := "user://test_settings.cfg"
	var a := Settings.new()
	a.music = 0.3
	a.quality = 2
	a.muted = true
	a.pedal_start = false
	a.last_rider = "3"
	a.save_file(path)
	var b := Settings.new()
	b.load_file(path)
	check(b.music == 0.3 and b.quality == 2, "values")
	check(b.muted and not b.pedal_start, "mute and pedal to start")
	check(b.last_rider == "3", "last rider")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_dir(what: String) -> String:
	return "user://test_%s_%d" % [what, Time.get_ticks_usec()]


func test_rider_round_trip() -> void:
	var a := Rider.new()
	a.id = "4"
	a.dir = _test_dir("rider")
	a.name = "Ana"
	a.weight = 61.5
	a.ftp = 185.0
	a.hill_feel = 0.75
	a.color = 3
	a.camera = 2
	a.last_choice = "route:neon-flats"
	a.save_file()
	var b := Rider.new()
	b.dir = a.dir
	check(b.load_file(), "loads")
	check(b.name == "Ana" and b.weight == 61.5 and b.ftp == 185.0 and b.hill_feel == 0.75, "values")
	check(b.color == 3 and b.rgb() == Rider.COLORS[3][1] and b.camera == 2, "colour and camera")
	check(b.last_choice == "route:neon-flats", "last choice")
	b.apply({"weight": 500, "ftp": -3, "color": 99, "camera": 7})
	check(b.weight == 160.0 and b.ftp == 50.0 and b.color == Rider.COLORS.size() - 1 and b.camera == 2,
			"values stay within limits")
	Riders._remove_tree(ProjectSettings.globalize_path(a.dir))


func test_riders_add_rename_remove() -> void:
	var rs := Riders.new()
	rs.root = _test_dir("riders")
	rs.load_all("user://no-such-settings.cfg", "user://no-such-rides")
	check(rs.list.size() == 1 and rs.list[0].name == "Rider 1" and rs.list[0].id == "1",
			"a new bike starts with Rider 1")
	var ana := rs.add("  Ana  ")
	var ben := rs.add("Big   Ben")
	check(ana.name == "Ana" and ben.name == "Big Ben", "names are tidied")
	check(ana.id == "2" and ben.id == "3", "numbered in order")
	check(Riders.clean_name("x".repeat(40)).length() == Riders.NAME_MAX, "names are cut to length")
	check(rs.name_problem("   ") != "", "an empty name is refused")
	check(rs.name_problem("ANA") != "", "a name already here is refused, whatever the case")
	check(rs.name_problem("ana", ana) == "", "a rider may keep their own name")
	check(rs.name_problem("Kim") == "", "a new name is fine")
	rs.rename(rs.list[0], "Kim")
	var h := History.new()
	h.dir = ben.rides_dir()
	h.save(_ride_route(Catalog.find(Catalog.routes(), "city-sprint"), 200.0))
	check(h.rides().size() == 1, "each rider has their own rides")
	var again := Riders.new()
	again.root = rs.root
	again.load_all("user://no-such-settings.cfg", "user://no-such-rides")
	var names := again.list.map(func(r: Rider) -> String: return r.name)
	check(names == ["Kim", "Ana", "Big Ben"], "read back in order: %s" % [names])
	check(rs.remove(ben), "a rider can be deleted")
	check(not DirAccess.dir_exists_absolute(ben.dir), "with all their rides")
	check(rs.remove(ana) and not rs.remove(rs.list[0]), "but never the last one")
	var dan := rs.add("Dan")
	var dans := History.new()
	dans.dir = dan.rides_dir()
	check(dan.id == "2" and dans.rides().is_empty(), "a freed number starts afresh: %s" % dan.id)
	Riders._remove_tree(ProjectSettings.globalize_path(rs.root))


func test_old_data_becomes_rider_1() -> void:
	var base := _test_dir("old")
	DirAccess.make_dir_recursive_absolute(base)
	var old_cfg := base.path_join("settings.cfg")
	var cf := ConfigFile.new()
	cf.set_value("rider", "weight", 70.0)
	cf.set_value("rider", "ftp", 210.0)
	cf.set_value("rider", "color", 2)
	cf.set_value("screen", "camera", 1)
	cf.set_value("menu", "last_choice", "workout:pyramid")
	cf.set_value("sound", "music", 0.2)
	cf.save(old_cfg)
	var old := History.new()
	old.dir = base.path_join("rides")
	old.save(_ride_route(Catalog.find(Catalog.routes(), "city-sprint"), 200.0))
	var rs := Riders.new()
	rs.root = base.path_join("riders")
	rs.load_all(old_cfg, old.dir)
	var r := rs.list[0]
	check(rs.list.size() == 1 and r.name == "Rider 1", "one rider, Rider 1")
	check(r.weight == 70.0 and r.ftp == 210.0 and r.color == 2 and r.camera == 1, "their settings came along")
	check(r.last_choice == "workout:pyramid", "and their last choice")
	var h := History.new()
	h.dir = r.rides_dir()
	check(h.rides().size() == 1 and not h.best("city-sprint").is_empty(), "and their rides and bests")
	check(not DirAccess.dir_exists_absolute(old.dir), "moved, not copied")
	var s := Settings.new()
	s.load_file(old_cfg)
	check(s.music == 0.2, "the shared settings stay where they were")
	rs.load_all(old_cfg, old.dir)
	check(rs.list.size() == 1, "and it only happens once")
	Riders._remove_tree(ProjectSettings.globalize_path(base))


func test_history_keeps_rides_bests_and_ghosts() -> void:
	var h := History.new()
	h.dir = "user://test_rides_%d" % Time.get_ticks_usec()
	var spec := Catalog.find(Catalog.routes(), "city-sprint")
	var slow := _ride_route(spec, 150.0)
	var fast := _ride_route(spec, 260.0)
	var short := Ride.create(Ride.Kind.FREE, Route.from_spec(Catalog.find(Catalog.free_rides(), "city-laps")), null, 80.0, 200.0)
	short.update(200.0, 90.0, 10.0)
	h.save(slow)
	fast.started_at = "2026-09-29 07:00:00"
	var saved := h.save(fast)
	h.save(short)
	check(h.rides().size() == 2, "rides under a minute aren't kept")
	check(h.best("city-sprint").get("file") == saved.get("file"), "the fast ride is the best")
	var g := h.ghost("city-sprint")
	check(g.size() == fast.samples.size(), "ghost has a point a second")
	for f in DirAccess.get_files_at(h.dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(h.dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(h.dir))


# --- XP and levels ---------------------------------------------------------

## `seconds` of steady riding at `watts`, as a ride's samples.
func _samples(seconds: int, watts: float) -> Array:
	var out := []
	for t in seconds:
		out.append([float(t), t * 8.0, watts, 88.0])
	return out


func test_xp_is_fair_across_riders() -> void:
	check(Levels.effort_xp(_samples(3600, 200.0), 200.0) == 1000, "an hour at FTP is 1000 XP")
	var beginner := Levels.effort_xp(_samples(1800, 120.0), 150.0)
	var strong := Levels.effort_xp(_samples(1800, 240.0), 300.0)
	check(beginner == strong and beginner == 320, "the same effort earns the same: %d, %d" % [beginner, strong])
	check(Levels.effort_xp(_samples(600, 2000.0), 200.0) == Levels.effort_xp(_samples(600, 300.0), 200.0),
			"a sprint counts only up to 1.5 times FTP")
	check(Levels.effort_xp(_samples(60, -5.0), 200.0) == 0, "no power, no XP")
	check(Levels.effort_words(_samples(60, 100.0), 200.0) == "easy for you", "easy")
	check(Levels.effort_words(_samples(60, 190.0), 200.0) == "very hard for you", "very hard")


func test_ride_xp_bonuses() -> void:
	var spec := Catalog.find(Catalog.routes(), "city-sprint")
	var first := _ride_route(spec, 200.0)
	first.started_at = "2026-09-20 18:00:00"
	var xp := Levels.for_ride(first, [], {})
	var names: Array = xp["parts"].map(func(p: Array) -> String: return p[0])
	check(names.has("route finished") and names.has("first time on this route"), "first finish: %s" % [names])
	var sum := 0
	for p in xp["parts"]:
		sum += p[1]
	check(xp["total"] == sum and sum > Levels.FINISHED + Levels.FIRST_TIME, "the total adds up")
	var again := _ride_route(spec, 260.0)
	again.started_at = "2026-09-21 18:00:00"
	var before := [{"date": first.started_at, "kind": "route", "id": "city-sprint", "time": first.elapsed}]
	names = Levels.for_ride(again, before, before[0])["parts"].map(func(p: Array) -> String: return p[0])
	check(names.has("new best time") and not names.has("first time on this route"), "a new best: %s" % [names])
	check(names.has("2 days in a row"), "two days running: %s" % [names])
	var slow := _ride_route(spec, 150.0)
	slow.started_at = "2026-09-25 18:00:00"
	names = Levels.for_ride(slow, before, before[0])["parts"].map(func(p: Array) -> String: return p[0])
	check(not names.has("new best time") and names.size() == 2, "slower and after a gap: %s" % [names])


func test_streaks() -> void:
	var rides := [{"date": "2026-09-26 07:00:00"}, {"date": "2026-09-27 19:00:00"},
		{"date": "2026-09-28 06:30:00"}, {"date": "2026-09-28 20:00:00"}]
	check(Levels.streak(rides, "2026-09-29 08:00:00") == 4, "four days running")
	check(Levels.streak(rides, "2026-09-28 21:00:00") == 0, "the day's bonus came with its first ride")
	check(Levels.streak(rides, "2026-09-30 08:00:00") == 1, "a missed day starts again")
	check(Levels.streak([], "2026-09-30 08:00:00") == 1, "a first ride")
	var long := []
	for d in 20:
		long.append({"date": Time.get_date_string_from_unix_time(
				Time.get_unix_time_from_datetime_string("2026-09-01") + 86400 * d) + " 07:00:00"})
	var r := _ride_route(Catalog.find(Catalog.routes(), "city-sprint"), 200.0)
	r.started_at = "2026-09-21 07:00:00"
	var parts: Array = Levels.for_ride(r, long, {"time": 1.0})["parts"]
	check(parts.back() == ["21 days in a row", Levels.STREAK_DAY * Levels.STREAK_MAX], "the bonus stops growing")


func test_levels() -> void:
	check(Levels.level_for(0)["level"] == 1 and Levels.level_for(0)["title"] == "Rookie", "everyone starts at 1")
	check(Levels.level_for(Levels.FIRST_LEVEL - 1)["level"] == 1, "just short of 2")
	var two := Levels.level_for(Levels.FIRST_LEVEL)
	check(two["level"] == 2 and two["into"] == 0 and two["needed"] == Levels.cost(2), "level 2")
	check(Levels.cost(10) > Levels.cost(9), "each level costs more")
	var at := 0
	for l in range(1, 8):
		at += Levels.cost(l)
	check(Levels.level_for(at)["level"] == 8 and Levels.level_for(at)["title"] == "Road Captain", "level 8")
	check(Levels.title(45) == "Lightspeed", "the last title stays")
	var rides := [{"xp": 610}, {"time": 1800.0, "avg_power": 150.0, "kind": "route", "completed": true}]
	check(Levels.total(rides, 150.0) == 610 + 500 + Levels.FINISHED, "old rides are estimated")


func test_ftp_test_ramps_from_the_riders_ftp() -> void:
	var w := Workout.ftp_test(150.0)
	check(w.id == Workout.TEST_ID and Workout.test_start(150.0) == 80.0, "starts at half the FTP")
	near(w.target_at(100.0) * 150.0, 80.0, 0.01, "warm-up")
	near(w.target_at(Workout.TEST_WARMUP + 30.0) * 150.0, 100.0, 0.01, "first minute of the ramp")
	near(w.target_at(Workout.TEST_WARMUP + 5 * 60.0 + 30.0) * 150.0, 200.0, 0.01, "sixth minute")
	check(Workout.test_start(40.0) == 60.0 and Workout.test_start(500.0) == 150.0, "a sensible start")
	check(Workout.test_minutes(150.0) == 11, "about 11 minutes at 150 W: %d" % Workout.test_minutes(150.0))


func test_ftp_test_result() -> void:
	var samples := []
	for t in int(Workout.TEST_WARMUP):
		samples.append([float(t), 0.0, 80.0, 85.0])
	for minute in 9:  # 100 W to 260 W, then the legs go
		for t in 60:
			samples.append([float(samples.size()), 0.0, 100.0 + 20.0 * minute, 85.0])
	for t in 15:
		samples.append([float(samples.size()), 0.0, 120.0, 50.0])
	var r := Workout.test_result(samples)
	check(r.get("best_minute") == 260.0 and r.get("ftp") == 195.0, "FTP from the best minute: %s" % [r])
	check(Workout.test_result(samples.slice(0, 330)).is_empty(), "no answer from the warm-up alone")


func test_beating_another_riders_best() -> void:
	var spec := Catalog.find(Catalog.routes(), "city-sprint")
	var fast := _ride_route(spec, 260.0)
	fast.rival = {"name": "Sam", "time": fast.elapsed + 30.0, "self": false}
	var names: Array = Levels.for_ride(fast, [], {"time": 1.0})["parts"].map(func(p: Array) -> String: return p[0])
	check(names.has("beat Sam's best"), "beating Sam's best: %s" % [names])
	fast.rival["time"] = fast.elapsed - 30.0
	names = Levels.for_ride(fast, [], {"time": 1.0})["parts"].map(func(p: Array) -> String: return p[0])
	check(not names.has("beat Sam's best"), "not beating it")
	fast.rival = {"name": "Me", "time": fast.elapsed + 30.0, "self": true}
	names = Levels.for_ride(fast, [], {"time": 1.0})["parts"].map(func(p: Array) -> String: return p[0])
	check(not names.has("beat Me's best"), "your own best is the new-best bonus, not this one")


func test_history_keeps_xp() -> void:
	var h := History.new()
	h.dir = _test_dir("xp")
	var r := _ride_route(Catalog.find(Catalog.routes(), "city-sprint"), 200.0)
	var xp := Levels.for_ride(r, [], {})
	var saved := h.save(r, xp, {"rival": {"name": "Sam", "time": 400.0}})
	check(saved["xp"] == xp["total"] and h.rides()[0]["xp"] == xp["total"], "saved with the ride")
	check(h.rides()[0]["rival"]["name"] == "Sam", "and anything extra")
	check(h.rides()[0]["xp_parts"].size() == xp["parts"].size(), "with its parts")
	check(Levels.total(h.rides(), 200.0) == xp["total"], "and counted")
	Riders._remove_tree(ProjectSettings.globalize_path(h.dir))


# --- the link to the bike ----------------------------------------------------

func test_bike_link_reads_the_bridge_messages() -> void:
	var link := BikeLink.new()
	link.handle({"type": "status", "state": "connected", "bike": "DOMYOS", "erg": true, "controlled": false})
	check(not link.controlled, "not controlled yet")
	link.handle({"type": "status", "state": "connected", "bike": "DOMYOS", "erg": true})
	check(link.controlled, "an older bridge that doesn't say counts as controlled")
	link.handle({"type": "ride", "power": 212, "cadence": 88.5, "speed": null})
	check(link.bike_connected and link.bike_name == "DOMYOS" and link.erg, "status")
	check(link.power == 212.0 and link.cadence == 88.5, "reading")
	link.handle({"type": "status", "state": "searching", "bike": null})
	check(not link.bike_connected and link.bike_name == "", "searching")
	link.handle({"type": "ride", "power": null, "cadence": null})
	check(link.power == 0.0, "missing power is zero")
	link.handle({"type": "status", "state": "no_adapter", "bike": null})
	check(link.bridge_state == "no_adapter" and not link.bike_connected, "no adapter")
	link.free()
