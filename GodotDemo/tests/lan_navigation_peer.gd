extends SceneTree

var app
var role: String = ""
var coord: String = ""
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

func wait_for(condition: Callable, seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
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
	print("LAN_NAVIGATION_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func run_host() -> void:
	app._host_lan("Navigation Host", "Navigation test", 4, 600)
	check(app.lan_session.phase == "lobby", "Host creates local room")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Client connects and becomes ready")
	if not ready:
		return
	app._start_lan_shift()
	check(app.state == "playing", "Host starts the shared shift")
	app._close_modal()
	var picked: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("client-picked")))
	check(picked, "Client obtains server-confirmed pickup")
	if not picked:
		return
	check(app.active_order.is_empty() and app.hud._mini_map.route_points.is_empty(), "Client order never appears as Host's personal route")
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-picked")))
	app._accept_order(int(app.orders[0]["id"]))
	check(not app.active_order.is_empty() and int(app.active_order["id"]) != client_id, "Host owns a different shared order")
	check(not app.hud._mini_map.route_points.is_empty(), "Host has its own route")
	flag("host-accepted")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left, "Client disconnect is handled")
	check(app.state == "playing" and not app.active_order.is_empty(), "Host keeps playing with its own active order")
	check(app.hud._mini_map.route_points == app.hud._full_map.route_points, "Host maps remain consistent")

func run_client() -> void:
	app._join_lan("Navigation Client", "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client connects by IPv4")
	if not connected:
		return
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not app.orders.is_empty())
	check(started, "Client loads the shared city")
	if not started:
		return
	app._close_modal()
	var order_id: int = int(app.orders[0]["id"])
	app._accept_order(order_id)
	var accepted: bool = await wait_for(func() -> bool: return not app.active_order.is_empty())
	check(accepted, "Client waits for Host-confirmed acceptance")
	if not accepted:
		return
	check(not app.hud._mini_map.route_points.is_empty(), "Confirmed client order has a route")
	check(app.hud._mini_map.route_points == app.hud._full_map.route_points, "Client maps have identical paths")
	var pickup: Vector3 = app._target_position()
	Engine.max_fps = 60
	var deadline: int = Time.get_ticks_msec() + 12_000
	while Time.get_ticks_msec() < deadline:
		var direction: Vector3 = pickup - app.player.global_position
		direction.y = 0.0
		if direction.length() <= 1.8:
			break
		app.player.set_view_direction(atan2(-direction.x, -direction.z))
		Input.action_press("move_forward")
		await process_frame
		OS.delay_msec(17)
	Input.action_release("move_forward")
	await physics_frame
	app._interact()
	var picked: bool = await wait_for(func() -> bool: return app.active_order.get("state", "") == "PickedUp")
	check(picked, "Real movement and E interaction obtain Host-confirmed pickup")
	if not picked:
		return
	check(app.hud._full_map.target_position.is_equal_approx(app.active_order["delivery_position"]), "Client goal switches only after confirmed pickup")
	check(app.hud._full_map.target_picked, "Client delivery marker changes colour")
	check(app.hud._mini_map.other_players.size() == 1, "Host marker is visible on the client map")
	flag("client-picked", str(order_id))
	var host_accepted: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("host-accepted")))
	check(host_accepted, "Host accepts a separate order")
	check(int(app.active_order.get("id", -1)) == order_id, "Host order never replaces the client order")
	app._leave_lan()
