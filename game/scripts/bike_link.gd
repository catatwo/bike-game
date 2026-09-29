class_name BikeLink
extends Node
## The game's end of the bridge (bridge/bikebridge.py): readings come in on UDP
## 47810, the gradient or target wattage goes out on 47811, both on 127.0.0.1.
## With demo_watts set it makes up a rider instead, for work away from the bike.

signal connected_changed(is_connected: bool)

const LISTEN_PORT := 47810
const BRIDGE_PORT := 47811
const STALE_AFTER := 3.0  # seconds without a status: the bridge isn't running
const READING_STALE := 3.0  # seconds without a reading: treat as not pedalling
const RESEND_EVERY := 5.0  # repeat the command, in case the bridge restarted

var power := 0.0
var cadence := 0.0
var bike_name := ""
var bike_connected := false
var bridge_state := ""  # searching, connected, or no_adapter
var erg := false
var controlled := true  # the bike has accepted control, so it takes the gradient and wattage
var demo_watts := 0.0
var demo_grade := 0.0  # set by the game, so the demo rider feels the hills
var demo_max := INF  # the most the demo rider can push, to try out the FTP test
var demo_cadence := 0.0  # a workout's cadence target, which the demo rider keeps to
var demo_rpm := 0.0  # set: the demo rider's cadence, whatever it's asked for (tests)
var _udp := PacketPeerUDP.new()
var _since_status := INF
var _since_reading := INF
var _last_sent := ""
var _since_sent := 0.0


func _ready() -> void:
	if demo_watts > 0.0:
		return
	var err := _udp.bind(LISTEN_PORT, "127.0.0.1")
	if err != OK:
		push_warning("can't listen on UDP %d: %s" % [LISTEN_PORT, error_string(err)])
	_udp.set_dest_address("127.0.0.1", BRIDGE_PORT)


func _process(delta: float) -> void:
	var was := bike_connected
	if demo_watts > 0.0:
		_demo(delta)
	else:
		_since_status += delta
		_since_reading += delta
		_since_sent += delta
		while _udp.get_available_packet_count() > 0:
			var msg = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
			if msg is Dictionary:
				handle(msg)
		if _since_status > STALE_AFTER:
			bike_connected = false
		if _since_reading > READING_STALE or not bike_connected:
			power = 0.0
			cadence = 0.0
	if was != bike_connected:
		connected_changed.emit(bike_connected)


func handle(msg: Dictionary) -> void:
	match msg.get("type"):
		"status":
			_since_status = 0.0
			bike_connected = msg.get("state") == "connected"
			bridge_state = str(msg.get("state", ""))
			var n = msg.get("bike")
			bike_name = n if n is String else ""
			erg = msg.get("erg") == true
			controlled = msg.get("controlled", true) == true  # an older bridge doesn't say
		"ride":
			_since_reading = 0.0
			var p = msg.get("power")
			var c = msg.get("cadence")
			power = maxf(0.0, float(p)) if p != null else 0.0
			cadence = maxf(0.0, float(c)) if c != null else 0.0


func bridge_running() -> bool:
	return demo_watts > 0.0 or _since_status <= STALE_AFTER


func send_grade(percent: float) -> void:
	_send({"grade": snappedf(percent, 0.1)})


func send_power(watts: float) -> void:
	_send({"power": roundf(watts)})


func _send(msg: Dictionary) -> void:
	var text := JSON.stringify(msg)
	if text == _last_sent and _since_sent < RESEND_EVERY:
		return
	_last_sent = text
	_since_sent = 0.0
	if demo_watts <= 0.0:
		_udp.put_packet(text.to_utf8_buffer())
	elif msg.has("grade"):
		demo_grade = msg["grade"]
	else:
		demo_grade = 0.0


var _demo_t := 0.0


func _demo(delta: float) -> void:
	_demo_t += delta
	bike_connected = true
	bike_name = "demo rider"
	erg = true
	var target := demo_watts + 12.0 * demo_grade
	if _last_sent.begins_with('{"power"'):
		target = float(JSON.parse_string(_last_sent)["power"])
	power = clampf(target + 10.0 * sin(_demo_t * 1.7) + 6.0 * sin(_demo_t * 4.1), 0.0, demo_max)
	var rpm := demo_rpm if demo_rpm > 0.0 else (demo_cadence if demo_cadence > 0.0 else 88.0 - demo_grade)
	cadence = rpm + 3.0 * sin(_demo_t * 0.9)
