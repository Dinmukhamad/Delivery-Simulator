extends RefCounted
## Shared solo/LAN policy. Only the Host calls it for LAN; requests never supply rewards.
const FragileRules = preload("res://scripts/fragile_rules.gd")
const CONFIG_PATH: = "res://assets/city_orders.json"
const DEFAULT_CAPS: = {"walk": 130.0, "bicycle": 220.0, "scooter": 380.0, "car": 700.0}
const DEFAULT_ACCESS: = {"walk": 95.0, "bicycle": 180.0, "scooter": 300.0, "car": 520.0}


static func load_config() -> Dictionary:
	var source: Dictionary = {}
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			source = parsed
	var config: Dictionary = {
		"minimum_local_orders": clampi(int(_number(source.get("minimum_local_orders", 2), 2.0)), 2, 4),
		"regional_chance": clampf(_number(source.get("regional_chance", 0.65), 0.65), 0.0, 1.0),
		"minimum_delivery_distance": clampf(_number(source.get("minimum_delivery_distance", 8.0), 8.0), 2.0, 20.0),
		"express_reference_speed": clampf(_number(source.get("express_reference_speed", 4.5), 4.5), 2.0, 10.0),
		"express_time_factor": clampf(_number(source.get("express_time_factor", 1.7), 1.7), 1.0, 3.0),
		"express_handling_seconds": clampf(_number(source.get("express_handling_seconds", 18.0), 18.0), 10.0, 60.0),
		"express_minimum_seconds": clampf(_number(source.get("express_minimum_seconds", 45.0), 45.0), 30.0, 120.0),
		"route_cap_meters": {}, "pickup_access_meters": {}
	}
	for vehicle_id: String in DEFAULT_CAPS:
		var source_caps: Variant = source.get("route_cap_meters", {})
		var source_access: Variant = source.get("pickup_access_meters", {})
		var cap: Variant = source_caps.get(vehicle_id, DEFAULT_CAPS[vehicle_id]) if source_caps is Dictionary else DEFAULT_CAPS[vehicle_id]
		var access: Variant = source_access.get(vehicle_id, DEFAULT_ACCESS[vehicle_id]) if source_access is Dictionary else DEFAULT_ACCESS[vehicle_id]
		config["route_cap_meters"][vehicle_id] = clampf(_number(cap, float(DEFAULT_CAPS[vehicle_id])), 40.0, 800.0)
		config["pickup_access_meters"][vehicle_id] = clampf(_number(access, float(DEFAULT_ACCESS[vehicle_id])), 30.0, 600.0)
	# Walking remains local even if an accidental balance edit inflates transport distances.
	config["route_cap_meters"]["walk"] = minf(150.0, float(config["route_cap_meters"]["walk"]))
	config["pickup_access_meters"]["walk"] = minf(110.0, float(config["pickup_access_meters"]["walk"]))
	return config


static func local_order_count(orders: Array, config: Dictionary) -> int:
	var count: int = 0
	var limit: float = float(config.get("route_cap_meters", DEFAULT_CAPS).get("walk", 130.0))
	for value: Variant in orders:
		if value is Dictionary and value.get("type", "") == "standard" and float(value.get("distance", INF)) <= limit:
			count += 1
	return count


static func estimate_distance(from: Vector3, to: Vector3) -> float:
	# Blocks and orthogonal streets make straight-line estimates misleading.
	# This is a bounded planning estimate; the navigation service supplies the actual route.
	return absf(from.x - to.x) + absf(from.z - to.z)


static func mobility_for_profile(profile: Dictionary, definitions: Dictionary) -> String:
	var selected: String = "walk"
	var owned: Variant = profile.get("owned_vehicles", [])
	var level: int = int(profile.get("level", 1))
	if not owned is Array:
		return selected
	for vehicle_id: String in ["bicycle", "scooter", "car"]:
		var definition: Variant = definitions.get(vehicle_id, {})
		if definition is Dictionary and not definition.is_empty() and owned.has(vehicle_id) and level >= int(definition.get("required_level", 1)):
			selected = vehicle_id
	return selected


static func make_order(order_id: int, pickups: Array, destinations: Array, balance: Dictionary, couriers: Array, definitions: Dictionary, config: Dictionary, first: bool = false, local_only: bool = false) -> Dictionary:
	if pickups.is_empty() or destinations.is_empty():
		return {}
	var options: Array[Dictionary] = _courier_options(couriers, definitions, config)
	var chosen: Dictionary = _choose_courier(options, local_only)
	var local_cap: float = float(config["route_cap_meters"]["walk"])
	var cap: float = float(chosen["cap"])
	var regional: bool = not first and not local_only and cap > local_cap and randf() < float(config["regional_chance"])
	if not regional:
		cap = local_cap
	var pair: Dictionary = {}
	if first and _valid_pair(pickups[0], destinations[0], float(config["minimum_delivery_distance"]), local_cap):
		pair = {"pickup": pickups[0], "destination": destinations[0]}
	else:
		var access: float = float(config["pickup_access_meters"]["walk"]) if not regional else float(chosen["access"])
		pair = _choose_pair(pickups, destinations, chosen["position"], float(config["minimum_delivery_distance"]), cap, access, local_cap if regional else 0.0)
		if pair.is_empty() and regional:
			# A newly purchased bike still gets nearby work when no medium trip fits.
			regional = false
			pair = _choose_pair(pickups, destinations, chosen["position"], float(config["minimum_delivery_distance"]), local_cap, float(config["pickup_access_meters"]["walk"]), 0.0)
	if pair.is_empty():
		return {}
	var pickup: Dictionary = pair["pickup"]
	var destination: Dictionary = pair["destination"]
	var distance: float = estimate_distance(pickup["position"], destination["position"])
	var approach: float = estimate_distance(chosen["position"], pickup["position"])
	var highest_level: int = 1
	for courier: Dictionary in options:
		highest_level = maxi(highest_level, int(courier["level"]))
	var fragile: bool = not first and not local_only and highest_level >= FragileRules.required_level(balance) and randf() < clampf(_number(balance.get("fragile_chance", 0.25), 0.25), 0.0, 1.0)
	var express_level: int = maxi(1, int(_number(balance.get("express_required_level", 3), 3.0)))
	var express: bool = not first and not local_only and not fragile and highest_level >= express_level and randf() < 0.3
	var minimum: int = maxi(0, int(_number(balance.get("base_reward_min", 110), 110.0)))
	var maximum: int = maxi(minimum, int(_number(balance.get("base_reward_max", 160), 160.0)))
	var base: int = randi_range(minimum, maximum) + int(round(distance * maxf(0.0, _number(balance.get("distance_reward", 3.5), 3.5))))
	var multiplier: float = _number(balance.get("fragile_multiplier", 1.3), 1.3) if fragile else (_number(balance.get("express_multiplier", 1.5), 1.5) if express else 1.0)
	var pickup_district: String = str(pickup.get("district_name", ""))
	var delivery_district: String = str(destination.get("district_name", ""))
	var order: Dictionary = {
		"id": order_id, "title": "%s → %s" % [pickup["name"], destination["name"]],
		"type": "fragile" if fragile else ("express" if express else "standard"),
		"type_name": "Хрупкий груз" if fragile else ("Экспресс" if express else "Стандарт"),
		"pickup_name": pickup["name"], "delivery_name": destination["name"],
		"pickup_position": pickup["position"], "delivery_position": destination["position"],
		"pickup_id": pickup["id"], "delivery_id": destination["id"],
		"pickup_district": pickup_district, "delivery_district": delivery_district,
		"pickup_district_id": str(pickup.get("district_id", "")), "delivery_district_id": str(destination.get("district_id", "")),
		"district_route": pickup_district if pickup_district == delivery_district else "%s → %s" % [pickup_district, delivery_district],
		"route_band": "regional" if regional else "local",
		"suggested_vehicle": str(chosen["vehicle"]) if regional else "walk",
		"distance": distance, "base_reward": base, "reward": int(round(base * maxf(0.0, multiplier))),
		"required_level": FragileRules.required_level(balance) if fragile else (express_level if express else 1),
		"xp": int(_number(balance.get("fragile_xp", 75), 75.0)) if fragile else (int(_number(balance.get("express_xp", 75), 75.0)) if express else int(_number(balance.get("standard_xp", 50), 50.0))),
		"time_limit": maxf(float(config["express_minimum_seconds"]), (approach + distance) / float(config["express_reference_speed"]) * float(config["express_time_factor"]) + float(config["express_handling_seconds"])),
		"state": "Available", "locked": false
	}
	if fragile:
		order.merge(FragileRules.initial_fields(balance), true)
	return order


static func _courier_options(couriers: Array, definitions: Dictionary, config: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for value: Variant in couriers:
		if not value is Dictionary:
			continue
		var profile: Variant = value.get("profile", {})
		var position: Variant = value.get("position", null)
		if not profile is Dictionary or not position is Vector3 or not _finite(position):
			continue
		var vehicle: String = mobility_for_profile(profile, definitions)
		options.append({
			"vehicle": vehicle, "level": int(profile.get("level", 1)), "position": position,
			"cap": float(config["route_cap_meters"][vehicle]), "access": float(config["pickup_access_meters"][vehicle])
		})
	if options.is_empty():
		options.append({"vehicle": "walk", "level": 1, "position": Vector3(-23, 0, 4), "cap": float(config["route_cap_meters"]["walk"]), "access": float(config["pickup_access_meters"]["walk"])})
	return options


static func _choose_courier(options: Array[Dictionary], local_only: bool) -> Dictionary:
	var preferred: Array[Dictionary] = []
	var best_cap: float = INF if local_only else -INF
	for candidate: Dictionary in options:
		var cap: float = float(candidate["cap"])
		if (local_only and cap < best_cap) or (not local_only and cap > best_cap):
			preferred.clear()
			best_cap = cap
		if is_equal_approx(cap, best_cap):
			preferred.append(candidate)
	return preferred.pick_random()


static func _choose_pair(pickups: Array, destinations: Array, origin: Vector3, minimum: float, cap: float, access: float, minimum_trip: float) -> Dictionary:
	var nearby: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	var nearest: float = INF
	for pickup_value: Variant in pickups:
		if not pickup_value is Dictionary:
			continue
		var pickup: Dictionary = pickup_value
		var choices: Array[Dictionary] = []
		for destination: Variant in destinations:
			if _valid_pair(pickup, destination, maxf(minimum, minimum_trip + 0.01), cap):
				choices.append(destination)
		if choices.is_empty():
			continue
		var approach: float = estimate_distance(origin, pickup["position"])
		var entry: Dictionary = {"pickup": pickup, "destinations": choices}
		if approach <= access:
			nearby.append(entry)
		if approach < nearest - 0.01:
			nearest = approach
			fallback.clear()
		if absf(approach - nearest) <= 0.01:
			fallback.append(entry)
	var pool: Array[Dictionary] = nearby if not nearby.is_empty() else fallback
	if pool.is_empty():
		return {}
	var selected: Dictionary = pool.pick_random()
	return {"pickup": selected["pickup"], "destination": selected["destinations"].pick_random()}


static func _valid_pair(pickup: Variant, destination: Variant, minimum: float, cap: float) -> bool:
	if not pickup is Dictionary or not destination is Dictionary:
		return false
	if str(pickup.get("id", "")) == str(destination.get("id", "")):
		return false
	var from: Variant = pickup.get("position", null)
	var to: Variant = destination.get("position", null)
	if not from is Vector3 or not to is Vector3 or not _finite(from) or not _finite(to):
		return false
	var distance: float = estimate_distance(from, to)
	return distance >= minimum and distance <= cap


static func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _number(value: Variant, fallback: float) -> float:
	if not (value is int or value is float):
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback
