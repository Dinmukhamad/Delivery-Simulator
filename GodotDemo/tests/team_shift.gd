extends SceneTree

const WorldScript = preload("res://scripts/world.gd")
const AuthorityScript = preload("res://scripts/lan_authority.gd")
const FragileRules = preload("res://scripts/fragile_rules.gd")
var city
var authority
var checks: int = 0
var failures: Array[String] = []
var order_sequence: int = 10000
var events: Array[Dictionary] = []
const ORIGIN: Vector3 = Vector3(-23.0, 0.15, 4.0)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("Team tests require --test-mode")
		quit(2)
		return
	city = WorldScript.new()
	root.add_child(city)
	authority = AuthorityScript.new()
	root.add_child(authority)
	authority.event_ready.connect(func(peer_id: int, event: Dictionary) -> void:
		events.append({"peer_id": peer_id, "event": event.duplicate(true)}))
	await process_frame
	await physics_frame
	test_transfer_validation()
	await test_line_of_sight()
	test_transfer_preservation()
	test_offer_lifecycle()
	test_team_reward()
	test_shift_lifecycle()
	authority.queue_free()
	city.queue_free()
	await process_frame
	print("TEAM_SHIFT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fresh(mode: String = "team", count: int = 4) -> void:
	var roster: Array = []
	for id: int in range(1, count + 1):
		roster.append({"id": id, "name": "Courier %d" % id, "profile": {"money": 0, "xp": 10000, "owned_vehicles": [], "selected_vehicle": ""}})
	authority.start_session({"shift_seconds": -1, "shift_mode": mode}, roster, city, {}, "team-test-%d" % order_sequence)
	for id: int in authority.records:
		authority.records[id]["position"] = ORIGIN + Vector3(float(id - 1) * 0.7, 0, 0)
	events.clear()

func parcel(peer_id: int, kind: String = "standard", state: String = "PickedUp") -> Dictionary:
	var value: Dictionary = authority.orders[0].duplicate(true)
	order_sequence += 1
	value.merge({"id": order_sequence, "owner_id": peer_id, "type": kind, "state": state, "title": "Test parcel", "reward": 200, "base_reward": 200, "xp": 50, "required_level": 1, "time_limit": 60.0, "accepted_msec": Time.get_ticks_msec() - 2000, "pickup_msec": Time.get_ticks_msec() - 1000, "pickup_position": ORIGIN, "delivery_position": ORIGIN + Vector3(0, 0, 4)}, true)
	if kind == "express":
		value["required_level"] = 3
		value["deadline_msec"] = Time.get_ticks_msec() + 60000
	if kind == "fragile":
		value["required_level"] = 5
		value.merge(FragileRules.initial_fields({}), true)
		value["quality"] = 61.0
		value["quality_bonus"] = 61
		value["last_impact_msec"] = Time.get_ticks_msec() - 250
	authority.records[peer_id]["active_order"] = value
	authority.records[peer_id]["carrying"] = state == "PickedUp"
	return value.duplicate(true)

func incoming(peer_id: int) -> Array:
	return authority.snapshot_for(peer_id).get("handoffs", {}).get("incoming", [])

func outgoing(peer_id: int) -> Dictionary:
	return authority.snapshot_for(peer_id).get("handoffs", {}).get("outgoing", {})

func offer(sender_id: int = 1, target_id: int = 2) -> Dictionary:
	authority.handle_request(sender_id, "offer_handoff", {"target_id": target_id})
	var pending: Array = incoming(target_id)
	return {} if pending.is_empty() else pending[0].duplicate(true)

func accept(target_id: int, proposal: Dictionary) -> void:
	authority.handle_request(target_id, "accept_handoff", {"sender_id": int(proposal.get("sender_id", 0)), "offer_id": proposal.get("offer_id")})

func no_transfer(message: String) -> void:
	check(not authority.records[1]["active_order"].is_empty() and authority.records[2]["active_order"].is_empty(), message)

func complete(peer_id: int) -> void:
	if authority.records[peer_id]["active_order"].is_empty():
		parcel(peer_id)
	var target: Vector3 = authority.records[peer_id]["active_order"]["delivery_position"]
	authority.records[peer_id]["position"] = target
	authority.handle_request(peer_id, "interact", {})

func test_transfer_validation() -> void:
	fresh("competitive")
	parcel(1)
	check(offer().is_empty(), "Competitive mode does not offer parcels")
	no_transfer("Competitive mode retains ownership")
	fresh()
	parcel(1, "standard", "Accepted")
	check(offer().is_empty(), "Unpicked parcel cannot be offered")
	fresh()
	parcel(1)
	check(offer(1, 1).is_empty() and outgoing(1).is_empty(), "Cannot offer a parcel to yourself")
	authority.handle_request(1, "offer_handoff", {"target_id": "2"})
	check(incoming(2).is_empty(), "Wrong target payload type rejected")
	authority.handle_request(999, "offer_handoff", {"target_id": 2})
	check(incoming(2).is_empty(), "Unknown sender cannot create an offer")
	authority.records[2]["position"] = ORIGIN + Vector3(8, 0, 0)
	check(offer().is_empty(), "Remote recipient cannot receive an offer")
	authority.records[2]["position"] = ORIGIN + Vector3(0.7, 0, 0)
	authority.records[1]["vehicle"] = {"type": "bicycle", "occupied": true}
	check(offer().is_empty(), "Riding sender cannot hand off")
	authority.records[1]["vehicle"] = {}
	authority.records[2]["vehicle"] = {"type": "bicycle", "occupied": true}
	check(offer().is_empty(), "Riding receiver cannot receive")
	authority.records[2]["vehicle"] = {}
	parcel(2)
	check(offer().is_empty(), "Busy recipient cannot receive")
	authority.records[2]["active_order"] = {}
	authority.records[2]["carrying"] = false
	var proposal: Dictionary = offer()
	check(not proposal.is_empty(), "Valid nearby empty recipient receives proposal")
	if proposal.is_empty():
		return
	check(incoming(3).is_empty() and outgoing(3).is_empty(), "Other peer cannot see private proposal")
	accept(3, proposal)
	no_transfer("Wrong recipient cannot accept a private proposal")
	authority.handle_request(2, "accept_handoff", {"sender_id": 1, "offer_id": int(proposal["offer_id"]) + 999})
	no_transfer("Wrong proposal token does not transfer ownership")
	authority.records[2]["position"] = ORIGIN + Vector3(8, 0, 0)
	accept(2, proposal)
	no_transfer("Accept rechecks current range")
	fresh()
	parcel(1)
	proposal = offer()
	authority.records[2]["vehicle"] = {"type": "bicycle", "occupied": true}
	accept(2, proposal)
	no_transfer("Accept rechecks current riding state")
	fresh()
	parcel(1)
	proposal = offer()
	parcel(2)
	accept(2, proposal)
	check(int(authority.records[1]["active_order"]["owner_id"]) == 1 and int(authority.records[2]["active_order"]["owner_id"]) == 2, "Accept cannot overwrite a new recipient order")
	fresh()
	parcel(1, "fragile")
	authority.records[2]["profile"]["level"] = 1
	authority.orders[0]["type"] = "fragile"
	authority.handle_request(2, "accept", {"id": int(authority.orders[0]["id"])})
	check(authority.records[2]["active_order"].is_empty(), "Normal order acceptance remains level-gated")
	proposal = offer()
	accept(2, proposal)
	check(authority.records[2]["active_order"].get("type") == "fragile" and int(authority.records[2]["active_order"].get("required_level", 0)) == 5 and float(authority.records[2]["active_order"].get("quality", 0)) == 61.0, "Cooperation allows a lower-level receiver to finish an already picked fragile parcel without changing its requirements")

func test_line_of_sight() -> void:
	fresh()
	parcel(1)
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 1
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.15, 3.0, 2.0)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = ORIGIN + Vector3(0.35, 1.0, 0)
	city.add_child(wall)
	await physics_frame
	check(offer().is_empty(), "A real physics wall blocks proposal")
	wall.queue_free()
	await physics_frame
	var proposal: Dictionary = offer()
	check(not proposal.is_empty(), "Unobstructed proposal is possible")
	wall = StaticBody3D.new()
	wall.collision_layer = 1
	collider = CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = ORIGIN + Vector3(0.35, 1.0, 0)
	city.add_child(wall)
	await physics_frame
	accept(2, proposal)
	no_transfer("Accept rechecks line of sight after proposal")
	wall.queue_free()
	await physics_frame

func test_transfer_preservation() -> void:
	for kind: String in ["standard", "express", "fragile"]:
		fresh()
		var original: Dictionary = parcel(1, kind)
		var before_sender: Dictionary = authority.get_profile(1)
		var before_receiver: Dictionary = authority.get_profile(2)
		var proposal: Dictionary = offer()
		accept(2, proposal)
		var received: Dictionary = authority.records[2]["active_order"]
		check(authority.records[1]["active_order"].is_empty() and not bool(authority.records[1]["carrying"]), "%s transfer clears sender parcel" % kind)
		check(not received.is_empty() and int(received.get("owner_id", 0)) == 2 and bool(authority.records[2]["carrying"]), "%s transfer changes owner atomically" % kind)
		if received.is_empty():
			continue
		for key: String in ["id", "state", "type", "reward", "xp", "required_level", "time_limit", "accepted_msec", "pickup_msec", "pickup_position", "delivery_position"]:
			check(received.get(key) == original.get(key), "%s transfer preserves %s" % [kind, key])
		if kind == "express":
			check(received["deadline_msec"] == original["deadline_msec"], "Express deadline never resets during handoff")
		if kind == "fragile":
			check(received["quality"] == original["quality"] and received["quality_bonus"] == original["quality_bonus"] and received["last_impact_msec"] == original["last_impact_msec"], "Fragile condition and collision cooldown preserved")
		check(authority.get_profile(1) == before_sender and authority.get_profile(2) == before_receiver, "Handoff itself grants no money or XP")
		check(incoming(2).is_empty() and outgoing(1).is_empty(), "Completed proposal removed from both private snapshots")
		accept(2, proposal)
		accept(3, proposal)
		check(int(authority.records[2]["active_order"]["id"]) == int(original["id"]) and authority.records[3]["active_order"].is_empty(), "Repeated and competing accepts cannot duplicate parcel")
		complete(2)
		var paid: Dictionary = authority.get_profile(2)
		check(authority.records[2]["active_order"].is_empty() and int(paid["total_deliveries"]) == 1, "Only finishing recipient receives normal delivery credit")
		check(int(authority.get_profile(1)["total_deliveries"]) == 0 and int(authority.get_profile(1)["money"]) == 0, "Sender cannot farm delivery credit via handoff")
		authority.handle_request(2, "interact", {})
		check(authority.get_profile(2) == paid, "Duplicate delivery request does not pay twice")

func test_offer_lifecycle() -> void:
	fresh()
	parcel(1)
	var proposal: Dictionary = offer()
	authority.handle_request(2, "decline_handoff", {"sender_id": 1, "offer_id": proposal.get("offer_id")})
	check(incoming(2).is_empty() and outgoing(1).is_empty(), "Recipient can decline a proposal")
	no_transfer("Declined proposal retains sender ownership")
	proposal = offer()
	authority.handle_request(1, "cancel_handoff", {})
	check(incoming(2).is_empty() and outgoing(1).is_empty(), "Sender can cancel a proposal")
	proposal = offer()
	authority.handle_request(1, "abandon", {})
	parcel(1)
	accept(2, proposal)
	no_transfer("Stale token cannot transfer a replacement order")
	proposal = offer()
	if authority._handoff_offers.has(1):
		authority._handoff_offers[1]["deadline_msec"] = Time.get_ticks_msec() - 1
	accept(2, proposal)
	check(incoming(2).is_empty() and outgoing(1).is_empty(), "Expired proposal clears without transfer")
	no_transfer("Ten-second proposal expiry preserves ownership")
	proposal = offer()
	authority.remove_player(2)
	check(outgoing(1).is_empty(), "Recipient disconnect removes sender proposal")
	check(not authority.records[1]["active_order"].is_empty(), "Recipient disconnect preserves sender parcel")
	fresh()
	parcel(1)
	proposal = offer()
	authority.remove_player(1)
	check(incoming(2).is_empty(), "Sender disconnect removes recipient proposal")
	fresh()
	parcel(1, "express")
	proposal = offer()
	authority.records[1]["active_order"]["deadline_msec"] = Time.get_ticks_msec() - 1
	accept(2, proposal)
	check(authority.records[1]["active_order"].is_empty() and authority.records[2]["active_order"].is_empty() and incoming(2).is_empty(), "Express expiry clears parcel and related proposal")

func test_team_reward() -> void:
	fresh()
	var team: Dictionary = authority.snapshot_for(1).get("team", {})
	var target: int = int(team.get("target", 0))
	check(bool(team.get("enabled", false)) and target > 0, "Team session has server-owned common goal")
	var initial_target: int = target
	authority.remove_player(4)
	check(int(authority.snapshot_for(1).get("team", {}).get("target", 0)) == initial_target, "Disconnect never shrinks initial team target")
	for index: int in range(maxi(0, target - 1)):
		parcel(1)
		complete(1)
	check(not bool(authority.snapshot_for(1).get("team", {}).get("completed", false)), "Incomplete goal grants no team bonus")
	check(int(authority.get_profile(1)["money"]) == maxi(0, target - 1) * 200, "Normal delivery payments remain separate from team bonus")
	parcel(2)
	complete(2)
	team = authority.snapshot_for(1).get("team", {})
	check(bool(team.get("completed", false)) and int(team.get("delivered", 0)) == target, "All connected peers share confirmed completed goal")
	check(int(authority.get_profile(1)["money"]) == maxi(0, target - 1) * 200 + 500 and int(authority.get_profile(2)["money"]) == 700, "Every connected finisher receives exactly 500 team money")
	check(int(authority.get_profile(1)["xp"]) == 10000 + maxi(0, target - 1) * 50 + 100 and int(authority.get_profile(2)["xp"]) == 10150, "Each eligible contributor receives exactly 100 team XP")
	check(int(authority.get_profile(3)["money"]) == 0 and int(authority.get_profile(4)["money"]) == 0, "Idle and disconnected players receive no bonus")
	check(int(authority.get_profile(2)["total_deliveries"]) == 1 and int(authority.records[2]["shift_stats"]["best_delivery"]) == 200, "Team bonus does not invent a delivery or best delivery")
	check(int(authority.get_profile(2)["total_money_earned"]) == 700 and int(authority.get_profile(2)["best_shift"]) == 700 and int(authority.records[2]["shift_stats"]["money"]) == 700, "Team bonus updates career earned money, best shift and leaderboard money")
	var once: Dictionary = authority.get_profile(2)
	authority.snapshot_for(2)
	authority.snapshot_for(2)
	authority._advance_clock(Time.get_ticks_msec())
	check(authority.get_profile(2) == once, "Snapshot replay and clock advancement never duplicate bonus")
	parcel(2)
	complete(2)
	check(int(authority.get_profile(2)["money"]) == 900 and int(authority.get_profile(2)["xp"]) == 10200, "Repeated deliveries after goal pay normal reward without another team bonus")
	parcel(3)
	complete(3)
	check(int(authority.get_profile(3)["money"]) == 700 and int(authority.get_profile(3)["xp"]) == 10150, "Late first contribution still receives its one-time team bonus")
	check(bool(authority.snapshot_for(3).get("team", {}).get("eligible", false)) and bool(authority.snapshot_for(3).get("team", {}).get("bonus_awarded", false)), "Personal team summary confirms contribution and once-only award")
	fresh()
	target = int(authority.snapshot_for(1).get("team", {}).get("target", 0))
	parcel(4)
	complete(4)
	authority.remove_player(4)
	for index: int in range(maxi(0, target - 1)):
		parcel(1)
		complete(1)
	check(int(authority.get_profile(4)["money"]) == 200 and int(authority.get_profile(4)["xp"]) == 10050 and not bool(authority.snapshot_for(4).get("team", {}).get("bonus_awarded", true)), "A disconnected finisher keeps normal progress but cannot claim completion bonus")
	fresh("team", 1)
	authority.records[1]["profile"]["xp"] = 0
	authority.records[1]["profile"]["level"] = 1
	authority.records[1]["profile"]["rank"] = "Rookie Courier"
	target = int(authority.snapshot_for(1).get("team", {}).get("target", 0))
	for index: int in range(maxi(0, target)):
		parcel(1)
		complete(1)
	check(int(authority.get_profile(1)["level"]) == 2 and str(authority.get_profile(1)["rank"]) == "City Courier", "Team XP recomputes career level and rank")
	fresh("competitive")
	parcel(1)
	complete(1)
	check(not bool(authority.snapshot_for(1).get("team", {}).get("enabled", false)) and int(authority.get_profile(1)["money"]) == 200, "Competitive shifts retain normal economy without team bonus")

func test_shift_lifecycle() -> void:
	fresh()
	parcel(1)
	offer()
	authority._finish_shift()
	check(authority.phase == "results" and incoming(2).is_empty() and outgoing(1).is_empty(), "Shift end clears pending proposals")
	authority.handle_request(2, "accept_handoff", {"sender_id": 1, "offer_id": 1})
	check(authority.records[2]["active_order"].is_empty(), "Results phase rejects handoff actions")
	check(bool(authority.snapshot_for(1).get("team", {}).get("enabled", false)), "Results retain team summary")
	fresh()
	check(int(authority.snapshot_for(1).get("team", {}).get("delivered", -1)) == 0 and not bool(authority.snapshot_for(1).get("team", {}).get("completed", true)), "Next shift resets team goal and contribution state")
	parcel(1)
	offer()
	authority.stop_session()
	check(incoming(2).is_empty() and outgoing(1).is_empty(), "Session stop clears all handoff proposals")
