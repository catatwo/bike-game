class_name Workout
extends RefCounted
## A structured workout: a list of steps, each a duration and a target power
## as a fraction of FTP, steady or ramping, and maybe a cadence to hold.

const TEST_ID := "ftp-test"
const TEST_WARMUP := 300.0  # s, easy, before the ramp
const TEST_STEP := 20.0  # W more each minute of the ramp
const TEST_GIVE_UP := 0.85  # below this share of the target...
const TEST_GIVE_UP_AFTER := 10.0  # ...for this long (s), the test is over
const TEST_FTP_SHARE := 0.75  # FTP from the best minute, the usual ramp-test rule

var id := ""
var title := ""
var level := ""
var about := ""
const CADENCE_BAND := 5.0  # rpm either side of a cadence target counts as on it
const POWER_BAND := 0.10  # this share either side of the power target counts as on it
const SETTLE := 5.0  # s at the start of each block before it's judged

var steps: Array = []  # [seconds, from, to, rpm]; rpm 0 for no cadence target
var duration := 0.0
var _starts: Array[float] = []


static func from_spec(spec: Dictionary) -> Workout:
	var w := Workout.new()
	w.id = spec.get("id", "")
	w.title = spec.get("name", "Workout")
	w.level = spec.get("level", "")
	w.about = spec.get("about", "")
	for st in spec.get("steps", []):
		var from := float(st[1])
		var to := float(st[2]) if st.size() > 2 else from
		var rpm := float(st[3]) if st.size() > 3 else 0.0
		w._starts.append(w.duration)
		w.steps.append([float(st[0]), from, to, rpm])
		w.duration += float(st[0])
	return w


func step_index(t: float) -> int:
	for i in range(steps.size() - 1, -1, -1):
		if t >= _starts[i]:
			return i
	return 0


func step_start(i: int) -> float:
	return _starts[i]


## Target at time t, as a fraction of FTP.
func target_at(t: float) -> float:
	var i := step_index(t)
	var st: Array = steps[i]
	var k := clampf((t - _starts[i]) / st[0], 0.0, 1.0)
	return lerpf(st[1], st[2], k)


## The cadence to hold at time t, rpm, or 0 for none.
func cadence_at(t: float) -> float:
	return steps[step_index(t)][3]


## True while a block is new, and the bike and the rider are still settling.
func settling(t: float) -> bool:
	return t - _starts[step_index(t)] < SETTLE


func has_cadence() -> bool:
	return steps.any(func(st: Array) -> bool: return st[3] > 0.0)


## "196 W", "150 to 210 W", with ", 90 rpm" when there's a cadence target.
static func describe(step: Array, ftp: float, intensity: float) -> String:
	var from := roundi(ftp * step[1] * intensity)
	var to := roundi(ftp * step[2] * intensity)
	var text := "%d W" % from if from == to else "%d to %d W" % [from, to]
	if step[3] > 0.0:
		text += ", %d rpm" % roundi(step[3])
	return text


func remaining_in_step(t: float) -> float:
	var i := step_index(t)
	return _starts[i] + steps[i][0] - t


## Average target over the whole workout, for the menus.
func average_target() -> float:
	var total := 0.0
	for st in steps:
		total += st[0] * (st[1] + st[2]) * 0.5
	return total / maxf(duration, 1.0)


## The FTP test: five easy minutes, then TEST_STEP watts more every minute
## until the rider can't keep up. The targets are fractions of the FTP it's
## built for, like any workout; `ramp_steps` far exceeds anyone by default.
static func ftp_test(ftp: float, ramp_steps := 80) -> Workout:
	var start := test_start(ftp)
	var steps := [[TEST_WARMUP, start / ftp]]
	for i in ramp_steps:
		steps.append([60.0, (start + TEST_STEP * (i + 1)) / ftp])
	return from_spec({"id": TEST_ID, "name": "FTP test", "level": "Test", "steps": steps,
		"about": "Five easy minutes, then the bike asks for %d W more every minute. Keep going until you can't: the test ends by itself, and your FTP comes from your best minute." % TEST_STEP})


## Where the test starts: half the FTP it's checking, within 60 to 150 W.
static func test_start(ftp: float) -> float:
	return clampf(snappedf(ftp * 0.5, 10.0), 60.0, 150.0)


## About how long the test will take someone whose FTP really is `ftp`.
static func test_minutes(ftp: float) -> int:
	var ramp := maxf(ftp / TEST_FTP_SHARE - test_start(ftp), 0.0) / TEST_STEP
	return roundi(TEST_WARMUP / 60.0 + ramp)


## The test's answer from a ride's samples: {"best_minute": W, "ftp": W}, or
## {} when it didn't get a full minute into the ramp.
static func test_result(samples: Array) -> Dictionary:
	if samples.size() < TEST_WARMUP + 60.0:
		return {}
	var best := 0.0
	var sum := 0.0
	for i in samples.size():
		sum += float(samples[i][2])
		if i >= 60:
			sum -= float(samples[i - 60][2])
		if i >= 59:
			best = maxf(best, sum / 60.0)
	return {"best_minute": roundf(best), "ftp": roundf(best * TEST_FTP_SHARE)}


## Colour for a target, by training zone (as a fraction of FTP).
static func zone_color(pct: float) -> Color:
	if pct < 0.56:
		return Color("7f8c9a")  # recovery
	if pct < 0.76:
		return Color("2f9bff")  # endurance
	if pct < 0.91:
		return Color("35d07f")  # tempo
	if pct < 1.06:
		return Color("ffd23f")  # threshold
	if pct < 1.21:
		return Color("ff8a2b")  # VO2 max
	return Color("ff3b5c")  # anaerobic
