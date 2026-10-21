extends SceneTree

const Rules = preload("res://scripts/city_order_rules.gd")
const CityLayout = preload("res://scripts/city_layout.gd")
const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
const Placement = preload("res://scripts/vehicle_placement.gd")
const WorldScript = preload("res://scripts/world.gd")
const AuthorityScript = preload("res://scripts/lan_authority.gd")
const VehicleScript = preload("res://scripts/vehicle_controller.gd")
var checks: int = 0
var failures: Array[String] = []
var config: Dictionary
var definitions: Dictionary
var balance: Dictionary
var pickups: Array = []
var destinations: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("City order tests require --test-mode")
		quit(2)
		return
	seed(110016)
	config = Rules.load_config()
	definitions = VehicleCatalog.load_definitions()
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	make_points()
	test_mobility()
	test_generated_routes()
	test_selection_and_timing()
	await test_expanded_authority()
	print("CITY_ORDER_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func make_points() -> void:
	var positions: Array[Vector3] = [Vector3(-23, 0, 10), Vector3(-66, 0, -32), Vector3(180, 0, -160), Vector3(180, 0, 40), Vector3(-190, 0, -180), Vector3(-190, 0, 150)]
	var ids: Array[String] = ["warehouse", "coffee", "business_pickup", "civic_pickup", "industrial_pickup", "residential_pickup"]
	for index: int in range(positions.size()):
		pickups.append({"id": ids[index], "name": ids[index], "position": positions[index], "district_id": "district_%d" % index, "district_name": "Район %d" % index})
	destinations.append({"id": "house_01", "name": "Дом 1", "position": Vector3(12, 0, 10), "district_id": "district_0", "district_name": "Район 0"})
	for index: int in range(positions.size()):
		destinations.append({"id": "address_%d" % index, "name": "Адрес %d" % index, "position": positions[index] + Vector3(25, 0, 15), "district_id": "district_%d" % index, "district_name": "Район %d" % index})


func test_mobility() -> void:
	check(Rules.mobility_for_profile({"level": 10, "owned_vehicles": []}, definitions) == "walk", "Level alone does not create long motor routes")
	check(Rules.mobility_for_profile({"level": 1, "owned_vehicles": ["car"]}, definitions) == "walk", "An owned but locked vehicle does not unlock long routes")
	check(Rules.mobility_for_profile({"level": 2, "owned_vehicles": ["bicycle"]}, definitions) == "bicycle", "A bought and unlocked bicycle extends route choices")
	check(Rules.mobility_for_profile({"level": 4, "owned_vehicles": ["scooter"]}, definitions) == "scooter", "A bought scooter extends route choices")
	check(Rules.mobility_for_profile({"level": 6, "owned_vehicles": ["car", "bicycle"]}, definitions) == "car", "The best usable owned transport determines the route cap")
	check(Rules.mobility_for_profile({"level": 10, "owned_vehicles": "car"}, definitions) == "walk", "Malformed ownership remains on foot")


func test_generated_routes() -> void:
	var types: Array[String] = ["walk", "bicycle", "scooter", "car"]
	var levels: Array[int] = [1, 2, 4, 6]
	for index: int in range(types.size()):
		var courier: Dictionary = {"profile": {"level": levels[index], "owned_vehicles": [] if types[index] == "walk" else [types[index]]}, "position": Vector3(-23, 0, 4)}
		for sequence: int in range(32):
			var order: Dictionary = Rules.make_order(sequence + 1, pickups, destinations, balance, [courier], definitions, config)
			check(not order.is_empty() and float(order["distance"]) <= float(config["route_cap_meters"][types[index]]) and order["pickup_id"] != order["delivery_id"], "%s routes stay within the mobility cap and use different addresses" % types[index])
			if order.is_empty():
				continue
			check(float(order["distance"]) >= 8.0 and int(order["reward"]) <= int(round((160 + round(float(order["distance"]) * 3.5)) * 1.5)) and int(order["xp"]) <= 75, "Long trips keep existing economy multipliers and XP")
	var first: Dictionary = Rules.make_order(1, pickups, destinations, balance, [{"profile": {"level": 1, "owned_vehicles": []}, "position": Vector3(-23, 0, 4)}], definitions, config, true, true)
	check(first["pickup_id"] == "warehouse" and first["delivery_id"] == "house_01" and first["type"] == "standard", "The first delivery remains deterministic and beginner friendly")
	check(is_equal_approx(float(first["distance"]), 35.0), "The first order retains its original distance")
	check(first["pickup_district_id"] == "district_0" and first["district_route"] == "Район 0", "District names and IDs are part of the authoritative order")


func test_selection_and_timing() -> void:
	var outside: Dictionary = {"profile": {"level": 1, "owned_vehicles": []}, "position": Vector3(181, 0, -162)}
	var order: Dictionary = Rules.make_order(20, pickups, destinations, balance, [outside], definitions, config, false, true)
	check(order["pickup_id"] == "business_pickup", "A pedestrian exploring a new district gets work near their location")
	check(float(order["distance"]) <= 130.0 and order["type"] == "standard", "Reserved local orders remain accessible to a rookie")
	check(Rules.make_order(1, [pickups[0]], [pickups[0]], balance, [outside], definitions, config).is_empty(), "A pool containing only coincident or too-distant points does not invent a delivery")
	var regional_config: Dictionary = config.duplicate(true)
	regional_config["regional_chance"] = 1.0
	var courier: Dictionary = {"profile": {"level": 6, "owned_vehicles": ["car"]}, "position": Vector3(-23, 0, 4)}
	var regional_count: int = 0
	for sequence: int in range(24):
		order = Rules.make_order(100 + sequence, pickups, destinations, balance, [courier], definitions, regional_config)
		if order.get("route_band", "") == "regional":
			regional_count += 1
		var estimate: float = Rules.estimate_distance(courier["position"], order["pickup_position"]) + float(order["distance"])
		check(float(order["time_limit"]) >= estimate / float(config["express_reference_speed"]) * float(config["express_time_factor"]) + float(config["express_handling_seconds"]) - 0.001, "The express timer accounts for the trip to the pickup as well as delivery")
	check(regional_count > 0, "Owning a car creates real interdistrict opportunities")
	check(Rules.estimate_distance(Vector3.ZERO, Vector3(100, 0, 100)) == 200.0, "Street planning uses block distance instead of a diagonal chord")


func test_expanded_authority() -> void:
	var city: Node3D = WorldScript.new()
	root.add_child(city)
	var authority: Node = AuthorityScript.new()
	root.add_child(authority)
	await process_frame
	await physics_frame
	var roster: Array = [
		{"id": 1, "name": "Driver", "profile": {"xp": 6000, "owned_vehicles": ["car"], "selected_vehicle": ""}},
		{"id": 2, "name": "Rookie", "profile": {"xp": 0, "owned_vehicles": [], "selected_vehicle": ""}}
	]
	authority.start_session({"shift_seconds": -1, "shift_mode": "team"}, roster, city, balance, "city-order-test")
	check(authority.orders.size() == 6 and Rules.local_order_count(authority.orders, config) >= 2, "A mixed LAN lobby retains six shared orders and at least two short standard jobs")
	check(authority.orders[0]["pickup_id"] == "warehouse" and authority.orders[0]["delivery_id"] == "house_01", "The Host still publishes the deterministic first order")
	check(authority._inside_bounds(Vector3(200, 0.1, 0)) and not authority._inside_bounds(Vector3(260, 0.1, 0)), "Server bounds expand with the real city while rejecting the new exterior")
	check(not authority._inside_bounds(Vector3(200, 7, 0)) and not authority._inside_bounds(Vector3(NAN, 0.1, 0)), "Height and nonfinite pose rejection remain active")
	test_vehicle_boundary(authority)
	var origin: Vector3 = Vector3(-200, 0.1, 0)
	check(Placement.position_is_free(city, origin, PI, definitions["car"]), "Vehicles can occupy an actual new district road beyond the old border")
	authority.records[2]["position"] = origin
	authority.records[2]["move_credit"] = 2.0
	authority.records[2]["pose_tick_msec"] = Time.get_ticks_msec()
	var valid: Vector3 = origin + Vector3(1, 0, 0)
	authority._accept_pose(2, {"position": valid, "yaw": PI, "velocity": Vector3(1, 0, 0), "grounded": true, "carrying": false, "active_vehicle": "walking"})
	check(authority.records[2]["position"] == valid, "An ordinary client step in the expanded district is accepted")
	authority._accept_pose(2, {"position": valid + Vector3(40, 0, 0), "yaw": PI, "velocity": Vector3.ZERO, "grounded": true, "carrying": false, "active_vehicle": "walking"})
	check(authority.records[2]["position"] == valid, "Expanded bounds do not permit a speed-credit teleport")
	authority._accept_pose(2, {"position": Vector3(-260, 0.1, 0), "yaw": PI, "velocity": Vector3.ZERO, "grounded": true, "carrying": false, "active_vehicle": "walking"})
	check(authority.records[2]["position"] == valid, "Poses outside the new city are rejected")
	var accepted_id: int = int(authority.orders[0]["id"])
	var canonical_reward: int = int(authority.orders[0]["reward"])
	authority.handle_request(2, "accept", {"id": accepted_id, "reward": 999999999, "delivery_position": valid})
	check(int(authority.records[2]["active_order"]["reward"]) == canonical_reward, "Clients still cannot supply the reward or destination")
	check(authority.orders.size() == 6 and Rules.local_order_count(authority.orders, config) >= 2, "Accepting an order replenishes the Host pool with short opportunities")
	check(bool(authority.snapshot_for(2).get("team", {}).get("enabled", false)), "The expanded city retains team shifts")
	authority.queue_free()
	city.queue_free()
	await process_frame


func test_vehicle_boundary(authority: Node) -> void:
	# Seed a valid Host-owned spawn fixture next to the clamp; requests still traverse
	# the full generation, move-credit, line-of-sight and vehicle collision checks.
	var saved_record: Dictionary = authority.records[2].duplicate(true)
	var edge: float = VehicleScript.WORLD_BOUND
	for side: float in [-1.0, 1.0]:
		var record: Dictionary = authority.records[2]
		record["profile"]["owned_vehicles"] = ["bicycle"]
		record["profile"]["level"] = 2
		record["position"] = Vector3(side * (edge - 0.1), 0.1, 0)
		record["vehicle"] = authority._new_vehicle(2, "bicycle", record["position"], PI)
		record["vehicle"]["occupied"] = true
		record["move_credit"] = 2.0
		record["pose_tick_msec"] = Time.get_ticks_msec()
		var boundary: Vector3 = Vector3(side * edge, 0.1, 0)
		var payload: Dictionary = {
			"position": boundary, "yaw": PI, "velocity": Vector3.ZERO,
			"grounded": true, "carrying": false, "active_vehicle": "bicycle",
			"vehicle_generation": int(record["vehicle"]["generation"])
		}
		authority._accept_pose(2, payload)
		check(authority.records[2]["position"] == boundary, "A client bicycle pose at the exact %s controller clamp passes server validation" % ("negative" if side < 0.0 else "positive"))
		payload["position"] = Vector3(side * (edge + 0.01), 0.1, 0)
		authority._accept_pose(2, payload)
		check(authority.records[2]["position"] == boundary, "A bicycle pose 0.01 m outside the %s city bound is rejected" % ("negative" if side < 0.0 else "positive"))
	authority.records[2] = saved_record
