class_name Catalog
extends RefCounted
## Every route, free ride, workout and colour theme in the game. Routes and
## free rides are ways round the island (Island): see Route for their specs.
## Their ids are new since the island (2026-09-29), so best times and ghosts
## from the roads before it are never raced on these.
##
## Workout steps: [seconds, fraction of FTP] or [seconds, from, to] for a ramp,
## and [seconds, from, to, rpm] to hold a cadence too.


static func routes() -> Array:
	return [
		{"id": "city-sprint", "name": "City Sprint", "level": "Beginner",
			"about": "One lap of the city's neon streets, dead flat. A warm-up, or flat out.",
			"path": ["city-loop"]},
		{"id": "gate-run", "name": "Gate Run", "level": "Beginner",
			"about": "A lap of the city, then out west to the gate. Barely a bump.",
			"path": ["city-loop", "gate-road"]},
		{"id": "valley-loop", "name": "Valley Loop", "level": "Beginner",
			"about": "Once round the valley, on the flattest road on the island.",
			"path": ["west-rim", "east-rim"]},
		{"id": "hill-rollers", "name": "Hill Rollers", "level": "Intermediate",
			"about": "Up to the hilltop, over the rolling ridge to East Point, and back to the city.",
			"path": ["hill-road", "ridge", "east-road", "-south-road"]},
		{"id": "grand-tour", "name": "Grand Tour", "level": "Intermediate",
			"about": "The long way: round the valley, up to the hilltop, along the ridge to East Point, and home.",
			"path": ["valley-road", "-east-rim", "-west-rim", "-valley-hill", "ridge", "east-road",
				"-south-road"]},
		{"id": "summit-climb", "name": "Summit Climb", "level": "Intermediate",
			"about": "Four easy kilometres to the mountain, then five up the switchbacks at about 5.5%.",
			"path": ["south-road", "summit-road"]},
		{"id": "quarry-walls", "name": "Quarry Walls", "level": "Advanced",
			"about": "Out west past the gate, down to the quarry, over its two walls of over 7% to the mountain, and on to East Point.",
			"path": ["gate-road", "west-road", "quarry-road", "-east-road"]},
		{"id": "summit-of-light", "name": "Summit of Light", "level": "Advanced",
			"about": "The switchbacks to the summit, then the long way down to East Point.",
			"path": ["south-road", "summit-road", "summit-east"]},
	]


static func free_rides() -> Array:
	return [
		{"id": "city-laps", "name": "City laps", "level": "Beginner", "endless": true,
			"loop": ["city-loop"],
			"about": "Round and round the city's neon streets, dead flat."},
		{"id": "free-flat", "name": "Valley laps", "level": "Beginner", "endless": true,
			"loop": ["west-rim", "east-rim"],
			"about": "Round and round the valley, the flattest long road on the island."},
		{"id": "easy-roam", "name": "Easy roaming", "level": "Beginner", "endless": true,
			"roam": 21, "from": "city", "max_grade": 0.04,
			"about": "Round the island on the gentle roads only, nothing steeper than 4%, taking a road at random at every junction."},
		{"id": "free-rolling", "name": "Roam the island", "level": "Intermediate", "endless": true,
			"roam": 77, "from": "city", "avoid": ["summit-road", "summit-east"],
			"about": "Everywhere but the mountain, the ridge and the quarry walls included, taking a road at random at every junction."},
		{"id": "hill-laps", "name": "Hill laps", "level": "Intermediate", "endless": true,
			"loop": ["hill-road", "ridge", "east-road", "-south-road"],
			"about": "Up to the hilltop, over the rolling ridge to East Point, back to the city, and round again."},
		{"id": "roam-all", "name": "Roam everywhere", "level": "Advanced", "endless": true,
			"roam": 99, "from": "city",
			"about": "The whole island, the mountain too, taking a road at random at every junction."},
		{"id": "mountain-laps", "name": "Mountain laps", "level": "Advanced", "endless": true,
			"loop": ["summit-road", "summit-east", "-ridge", "-hill-road", "south-road"],
			"about": "Up the switchbacks to the summit, down the long descent to East Point, back over the ridge and through the city, and up again."},
	]


## The road workouts are ridden on; the bike holds the target wattage, so its
## hills only change the scenery and the speed.
static func workout_road() -> Dictionary:
	return {"id": "workout-road", "name": "Valley laps", "endless": true,
		"loop": ["west-rim", "east-rim"]}


static func _repeat(times: int, block: Array) -> Array:
	var out := []
	for i in times:
		out.append_array(block)
	return out


static func workouts() -> Array:
	return [
		{"id": "first-spin", "name": "First Spin", "level": "Beginner",
			"about": "Ten easy minutes to get to know the bike.",
			"steps": [[180, 0.40, 0.60], [300, 0.60], [120, 0.60, 0.40]]},
		{"id": "leg-openers", "name": "Leg Openers", "level": "Beginner",
			"about": "Five short 30-second lifts, spinning fast, to wake the legs up.",
			"steps": [[240, 0.40, 0.65]] + _repeat(5, [[30, 1.10, 1.10, 100], [90, 0.55]])
				+ [[60, 0.50]]},
		{"id": "easy-endurance", "name": "Easy Endurance", "level": "Beginner",
			"about": "Twenty minutes, mostly at a steady, chatty pace.",
			"steps": [[300, 0.45, 0.65], [720, 0.65], [180, 0.60, 0.45]]},
		{"id": "cadence-builder", "name": "Cadence Builder", "level": "Beginner",
			"about": "The same easy effort all the way, with your legs spinning faster and faster: 80, 90, 100, then 110 rpm.",
			"steps": [[240, 0.45, 0.60, 85]] + _repeat(3, [[120, 0.60, 0.60, 80], [60, 0.60, 0.60, 90],
				[60, 0.60, 0.60, 100], [30, 0.60, 0.60, 110], [90, 0.55, 0.55, 85]]) + [[120, 0.55, 0.45]]},
		{"id": "big-gear", "name": "Big Gear", "level": "Intermediate",
			"about": "Strength work: four 4-minute blocks just under your limit at a slow, heavy 60 rpm, spinning easy in between.",
			"steps": [[480, 0.45, 0.70, 90]] + _repeat(4, [[240, 0.85, 0.85, 60], [180, 0.55, 0.55, 90]])
				+ [[240, 0.55, 0.40]]},
		{"id": "sprint-fun", "name": "Sprint Fun", "level": "Intermediate",
			"about": "Six all-out 15-second sprints at 110 rpm with long recoveries.",
			"steps": [[420, 0.45, 0.70]] + _repeat(6, [[15, 1.50, 1.50, 110], [105, 0.50]])
				+ [[60, 0.45]]},
		{"id": "recovery-spin", "name": "Recovery Spin", "level": "Beginner",
			"about": "Thirty very easy minutes. Just turn the legs.",
			"steps": [[300, 0.40, 0.52], [1320, 0.52], [180, 0.50, 0.40]]},
		{"id": "tempo-30", "name": "Tempo 30", "level": "Intermediate",
			"about": "Two eight-minute blocks at a strong but steady pace.",
			"steps": [[360, 0.45, 0.70], [480, 0.80], [240, 0.55], [480, 0.82],
				[240, 0.55, 0.40]]},
		{"id": "pyramid", "name": "Pyramid", "level": "Intermediate",
			"about": "One to four minutes and back down, harder in the middle.",
			"steps": [[360, 0.45, 0.70], [60, 0.90], [60, 0.55], [120, 1.00],
				[60, 0.55], [180, 1.05], [60, 0.55], [240, 1.10], [60, 0.55],
				[180, 1.05], [60, 0.55], [120, 1.00], [60, 0.55], [60, 0.90],
				[300, 0.55, 0.40]]},
		{"id": "sweet-spot-40", "name": "Sweet Spot 40", "level": "Intermediate",
			"about": "Three eight-minute blocks just under your limit.",
			"steps": [[420, 0.45, 0.72]] + _repeat(2, [[480, 0.90], [180, 0.55]])
				+ [[480, 0.90], [180, 0.55, 0.40]]},
		{"id": "vo2-45", "name": "VO2 Max 45", "level": "Advanced",
			"about": "Five hard three-minute efforts at 95 rpm. Breathe.",
			"steps": [[600, 0.45, 0.75]] + _repeat(5, [[180, 1.15, 1.15, 95], [180, 0.50]])
				+ [[300, 0.50, 0.40]]},
		{"id": "over-unders", "name": "Over-Unders", "level": "Advanced",
			"about": "Three sets swinging either side of your threshold.",
			"steps": [[600, 0.45, 0.75]]
				+ _repeat(2, _repeat(3, [[120, 0.95], [60, 1.05]]) + [[240, 0.55]])
				+ _repeat(3, [[120, 0.95], [60, 1.05]]) + [[300, 0.55, 0.40]]},
		{"id": "long-endurance", "name": "Long Endurance", "level": "Intermediate",
			"about": "An hour at an all-day pace.",
			"steps": [[600, 0.45, 0.68], [2700, 0.68], [300, 0.60, 0.42]]},
		{"id": "hour-of-power", "name": "Hour of Power", "level": "Advanced",
			"about": "Four long blocks climbing from 85% to 95%.",
			"steps": [[600, 0.45, 0.75], [600, 0.85], [180, 0.55], [600, 0.88],
				[180, 0.55], [600, 0.90], [180, 0.55], [360, 0.95],
				[300, 0.55, 0.40]]},
	]


## Colours for each part of the island (Island.AREAS).
static func themes() -> Dictionary:
	return {
		"city": {"sky": Color("05030f"), "fog": Color("120a2a"),
			"grid": Color("3d5cff"), "edge": Color("00f0ff"),
			"accent": Color("ff2bd6"), "sun_top": Color("ffd23f"),
			"sun_bottom": Color("ff2bd6"), "rider": Color("ffb000"),
			"scenery": "tower"},
		"cyan": {"sky": Color("03060f"), "fog": Color("071630"),
			"grid": Color("00b8e6"), "edge": Color("00f0ff"),
			"accent": Color("ff2bd6"), "sun_top": Color("ffd23f"),
			"sun_bottom": Color("ff2bd6"), "rider": Color("ffb000"),
			"scenery": "prism"},
		"magenta": {"sky": Color("0b0314"), "fog": Color("1c0729"),
			"grid": Color("d61fb6"), "edge": Color("ff4fe0"),
			"accent": Color("00e5ff"), "sun_top": Color("ff9f1c"),
			"sun_bottom": Color("ff2bd6"), "rider": Color("00e5ff"),
			"scenery": "pyramid"},
		"amber": {"sky": Color("0d0602"), "fog": Color("211004"),
			"grid": Color("d97300"), "edge": Color("ffb000"),
			"accent": Color("ff4a1f"), "sun_top": Color("ffe066"),
			"sun_bottom": Color("ff5500"), "rider": Color("00f0ff"),
			"scenery": "cube"},
		"green": {"sky": Color("020d06"), "fog": Color("04190e"),
			"grid": Color("1fd672"), "edge": Color("7dffb4"),
			"accent": Color("d4ff3f"), "sun_top": Color("e8ff7a"),
			"sun_bottom": Color("00b36b"), "rider": Color("ff6ad5"),
			"scenery": "tree"},
		"violet": {"sky": Color("07031a"), "fog": Color("140a38"),
			"grid": Color("8a4dff"), "edge": Color("c6a4ff"),
			"accent": Color("3dffea"), "sun_top": Color("ff6ad5"),
			"sun_bottom": Color("7b2cff"), "rider": Color("3dffea"),
			"scenery": "crystal"},
		"gold": {"sky": Color("0a0703"), "fog": Color("1d1407"),
			"grid": Color("d9a52e"), "edge": Color("fff0b3"),
			"accent": Color("ff6a3d"), "sun_top": Color("fff3b0"),
			"sun_bottom": Color("ff9a2e"), "rider": Color("7fd8ff"),
			"scenery": "prism"},
		"ice": {"sky": Color("020a12"), "fog": Color("08203a"),
			"grid": Color("5fc4f0"), "edge": Color("e6f7ff"),
			"accent": Color("5b8cff"), "sun_top": Color("e6f7ff"),
			"sun_bottom": Color("5bc8ff"), "rider": Color("ff8a2b"),
			"scenery": "crystal"},
	}


static func find(list: Array, id: String) -> Dictionary:
	for spec in list:
		if spec["id"] == id:
			return spec
	return {}
