extends SceneTree

# Run against source or an exported pack with --test-mode. No personal saves.
const Catalog = preload("res://scripts/vehicle_catalog.gd")
const Controller = preload("res://scripts/vehicle_controller.gd")
const Placement = preload("res://scripts/vehicle_placement.gd")
const Authority = preload("res://scripts/lan_authority.gd")
var checks: int = 0
var failures: Array[String] = []
var definitions: Dictionary = {}

class FlatWorld:
	extends Node3D
	var spawn_position: Vector3 = Vector3(-66.0, 0.1, 10.0)
	var pickup_points: Array[Dictionary] = []
	var delivery_points: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("Aircraft tests require --test-mode")
		quit(2)
		return
	definitions = Catalog.load_definitions()
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "jump", "flight_descend"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	test_catalog()
	if not definitions.has("airplane"):
		finish()
		return
	await test_authority_and_placement()
	await test_controller()
	await test_actual_solo()
	finish()

func finish() -> void:
	print("AIRCRAFT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_catalog() -> void:
	check(definitions.size() == 4 and definitions.has("airplane"), "Catalog ships the fourth airplane vehicle")
	if not definitions.has("airplane"):
		return
	var plane: Dictionary = definitions["airplane"]
	check(plane["id"] == "airplane" and plane["name"] == "Самолёт Air Courier", "Airplane has the canonical ID and Russian name")
	check(int(plane["price"]) == 30000 and int(plane["required_level"]) == 8, "Airplane costs 30000 tenge and unlocks at level eight")
	check(float(plane["max_speed"]) == 30.0 and float(plane["max_altitude"]) == 60.0 and float(plane["ascend_rate"]) == 8.0 and float(plane["descend_rate"]) == 6.0, "Airplane catalog defines all four flight limits")
	var sanitized: Dictionary = Catalog.sanitize_profile_vehicles({"owned_vehicles": ["airplane", "airplane", "car", "forged"], "selected_vehicle": "airplane"})
	check(sanitized["owned_vehicles"] == ["airplane", "car"] and sanitized["selected_vehicle"] == "airplane", "Profile sanitizer preserves selected airplane and removes duplicate or unknown ownership")
	var defaults: Dictionary = Catalog.definitions_from_data({"airplane": {"max_altitude": NAN, "ascend_rate": INF, "descend_rate": -INF}})
	check(float(defaults["airplane"]["max_altitude"]) == 60.0 and float(defaults["airplane"]["ascend_rate"]) == 8.0 and float(defaults["airplane"]["descend_rate"]) == 6.0, "Malformed flight configuration falls back to finite shipped limits")
	var inflated: Dictionary = Catalog.definitions_from_data({"airplane": {"max_speed": 1.0e20, "max_altitude": 1.0e20, "ascend_rate": 1.0e20, "descend_rate": 1.0e20}})["airplane"]
	check(float(inflated["max_speed"]) == 30.0 and float(inflated["max_altitude"]) == 60.0 and float(inflated["ascend_rate"]) == 8.0 and float(inflated["descend_rate"]) == 6.0, "Finite inflated airplane configuration remains inside all four hard flight caps")

func box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func flat_world() -> FlatWorld:
	var world := FlatWorld.new()
	root.add_child(world)
	box(world, Vector3(0.0, -0.5, 0.0), Vector3(516.0, 1.0, 516.0))
	return world

func career() -> Dictionary:
	return {"money": 60000, "xp": 7350, "level": 8, "rank": "Express Pro", "owned_vehicles": [], "selected_vehicle": ""}

func pose(record: Dictionary, position: Vector3, velocity: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"position": position, "yaw": float(record["yaw"]), "velocity": velocity, "grounded": position.y < 0.3, "carrying": false, "active_vehicle": "airplane", "vehicle_generation": int(record["vehicle"]["generation"])}

func locate(record: Dictionary, position: Vector3) -> void:
	# Trusted fixture placement only; requests below use production validation.
	record["position"] = position
	record["vehicle"]["position"] = position
	record["velocity"] = Vector3.ZERO
	record["vehicle"]["velocity"] = Vector3.ZERO
	record["pose_tick_msec"] = Time.get_ticks_msec() - 100
	record["move_credit"] = 2.0
	record["flight_ascent_credit"] = 0.65
	record["flight_descent_credit"] = 0.65
	record["flight_turn_credit"] = 0.25

func reject_pose(authority, peer_id: int, payload: Dictionary, message: String) -> void:
	var before: Vector3 = authority.records[peer_id]["position"]
	authority.handle_request(peer_id, "pose", payload)
	check(authority.records[peer_id]["position"] == before, message)

func test_authority_and_placement() -> void:
	var world := flat_world()
	var authority = Authority.new()
	root.add_child(authority)
	await physics_frame
	await process_frame
	authority.start_session({"shift_seconds": -1}, [{"id": 1, "name": "Host", "profile": career()}, {"id": 2, "name": "Client", "profile": career()}], world, {}, "aircraft-regression")
	authority.set_process(false)
	var record: Dictionary = authority.records[2]
	record["position"] = Placement.GARAGE_POSITION + Vector3(0.0, 0.1, 0.0)
	record["profile"]["level"] = 7
	authority.handle_request(2, "vehicle_buy", {"type": "airplane"})
	check(record["vehicle"].is_empty() and int(record["profile"]["money"]) == 60000, "Host rejects an airplane purchase below level eight")
	record["profile"]["level"] = 8
	record["profile"]["money"] = 29999
	authority.handle_request(2, "vehicle_buy", {"type": "airplane"})
	check(record["vehicle"].is_empty() and record["profile"]["owned_vehicles"].is_empty(), "Host rejects an unaffordable airplane without granting ownership")
	record["profile"]["money"] = 60000
	authority.handle_request(2, "vehicle_buy", {"type": "airplane"})
	check(record["profile"]["owned_vehicles"].has("airplane") and record["profile"]["selected_vehicle"] == "airplane" and int(record["profile"]["money"]) == 30000, "Host buys, selects and charges exactly once for airplane")
	check(record["vehicle"].get("type", "") == "airplane" and not bool(record["vehicle"].get("occupied", true)), "Host spawns the purchased airplane parked nearby")
	if record["vehicle"].is_empty():
		authority.queue_free()
		world.queue_free()
		await process_frame
		return
	authority.handle_request(2, "vehicle_buy", {"type": "airplane"})
	check(int(record["profile"]["money"]) == 30000 and record["profile"]["owned_vehicles"].size() == 1, "Duplicate purchase cannot charge again or duplicate inventory")
	record["position"] = record["vehicle"]["position"]
	authority.handle_request(2, "vehicle_toggle", {"owner_id": 1})
	check(not bool(record["vehicle"]["occupied"]), "Client cannot enter another peer's airplane")
	authority.handle_request(2, "vehicle_toggle", {"owner_id": 2})
	check(bool(record["vehicle"]["occupied"]), "Owner can enter a grounded airplane")
	locate(record, Vector3(0.0, 5.0, 0.0))
	authority.handle_request(2, "vehicle_toggle", {"owner_id": 2})
	check(bool(record["vehicle"]["occupied"]) and record["position"].y == 5.0, "Host refuses airborne disembark even at zero horizontal speed")
	check(Placement.find_exit(world, Vector3(0.0, 5.0, 0.0), 0.0, [], definitions["airplane"]) == null, "Exit search cannot project an airborne vehicle down to street level")
	check(not Placement.is_near_floor(world, Vector3(0.0, 5.0, 0.0)) and Placement.is_near_floor(world, Vector3(0.0, 0.1, 0.0)), "Ground gate uses actual nearby floor height")
	for invalid: Vector3 in [Vector3(0.0, 60.01, 0.0), Vector3(256.0, 5.0, 0.0), Vector3(INF, 5.0, 0.0), Vector3(100.0, 5.0, 0.0), Vector3(0.0, 10.0, 0.0), Vector3(0.0, 0.1, 0.0)]:
		reject_pose(authority, 2, pose(record, invalid), "Host rejects invalid height, bounds, nonfinite, teleport or vertical jump")
	for invalid_velocity: Vector3 in [Vector3(100.0, 0.0, 0.0), Vector3(0.0, 99.0, 0.0), Vector3(0.0, -99.0, 0.0), Vector3(0.0, NAN, 0.0)]:
		reject_pose(authority, 2, pose(record, Vector3(0.2, 5.0, 0.0), invalid_velocity), "Host rejects out-of-range or nonfinite declared flight velocity")
	var wrong: Dictionary = pose(record, Vector3(0.2, 5.0, 0.0))
	wrong["active_vehicle"] = "car"
	reject_pose(authority, 2, wrong, "Host rejects a forged active vehicle")
	wrong = pose(record, Vector3(0.2, 5.0, 0.0))
	wrong["vehicle_generation"] = int(wrong["vehicle_generation"]) + 1
	reject_pose(authority, 2, wrong, "Host rejects a stale or forged vehicle generation")
	wrong = pose(record, Vector3(0.2, 5.0, 0.0))
	wrong.erase("vehicle_generation")
	reject_pose(authority, 2, wrong, "Host rejects a plane pose missing its vehicle generation")
	wrong = pose(record, Vector3(0.2, 5.0, 0.0))
	wrong["yaw"] = float(record["yaw"]) + PI
	reject_pose(authority, 2, wrong, "Host rejects an instantaneous half-turn")
	locate(record, Vector3(0.0, 0.6, 0.0))
	wrong = pose(record, Vector3(0.0, 0.6, 0.0))
	wrong["grounded"] = true
	authority.handle_request(2, "pose", wrong)
	authority.handle_request(2, "vehicle_toggle", {"owner_id": 2})
	check(bool(record["vehicle"]["occupied"]) and not bool(record["grounded"]), "Forged grounded flag at sixty centimetres cannot authorize airplane exit")
	locate(record, Vector3(0.0, 5.0, 0.0))
	authority.handle_request(2, "pose", pose(record, Vector3(0.5, 5.3, 0.0), Vector3(5.0, 3.0, 0.0)))
	check(record["position"].is_equal_approx(Vector3(0.5, 5.3, 0.0)) and not bool(record["grounded"]), "Host accepts bounded horizontal flight and ascent with airborne grounding")
	var flood_start: float = float(record["position"].y)
	for index: int in range(100):
		var next: Vector3 = record["position"] + Vector3(0.0, 0.2, 0.0)
		authority.handle_request(2, "pose", pose(record, next, Vector3(0.0, 8.0, 0.0)))
	check(float(record["position"].y) - flood_start < 2.0, "Rapid packet spam cannot refill ascent movement credit")
	locate(record, Vector3(0.0, 10.0, 0.0))
	for index: int in range(100):
		authority.handle_request(2, "pose", pose(record, record["position"] + Vector3(0.0, -0.2, 0.0), Vector3(0.0, -6.0, 0.0)))
	check(10.0 - float(record["position"].y) < 2.0, "Rapid packet spam cannot refill descent movement credit")
	locate(record, Vector3(0.0, 5.0, 0.0))
	for index: int in range(100):
		authority.handle_request(2, "pose", pose(record, record["position"] + Vector3(0.2, 0.0, 0.0), Vector3(30.0, 0.0, 0.0)))
	check(float(record["position"].x) < 6.0, "Rapid packet spam cannot refill horizontal flight credit")
	locate(record, Vector3(0.0, 0.65, 0.0))
	record["active_order"] = {"type": "fragile", "state": "PickedUp", "quality": 100.0, "quality_bonus_max": 100, "last_impact_msec": -1}
	record["impact_pose_msec"] = Time.get_ticks_msec() - 100
	record["displacement_velocity"] = Vector3(0.0, -6.0, 0.0)
	authority.handle_request(2, "pose", pose(record, Vector3(0.0, 0.05, 0.0)))
	check(float(record["active_order"]["quality"]) < 100.0, "Host damages a fragile parcel for a measured hard landing at real floor contact")
	locate(record, Vector3(0.0, 5.0, 0.0))
	record["active_order"] = {"type": "fragile", "state": "PickedUp", "quality": 100.0, "quality_bonus_max": 100, "last_impact_msec": -1}
	record["impact_pose_msec"] = Time.get_ticks_msec() - 100
	record["displacement_velocity"] = Vector3.ZERO
	authority.handle_request(2, "pose", pose(record, Vector3(0.0, 5.0, 0.0), Vector3(0.0, -6.0, 0.0)))
	check(float(record["active_order"]["quality"]) == 100.0, "Declared descent velocity alone cannot fabricate a fragile impact without displacement and contact")
	record["active_order"] = {}
	var host: Dictionary = authority.records[1]
	host["profile"]["owned_vehicles"] = ["airplane"]
	host["vehicle"] = authority._new_vehicle(1, "airplane", Vector3(15.0, 5.0, 0.0), 0.0)
	host["vehicle"]["occupied"] = true
	locate(host, Vector3(15.0, 5.0, 0.0))
	reject_pose(authority, 1, pose(host, Vector3(100.0, 5.0, 0.0)), "Host's own airplane obeys teleport validation")
	var plane: Dictionary = definitions["airplane"]
	var half_length: float = float(plane["collision_length"]) * 0.5
	var post := box(world, Vector3(float(plane["collision_width"]) * 0.42, 5.8, 0.0), Vector3(0.25, 1.5, 0.25))
	await physics_frame
	var from := Vector3(0.0, 5.0, -half_length - 1.0)
	var to := Vector3(0.0, 5.0, half_length + 1.0)
	check(Placement.has_line_of_sight(world, from, to), "Wing obstruction fixture leaves the center line unobstructed")
	check(not Placement.flight_path_is_free(world, from, 0.0, to, 0.0, plane), "Full airplane sweep catches a post hit only by the wing")
	post.queue_free()
	authority.queue_free()
	world.queue_free()
	await process_frame

func test_controller() -> void:
	var world := flat_world()
	var plane = Controller.new()
	var inflated: Dictionary = definitions["airplane"].duplicate(true)
	for field: String in ["max_speed", "ascend_rate", "descend_rate", "max_altitude"]:
		inflated[field] = 999.0
	plane.configure(inflated, 0, false)
	world.add_child(plane)
	plane.reset_at(Vector3(0.0, 0.1, 0.0), 0.0)
	plane.set_occupied(true)
	plane.set_controls_enabled(true)
	await physics_frame
	plane.set_physics_process(false)
	Input.action_press("jump")
	for index: int in range(30):
		plane._physics_process(1.0 / 60.0)
	Input.action_release("jump")
	check(plane.global_position.y > 1.0 and plane.velocity.y <= 8.01, "Space produces vertical takeoff at the ascent limit")
	check(not plane.can_disembark(), "Controller blocks disembark while airborne")
	var hover_height: float = plane.global_position.y
	for index: int in range(15):
		plane._physics_process(1.0 / 60.0)
	check(absf(plane.global_position.y - hover_height) < 0.01 and absf(plane.velocity.y) < 0.01, "Releasing vertical controls holds flight altitude")
	Input.action_press("flight_descend")
	for index: int in range(90):
		plane._physics_process(1.0 / 60.0)
	Input.action_release("flight_descend")
	check(plane.velocity.y >= -6.01, "Ctrl descent respects the descent limit")
	check(plane.is_on_floor() and plane.can_disembark(), "Ctrl descent lands on collision floor and restores safe disembark")
	plane.reset_at(Vector3(0.0, 59.95, 0.0), 0.0)
	Input.action_press("jump")
	for index: int in range(10):
		plane._physics_process(1.0 / 60.0)
	Input.action_release("jump")
	check(plane.global_position.y <= 60.001, "Controller clamps flight at sixty metres")
	Input.action_press("move_forward")
	for index: int in range(240):
		plane._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	check(plane.speed <= 30.01 and Vector2(plane.velocity.x, plane.velocity.z).length() <= 30.01, "Direct inflated controller configuration cannot exceed horizontal flight speed cap")
	var impacts: Array[float] = []
	plane.impact.connect(func(normal_speed: float) -> void: impacts.append(normal_speed))
	var ceiling := box(world, Vector3(0.0, 9.0, 0.0), Vector3(20.0, 0.2, 20.0))
	await physics_frame
	plane.reset_at(Vector3(0.0, 5.0, 0.0), 0.0)
	Input.action_press("jump")
	for index: int in range(30):
		plane._physics_process(1.0 / 60.0)
	Input.action_release("jump")
	check(plane.global_position.y <= 6.46 and not impacts.is_empty(), "Actual controller full-body sweep stops at ceiling and emits vertical impact")
	ceiling.queue_free()
	var post := box(world, Vector3(2.5, 5.8, -6.0), Vector3(0.25, 1.5, 0.25))
	await physics_frame
	plane.reset_at(Vector3(0.0, 5.0, 0.0), 0.0)
	plane.speed = 30.0
	Input.action_press("move_forward")
	for index: int in range(30):
		plane._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	check(plane.global_position.z > -3.4, "Actual controller collision catches a post at the wing edge")
	post.queue_free()
	world.queue_free()
	await process_frame

func test_actual_solo() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.set_process(false)
	app.player.set_physics_process(false)
	app.profile = app.lan_authority._sanitize_profile(career())
	app._begin_shift()
	app._close_modal()
	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(0.0, 0.15, 0.0))
	app._buy_vehicle("airplane")
	check(app.profile["owned_vehicles"].has("airplane") and app.profile["selected_vehicle"] == "airplane" and int(app.profile["money"]) == 30000, "Actual Solo garage buys and selects airplane through production Main")
	if app.vehicles.has(0):
		var plane = app.vehicles[0]
		for index: int in range(12):
			await physics_frame
		plane.set_physics_process(false)
		app.player.reset_at(plane.global_position)
		app._toggle_vehicle(0)
		check(app.player.is_riding(), "Actual Solo owner enters the grounded airplane")
		var profiles_before: int = app.navigation._profiles.size()
		var queries_before: int = app.navigation.query_count
		var course: Dictionary = {}
		for index: int in range(100):
			course = app.navigation.guidance(Vector3(0.0, 20.0, 0.0), Vector3(0.0, 0.0, 8.0), "aircraft-route", "airplane")
		check(bool(course.get("airborne", false)) and bool(course.get("walk_last", false)) and is_finite(float(course.get("distance", NAN))) and course["hint"].contains("посадка"), "Airplane guidance gives finite aerial bearing and a landing-first hint")
		check(app.navigation._profiles.size() == profiles_before and app.navigation.query_count == queries_before, "Repeated aircraft guidance builds no street grids or ground-route queries")
		var invalid_route: Dictionary = app.navigation.guidance(Vector3(NAN, 20.0, 0.0), Vector3.ZERO, "invalid-aircraft", "airplane")
		check(invalid_route.get("status") == "no_route" and invalid_route.get("points", []).is_empty() and is_finite(float(invalid_route.get("distance", NAN))), "Invalid flight position produces no route and no nonfinite distance")
		app.audio_manager.set_context(true, app.player, plane, {})
		var audio: Dictionary = app.audio_manager.debug_state()
		check(audio.get("engine_type") == "airplane" and bool(audio.get("engine_playing", false)) and not app.audio_manager.play_event("footstep"), "Mounted airplane starts its pooled engine and suppresses footsteps")
		app.audio_manager.stop_gameplay()
		audio = app.audio_manager.debug_state()
		check(not bool(audio.get("engine_playing", true)) and str(audio.get("engine_type", "")).is_empty(), "Stopping gameplay shuts down airplane engine")
		plane.global_position.y = 8.0
		plane.velocity = Vector3.ZERO
		plane.speed = 0.0
		app._toggle_vehicle(0)
		check(app.player.is_riding(), "Actual Solo refuses airborne exit even while stationary")
		app.player.set_riding_vehicle(null)
		plane.set_occupied(false)
		var walking: Dictionary = app.navigation.guidance(Vector3.ZERO, Vector3(0.0, 0.0, 8.0), "aircraft-route", "walking")
		check(not bool(walking.get("airborne", false)) and walking.get("status") in ["ok", "arrived"] and app.navigation.query_count > queries_before, "Walking navigation returns after leaving airplane")
		app.player.reset_at(Placement.GARAGE_POSITION + Vector3(0.0, 0.15, 0.0))
		app._spawn_vehicle("airplane")
		check(app.vehicles[0].global_position.y < 0.7 and app.profile["selected_vehicle"] == "airplane", "Actual Solo garage can safely respawn its owned airplane")
	check(app.test_mode, "Solo regression keeps personal profile writes disabled")
	app.queue_free()
	await process_frame
