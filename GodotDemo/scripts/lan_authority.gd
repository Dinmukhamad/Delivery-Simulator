extends Node


signal changed()
signal event_ready(peer_id: int, event: Dictionary)
signal pose_ready(peer_id: int, pose: Dictionary)

const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
const CosmeticCatalog = preload("res://scripts/cosmetic_catalog.gd")
const CheatCodeRules = preload("res://scripts/cheat_code_rules.gd")
const VehiclePlacement = preload("res://scripts/vehicle_placement.gd")
const FragileRules = preload("res://scripts/fragile_rules.gd")
const TeamShiftRules = preload("res://scripts/team_shift_rules.gd")
const CityLayout = preload("res://scripts/city_layout.gd")
const CityOrderRules = preload("res://scripts/city_order_rules.gd")
const DistrictEventRules = preload("res://scripts/district_event_rules.gd")
const AVAILABLE_ORDER_COUNT: = 6
const EXPRESS_REQUIRED_LEVEL: = 3
const MAX_PROFILE_VALUE: = 1000000000
const MAX_PEER_ID: = 2147483647
const INTERACTION_DISTANCE: = 3.2
const MAX_MOVE_SPEED: = 10.5
const INITIAL_MOVE_CREDIT: = 2.0
const MAX_MOVE_CREDIT: = 2.5
const CLOCK_BROADCAST_MSEC: = 500
const POSE_BROADCAST_MSEC: = 50
const GARAGE_POSITION: = Vector3(-66.0, 0.0, 10.0)
const GARAGE_DISTANCE: = 5.0
const VEHICLE_ENTER_DISTANCE: = 2.8
const VEHICLE_EXIT_SPEED: = 1.5
const MAX_FLIGHT_ALTITUDE: = 60.0
const FLIGHT_VERTICAL_EXIT_SPEED: = 0.75
const FLIGHT_INITIAL_VERTICAL_CREDIT: = 0.65
const FLIGHT_INITIAL_TURN_CREDIT: = 0.25
const IMPACT_HISTORY_MSEC: = 250
const CHEAT_REQUEST_BURST: float = 6.0
const CHEAT_REQUESTS_PER_SECOND: float = 3.0

var records: Dictionary = {}
var phase: String = "offline"
var session_id: String = ""
var revision: int = 0
var orders: Array[Dictionary] = []
var next_order_id: int = 1

var _world: Node3D
var _balance: Dictionary = {}
var _city_order_config: Dictionary = {}
var _district_event_config: Dictionary = {}
var _district_event_phase: String = "ended"
var _district_event_id: String = ""
var _event_delivered: int = 0
var _event_bonus_money: int = 0
var _started_at_msec: int = 0
var _deadline_msec: int = -1
var _shift_seconds: float = -1.0
var _last_broadcast_msec: int = 0
var _vehicle_definitions: Dictionary = {}
var _team_config: Dictionary = {}
var _team_enabled: bool = false
var _team_target: int = 0
var _team_delivered: int = 0
var _team_completed: bool = false
var _team_awarded: Dictionary = {}
var _handoff_offers: Dictionary = {}
var _next_offer_id: int = 1
var _cheat_budgets: Dictionary = {}


func _ready() -> void :

	process_mode = Node.PROCESS_MODE_ALWAYS


func start_session(config: Dictionary, roster: Array, world: Node3D, balance: Dictionary, new_session_id: String) -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = world
	_balance = balance.duplicate(true)
	_city_order_config = CityOrderRules.load_config()
	_district_event_config = DistrictEventRules.load_config()
	_district_event_phase = "waiting"
	_district_event_id = "lunch_rush:1"
	_event_delivered = 0
	_event_bonus_money = 0
	_vehicle_definitions = VehicleCatalog.load_definitions()
	_team_config = TeamShiftRules.load_config()
	_team_enabled = TeamShiftRules.normalize_mode(config.get("shift_mode", "competitive")) == "team"
	_team_target = 0
	_team_delivered = 0
	_team_completed = false
	_team_awarded.clear()
	_handoff_offers.clear()
	_next_offer_id = 1
	_cheat_budgets.clear()
	session_id = new_session_id
	phase = "playing"
	records.clear()
	orders.clear()
	next_order_id = 1
	_started_at_msec = Time.get_ticks_msec()
	_last_broadcast_msec = _started_at_msec
	_shift_seconds = minf(86400.0, _number(config.get("shift_seconds", 600), 600.0))
	_deadline_msec = _started_at_msec + int(_shift_seconds * 1000.0) if _shift_seconds > 0.0 else -1
	var spawn: = Vector3(-23.0, 0.15, 4.0)
	if is_instance_valid(_world):
		var world_spawn: Variant = _world.get("spawn_position")
		if world_spawn is Vector3 and _finite_vector(world_spawn):
			spawn = world_spawn
	var spawn_index: int = 0
	for member_value: Variant in roster:
		if not member_value is Dictionary:
			continue
		var member: Dictionary = member_value
		var peer_value: Variant = member.get("id", 0)
		if not peer_value is int or peer_value <= 0 or peer_value > MAX_PEER_ID or records.has(peer_value):
			continue
		var peer_id: int = peer_value
		var name_value: Variant = member.get("name", "Courier")
		var display_name: String = name_value if name_value is String else "Courier"
		display_name = display_name.strip_edges().left(32)
		if display_name.is_empty():
			display_name = "Courier"
		var profile_value: Variant = member.get("profile", {})
		var profile: Dictionary = _sanitize_profile(profile_value if profile_value is Dictionary else {})
		profile["player_name"] = display_name
		var spawn_row: int = floori(float(spawn_index) / 2.0)
		var position: Vector3 = spawn + Vector3(float(spawn_index % 2) * 2.0, 0.0, float(spawn_row) * 2.0)
		records[peer_id] = {
			"id": peer_id, "name": display_name, "profile": profile,
			"active_order": {}, "shift_stats": _empty_shift_stats(), "connected": true,
			"position": position, "yaw": PI, "velocity": Vector3.ZERO,
			"grounded": true, "carrying": false,
			"vehicle": {}, "vehicle_speed": 0.0, "vehicle_generation": 0,
			"move_credit": INITIAL_MOVE_CREDIT, "pose_tick_msec": _started_at_msec,
			"flight_ascent_credit": FLIGHT_INITIAL_VERTICAL_CREDIT, "flight_descent_credit": FLIGHT_INITIAL_VERTICAL_CREDIT,
			"flight_turn_credit": FLIGHT_INITIAL_TURN_CREDIT,
			"pose_emit_msec": _started_at_msec - POSE_BROADCAST_MSEC,
			"displacement_velocity": Vector3.ZERO, "impact_pose_msec": _started_at_msec
		}
		spawn_index += 1
	_team_target = records.size() * int(_team_config["deliveries_per_player"]) if _team_enabled else 0
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		var selected: String = str(record["profile"].get("selected_vehicle", ""))
		if _owns_vehicle(record, selected) and int(record["profile"]["level"]) >= int(_vehicle_definition(selected).get("required_level", 1)):
			_spawn_record_vehicle(int(peer_id), selected, false)
	_fill_orders(true)
	_mark_changed()


func handle_request(peer_id: int, action: String, payload: Dictionary) -> void :
	if phase != "playing" or not records.has(peer_id):
		return
	var record: Dictionary = records[peer_id]
	if not bool(record.get("connected", false)):
		return
	_advance_clock(Time.get_ticks_msec())
	if phase != "playing":
		return
	match action:
		"accept":
			_accept_order(peer_id, payload)
		"interact":
			_interact(peer_id)
		"abandon":
			_abandon_order(peer_id)
		"pose":
			_accept_pose(peer_id, payload)
		"cheat_code":
			_cheat_request(peer_id, payload)
		"cosmetic_buy":
			_cosmetic_request(peer_id, payload, true)
		"cosmetic_select":
			_cosmetic_request(peer_id, payload, false)
		"vehicle_buy":
			_buy_vehicle(peer_id, payload)
		"vehicle_spawn":
			_spawn_vehicle(peer_id, payload)
		"vehicle_toggle":
			_toggle_vehicle(peer_id, payload)
		"offer_handoff":
			_offer_handoff(peer_id, payload)
		"accept_handoff":
			_accept_handoff(peer_id, payload)
		"decline_handoff":
			_decline_handoff(peer_id, payload)
		"cancel_handoff":
			_cancel_handoff(peer_id)


func remove_player(peer_id: int) -> void :
	if not records.has(peer_id):
		return
	var record: Dictionary = records[peer_id]
	if not bool(record.get("connected", false)):
		return
	_clear_handoffs_for(peer_id)
	_cheat_budgets.erase(peer_id)
	record["connected"] = false
	record["active_order"] = {}
	record["carrying"] = false
	record["velocity"] = Vector3.ZERO
	record["vehicle"] = {}
	_reset_impact_history(record)

	record["shift_stats"]["time_used"] = _elapsed_seconds(Time.get_ticks_msec())
	if phase == "playing":

		for index: int in range(orders.size() - 1, -1, -1):
			if (orders[index]["type"] == "express" and not _express_unlocked()) or (orders[index]["type"] == "fragile" and not _fragile_unlocked()):
				orders.remove_at(index)
		_fill_orders()
	_mark_changed()


func stop_session() -> void :
	if phase == "offline":
		return
	phase = "offline"
	_district_event_phase = "ended"
	_handoff_offers.clear()
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		record["active_order"] = {}
		record["carrying"] = false
		record["velocity"] = Vector3.ZERO
		_park_vehicle(record)
		_record_best_shift(record)
	orders.clear()
	_mark_changed()


func snapshot_for(peer_id: int) -> Dictionary:
	var now: int = Time.get_ticks_msec()
	var record: Dictionary = records.get(peer_id, {})
	var profile: Dictionary = record.get("profile", {}).duplicate(true)
	var active_order: Dictionary = record.get("active_order", {}).duplicate(true)
	if not active_order.is_empty():
		active_order["remaining"] = _order_remaining(active_order, now)
		active_order.erase("deadline_msec")
		active_order.erase("last_impact_msec")
		DistrictEventRules.publish_order_fields(active_order, _elapsed_seconds(now), phase == "playing", _district_event_config)
	var shift_stats: Dictionary = record.get("shift_stats", _empty_shift_stats()).duplicate(true)
	if phase == "playing" and bool(record.get("connected", false)):
		shift_stats["time_used"] = _elapsed_seconds(now)
	var visible_orders: Array[Dictionary] = []
	var level: int = int(profile.get("level", 1))
	for order: Dictionary in orders:
		var visible: Dictionary = order.duplicate(true)
		visible.erase("last_impact_msec")
		visible["locked"] = level < _order_required_level(order)
		DistrictEventRules.publish_order_fields(visible, _elapsed_seconds(now), phase == "playing", _district_event_config)
		visible_orders.append(visible)
	return {
		"session_id": session_id, "revision": revision, "phase": phase,
		"remaining": _remaining_seconds(now), "orders": visible_orders,
		"active_order": active_order, "profile": profile, "shift_stats": shift_stats,
		"players": _public_players(), "vehicles": _public_vehicles(), "leaderboard": _leaderboard(),
		"team": _team_snapshot(peer_id), "handoffs": _handoff_snapshot(peer_id, now),
		"district_event": _district_event_snapshot(now),
		"order_event": DistrictEventRules.order_view(active_order, _elapsed_seconds(now), phase == "playing", _district_event_config)
	}


func get_profile(peer_id: int) -> Dictionary:
	if not records.has(peer_id):
		return {}
	return records[peer_id]["profile"].duplicate(true)


func _process(_delta: float) -> void :
	if phase != "playing":
		return
	var now: int = Time.get_ticks_msec()
	var clock_changed: bool = _advance_clock(now)
	if phase == "playing" and not clock_changed and now - _last_broadcast_msec >= CLOCK_BROADCAST_MSEC:
		_mark_changed()


func _advance_clock(now: int) -> bool:
	if phase != "playing":
		return false
	if _deadline_msec >= 0 and now >= _deadline_msec:
		_finish_shift(now)
		return true
	var expired: bool = _advance_district_event(now)
	expired = _cleanup_handoffs(now) or expired
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		var active: Dictionary = record["active_order"]
		if active.is_empty() or active.get("type", "standard") != "express":
			continue
		if _order_remaining(active, now) <= 0.0:
			_clear_handoffs_for(int(peer_id))
			record["active_order"] = {}
			record["carrying"] = false
			if not record["vehicle"].is_empty():
				record["vehicle"]["carrying"] = false
			_notice(int(peer_id), "Время экспресс-заказа вышло. Возьмите новый заказ.")
			expired = true
	if expired:
		_mark_changed()
	return expired


func _finish_shift(now: int = -1) -> void :
	if phase != "playing":
		return
	if now < 0:
		now = Time.get_ticks_msec()
	phase = "results"
	_district_event_phase = "ended"
	_remove_stale_event_orders(_district_event_snapshot(now))
	_handoff_offers.clear()
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		record["active_order"] = {}
		record["carrying"] = false
		record["velocity"] = Vector3.ZERO
		_park_vehicle(record)
		if bool(record.get("connected", false)):
			record["shift_stats"]["time_used"] = _elapsed_seconds(now)
		_record_best_shift(record)
	_mark_changed()


func _accept_order(peer_id: int, payload: Dictionary) -> void :
	var record: Dictionary = records[peer_id]
	if not record["active_order"].is_empty():
		_notice(peer_id, "Сначала завершите текущий заказ или отмените его.")
		return
	var requested_id: Variant = payload.get("id", null)
	if not requested_id is int or requested_id <= 0 or requested_id > MAX_PEER_ID:
		_notice(peer_id, "Неверный номер заказа.")
		return
	for index: int in range(orders.size()):
		var order: Dictionary = orders[index]
		if int(order["id"]) != requested_id:
			continue
		if not DistrictEventRules.can_accept(order, _district_event_snapshot(Time.get_ticks_msec())):
			orders.remove_at(index)
			_notice(peer_id, "Обеденный час завершен. Выберите другой заказ.")
			_mark_changed()
			return
		var required_level: int = _order_required_level(order)
		if int(record["profile"]["level"]) < required_level:
			_notice(peer_id, "%s: требуется уровень %d." % [str(order.get("type_name", "Этот заказ")), required_level])
			return

		orders.remove_at(index)
		var accepted: Dictionary = order.duplicate(true)
		accepted["state"] = "Accepted"
		accepted["owner_id"] = peer_id
		accepted["accepted_msec"] = Time.get_ticks_msec()
		accepted["handoff_history"] = []
		if accepted["type"] == "fragile":
			accepted.merge(FragileRules.initial_fields(_balance), true)
		accepted["remaining"] = float(accepted["time_limit"])
		if accepted["type"] == "express":
			accepted["deadline_msec"] = Time.get_ticks_msec() + int(float(accepted["time_limit"]) * 1000.0)
		_clear_handoffs_for(peer_id)
		record["active_order"] = accepted
		_fill_orders()
		_notice(peer_id, "Заказ принят. Идите к золотому маркеру и нажмите E.")
		_mark_changed()
		return
	_notice(peer_id, "Этот заказ уже принят другим курьером. Выберите другой.")


func _interact(peer_id: int) -> void :
	var record: Dictionary = records[peer_id]
	if _is_riding(record):
		_notice(peer_id, "Сначала остановитесь и выйдите из транспорта клавишей F.")
		return
	if not VehiclePlacement.is_near_floor(_world, record["position"]):
		return
	var active: Dictionary = record["active_order"]
	if active.is_empty() or int(active.get("owner_id", 0)) != peer_id:
		return
	var order_state: String = str(active.get("state", ""))
	if order_state not in ["Accepted", "PickedUp"]:
		return
	var target: Vector3 = active["delivery_position"] if order_state == "PickedUp" else active["pickup_position"]
	var position: Vector3 = record["position"]

	if position.distance_to(target) > INTERACTION_DISTANCE or not _has_line_of_sight(position, target):
		_notice(peer_id, "Подойдите к маркеру, чтобы передать коробку.")
		return
	if order_state == "Accepted":
		active["state"] = "PickedUp"
		active["pickup_msec"] = Time.get_ticks_msec()
		_reset_impact_history(record)
		record["carrying"] = true
		_notice(peer_id, "Коробка у вас. Доставьте ее к бирюзовому маркеру.")
	else:
		_complete_delivery(peer_id, Time.get_ticks_msec())
	_mark_changed()


func _complete_delivery(peer_id: int, now: int) -> void :
	var record: Dictionary = records[peer_id]
	var active: Dictionary = record["active_order"]
	if active.is_empty() or active.get("state", "") != "PickedUp" or int(active.get("owner_id", 0)) != peer_id:
		return
	var remaining: float = _order_remaining(active, now)
	if active["type"] == "express" and remaining <= 0.0:
		_clear_handoffs_for(peer_id)
		record["active_order"] = {}
		record["carrying"] = false
		_notice(peer_id, "Время экспресс-заказа вышло. Возьмите новый заказ.")
		return

	_clear_handoffs_for(peer_id)
	var completed: Dictionary = active.duplicate(true)
	completed["state"] = "Delivered"
	record["active_order"] = {}
	record["carrying"] = false
	var money: int = int(completed["reward"])
	var xp: int = int(completed["xp"])
	var profile: Dictionary = record["profile"]
	var stats: Dictionary = record["shift_stats"]
	var previous_level: int = int(profile["level"])
	if completed["type"] == "express":
		money += int(round(remaining / float(completed["time_limit"]) * 80.0))
		profile["express_deliveries"] = int(profile["express_deliveries"]) + 1
	elif completed["type"] == "fragile":
		money += FragileRules.quality_bonus(completed)
	var event_bonus: int = DistrictEventRules.bonus_for_delivery(completed, money, _elapsed_seconds(now), _district_event_config)
	money += event_bonus
	if DistrictEventRules.is_event_order(completed):
		_event_delivered += 1
		_event_bonus_money += event_bonus
		stats["event_deliveries"] = int(stats.get("event_deliveries", 0)) + 1
		stats["event_bonus_money"] = int(stats.get("event_bonus_money", 0)) + event_bonus
	profile["money"] = mini(MAX_PROFILE_VALUE, int(profile["money"]) + money)
	profile["xp"] = mini(MAX_PROFILE_VALUE, int(profile["xp"]) + xp)
	profile["total_deliveries"] = int(profile["total_deliveries"]) + 1
	profile["total_money_earned"] = int(profile["total_money_earned"]) + money
	profile["level"] = _level_for_xp(int(profile["xp"]))
	profile["rank"] = _rank_for_level(int(profile["level"]))
	stats["deliveries"] = int(stats["deliveries"]) + 1
	stats["money"] = int(stats["money"]) + money
	stats["xp"] = int(stats["xp"]) + xp
	stats["best_delivery"] = maxi(int(stats["best_delivery"]), money)
	_record_best_shift(record)
	if _team_enabled:
		_team_delivered += 1
		if _team_target > 0 and _team_delivered >= _team_target:
			_team_completed = true
		_award_team_bonuses()
	var level_notice: String = " · Новый уровень %d!" % int(profile["level"]) if int(profile["level"]) > previous_level else ""
	var event_notice: String = " · Бонус обеденного часа +%d ₸" % event_bonus if event_bonus > 0 else (" · Заказ события: обычная награда" if DistrictEventRules.is_event_order(completed) else "")
	_notice(peer_id, "Доставка завершена! +%d ₸ · +%d XP%s%s" % [money, xp, event_notice, level_notice])


func _abandon_order(peer_id: int) -> void :
	var record: Dictionary = records[peer_id]
	if record["active_order"].is_empty():
		return
	_clear_handoffs_for(peer_id)
	record["active_order"] = {}
	record["carrying"] = false
	if not record["vehicle"].is_empty():
		record["vehicle"]["carrying"] = false
	_notice(peer_id, "Заказ отменен. За завершенные доставки прогресс сохранен.")
	_mark_changed()



# A sender has at most one outstanding offer. Each receiver has at most one
# incoming offer, so a confirmation can never choose a different parcel.
func _offer_handoff(peer_id: int, payload: Dictionary) -> void:
	var target_id: int = _request_peer_id(payload.get("target_id"))
	var now: int = Time.get_ticks_msec()
	if not _handoff_pair_valid(peer_id, target_id, now):
		_notice(peer_id, "Передать посылку можно свободному курьеру рядом: оба должны быть пешком.")
		return
	if _handoff_offers.has(peer_id) or _has_incoming_handoff(target_id):
		_notice(peer_id, "У вас или у получателя уже есть предложение передачи.")
		return
	if _next_offer_id > MAX_PEER_ID:
		return
	var order: Dictionary = records[peer_id]["active_order"]
	_handoff_offers[peer_id] = {
		"offer_id": _next_offer_id, "sender_id": peer_id, "target_id": target_id,
		"order_id": int(order["id"]),
		"deadline_msec": now + int(float(_team_config["offer_seconds"]) * 1000.0)
	}
	_next_offer_id += 1
	_notice(peer_id, "Предложение отправлено. Получатель должен подтвердить передачу.")
	_notice(target_id, "%s предлагает передать вам посылку." % str(records[peer_id]["name"]))
	_mark_changed()


func _accept_handoff(peer_id: int, payload: Dictionary) -> void:
	var sender_id: int = _request_peer_id(payload.get("sender_id"))
	var offer_id: int = _request_peer_id(payload.get("offer_id"))
	if not _matching_handoff(peer_id, sender_id, offer_id):
		_notice(peer_id, "Предложение передачи уже недоступно.")
		return
	var now: int = Time.get_ticks_msec()
	var offer: Dictionary = _handoff_offers[sender_id]
	var valid: bool = now < int(offer["deadline_msec"]) and _handoff_pair_valid(sender_id, peer_id, now)
	if valid:
		valid = int(records[sender_id]["active_order"].get("id", -1)) == int(offer["order_id"])
	if not valid:
		_handoff_offers.erase(sender_id)
		_notice(peer_id, "Передача отменена. Подойдите к курьеру пешком и попробуйте снова.")
		_mark_changed()
		return
	# Consume the exact offer before updating either record. Requests are processed
	# on the Host thread; a replay cannot reward or transfer this parcel again.
	_clear_handoffs_for(sender_id)
	_clear_handoffs_for(peer_id)
	var sender: Dictionary = records[sender_id]
	var recipient: Dictionary = records[peer_id]
	var active: Dictionary = sender["active_order"]
	var history: Array = active.get("handoff_history", [])
	history.append({"from_id": sender_id, "to_id": peer_id, "at_msec": now})
	active["handoff_history"] = history
	active["owner_id"] = peer_id
	# Keep ID, type, deadline, accepted/pickup time, quality and impact cooldown.
	sender["active_order"] = {}
	sender["carrying"] = false
	recipient["active_order"] = active
	recipient["carrying"] = true
	if not sender["vehicle"].is_empty():
		sender["vehicle"]["carrying"] = false
	if not recipient["vehicle"].is_empty():
		recipient["vehicle"]["carrying"] = true
	_reset_impact_history(sender)
	_reset_impact_history(recipient)
	_notice(sender_id, "Посылка передана курьеру %s." % str(recipient["name"]))
	_notice(peer_id, "Посылка получена от %s. Доставьте её к бирюзовому маркеру." % str(sender["name"]))
	_mark_changed()


func _decline_handoff(peer_id: int, payload: Dictionary) -> void:
	var sender_id: int = _request_peer_id(payload.get("sender_id"))
	var offer_id: int = _request_peer_id(payload.get("offer_id"))
	if not _matching_handoff(peer_id, sender_id, offer_id):
		return
	_handoff_offers.erase(sender_id)
	_notice(sender_id, "Получатель отказался от передачи посылки.")
	_mark_changed()


func _cancel_handoff(peer_id: int) -> void:
	if not _handoff_offers.has(peer_id):
		return
	_handoff_offers.erase(peer_id)
	_notice(peer_id, "Предложение передачи отменено.")
	_mark_changed()


func _request_peer_id(value: Variant) -> int:
	return int(value) if value is int and value > 0 and value <= MAX_PEER_ID else 0


func _matching_handoff(receiver_id: int, sender_id: int, offer_id: int) -> bool:
	if not _team_enabled or phase != "playing" or receiver_id == sender_id or offer_id <= 0:
		return false
	var offer: Dictionary = _handoff_offers.get(sender_id, {})
	return not offer.is_empty() and int(offer.get("target_id", 0)) == receiver_id and int(offer.get("offer_id", 0)) == offer_id


func _handoff_pair_valid(sender_id: int, receiver_id: int, now: int) -> bool:
	if not _team_enabled or phase != "playing" or sender_id == receiver_id or sender_id <= 0 or receiver_id <= 0:
		return false
	if not records.has(sender_id) or not records.has(receiver_id):
		return false
	var sender: Dictionary = records[sender_id]
	var receiver: Dictionary = records[receiver_id]
	if not bool(sender.get("connected", false)) or not bool(receiver.get("connected", false)):
		return false
	if _is_riding(sender) or _is_riding(receiver) or not receiver["active_order"].is_empty():
		return false
	var active: Dictionary = sender["active_order"]
	if active.get("state", "") != "PickedUp" or int(active.get("owner_id", 0)) != sender_id:
		return false
	if active.get("type", "") == "express" and _order_remaining(active, now) <= 0.0:
		return false
	var from: Vector3 = sender["position"]
	var to: Vector3 = receiver["position"]
	return _finite_vector(from) and _finite_vector(to) and from.distance_to(to) <= float(_team_config.get("handoff_distance", 3.2)) and _has_line_of_sight(from, to)


func _has_incoming_handoff(peer_id: int) -> bool:
	for offer_value: Variant in _handoff_offers.values():
		var offer: Dictionary = offer_value
		if int(offer.get("target_id", 0)) == peer_id:
			return true
	return false


func _clear_handoffs_for(peer_id: int) -> void:
	for sender_id: Variant in _handoff_offers.keys():
		var offer: Dictionary = _handoff_offers[sender_id]
		if int(sender_id) == peer_id or int(offer.get("target_id", 0)) == peer_id:
			_handoff_offers.erase(sender_id)


func _cleanup_handoffs(now: int) -> bool:
	var removed: bool = false
	for sender_value: Variant in _handoff_offers.keys():
		var sender_id: int = int(sender_value)
		var offer: Dictionary = _handoff_offers[sender_value]
		var receiver_id: int = int(offer.get("target_id", 0))
		var valid: bool = now < int(offer.get("deadline_msec", 0)) and _handoff_pair_valid(sender_id, receiver_id, now)
		if valid:
			valid = int(records[sender_id]["active_order"].get("id", -1)) == int(offer.get("order_id", -2))
		if not valid:
			_handoff_offers.erase(sender_value)
			removed = true
	return removed


func _handoff_snapshot(peer_id: int, now: int) -> Dictionary:
	var incoming: Array[Dictionary] = []
	var outgoing: Dictionary = {}
	for sender_value: Variant in _handoff_offers:
		var sender_id: int = int(sender_value)
		var offer: Dictionary = _handoff_offers[sender_value]
		var remaining: float = maxf(0.0, float(int(offer["deadline_msec"]) - now) / 1000.0)
		if remaining <= 0.0:
			continue
		var target_id: int = int(offer["target_id"])
		var order: Dictionary = records[sender_id]["active_order"]
		var visible: Dictionary = {
			"offer_id": int(offer["offer_id"]), "sender_id": sender_id,
			"target_id": target_id, "order_id": int(offer["order_id"]),
			"title": str(order.get("title", "Посылка")), "remaining": remaining
		}
		if target_id == peer_id:
			visible["name"] = str(records[sender_id]["name"])
			incoming.append(visible)
		if sender_id == peer_id:
			visible["name"] = str(records[target_id]["name"])
			outgoing = visible
	return {"incoming": incoming, "outgoing": outgoing}


func _team_snapshot(peer_id: int) -> Dictionary:
	var record: Dictionary = records.get(peer_id, {})
	var contributions: int = int(record.get("shift_stats", {}).get("deliveries", 0))
	return {
		"enabled": _team_enabled, "target": _team_target, "delivered": _team_delivered,
		"completed": _team_completed, "bonus_money": int(_team_config.get("bonus_money", 500)),
		"bonus_xp": int(_team_config.get("bonus_xp", 100)),
		"eligible": _team_enabled and bool(record.get("connected", false)) and contributions > 0,
		"bonus_awarded": _team_awarded.has(peer_id), "contributions": contributions
	}


func _award_team_bonuses() -> void:
	if not _team_enabled or not _team_completed:
		return
	for peer_value: Variant in records:
		var peer_id: int = int(peer_value)
		var record: Dictionary = records[peer_value]
		var stats: Dictionary = record["shift_stats"]
		if not bool(record.get("connected", false)) or int(stats["deliveries"]) <= 0 or _team_awarded.has(peer_id):
			continue
		_team_awarded[peer_id] = true
		var money: int = int(_team_config["bonus_money"])
		var xp: int = int(_team_config["bonus_xp"])
		var profile: Dictionary = record["profile"]
		profile["money"] = mini(MAX_PROFILE_VALUE, int(profile["money"]) + money)
		profile["total_money_earned"] = int(profile["total_money_earned"]) + money
		profile["xp"] = mini(MAX_PROFILE_VALUE, int(profile["xp"]) + xp)
		profile["level"] = _level_for_xp(int(profile["xp"]))
		profile["rank"] = _rank_for_level(int(profile["level"]))
		stats["money"] = int(stats["money"]) + money
		stats["xp"] = int(stats["xp"]) + xp
		stats["team_bonus_money"] = money
		stats["team_bonus_xp"] = xp
		_record_best_shift(record)
		_notice(peer_id, "Командный план выполнен! Ваш бонус: +%d ₸ · +%d XP." % [money, xp])


func _cheat_request(peer_id: int, payload: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if not _allow_cheat_request(peer_id, now):
		return
	var result: Dictionary
	if payload.size() != 1 or not payload.has("code") or not payload["code"] is String:
		result = {"ok": false, "changed": false, "message": "Запрос должен содержать только строку чит-кода.", "code": ""}
	else:
		var record: Dictionary = records[peer_id]
		var step: int = maxi(1, int(_number(_balance.get("level_xp_step", 150), 150.0)))
		result = CheatCodeRules.apply(record["profile"], payload["code"], step)
		if bool(result.get("changed", false)):
			# The requester is the sole target. Grants never count as deliveries,
			# shift earnings, team progress or district-event rewards.
			_mark_changed()
	_send_cheat_result(peer_id, result)


func _allow_cheat_request(peer_id: int, now: int) -> bool:
	var budget: Dictionary = _cheat_budgets.get(peer_id, {"tokens": CHEAT_REQUEST_BURST, "updated_msec": now, "denied_msec": -1000})
	var elapsed: float = maxf(0.0, float(now - int(budget["updated_msec"])) / 1000.0)
	budget["tokens"] = minf(CHEAT_REQUEST_BURST, float(budget["tokens"]) + elapsed * CHEAT_REQUESTS_PER_SECOND)
	budget["updated_msec"] = now
	_cheat_budgets[peer_id] = budget
	if float(budget["tokens"]) < 1.0:
		# Bound denial replies as well as grants to avoid echoing a request flood.
		if now - int(budget["denied_msec"]) >= 1000:
			budget["denied_msec"] = now
			_send_cheat_result(peer_id, {"ok": false, "changed": false, "message": "Слишком много чит-кодов. Подождите секунду и повторите.", "code": ""})
		return false
	budget["tokens"] = float(budget["tokens"]) - 1.0
	return true


func _send_cheat_result(peer_id: int, result: Dictionary) -> void:
	event_ready.emit(peer_id, {"type": "cheat_result", "session_id": session_id,
		"ok": bool(result.get("ok", false)), "changed": bool(result.get("changed", false)),
		"message": str(result.get("message", "")), "code": str(result.get("code", ""))})


func _cosmetic_request(peer_id: int, payload: Dictionary, purchasing: bool) -> void:
	var record: Dictionary = records[peer_id]
	var result: Dictionary
	if _is_riding(record) or not VehiclePlacement.can_use_garage(record["position"], _world):
		result = {"ok": false, "changed": false, "message": "Для смены стиля подойдите к гаражу пешком."}
	else:
		var category: Variant = payload.get("category")
		var item_id: Variant = payload.get("id")
		result = CosmeticCatalog.buy(record["profile"], category, item_id) if purchasing else CosmeticCatalog.select(record["profile"], category, item_id)
	if bool(result.get("changed", false)):
		var vehicle: Dictionary = record.get("vehicle", {})
		if not vehicle.is_empty():
			vehicle["appearance"] = CosmeticCatalog.sanitize_profile(record["profile"])["appearance"]
		_mark_changed()
	event_ready.emit(peer_id, {"type": "cosmetic_result", "session_id": session_id,
		"ok": bool(result.get("ok", false)), "changed": bool(result.get("changed", false)),
		"message": str(result.get("message", ""))})


func _buy_vehicle(peer_id: int, payload: Dictionary) -> void :
	var record: Dictionary = records[peer_id]
	var vehicle_id: String = _requested_vehicle_id(peer_id, payload)
	if vehicle_id.is_empty() or not _at_garage(record):
		return
	var definition: Dictionary = _vehicle_definition(vehicle_id)
	var vehicle_name: String = str(definition.get("name", vehicle_id))
	if _owns_vehicle(record, vehicle_id):
		_notice(peer_id, "%s уже куплен. Выберите его подачу в гараже." % vehicle_name)
		return
	var profile: Dictionary = record["profile"]
	var required_level: int = maxi(1, int(definition.get("required_level", 1)))
	var price: int = maxi(0, int(definition.get("price", 0)))
	if int(profile["level"]) < required_level:
		_notice(peer_id, "%s доступен с уровня %d." % [vehicle_name, required_level])
		return
	if int(profile["money"]) < price:
		_notice(peer_id, "Недостаточно денег. %s стоит %d ₸." % [vehicle_name, price])
		return
	var placement: Dictionary = _find_vehicle_placement(peer_id, vehicle_id)
	if placement.is_empty():
		_notice(peer_id, "Нет свободного места для транспорта. Отойдите от стены и попробуйте снова.")
		return

	var owned: Array = profile.get("owned_vehicles", []).duplicate()
	owned.append(vehicle_id)
	profile["owned_vehicles"] = owned
	profile["selected_vehicle"] = vehicle_id
	profile["money"] = int(profile["money"]) - price
	record["vehicle"] = _new_vehicle(peer_id, vehicle_id, placement["position"], float(record["yaw"]))
	_emit_vehicle_state(peer_id)
	_notice(peer_id, "%s куплен! Подойдите к нему и нажмите F." % vehicle_name)
	_mark_changed()


func _spawn_vehicle(peer_id: int, payload: Dictionary) -> void :
	var record: Dictionary = records[peer_id]
	var vehicle_id: String = _requested_vehicle_id(peer_id, payload)
	if vehicle_id.is_empty() or not _at_garage(record):
		return
	var definition: Dictionary = _vehicle_definition(vehicle_id)
	if not _owns_vehicle(record, vehicle_id):
		_notice(peer_id, "Сначала купите этот транспорт в гараже.")
		return
	if int(record["profile"]["level"]) < int(definition.get("required_level", 1)):
		_notice(peer_id, "Ваш уровень пока не позволяет использовать этот транспорт.")
		return
	if _spawn_record_vehicle(peer_id, vehicle_id):
		record["profile"]["selected_vehicle"] = vehicle_id
		_emit_vehicle_state(peer_id)
		_notice(peer_id, "%s подан. Подойдите к нему и нажмите F." % str(definition.get("name", vehicle_id)))
		_mark_changed()


func _requested_vehicle_id(peer_id: int, payload: Dictionary) -> String:

	var supplied: Variant = payload.get("type", "bicycle")
	if not supplied is String or not _vehicle_definitions.has(supplied):
		_notice(peer_id, "Этот транспорт пока недоступен.")
		return ""
	return supplied


func _at_garage(record: Dictionary) -> bool:
	if _is_riding(record):
		_notice(int(record["id"]), "Сначала остановитесь и выйдите из транспорта клавишей F.")
		return false
	var position: Vector3 = record["position"]
	if not VehiclePlacement.can_use_garage(position, _world):
		_notice(int(record["id"]), "Подойдите к гаражу, чтобы купить или подать транспорт.")
		return false
	return true


func _toggle_vehicle(peer_id: int, payload: Dictionary) -> void :
	var record: Dictionary = records[peer_id]
	var requested_owner: Variant = payload.get("owner_id", peer_id)
	if not requested_owner is int or requested_owner != peer_id:
		_notice(peer_id, "Можно использовать только свой транспорт.")
		return
	var vehicle: Dictionary = record["vehicle"]
	var vehicle_id: String = str(vehicle.get("type", ""))
	if vehicle.is_empty() or not _owns_vehicle(record, vehicle_id):
		_notice(peer_id, "У вас пока нет транспорта. Купите его в гараже.")
		return
	var definition: Dictionary = _vehicle_definition(vehicle_id)
	if int(record["profile"]["level"]) < int(definition.get("required_level", 1)):
		_notice(peer_id, "Ваш уровень пока не позволяет использовать этот транспорт.")
		return
	if _is_riding(record):
		var current_velocity: Vector3 = record["velocity"]
		if not _vehicle_at_floor(vehicle, current_velocity):
			_notice(peer_id, "Для выхода сначала приземлитесь на свободную площадку и остановитесь.")
			return
		if maxf(Vector2(current_velocity.x, current_velocity.z).length(), float(record.get("vehicle_speed", 0.0))) > VEHICLE_EXIT_SPEED:
			_notice(peer_id, "Остановитесь перед выходом из транспорта.")
			return
		var exit_placement: Dictionary = _find_exit_placement(peer_id)
		if exit_placement.is_empty():
			_notice(peer_id, "Недостаточно места для выхода. Отъедьте от стены.")
			return
		vehicle["occupied"] = false
		record["position"] = exit_placement["position"]
	else:
		var position: Vector3 = record["position"]
		var parked_position: Vector3 = vehicle["position"]
		if not _vehicle_at_floor(vehicle, vehicle.get("velocity", Vector3.ZERO)):
			_notice(peer_id, "Сесть в транспорт можно после его приземления.")
			return
		if position.distance_to(parked_position) > VEHICLE_ENTER_DISTANCE or not _has_line_of_sight(position, parked_position):
			_notice(peer_id, "Подойдите ближе к своему транспорту.")
			return
		if not _position_is_free(parked_position, float(vehicle["yaw"]), definition):
			_notice(peer_id, "Транспорт заблокирован. Подайте его снова в гараже.")
			return
		vehicle["occupied"] = true
		record["position"] = parked_position
		record["yaw"] = vehicle["yaw"]


	_clear_handoffs_for(peer_id)
	_advance_vehicle_generation(record)
	record["velocity"] = Vector3.ZERO
	record["vehicle_speed"] = 0.0
	record["grounded"] = true
	vehicle["velocity"] = Vector3.ZERO
	vehicle["grounded"] = true
	vehicle["carrying"] = bool(record["carrying"]) if _is_riding(record) else false
	record["move_credit"] = INITIAL_MOVE_CREDIT
	_reset_flight_credit(record)
	record["pose_tick_msec"] = Time.get_ticks_msec()
	_reset_impact_history(record)
	_emit_vehicle_state(peer_id)
	_mark_changed()


func _vehicle_at_floor(vehicle: Dictionary, velocity: Vector3) -> bool:
	if not VehiclePlacement.is_near_floor(_world, vehicle.get("position", Vector3.INF)):
		return false
	return str(vehicle.get("type", "")) != "airplane" or (bool(vehicle.get("grounded", false)) and absf(velocity.y) <= FLIGHT_VERTICAL_EXIT_SPEED)


func _reset_flight_credit(record: Dictionary) -> void:
	record["flight_ascent_credit"] = FLIGHT_INITIAL_VERTICAL_CREDIT
	record["flight_descent_credit"] = FLIGHT_INITIAL_VERTICAL_CREDIT
	record["flight_turn_credit"] = FLIGHT_INITIAL_TURN_CREDIT


func _owns_vehicle(record: Dictionary, vehicle_id: String) -> bool:
	var owned: Variant = record.get("profile", {}).get("owned_vehicles", [])
	return _vehicle_definitions.has(vehicle_id) and owned is Array and owned.has(vehicle_id)


func _is_riding(record: Dictionary) -> bool:
	var vehicle: Dictionary = record.get("vehicle", {})
	return not vehicle.is_empty() and bool(vehicle.get("occupied", false))


func _active_vehicle_type(record: Dictionary) -> String:
	return str(record["vehicle"].get("type", "walking")) if _is_riding(record) else "walking"


func _vehicle_definition(vehicle_id: String) -> Dictionary:
	return _vehicle_definitions.get(vehicle_id, {})


func _new_vehicle(peer_id: int, vehicle_id: String, position: Vector3, yaw: float) -> Dictionary:
	var generation: int = int(records[peer_id].get("vehicle_generation", 0)) + 1
	records[peer_id]["vehicle_generation"] = generation
	_reset_impact_history(records[peer_id])
	return {
		"owner_id": peer_id, "type": vehicle_id, "generation": generation, "position": position, "yaw": yaw, "occupied": false,
		"velocity": Vector3.ZERO, "grounded": true, "carrying": false,
		"appearance": CosmeticCatalog.sanitize_profile(records[peer_id]["profile"])["appearance"]
	}


func _spawn_record_vehicle(peer_id: int, vehicle_id: String, notify_failure: bool = true) -> bool:
	var placement: Dictionary = _find_vehicle_placement(peer_id, vehicle_id)
	if placement.is_empty():
		if notify_failure:
			_notice(peer_id, "Нет свободного места для транспорта. Отойдите от стены и попробуйте снова.")
		return false
	var record: Dictionary = records[peer_id]
	record["vehicle"] = _new_vehicle(peer_id, vehicle_id, placement["position"], float(record["yaw"]))
	record["vehicle_speed"] = 0.0
	_reset_impact_history(record)
	return true


func _find_vehicle_placement(peer_id: int, vehicle_id: String = "bicycle") -> Dictionary:
	var record: Dictionary = records[peer_id]
	var definition: Dictionary = _vehicle_definition(vehicle_id)
	if definition.is_empty():
		return {}
	var position: Variant = VehiclePlacement.find_spawn(_world, record["position"], float(record["yaw"]), _blocked_positions(peer_id), definition)
	return {"position": position} if position is Vector3 else {}


func _find_exit_placement(peer_id: int) -> Dictionary:
	var vehicle: Dictionary = records[peer_id]["vehicle"]
	var definition: Dictionary = _vehicle_definition(str(vehicle.get("type", "")))
	var position: Variant = VehiclePlacement.find_exit(_world, vehicle["position"], float(vehicle["yaw"]), _blocked_positions(peer_id), definition)
	return {"position": position} if position is Vector3 else {}


func _position_is_free(position: Vector3, yaw: float, vehicle: Variant) -> bool:
	return VehiclePlacement.position_is_free(_world, position, yaw, vehicle)


func _blocked_positions(peer_id: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for other_id: Variant in records:
		if int(other_id) == peer_id:
			continue
		var other: Dictionary = records[other_id]
		if not bool(other.get("connected", false)):
			continue
		positions.append(other["position"])
		var vehicle: Dictionary = other.get("vehicle", {})
		if vehicle.is_empty():
			continue


		var definition: Dictionary = _vehicle_definition(str(vehicle.get("type", "")))
		var width: float = float(definition.get("collision_width", 0.8))
		var length: float = float(definition.get("collision_length", 2.2))
		var basis: = Basis(Vector3.UP, float(vehicle.get("yaw", PI)))
		var center: Vector3 = vehicle["position"]
		var columns: int = maxi(1, ceili(width / 0.6))
		var rows: int = maxi(1, ceili(length / 0.6))
		for column: int in range(columns + 1):
			for row: int in range(rows + 1):
				positions.append(center + basis * Vector3(lerpf( - width * 0.5, width * 0.5, float(column) / columns), 0.0, lerpf( - length * 0.5, length * 0.5, float(row) / rows)))
	return positions


func _park_vehicle(record: Dictionary) -> void :
	var vehicle: Dictionary = record.get("vehicle", {})
	if not vehicle.is_empty():
		if bool(vehicle.get("occupied", false)):
			_advance_vehicle_generation(record)
		vehicle["occupied"] = false
		vehicle["velocity"] = Vector3.ZERO
		vehicle["grounded"] = bool(record.get("grounded", true))
		vehicle["carrying"] = false
	record["vehicle_speed"] = 0.0
	_reset_impact_history(record)


func _advance_vehicle_generation(record: Dictionary) -> void :
	var vehicle: Dictionary = record.get("vehicle", {})
	if vehicle.is_empty():
		return
	var generation: int = maxi(int(record.get("vehicle_generation", 0)), int(vehicle.get("generation", 0))) + 1
	record["vehicle_generation"] = generation
	vehicle["generation"] = generation


func _emit_vehicle_state(peer_id: int) -> void :
	var record: Dictionary = records[peer_id]
	event_ready.emit(peer_id, {
		"type": "vehicle_state", "vehicle": record["vehicle"].duplicate(true),
		"position": record["position"], "active_vehicle": _active_vehicle_type(record)
	})


func _accept_pose(peer_id: int, payload: Dictionary) -> void :
	var record: Dictionary = records[peer_id]
	var expected_vehicle: String = _active_vehicle_type(record)
	var airplane: bool = expected_vehicle == "airplane"
	var definition: Dictionary = _vehicle_definition(expected_vehicle)


	if (airplane and not payload.has("active_vehicle")) or (payload.has("active_vehicle") and payload["active_vehicle"] != expected_vehicle):
		_correct_position(peer_id)
		return
	if airplane and not payload.has("vehicle_generation"):
		_correct_position(peer_id)
		return
	if _is_riding(record) and payload.has("vehicle_generation"):
		var supplied_generation: Variant = payload["vehicle_generation"]
		if not supplied_generation is int or supplied_generation != int(record["vehicle"].get("generation", 0)):
			_correct_position(peer_id)
			return
	var position_value: Variant = payload.get("position", null)
	var velocity_value: Variant = payload.get("velocity", null)
	var yaw_value: Variant = payload.get("yaw", null)
	if not position_value is Vector3 or not velocity_value is Vector3 or not (yaw_value is int or yaw_value is float):
		_correct_position(peer_id)
		return
	if not payload.get("grounded", null) is bool or not payload.get("carrying", null) is bool:
		_correct_position(peer_id)
		return
	var position: Vector3 = position_value
	var velocity: Vector3 = velocity_value
	var yaw: float = float(yaw_value)
	if not _finite_vector(position) or not _finite_vector(velocity) or not is_finite(yaw) or not _inside_bounds(position, minf(MAX_FLIGHT_ALTITUDE, float(definition.get("max_altitude", MAX_FLIGHT_ALTITUDE))) if airplane else 6.0):
		_correct_position(peer_id)
		return
	var now: int = Time.get_ticks_msec()
	var previous_position: Vector3 = record["position"]
	var elapsed: float = maxf(0.0, float(now - int(record["pose_tick_msec"])) / 1000.0)
	var riding: bool = _is_riding(record)
	var allowed_speed: float = maxf(1.0, float(definition.get("max_speed", 13.0))) + 2.0 if riding else MAX_MOVE_SPEED
	if airplane:
		allowed_speed = minf(30.0, float(definition.get("max_speed", 30.0))) + 0.5
	var maximum_credit: float = 3.5 if riding else MAX_MOVE_CREDIT
	var credit: float = minf(maximum_credit, float(record["move_credit"]) + elapsed * allowed_speed)
	record["pose_tick_msec"] = now
	record["move_credit"] = credit
	var travelled: float = previous_position.distance_to(position)
	var horizontal_distance: float = Vector2(position.x - previous_position.x, position.z - previous_position.z).length()


	if airplane:
		if not _validate_flight_motion(record, position, velocity, yaw, elapsed, credit, definition):
			_correct_position(peer_id)
			return
	elif peer_id != 1 and travelled > credit:
		_correct_position(peer_id)
		return
	if not airplane and travelled > 0.001 and not _has_line_of_sight(previous_position, position):
		_correct_position(peer_id)
		return
	if riding and not airplane and (position.y > 0.8 or not _position_is_free(position, yaw, definition)):
		_correct_position(peer_id)
		return


	var impact_changed: bool = _apply_validated_impact(record, position, yaw, now, allowed_speed) if riding else false
	if peer_id != 1 or airplane:
		record["move_credit"] = maxf(0.0, credit - (horizontal_distance if airplane else travelled))
	record["position"] = position
	record["yaw"] = wrapf(yaw, - PI, PI)
	record["velocity"] = velocity if airplane else velocity.limit_length(allowed_speed + 1.0 if riding else 16.0)
	record["grounded"] = _flight_grounded(position, velocity) if airplane else bool(payload["grounded"])
	if riding:
		var vehicle: Dictionary = record["vehicle"]
		vehicle["position"] = position
		vehicle["yaw"] = record["yaw"]
		record["vehicle_speed"] = horizontal_distance / maxf(elapsed, 0.001) if peer_id != 1 else Vector2(velocity.x, velocity.z).length()
	else:
		record["vehicle_speed"] = 0.0
	var carrying: bool = not record["active_order"].is_empty() and record["active_order"].get("state", "") == "PickedUp"
	record["carrying"] = carrying
	if riding:
		var vehicle: Dictionary = record["vehicle"]
		vehicle["velocity"] = record["velocity"]
		vehicle["grounded"] = record["grounded"]
		vehicle["carrying"] = carrying
	if _cleanup_handoffs(now):
		_mark_changed()
	if impact_changed:
		_notice(peer_id, "Хрупкая посылка повреждена: качество %d%% · бонус %d ₸." % [int(record["active_order"].get("quality", 100)), FragileRules.quality_bonus(record["active_order"])])
		_mark_changed()
	if now - int(record["pose_emit_msec"]) < POSE_BROADCAST_MSEC:
		return
	record["pose_emit_msec"] = now
	pose_ready.emit(peer_id, {
		"position": position, "yaw": record["yaw"], "velocity": record["velocity"],
		"grounded": record["grounded"], "carrying": carrying,
		"active_vehicle": _active_vehicle_type(record), "vehicle": record["vehicle"].duplicate(true)
	})


func _validate_flight_motion(record: Dictionary, position: Vector3, velocity: Vector3, yaw: float, elapsed: float, horizontal_credit: float, definition: Dictionary) -> bool:
	var ascend_rate: float = minf(8.0, float(definition.get("ascend_rate", 8.0)))
	var descend_rate: float = minf(6.0, float(definition.get("descend_rate", 6.0)))
	var turn_rate: float = float(definition.get("steer_rate", 1.2))
	var ascent_credit: float = minf(ascend_rate * 0.2 + 0.1, float(record.get("flight_ascent_credit", FLIGHT_INITIAL_VERTICAL_CREDIT)) + elapsed * ascend_rate)
	var descent_credit: float = minf(descend_rate * 0.2 + 0.1, float(record.get("flight_descent_credit", FLIGHT_INITIAL_VERTICAL_CREDIT)) + elapsed * descend_rate)
	var turn_credit: float = minf(0.45, float(record.get("flight_turn_credit", FLIGHT_INITIAL_TURN_CREDIT)) + elapsed * turn_rate)
	# Store earned credit even after rejection. No tolerance is added per pose:
	# sending more packets cannot manufacture climb or turn capacity.
	record["flight_ascent_credit"] = ascent_credit
	record["flight_descent_credit"] = descent_credit
	record["flight_turn_credit"] = turn_credit
	var displacement: Vector3 = position - Vector3(record["position"])
	var turn: float = absf(angle_difference(float(record["yaw"]), yaw))
	if position.y < -0.001 or Vector2(velocity.x, velocity.z).length() > minf(30.0, float(definition.get("max_speed", 30.0))) + 0.5 or velocity.y > ascend_rate + 0.1 or velocity.y < -descend_rate - 0.1:
		return false
	if Vector2(displacement.x, displacement.z).length() > horizontal_credit or displacement.y > ascent_credit or -displacement.y > descent_credit or turn > turn_credit:
		return false
	if not VehiclePlacement.flight_path_is_free(_world, record["position"], float(record["yaw"]), position, yaw, definition):
		return false
	record["flight_ascent_credit"] = maxf(0.0, ascent_credit - maxf(0.0, displacement.y))
	record["flight_descent_credit"] = maxf(0.0, descent_credit - maxf(0.0, -displacement.y))
	record["flight_turn_credit"] = maxf(0.0, turn_credit - turn)
	return true


func _flight_grounded(position: Vector3, velocity: Vector3) -> bool:
	if absf(velocity.y) > FLIGHT_VERTICAL_EXIT_SPEED or not VehiclePlacement.is_near_floor(_world, position):
		return false
	var ground: Variant = VehiclePlacement.grounded_position(_world, position)
	return ground is Vector3 and absf(position.y - (Vector3(ground).y - 0.1)) <= 0.15


func _reset_impact_history(record: Dictionary) -> void :
	record["displacement_velocity"] = Vector3.ZERO
	record["impact_pose_msec"] = Time.get_ticks_msec()


func _apply_validated_impact(record: Dictionary, position: Vector3, yaw: float, now: int, allowed_speed: float) -> bool:
	var gap_msec: int = now - int(record.get("impact_pose_msec", now))
	var previous_velocity: Vector3 = record.get("displacement_velocity", Vector3.ZERO)
	var displacement: Vector3 = position - Vector3(record["position"])
	var airplane: bool = _active_vehicle_type(record) == "airplane"
	if not airplane:
		displacement.y = 0.0
	var velocity: Vector3 = Vector3.ZERO
	if gap_msec > 0 and gap_msec <= IMPACT_HISTORY_MSEC:
		velocity = (displacement / maxf(0.025, float(gap_msec) / 1000.0)).limit_length(sqrt(allowed_speed * allowed_speed + 64.0) if airplane else allowed_speed)
	else:
		previous_velocity = Vector3.ZERO
	record["displacement_velocity"] = velocity
	record["impact_pose_msec"] = now
	var active: Dictionary = record.get("active_order", {})
	if active.get("type", "") != "fragile" or active.get("state", "") != "PickedUp":
		return false
	var definition: Dictionary = _vehicle_definition(_active_vehicle_type(record))
	var normal: Vector3 = FragileRules.wall_normal(_world, definition, position, yaw)
	var normal_speed: float = maxf(0.0, maxf( - velocity.dot(normal), - previous_velocity.dot(normal)))
	if airplane:
		var vertical_normal: Vector3 = _flight_vertical_contact_normal(definition, position, yaw)
		normal_speed = maxf(normal_speed, maxf(-velocity.dot(vertical_normal), -previous_velocity.dot(vertical_normal)))
	return FragileRules.apply_impact(active, normal_speed, now, _balance)


func _flight_vertical_contact_normal(definition: Dictionary, position: Vector3, yaw: float) -> Vector3:
	if not is_instance_valid(_world) or not _world.is_inside_tree():
		return Vector3.ZERO
	var height: float = float(definition.get("collision_height", 2.45))
	var shape: = BoxShape3D.new()
	shape.size = Vector3(float(definition.get("collision_width", 6.0)), height + 0.12, float(definition.get("collision_length", 5.3)))
	var query: = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), position + Vector3.UP * height * 0.5)
	query.collision_mask = 1
	query.margin = 0.0
	var contact: Dictionary = _world.get_world_3d().direct_space_state.get_rest_info(query)
	if contact.is_empty():
		return Vector3.ZERO
	var normal: Vector3 = contact.get("normal", Vector3.ZERO)
	return normal.normalized() if _finite_vector(normal) and absf(normal.y) >= 0.6 else Vector3.ZERO


func _correct_position(peer_id: int) -> void :
	var record: Dictionary = records[peer_id]
	event_ready.emit(peer_id, {
		"type": "correction", "position": record["position"],
		"active_vehicle": _active_vehicle_type(record), "vehicle": record["vehicle"].duplicate(true)
	})


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return VehiclePlacement.has_line_of_sight(_world, from, to)


func _inside_bounds(position: Vector3, maximum_height: float = 6.0) -> bool:
	return CityLayout.contains_position(position) and position.y >= -1.0 and position.y <= maximum_height


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _district_event_snapshot(now: int = -1) -> Dictionary:
	if now < 0:
		now = Time.get_ticks_msec()
	var event: Dictionary = DistrictEventRules.snapshot(_elapsed_seconds(now), phase == "playing", _district_event_config)
	event["delivered"] = _event_delivered
	event["bonus_money"] = _event_bonus_money
	return event


func _remove_stale_event_orders(event: Dictionary) -> bool:
	var removed: bool = false
	for index: int in range(orders.size() - 1, -1, -1):
		if DistrictEventRules.is_event_order(orders[index]) and not DistrictEventRules.can_accept(orders[index], event):
			orders.remove_at(index)
			removed = true
	return removed


func _advance_district_event(now: int) -> bool:
	var event: Dictionary = _district_event_snapshot(now)
	var transition: bool = str(event["phase"]) != _district_event_phase or str(event["id"]) != _district_event_id
	_district_event_phase = str(event["phase"])
	_district_event_id = str(event["id"])
	var changed_event: bool = _remove_stale_event_orders(event)
	if transition:
		_fill_orders(false, now)
		if event["phase"] == "active":
			for peer_id: Variant in records:
				if bool(records[peer_id].get("connected", false)):
					_notice(int(peer_id), "Обеденный час! Кофейня → офисы делового центра: +%d%% к деньгам за доставку в следующие %d с." % [int(round((float(event["bonus_multiplier"]) - 1.0) * 100.0)), int(ceil(float(event["remaining"])))])
	return transition or changed_event


func _fill_orders(first: bool = false, now: int = -1) -> void:
	if not is_instance_valid(_world):
		return
	var pickup_value: Variant = _world.get("pickup_points")
	var delivery_value: Variant = _world.get("delivery_points")
	if not pickup_value is Array or not delivery_value is Array or pickup_value.is_empty() or delivery_value.is_empty():
		return
	if now < 0:
		now = Time.get_ticks_msec()
	var event: Dictionary = _district_event_snapshot(now)
	_remove_stale_event_orders(event)
	var normal: Array[Dictionary] = DistrictEventRules.normal_orders(orders)
	while normal.size() < AVAILABLE_ORDER_COUNT:
		var local_only: bool = CityOrderRules.local_order_count(normal, _city_order_config) < int(_city_order_config["minimum_local_orders"])
		var order: Dictionary = _make_order(first and normal.is_empty(), local_only)
		if order.is_empty():
			break
		orders.append(order)
		normal.append(order)
	if event["phase"] == "active":
		var event_count: int = orders.size() - normal.size()
		while event_count < int(_district_event_config["available_orders"]):
			var order: Dictionary = DistrictEventRules.make_order(next_order_id, pickup_value, delivery_value, _balance, event, _district_event_config, orders)
			if order.is_empty():
				break
			next_order_id += 1
			orders.append(order)
			event_count += 1


func _make_order(first: bool = false, local_only: bool = false) -> Dictionary:
	var couriers: Array = []
	for value: Variant in records.values():
		var record: Dictionary = value
		if bool(record.get("connected", false)):
			couriers.append({"profile": record["profile"], "position": record["position"]})
	var order: Dictionary = CityOrderRules.make_order(next_order_id, _world.get("pickup_points"), _world.get("delivery_points"), _balance, couriers, _vehicle_definitions, _city_order_config, first, local_only)
	if not order.is_empty():
		next_order_id += 1
	return order


func _express_unlocked() -> bool:
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		if bool(record["connected"]) and int(record["profile"]["level"]) >= maxi(1, int(_number(_balance.get("express_required_level", EXPRESS_REQUIRED_LEVEL), float(EXPRESS_REQUIRED_LEVEL)))):
			return true
	return false


func _fragile_unlocked() -> bool:
	for record_value: Variant in records.values():
		var record: Dictionary = record_value
		if bool(record.get("connected", false)) and int(record["profile"]["level"]) >= FragileRules.required_level(_balance):
			return true
	return false


func _order_required_level(order: Dictionary) -> int:
	match str(order.get("type", "standard")):
		"express":
			return maxi(1, int(_number(_balance.get("express_required_level", EXPRESS_REQUIRED_LEVEL), float(EXPRESS_REQUIRED_LEVEL))))
		"fragile":
			return FragileRules.required_level(_balance)
	return 1


func _public_players() -> Array[Dictionary]:
	var players: Array[Dictionary] = []
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		var profile: Dictionary = record["profile"]
		players.append({
			"id": int(peer_id), "name": record["name"], "level": int(profile["level"]), "rank": str(profile["rank"]),
			"position": record["position"], "yaw": float(record["yaw"]), "carrying": bool(record["carrying"]), "connected": bool(record["connected"]),
			"active_vehicle": _active_vehicle_type(record),
			"appearance": CosmeticCatalog.sanitize_profile(profile)["appearance"],
			"has_order": not record["active_order"].is_empty(),
			"order_state": str(record["active_order"].get("state", ""))
		})
	return players


func _public_vehicles() -> Array[Dictionary]:
	var vehicles: Array[Dictionary] = []
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		var vehicle: Dictionary = record.get("vehicle", {})
		if bool(record.get("connected", false)) and not vehicle.is_empty():
			var public_vehicle: Dictionary = vehicle.duplicate(true)
			public_vehicle["appearance"] = CosmeticCatalog.sanitize_profile(record["profile"])["appearance"]
			vehicles.append(public_vehicle)
	return vehicles


func _leaderboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for peer_id: Variant in records:
		var record: Dictionary = records[peer_id]
		var stats: Dictionary = record["shift_stats"]
		rows.append({
			"id": int(peer_id), "name": record["name"], "money": int(stats["money"]), "xp": int(stats["xp"]),
			"deliveries": int(stats["deliveries"]), "best_delivery": int(stats["best_delivery"]), "connected": bool(record["connected"]),
			"team_bonus_money": int(stats.get("team_bonus_money", 0)), "team_bonus_xp": int(stats.get("team_bonus_xp", 0)),
			"event_deliveries": int(stats.get("event_deliveries", 0)), "event_bonus_money": int(stats.get("event_bonus_money", 0))
		})
	rows.sort_custom( func(a: Dictionary, b: Dictionary) -> bool:
		if a["money"] != b["money"]:
			return int(a["money"]) > int(b["money"])
		if a["deliveries"] != b["deliveries"]:
			return int(a["deliveries"]) > int(b["deliveries"])
		return int(a["id"]) < int(b["id"])
	)
	return rows


func _remaining_seconds(now: int) -> float:
	if _deadline_msec < 0:
		return -1.0
	if phase == "results":
		return 0.0
	return maxf(0.0, float(_deadline_msec - now) / 1000.0)


func _elapsed_seconds(now: int) -> float:
	var elapsed: float = maxf(0.0, float(now - _started_at_msec) / 1000.0)
	return minf(elapsed, _shift_seconds) if _shift_seconds > 0.0 else elapsed


func _order_remaining(order: Dictionary, now: int) -> float:
	if order.get("type", "standard") != "express":
		return float(order.get("time_limit", 0.0))
	return maxf(0.0, float(int(order.get("deadline_msec", now)) - now) / 1000.0)


func _empty_shift_stats() -> Dictionary:
	return {"deliveries": 0, "money": 0, "xp": 0, "best_delivery": 0, "time_used": 0.0, "team_bonus_money": 0, "team_bonus_xp": 0, "event_deliveries": 0, "event_bonus_money": 0}


func _record_best_shift(record: Dictionary) -> void :
	var profile: Dictionary = record["profile"]
	profile["best_shift"] = maxi(int(profile["best_shift"]), int(record["shift_stats"]["money"]))


func _sanitize_profile(source: Dictionary) -> Dictionary:
	var profile: Dictionary = {"version": 1, "player_name": "Courier"}
	for key: String in ["money", "xp", "total_deliveries", "express_deliveries", "total_money_earned", "best_shift"]:
		var value: Variant = source.get(key, 0)
		var number: float = _number(value, 0.0)
		profile[key] = int(clampf(number, 0.0, float(MAX_PROFILE_VALUE)))
	profile["level"] = _level_for_xp(int(profile["xp"]))
	profile["rank"] = _rank_for_level(int(profile["level"]))
	profile.merge(VehicleCatalog.sanitize_profile_vehicles(source))
	profile.merge(CosmeticCatalog.sanitize_profile(source), true)
	return profile


func _number(value: Variant, fallback: float) -> float:
	if not (value is int or value is float):
		return fallback
	var result: float = float(value)
	return result if is_finite(result) else fallback


func _level_for_xp(xp: int) -> int:
	var level: int = 1
	var step: int = maxi(1, int(_number(_balance.get("level_xp_step", 150), 150.0)))
	while level < 10 and xp >= level * level * step:
		level += 1
	return level


func _rank_for_level(level: int) -> String:
	if level >= 10:
		return "Delivery Master"
	if level >= 6:
		return "Express Pro"
	if level >= 4:
		return "Fast Courier"
	if level >= 2:
		return "City Courier"
	return "Rookie Courier"


func _notice(peer_id: int, message: String) -> void :
	event_ready.emit(peer_id, {"type": "notice", "message": message, "session_id": session_id})


func _mark_changed() -> void :
	revision += 1
	_last_broadcast_msec = Time.get_ticks_msec()
	changed.emit()
