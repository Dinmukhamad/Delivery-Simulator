extends SceneTree

# Execute with --test-mode against source and both exported packs. Every career
# is an in-memory fixture; the actual app disables profile/settings/audio writes.
const Rules = preload("res://scripts/cheat_code_rules.gd")
const Catalog = preload("res://scripts/cosmetic_catalog.gd")
const Vehicles = preload("res://scripts/vehicle_catalog.gd")
const Placement = preload("res://scripts/vehicle_placement.gd")
const AuthorityScript = preload("res://scripts/lan_authority.gd")
const WorldScript = preload("res://scripts/world.gd")
const EXPECTED_CODES: Array[String] = ["MONEY10000", "MONEY50000", "XP1000", "LEVELUP", "DELIVERYMASTER", "ALLVEHICLES"]
const CAP: int = 1000000000
var checks: int = 0
var failures: Array[String] = []
var cheat_events: Array[Dictionary] = []
var change_count: int = 0
var definitions: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("Cheat-code tests require --test-mode")
		quit(2)
		return
	seed(140014)
	definitions = Vehicles.load_definitions()
	test_allowlist()
	test_grants_and_levels()
	test_numeric_bounds()
	await test_authority()
	await test_actual_menu_and_solo()
	print("CHEAT_CODE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func career() -> Dictionary:
	return {"version": 1, "player_name": "Cheat regression", "money": 9000, "xp": 3900,
		"level": 6, "rank": "Express Pro", "total_deliveries": 47, "express_deliveries": 8,
		"total_money_earned": 24000, "best_shift": 7100,
		"owned_vehicles": ["bicycle", "scooter"], "selected_vehicle": "scooter",
		"appearance": {"outfit": "night", "backpack": "compact", "vehicle_paint": "amber"},
		"owned_cosmetics": ["outfit:night", "vehicle_paint:amber"]}

func preserved(actual: Dictionary, original: Dictionary, allowed: Array[String], message: String) -> void:
	var same_schema: bool = actual.size() == original.size()
	for key: String in actual:
		same_schema = same_schema and original.has(key)
	check(same_schema, message + " preserves the profile schema")
	for key: String in original:
		if not allowed.has(key):
			check(actual.get(key) == original.get(key), message + " preserves " + key)

func apply_checked(profile: Dictionary, code: Variant, expected_money: int, expected_xp: int, message: String) -> Dictionary:
	var result: Dictionary = Rules.apply(profile, code)
	check(bool(result.get("ok", false)), message + " succeeds")
	check(int(profile["money"]) == expected_money and int(profile["xp"]) == expected_xp, message + " grants exactly the documented money/XP")
	check(int(profile["level"]) == Rules.level_for_xp(expected_xp) and profile["rank"] == Rules.rank_for_level(int(profile["level"])), message + " derives level and rank from XP")
	return result

func test_allowlist() -> void:
	check(ResourceLoader.exists("res://scripts/cheat_code_rules.gd"), "The export contains the cheat rules")
	var entries: Array[Dictionary] = Rules.code_catalog()
	var names: Array[String] = []
	for entry: Dictionary in entries:
		names.append(str(entry.get("code", "")))
		check(not str(entry.get("description", "")).is_empty(), "Each advertised code has a description")
	check(names == EXPECTED_CODES, "Only the six documented codes are advertised")
	if not entries.is_empty():
		entries[0]["code"] = "FORGED"
		check(Rules.code_catalog()[0]["code"] == EXPECTED_CODES[0], "A caller cannot mutate the shared code catalog")
	for code: String in EXPECTED_CODES:
		check(Rules.normalize_code("  " + code.to_lower() + "  ") == code, code + " accepts ordinary surrounding spaces and mixed case")
	var invalid: Array = [null, 0, 10000, true, [], {}, {"code": "MONEY10000"}, "", "   ",
		"UNKNOWN", "MONEY", "MONEY10000 1", "MONEY10000;XP1000", "MONEY10000\n",
		"\tMONEY10000", "MONEY10000\r", "MONEY10000".repeat(7),
		"  ".repeat(33) + "MONEY10000", "money=1000000000", "eval(1+1)", "LEVEL10", "XP-1000",
		"MONEY10000\u0000", "ＭＯＮＥＹ１００００"]
	for code: Variant in invalid:
		var profile: Dictionary = career()
		var before: Dictionary = profile.duplicate(true)
		var result: Dictionary = Rules.apply(profile, code)
		check(not bool(result.get("ok", true)) and not bool(result.get("changed", true)), "Unknown, overlong, typed or command-like input is rejected")
		check(profile == before, "Invalid code leaves every profile field unchanged")

func test_grants_and_levels() -> void:
	for code: String in EXPECTED_CODES:
		var profile: Dictionary = career()
		var before: Dictionary = profile.duplicate(true)
		var money: int = 9000 + (10000 if code == "MONEY10000" else (50000 if code == "MONEY50000" else 0))
		var xp: int = 4900 if code == "XP1000" else (5400 if code == "LEVELUP" else (12150 if code == "DELIVERYMASTER" else 3900))
		var result: Dictionary = apply_checked(profile, " " + code.to_lower() + " ", money, xp, code)
		check(bool(result.get("changed", false)) and result.get("code") == code and not str(result.get("message", "")).is_empty(), code + " reports a normalized code and concrete feedback")
		preserved(profile, before, ["money", "xp", "level", "rank", "owned_vehicles"], code)
		if code == "ALLVEHICLES":
			var owned: Array = profile["owned_vehicles"]
			check(owned.size() == definitions.size(), "ALLVEHICLES grants one ownership entry for every catalog vehicle")
			for vehicle_id: String in definitions:
				check(owned.has(vehicle_id), "ALLVEHICLES grants " + vehicle_id)
			check(profile["selected_vehicle"] == before["selected_vehicle"], "ALLVEHICLES keeps the selected transport")
			var granted: Dictionary = profile.duplicate(true)
			result = Rules.apply(profile, code)
			check(bool(result.get("ok", false)) and not bool(result.get("changed", true)) and profile == granted, "Repeating ALLVEHICLES is a successful ownership no-op")
		else:
			check(profile["owned_vehicles"] == before["owned_vehicles"], code + " never changes vehicle ownership")
	var repeated: Dictionary = career()
	apply_checked(repeated, "MONEY10000", 19000, 3900, "First repeatable money grant")
	apply_checked(repeated, "MONEY10000", 29000, 3900, "Second repeatable money grant")
	apply_checked(repeated, "XP1000", 29000, 4900, "First repeatable XP grant")
	apply_checked(repeated, "XP1000", 29000, 5900, "Second repeatable XP grant")
	preserved(repeated, career(), ["money", "xp", "level", "rank"], "Repeated grants")
	for level: int in range(1, 11):
		var floor_xp: int = 0 if level == 1 else (level - 1) * (level - 1) * 150
		var profile: Dictionary = career()
		profile["xp"] = floor_xp
		profile["level"] = 999
		profile["rank"] = "Forged rank"
		var result: Dictionary = Rules.apply(profile, "MONEY10000")
		check(bool(result.get("ok", false)) and int(profile["level"]) == level, "Level %d is derived at its exact XP floor" % level)
		var rank: String = "Delivery Master" if level == 10 else ("Express Pro" if level >= 6 else ("Fast Courier" if level >= 4 else ("City Courier" if level >= 2 else "Rookie Courier")))
		check(profile["rank"] == rank, "Level %d receives its normal rank" % level)
		var original_xp: int = int(profile["xp"])
		result = Rules.apply(profile, "LEVELUP")
		var next_xp: int = level * level * 150 if level < 10 else original_xp
		check(bool(result.get("ok", false)) and int(profile["xp"]) == next_xp and int(profile["level"]) == mini(level + 1, 10), "LEVELUP advances level %d to the next normal threshold" % level)
		check(int(profile["xp"]) >= original_xp, "LEVELUP never decreases existing XP")
		if level < 10:
			check(Rules.level_for_xp(next_xp - 1) == level and Rules.level_for_xp(next_xp) == level + 1, "The exact level %d boundary matches ordinary progression" % (level + 1))
	var starter: Dictionary = career()
	starter["xp"] = 0
	starter["level"] = 1
	starter["rank"] = "Rookie Courier"
	starter["owned_vehicles"] = []
	starter["selected_vehicle"] = ""
	Rules.apply(starter, "ALLVEHICLES")
	check(starter["owned_vehicles"].size() == definitions.size() and starter["xp"] == 0 and starter["level"] == 1 and starter["selected_vehicle"] == "", "ALLVEHICLES grants ownership without bypassing normal level progression")
	var advanced: Dictionary = career()
	advanced["xp"] = 50000
	apply_checked(advanced, "DELIVERYMASTER", 9000, 50000, "DELIVERYMASTER on an already advanced career")
	var custom: Dictionary = career()
	custom["xp"] = 0
	Rules.apply(custom, "LEVELUP", 200)
	check(custom["xp"] == 200 and custom["level"] == 2, "LEVELUP uses the configured normal XP step")
	Rules.apply(custom, "DELIVERYMASTER", 200)
	check(custom["xp"] == 16200 and custom["level"] == 10 and custom["rank"] == "Delivery Master", "DELIVERYMASTER uses the configured max-level threshold")

func test_numeric_bounds() -> void:
	for baseline: Variant in [null, "9000", [], {}, true, NAN, INF, -INF, -9, -0.5]:
		var profile: Dictionary = career()
		profile["money"] = baseline
		profile["xp"] = baseline
		Rules.apply(profile, "MONEY10000")
		check(profile["money"] == 10000 and profile["xp"] == 0 and profile["level"] == 1, "Invalid or negative balances normalize to finite zero before a grant")
	for baseline: Variant in [CAP - 5, CAP, CAP + 1, 1.0e100]:
		var profile: Dictionary = career()
		profile["money"] = baseline
		profile["xp"] = baseline
		Rules.apply(profile, "MONEY50000")
		check(profile["money"] == CAP and int(profile["xp"]) <= CAP and int(profile["xp"]) >= 0, "Large money grants clamp at the finite profile cap")
		Rules.apply(profile, "XP1000")
		check(profile["money"] == CAP and profile["xp"] == CAP and profile["level"] == 10, "Large XP grants clamp at the same cap and derive max level")
		var capped: Dictionary = profile.duplicate(true)
		var result: Dictionary = Rules.apply(profile, "XP1000")
		check(bool(result.get("ok", false)) and not bool(result.get("changed", true)) and profile == capped, "A repeated capped grant reports success without inventing a mutation")
	var fractional: Dictionary = career()
	fractional["money"] = 12.9
	fractional["xp"] = 149.9
	Rules.apply(fractional, "XP1000")
	check(fractional["money"] == 12 and fractional["xp"] == 1149 and fractional["level"] == 3, "Finite fractional profile values normalize to integer balances")

func _on_cheat_event(peer_id: int, event: Dictionary) -> void:
	if event.get("type") == "cheat_result":
		var copied: Dictionary = event.duplicate(true)
		copied["peer_id"] = peer_id
		cheat_events.append(copied)

func _on_authority_changed() -> void:
	change_count += 1

func request_checked(authority, payload: Dictionary, ok: bool, changed: bool, message: String) -> void:
	var before: Dictionary = authority.get_profile(1)
	var revision: int = authority.revision
	var events: int = cheat_events.size()
	var changes: int = change_count
	authority.handle_request(1, "cheat_code", payload)
	check(cheat_events.size() == events + 1, message + " returns one private result")
	if cheat_events.size() > events:
		var result: Dictionary = cheat_events.back()
		check(bool(result.get("ok", not ok)) == ok and result.get("session_id") == "cheat-regression" and int(result.get("peer_id", 0)) == 1, message + " identifies only the requester and current session")
		check(not str(result.get("message", "")).is_empty(), message + " gives explicit feedback")
	check(authority.revision == revision + (1 if changed else 0) and change_count == changes + (1 if changed else 0), message + " uses one normal authoritative revision for a real change")
	if not changed:
		check(authority.get_profile(1) == before, message + " preserves the full career")

func fresh(authority, city) -> void:
	authority.start_session({"shift_seconds": -1, "shift_mode": "team"}, [
		{"id": 1, "name": "First courier", "profile": career()},
		{"id": 2, "name": "Second courier", "profile": career()}
	], city, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")), "cheat-regression")
	authority.set_process(false)

func test_authority() -> void:
	var city = WorldScript.new()
	root.add_child(city)
	var authority = AuthorityScript.new()
	root.add_child(authority)
	await process_frame
	await physics_frame
	authority.changed.connect(_on_authority_changed)
	authority.event_ready.connect(_on_cheat_event)
	fresh(authority, city)
	var selected: Dictionary = {}
	for order: Dictionary in authority.orders:
		if order.get("type", "") == "standard" and not order.has("event_id"):
			selected = order.duplicate(true)
			break
	check(not selected.is_empty(), "Host fixture uses a real ordinary order")
	if not selected.is_empty():
		authority.handle_request(1, "accept", {"id": int(selected["id"])})
	var other: Dictionary = authority.records[2].duplicate(true)
	var active: Dictionary = authority.records[1]["active_order"].duplicate(true)
	var stats: Dictionary = authority.records[1]["shift_stats"].duplicate(true)
	var vehicle: Dictionary = authority.records[1]["vehicle"].duplicate(true)
	var offers: Array = authority.orders.duplicate(true)
	var team: Dictionary = authority.snapshot_for(1)["team"].duplicate(true)
	var leaderboard: Array = authority.snapshot_for(1)["leaderboard"].duplicate(true)
	var event_delivered: int = authority._event_delivered
	var event_bonus: int = authority._event_bonus_money
	for code: String in ["MONEY10000", "MONEY10000", "XP1000", "LEVELUP", "DELIVERYMASTER", "ALLVEHICLES"]:
		request_checked(authority, {"code": code.to_lower()}, true, true, "Host " + code)
		check(authority.records[1]["active_order"] == active and authority.records[1]["shift_stats"] == stats, "Host cheat preserves the accepted parcel, its deadlines and all shift counters")
		check(authority.records[1]["vehicle"] == vehicle, "Host cheat never spawns, moves, mounts or selects a vehicle")
		check(authority.orders == offers, "Host cheat keeps all offered orders intact")
		check(authority.records[2] == other, "Host cheat changes no other courier state")
		check(authority.snapshot_for(1)["team"] == team and authority.snapshot_for(1)["leaderboard"] == leaderboard, "Host cheat fabricates no Team Shift or leaderboard progress")
		check(authority._event_delivered == event_delivered and authority._event_bonus_money == event_bonus, "Host cheat fabricates no district-event statistics")
	check(authority.get_profile(1)["money"] == 29000 and authority.get_profile(1)["xp"] == 12150 and authority.get_profile(1)["level"] == 10, "Host grants exactly the requested repeated money and max-level XP")
	preserved(authority.get_profile(1), career_with_name("First courier"), ["money", "xp", "level", "rank", "owned_vehicles"], "Confirmed Host cheat profile")
	# A new session also resets the bounded request budget. All malformed requests
	# below are independent of any anti-flood rejection of a previous burst.
	fresh(authority, city)
	for payload: Dictionary in [{"code": "MONEY10000", "target_id": 2, "money": CAP, "xp": CAP, "level": 10},
		{"code": []}, {"code": "MONEY10000;XP1000"}, {"code": "x".repeat(65)}, {}, {"code": "UNKNOWN"}]:
		var untouched: Dictionary = authority.records[2].duplicate(true)
		request_checked(authority, payload, false, false, "Malformed Host code request")
		check(authority.records[2] == untouched, "Forged target, balance and level cannot alter another player")
	fresh(authority, city)
	var events: int = cheat_events.size()
	var before: Dictionary = authority.get_profile(1)
	var revision: int = authority.revision
	authority.handle_request(999, "cheat_code", {"code": "MONEY50000"})
	authority.records[1]["connected"] = false
	authority.handle_request(1, "cheat_code", {"code": "MONEY50000"})
	authority.records[1]["connected"] = true
	authority.phase = "results"
	authority.handle_request(1, "cheat_code", {"code": "MONEY50000"})
	check(cheat_events.size() == events and authority.revision == revision and authority.get_profile(1) == before, "Unknown, disconnected and ended-session requesters cannot use codes")
	fresh(authority, city)
	authority.records[1]["profile"]["money"] = CAP
	authority.records[1]["profile"]["xp"] = CAP
	authority.records[1]["profile"]["level"] = 10
	authority.records[1]["profile"]["rank"] = "Delivery Master"
	var paid_order: Dictionary = {}
	for order: Dictionary in authority.orders:
		if order.get("type", "") == "standard" and str(order.get("event_id", "")).is_empty():
			paid_order = order.duplicate(true)
			break
	check(not paid_order.is_empty(), "Capped Host career still receives a real ordinary delivery")
	if not paid_order.is_empty():
		var earned_before: int = int(authority.get_profile(1)["total_money_earned"])
		var deliveries_before: int = int(authority.get_profile(1)["total_deliveries"])
		authority.handle_request(1, "accept", {"id": int(paid_order["id"])})
		authority.records[1]["position"] = paid_order["pickup_position"]
		authority.handle_request(1, "interact", {})
		check(authority.records[1]["active_order"].get("state", "") == "PickedUp", "Capped Host career can physically collect its parcel")
		authority.records[1]["position"] = paid_order["delivery_position"]
		authority.handle_request(1, "interact", {})
		var paid: Dictionary = authority.get_profile(1)
		var paid_stats: Dictionary = authority.records[1]["shift_stats"]
		check(authority.records[1]["active_order"].is_empty() and paid["money"] == CAP and paid["xp"] == CAP, "A legitimate Host delivery cannot overflow capped career money or XP")
		check(int(paid["total_deliveries"]) == deliveries_before + 1 and int(paid["total_money_earned"]) == earned_before + int(paid_order["reward"]), "The capped Host still credits only its actual completed delivery")
		check(int(paid_stats["deliveries"]) == 1 and int(paid_stats["money"]) == int(paid_order["reward"]) and int(paid_stats["xp"]) == int(paid_order["xp"]), "Actual Host shift earnings contain the delivery reward and exclude the capped career balance")
		var confirmed_paid: Dictionary = paid.duplicate(true)
		authority.handle_request(1, "interact", {})
		check(authority.get_profile(1) == confirmed_paid, "A repeated interaction cannot credit a capped Host delivery twice")
	authority.queue_free()
	city.queue_free()
	await process_frame

func career_with_name(player_name: String) -> Dictionary:
	var profile: Dictionary = career()
	profile["player_name"] = player_name
	return profile

func press_key(app, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	app._input(event)

func submit_entry(app, text: String, button: bool = false) -> void:
	app.hud._cheat_input.text = text
	if button:
		app.hud._cheat_apply.pressed.emit()
	else:
		app.hud._cheat_input.text_submitted.emit(text)

func freeze_app(app) -> void:
	app.set_process(false)
	app.player.set_physics_process(false)
	for owner_id: Variant in app.vehicles:
		app.vehicles[owner_id].set_physics_process(false)

func actual_vehicle_state(app) -> Dictionary:
	var result: Dictionary = {}
	for owner_id: Variant in app.vehicles:
		var vehicle = app.vehicles[owner_id]
		result[owner_id] = [vehicle.get_instance_id(), vehicle.transform, vehicle.occupied, vehicle.speed, vehicle.owner_peer_id]
	return result

func test_actual_menu_and_solo() -> void:
	var save_exists: bool = FileAccess.file_exists("user://profile.json")
	var saved_text: String = FileAccess.get_file_as_string("user://profile.json") if save_exists else ""
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	freeze_app(app)
	check(app.test_mode and not app._lan_active(), "Actual Main uses offline production logic with all personal writes disabled")
	app.profile = app.lan_authority._sanitize_profile(career())
	app._apply_profile_appearance()
	app.hud.show_menu(app.profile)
	check(app.hud.find_child("OpenCheatsMenu", true, false) != null and app.hud.find_child("OpenCheatsPause", true, false) != null, "Menu and pause offer visible cheat-code entry buttons")
	press_key(app, KEY_F2)
	await process_frame
	check(app.state == "menu" and app.modal == "cheats" and app.hud._cheats.visible and not app.player.controls_enabled, "F2 opens the actual profile-menu code dialog")
	check(app.hud._cheat_input.has_focus(), "The code entry receives keyboard focus")
	for code: String in EXPECTED_CODES:
		check(app.hud._cheat_help.text.contains(code), "The actual help lists " + code)
	var before: Dictionary = app.profile.duplicate(true)
	submit_entry(app, " money10000 ")
	check(app.profile["money"] == 19000 and app.profile["xp"] == before["xp"] and app.modal == "cheats", "Actual Enter signal grants money and keeps the code dialog open")
	preserved(app.profile, before, ["money"], "Profile-menu money code")
	check(not app.hud._cheat_notice.text.is_empty(), "Actual successful submission displays feedback")
	var granted: Dictionary = app.profile.duplicate(true)
	submit_entry(app, "MONEY10000;XP1000", true)
	check(app.profile == granted and not app.hud._cheat_notice.text.is_empty(), "Actual apply button rejects command-like text without a mutation")
	app.hud._cheat_input.text = "XP1000"
	app.hud._cheat_input.caret_column = 3
	app.hud.update_cheats_profile(app.profile)
	check(app.hud._cheat_input.text == "XP1000" and app.hud._cheat_input.caret_column == 3, "A confirmed profile-label refresh preserves entry text and caret")
	press_key(app, KEY_ESCAPE)
	check(app.state == "menu" and app.modal.is_empty() and not app.hud._cheats.visible and not app.player.controls_enabled, "Escape from profile codes restores the menu")

	app._begin_shift()
	freeze_app(app)
	check(app.modal == "orders", "Actual Solo starts at the order selector")
	press_key(app, KEY_F2)
	press_key(app, KEY_ESCAPE)
	check(app.modal == "orders" and not app.player.controls_enabled, "Closing codes restores the existing order selector")
	app._close_modal()
	app._open_map()
	press_key(app, KEY_F2)
	press_key(app, KEY_ESCAPE)
	check(app.modal == "map" and not app.player.controls_enabled, "Closing codes restores the existing map")
	app._close_modal()
	var selected: Dictionary = {}
	for order: Dictionary in app.orders:
		if order.get("type", "") == "standard" and not order.has("event_id"):
			selected = order.duplicate(true)
			break
	check(not selected.is_empty(), "Actual Solo supplies a regular order for modal-input checks")
	if not selected.is_empty():
		app._accept_order(int(selected["id"]))
		app.player.reset_at(selected["pickup_position"] + Vector3(0, 0.15, 0))
		await physics_frame
	var order_before: Dictionary = app.active_order.duplicate(true)
	var stats_before: Dictionary = app.shift_stats.duplicate(true)
	var vehicle_before: Dictionary = actual_vehicle_state(app)
	var offers_before: Array = app.orders.duplicate(true)
	var profile_before: Dictionary = app.profile.duplicate(true)
	press_key(app, KEY_F2)
	check(app.modal == "cheats" and not app.player.controls_enabled and not app._can_interact(), "F2 disables interaction while the courier types beside a real pickup")
	for key: int in [KEY_E, KEY_F, KEY_M, KEY_TAB, KEY_SPACE, KEY_W]:
		press_key(app, key)
		check(app.modal == "cheats" and app.active_order == order_before and actual_vehicle_state(app) == vehicle_before, "Typing gameplay keys cannot interact, mount, open orders/map or move transport")
	submit_entry(app, "xp1000", true)
	check(app.profile["xp"] == int(profile_before["xp"]) + 1000 and app.profile["money"] == profile_before["money"], "Actual Solo apply button grants only requested XP")
	submit_entry(app, "ALLVEHICLES")
	check(app.profile["owned_vehicles"].size() == definitions.size() and actual_vehicle_state(app) == vehicle_before and app.player.riding_vehicle == null, "Actual ALLVEHICLES grants ownership without spawning or riding")
	check(app.active_order == order_before and app.orders == offers_before and app.shift_stats == stats_before, "Solo codes preserve the accepted order, deadlines, offers and shift results")
	preserved(app.profile, profile_before, ["xp", "level", "rank", "owned_vehicles"], "Actual Solo codes")
	press_key(app, KEY_ESCAPE)
	check(app.state == "playing" and app.modal.is_empty() and app.player.controls_enabled, "Escape closes playing codes and restores gameplay without pausing")

	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(0, 0.15, -3))
	app._open_garage()
	press_key(app, KEY_F2)
	press_key(app, KEY_ESCAPE)
	check(app.modal == "garage" and not app.player.controls_enabled, "Codes safely restore the existing garage")
	app._open_customization()
	press_key(app, KEY_F2)
	press_key(app, KEY_ESCAPE)
	check(app.modal == "customization" and not app.player.controls_enabled, "Codes safely restore existing customization")
	app._close_customization()
	app._close_modal()
	app._pause()
	var frozen: float = app._solo_elapsed_seconds
	var remaining: float = app.shift_remaining
	press_key(app, KEY_F2)
	check(app.state == "paused" and app.modal == "cheats", "F2 is available in an actual paused Solo game")
	submit_entry(app, "MONEY50000")
	app._process(30.0)
	check(app._solo_elapsed_seconds == frozen and app.shift_remaining == remaining, "Paused code entry keeps Solo shift and event clocks frozen")
	press_key(app, KEY_ESCAPE)
	check(app.state == "paused" and app.modal.is_empty() and not app.player.controls_enabled, "Closing paused codes preserves the paused state")
	app._open_settings()
	press_key(app, KEY_F2)
	check(app.modal == "settings" and not app.hud._cheats.visible, "F2 cannot replace an active settings modal")
	app._close_settings()
	app._resume()
	press_key(app, KEY_F2)
	app._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(app.state == "paused" and app.modal.is_empty() and not app.hud._cheats.visible and not app.player.controls_enabled, "Focus loss while typing closes codes and pauses Solo")
	app._resume()
	check(app.state == "playing" and app.player.controls_enabled, "Resume after focus loss restores controls")
	app._end_shift()
	press_key(app, KEY_F2)
	check(app.state == "results" and app.modal.is_empty() and not app.hud._cheats.visible, "Results cannot open the code dialog")
	app.profile = app.lan_authority._sanitize_profile(career())
	app.profile["xp"] = 0
	app.profile["level"] = 1
	app.profile["rank"] = "Rookie Courier"
	app.profile["owned_vehicles"] = []
	app.profile["selected_vehicle"] = ""
	app._begin_shift()
	freeze_app(app)
	press_key(app, KEY_F2)
	submit_entry(app, "ALLVEHICLES")
	check(app.profile["level"] == 1 and app.vehicles.is_empty() and app.profile["owned_vehicles"].size() == definitions.size(), "Actual starter ownership grant keeps all higher-level transport parked")
	press_key(app, KEY_ESCAPE)
	app._close_modal()
	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(0, 0.15, -3))
	var starter_before: Dictionary = app.profile.duplicate(true)
	app._spawn_vehicle("car")
	check(app.vehicles.is_empty() and app.profile == starter_before and app.player.riding_vehicle == null, "Normal garage spawning still rejects an owned car below its required level")
	app.profile["money"] = CAP
	app.profile["xp"] = CAP
	app.profile["level"] = 10
	app.profile["rank"] = "Delivery Master"
	app._begin_shift()
	freeze_app(app)
	var paid_order: Dictionary = {}
	for order: Dictionary in app.orders:
		if order.get("type", "") == "standard" and str(order.get("event_id", "")).is_empty():
			paid_order = order.duplicate(true)
			break
	check(not paid_order.is_empty(), "Capped Solo career still receives a real ordinary delivery")
	if not paid_order.is_empty():
		var earned_before: int = int(app.profile["total_money_earned"])
		var deliveries_before: int = int(app.profile["total_deliveries"])
		app._accept_order(int(paid_order["id"]))
		app.player.reset_at(paid_order["pickup_position"] + Vector3(0, 0.15, 0))
		await physics_frame
		app._interact()
		check(app.active_order.get("state", "") == "PickedUp", "Capped Solo career can physically collect its parcel")
		app.player.reset_at(paid_order["delivery_position"] + Vector3(0, 0.15, 0))
		await physics_frame
		app._interact()
		check(app.active_order.is_empty() and app.profile["money"] == CAP and app.profile["xp"] == CAP, "A legitimate Solo delivery cannot overflow capped career money or XP")
		check(int(app.profile["total_deliveries"]) == deliveries_before + 1 and int(app.profile["total_money_earned"]) == earned_before + int(paid_order["reward"]), "Capped Solo still credits only its actual completed delivery")
		check(int(app.shift_stats["deliveries"]) == 1 and int(app.shift_stats["money"]) == int(paid_order["reward"]) and int(app.shift_stats["xp"]) == int(paid_order["xp"]), "Actual Solo shift earnings contain only the completed delivery reward")
		var confirmed_paid: Dictionary = app.profile.duplicate(true)
		app._interact()
		check(app.profile == confirmed_paid, "A repeated interaction cannot credit a capped Solo delivery twice")
	check(app._save_profile(), "Normal profile save is a harmless success in test mode")
	check(FileAccess.file_exists("user://profile.json") == save_exists and (not save_exists or FileAccess.get_file_as_string("user://profile.json") == saved_text), "Actual code submissions never create or overwrite a personal save in --test-mode")
	app.queue_free()
	await process_frame
