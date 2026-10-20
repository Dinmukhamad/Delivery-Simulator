extends SceneTree

# Two real ENet peers. Writes are enabled only after a verified fresh,
# role-specific /tmp XDG save directory and the explicit fixture sentinel.
const Placement = preload("res://scripts/vehicle_placement.gd")
var app
var role: String = ""
var coord: String = ""
var data_path: String = ""
var latest_snapshot: Dictionary = {}
var corrections: int = 0
var checks: int = 0
var failures: Array[String] = []
var deadline_msec: int = 0

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
	check(false, "Two-peer aircraft regression exceeded eighty seconds")
	print("LAN_AIRCRAFT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
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
		printerr("LAN aircraft refused: test-mode, isolated-save, fixture sentinel, shared /tmp coord and separate role-specific /tmp XDG data/config paths are required")
		quit(2)
		return
	coord = coord.simplify_path()
	deadline_msec = Time.get_ticks_msec() + 80000
	create_timer(80.0).timeout.connect(_timeout)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var isolated: bool = app.test_mode and user_path.begins_with(data_path.trim_suffix("/") + "/")
	check(isolated, "Fixture verifies the production user path is inside its role-specific temporary directory")
	if not isolated or FileAccess.file_exists(app.SAVE_PATH) or FileAccess.file_exists(app.SAVE_PATH + ".tmp") or FileAccess.file_exists(app.SAVE_PATH + ".backup"):
		check(false, "Aircraft save fixture requires a fresh isolated destination")
		await finish()
		return
	app.test_mode = false
	app.profile["player_name"] = "Aircraft " + role.capitalize()
	app.profile["money"] = 60000
	app.profile["xp"] = 7350
	app.profile["level"] = 8
	app.profile["rank"] = "Express Pro"
	app.profile["owned_vehicles"] = []
	app.profile["selected_vehicle"] = ""
	check(app._save_profile(), "Initial level-eight fixture uses normal atomic JSON save")
	app.lan_session.state_received.connect(func(data: Dictionary) -> void: latest_snapshot = data.duplicate(true))
	app.lan_session.event_received.connect(func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "correction":
			corrections += 1)
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
	check(saved is Dictionary and saved == json_value(app.profile), label + " atomic save matches every confirmed profile field")
	check(not FileAccess.file_exists(app.SAVE_PATH + ".tmp"), label + " leaves no unfinished atomic save")

func garage_fixture(client_id: int) -> void:
	# Only initial approaches are trusted setup. Purchases, mounts and every
	# subsequent flight pose travel through the ordinary production RPC paths.
	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(2.0, 0.15, -2.0))
	app.lan_authority.records[1]["position"] = app.player.global_position
	var client: Dictionary = app.lan_authority.records[client_id]
	client["position"] = Placement.GARAGE_POSITION + Vector3(-2.0, 0.15, 2.0)
	client["velocity"] = Vector3.ZERO
	client["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._correct_position(client_id)
	app.lan_authority._mark_changed()

func runway_fixture(peer_id: int, position: Vector3) -> void:
	var record: Dictionary = app.lan_authority.records[peer_id]
	var vehicle: Dictionary = record["vehicle"]
	vehicle["position"] = position
	vehicle["yaw"] = 0.0
	vehicle["velocity"] = Vector3.ZERO
	vehicle["grounded"] = true
	record["position"] = position + Vector3(0.0, 0.05, 1.0)
	record["yaw"] = 0.0
	record["velocity"] = Vector3.ZERO
	record["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._advance_vehicle_generation(record)
	app.lan_authority._emit_vehicle_state(peer_id)

func enter_and_takeoff() -> bool:
	app._close_modal()
	app._toggle_vehicle(app.lan_session.local_id)
	var entered: bool = await wait_for(func() -> bool: return app.player.is_riding())
	check(entered, role + " mounts its own grounded airplane through normal F action")
	if not entered:
		return false
	Input.action_press("jump")
	var lifted: bool = await wait_for(func() -> bool: return app.player.riding_vehicle.global_position.y > 4.0, 4.0)
	Input.action_release("jump")
	check(lifted, role + " uses stationary Space takeoff through real physics and pose RPC")
	await create_timer(0.2).timeout
	return lifted

func land_and_exit() -> bool:
	if not app.player.is_riding():
		return false
	Input.action_press("flight_descend")
	var landed: bool = await wait_for(func() -> bool: return app.player.riding_vehicle.global_position.y < 0.15 and app.player.riding_vehicle.is_on_floor(), 5.0)
	Input.action_release("flight_descend")
	check(landed, role + " lands with Ctrl through real collision physics")
	await create_timer(0.2).timeout
	app._toggle_vehicle(app.lan_session.local_id)
	var exited: bool = await wait_for(func() -> bool: return not app.player.is_riding())
	check(exited, role + " can disembark safely after landing and stopping")
	return exited

func run_host() -> void:
	app._host_lan(str(app.profile["player_name"]), "Aircraft integration", 4, 600)
	check(app.lan_session.phase == "lobby", "Host creates an ordinary actual ENet lobby")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Client completes production registration and Ready handshake")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	if not await wait_flag("client-started"):
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-started")))
	garage_fixture(client_id)
	app._buy_vehicle("airplane")
	check(app.profile["owned_vehicles"].has("airplane") and int(app.profile["money"]) == 30000, "Host buys its own airplane through production authoritative garage")
	flag("garage-ready")
	if not await wait_flag("client-bought"):
		return
	var client_profile: Dictionary = app.lan_authority.get_profile(client_id)
	check(client_profile["owned_vehicles"].has("airplane") and client_profile["selected_vehicle"] == "airplane" and int(client_profile["money"]) == 30000, "Host independently confirms Client purchase, selection and exact charge")
	check(int(app.profile["money"]) == 30000 and app.profile["owned_vehicles"].size() == 1, "Client purchase leaves Host inventory and money unchanged")
	runway_fixture(1, Vector3(0.0, 0.1, -10.0))
	runway_fixture(client_id, Vector3(0.0, 0.1, 10.0))
	app.lan_authority._mark_changed()
	flag("runway-ready")
	if not await wait_flag("client-airborne"):
		return
	var remote_flying: bool = await wait_for(func() -> bool: return app.vehicles.has(client_id) and app.vehicles[client_id].global_position.y > 3.0 and float(app.lan_authority.records[client_id]["position"].y) > 3.0)
	check(remote_flying and not bool(app.lan_authority.records[client_id]["grounded"]), "Host validates and renders Client airborne plane with an airborne authoritative pose")
	check(app._other_player_map_positions().any(func(entry: Dictionary) -> bool: return int(entry.get("id", 0)) == client_id and entry.get("active_vehicle", "") == "airplane" and absf(angle_difference(float(entry.get("yaw", 0.0)), app.vehicles[client_id].rotation.y)) < 0.1), "Host minimap receives the real remote airplane type and heading")
	await enter_and_takeoff()
	flag("host-airborne")
	if not await wait_flag("client-finished"):
		return
	var client_record: Dictionary = app.lan_authority.records[client_id]
	check(not bool(client_record["vehicle"]["occupied"]) and float(client_record["position"].y) < 0.7, "Host independently confirms Client landed before exiting")
	check(int(client_record["profile"]["money"]) == 30000 and int(client_record["profile"]["total_deliveries"]) == 0, "Flying and malicious pose rejection grant no delivery rewards")
	await land_and_exit()
	saved_profile("Host airplane purchase")
	flag("host-verified")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left, "Client disconnect preserves the running Host shift")
	if not await wait_flag("client-reloaded"):
		return
	await disconnect_and_reload()

func malicious_pose(changes: Dictionary, label: String) -> void:
	var before: int = corrections
	var payload: Dictionary = app._network_pose()
	payload.merge(changes, true)
	app.lan_session.send_pose(payload)
	var rejected: bool = await wait_for(func() -> bool: return corrections > before)
	check(rejected and app.player.is_riding() and app.player.riding_vehicle.global_position.y < 60.0, label + " receives a real Host correction without leaving the airplane")

func run_client() -> void:
	if not await wait_flag("host-ready"):
		return
	app._join_lan(str(app.profile["player_name"]), "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client joins through actual loopback ENet")
	if not connected:
		return
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not latest_snapshot.is_empty())
	check(started, "Client receives the ordinary authoritative shift snapshot")
	if not started:
		return
	app._close_modal()
	flag("client-started", str(app.lan_session.local_id))
	if not await wait_flag("garage-ready"):
		return
	var at_garage: bool = await wait_for(func() -> bool: return app._near_garage())
	check(at_garage, "Host fixture corrects Client to the physical Garage")
	app._buy_vehicle("airplane")
	var bought: bool = await wait_for(func() -> bool: return app.profile["owned_vehicles"].has("airplane") and app.vehicles.has(app.lan_session.local_id))
	check(bought and int(app.profile["money"]) == 30000 and app.profile["selected_vehicle"] == "airplane", "Client garage waits for Host-confirmed airplane inventory and selection")
	saved_profile("Client confirmed airplane purchase")
	flag("client-bought")
	if not await wait_flag("runway-ready"):
		return
	await enter_and_takeoff()
	flag("client-airborne")
	if not await wait_flag("host-airborne"):
		return
	var host_flying: bool = await wait_for(func() -> bool: return app.vehicles.has(1) and app.vehicles[1].global_position.y > 3.0)
	check(host_flying, "Client renders Host's airborne plane through ordinary replication")
	check(app._other_player_map_positions().any(func(entry: Dictionary) -> bool: return int(entry.get("id", 0)) == 1 and entry.get("active_vehicle", "") == "airplane" and absf(angle_difference(float(entry.get("yaw", 0.0)), app.vehicles[1].rotation.y)) < 0.1), "Client minimap receives the real Host airplane type and heading")
	app._toggle_vehicle(app.lan_session.local_id)
	await create_timer(0.25).timeout
	check(app.player.is_riding() and app.player.riding_vehicle.global_position.y > 3.0, "Actual Client F request cannot teleport an airborne courier to street level")
	var current: Vector3 = app.player.riding_vehicle.global_position
	await malicious_pose({"position": Vector3(current.x, 65.0, current.z)}, "Height-limit forgery")
	await malicious_pose({"position": current + Vector3(100.0, 0.0, 0.0)}, "Horizontal teleport forgery")
	await malicious_pose({"position": current + Vector3(0.0, 5.0, 0.0)}, "Excessive climb forgery")
	await malicious_pose({"velocity": Vector3(0.0, 99.0, 0.0)}, "Vertical velocity forgery")
	await malicious_pose({"active_vehicle": "car"}, "Wrong active-vehicle forgery")
	await malicious_pose({"vehicle_generation": 999999}, "Wrong generation forgery")
	await land_and_exit()
	saved_profile("Client after flight and rejected poses")
	flag("client-finished")
	if not await wait_flag("host-verified"):
		return
	await disconnect_and_reload()
	flag("client-reloaded")

func disconnect_and_reload() -> void:
	var confirmed: Variant = json_value(app.profile)
	app._leave_lan()
	check(json_value(app.profile) == confirmed, "Disconnect preserves the confirmed airplane profile")
	saved_profile(role + " disconnect")
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var safe: bool = app.test_mode and user_path.begins_with(data_path.trim_suffix("/") + "/") and OS.get_environment("DELIVERY_TEAM_TEST_SAVE") == "1"
	check(safe, "Fresh instance retains verified isolated save protection")
	if not safe:
		return
	app.test_mode = false
	app.profile = app._load_profile()
	check(json_value(app.profile) == confirmed and app.profile["owned_vehicles"].has("airplane") and app.profile["selected_vehicle"] == "airplane", "Production loader restores exactly the purchased and selected airplane")
	saved_profile(role + " reload")

func finish() -> void:
	for action: String in ["jump", "flight_descend", "move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)
	if is_instance_valid(app):
		app._leave_lan()
		app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LAN_AIRCRAFT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
