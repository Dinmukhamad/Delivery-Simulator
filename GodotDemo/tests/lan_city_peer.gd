extends SceneTree

# Two real ENet processes exercise authority and HUD beyond the old 84 m limits.
# Trusted Host setup relocates participants; all subsequent Client movement and
# delivery use the unchanged production RPC and collision/credit validation.
# This harness refuses to run without --test-mode, which disables profile writes.
var app
var role: String = ""
var coord: String = ""
var checks: int = 0
var failures: Array[String] = []

const ORDER_ID: int = 60001
const REWARD: int = 200
const DELIVERY_XP: int = 50
const CLIENT_START: Vector3 = Vector3(160.0, 0.15, 0.0)
const HOST_START: Vector3 = Vector3(160.0, 0.15, -2.0)
const DELIVERY_TARGET: Vector3 = Vector3(160.0, 0.0, 5.0)

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func flag(name: String, value: String = "ok") -> void:
	var file: FileAccess = FileAccess.open(coord.path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func wait_for(condition: Callable, seconds: float = 20.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
		# Headless processes must advance at human gameplay speed, not unbounded FPS.
		OS.delay_msec(17)
	return false

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("LAN city regression requires --test-mode")
		quit(2)
		return
	for arg: String in args:
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		if arg.begins_with("--coord="):
			coord = arg.trim_prefix("--coord=")
	if role not in ["host", "client"] or coord.is_empty():
		quit(2)
		return
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	if role == "host":
		await run_host()
	else:
		await run_client()
	Input.action_release("move_forward")
	if is_instance_valid(app):
		app._leave_lan()
		app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LAN_CITY_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func run_host() -> void:
	app._host_lan("City Host", "Expanded city integration", 4, 600)
	check(app.lan_session.phase == "lobby", "Host creates an ordinary competitive LAN room")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Client connects and readies the lobby")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and FileAccess.file_exists(coord.path_join("client-started")))
	check(started, "Both processes load the same expanded city")
	if not started:
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-started")))
	var host_money: int = int(app.profile["money"])
	var host_xp: int = int(app.profile["xp"])
	var client_money: int = int(app.lan_authority.get_profile(client_id)["money"])
	var client_xp: int = int(app.lan_authority.get_profile(client_id)["xp"])

	# Trusted fixture only. A Client never requests a teleport, reward or order.
	# The production correction event seeds its physical body in the new district.
	app.player.reset_at(HOST_START)
	app.lan_authority.records[1]["position"] = HOST_START
	app.lan_authority.records[1]["velocity"] = Vector3.ZERO
	app.lan_authority.records[client_id]["position"] = CLIENT_START
	app.lan_authority.records[client_id]["velocity"] = Vector3.ZERO
	app.lan_authority.records[client_id]["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._correct_position(client_id)
	app.lan_authority._mark_changed()
	var far_positioned: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("far-positioned")))
	check(far_positioned, "Client applies the normal Host correction beyond the former city bounds")
	if not far_positioned:
		return

	# A prepared parcel avoids a long cross-city approach in CI. Delivery itself
	# still requires validated physical Client movement and a server interaction.
	var parcel: Dictionary = app.lan_authority.orders[0].duplicate(true)
	parcel.merge({"id": ORDER_ID, "owner_id": client_id, "state": "PickedUp", "type": "standard", "required_level": 1, "title": "Expanded city parcel", "reward": REWARD, "base_reward": REWARD, "xp": DELIVERY_XP, "time_limit": 60.0, "pickup_position": CLIENT_START, "delivery_position": DELIVERY_TARGET}, true)
	app.lan_authority.records[client_id]["active_order"] = parcel
	app.lan_authority.records[client_id]["carrying"] = true
	app.lan_authority._mark_changed()
	var delivered: bool = await wait_for(func() -> bool: return int(app.lan_authority.records[client_id]["shift_stats"]["deliveries"]) == 1 and FileAccess.file_exists(coord.path_join("client-delivered")))
	check(delivered, "Client movement and E interaction complete a delivery in the added district")
	if not delivered:
		return
	var confirmed_position: Vector3 = app.lan_authority.records[client_id]["position"]
	check(confirmed_position.x > 150.0 and confirmed_position.z >= 2.0, "Host accepts actual Client movement beyond the old 84 m limit")
	check(int(app.lan_authority.get_profile(client_id)["money"]) == client_money + REWARD and int(app.lan_authority.get_profile(client_id)["xp"]) == client_xp + DELIVERY_XP, "Host awards the exact personal delivery reward")
	check(int(app.profile["money"]) == host_money and int(app.profile["xp"]) == host_xp and not app.lan_authority._team_enabled, "Competitive delivery grants no Host reward or accidental team bonus")
	check(app.active_order.is_empty() and app.hud._mini_map.route_points.is_empty(), "Client's private route is never assigned to the Host")
	flag("host-verified")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left, "Client disconnect removes the LAN participant")
	check(app.state == "playing" and app.remote_players.is_empty(), "Host continues its shift with the disconnected avatar removed")

func run_client() -> void:
	app._join_lan("City Client", "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client connects by local IPv4")
	if not connected:
		return
	check(str(app.lan_session.lobby_config.get("shift_mode", "")) == "competitive", "Default room mode remains competitive")
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not app.orders.is_empty())
	check(started, "Client receives the server's shared orders")
	if not started:
		return
	app._close_modal()
	var base_money: int = int(app.profile["money"])
	var base_xp: int = int(app.profile["xp"])
	flag("client-started", str(app.lan_session.local_id))
	var far_positioned: bool = await wait_for(func() -> bool: return absf(app.player.global_position.x - CLIENT_START.x) < 0.25 and absf(app.player.global_position.z - CLIENT_START.z) < 0.25 and app.hud._mini_map.player_position.x > 150.0)
	check(far_positioned, "Client body and minimap follow the confirmed far-district position")
	if not far_positioned:
		return
	var bounds: Rect2 = app.hud._full_map.layout.get("bounds", Rect2())
	check(bounds.size.is_equal_approx(Vector2(516.0, 516.0)) and bounds.has_point(Vector2(160.0, 5.0)), "Both far player and destination fit within the expanded 516 m map")
	var map_area: Rect2 = app.hud._mini_map._map_rect()
	var mapped_player: Vector2 = app.hud._mini_map._point(app.player.global_position)
	check(map_area.has_point(mapped_player) and mapped_player.x < map_area.end.x - 2.0, "Far-district player marker is inside the map rather than clamped to its border")
	flag("far-positioned")
	var parcel_received: bool = await wait_for(func() -> bool: return int(app.active_order.get("id", 0)) == ORDER_ID and app.active_order.get("state", "") == "PickedUp")
	check(parcel_received, "Client receives its Host-confirmed parcel ownership")
	if not parcel_received:
		return
	check(app.player.is_carrying and app.hud._full_map.target_picked and app.hud._full_map.target_position.is_equal_approx(DELIVERY_TARGET) and not app.hud._mini_map.route_points.is_empty(), "Far delivery shows its parcel, delivery marker and usable route")
	var host_visible: bool = await wait_for(func() -> bool:
		if not app.remote_players.has(1):
			return false
		var position: Vector3 = app.remote_players[1].global_position
		return position.x > 150.0 and app.hud._mini_map.other_players.size() == 1)
	check(host_visible, "Real Host pose and peer marker are visible in the added district")
	if not host_visible:
		return
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var direction: Vector3 = DELIVERY_TARGET - app.player.global_position
		direction.y = 0.0
		if direction.length() <= 1.5:
			break
		app.player.set_view_direction(atan2(-direction.x, -direction.z))
		Input.action_press("move_forward")
		await process_frame
		OS.delay_msec(17)
	Input.action_release("move_forward")
	await physics_frame
	app._interact()
	var delivered: bool = await wait_for(func() -> bool: return app.active_order.is_empty() and int(app.shift_stats.get("deliveries", 0)) == 1)
	check(delivered, "Real WASD movement and E produce server-confirmed completion")
	if not delivered:
		return
	check(int(app.profile["money"]) == base_money + REWARD and int(app.profile["xp"]) == base_xp + DELIVERY_XP, "Client receives only the exact confirmed personal money and XP")
	check(not app.player.is_carrying and not app.hud._full_map.has_target and app.hud._mini_map.route_points.is_empty(), "Completed parcel and both map goals clear")
	flag("client-delivered")
	var verified: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("host-verified")))
	check(verified, "Host independently verifies the far delivery before Client leaves")
	app._leave_lan()
