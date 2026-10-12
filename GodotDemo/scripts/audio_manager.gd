extends Node



const POOL_SIZE: = 8
const AUDIO_DIRECTORY: = "res://assets/audio/"
const EVENT_VOLUMES: = {
	"footstep": -11.0, "order_accept": -9.0, "pickup": -9.0, 
	"delivery": -10.0, "level_up": -10.0, "purchase": -9.0, "ui_click": -13.0, 
}
const AUDIO_NAMES: Array[String] = ["footstep", "order_accept", "pickup", "delivery", 
	"level_up", "purchase", "ui_click", "scooter_engine", "car_engine", "music"]

var test_mode: = false
var _initialized: = false
var _gameplay_active: = false
var _local_player: Node3D
var _local_vehicle: Node3D
var _streams: Dictionary = {}
var _one_shots: Array[AudioStreamPlayer] = []
var _slot_events: Array[String] = []
var _slot_serials: Array[int] = []
var _play_serial: = 0
var _event_counts: Dictionary = {}
var _music: AudioStreamPlayer
var _engine: AudioStreamPlayer3D
var _engine_type: = ""
var _engine_vehicle: Node3D
var _last_step_position: = Vector3.ZERO
var _step_position_valid: = false
var _step_distance: = 0.0
var _footstep_alternate: = false


func initialize(use_test_mode: bool) -> void :
	test_mode = use_test_mode
	process_mode = Node.PROCESS_MODE_ALWAYS

	process_physics_priority = 100
	_ensure_audio_buses()
	if _initialized:
		return
	_initialized = true
	for audio_name: String in AUDIO_NAMES:
		var stream: = load(AUDIO_DIRECTORY + audio_name + ".wav") as AudioStream
		if stream != null:
			_streams[audio_name] = stream
		_event_counts[audio_name] = 0
	for index in range(POOL_SIZE):
		var voice: = AudioStreamPlayer.new()
		voice.name = "OneShot_%d" % index
		voice.bus = "SFX"
		voice.max_polyphony = 1
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_one_shots.append(voice)
		_slot_events.append("")
		_slot_serials.append(0)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = "Music"
	_music.volume_db = -9.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	if _streams.has("music"):
		_music.stream = _looping_stream(_streams["music"])
		_music.play()
		_event_counts["music"] += 1
	_engine = AudioStreamPlayer3D.new()
	_engine.name = "Engine"
	_engine.bus = "SFX"
	_engine.max_polyphony = 1
	_engine.unit_size = 10.0
	_engine.max_distance = 75.0
	_engine.volume_db = -17.0
	_engine.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_engine)


func play_event(event_name: String) -> bool:
	if not _initialized or not EVENT_VOLUMES.has(event_name) or not _streams.has(event_name):
		return false
	if event_name == "footstep" and not _can_walk():
		return false
	var index: = _available_slot(event_name)
	if index < 0:
		return false
	var voice: = _one_shots[index]
	voice.stop()
	voice.stream = _streams[event_name]
	voice.volume_db = float(EVENT_VOLUMES[event_name])
	voice.pitch_scale = 1.0
	if event_name == "footstep":


		voice.pitch_scale = 0.96 if _footstep_alternate else 1.04
		_footstep_alternate = not _footstep_alternate
	_play_serial += 1
	_slot_events[index] = event_name
	_slot_serials[index] = _play_serial
	voice.play()
	_event_counts[event_name] = int(_event_counts.get(event_name, 0)) + 1
	return true


func set_context(gameplay_active: bool, local_player: Node3D, local_vehicle: Node3D, _remote_players: Dictionary) -> void :
	var changed_player: = _local_player != local_player
	_gameplay_active = gameplay_active
	_local_player = local_player
	_local_vehicle = local_vehicle
	if changed_player or not _can_walk():
		_stop_footsteps()
	_sync_engine(0.0)


func stop_gameplay() -> void :
	_gameplay_active = false
	_local_player = null
	_local_vehicle = null
	_stop_footsteps()
	_stop_engine()




func _physics_process(delta: float) -> void :
	if not _initialized:
		return
	_sync_engine(delta)
	_update_footsteps(delta)


func _exit_tree() -> void :

	for voice: AudioStreamPlayer in _one_shots:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	if is_instance_valid(_engine):
		_engine.stop()
		_engine.stream = null


func _can_walk() -> bool:
	if not _gameplay_active or get_tree().paused or not is_instance_valid(_local_player):
		return false
	if not (_local_player is CharacterBody3D) or not bool(_local_player.get("controls_enabled")):
		return false
	if _local_player.has_method("is_riding") and bool(_local_player.call("is_riding")):
		return false
	var body: = _local_player as CharacterBody3D
	return body.is_on_floor() and Vector2(body.velocity.x, body.velocity.z).length() > 0.2


func _update_footsteps(delta: float) -> void :
	if not _can_walk():
		_stop_footsteps()
		return
	var body: = _local_player as CharacterBody3D
	var position: = _local_player.global_position
	if not _step_position_valid:
		_last_step_position = position
		_step_position_valid = true
		return
	var displacement: = Vector2(position.x - _last_step_position.x, position.z - _last_step_position.z).length()
	_last_step_position = position
	var speed: = Vector2(body.velocity.x, body.velocity.z).length()

	if not is_finite(displacement) or displacement > maxf(0.9, speed * delta * 2.0 + 0.2):
		_step_distance = 0.0
		return
	if displacement < 0.0005:
		_stop_footsteps()
		return
	_step_distance += displacement
	var stride: = 2.65 if speed > 4.6 else 1.9
	if _step_distance >= stride:
		_step_distance = fmod(_step_distance, stride)
		play_event("footstep")


func _stop_footsteps() -> void :
	_step_position_valid = false
	_step_distance = 0.0
	for index in range(_one_shots.size()):
		if _slot_events[index] == "footstep" and _one_shots[index].playing:
			_one_shots[index].stop()


func _mounted_motor_type() -> String:
	if not _gameplay_active or get_tree().paused or not is_instance_valid(_local_player) or not is_instance_valid(_local_vehicle):
		return ""
	if not bool(_local_player.get("controls_enabled")) or not bool(_local_vehicle.get("controls_enabled")):
		return ""
	if not bool(_local_vehicle.get("occupied")) or bool(_local_vehicle.get("remote_mode")):
		return ""
	if _local_player.get("riding_vehicle") != _local_vehicle:
		return ""
	var definition: Variant = _local_vehicle.get("definition")
	if not (definition is Dictionary):
		return ""
	var type: = str(definition.get("id", ""))
	return type if type in ["scooter", "car"] else ""


func _sync_engine(delta: float) -> void :
	if not is_instance_valid(_engine):
		return
	var type: = _mounted_motor_type()
	if type.is_empty():
		_stop_engine()
		return
	var stream_name: = type + "_engine"
	if not _streams.has(stream_name):
		_stop_engine()
		return
	_engine.global_position = _local_vehicle.global_position + Vector3.UP * 0.65
	if type != _engine_type or _engine_vehicle != _local_vehicle or not _engine.playing:
		_engine.stop()
		_engine.stream = _looping_stream(_streams[stream_name])
		_engine_type = type
		_engine_vehicle = _local_vehicle
		_engine.pitch_scale = 0.82
		_engine.play()
		_event_counts[stream_name] = int(_event_counts.get(stream_name, 0)) + 1
	var supplied_speed: Variant = _local_vehicle.get("speed")
	var speed: = absf(float(supplied_speed)) if (supplied_speed is float or supplied_speed is int) and is_finite(float(supplied_speed)) else 0.0
	var definition: Dictionary = _local_vehicle.get("definition")
	var supplied_max: Variant = definition.get("max_speed", 20.0)
	var maximum: = maxf(0.01, float(supplied_max)) if (supplied_max is float or supplied_max is int) and is_finite(float(supplied_max)) else 20.0
	var ratio: = clampf(speed / maximum, 0.0, 1.0)
	var target_pitch: = 0.82 + ratio * (0.92 if type == "scooter" else 0.72)
	_engine.pitch_scale = lerpf(_engine.pitch_scale, target_pitch, 1.0 - exp(-8.0 * maxf(0.0, delta)))
	_engine.volume_db = -17.0 + ratio * 5.0


func _stop_engine() -> void :
	if is_instance_valid(_engine):
		_engine.stop()
	_engine_type = ""
	_engine_vehicle = null


func _available_slot(event_name: String) -> int:
	for index in range(_one_shots.size()):
		if not _one_shots[index].playing:
			return index

	if event_name == "footstep":
		return -1
	var oldest: = 0
	for index in range(1, _one_shots.size()):
		if _slot_serials[index] < _slot_serials[oldest]:
			oldest = index
	return oldest


func _looping_stream(source: AudioStream) -> AudioStream:
	var result: = source.duplicate() as AudioStream
	if result is AudioStreamWAV:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_begin = 0
		result.loop_end = maxi(1, int(round(result.get_length() * result.mix_rate)))
	return result


func _ensure_audio_buses() -> void :
	for bus: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index: = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")


func debug_state() -> Dictionary:
	var active: = 0
	var footsteps: = 0
	var routing: Array[String] = []
	for index in range(_one_shots.size()):
		var voice: = _one_shots[index]
		routing.append(voice.bus)
		if voice.playing:
			active += 1
			if _slot_events[index] == "footstep":
				footsteps += 1
	return {"initialized": _initialized, "test_mode": test_mode, 
		"event_counts": _event_counts.duplicate(true), "loaded_streams": _streams.size(), 
		"pool_size": _one_shots.size(), "active_count": active, "active_footsteps": footsteps, 
		"engine_type": _engine_type, "engine_playing": is_instance_valid(_engine) and _engine.playing, 
		"engine_pitch": _engine.pitch_scale if is_instance_valid(_engine) else 0.0, 
		"engine_bus": _engine.bus if is_instance_valid(_engine) else "", 
		"music_playing": is_instance_valid(_music) and _music.playing, 
		"music_bus": _music.bus if is_instance_valid(_music) else "", 
		"one_shot_buses": routing, "runtime_player_count": get_child_count(), 
		"gameplay_active": _gameplay_active}


func get_debug_state() -> Dictionary:
	return debug_state()
