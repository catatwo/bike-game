class_name RiderPhysics
extends RefCounted
## Speed from power on a road of a given gradient: gravity, rolling resistance
## and air drag. The standard model cycling apps use.

const G := 9.81
const AIR_DENSITY := 1.225
const BIKE_KG := 9.0
const WHEEL_INERTIA_KG := 1.5  # spinning wheels feel like a little extra mass

var rider_kg := 80.0
var cda := 0.32  # drag area in m²: an upright position on the hoods
var crr := 0.004  # rolling resistance of a good road tyre
var speed := 0.0  # m/s
var distance := 0.0  # m


func step(power: float, grade: float, delta: float) -> void:
	var mass := rider_kg + BIKE_KG
	var angle := atan(grade)
	var resist := mass * G * (sin(angle) + crr * cos(angle)) \
			+ 0.5 * AIR_DENSITY * cda * speed * speed
	# Force from power is P/v; below 1 m/s it's capped, or a standing start
	# would be infinitely strong.
	var drive := maxf(power, 0.0) / maxf(speed, 1.0)
	speed = maxf(0.0, speed + (drive - resist) / (mass + WHEEL_INERTIA_KG) * delta)
	distance += speed * delta


## Seconds to ride a route at a steady power, for the estimates in the menus.
static func time_for(route: Route, power: float, rider_kg: float) -> float:
	var p := RiderPhysics.new()
	p.rider_kg = rider_kg
	var t := 0.0
	var dt := 1.0
	while p.distance < route.length and t < 6 * 3600.0:
		p.step(power, route.grade_at(p.distance), dt)
		t += dt
	return t
