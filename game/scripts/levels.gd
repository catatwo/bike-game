class_name Levels
extends RefCounted
## Experience (XP) and levels. XP comes from how hard a ride was for the
## person riding it, measured against their own FTP, so a beginner and a
## strong rider level up at the same pace for the same effort. Bonuses come
## on top for finishing a route or workout, a first time on a route, a new
## best, and riding on days in a row. Each level takes more XP than the last.

const PER_HOUR_AT_FTP := 1000.0  # an hour ridden at your FTP
const MAX_INTENSITY := 1.5  # sprints count, up to 1.5 times FTP
const FINISHED := 100
const FIRST_TIME := 100
const NEW_BEST := 150
const BEAT_RIVAL := 100  # beating another rider's best, racing their ghost
const SEGMENT_BEST := 50  # beating your own best on a segment
const SEGMENT_KOM := 100  # taking a segment's fastest time from another rider
const RECORD := 50  # each power record beaten
const STREAK_DAY := 50  # for each day in a row after the first
const STREAK_MAX := 6  # so at most +300
const FIRST_LEVEL := 500  # XP from level 1 to level 2
const LEVEL_STEP := 250  # each level after that costs this much more
const TITLES := [[1, "Rookie"], [3, "Spinner"], [5, "Pacer"], [8, "Road Captain"],
	[12, "Climber"], [16, "Breakaway"], [20, "Neon Racer"], [25, "Grid Master"],
	[30, "Neon Legend"], [40, "Lightspeed"]]


## XP for the effort alone: every second counts (power / FTP) squared.
static func effort_xp(samples: Array, ftp: float) -> int:
	var sum := 0.0
	for s in samples:
		var i := minf(maxf(float(s[2]), 0.0) / ftp, MAX_INTENSITY)
		sum += i * i
	return roundi(sum * PER_HOUR_AT_FTP / 3600.0)


## How hard a ride was for its rider, in words.
static func effort_words(samples: Array, ftp: float) -> String:
	if samples.is_empty():
		return "easy for you"
	var sum := 0.0
	for s in samples:
		var i := minf(maxf(float(s[2]), 0.0) / ftp, MAX_INTENSITY)
		sum += i * i
	var level := sqrt(sum / samples.size())
	if level < 0.65:
		return "easy for you"
	if level < 0.8:
		return "steady for you"
	if level < 0.95:
		return "hard for you"
	return "very hard for you"


## A saved ride's XP: {"total": n, "parts": [[what, xp], ...]}. `before` is
## the rider's rides saved before this one; `best_before`, their best time on
## this route before it, or {}.
static func for_ride(ride: Ride, before: Array, best_before: Dictionary) -> Dictionary:
	var parts := []
	parts.append(["%d min riding, %s" % [maxi(1, roundi(ride.elapsed / 60.0)),
			effort_words(ride.samples, ride.ftp)], effort_xp(ride.samples, ride.ftp)])
	if ride.finished and ride.kind == Ride.Kind.ROUTE:
		parts.append(["route finished", FINISHED])
		if best_before.is_empty():
			parts.append(["first time on this route", FIRST_TIME])
		elif ride.elapsed < float(best_before.get("time", INF)):
			parts.append(["new best time", NEW_BEST])
		if not ride.rival.is_empty() and not ride.rival.get("self", false) \
				and ride.elapsed < float(ride.rival.get("time", 0.0)):
			parts.append(["beat %s's best" % ride.rival["name"], BEAT_RIVAL])
	elif ride.finished and ride.kind == Ride.Kind.WORKOUT:
		parts.append(["FTP test done" if ride.workout.id == Workout.TEST_ID else "workout done", FINISHED])
	# Each segment once, its fastest time this ride (laps can repeat one).
	var fastest := {}
	for seg in ride.segments_done:
		if not fastest.has(seg["id"]) or seg["time"] < fastest[seg["id"]]["time"]:
			fastest[seg["id"]] = seg
	for seg in fastest.values():
		var id: String = seg["id"]
		var t: float = seg["time"]
		var kom: Dictionary = ride.segment_kom.get(id, {})
		if not kom.is_empty() and not kom.get("self", false) and t < float(kom["time"]):
			parts.append(["King of the Mountain: %s" % seg["name"], SEGMENT_KOM])
		elif ride.segment_best.has(id) and t < float(ride.segment_best[id]):
			parts.append(["best on %s" % seg["name"], SEGMENT_BEST])
	for rec in ride.new_records():
		parts.append(["new %s power record" % Ride.SPAN_NAMES[rec[0]], RECORD])
	var days := streak(before, ride.started_at)
	if days >= 2:
		parts.append(["%d days in a row" % days, STREAK_DAY * mini(days - 1, STREAK_MAX)])
	var total := 0
	for p in parts:
		total += p[1]
	return {"total": total, "parts": parts}


## Days in a row with a ride, today's included, or 0 when there was already a
## ride today (the bonus came with that one).
static func streak(before: Array, date: String) -> int:
	var today := date.substr(0, 10)
	var days := {}
	for s in before:
		days[str(s.get("date", "")).substr(0, 10)] = true
	if days.has(today):
		return 0
	var t := Time.get_unix_time_from_datetime_string(today)
	var n := 1
	while days.has(Time.get_date_string_from_unix_time(t - 86400 * n)):
		n += 1
	return n


## All the XP in a rider's saved rides. Rides saved before there was XP are
## estimated from their average power, against today's FTP.
static func total(rides: Array, ftp: float) -> int:
	var t := 0
	for s in rides:
		t += int(s["xp"]) if s.has("xp") else estimate(s, ftp)
	return t


static func estimate(s: Dictionary, ftp: float) -> int:
	var i := minf(float(s.get("avg_power", 0.0)) / ftp, MAX_INTENSITY)
	var xp := roundi(i * i * float(s.get("time", 0.0)) * PER_HOUR_AT_FTP / 3600.0)
	if s.get("completed", false) and s.get("kind") != "free":
		xp += FINISHED
	return xp


## XP it takes to go from `level` to the next one.
static func cost(level: int) -> int:
	return FIRST_LEVEL + LEVEL_STEP * (level - 1)


## Where a total of XP puts you: {"level", "into" (XP into this level),
## "needed" (for the next), "title"}.
static func level_for(xp: int) -> Dictionary:
	var level := 1
	var left := maxi(xp, 0)
	while left >= cost(level):
		left -= cost(level)
		level += 1
	return {"level": level, "into": left, "needed": cost(level), "title": title(level)}


static func title(level: int) -> String:
	var t: String = TITLES[0][1]
	for pair in TITLES:
		if level >= pair[0]:
			t = pair[1]
	return t
