extends SceneTree

# Deterministic timeline/security regressions plus real Solo and Host interactions.
# Fixtures only change trusted simulation time and starting positions. Production
# order acceptance, physics range checks, handoffs and reward paths stay intact.
const Rules = preload("res://scripts/district_event_rules.gd")
const WorldScript = preload("res://scripts/world.gd")
const AuthorityScript = preload("res://scripts/lan_authority.gd")
const ORIGIN: Vector3 = Vector3(-23.0, 0.15, 4.0)
var city
var authority
var config: Dictionary = {}
var balance: Dictionary = {}
var checks: int = 0
var failures: Array[String] = []
var session_sequence: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("District event tests require --test-mode")
		quit(2)
		return
	seed(120020)
	config = Rules.load_config()
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	city = WorldScript.new()
	root.add_child(city)
	authority = AuthorityScript.new()
	root.add_child(authority)
	await process_frame
	await physics_frame
	authority.set_process(false)
	test_config_and_timeline()
	test_real_event_pool()
	test_authoritative_claim()
	test_reward_and_deadlines()
	test_handoff_and_lifecycle()
	authority.queue_free()
	city.queue_free()
	await process_frame
	await test_solo_flow()
	print("DISTRICT_EVENT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fresh(mode: String = "competitive") -> void:
	session_sequence += 1
	authority.start_session({"shift_seconds": -1, "shift_mode": mode}, [
		{"id": 1, "name": "Courier one", "profile": {"xp": 0, "money": 0, "owned_vehicles": []}},
		{"id": 2, "name": "Courier two", "profile": {"xp": 0, "money": 0, "owned_vehicles": []}}
	], city, balance, "event-regression-%d" % session_sequence)
	authority.set_process(false)
	for id: int in authority.records:
		authority.records[id]["position"] = ORIGIN + Vector3(float(id - 1) * 0.7, 0, 0)

func elapsed(seconds: float) -> void:
	authority._started_at_msec = Time.get_ticks_msec() - int(seconds * 1000.0)
	authority._advance_clock(Time.get_ticks_msec())

func event_orders(pool: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order: Dictionary in pool:
		if not str(order.get("event_id", "")).is_empty():
			result.append(order)
	return result

func standard_orders(pool: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order: Dictionary in pool:
		if str(order.get("event_id", "")).is_empty():
			result.append(order)
	return result

func claim_first(peer_id: int = 1) -> Dictionary:
	var available: Array[Dictionary] = event_orders(authority.orders)
	check(not available.is_empty(), "An active district event creates an offer to accept")
	if available.is_empty():
		return {}
	var selected: Dictionary = available[0].duplicate(true)
	authority.handle_request(peer_id, "accept", {"id": int(selected["id"])})
	var accepted: Dictionary = authority.records[peer_id]["active_order"]
	check(int(accepted.get("id", 0)) == int(selected["id"]) and accepted.get("state", "") == "Accepted", "The ordinary server acceptance path owns the event order")
	return selected

func pick_up(peer_id: int) -> void:
	var active: Dictionary = authority.records[peer_id]["active_order"]
	if active.is_empty():
		return
	authority.records[peer_id]["position"] = active["pickup_position"]
	authority.handle_request(peer_id, "interact", {})
	check(authority.records[peer_id]["active_order"].get("state", "") == "PickedUp" and bool(authority.records[peer_id]["carrying"]), "Physical pickup validation produces a carried event parcel")

func finish(peer_id: int, seconds: float) -> void:
	var active: Dictionary = authority.records[peer_id]["active_order"]
	if active.is_empty():
		return
	authority.records[peer_id]["position"] = active["delivery_position"]
	authority._started_at_msec = Time.get_ticks_msec() - int(seconds * 1000.0)
	authority.handle_request(peer_id, "interact", {})

func test_config_and_timeline() -> void:
	check(float(config.get("first_start_seconds", 0)) == 45.0 and float(config.get("duration_seconds", 0)) == 180.0 and float(config.get("cooldown_seconds", 0)) == 300.0, "Default lunch event starts after 45 s, lasts 180 s and rests 300 s")
	check(int(config.get("available_orders", 0)) == 3 and float(config.get("bonus_multiplier", 0)) == 1.5 and float(config.get("maximum_route_meters", 0)) == 130.0, "Default offer count, payout and walking route cap match the advertised event")
	check(Rules.config_from_data({}) == config, "Missing event balance fields safely use defaults")
	var hostile: Dictionary = Rules.config_from_data({"first_start_seconds": "0", "duration_seconds": INF, "cooldown_seconds": NAN, "available_orders": 9999, "bonus_multiplier": -4.0, "maximum_route_meters": 99999.0})
	check(float(hostile["first_start_seconds"]) == 45.0 and float(hostile["duration_seconds"]) == 180.0 and float(hostile["cooldown_seconds"]) == 300.0, "Text and nonfinite timeline values cannot skip or corrupt a shift")
	check(int(hostile["available_orders"]) == 3 and float(hostile["bonus_multiplier"]) == 1.0 and float(hostile["maximum_route_meters"]) == 130.0, "Oversized pool, negative bonus and overly long routes remain bounded")
	var before: Dictionary = Rules.snapshot(44.999, true, config)
	var start: Dictionary = Rules.snapshot(45.0, true, config)
	var last: Dictionary = Rules.snapshot(224.999, true, config)
	var end: Dictionary = Rules.snapshot(225.0, true, config)
	var resting: Dictionary = Rules.snapshot(524.999, true, config)
	var next: Dictionary = Rules.snapshot(525.0, true, config)
	check(before.get("phase") == "waiting" and float(before.get("starts_in", 0)) > 0.0, "First event stays waiting until its exact start")
	check(start.get("phase") == "active" and start.get("id") == "lunch_rush:1" and float(start.get("remaining", 0)) == 180.0, "First start opens one identified 180-second event")
	check(last.get("phase") == "active" and float(last.get("remaining", 0)) > 0.0, "The final millisecond before the deadline stays active")
	check(end.get("phase") == "cooldown" and resting.get("phase") == "cooldown", "Exact deadline and later gap both stop the bonus window")
	check(next.get("phase") == "active" and next.get("id") == "lunch_rush:2" and float(next.get("starts_at", 0)) == 525.0, "The next event has a fresh identity after the full cooldown")
	check(Rules.snapshot(100.0, false, config).get("phase") == "ended", "An ended shift cannot keep an event active")
	for seconds: float in [0.0, 44.999, 45.0, 100.0, 224.999, 225.0, 524.999, 525.0, 704.999, 705.0, 100000.0]:
		var view: Dictionary = Rules.snapshot(seconds, true, config)
		check(float(view.get("remaining", -1)) >= 0 and float(view.get("starts_in", -1)) >= 0, "Published event timers never become negative at %.3f s" % seconds)

func test_real_event_pool() -> void:
	var active: Dictionary = Rules.snapshot(45.0, true, config)
	var pool: Array = []
	for sequence: int in range(3):
		var order: Dictionary = Rules.make_order(1000 + sequence, city.pickup_points, city.delivery_points, balance, active, config, pool)
		check(not order.is_empty(), "Real business district contains a valid bounded lunch route")
		if order.is_empty():
			continue
		pool.append(order)
		check(order.get("pickup_id") == "pickup_espresso" and str(order.get("delivery_id", "")).begins_with("delivery_"), "Lunch is collected at the real business cafe and sent to a real address")
		check(order.get("pickup_district_id") == "business" and order.get("delivery_district_id") == "business", "Lunch pickup and destination both belong to the business district")
		check(order.get("type") == "standard" and int(order.get("required_level", 0)) == 1, "A rookie pedestrian can accept lunch without Express or Fragile unlocks")
		check(float(order.get("distance", 9999)) <= 130.0 and float(order.get("distance", 0)) >= 8.0 and order.get("pickup_id") != order.get("delivery_id"), "Lunch route length stays feasible on foot and does not coincide")
		check(order.get("event_id") == active.get("id") and float(order.get("event_starts_at", 0)) == 45.0 and float(order.get("event_ends_at", 0)) == 225.0, "Each offer carries the absolute window of its own event")
		check(int(order.get("event_bonus", -1)) == int(floor(float(order["reward"]) * 0.5)), "Advertised bonus is separate from the base order reward")
	var pairs: Dictionary = {}
	for order: Dictionary in pool:
		var key: String = str(order["pickup_id"]) + ":" + str(order["delivery_id"])
		check(not pairs.has(key), "Current lunch offers use different destinations")
		pairs[key] = true
	check(Rules.make_order(99, city.pickup_points, city.delivery_points, balance, Rules.snapshot(225.0, true, config), config).is_empty(), "No offer is generated after the event closes")
	check(Rules.make_order(99, [], city.delivery_points, balance, active, config).is_empty(), "Missing cafe does not fabricate a pickup")
	check(Rules.make_order(99, city.pickup_points, [], balance, active, config).is_empty(), "Missing destinations do not fabricate a lunch order")
	fresh()
	check(standard_orders(authority.orders).size() == 6 and event_orders(authority.orders).is_empty(), "New shifts retain all six normal orders while waiting")
	elapsed(45.0)
	check(standard_orders(authority.orders).size() == 6 and event_orders(authority.orders).size() == 3, "Lunch adds three offers without replacing any of the six normal ones")
	var reserved_local: int = 0
	for normal: Dictionary in standard_orders(authority.orders):
		if normal.get("route_band", "") == "local" and normal.get("type", "") == "standard":
			reserved_local += 1
	check(reserved_local >= 2, "Lunch offers do not consume the two reserved ordinary local deliveries")
	var ids: Array[int] = []
	for order: Dictionary in authority.orders:
		check(not ids.has(int(order["id"])), "Normal and lunch orders have unique claim IDs")
		ids.append(int(order["id"]))
	var normal_ids: Array[int] = []
	for order: Dictionary in standard_orders(authority.orders):
		normal_ids.append(int(order["id"]))
	var expired_offer_id: int = int(event_orders(authority.orders)[0]["id"])
	elapsed(225.0)
	authority.handle_request(1, "accept", {"id": expired_offer_id, "event_ends_at": 999999.0})
	check(authority.records[1]["active_order"].is_empty(), "A stale unclaimed offer cannot be accepted at or after its deadline")
	check(event_orders(authority.orders).is_empty() and standard_orders(authority.orders).size() == 6, "Unclaimed lunch offers disappear exactly when the window ends")
	for order: Dictionary in standard_orders(authority.orders):
		check(normal_ids.has(int(order["id"])), "Ending lunch does not regenerate or steal existing normal orders")
	elapsed(525.0)
	check(event_orders(authority.orders).size() == 3 and event_orders(authority.orders)[0].get("event_id") == "lunch_rush:2", "The second window creates fresh offers with its new event identity")

func test_authoritative_claim() -> void:
	fresh()
	elapsed(45.0)
	var available: Array[Dictionary] = event_orders(authority.orders)
	if available.is_empty():
		check(false, "Active event supplies a claim target")
		return
	var original: Dictionary = available[0].duplicate(true)
	var spoof: Dictionary = {"id": int(original["id"]), "reward": 99999999, "xp": 99999999, "event_bonus": 99999999, "event_bonus_multiplier": 1000000.0, "event_ends_at": 99999999.0, "delivery_position": ORIGIN}
	authority.handle_request(1, "accept", spoof)
	authority.handle_request(2, "accept", spoof)
	var owned: Dictionary = authority.records[1]["active_order"]
	check(int(owned.get("id", 0)) == int(original["id"]) and authority.records[2]["active_order"].is_empty(), "Only the first claimant owns a shared lunch parcel")
	for key: String in ["reward", "xp", "event_bonus", "event_bonus_multiplier", "event_ends_at", "delivery_position"]:
		check(owned.get(key) == original.get(key), "Client claim cannot replace authoritative %s" % key)
	authority.handle_request(1, "accept", {"id": int(original["id"])})
	check(int(authority.records[1]["active_order"].get("id", 0)) == int(original["id"]) and int(authority.get_profile(1)["money"]) == 0, "A repeated accept never duplicates the parcel or grants money")
	check(standard_orders(authority.orders).size() == 6 and event_orders(authority.orders).size() <= 3, "Claims refill only the bounded event pool and preserve normal work")
	pick_up(1)
	var original_id: int = int(owned["id"])
	authority.records[1]["position"] = ORIGIN
	authority.handle_request(1, "interact", spoof)
	check(int(authority.records[1]["active_order"].get("id", 0)) == original_id and int(authority.get_profile(1)["money"]) == 0, "Claiming a fake destination or reward cannot bypass physical delivery range")
	finish(1, 100.0)
	var reward: int = int(original["reward"])
	var extra: int = int(floor(float(reward) * 0.5))
	check(int(authority.get_profile(1)["money"]) == reward + extra and int(authority.get_profile(1)["xp"]) == int(original["xp"]), "Server completion calculates exactly 50 percent extra and unchanged XP")
	check(int(authority.get_profile(2)["money"]) == 0 and int(authority.get_profile(2)["total_deliveries"]) == 0, "Losing claimant receives no money or delivery credit")
	var paid: Dictionary = authority.get_profile(1)
	var stats: Dictionary = authority.records[1]["shift_stats"].duplicate(true)
	authority.handle_request(1, "interact", spoof)
	authority.snapshot_for(1)
	authority.snapshot_for(1)
	check(authority.get_profile(1) == paid and authority.records[1]["shift_stats"] == stats, "Repeated completion requests and snapshot reads cannot pay twice")

func test_reward_and_deadlines() -> void:
	var event: Dictionary = Rules.snapshot(45.0, true, config)
	var order: Dictionary = Rules.make_order(5000, city.pickup_points, city.delivery_points, balance, event, config)
	if order.is_empty():
		check(false, "Reward fixture uses a real event order")
		return
	var base: int = int(order["reward"])
	var bonus: int = int(floor(float(base) * 0.5))
	check(Rules.bonus_for_delivery(order, base, 44.999, config) == 0, "A future event cannot pay its bonus early")
	check(Rules.bonus_for_delivery(order, base, 45.0, config) == bonus and Rules.bonus_for_delivery(order, base, 224.999, config) == bonus, "Bonus applies at start and through the last millisecond")
	check(Rules.bonus_for_delivery(order, base, 225.0, config) == 0 and Rules.bonus_for_delivery(order, base, 525.0, config) == 0, "Exact deadline and later events cannot revive an old parcel bonus")
	var malformed: Dictionary = order.duplicate(true)
	malformed["event_id"] = "lunch_rush:999"
	check(Rules.bonus_for_delivery(malformed, base, 100.0, config) == 0, "A fabricated event identity receives no bonus")
	malformed = order.duplicate(true)
	malformed["event_ends_at"] = 999999.0
	check(Rules.bonus_for_delivery(malformed, base, 100.0, config) == 0, "An extended parcel deadline cannot alter the authoritative window")
	check(Rules.bonus_for_delivery({}, base, 100.0, config) == 0, "A normal delivery cannot collect an event bonus")
	for seconds: float in [224.0, 225.0, 226.0, 525.0]:
		fresh()
		elapsed(45.0)
		var selected: Dictionary = claim_first()
		if selected.is_empty():
			continue
		pick_up(1)
		var before: Dictionary = authority.records[1]["active_order"].duplicate(true)
		elapsed(seconds)
		check(int(authority.records[1]["active_order"].get("id", 0)) == int(before["id"]) and bool(authority.records[1]["carrying"]), "Already picked lunch survives event close at %.0f s" % seconds)
		finish(1, seconds)
		var paid_bonus: int = int(floor(float(selected["reward"]) * 0.5)) if seconds < 225.0 else 0
		var money: int = int(selected["reward"]) + paid_bonus
		check(authority.records[1]["active_order"].is_empty() and int(authority.get_profile(1)["money"]) == money, "Completion at %.0f s pays the correct base plus eligible bonus" % seconds)
		check(int(authority.records[1]["shift_stats"].get("event_deliveries", -1)) == 1 and int(authority.records[1]["shift_stats"].get("event_bonus_money", -1)) == paid_bonus, "Event delivery and bonus statistics stay separate at %.0f s" % seconds)
		check(int(authority.get_profile(1)["total_money_earned"]) == money and int(authority.get_profile(1)["best_shift"]) == money and int(authority.records[1]["shift_stats"]["best_delivery"]) == money, "Career, best shift and best delivery include only actually paid money")
		check(int(authority.snapshot_for(2).get("district_event", {}).get("delivered", -1)) == 1 and int(authority.snapshot_for(2).get("district_event", {}).get("bonus_money", -1)) == paid_bonus, "Shared event totals match the finisher's confirmed payment")
	fresh()
	elapsed(45.0)
	var selected: Dictionary = claim_first()
	elapsed(225.0)
	check(authority.records[1]["active_order"].get("state", "") == "Accepted", "An accepted but not yet picked lunch also survives the deadline")
	pick_up(1)
	finish(1, 226.0)
	check(int(authority.get_profile(1)["money"]) == int(selected.get("reward", 0)), "A parcel collected after lunch closes remains worth its base payout")

func test_handoff_and_lifecycle() -> void:
	for late: bool in [false, true]:
		fresh("team")
		elapsed(45.0)
		var selected: Dictionary = claim_first()
		if selected.is_empty():
			continue
		pick_up(1)
		authority.records[1]["position"] = ORIGIN
		authority.records[2]["position"] = ORIGIN + Vector3(0.7, 0, 0)
		authority.handle_request(1, "offer_handoff", {"target_id": 2})
		var proposals: Array = authority.snapshot_for(2).get("handoffs", {}).get("incoming", [])
		check(not proposals.is_empty(), "A carried lunch uses the same nearby Team Shift handoff")
		if proposals.is_empty():
			continue
		var proposal: Dictionary = proposals[0].duplicate(true)
		var before: Dictionary = authority.records[1]["active_order"].duplicate(true)
		authority.handle_request(2, "accept_handoff", {"sender_id": 1, "offer_id": proposal["offer_id"]})
		var received: Dictionary = authority.records[2]["active_order"]
		check(authority.records[1]["active_order"].is_empty() and int(received.get("owner_id", 0)) == 2, "Handoff changes one parcel owner atomically")
		for key: String in ["event_id", "event_name", "event_starts_at", "event_ends_at", "event_bonus_multiplier", "event_bonus", "reward", "xp", "accepted_msec", "pickup_msec"]:
			check(received.get(key) == before.get(key), "Lunch handoff preserves original %s" % key)
		authority.handle_request(2, "accept_handoff", {"sender_id": 1, "offer_id": proposal["offer_id"]})
		check(int(authority.get_profile(1)["money"]) == 0 and int(authority.get_profile(2)["money"]) == 0, "Repeated handoff acceptance grants no early reward")
		finish(2, 226.0 if late else 100.0)
		var extra: int = 0 if late else int(floor(float(selected["reward"]) * 0.5))
		check(int(authority.get_profile(2)["money"]) == int(selected["reward"]) + extra and int(authority.get_profile(2)["total_deliveries"]) == 1, "Only the handoff finisher receives the eligible lunch reward")
		check(int(authority.get_profile(1)["money"]) == 0 and int(authority.get_profile(1)["total_deliveries"]) == 0, "Sender gets no duplicate delivery or lunch credit")
		check(int(authority.snapshot_for(2).get("team", {}).get("delivered", 0)) == 1, "A handed-off lunch advances the shared Team Shift goal exactly once")
		var paid: Dictionary = authority.get_profile(2)
		authority.handle_request(1, "interact", {})
		authority.handle_request(2, "interact", {})
		check(authority.get_profile(2) == paid, "A transferred parcel cannot be completed or rewarded twice")
	fresh("team")
	elapsed(45.0)
	claim_first()
	pick_up(1)
	authority.records[1]["position"] = ORIGIN
	authority.records[2]["position"] = ORIGIN + Vector3(0.7, 0, 0)
	authority.handle_request(1, "offer_handoff", {"target_id": 2})
	authority.remove_player(2)
	check(not authority.records[1]["active_order"].is_empty() and authority.snapshot_for(1).get("handoffs", {}).get("outgoing", {}).is_empty(), "Recipient disconnect cancels the proposal and retains the sender's lunch")
	authority._finish_shift()
	check(authority.phase == "results" and authority.records[1]["active_order"].is_empty() and authority.snapshot_for(1).get("district_event", {}).get("phase") == "ended", "Shift results end the event and clear carried lunch")
	var prior_profile: Dictionary = authority.get_profile(1)
	authority.handle_request(1, "interact", {"reward": 999999})
	check(authority.get_profile(1) == prior_profile, "A completion packet after shift end grants no reward")
	fresh()
	check(authority.snapshot_for(1).get("district_event", {}).get("phase") == "waiting" and int(authority.records[1]["shift_stats"].get("event_deliveries", -1)) == 0, "A fresh shift resets event timing and personal event statistics")
	check(int(authority.snapshot_for(1).get("district_event", {}).get("delivered", -1)) == 0 and int(authority.snapshot_for(1).get("district_event", {}).get("bonus_money", -1)) == 0, "New session clears shared event totals")
	authority.stop_session()
	check(authority.snapshot_for(1).get("district_event", {}).get("phase") == "ended", "Stopping a session cannot leave an active district event")

func test_solo_flow() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.set_process(false)
	check(app.test_mode and not app._lan_active(), "Solo harness uses the regular offline app with profile writes disabled")
	for late: bool in [false, true]:
		app._begin_shift()
		app.set_process(false)
		app._solo_elapsed_seconds = 45.0
		app._advance_solo_event()
		check(event_orders(app.orders).size() == 3 and standard_orders(app.orders).size() == 6, "Actual Solo event opens the additional lunch pool")
		var available: Array[Dictionary] = event_orders(app.orders)
		if available.is_empty():
			continue
		var selected: Dictionary = available[0].duplicate(true)
		var before_money: int = int(app.profile["money"])
		var before_xp: int = int(app.profile["xp"])
		var before_deliveries: int = int(app.profile["total_deliveries"])
		app._accept_order(int(selected["id"]))
		check(int(app.active_order.get("id", 0)) == int(selected["id"]) and app.active_order.get("state") == "Accepted", "Solo UI acceptance owns a lunch order through production logic")
		app.player.reset_at(selected["pickup_position"] + Vector3(0, 0.15, 0))
		await physics_frame
		app._interact()
		check(app.active_order.get("state", "") == "PickedUp" and app.player.is_carrying, "Solo E at the real cafe picks up and shows the parcel")
		app._solo_elapsed_seconds = 225.0 if late else 100.0
		app._advance_solo_event()
		check(int(app.active_order.get("id", 0)) == int(selected["id"]), "Closing a Solo event retains its already accepted parcel")
		app.player.reset_at(selected["delivery_position"] + Vector3(0, 0.15, 0))
		await physics_frame
		app._interact()
		var extra: int = 0 if late else int(floor(float(selected["reward"]) * 0.5))
		var expected: int = int(selected["reward"]) + extra
		check(app.active_order.is_empty() and not app.player.is_carrying, "Solo E at the real office completes and clears the lunch")
		check(int(app.profile["money"]) == before_money + expected and int(app.profile["xp"]) == before_xp + int(selected["xp"]) and int(app.profile["total_deliveries"]) == before_deliveries + 1, "Solo payment matches Host policy for %s delivery" % ("late" if late else "on-time"))
		check(int(app.shift_stats.get("event_deliveries", -1)) == 1 and int(app.shift_stats.get("event_bonus_money", -1)) == extra, "Solo result statistics count one event delivery and its actual bonus")
		var paid: Dictionary = app.profile.duplicate(true)
		app._interact()
		check(app.profile == paid, "A repeated Solo E cannot pay the completed event again")
	app._begin_shift()
	app.set_process(false)
	app._solo_elapsed_seconds = 100.0
	app._advance_solo_event()
	var frozen: float = app._solo_elapsed_seconds
	app._pause()
	app._process(30.0)
	check(app.state == "paused" and app._solo_elapsed_seconds == frozen, "Solo pause freezes the event timeline")
	app._resume()
	app._process(1.0)
	check(is_equal_approx(app._solo_elapsed_seconds, frozen + 1.0), "Solo event time resumes with gameplay")
	app._end_shift()
	check(app._district_event_view().get("phase") == "ended", "Solo results stop district bonuses")
	app._begin_shift()
	app.set_process(false)
	check(app._solo_elapsed_seconds == 0.0 and app._district_event_view().get("phase") == "waiting" and event_orders(app.orders).is_empty(), "Restarting Solo resets event timing, offers and results")
	app.queue_free()
	await process_frame

