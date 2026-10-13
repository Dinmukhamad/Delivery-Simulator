extends SceneTree

# Two real ENet processes use the normal lobby, server order pool and E RPCs.
# CI seeds only Host simulation time and six-metre approach positions at actual
# cafe/office addresses; all Client walking and interactions remain validated.
# Profile disk writes are disabled by --test-mode in both processes.
var app
var role: String = ""
var coord: String = ""
var latest_snapshot: Dictionary = {}
var checks: int = 0
var failures: Array[String] = []

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
		OS.delay_msec(17)
	return false

func walk_to(target: Vector3) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var direction: Vector3 = target - app.player.global_position
		direction.y = 0.0
		if direction.length() <= 1.5:
			Input.action_release("move_forward")
			await physics_frame
			return true
		app.player.set_view_direction(atan2(-direction.x, -direction.z))
		Input.action_press("move_forward")
		await process_frame
		OS.delay_msec(17)
	Input.action_release("move_forward")
	return false

func real_event_order(order_id: int = 0) -> Dictionary:
	for order: Dictionary in app.orders:
		if not str(order.get("event_id", "")).is_empty() and (order_id == 0 or int(order.get("id", 0)) == order_id):
			return order.duplicate(true)
	return {}

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("LAN event regression requires --test-mode")
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
	app.lan_session.state_received.connect(func(data: Dictionary) -> void: latest_snapshot = data.duplicate(true))
	check(app.test_mode, "LAN event regression disables persistent profile writes")
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
	print("LAN_EVENT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func place_client(peer_id: int, target: Vector3) -> void:
	# Trusted fixture, never a Client request. Correction uses the existing RPC.
	var approach: Vector3 = target + Vector3(0, 0.15, -6.0)
	app.player.reset_at(approach + Vector3(2.0, 0, 0))
	app.lan_authority.records[1]["position"] = app.player.global_position
	app.lan_authority.records[1]["velocity"] = Vector3.ZERO
	app.lan_authority.records[peer_id]["position"] = approach
	app.lan_authority.records[peer_id]["velocity"] = Vector3.ZERO
	app.lan_authority.records[peer_id]["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._correct_position(peer_id)
	app.lan_authority._mark_changed()

func run_host() -> void:
	app._host_lan("Lunch Host", "District event integration", 4, 600)
	check(app.lan_session.phase == "lobby", "Host creates an ordinary LAN room")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Client completes the version-checked lobby and Ready handshake")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and FileAccess.file_exists(coord.path_join("client-started")))
	check(started, "Both processes load the same city and shift")
	if not started:
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-started")))
	var host_before: Dictionary = app.profile.duplicate(true)
	var client_before: Dictionary = app.lan_authority.get_profile(client_id)
	# Start the production schedule without waiting 45 wall-clock seconds in CI.
	app.lan_authority._started_at_msec = Time.get_ticks_msec() - 45000
	app.lan_authority._deadline_msec = app.lan_authority._started_at_msec + 600000
	app.lan_authority._advance_clock(Time.get_ticks_msec())
	var chosen: Dictionary = real_event_order()
	check(not chosen.is_empty() and latest_snapshot.get("district_event", {}).get("phase", "") == "active", "Host-generated event and extra lunch offers reach its normal snapshot")
	if chosen.is_empty():
		return
	var order_id: int = int(chosen["id"])
	var expected_bonus: int = int(floor(float(chosen["reward"]) * 0.5))
	var expected_money: int = int(chosen["reward"]) + expected_bonus
	place_client(client_id, chosen["pickup_position"])
	flag("event-order", str(order_id))
	var accepted: bool = await wait_for(func() -> bool: return int(app.lan_authority.records[client_id]["active_order"].get("id", 0)) == order_id and FileAccess.file_exists(coord.path_join("client-accepted")))
	check(accepted, "Client claims one of the actual shared cafe-to-office offers")
	if not accepted:
		return
	var confirmed: Dictionary = app.lan_authority.records[client_id]["active_order"]
	for key: String in ["reward", "xp", "event_id", "event_ends_at", "event_bonus_multiplier", "delivery_position"]:
		check(confirmed.get(key) == chosen.get(key), "Wire claim cannot forge server-owned %s" % key)
	var picked: bool = await wait_for(func() -> bool: return app.lan_authority.records[client_id]["active_order"].get("state", "") == "PickedUp" and FileAccess.file_exists(coord.path_join("client-picked")))
	check(picked, "Real Client walking and E collect the event parcel at the cafe")
	if not picked:
		return
	check(int(app.lan_authority.get_profile(client_id)["money"]) == int(client_before["money"]), "Picking up lunch never grants an early reward")
	place_client(client_id, chosen["delivery_position"])
	flag("office-approach")
	var delivered: bool = await wait_for(func() -> bool: return int(app.lan_authority.records[client_id]["shift_stats"]["deliveries"]) == 1 and FileAccess.file_exists(coord.path_join("client-delivered")))
	check(delivered, "Real Client walking and E complete the lunch at its actual office")
	if not delivered:
		return
	var client_after: Dictionary = app.lan_authority.get_profile(client_id)
	check(int(client_after["money"]) == int(client_before["money"]) + expected_money and int(client_after["xp"]) == int(client_before["xp"]) + int(chosen["xp"]), "Host computes the exact base plus 50 percent and unchanged delivery XP")
	check(int(app.lan_authority.records[client_id]["shift_stats"].get("event_deliveries", 0)) == 1 and int(app.lan_authority.records[client_id]["shift_stats"].get("event_bonus_money", 0)) == expected_bonus, "Host records one event delivery and the actual extra payment")
	check(app.profile == host_before and not app.lan_authority._team_enabled, "The Host receives no reward for the Client's competitive delivery")
	check(int(latest_snapshot.get("district_event", {}).get("delivered", 0)) == 1 and int(latest_snapshot.get("district_event", {}).get("bonus_money", 0)) == expected_bonus, "Shared event totals reflect the validated Client delivery")
	flag("host-verified")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left and app.state == "playing" and app.remote_players.is_empty(), "Client disconnect removes its avatar while the Host event continues")
	check(app.lan_authority.get_profile(client_id) == client_after, "Disconnect retains the Client's exact confirmed career record")

func run_client() -> void:
	app._join_lan("Lunch Client", "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client connects by LAN IPv4")
	if not connected:
		return
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not app.orders.is_empty())
	check(started, "Client receives ordinary shared orders before lunch")
	if not started:
		return
	app._close_modal()
	check(latest_snapshot.get("district_event", {}).get("phase", "") == "waiting", "Client sees the server's initial waiting schedule")
	var before: Dictionary = app.profile.duplicate(true)
	flag("client-started", str(app.lan_session.local_id))
	var active: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("event-order")) and latest_snapshot.get("district_event", {}).get("phase", "") == "active" and not real_event_order().is_empty())
	check(active, "Active event identity, timer and offers cross the real ENet connection")
	if not active:
		return
	var order_id: int = int(FileAccess.get_file_as_string(coord.path_join("event-order")))
	var chosen: Dictionary = real_event_order(order_id)
	check(not chosen.is_empty() and chosen.get("pickup_id") == "pickup_espresso" and chosen.get("delivery_district_id") == "business", "Client receives the real cafe and business office route")
	if chosen.is_empty():
		return
	var event: Dictionary = latest_snapshot.get("district_event", {})
	check(float(event.get("remaining", 0)) > 0.0 and float(event.get("remaining", 999)) <= 180.0 and app._district_event_view().get("phase", "") == "active", "Client HUD uses the server-confirmed active window")
	var approach: Vector3 = chosen["pickup_position"] + Vector3(0, 0.15, -6.0)
	var corrected: bool = await wait_for(func() -> bool: return absf(app.player.global_position.x - approach.x) < 0.25 and absf(app.player.global_position.z - approach.z) < 0.25)
	check(corrected, "Client body applies the normal Host correction outside the cafe")
	if not corrected:
		return
	app.lan_session.request_action("accept", {"id": order_id, "reward": 99999999, "xp": 99999999, "event_bonus_multiplier": 1000000.0, "event_ends_at": 99999999.0, "delivery_position": Vector3.ZERO})
	var accepted: bool = await wait_for(func() -> bool: return int(app.active_order.get("id", 0)) == order_id and app.active_order.get("state", "") == "Accepted")
	check(accepted, "Client waits for Host-confirmed event acceptance")
	if not accepted:
		return
	check(int(app.active_order["reward"]) == int(chosen["reward"]) and app.active_order.get("event_ends_at") == chosen.get("event_ends_at") and int(app.profile["money"]) == int(before["money"]), "The forged reward and extended deadline are ignored without an early payout")
	flag("client-accepted")
	check(await walk_to(chosen["pickup_position"]), "Actual WASD reaches the cafe interaction distance")
	app._interact()
	var picked: bool = await wait_for(func() -> bool: return app.active_order.get("state", "") == "PickedUp")
	check(picked, "Server confirmation changes the Client to carrying lunch")
	if not picked:
		return
	check(app.player.is_carrying and app.hud._full_map.target_picked and not app.hud._mini_map.route_points.is_empty(), "Parcel visual and both navigation maps point to the real office")
	flag("client-picked")
	approach = chosen["delivery_position"] + Vector3(0, 0.15, -6.0)
	var office: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("office-approach")) and absf(app.player.global_position.x - approach.x) < 0.25 and absf(app.player.global_position.z - approach.z) < 0.25)
	check(office, "Client receives its trusted test approach at the actual office address")
	if not office:
		return
	check(await walk_to(chosen["delivery_position"]), "Actual WASD reaches the office interaction distance")
	app._interact()
	var delivered: bool = await wait_for(func() -> bool: return app.active_order.is_empty() and int(app.shift_stats.get("deliveries", 0)) == 1)
	check(delivered, "Server validates E and confirms one finished lunch")
	if not delivered:
		return
	var bonus: int = int(floor(float(chosen["reward"]) * 0.5))
	check(int(app.profile["money"]) == int(before["money"]) + int(chosen["reward"]) + bonus and int(app.profile["xp"]) == int(before["xp"]) + int(chosen["xp"]), "Client applies only the exact Host-approved event money and XP")
	check(int(app.shift_stats.get("event_deliveries", 0)) == 1 and int(app.shift_stats.get("event_bonus_money", 0)) == bonus, "Client result counters match its actual bonus")
	check(not app.player.is_carrying and not app.hud._full_map.has_target and app.hud._mini_map.route_points.is_empty(), "Finished lunch clears parcel and navigation goals")
	var paid: Dictionary = app.profile.duplicate(true)
	app.lan_session.request_action("interact", {"reward": 99999999, "event_bonus": 99999999})
	await create_timer(0.6).timeout
	check(app.profile == paid and int(app.shift_stats["deliveries"]) == 1, "A duplicated forged completion packet cannot add money or delivery credit")
	flag("client-delivered")
	var verified: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("host-verified")))
	check(verified, "Host independently verifies payment before the Client exits")
	app._leave_lan()
