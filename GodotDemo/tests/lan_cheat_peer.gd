extends SceneTree

# Two real ENet processes, using production HUD, RPC, snapshots and JSON saves.
# --test-mode --isolated-save --role=host|client --coord=/tmp/...
# DELIVERY_TEAM_TEST_SAVE=1 plus distinct role-specific /tmp XDG data/config
# directories are required before this fixture permits production profile writes.
const START_MONEY: int = 1250
const CAREER_STATS: Array[String] = ["total_deliveries", "express_deliveries", "total_money_earned", "best_shift"]
const SESSION_STATS: Array[String] = ["money", "xp", "deliveries", "best_delivery", "team_bonus_money", "team_bonus_xp", "event_deliveries", "event_bonus_money"]
const HOST_STYLE: Dictionary = {"outfit": "mint", "backpack": "compact", "vehicle_paint": "coral"}
const CLIENT_STYLE: Dictionary = {"outfit": "sunshine", "backpack": "compact", "vehicle_paint": "mint"}
var app
var role: String = ""
var coord: String = ""
var data_path: String = ""
var latest_snapshot: Dictionary = {}
var cheat_results: Array[Dictionary] = []
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
	var file: FileAccess = FileAccess.open(coord.path_join(name), FileAccess.WRITE)
	check(file != null, "Coordination marker opens: " + name)
	if file != null:
		file.store_string(value)
		file.close()

func has_flag(name: String) -> bool:
	return FileAccess.file_exists(coord.path_join(name))

func wait_for(condition: Callable, seconds: float = 12.0) -> bool:
	var until: int = mini(deadline_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await process_frame
		OS.delay_msec(17)
	return false

func wait_flag(name: String) -> bool:
	var received: bool = await wait_for(func() -> bool: return has_flag(name))
	check(received, "Other process confirms " + name)
	return received

func json_value(value: Variant) -> Variant:
	# JSON numbers and typed arrays must be compared in the same representation.
	return JSON.parse_string(JSON.stringify(value))

func _temporary_role_path(path: String) -> bool:
	if not path.is_absolute_path() or not path.simplify_path().begins_with("/tmp/"):
		return false
	var found: bool = false
	var other: String = "client" if role == "host" else "host"
	for part: String in path.simplify_path().split("/"):
		if part == role or part.begins_with(role + "-") or part.begins_with(role + "_"):
			found = true
		if part == other or part.begins_with(other + "-") or part.begins_with(other + "_"):
			return false
	return found

func _timeout() -> void:
	check(false, "Two-process cheat regression exceeded 85 seconds")
	print("LAN_CHEAT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
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
	if not args.has("--test-mode") or not args.has("--isolated-save") or role not in ["host", "client"] or OS.get_environment("DELIVERY_TEAM_TEST_SAVE") != "1" or not _temporary_role_path(data_path) or not _temporary_role_path(config_path) or data_path == config_path or not coord.is_absolute_path() or not coord.simplify_path().begins_with("/tmp/"):
		printerr("LAN cheat regression refused: test mode, isolation flag, save sentinel, shared /tmp coord and distinct role-specific /tmp XDG data/config directories required")
		quit(2)
		return
	coord = coord.simplify_path()
	deadline_msec = Time.get_ticks_msec() + 85000
	create_timer(85.0).timeout.connect(_timeout)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var isolated: bool = user_path.begins_with(data_path.trim_suffix("/") + "/")
	check(app.test_mode and isolated, "Test mode protects a verified role-specific user directory")
	if not isolated or not app.test_mode or FileAccess.file_exists(app.SAVE_PATH) or FileAccess.file_exists(app.SAVE_PATH + ".tmp") or FileAccess.file_exists(app.SAVE_PATH + ".backup"):
		check(false, "Profile save fixture requires a fresh isolated destination")
		await finish()
		return
	# Only the verified explicit fixture switches on normal production writes.
	app.test_mode = false
	app.lan_session.state_received.connect(func(data: Dictionary) -> void: latest_snapshot = data.duplicate(true))
	app.lan_session.event_received.connect(func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "cheat_result":
			cheat_results.append(event.duplicate(true)))
	seed_profile()
	if role == "host":
		await run_host()
	else:
		await run_client()
	await finish()

func seed_profile() -> void:
	# Trusted setup only; all grants during the shift go through production paths.
	app.profile["player_name"] = "Cheat " + role.capitalize()
	app.profile["money"] = START_MONEY
	app.profile["xp"] = 0
	app.profile["level"] = 1
	app.profile["rank"] = "Rookie Courier"
	app.profile["total_deliveries"] = 17
	app.profile["express_deliveries"] = 4
	app.profile["total_money_earned"] = 20500
	app.profile["best_shift"] = 3100
	app.profile["owned_vehicles"] = ["bicycle"]
	app.profile["selected_vehicle"] = ""
	app._open_customization()
	var style: Dictionary = HOST_STYLE if role == "host" else CLIENT_STYLE
	for category: String in style:
		app._select_cosmetic(category, str(style[category]))
	app._close_customization()
	check(app.profile["appearance"] == style, "Ordinary offline customization establishes the fixture style")
	check(app._save_profile(), "Fixture uses the normal atomic production JSON save")
	check_saved_profile("Initial " + role)

func public_player(peer_id: int) -> Dictionary:
	for entry: Dictionary in latest_snapshot.get("players", []):
		if int(entry.get("id", 0)) == peer_id:
			return entry
	return {}

func no_earned_credit(profile: Dictionary, stats: Dictionary, label: String) -> void:
	var expected: Array[int] = [17, 4, 20500, 3100]
	for index: int in CAREER_STATS.size():
		check(int(profile.get(CAREER_STATS[index], -1)) == expected[index], label + " preserves career " + CAREER_STATS[index])
	for key: String in SESSION_STATS:
		check(int(stats.get(key, -1)) == 0, label + " grants no session " + key)

func check_session_progress(label: String) -> void:
	no_earned_credit(app.profile, app.shift_stats, label)
	var team: Dictionary = latest_snapshot.get("team", {})
	check(bool(team.get("enabled", false)) and int(team.get("target", 0)) == 8 and int(team.get("delivered", -1)) == 0 and not bool(team.get("completed", true)) and not bool(team.get("bonus_awarded", true)) and int(team.get("contributions", -1)) == 0, label + " leaves real team progress and bonus untouched")
	var district: Dictionary = latest_snapshot.get("district_event", {})
	check(int(district.get("delivered", -1)) == 0 and int(district.get("bonus_money", -1)) == 0, label + " leaves district event credit untouched")
	var rows: Array = latest_snapshot.get("leaderboard", [])
	check(rows.size() == 2, label + " keeps both players in the results roster")
	for row: Dictionary in rows:
		for key: String in SESSION_STATS:
			check(int(row.get(key, -1)) == 0, label + " results row %d has no %s" % [int(row.get("id", 0)), key])

func submit_dialog(code: String, expected_ok: bool = true) -> bool:
	var before: Dictionary = app.profile.duplicate(true)
	var revision: int = app._last_network_revision
	var before_results: int = cheat_results.size()
	app._open_cheats()
	check(app.modal == "cheats" and not app.player.controls_enabled, "Normal cheat dialog opens and pauses local controls")
	var input: LineEdit = app.hud.find_child("CheatCodeInput", true, false) as LineEdit
	var button: Button = app.hud.find_child("CheatApply", true, false) as Button
	check(input != null and button != null, "Normal dialog exposes code input and Apply button")
	if input == null or button == null:
		return false
	input.text = code
	button.pressed.emit()
	if role == "client":
		check(app.profile == before, "Client dialog waits for Host confirmation before changing the career")
	var received: bool = await wait_for(func() -> bool: return cheat_results.size() > before_results)
	check(received, code + " receives a private Host cheat result")
	if not received:
		return false
	var result: Dictionary = cheat_results[before_results]
	check(bool(result.get("ok", false)) == expected_ok and str(result.get("session_id", "")) == app.lan_session.session_id, code + " receives the expected decision for this session")
	if expected_ok:
		check(str(result.get("code", "")) == code.strip_edges().to_upper(), code + " result confirms the submitted canonical code")
		check(app._last_network_revision > revision, code + " arrives in a newer authoritative profile revision")
	else:
		check(json_value(app.profile) == json_value(before), code + " rejection leaves the entire profile untouched")
	# Requests remain below the production anti-flood refill rate.
	await create_timer(0.4).timeout
	return bool(result.get("ok", false)) == expected_ok

func run_host() -> void:
	app._host_lan(str(app.profile["player_name"]), "Cheat integration", 4, 600, "team")
	check(app.lan_session.phase == "lobby", "Host creates an ordinary team ENet lobby")
	if app.lan_session.phase != "lobby":
		return
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Actual Client completes registration and Ready")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	if not await wait_flag("client-first-grant"):
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-first-grant")))
	var remote_ready: bool = await wait_for(func() -> bool: return app.remote_players.has(client_id))
	check(remote_ready, "Host creates the actual Client courier")
	var client_before: Dictionary = app.lan_authority.get_profile(client_id)
	check(int(client_before["money"]) == START_MONEY + 10000 and int(app.profile["money"]) == START_MONEY, "Client Money code changes only the requesting Client")
	check(app.lan_authority.records[client_id]["active_order"].get("state", "") == "Accepted", "Client retains its ordinary claimed parcel during a cheat")
	check(client_before["appearance"] == CLIENT_STYLE, "Host-confirmed Client cheat preserves appearance IDs")
	if remote_ready:
		check(app.remote_players[client_id].get_appearance() == CLIENT_STYLE, "Host remote courier preserves its cosmetic appearance")
	await submit_dialog("MONEY50000")
	await submit_dialog("XP1000")
	check(int(app.profile["money"]) == START_MONEY + 50000 and int(app.profile["xp"]) == 1000 and int(app.profile["level"]) == 3, "Host can apply its own fixed Money and XP codes")
	check(json_value(app.lan_authority.get_profile(client_id)) == json_value(client_before), "Host's own cheats do not alter the Client profile")
	check_session_progress("Host cheats")
	check_saved_profile("Host confirmed cheats")
	flag("host-cheated")
	if not await wait_flag("client-finished"):
		return
	var client_profile: Dictionary = app.lan_authority.get_profile(client_id)
	check(int(client_profile["money"]) == START_MONEY + 70000 and int(client_profile["xp"]) == 12150 and int(client_profile["level"]) == 10 and client_profile["rank"] == "Delivery Master", "Host validates Client fixed grants and Delivery Master progression")
	check(client_profile["owned_vehicles"].has("bicycle") and client_profile["owned_vehicles"].has("scooter") and client_profile["owned_vehicles"].has("car") and client_profile["selected_vehicle"] == "", "ALLVEHICLES grants inventory without selecting or spawning a vehicle")
	no_earned_credit(client_profile, app.lan_authority.records[client_id]["shift_stats"], "Host-confirmed Client")
	var public_ready: bool = await wait_for(func() -> bool: return int(public_player(client_id).get("level", 0)) == 10 and public_player(client_id).get("rank", "") == "Delivery Master")
	check(public_ready and public_player(client_id).get("appearance") == CLIENT_STYLE, "Updated Client level/rank reaches the public roster with unchanged cosmetics")
	check(app.lan_authority.records[client_id]["active_order"].is_empty(), "Client abandons its fixture order without a fabricated delivery")
	check(int(app.profile["money"]) == START_MONEY + 50000 and int(app.profile["xp"]) == 1000, "Later Client cheats preserve Host's own confirmed career")
	check(cheat_results.size() == 2, "Host receives only its own private cheat results")
	flag("host-verified")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left and app.state == "playing", "Client disconnect leaves the real Host shift running")
	if not await wait_flag("client-reloaded"):
		return
	await disconnect_and_reload()

func run_client() -> void:
	if not await wait_flag("host-ready"):
		return
	app._join_lan(str(app.profile["player_name"]), "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Client joins via actual loopback IPv4 ENet")
	if not connected:
		return
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not latest_snapshot.is_empty() and app.remote_players.has(1))
	check(started, "Client receives the ordinary authoritative shift snapshot")
	if not started:
		return
	app._close_modal()
	var first: Dictionary = {}
	for order: Dictionary in app.orders:
		if order.get("type", "") == "standard" and str(order.get("event_id", "")).is_empty():
			first = order.duplicate(true)
			break
	check(not first.is_empty(), "Unmodified shared order pool includes a standard parcel")
	if first.is_empty():
		return
	app._accept_order(int(first["id"]))
	var accepted: bool = await wait_for(func() -> bool: return int(app.active_order.get("id", 0)) == int(first["id"]))
	check(accepted, "Client claims the real server order through the normal accept RPC")
	if not accepted:
		return
	var active_before: Variant = json_value(app.active_order)
	var appearance_before: Variant = json_value(app.profile["appearance"])
	var cosmetics_before: Variant = json_value(app.profile["owned_cosmetics"])
	await submit_dialog("UNKNOWN-CHEAT", false)
	var before_forgery: Variant = json_value(app.profile)
	var before_results: int = cheat_results.size()
	# Bypass the HUD with an actual malicious wire payload; sender identity still
	# comes from ENet. Neither amount, target nor submitted profile is trusted.
	app.lan_session._rpc_action.rpc_id(1, app.lan_session.session_id, "cheat_code", {"code": "MONEY50000", "amount": 999999999, "money": 999999999, "xp": 999999999, "level": 10, "target_id": 1, "owner_id": 1, "id": 1})
	var rejected: bool = await wait_for(func() -> bool: return cheat_results.size() > before_results)
	check(rejected and not bool(cheat_results.back().get("ok", true)), "Host rejects forged amount/target/profile fields sent directly over RPC")
	check(json_value(app.profile) == before_forgery, "Forged direct RPC cannot mutate the Client career")
	await create_timer(0.4).timeout
	await submit_dialog("  money10000  ")
	check(int(app.profile["money"]) == START_MONEY + 10000, "Normal Client dialog applies the fixed case-insensitive Money grant")
	var first_confirmed: Variant = json_value(app.profile)
	flag("client-first-grant", str(app.lan_session.local_id))
	if not await wait_flag("host-cheated"):
		return
	check(json_value(app.profile) == first_confirmed, "Host's own Money and XP codes leave the Client unchanged")
	var host_roster: bool = await wait_for(func() -> bool: return int(public_player(1).get("level", 0)) == 3 and public_player(1).get("rank", "") == "City Courier")
	check(host_roster and public_player(1).get("appearance") == HOST_STYLE and app.remote_players[1].get_appearance() == HOST_STYLE, "Host XP updates its public level/rank while preserving remote appearance")
	await submit_dialog("MONEY10000")
	await submit_dialog("MONEY50000")
	check(int(app.profile["money"]) == START_MONEY + 70000, "Repeated Money codes intentionally grant their fixed amounts again")
	await submit_dialog("XP1000")
	check(int(app.profile["xp"]) == 1000 and int(app.profile["level"]) == 3 and app.profile["rank"] == "City Courier", "Client XP derives its level and rank through Host confirmation")
	await submit_dialog("LEVELUP")
	check(int(app.profile["xp"]) == 1350 and int(app.profile["level"]) == 4 and app.profile["rank"] == "Fast Courier", "LEVELUP uses the next canonical XP threshold")
	await submit_dialog("DELIVERYMASTER")
	check(int(app.profile["xp"]) == 12150 and int(app.profile["level"]) == 10 and app.profile["rank"] == "Delivery Master", "DELIVERYMASTER reaches the canonical maximum rank")
	await submit_dialog("ALLVEHICLES")
	check(app.profile["owned_vehicles"].size() == 3 and app.profile["owned_vehicles"].has("bicycle") and app.profile["owned_vehicles"].has("scooter") and app.profile["owned_vehicles"].has("car") and app.profile["selected_vehicle"] == "" and app.vehicles.is_empty(), "Inventory cheat owns all shipped vehicles without changing selection or spawning")
	check(json_value(app.active_order) == active_before, "All cheat confirmations preserve the active standard order")
	check(json_value(app.profile["appearance"]) == appearance_before and json_value(app.profile["owned_cosmetics"]) == cosmetics_before and app.player.get_appearance() == CLIENT_STYLE, "All cheat confirmations preserve cosmetic inventory and the visible courier")
	check(cheat_results.size() == 9, "Client receives only its own two rejections and seven cheat results")
	check_session_progress("Client cheats")
	check_saved_profile("Client confirmed cheats")
	app._close_cheats()
	app.lan_session.request_action("abandon")
	var abandoned: bool = await wait_for(func() -> bool: return app.active_order.is_empty() and not app.player.is_carrying)
	check(abandoned, "Normal abandon RPC clears the fixture parcel")
	check_session_progress("Client after abandoning")
	flag("client-finished")
	if not await wait_flag("host-verified"):
		return
	await disconnect_and_reload()
	flag("client-reloaded")

func check_saved_profile(label: String) -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.SAVE_PATH))
	check(saved is Dictionary and saved == json_value(app.profile), label + " atomic JSON matches every confirmed profile field")
	check(not FileAccess.file_exists(app.SAVE_PATH + ".tmp"), label + " leaves no unfinished atomic save")

func disconnect_and_reload() -> void:
	var confirmed: Variant = json_value(app.profile)
	app._leave_lan()
	check(app.state == "menu" and app.lan_session.phase == "offline" and json_value(app.profile) == confirmed, role + " disconnect retains the entire confirmed career")
	check_saved_profile(role + " after disconnect")
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var safe: bool = app.test_mode and user_path.begins_with(data_path.trim_suffix("/") + "/") and OS.get_environment("DELIVERY_TEAM_TEST_SAVE") == "1"
	check(safe, "Fresh instance retains test-mode protection and verified isolated save path")
	if not safe:
		return
	app.test_mode = false
	app.profile = app._load_profile()
	app._apply_profile_appearance()
	check(json_value(app.profile) == confirmed, "Fresh production loader restores the exact confirmed Money/XP/level/rank/inventory/cosmetics")
	check(app.player.get_appearance() == app.profile["appearance"], "Fresh courier restores its saved appearance")
	check_saved_profile("Reloaded " + role)

func finish() -> void:
	if is_instance_valid(app):
		app._leave_lan()
		app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LAN_CHEAT_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
