extends RefCounted
## Shared schedule and award policy. LAN calls come only from the Host.
const CityOrderRules = preload("res://scripts/city_order_rules.gd")
const CONFIG_PATH: String = "res://assets/district_events.json"
const EVENT_KEY: String = "lunch_rush"
const EVENT_NAME: String = "Обеденный час"
const DISTRICT_ID: String = "business"
const DISTRICT_NAME: String = "Деловой центр"
const DEFAULT_PICKUPS: Array[String] = ["pickup_espresso"]
const DEFAULT_DELIVERIES: Array[String] = ["delivery_northstar", "delivery_metro", "delivery_courier_hub", "delivery_riverbank", "delivery_summit", "delivery_insurance"]


static func load_config() -> Dictionary:
	var source: Dictionary = {}
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			source = parsed
	return config_from_data(source)


static func config_from_data(source: Dictionary) -> Dictionary:
	return {
		"first_start_seconds": clampf(_number(source.get("first_start_seconds", 45.0), 45.0), 5.0, 300.0),
		"duration_seconds": clampf(_number(source.get("duration_seconds", 180.0), 180.0), 30.0, 600.0),
		"cooldown_seconds": clampf(_number(source.get("cooldown_seconds", 300.0), 300.0), 30.0, 1800.0),
		"available_orders": int(clampf(_number(source.get("available_orders", 3), 3.0), 1.0, 3.0)),
		"bonus_multiplier": clampf(_number(source.get("bonus_multiplier", 1.5), 1.5), 1.0, 2.0),
		"maximum_route_meters": clampf(_number(source.get("maximum_route_meters", 130.0), 130.0), 40.0, 130.0),
		# Explicit addresses avoid generating office lunch orders to houses or warehouses.
		"pickup_ids": _address_ids(source.get("pickup_ids", DEFAULT_PICKUPS), DEFAULT_PICKUPS),
		"delivery_ids": _address_ids(source.get("delivery_ids", DEFAULT_DELIVERIES), DEFAULT_DELIVERIES)
	}


static func snapshot(elapsed_seconds: float, running: bool, config: Dictionary) -> Dictionary:
	var safe: Dictionary = config_from_data(config)
	var elapsed: float = clampf(elapsed_seconds, 0.0, 1000000000000.0) if is_finite(elapsed_seconds) else 0.0
	var first: float = float(safe["first_start_seconds"])
	var duration: float = float(safe["duration_seconds"])
	var cooldown: float = float(safe["cooldown_seconds"])
	var cycle_seconds: float = duration + cooldown
	var cycle: int = 0 if elapsed < first else floori((elapsed - first) / cycle_seconds)
	var starts_at: float = first + float(cycle) * cycle_seconds
	var ends_at: float = starts_at + duration
	var event_phase: String = "waiting"
	if not running:
		event_phase = "ended"
	elif elapsed >= first:
		event_phase = "active" if elapsed < ends_at else "cooldown"
	var next_start: float = starts_at if elapsed < first else (starts_at + cycle_seconds if event_phase == "cooldown" else starts_at)
	return {
		"id": "%s:%d" % [EVENT_KEY, cycle + 1], "phase": event_phase,
		"name": EVENT_NAME, "district_id": DISTRICT_ID, "district_name": DISTRICT_NAME,
		"starts_in": maxf(0.0, next_start - elapsed) if running else 0.0,
		"remaining": maxf(0.0, ends_at - elapsed) if event_phase == "active" else 0.0,
		"starts_at": starts_at, "ends_at": ends_at, "elapsed": elapsed,
		"bonus_multiplier": float(safe["bonus_multiplier"])
	}


static func is_event_order(order: Dictionary) -> bool:
	return not str(order.get("event_id", "")).is_empty()


static func normal_orders(orders: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in orders:
		if value is Dictionary and not is_event_order(value):
			result.append(value)
	return result


static func can_accept(order: Dictionary, event: Dictionary) -> bool:
	if not is_event_order(order):
		return true
	return event.get("phase", "") == "active" and str(order.get("event_id", "")) == str(event.get("id", "")) and float(event.get("elapsed", 0.0)) < float(order.get("event_ends_at", 0.0))


static func make_order(order_id: int, pickups: Array, destinations: Array, balance: Dictionary, event: Dictionary, config: Dictionary, existing_orders: Array = []) -> Dictionary:
	if event.get("phase", "") != "active" or order_id <= 0:
		return {}
	var used_pairs: Dictionary = {}
	for value: Variant in existing_orders:
		if value is Dictionary and str(value.get("event_id", "")) == str(event["id"]):
			used_pairs["%s|%s" % [str(value.get("pickup_id", "")), str(value.get("delivery_id", ""))]] = true
	var pairs: Array[Dictionary] = []
	for pickup_value: Variant in pickups:
		if not _point_allowed(pickup_value, config.get("pickup_ids", DEFAULT_PICKUPS)):
			continue
		var pickup: Dictionary = pickup_value
		for destination_value: Variant in destinations:
			if not _point_allowed(destination_value, config.get("delivery_ids", DEFAULT_DELIVERIES)):
				continue
			var destination: Dictionary = destination_value
			var key: String = "%s|%s" % [str(pickup["id"]), str(destination["id"])]
			var distance: float = CityOrderRules.estimate_distance(pickup["position"], destination["position"])
			if str(pickup["id"]) == str(destination["id"]) or used_pairs.has(key) or distance < 8.0 or distance > float(config.get("maximum_route_meters", 130.0)):
				continue
			pairs.append({"pickup": pickup, "destination": destination, "distance": distance})
	if pairs.is_empty():
		return {}
	var selected: Dictionary = pairs.pick_random()
	var pickup: Dictionary = selected["pickup"]
	var destination: Dictionary = selected["destination"]
	var distance: float = float(selected["distance"])
	var minimum: int = maxi(0, int(_number(balance.get("base_reward_min", 110), 110.0)))
	var maximum: int = maxi(minimum, int(_number(balance.get("base_reward_max", 160), 160.0)))
	var base_reward: int = randi_range(minimum, maximum) + int(round(distance * maxf(0.0, _number(balance.get("distance_reward", 3.5), 3.5))))
	var multiplier: float = float(event["bonus_multiplier"])
	var bonus: int = int(floor(float(base_reward) * (multiplier - 1.0)))
	return {
		"id": order_id, "title": "%s → %s" % [pickup["name"], destination["name"]],
		"type": "standard", "type_name": "Обеденный час", "state": "Available", "locked": false,
		"pickup_name": pickup["name"], "delivery_name": destination["name"],
		"pickup_position": pickup["position"], "delivery_position": destination["position"],
		"pickup_id": pickup["id"], "delivery_id": destination["id"],
		"pickup_district": DISTRICT_NAME, "delivery_district": DISTRICT_NAME,
		"pickup_district_id": DISTRICT_ID, "delivery_district_id": DISTRICT_ID,
		"district_route": DISTRICT_NAME, "route_band": "local", "suggested_vehicle": "walk",
		"distance": distance, "base_reward": base_reward, "reward": base_reward,
		"required_level": 1, "xp": maxi(0, int(_number(balance.get("standard_xp", 50), 50.0))),
		"time_limit": 0.0,
		"event_id": str(event["id"]), "event_name": EVENT_NAME,
		"event_starts_at": float(event["starts_at"]), "event_ends_at": float(event["ends_at"]),
		"event_bonus_multiplier": multiplier, "event_bonus": bonus,
		"event_remaining": float(event["remaining"]), "event_bonus_money": bonus, "event_bonus_available": true
	}


static func bonus_for_delivery(order: Dictionary, normal_money: int, elapsed_seconds: float, config: Dictionary) -> int:
	if not is_event_order(order) or normal_money <= 0 or not is_finite(elapsed_seconds):
		return 0
	var event: Dictionary = snapshot(elapsed_seconds, true, config)
	if not can_accept(order, event) or str(order.get("type", "")) != "standard":
		return 0
	# The schedule, rather than caller-provided metadata, sets the reward deadline.
	if not is_equal_approx(float(order.get("event_starts_at", -1.0)), float(event["starts_at"])) or not is_equal_approx(float(order.get("event_ends_at", -1.0)), float(event["ends_at"])):
		return 0
	return int(floor(float(normal_money) * (float(event["bonus_multiplier"]) - 1.0)))


static func order_view(order: Dictionary, elapsed_seconds: float, running: bool, config: Dictionary) -> Dictionary:
	if not is_event_order(order):
		return {}
	var remaining: float = maxf(0.0, float(order.get("event_ends_at", 0.0)) - elapsed_seconds)
	var bonus: int = bonus_for_delivery(order, int(order.get("reward", 0)), elapsed_seconds, config) if running else 0
	return {
		"id": str(order.get("event_id", "")), "name": str(order.get("event_name", EVENT_NAME)),
		"remaining": remaining if running else 0.0,
		"bonus_multiplier": float(order.get("event_bonus_multiplier", 1.5)),
		"bonus_money": bonus, "bonus_available": bonus > 0
	}


static func publish_order_fields(order: Dictionary, elapsed_seconds: float, running: bool, config: Dictionary) -> void:
	var view: Dictionary = order_view(order, elapsed_seconds, running, config)
	if view.is_empty():
		return
	order["event_remaining"] = view["remaining"]
	order["event_bonus_money"] = view["bonus_money"]
	order["event_bonus_available"] = view["bonus_available"]


static func _point_allowed(value: Variant, allowed_ids: Variant) -> bool:
	if not value is Dictionary or not allowed_ids is Array or not allowed_ids.has(str(value.get("id", ""))):
		return false
	var position: Variant = value.get("position", null)
	return position is Vector3 and position.is_finite() and str(value.get("district_id", "")) == DISTRICT_ID


static func _address_ids(value: Variant, fallback: Array[String]) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			if entry is String and fallback.has(entry) and not result.has(entry):
				result.append(entry)
	return fallback.duplicate() if result.is_empty() else result


static func _number(value: Variant, fallback: float) -> float:
	if not (value is int or value is float):
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback
