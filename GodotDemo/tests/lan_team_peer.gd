extends SceneTree

var app
var role: String = ""
var coord: String = ""
var latest_snapshot: Dictionary = {}
var checks: int = 0
var failures: Array[String] = []
var isolated_save: bool = false
const REWARD: int = 200
const DELIVERY_XP: int = 50
const BONUS_MONEY: int = 500
const BONUS_XP: int = 100
const ORDER_ID: int = 40001

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

func wait_for(condition: Callable, seconds: float = 15.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
		OS.delay_msec(17)
	return false

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("LAN team regression requires --test-mode")
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
	isolated_save = args.has("--isolated-save")
	if isolated_save and (OS.get_environment("DELIVERY_TEAM_TEST_SAVE") != "1" or OS.get_environment("XDG_DATA_HOME").is_empty() or OS.get_environment("XDG_CONFIG_HOME").is_empty()):
		printerr("Save regression refused: explicit isolation flag, sentinel and role-specific XDG paths required")
		quit(2)
		return
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.lan_session.state_received.connect(func(data: Dictionary) -> void: latest_snapshot = data.duplicate(true))
	if isolated_save:
		# CI supplies separate temporary XDG directories per role.
		# A regular --test-mode invocation never touches a persistent profile.
		app.test_mode = false
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
	print("LAN_TEAM_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func received_offers() -> Array:
	return latest_snapshot.get("handoffs", {}).get("incoming", [])

func new_host_parcel(order_id: int, target: Vector3) -> void:
	# Trusted Host fixture only: do not weaken client movement/order validation.
	var order: Dictionary = app.lan_authority.orders[0].duplicate(true)
	order.merge({"id": order_id, "owner_id": 1, "state": "PickedUp", "type": "standard", "required_level": 1, "title": "Team test parcel", "reward": REWARD, "base_reward": REWARD, "xp": DELIVERY_XP, "time_limit": 60.0, "pickup_position": app.player.global_position, "delivery_position": target}, true)
	app.lan_authority.records[1]["active_order"] = order
	app.lan_authority.records[1]["carrying"] = true
	app.lan_authority.records[1]["position"] = app.player.global_position
	app.lan_authority._mark_changed()

func run_host() -> void:
	app._host_lan("Team Host", "Team integration", 4, 600, "team")
	check(app.lan_session.phase == "lobby", "Host creates team room")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Client joins and readies the team lobby")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and FileAccess.file_exists(coord.path_join("client-started")))
	check(started, "Both processes enter the shared team shift")
	if not started:
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-started")))
	var client_position: Vector3 = app.lan_authority.records[client_id]["position"]
	var target: Vector3 = client_position + Vector3(0, 0, 4)
	new_host_parcel(ORDER_ID, target)
	check(int(latest_snapshot.get("team", {}).get("target", 0)) == 8, "Two initial participants have a fixed eight-delivery goal")
	app.lan_session.request_action("offer_handoff", {"target_id": client_id})
	var accepted: bool = await wait_for(func() -> bool: return app.lan_authority.records[1]["active_order"].is_empty() and int(app.lan_authority.records[client_id]["active_order"].get("id", 0)) == ORDER_ID)
	check(accepted, "Client acceptance atomically transfers Host-owned parcel")
	if not accepted:
		return
	check(int(app.lan_authority.get_profile(1)["money"]) == 0 and int(app.lan_authority.get_profile(client_id)["money"]) == 0, "RPC handoff grants neither player an early reward")
	check(not app.player.is_carrying and app.active_order.is_empty(), "Host visual parcel clears after confirmed transfer")
	flag("handoff-confirmed")
	var delivered: bool = await wait_for(func() -> bool: return int(app.lan_authority.records[client_id]["shift_stats"]["deliveries"]) == 1 and FileAccess.file_exists(coord.path_join("client-delivered")))
	check(delivered, "Client real movement and E complete the transferred parcel")
	if not delivered:
		return
	check(int(app.lan_authority.get_profile(client_id)["money"]) == REWARD and int(app.lan_authority.get_profile(1)["money"]) == 0, "Normal reward goes only to the finishing client")
	for index: int in range(7):
		app.player.reset_at(Vector3(-23.0, 0.15, 4.0))
		new_host_parcel(ORDER_ID + index + 1, app.player.global_position)
		app.lan_session.request_action("interact")
	var team: Dictionary = latest_snapshot.get("team", {})
	check(bool(team.get("completed", false)) and int(team.get("delivered", 0)) == 8, "Shared progress reaches exact goal")
	check(int(app.profile["money"]) == 7 * REWARD + BONUS_MONEY and int(app.shift_stats["deliveries"]) == 7, "Host receives its normal deliveries and one team bonus")
	check(int(app.lan_authority.get_profile(client_id)["money"]) == REWARD + BONUS_MONEY, "Client receives one Host-calculated team bonus")
	flag("goal-completed")
	var saved: bool = await wait_for(func() -> bool: return FileAccess.file_exists(coord.path_join("client-reward-confirmed")))
	check(saved, "Client confirms rewarded career and local save")
	check_saved_profile("Host")
	var prior_profile: Dictionary = app.profile.duplicate(true)
	app._broadcast_lan_state()
	app._broadcast_lan_state()
	await process_frame
	check(app.profile == prior_profile, "Repeated unchanged snapshots cannot grant Host bonus again")
	# Offer another parcel at the recipient's validated location, then disconnect.
	client_position = app.lan_authority.records[client_id]["position"]
	app.player.reset_at(client_position + Vector3(1.5, 0, 0))
	new_host_parcel(ORDER_ID + 100, client_position + Vector3(0, 0, 4))
	app.lan_session.request_action("offer_handoff", {"target_id": client_id})
	flag("disconnect-offer")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left, "Client disconnect propagates to Host")
	check(app.state == "playing" and int(app.active_order.get("id", 0)) == ORDER_ID + 100, "Host continues and retains an unaccepted parcel")
	check(latest_snapshot.get("handoffs", {}).get("outgoing", {}).is_empty(), "Client disconnect cleans private pending offer")
	check(int(latest_snapshot.get("team", {}).get("target", 0)) == 8, "Disconnect does not lower original common goal")
	check_saved_profile("Host after disconnect")

func run_client() -> void:
	app._join_lan("Team Client", "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client connects via local IPv4")
	if not connected:
		return
	check(str(app.lan_session.lobby_config.get("shift_mode", "")) == "team", "Host-selected team mode reaches client lobby")
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not latest_snapshot.is_empty())
	check(started, "Client receives server team snapshot")
	if not started:
		return
	app._close_modal()
	var base_money: int = int(app.profile["money"])
	var base_xp: int = int(app.profile["xp"])
	flag("client-started", str(app.lan_session.local_id))
	var offered: bool = await wait_for(func() -> bool: return not received_offers().is_empty())
	check(offered, "Recipient alone receives private incoming proposal")
	if not offered:
		return
	var proposal: Dictionary = received_offers()[0]
	check(int(proposal.get("order_id", 0)) == ORDER_ID and float(proposal.get("remaining", 0)) > 0, "Proposal names exact parcel and deadline")
	app.lan_session.request_action("accept_handoff", {"sender_id": int(proposal["sender_id"]), "offer_id": proposal["offer_id"]})
	var accepted: bool = await wait_for(func() -> bool: return int(app.active_order.get("id", 0)) == ORDER_ID and app.active_order.get("state", "") == "PickedUp")
	check(accepted, "Client waits for Host-confirmed parcel ownership")
	if not accepted:
		return
	check(app.player.is_carrying and app.hud._full_map.target_picked and app.hud._full_map.target_position.is_equal_approx(app.active_order["delivery_position"]), "Carry visual and route switch to transferred delivery")
	check(int(app.profile["money"]) == base_money and int(app.profile["xp"]) == base_xp, "Client does not grant itself handoff money or XP")
	app.lan_session.request_action("accept_handoff", {"sender_id": int(proposal["sender_id"]), "offer_id": proposal["offer_id"]})
	var target: Vector3 = app.active_order["delivery_position"]
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var direction: Vector3 = target - app.player.global_position
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
	check(delivered, "Actual client movement and interaction deliver transferred parcel")
	if not delivered:
		return
	check(int(app.profile["money"]) == base_money + REWARD and int(app.profile["xp"]) == base_xp + DELIVERY_XP, "Only confirmed normal delivery is saved before goal")
	flag("client-delivered")
	var rewarded: bool = await wait_for(func() -> bool: return bool(latest_snapshot.get("team", {}).get("completed", false)) and int(app.profile["money"]) == base_money + REWARD + BONUS_MONEY)
	check(rewarded, "Client receives shared goal completion and one team bonus")
	check(int(app.profile["xp"]) == base_xp + DELIVERY_XP + BONUS_XP and int(app.profile["total_deliveries"]) == 1, "Team XP confirmed without inventing deliveries")
	check_saved_profile("Client")
	flag("client-reward-confirmed")
	var next_offer: bool = await wait_for(func() -> bool: return not received_offers().is_empty() and int(received_offers()[0].get("order_id", 0)) == ORDER_ID + 100)
	check(next_offer, "Recipient receives another proposal after team completion")
	check(int(app.profile["money"]) == base_money + REWARD + BONUS_MONEY, "Later snapshots preserve exact once-only reward")
	app._leave_lan()
	check_saved_profile("Client after leaving")

func check_saved_profile(label: String) -> void:
	if not isolated_save:
		check(not app.profile.is_empty(), label + " retains confirmed profile (disk writes disabled)")
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.SAVE_PATH))
	var same: bool = saved is Dictionary
	if same:
		for key: String in ["player_name", "money", "xp", "level", "rank", "total_deliveries", "express_deliveries", "total_money_earned", "best_shift", "owned_vehicles", "selected_vehicle"]:
			if saved.get(key) != app.profile.get(key):
				same = false
	check(same, label + " disk profile matches all confirmed career fields")
