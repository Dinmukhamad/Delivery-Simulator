extends SceneTree

# This suite has no profile I/O. Placements are trusted fixtures; purchases,
# mounts, shots, damage and recovery use the production Host request path.
const Authority = preload("res://scripts/lan_authority.gd")
const Rules = preload("res://scripts/aircraft_combat_rules.gd")
const Catalog = preload("res://scripts/vehicle_catalog.gd")
const Placement = preload("res://scripts/vehicle_placement.gd")

var checks: int = 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var definitions: Dictionary = {}

class FlatWorld:
	extends Node3D
	var spawn_position: Vector3 = Vector3(-23.0, 0.15, 4.0)
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
		printerr("Air combat tests require --test-mode")
		quit(2)
		return
	definitions = Catalog.load_definitions()
	test_geometry()
	await test_authority()
	await test_actual_game_input_and_effects()
	print("AIR_COMBAT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_geometry() -> void:
	var definition: Dictionary = definitions["airplane"]
	check(Rules.MAX_HEALTH == 100 and Rules.DAMAGE == 25, "Arcade combat uses one hundred health and four-hit shootdowns")
	check(Rules.COOLDOWN_MSEC == 250 and Rules.RANGE == 160.0 and Rules.MIN_COMBAT_ALTITUDE == 2.0, "Combat cadence, range and safe-ground boundary are explicit")
	check(Rules.shot_direction(0.0).is_equal_approx(Vector3.FORWARD), "Yaw zero fires along the plane's nose")
	check(Rules.shot_direction(PI * 0.5).is_equal_approx(Vector3.LEFT), "Quarter-turn rotates the firing line with the plane")
	check(Rules.shot_direction(NAN) == Vector3.ZERO, "Nonfinite yaw cannot produce a usable firing direction")
	var origin := Vector3(0.0, 13.25, 30.0)
	var target := Vector3(0.0, 12.0, -30.0)
	var distance: float = Rules.ray_hit_distance(origin, Vector3.FORWARD, target, 0.0, definition)
	check(is_equal_approx(distance, 57.35), "Ray intersects the nearest front face of the full aircraft box")
	check(is_finite(Rules.ray_hit_distance(origin + Vector3(2.9, 0.0, 0.0), Vector3.FORWARD, target, 0.0, definition)), "Wing-edge hit succeeds even when a narrow fuselage ray would miss")
	check(is_inf(Rules.ray_hit_distance(origin + Vector3(3.1, 0.0, 0.0), Vector3.FORWARD, target, 0.0, definition)), "A ray beyond the wing is a miss")
	check(is_inf(Rules.ray_hit_distance(origin + Vector3(2.9, 0.0, 0.0), Vector3.FORWARD, target, PI * 0.5, definition)), "Rotated hitbox uses the shorter nose-to-tail dimension at this lateral offset")
	check(is_inf(Rules.ray_hit_distance(origin, Vector3.BACK, target, 0.0, definition)), "A target behind the firing direction cannot be hit")
	check(is_inf(Rules.ray_hit_distance(origin, Vector3.FORWARD, target, 0.0, definition, 40.0)), "The finite shot segment cannot hit a distant target")
	check(is_inf(Rules.ray_hit_distance(origin + Vector3.UP * 3.0, Vector3.FORWARD, target, 0.0, definition)), "Horizontal guns cannot damage an aircraft at a different altitude")
	for invalid: Vector3 in [Vector3(INF, 0.0, 0.0), Vector3(0.0, NAN, 0.0)]:
		check(is_inf(Rules.ray_hit_distance(invalid, Vector3.FORWARD, target, 0.0, definition)), "Nonfinite ray origins are rejected")
		check(is_inf(Rules.ray_hit_distance(origin, invalid, target, 0.0, definition)), "Nonfinite ray directions are rejected")
	check(is_inf(Rules.ray_hit_distance(origin, Vector3.ZERO, target, 0.0, definition)), "A zero-length firing direction is rejected")
	check(is_inf(Rules.ray_hit_distance(origin, Vector3.FORWARD, target, NAN, definition)), "A nonfinite target orientation is rejected")
	var plane: Dictionary = {"type": "airplane", "occupied": true, "health": 100, "position": Vector3(0.0, 2.0, 0.0)}
	check(Rules.eligible(plane), "An occupied live plane at two metres is eligible")
	for change: Dictionary in [{"occupied": false}, {"health": 0}, {"type": "car"}, {"position": Vector3(0.0, 1.99, 0.0)}, {"position": Vector3(INF, 8.0, 0.0)}]:
		var ineligible: Dictionary = plane.duplicate(true)
		ineligible.merge(change, true)
		check(not Rules.eligible(ineligible), "Parked, destroyed, ground, non-plane and invalid aircraft remain protected")

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

func career() -> Dictionary:
	return {"money": 60000, "xp": 7350, "level": 8, "rank": "Express Pro", "owned_vehicles": [], "selected_vehicle": "", "total_deliveries": 7, "total_money_earned": 1234}

func locate(record: Dictionary, position: Vector3, yaw: float = 0.0) -> void:
	# Set up a known airspace without spending real minutes flying there. This
	# never grants a shot/hit; those always go through normal request validation.
	record["position"] = position
	record["yaw"] = yaw
	record["velocity"] = Vector3.ZERO
	record["grounded"] = position.y < 0.5
	if not record["vehicle"].is_empty():
		record["vehicle"]["position"] = position
		record["vehicle"]["yaw"] = yaw
		record["vehicle"]["velocity"] = Vector3.ZERO
		record["vehicle"]["grounded"] = position.y < 0.5

func capture_event(peer_id: int, event: Dictionary) -> void:
	events.append({"recipient": peer_id, "event": event.duplicate(true)})

func shots(peer_id: int = 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in events:
		if int(entry["recipient"]) == peer_id and str(entry["event"].get("type", "")) == "aircraft_shot":
			result.append(entry["event"])
	return result

func request(authority, peer_id: int) -> Dictionary:
	return {"generation": int(authority.records[peer_id]["vehicle"].get("generation", 0))}

func ready_guns(authority, peer_id: int = 1) -> void:
	# Trusted clock fixture for independent scenarios. A separate real-time
	# assertion below verifies that packet spam cannot bypass the actual timer.
	authority._aircraft_last_fire_msec.erase(peer_id)

func reject(authority, peer_id: int, payload: Dictionary, message: String) -> void:
	var before: int = shots().size()
	var health: int = int(authority.records[2]["vehicle"].get("health", -1))
	authority.handle_request(peer_id, "aircraft_fire", payload)
	check(shots().size() == before and int(authority.records[2]["vehicle"].get("health", -1)) == health, message)

func test_authority() -> void:
	var world := FlatWorld.new()
	root.add_child(world)
	box(world, Vector3(0.0, -0.5, 0.0), Vector3(516.0, 1.0, 516.0))
	var authority = Authority.new()
	root.add_child(authority)
	authority.event_ready.connect(capture_event)
	await physics_frame
	await process_frame
	authority.start_session({"shift_seconds": -1}, [{"id": 1, "name": "Host", "profile": career()}, {"id": 2, "name": "Client", "profile": career()}, {"id": 3, "name": "Third", "profile": career()}], world, {}, "air-combat-tests")
	authority.set_process(false)
	for peer_id: int in [1, 2, 3]:
		var record: Dictionary = authority.records[peer_id]
		record["position"] = Placement.GARAGE_POSITION + Vector3(0.0, 0.15, 0.0)
		authority.handle_request(peer_id, "vehicle_buy", {"type": "airplane"})
		check(record["profile"]["owned_vehicles"].has("airplane") and int(record["profile"]["money"]) == 30000, "Each courier independently purchases their own airplane")
		check(str(record["vehicle"].get("type", "")) == "airplane" and int(record["vehicle"].get("health", 0)) == 100, "Every purchased aircraft starts with full health")
		if record["vehicle"].is_empty():
			authority.queue_free()
			world.queue_free()
			await process_frame
			return
		record["position"] = record["vehicle"]["position"]
		authority.handle_request(peer_id, "vehicle_toggle", {"owner_id": peer_id})
		check(bool(record["vehicle"].get("occupied", false)), "Each owner mounts through the ordinary validated vehicle action")
		locate(record, Vector3(float(peer_id) * 20.0, 12.0, 0.0))
	var shooter: Dictionary = authority.records[1]
	var target: Dictionary = authority.records[2]
	var third: Dictionary = authority.records[3]
	locate(shooter, Vector3(0.0, 12.0, 30.0))
	locate(target, Vector3(0.0, 12.0, -30.0))
	locate(third, Vector3(25.0, 12.0, -30.0))
	events.clear()
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(target["vehicle"]["health"]) == 75, "A real Host shot damages the Client's aligned aircraft by exactly twenty-five")
	check(int(shooter["vehicle"]["health"]) == 100 and int(third["vehicle"]["health"]) == 100, "A shot cannot damage its owner or a plane outside the firing line")
	check(shots(1).size() == 1 and shots(2).size() == 1 and shots(3).size() == 1, "One confirmed shot is sent to all three connected peers")
	if shots().is_empty():
		authority.queue_free()
		world.queue_free()
		await process_frame
		return
	var first: Dictionary = shots()[0]
	check(int(first.get("shooter_id", 0)) == 1 and int(first.get("hit_id", 0)) == 2 and int(first.get("health", 0)) == 75 and not bool(first.get("destroyed", true)), "Confirmed shot names the real sender, hit peer and remaining health")
	check(first.get("session_id", "") == "air-combat-tests" and int(first.get("shot_id", 0)) > 0, "Shot event is bound to the active session and a positive server sequence")
	check((first.get("from", Vector3.ZERO) as Vector3).is_equal_approx(Rules.muzzle(shooter["position"], shooter["yaw"])), "Host derives the muzzle from authoritative position and yaw")
	check(int(first.get("target_generation", -1)) == int(target["vehicle"]["generation"]), "Damage event identifies the victim's exact vehicle generation")
	for index: int in range(20):
		authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(target["vehicle"]["health"]) == 75 and shots().size() == 1, "Immediate repeated packets cannot bypass the actual firing cooldown")
	var cooldown_deadline: int = Time.get_ticks_msec() + Rules.COOLDOWN_MSEC + 25
	while Time.get_ticks_msec() < cooldown_deadline:
		await create_timer(0.01).timeout
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(target["vehicle"]["health"]) == 50 and shots().size() == 2, "A second shot becomes valid after the real cooldown elapses")
	check(int(shots()[-1]["shot_id"]) > int(first["shot_id"]), "Confirmed shot IDs increase monotonically")

	ready_guns(authority)
	var generation: int = int(shooter["vehicle"]["generation"])
	for invalid: Dictionary in [{}, {"generation": generation - 1}, {"generation": generation + 1}, {"generation": float(generation)}, {"generation": str(generation)}, {"generation": true}, {"generation": null}, {"generation": generation, "target_id": 2}, {"generation": generation, "damage": 100000}, {"generation": generation, "owner_id": 2}, {"generation": generation, "from": Vector3.ZERO}, {"generation": generation, "to": target["position"]}]:
		reject(authority, 1, invalid, "Malformed, stale, forged or extra-field fire payload cannot create a shot")
	reject(authority, 999, {"generation": generation}, "An unknown peer cannot fire")
	check(int(target["vehicle"]["health"]) == 50, "Rejected payloads leave target health unchanged")

	# Repositioned fixtures exercise the full production targeting/physics path.
	ready_guns(authority)
	locate(shooter, Vector3(0.0, 0.15, 30.0))
	reject(authority, 1, request(authority, 1), "A grounded aircraft cannot shoot")
	locate(shooter, Vector3(0.0, 12.0, 30.0))
	shooter["vehicle"]["occupied"] = false
	reject(authority, 1, request(authority, 1), "A courier outside an aircraft cannot fire its guns")
	shooter["vehicle"]["occupied"] = true
	shooter["vehicle"]["type"] = "car"
	reject(authority, 1, request(authority, 1), "Ground vehicles cannot use aircraft guns")
	shooter["vehicle"]["type"] = "airplane"
	shooter["connected"] = false
	reject(authority, 1, request(authority, 1), "A disconnected sender cannot fire")
	shooter["connected"] = true
	authority.phase = "results"
	reject(authority, 1, request(authority, 1), "No firing is accepted after the shift ends")
	authority.phase = "playing"

	for change: String in ["ground", "parked", "car", "disconnected", "altitude", "behind", "range"]:
		ready_guns(authority)
		locate(target, Vector3(0.0, 12.0, -30.0))
		target["vehicle"]["occupied"] = true
		target["vehicle"]["type"] = "airplane"
		target["connected"] = true
		match change:
			"ground": locate(target, Vector3(0.0, 0.15, -30.0))
			"parked": target["vehicle"]["occupied"] = false
			"car": target["vehicle"]["type"] = "car"
			"disconnected": target["connected"] = false
			"altitude": locate(target, Vector3(0.0, 20.0, -30.0))
			"behind": locate(target, Vector3(0.0, 12.0, 45.0))
			"range": locate(target, Vector3(0.0, 12.0, -150.0))
		authority.handle_request(1, "aircraft_fire", request(authority, 1))
		check(int(target["vehicle"]["health"]) == 50 and int(shots()[-1].get("hit_id", -1)) == 0, "Protected or unaligned target is not damaged: " + change)
	target["connected"] = true
	target["vehicle"]["occupied"] = true
	target["vehicle"]["type"] = "airplane"
	locate(target, Vector3(0.0, 12.0, -30.0))
	var wall := box(world, Vector3(0.0, 13.0, -2.0), Vector3(12.0, 8.0, 1.0))
	await physics_frame
	await process_frame
	ready_guns(authority)
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(target["vehicle"]["health"]) == 50 and int(shots()[-1].get("hit_id", -1)) == 0, "A static wall blocks damage even when the target box is on the firing ray")
	check(float((shots()[-1]["to"] as Vector3).z) > -3.0, "The confirmed visual tracer stops at the world obstruction")
	wall.queue_free()
	await physics_frame
	await process_frame
	# A nose clipped through a thin wall must not place the muzzle past cover.
	var muzzle_wall := box(world, Vector3(0.0, 13.0, 28.7), Vector3(12.0, 8.0, 0.4))
	await physics_frame
	await process_frame
	ready_guns(authority)
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(target["vehicle"]["health"]) == 50 and int(shots()[-1]["hit_id"]) == 0, "A muzzle beyond a thin wall cannot shoot through cover from the far side")
	check((shots()[-1]["to"] as Vector3).z > 28.0 and (shots()[-1]["to"] as Vector3).z < 30.0, "A clipped nose reports the near obstruction as its shot endpoint")
	muzzle_wall.queue_free()
	await physics_frame
	await process_frame
	locate(third, Vector3(0.0, 12.0, -10.0), PI * 0.5)
	ready_guns(authority)
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(third["vehicle"]["health"]) == 75 and int(target["vehicle"]["health"]) == 50 and int(shots()[-1]["hit_id"]) == 3, "Only the nearest aligned airplane is damaged; shots do not pierce it")
	locate(third, Vector3(25.0, 12.0, -30.0))

	# A normal delivery and career survive aircraft destruction. Combat ranking
	# is separate from delivery income, XP, cooperative/event rewards and saves.
	target["active_order"] = {"id": 777, "type": "standard", "state": "PickedUp", "pickup_name": "Depot", "delivery_name": "Office", "pickup_position": Vector3.ZERO, "delivery_position": Vector3(12.0, 0.0, 12.0), "reward": 900, "xp": 50}
	target["carrying"] = true
	target["vehicle"]["carrying"] = true
	var old_order: Dictionary = target["active_order"].duplicate(true)
	var shooter_profile: Dictionary = shooter["profile"].duplicate(true)
	var target_profile: Dictionary = target["profile"].duplicate(true)
	var shooter_stats: Dictionary = shooter["shift_stats"].duplicate(true)
	var target_stats: Dictionary = target["shift_stats"].duplicate(true)
	var target_generation: int = int(target["vehicle"]["generation"])
	ready_guns(authority)
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(int(target["vehicle"]["health"]) == 25 and not bool(shots()[-1]["destroyed"]), "Third landed hit leaves twenty-five health and an intact plane")
	ready_guns(authority)
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(target["vehicle"].is_empty() and bool(shots()[-1]["destroyed"]) and int(shots()[-1]["health"]) == 0, "The fourth landed hit confirms a shootdown and removes the target vehicle")
	check(int(shooter.get("air_kills", 0)) == 1 and int(target.get("air_losses", 0)) == 1, "Shootdown credits exactly one separate match kill and loss")
	check(int(target["vehicle_generation"]) > target_generation, "Shootdown advances the victim's vehicle generation")
	check((target["position"] as Vector3).distance_to(Placement.GARAGE_POSITION) < 5.0 and Placement.is_near_floor(world, target["position"]) and bool(target["grounded"]) and target["velocity"] == Vector3.ZERO, "Victim safely returns to the garage on foot with real ground support")
	check(shooter["profile"] == shooter_profile and target["profile"] == target_profile, "Shootdown preserves both complete career profiles including money, XP and plane ownership")
	check(shooter["shift_stats"] == shooter_stats and target["shift_stats"] == target_stats, "Combat cannot alter delivery money, XP, deliveries or team/event statistics")
	check(target["active_order"] == old_order and bool(target["carrying"]), "The victim retains the active parcel and can continue delivering on foot")
	var recovery_found: bool = false
	for entry: Dictionary in events:
		if int(entry["recipient"]) == 2 and str(entry["event"].get("type", "")) == "aircraft_recovery":
			recovery_found = true
	check(recovery_found, "Victim receives a session-bound explicit recovery event")
	var snapshot: Dictionary = authority.snapshot_for(2)
	check(int(snapshot.get("air_combat", {}).get("losses", 0)) == 1, "Owner snapshot publishes the confirmed combat score")
	var public_score: bool = false
	for member: Dictionary in snapshot.get("players", []):
		if int(member["id"]) == 1:
			public_score = int(member.get("air_kills", 0)) == 1
	check(public_score, "Other players receive the shooter's confirmed combat score")

	# The same owned airplane may be spawned again at the garage without a
	# second purchase. Old shots and poses cannot affect the new incarnation.
	target["position"] = Placement.GARAGE_POSITION + Vector3(0.0, 0.15, 0.0)
	authority.handle_request(2, "vehicle_spawn", {"type": "airplane"})
	check(not target["vehicle"].is_empty() and int(target["vehicle"].get("health", 0)) == 100 and int(target["vehicle"].get("generation", 0)) > target_generation, "Garage restores the owned plane with full health and a fresh generation")
	check(target["profile"] == target_profile, "Replacing a shot-down owned aircraft is free and preserves selection and career")
	target["position"] = target["vehicle"]["position"]
	authority.handle_request(2, "vehicle_toggle", {"owner_id": 2})
	locate(target, Vector3(0.0, 12.0, -30.0), PI)
	ready_guns(authority, 2)
	var shooter_health: int = int(shooter["vehicle"]["health"])
	authority.handle_request(2, "aircraft_fire", {"generation": target_generation})
	check(int(shooter["vehicle"]["health"]) == shooter_health, "A stale fire request cannot fire the victim's replacement aircraft")
	authority.handle_request(2, "aircraft_fire", request(authority, 2))
	check(int(shooter["vehicle"]["health"]) == shooter_health - 25, "The Client's new plane can return fire and damage the Host symmetrically")
	var before_disconnect: int = shots().size()
	authority.remove_player(2)
	authority.handle_request(2, "aircraft_fire", {"generation": int(target["vehicle_generation"])})
	check(shots().size() == before_disconnect and target["vehicle"].is_empty(), "A departed courier has no plane and cannot leave active firing behind")
	authority.stop_session()
	ready_guns(authority)
	var before_stop: int = shots().size()
	authority.handle_request(1, "aircraft_fire", request(authority, 1))
	check(shots().size() == before_stop, "Session shutdown rejects all later firing requests")
	authority.queue_free()
	world.queue_free()
	await process_frame


func no_local_shot(app, message: String) -> void:
	var before: int = int(app._solo_aircraft_shot_id)
	app._last_aircraft_fire_msec = -1000
	app._request_aircraft_fire()
	check(int(app._solo_aircraft_shot_id) == before and not app._can_fire_aircraft(), message)


func click_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func test_actual_game_input_and_effects() -> void:
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
	check(app.vehicles.has(0) and app.test_mode, "Production Solo fixture buys an aircraft while personal save writes remain disabled")
	if not app.vehicles.has(0):
		app.queue_free()
		await process_frame
		return
	var plane = app.vehicles[0]
	for index: int in range(12):
		await physics_frame
	plane.set_physics_process(false)
	app.player.reset_at(plane.global_position)
	app._toggle_vehicle(0)
	check(app.player.is_riding(), "Production courier boards their purchased aircraft")
	plane.global_position = Vector3(0.0, 25.0, 40.0)
	plane.rotation.y = 0.0
	plane.velocity = Vector3.ZERO
	plane.speed = 0.0
	app.player.set_mouse_captured(true)
	var profile_before: Dictionary = app.profile.duplicate(true)
	check(InputMap.has_action("aircraft_fire") and InputMap.action_get_events("aircraft_fire")[0] is InputEventMouseButton, "Aircraft guns are bound to a real mouse Input action")
	check(app.audio_manager._streams.has("aircraft_fire") and app.audio_manager._streams.has("aircraft_hit"), "Both original combat audio clips load through the production AudioManager")
	# The headless DisplayServer cannot capture a mouse. CI repeats this same
	# suite under Xvfb so its real pointer/input paths are exercised as well.
	if DisplayServer.get_name() != "headless":
		check(app._can_fire_aircraft(), "A live owned piloted airborne plane with captured pointer can fire")

		app._pause()
		no_local_shot(app, "Pause disables gunfire even before a cooldown has started")
		app._resume()
		app._open_map()
		no_local_shot(app, "Opening the map prevents shooting behind its UI")
		app._close_modal()
		app._open_cheats()
		no_local_shot(app, "Typing in the cheat console cannot fire aircraft guns")
		app._close_cheats()
		app._open_orders()
		no_local_shot(app, "Order cards prevent accidental mouse gunfire")
		app._close_modal()
		plane.set_controls_enabled(false)
		no_local_shot(app, "An aircraft with disabled owner controls cannot fire")
		plane.set_controls_enabled(true)
		plane.owner_peer_id = 9
		no_local_shot(app, "Another courier's aircraft cannot be used to fire locally")
		plane.owner_peer_id = 0
		plane.global_position.y = 1.99
		no_local_shot(app, "Local guns remain disabled below the airborne combat boundary")
		plane.global_position.y = 25.0
		plane.set_combat_health(0)
		no_local_shot(app, "A destroyed aircraft cannot keep shooting while awaiting removal")
		plane.set_combat_health(100)
		plane.set_occupied(false)
		no_local_shot(app, "An unoccupied aircraft cannot fire through a retained rider reference")
		plane.set_occupied(true)
		plane.set_controls_enabled(true)

		app.player.set_mouse_captured(false)
		var before_capture: int = int(app._solo_aircraft_shot_id)
		app._input(click_event(true))
		check(int(app._solo_aircraft_shot_id) == before_capture and not app._aircraft_fire_armed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "The first click recaptures the pointer without firing or arming held fire")
		app._input(click_event(false))
		app._last_aircraft_fire_msec = -1000
		app._input(click_event(true))
		check(int(app._solo_aircraft_shot_id) == before_capture + 1 and app._aircraft_fire_armed and app.combat_effects.active_effect_count() > 0, "A subsequent gameplay click creates a real visible shot and arms continuous fire")
		check(int(app.audio_manager.debug_state()["event_counts"].get("aircraft_fire", 0)) > 0, "A confirmed local shot plays the aircraft fire sound")
		Input.action_press("aircraft_fire")
		app._update_aircraft_fire()
		check(int(app._solo_aircraft_shot_id) == before_capture + 1, "Held input cannot create a second shot in the same cooldown")
		app._last_aircraft_fire_msec -= Rules.COOLDOWN_MSEC
		app._update_aircraft_fire()
		check(int(app._solo_aircraft_shot_id) == before_capture + 2, "Holding the mouse creates another shot after the local firing interval")
		Input.action_release("aircraft_fire")
		app._input(click_event(false))
		check(not app._aircraft_fire_armed, "Releasing the mouse disarms automatic fire")
	else:
		no_local_shot(app, "Headless visible-pointer mode prevents gunfire without a captured mouse")

	# Inject confirmed event fixtures at the presentation boundary. Real Host
	# targeting and damage are independently tested above and over ENet.
	app.combat_effects.clear_effects()
	app._upsert_vehicle(9, {"owner_id": 9, "type": "airplane", "position": Vector3(0.0, 25.0, -10.0), "yaw": 0.0, "occupied": true, "generation": 10, "health": 75}, true)
	app.vehicles[9].set_physics_process(false)
	var event: Dictionary = {"type": "aircraft_shot", "shot_id": int(app._last_aircraft_shot_id) + 1, "shooter_id": 0,
		"shooter_generation": int(plane.get_meta("generation", 0)), "target_generation": 10,
		"from": Rules.muzzle(plane.global_position, plane.rotation.y), "to": Vector3(0.0, 26.25, -8.0),
		"hit_id": 9, "health": 50, "destroyed": false, "target_position": Vector3(0.0, 25.0, -10.0)}
	var stale_shooter: Dictionary = event.duplicate(true)
	stale_shooter["shooter_generation"] = int(event["shooter_generation"]) - 1
	app._display_aircraft_shot(stale_shooter)
	check(int(app.vehicles[9].combat_health) == 75 and app.combat_effects.active_effect_count() == 0, "A delayed shot from an older shooter generation cannot create new hit presentation")
	app._display_aircraft_shot(event)
	check(int(app.vehicles[9].combat_health) == 50 and app.combat_effects.active_effect_count() == 1, "A confirmed hit updates the correct aircraft health and one visual effect")
	var fire_count: int = int(app.audio_manager.debug_state()["event_counts"].get("aircraft_fire", 0))
	var hit_count: int = int(app.audio_manager.debug_state()["event_counts"].get("aircraft_hit", 0))
	app._display_aircraft_shot(event)
	check(app.combat_effects.active_effect_count() == 1 and int(app.audio_manager.debug_state()["event_counts"].get("aircraft_fire", 0)) == fire_count and int(app.audio_manager.debug_state()["event_counts"].get("aircraft_hit", 0)) == hit_count, "Replaying a confirmed shot does not duplicate effects, sound or damage feedback")
	check(hit_count > 0, "A local confirmed hit plays its separate impact sound")
	event["shot_id"] = int(event["shot_id"]) + 1
	event["target_generation"] = 9
	event["health"] = 0
	event["destroyed"] = true
	app._display_aircraft_shot(event)
	check(app.vehicles.has(9) and int(app.vehicles[9].get_meta("generation", 0)) == 10 and int(app.vehicles[9].combat_health) == 50, "A delayed destruction event cannot remove or damage a newer replacement aircraft")
	event["shot_id"] = int(event["shot_id"]) + 1
	event["target_generation"] = 10
	app._display_aircraft_shot(event)
	check(not app.vehicles.has(9) and int(app._vehicle_generation_floor.get(9, 0)) == 11, "Current-generation shootdown removes the old aircraft and establishes a lifecycle floor")
	app._upsert_vehicle(9, {"owner_id": 9, "type": "airplane", "position": Vector3.ZERO, "generation": 10, "health": 100}, true)
	check(not app.vehicles.has(9), "A late vehicle snapshot cannot resurrect the shot-down aircraft")
	app._upsert_vehicle(9, {"owner_id": 9, "type": "airplane", "position": Vector3.ZERO, "generation": 11, "health": 100}, true)
	check(app.vehicles.has(9) and int(app.vehicles[9].combat_health) == 100, "A genuinely new aircraft generation is accepted with restored health")
	app.vehicles[9].set_physics_process(false)

	app.combat_effects.clear_effects()
	for index: int in range(40):
		app.combat_effects.show_shot(event)
	check(app.combat_effects.active_effect_count() <= 24 and app.combat_effects.get_child_count() <= 24, "A burst of repeated combat effects uses a bounded reusable pool")
	for index: int in range(30):
		app.combat_effects._process(0.1)
	check(app.combat_effects.active_effect_count() == 0 and not app.combat_effects.is_processing(), "Every tracer and falling wreck expires and the idle updater stops")
	app.combat_effects.show_shot(event)
	app.combat_effects.clear_effects()
	check(app.combat_effects.active_effect_count() == 0, "Session cleanup immediately hides all active combat effects")
	# Transport is deliberately replaced by an in-memory receive-context fixture
	# for these event handlers; the separate LAN suite verifies actual packets.
	app.lan_session.role = "client"
	app.lan_session.local_id = 0
	app.lan_session.phase = "playing"
	app.lan_session.session_id = "receive-context"
	app.lan_session.members = {0: {"name": "Local"}, 9: {"name": "Remote"}}
	var pilot_position: Vector3 = app.player.global_position
	var current_generation: int = int(plane.get_meta("generation", 0))
	app._on_lan_event({"type": "aircraft_recovery", "session_id": "old-session", "generation": current_generation + 10, "position": Vector3.ZERO})
	check(app.vehicles.has(0) and app.player.global_position.is_equal_approx(pilot_position), "A recovery event from another session cannot remove the current plane or move its pilot")
	app._on_lan_event({"type": "aircraft_recovery", "session_id": "receive-context", "generation": current_generation - 1, "position": Vector3.ZERO})
	check(app.vehicles.has(0) and int(app.vehicles[0].get_meta("generation", 0)) == current_generation and app.player.global_position.is_equal_approx(pilot_position), "An older recovery event cannot remove a newer current plane or reset its pilot")
	app._spawn_remote_player(9, "Remote", Vector3(10.0, 12.0, 10.0), 1)
	app.remote_players[9].set_physics_process(false)
	var remote_position: Vector3 = app.remote_players[9].global_position
	app._on_lan_pose(9, {"position": Vector3.ZERO, "yaw": 0.0, "velocity": Vector3.ZERO, "grounded": true, "active_vehicle": "walking", "vehicle": {}, "vehicle_generation": 10})
	check(app.vehicles.has(9) and int(app.vehicles[9].get_meta("generation", 0)) == 11 and app.remote_players[9].global_position.is_equal_approx(remote_position), "An old on-foot correction cannot remove a remote replacement plane or move its courier")
	app._on_lan_pose(9, {"position": Vector3.ZERO, "yaw": 0.0, "velocity": Vector3.ZERO, "grounded": true, "active_vehicle": "walking", "vehicle": {}, "vehicle_generation": 12})
	check(not app.vehicles.has(9) and int(app._vehicle_generation_floor.get(9, 0)) == 12, "A current on-foot correction removes the old remote plane normally")
	app._on_lan_event({"type": "aircraft_recovery", "session_id": "receive-context", "generation": current_generation + 1, "position": Placement.GARAGE_POSITION + Vector3.UP * 0.15})
	check(not app.vehicles.has(0) and not app.player.is_riding() and app.player.global_position.distance_to(Placement.GARAGE_POSITION) < 0.5, "A current recovery event removes the local plane before safely correcting its courier to the garage")
	app.lan_session.role = "offline"
	app.lan_session.phase = "offline"
	app.lan_session.members.clear()
	check(app.profile == profile_before and app.test_mode, "Input, presentation and combat feedback preserve career data with saving disabled")
	app.queue_free()
	await process_frame
