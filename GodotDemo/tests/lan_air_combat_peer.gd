extends SceneTree

# Real ENet integration. Only the opening career, garage approaches and air
# formation are guarded fixtures. Purchases, requests, damage, events, recovery
# and persistence use production code on two separate processes.
const Placement = preload("res://scripts/vehicle_placement.gd")
var app
var role: String = ""
var coord: String = ""
var data_path: String = ""
var latest_snapshot: Dictionary = {}
var shots: Array[Dictionary] = []
var recoveries: int = 0
var checks: int = 0
var failures: Array[String] = []
var deadline_msec: int = 0
var purchased_profile: Variant

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func flag(name: String, value: String = "ok") -> void:
	var file := FileAccess.open(coord.path_join(name), FileAccess.WRITE)
	check(file != null, "Coordination marker opens: " + name)
	if file != null:
		file.store_string(value)
		file.close()

func wait_for(condition: Callable, seconds: float = 12.0) -> bool:
	var until: int = mini(deadline_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await process_frame
		OS.delay_msec(17)
	return false

func wait_flag(name: String) -> bool:
	var received: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join(name)))
	check(received, "Other process confirms " + name)
	return received

func json_value(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func role_path(path: String) -> bool:
	if not path.is_absolute_path() or not path.simplify_path().begins_with("/tmp/"):
		return false
	var matched: bool = false
	var other: String = "client" if role == "host" else "host"
	for part: String in path.simplify_path().split("/"):
		if part == role or part.begins_with(role + "-") or part.begins_with(role + "_"):
			matched = true
		if part == other or part.begins_with(other + "-") or part.begins_with(other + "_"):
			return false
	return matched

func _timeout() -> void:
	check(false, "Two-peer air combat exceeded its ninety-second deadline")
	print("LAN_AIR_COMBAT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--coord="):
			coord = arg.trim_prefix("--coord=")
	data_path = OS.get_environment("XDG_DATA_HOME").simplify_path()
	var config_path: String = OS.get_environment("XDG_CONFIG_HOME").simplify_path()
	if not args.has("--test-mode") or not args.has("--isolated-save") or role not in ["host", "client"] or OS.get_environment("DELIVERY_TEAM_TEST_SAVE") != "1" or not role_path(data_path) or not role_path(config_path) or data_path == config_path or not coord.is_absolute_path() or not coord.simplify_path().begins_with("/tmp/"):
		printerr("LAN air combat refused: test-mode, isolated-save, sentinel, shared /tmp coord and separate role-specific temporary XDG data/config paths are required")
		quit(2)
		return
	coord = coord.simplify_path()
	deadline_msec = Time.get_ticks_msec() + 90000
	create_timer(90.0).timeout.connect(_timeout)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var isolated: bool = app.test_mode and user_path.begins_with(data_path.trim_suffix("/") + "/")
	check(isolated, "Production user path is inside its role-specific temporary directory")
	if not isolated or FileAccess.file_exists(app.SAVE_PATH) or FileAccess.file_exists(app.SAVE_PATH + ".tmp") or FileAccess.file_exists(app.SAVE_PATH + ".backup"):
		check(false, "Combat save fixture requires a fresh isolated destination")
		await finish()
		return
	app.test_mode = false
	app.profile["player_name"] = "Air combat " + role.capitalize()
	app.profile["money"] = 60000
	app.profile["xp"] = 7350
	app.profile["level"] = 8
	app.profile["rank"] = "Express Pro"
	app.profile["owned_vehicles"] = []
	app.profile["selected_vehicle"] = ""
	check(app._save_profile(), "Opening level-eight career uses normal atomic JSON save")
	app.lan_session.state_received.connect(func(data: Dictionary) -> void: latest_snapshot = data.duplicate(true))
	app.lan_session.event_received.connect(func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "aircraft_shot":
			shots.append(event.duplicate(true))
		elif str(event.get("type", "")) == "aircraft_recovery":
			recoveries += 1)
	if role == "host":
		await run_host()
	else:
		await run_client()
	await finish()

func vehicle_for(peer_id: int) -> Dictionary:
	for entry: Dictionary in latest_snapshot.get("vehicles", []):
		if int(entry.get("owner_id", 0)) == peer_id:
			return entry
	return {}

func saved_profile(label: String) -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.SAVE_PATH))
	check(saved is Dictionary and saved == json_value(app.profile), label + " confirmed profile matches the complete atomic save")
	check(not FileAccess.file_exists(app.SAVE_PATH + ".tmp"), label + " leaves no unfinished atomic save")

func freeze_formation() -> void:
	# Freeze only the fixture pilots' automatic pose loop and physical motion.
	# Signals/RPC transport, authority clock, effects and snapshot handlers stay on.
	app.set_process(false)
	app.player.set_physics_process(false)
	for plane in app.vehicles.values():
		plane.set_physics_process(false)

func garage_fixture(client_id: int) -> void:
	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(2.0, 0.15, -2.0))
	app.lan_authority.records[1]["position"] = app.player.global_position
	var client: Dictionary = app.lan_authority.records[client_id]
	client["position"] = Placement.GARAGE_POSITION + Vector3(-2.0, 0.15, 2.0)
	client["velocity"] = Vector3.ZERO
	client["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._correct_position(client_id)
	app.lan_authority._mark_changed()

func air_fixture(peer_id: int, position: Vector3, yaw: float) -> void:
	var record: Dictionary = app.lan_authority.records[peer_id]
	var vehicle: Dictionary = record["vehicle"]
	vehicle["position"] = position
	vehicle["yaw"] = yaw
	vehicle["velocity"] = Vector3.ZERO
	vehicle["grounded"] = false
	vehicle["occupied"] = true
	record["position"] = position
	record["yaw"] = yaw
	record["velocity"] = Vector3.ZERO
	record["grounded"] = false
	record["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._advance_vehicle_generation(record)
	app.lan_authority._emit_vehicle_state(peer_id)

func formation_fixture(client_id: int) -> void:
	# Central road is an unobstructed line at 32m, with two independent owned
	# production models. Horizontal guns face one another at equal altitude.
	air_fixture(1, Vector3(0.0, 32.0, -18.0), PI)
	air_fixture(client_id, Vector3(0.0, 32.0, 18.0), 0.0)
	app.lan_authority._mark_changed()
	freeze_formation()

func fire() -> void:
	var vehicle: Dictionary = vehicle_for(app.lan_session.local_id)
	check(not vehicle.is_empty(), role + " still has its own firing aircraft")
	if not vehicle.is_empty():
		app.lan_session.request_action("aircraft_fire", {"generation": int(vehicle["generation"])})

func run_host() -> void:
	app._host_lan(str(app.profile["player_name"]), "Air combat integration", 4, 600)
	check(app.lan_session.phase == "lobby", "Host creates the production ENet lobby")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Real Client completes registration and Ready handshake")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	if not await wait_flag("client-started"):
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-started")))
	garage_fixture(client_id)
	app._buy_vehicle("airplane")
	check(app.profile["owned_vehicles"].has("airplane") and int(app.profile["money"]) == 30000, "Host independently buys an airplane for exactly 30000 tenge")
	purchased_profile = json_value(app.profile)
	flag("garage-ready")
	if not await wait_flag("client-bought"):
		return
	var client_profile: Dictionary = app.lan_authority.get_profile(client_id)
	check(client_profile["owned_vehicles"].has("airplane") and int(client_profile["money"]) == 30000, "Host independently confirms Client's own plane and exact purchase charge")
	freeze_formation()
	formation_fixture(client_id)
	flag("first-formation")
	if not await wait_flag("client-first-shot"):
		return
	var first_hit: bool = await wait_for(func() -> bool: return int(vehicle_for(1).get("health", 0)) == 75)
	check(first_hit and app.player.riding_vehicle.combat_health == 75, "Host snapshot and real local aircraft both show Client's confirmed 25-damage hit")
	check(shots.size() == 1 and int(shots[0].get("hit_id", 0)) == 1, "Malformed/stale requests and same-tick spam produce only one real hit event")
	flag("first-hit-verified")
	if not await wait_flag("client-victory"):
		return
	var recovered: bool = await wait_for(func() -> bool: return recoveries == 1 and not app.player.is_riding() and not app.vehicles.has(1))
	check(recovered and app.player.global_position.y < 1.0, "Client can shoot down Host; production recovery removes plane and places courier safely on the street")
	check(json_value(app.profile) == purchased_profile, "Being shot down preserves Host's complete career, money and aircraft ownership")
	check(int(latest_snapshot.get("air_combat", {}).get("losses", 0)) == 1, "Host sees its confirmed session air loss")
	check(int(app.lan_authority.snapshot_for(client_id).get("air_combat", {}).get("kills", 0)) == 1, "Host confirms the Client earned one air kill without delivery rewards")
	saved_profile("Host recovery")
	var old_generation: int = int(app.lan_authority.records[1].get("vehicle_generation", 0))
	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(2.0, 0.15, -2.0))
	app.lan_authority.records[1]["position"] = app.player.global_position
	app._spawn_vehicle("airplane")
	check(app.vehicles.has(1) and int(app.profile["money"]) == 30000 and int(vehicle_for(1).get("health", 0)) == 100, "Owned aircraft can be respawned through the real garage for free with full health")
	check(int(vehicle_for(1).get("generation", 0)) > old_generation, "Replacement aircraft has a new authoritative generation")
	formation_fixture(client_id)
	flag("second-formation")
	if not await wait_flag("client-second-ready"):
		return
	fire()
	if not await wait_flag("client-return-hit"):
		return
	for index: int in range(3):
		await create_timer(0.28).timeout
		fire()
	var client_lost: bool = await wait_for(func() -> bool: return app.lan_authority.records[client_id]["vehicle"].is_empty())
	check(client_lost and not app.vehicles.has(client_id), "Host can also shoot down Client and remove the replicated aircraft")
	check(int(latest_snapshot.get("air_combat", {}).get("kills", 0)) == 1 and int(latest_snapshot.get("air_combat", {}).get("losses", 0)) == 1, "Host's session combat counters show one kill and one loss")
	check(int(app.profile["total_deliveries"]) == 0 and int(app.profile["total_money_earned"]) == 0 and int(app.profile["xp"]) == 7350, "Air combat does not forge delivery statistics, money or XP")
	check(shots.size() == 8 and shots.filter(func(event: Dictionary) -> bool: return bool(event.get("destroyed", false))).size() == 2, "Both peers receive eight unique shots and exactly two shootdowns")
	flag("host-victory")
	if not await wait_flag("client-all-verified"):
		return
	app._leave_lan()
	flag("host-disconnected")
	if not await wait_flag("client-reloaded"):
		return
	await reload_profile()

func run_client() -> void:
	if not await wait_flag("host-ready"):
		return
	app._join_lan(str(app.profile["player_name"]), "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client joins a real loopback ENet connection")
	if not connected:
		return
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not latest_snapshot.is_empty())
	check(started, "Client receives the production authoritative shift snapshot")
	if not started:
		return
	app._close_modal()
	flag("client-started", str(app.lan_session.local_id))
	if not await wait_flag("garage-ready"):
		return
	check(await wait_for(func() -> bool: return app._near_garage()), "Client's fixture approach reaches the physical garage")
	app._buy_vehicle("airplane")
	var bought: bool = await wait_for(func() -> bool: return app.profile["owned_vehicles"].has("airplane") and app.vehicles.has(app.lan_session.local_id))
	check(bought and int(app.profile["money"]) == 30000, "Client buys its own independent airplane through real Host-confirmed RPC")
	purchased_profile = json_value(app.profile)
	saved_profile("Client purchase")
	freeze_formation()
	flag("client-bought")
	if not await wait_flag("first-formation"):
		return
	var airborne: bool = await wait_for(func() -> bool: return app.player.is_riding() and float(vehicle_for(app.lan_session.local_id).get("position", Vector3.ZERO).y) > 2.0)
	check(airborne and app.vehicles.has(1), "Client sees both independently owned piloted airplanes in the airborne formation")
	freeze_formation()
	var generation: int = int(vehicle_for(app.lan_session.local_id).get("generation", 0))
	app.lan_session.request_action("aircraft_fire", {"generation": generation, "damage": 100000, "target_id": 1})
	app.lan_session.request_action("aircraft_fire", {"generation": generation - 1})
	fire()
	for index: int in range(10):
		app.lan_session.request_action("aircraft_fire", {"generation": generation})
	flag("client-first-shot")
	if not await wait_flag("first-hit-verified"):
		return
	check(int(vehicle_for(1).get("health", 0)) == 75 and app.vehicles[1].combat_health == 75, "Client sees the same confirmed remote HP75 after actual shooting")
	check(shots.size() == 1 and int(shots[0].get("shooter_id", 0)) == app.lan_session.local_id, "Client receives its Host-approved hit event once")
	for index: int in range(3):
		await create_timer(0.28).timeout
		fire()
	var host_down: bool = await wait_for(func() -> bool: return vehicle_for(1).is_empty() and not app.vehicles.has(1))
	check(host_down and int(latest_snapshot.get("air_combat", {}).get("kills", 0)) == 1, "Client's fourth confirmed hit shoots down Host and increments its session air kill")
	check(json_value(app.profile) == purchased_profile, "Shooting down another courier gives no unauthorized career money or XP")
	flag("client-victory")
	if not await wait_flag("second-formation"):
		return
	check(await wait_for(func() -> bool: return not vehicle_for(1).is_empty() and int(vehicle_for(1).get("health", 0)) == 100), "Client sees Host's free replacement airplane with full HP")
	freeze_formation()
	flag("client-second-ready")
	check(await wait_for(func() -> bool: return int(vehicle_for(app.lan_session.local_id).get("health", 0)) == 75), "Return fire from Host damages the actual Client aircraft")
	check(app.player.riding_vehicle.combat_health == 75, "Client local model uses confirmed health rather than a client-side damage claim")
	flag("client-return-hit")
	if not await wait_flag("host-victory"):
		return
	check(await wait_for(func() -> bool: return recoveries == 1 and not app.player.is_riding() and not app.vehicles.has(app.lan_session.local_id)), "Client shootdown is recovered by the Host while gameplay remains active")
	check(app.player.global_position.y < 1.0 and app.state == "playing", "Recovered Client is safely on foot in the continuing city session")
	check(json_value(app.profile) == purchased_profile, "Client recovery preserves every confirmed career field and aircraft ownership")
	check(await wait_for(func() -> bool: return int(latest_snapshot.get("air_combat", {}).get("kills", 0)) == 1 and int(latest_snapshot.get("air_combat", {}).get("losses", 0)) == 1), "Client's confirmed session counters show one kill and one loss")
	check(shots.size() == 8 and shots.filter(func(event: Dictionary) -> bool: return bool(event.get("destroyed", false))).size() == 2, "Client receives the same eight shots and two shootdown events")
	saved_profile("Client recovery")
	flag("client-all-verified")
	if not await wait_flag("host-disconnected"):
		return
	check(await wait_for(func() -> bool: return app.state == "menu" and not app._lan_active()), "Host departure cleanly returns Client to the main menu after combat")
	await reload_profile()
	flag("client-reloaded")

func reload_profile() -> void:
	var confirmed: Variant = json_value(app.profile)
	saved_profile(role + " disconnect")
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var safe: bool = app.test_mode and user_path.begins_with(data_path.trim_suffix("/") + "/") and OS.get_environment("DELIVERY_TEAM_TEST_SAVE") == "1"
	check(safe, "Fresh instance retains verified isolated-save protection")
	if safe:
		app.test_mode = false
		app.profile = app._load_profile()
		check(json_value(app.profile) == confirmed and app.profile["owned_vehicles"].has("airplane"), "Production loader restores the complete purchased aircraft career after air combat")

func finish() -> void:
	if is_instance_valid(app):
		app._leave_lan()
		app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LAN_AIR_COMBAT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
