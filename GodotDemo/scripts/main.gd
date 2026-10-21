extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const LanSessionScript = preload("res://scripts/lan_session.gd")
const LanAuthorityScript = preload("res://scripts/lan_authority.gd")
const VehicleCatalogScript = preload("res://scripts/vehicle_catalog.gd")
const VehicleScript = preload("res://scripts/vehicle_controller.gd")
const VehiclePlacementScript = preload("res://scripts/vehicle_placement.gd")
const FragileRules = preload("res://scripts/fragile_rules.gd")
const SettingsService = preload("res://scripts/settings_service.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const NavigationService = preload("res://scripts/navigation_service.gd")
const CityOrderRules = preload("res://scripts/city_order_rules.gd")
const DistrictEventRules = preload("res://scripts/district_event_rules.gd")
const CosmeticCatalog = preload("res://scripts/cosmetic_catalog.gd")
const CheatCodeRules = preload("res://scripts/cheat_code_rules.gd")
const AircraftCombatRules = preload("res://scripts/aircraft_combat_rules.gd")
const CombatEffectsScript = preload("res://scripts/combat_effects.gd")
const SAVE_PATH: = "user://profile.json"
const DEMO_VERSION: = "0.16.0"

var city
var player
var hud
var profile: Dictionary = {}
var balance: Dictionary = {}
var city_order_config: Dictionary = {}
var district_event_config: Dictionary = {}
var _solo_elapsed_seconds: float = 0.0
var _solo_event_phase: String = "ended"
var _solo_event_id: String = ""
var _solo_event_delivered: int = 0
var _solo_event_bonus_money: int = 0
var _network_district_event: Dictionary = {}
var _network_order_event: Dictionary = {}
var orders: Array[Dictionary] = []
var active_order: Dictionary = {}
var state: String = "menu"
var modal: String = ""
var _customization_return_modal: String = ""
var _cheat_return_modal: String = ""
var _cheat_return_customization_modal: String = ""
var cosmetic_defs: Dictionary = {}
var shift_remaining: float = 900.0
var shift_stats: Dictionary = {}
var next_order_id: int = 1
var test_mode: bool = false
var load_notice: String = ""
var lan_session
var lan_authority
var remote_players: Dictionary = {}
var vehicle_defs: Dictionary = {}
var vehicles: Dictionary = {}
var _network_players: Array = []
var _network_leaderboard: Array = []
var _network_team: Dictionary = {}
var _network_handoffs: Dictionary = {}
var _last_network_revision: int = -1
var _snapshot_time_msec: int = 0
var _snapshot_remaining: float = 0.0
var _snapshot_order_remaining: float = 0.0
var _last_pose_msec: int = 0
var _closing_lan: bool = false
var _has_lan_started: bool = false
var settings_service
var navigation
var audio_manager
var combat_effects
var _network_air_combat: Dictionary = {}
var _aircraft_fire_armed: bool = false
var _last_aircraft_fire_msec: int = -1000
var _last_aircraft_shot_id: int = 0
var _solo_aircraft_shot_id: int = 0
var _vehicle_generation_floor: Dictionary = {}

func _ready() -> void :
	test_mode = OS.get_cmdline_user_args().has("--test-mode")
	_define_input()
	balance = _load_balance()
	city_order_config = CityOrderRules.load_config()
	district_event_config = DistrictEventRules.load_config()
	vehicle_defs = VehicleCatalogScript.load_definitions()
	cosmetic_defs = CosmeticCatalog.load_definitions()
	profile = _load_profile()
	city = WorldScript.new()
	add_child(city)
	navigation = NavigationService.new()
	navigation.configure(city.get_map_layout())
	player = PlayerScript.new()
	add_child(player)
	player.reset_at(city.spawn_position)
	_apply_profile_appearance()
	if player.has_method("set_view_direction"):
		player.set_view_direction(PI)
	hud = HudScript.new()
	add_child(hud)
	hud.set_map_layout(city.get_map_layout())
	hud.play_requested.connect(_play_solo)
	hud.quit_requested.connect(_quit_game)
	hud.resume_requested.connect(_resume)
	hud.restart_requested.connect(_restart_shift)
	hud.order_requested.connect(_accept_order)
	hud.abandon_requested.connect(_abandon_order)
	hud.modal_closed.connect(_close_modal)
	hud.multiplayer_requested.connect(_open_lan_menu)
	hud.host_requested.connect(_host_lan)
	hud.handoff_offer_requested.connect(_offer_handoff)
	hud.handoff_accept_requested.connect(_accept_handoff)
	hud.handoff_decline_requested.connect(_decline_handoff)
	hud.handoff_cancel_requested.connect(_cancel_handoff)
	hud.join_requested.connect(_join_lan)
	hud.ready_requested.connect(_set_lan_ready)
	hud.start_requested.connect(_start_lan_shift)
	hud.leave_requested.connect(_leave_lan)
	hud.vehicle_buy_requested.connect(_buy_vehicle)
	hud.vehicle_spawn_requested.connect(_spawn_vehicle)
	hud.garage_closed.connect(_close_modal)
	hud.customization_requested.connect(_open_customization)
	hud.cosmetic_buy_requested.connect(_buy_cosmetic)
	hud.cosmetic_select_requested.connect(_select_cosmetic)
	hud.customization_closed.connect(_close_customization)
	hud.cheats_requested.connect(_open_cheats)
	hud.cheat_code_requested.connect(_submit_cheat_code)
	hud.cheats_closed.connect(_close_cheats)
	hud.settings_requested.connect(_open_settings)
	hud.settings_apply_requested.connect(_apply_settings)
	hud.settings_closed.connect(_close_settings)
	hud.settings_confirm_requested.connect(_confirm_settings_preview)
	hud.settings_revert_requested.connect(_revert_settings_preview)
	lan_session = LanSessionScript.new()
	lan_session.name = "LanSession"
	add_child(lan_session)
	lan_session.lobby_changed.connect(_on_lan_lobby)
	lan_session.session_started.connect(_on_lan_started)
	lan_session.request_received.connect(_on_lan_request)
	lan_session.state_received.connect(_on_lan_state)
	lan_session.event_received.connect(_on_lan_event)
	lan_session.pose_received.connect(_on_lan_pose)
	lan_session.peer_left.connect(_on_lan_peer_left)
	lan_session.disconnected.connect(_on_lan_disconnected)
	lan_session.message_received.connect(_on_lan_message)
	lan_authority = LanAuthorityScript.new()
	lan_authority.name = "LanAuthority"
	add_child(lan_authority)
	lan_authority.changed.connect(_broadcast_lan_state)
	lan_authority.event_ready.connect(_send_lan_event)
	lan_authority.pose_ready.connect(_publish_lan_pose)
	settings_service = SettingsService.new()
	settings_service.name = "SettingsService"
	add_child(settings_service)
	settings_service.preview_changed.connect(_on_settings_preview_changed)
	settings_service.initialize(city, player, test_mode)
	audio_manager = AudioManagerScript.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	audio_manager.initialize(test_mode)
	combat_effects = CombatEffectsScript.new()
	combat_effects.name = "CombatEffects"
	add_child(combat_effects)
	hud.ui_click_requested.connect( func() -> void : _play_sound("ui_click"))
	_reset_shift_stats()
	hud.show_menu(profile)
	player.set_controls_enabled(false)
	player.set_mouse_captured(false)
	if not load_notice.is_empty():
		hud.notify(load_notice)
	if not settings_service.load_notice.is_empty():
		hud.notify(settings_service.load_notice)
	get_tree().auto_accept_quit = false

func _define_input() -> void :
	var bindings: Dictionary = {
		"move_left": KEY_A, "move_right": KEY_D, 
		"move_forward": KEY_W, "move_back": KEY_S, 
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "flight_descend": KEY_CTRL
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event: = InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)
	if not InputMap.has_action("aircraft_fire"):
		InputMap.add_action("aircraft_fire")
	var fire_button: = InputEventMouseButton.new()
	fire_button.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("aircraft_fire", fire_button)

func _process(delta: float) -> void :
	if hud == null or player == null:
		return
	audio_manager.set_context(state == "playing" and modal.is_empty(), player, player.riding_vehicle, remote_players)
	_update_aircraft_fire()
	if _lan_active():
		if state in ["playing", "paused"] and lan_session.phase == "playing":
			var now: int = Time.get_ticks_msec()
			if now - _last_pose_msec >= 50:
				_last_pose_msec = now
				lan_session.send_pose(_network_pose())
			var elapsed: float = float(now - _snapshot_time_msec) / 1000.0
			shift_remaining = -1.0 if _snapshot_remaining < 0.0 else maxf(0.0, _snapshot_remaining - elapsed)
			if not active_order.is_empty() and active_order.get("type", "standard") == "express":
				active_order["remaining"] = maxf(0.0, _snapshot_order_remaining - elapsed)
			_update_hud()
		return
	if state == "playing":
		_solo_elapsed_seconds += minf(maxf(delta, 0.0), maxf(shift_remaining, 0.0))
		shift_remaining = maxf(0.0, shift_remaining - delta)
		_advance_solo_event()
		if not active_order.is_empty() and active_order.get("type", "standard") == "express":
			active_order["remaining"] = maxf(0.0, float(active_order["remaining"]) - delta)
			if float(active_order["remaining"]) <= 0.0:
				_abandon_order()
				hud.notify("Время экспресс-заказа вышло. Возьмите новый заказ.")
		if shift_remaining <= 0.0:
			_end_shift()
		_update_hud()

func _input(event: InputEvent) -> void :
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_ESCAPE:
			if modal == "cheats":
				_close_cheats()
			elif modal == "customization":
				_close_customization()
			elif modal == "settings":
				_close_settings()
			elif state in ["network_menu", "connecting", "lobby"]:
				_leave_lan()
			elif state == "paused":
				_resume()
			elif state == "playing":
				if not modal.is_empty():
					_close_modal()
				else:
					_pause()
			get_viewport().set_input_as_handled()
		elif key == KEY_F2:
			if modal == "cheats":
				_close_cheats()
			else:
				_open_cheats()
			get_viewport().set_input_as_handled()
		elif modal in ["cheats", "customization", "settings"]:
			# LineEdit retains text/Enter events; player and vehicle controls
			# remain disabled until the dialog has closed.
			return
		elif state == "playing" and key == KEY_TAB:
			if modal == "orders":
				_close_modal()
			else:
				_open_orders()
			get_viewport().set_input_as_handled()
		elif state == "playing" and key == KEY_M:
			if modal == "map":
				_close_modal()
			else:
				_open_map()
			get_viewport().set_input_as_handled()
		elif state == "playing" and modal.is_empty() and key == KEY_E:
			_interact()
			get_viewport().set_input_as_handled()
		elif state == "playing" and modal.is_empty() and key == KEY_F:
			_toggle_vehicle()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_aircraft_fire_armed = false
		elif state == "playing" and modal.is_empty():
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				# A click that captures the pointer must never also fire a weapon.
				_aircraft_fire_armed = false
				player.set_mouse_captured(true)
			else:
				_aircraft_fire_armed = _can_fire_aircraft()
				if _aircraft_fire_armed:
					_request_aircraft_fire()

func _notification(what: int) -> void :
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == "playing":
			_pause()
		elif modal == "cheats":
			_close_cheats()
		elif modal == "customization":
			_close_customization()

func _begin_shift() -> void :
	if player == null:
		return
	_dismiss_settings()
	_dismiss_cheats()
	if _lan_active():
		_restart_shift()
		return

	if state in ["playing", "paused"]:
		_record_best_shift()
	_clear_vehicles()
	shift_remaining = float(balance.get("shift_seconds", 900))
	_solo_elapsed_seconds = 0.0
	_solo_event_phase = "waiting"
	_solo_event_id = "lunch_rush:1"
	_solo_event_delivered = 0
	_solo_event_bonus_money = 0
	_reset_shift_stats()
	active_order.clear()
	if navigation != null:
		navigation.clear()
	orders.clear()
	_network_team.clear()
	_network_handoffs.clear()
	_network_district_event.clear()
	_network_order_event.clear()
	player.set_carrying(false)
	player.reset_at(city.spawn_position)
	_spawn_owned_vehicle_at_start()
	if player.has_method("set_view_direction"):
		player.set_view_direction(PI)
	city.clear_objective()
	state = "playing"
	modal = ""
	hud.show_game()
	_fill_orders(true)
	_update_hud()
	_open_orders()
	hud.notify("Выберите заказ, заберите коробку и доставьте ее по адресу.")

func _reset_shift_stats() -> void :
	shift_stats = {"deliveries": 0, "money": 0, "xp": 0, "best_delivery": 0, "time_used": 0.0, "event_deliveries": 0, "event_bonus_money": 0}

func _make_order(first: bool = false, local_only: bool = false) -> Dictionary:
	var couriers: Array = [{"profile": profile, "position": player.position}]
	var order: Dictionary = CityOrderRules.make_order(next_order_id, city.pickup_points, city.delivery_points, balance, couriers, vehicle_defs, city_order_config, first, local_only)
	if not order.is_empty():
		next_order_id += 1
	return order

func _district_event_view() -> Dictionary:
	if _lan_active():
		var event: Dictionary = _network_district_event.duplicate(true)
		if event.is_empty():
			return {}
		var elapsed: float = maxf(0.0, float(Time.get_ticks_msec() - _snapshot_time_msec) / 1000.0)
		# Client prediction changes presentation only; the Host owns phase transitions.
		if str(event.get("phase", "")) == "active":
			event["remaining"] = maxf(0.0, float(event.get("remaining", 0.0)) - elapsed)
		elif str(event.get("phase", "")) in ["waiting", "cooldown"]:
			event["starts_in"] = maxf(0.0, float(event.get("starts_in", 0.0)) - elapsed)
		return event
	var event: Dictionary = DistrictEventRules.snapshot(_solo_elapsed_seconds, state in ["playing", "paused"], district_event_config)
	event["delivered"] = _solo_event_delivered
	event["bonus_money"] = _solo_event_bonus_money
	return event


func _order_event_view() -> Dictionary:
	if _lan_active():
		var view: Dictionary = _network_order_event.duplicate(true)
		if view.is_empty():
			return {}
		var elapsed: float = maxf(0.0, float(Time.get_ticks_msec() - _snapshot_time_msec) / 1000.0)
		view["remaining"] = maxf(0.0, float(view.get("remaining", 0.0)) - elapsed)
		if float(view["remaining"]) <= 0.0:
			view["bonus_available"] = false
			view["bonus_money"] = 0
		return view
	return DistrictEventRules.order_view(active_order, _solo_elapsed_seconds, state in ["playing", "paused"], district_event_config)


func _advance_solo_event() -> void:
	if _lan_active() or state != "playing":
		return
	var event: Dictionary = _district_event_view()
	var transition: bool = str(event["phase"]) != _solo_event_phase or str(event["id"]) != _solo_event_id
	_solo_event_phase = str(event["phase"])
	_solo_event_id = str(event["id"])
	var removed: bool = false
	for index: int in range(orders.size() - 1, -1, -1):
		if DistrictEventRules.is_event_order(orders[index]) and not DistrictEventRules.can_accept(orders[index], event):
			orders.remove_at(index)
			removed = true
	if transition or removed:
		_fill_orders()
		if event["phase"] == "active":
			hud.notify("Обеденный час! Кофейня → офисы делового центра: +%d%% к деньгам за доставку в следующие %d с." % [int(round((float(event["bonus_multiplier"]) - 1.0) * 100.0)), int(ceil(float(event["remaining"])))])


func _fill_orders(first: bool = false) -> void:
	if _lan_active():
		return
	var event: Dictionary = _district_event_view()
	for index: int in range(orders.size() - 1, -1, -1):
		if DistrictEventRules.is_event_order(orders[index]) and not DistrictEventRules.can_accept(orders[index], event):
			orders.remove_at(index)
	var count: int = clampi(int(balance.get("available_orders", 6)), 1, 6)
	var normal: Array[Dictionary] = DistrictEventRules.normal_orders(orders)
	while normal.size() < count:
		var local_only: bool = CityOrderRules.local_order_count(normal, city_order_config) < int(city_order_config["minimum_local_orders"])
		var order: Dictionary = _make_order(first and normal.is_empty(), local_only)
		if order.is_empty():
			break
		orders.append(order)
		normal.append(order)
	if event.get("phase", "") == "active":
		var event_count: int = orders.size() - normal.size()
		while event_count < int(district_event_config["available_orders"]):
			var order: Dictionary = DistrictEventRules.make_order(next_order_id, city.pickup_points, city.delivery_points, balance, event, district_event_config, orders)
			if order.is_empty():
				break
			next_order_id += 1
			orders.append(order)
			event_count += 1
	for order: Dictionary in orders:
		DistrictEventRules.publish_order_fields(order, _solo_elapsed_seconds, state == "playing", district_event_config)
	hud.set_orders(orders)


func _accept_order(order_id: int) -> void :
	if state != "playing":
		return
	if _lan_active():
		lan_session.request_action("accept", {"id": order_id})
		return
	if not active_order.is_empty():
		hud.notify("Сначала завершите текущий заказ или отмените его.")
		return
	for i in range(orders.size()):
		if int(orders[i]["id"]) != order_id:
			continue
		if not DistrictEventRules.can_accept(orders[i], _district_event_view()):
			orders.remove_at(i)
			hud.notify("Обеденный час завершен. Выберите другой заказ.")
			_fill_orders()
			return
		if int(profile["level"]) < int(orders[i].get("required_level", 1)):
			hud.notify("Этот тип заказа доступен с уровня %d." % int(orders[i]["required_level"]))
			return
		active_order = orders[i].duplicate(true)
		active_order["state"] = "Accepted"
		active_order["remaining"] = float(active_order["time_limit"])
		_play_sound("order_accept")
		orders.remove_at(i)
		_fill_orders()
		city.set_objective(active_order["pickup_position"], "Забрать: " + str(active_order["pickup_name"]), Color("efb84e"))
		_close_modal()
		hud.notify("Заказ принят. Идите к золотому маркеру и нажмите E.")
		_update_hud()
		return

func _target_position() -> Vector3:
	if active_order.is_empty():
		return player.global_position if player != null else Vector3.ZERO
	return active_order["delivery_position"] if active_order["state"] == "PickedUp" else active_order["pickup_position"]

func _can_interact() -> bool:
	if active_order.is_empty() or state != "playing" or not modal.is_empty() or player.is_riding():
		return false
	if not VehiclePlacementScript.is_near_floor(city, player.global_position):
		return false
	var target: Vector3 = _target_position()
	var position: Vector3 = player.global_position
	position.y = 0.0
	target.y = 0.0
	if position.distance_to(target) > float(balance.get("interaction_distance", 3.2)):
		return false
	var query: = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, 
		_target_position() + Vector3.UP, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _interact() -> void :
	if state == "playing" and modal.is_empty() and not player.is_riding() and _near_garage():
		_open_garage()
		return
	if player.is_riding():
		hud.notify("Остановитесь и нажмите F, чтобы слезть перед передачей коробки.")
		return
	if not _can_interact():
		return
	if _lan_active():
		lan_session.send_pose(_network_pose())
		lan_session.request_action("interact")
		return
	if active_order["state"] == "Accepted":
		active_order["state"] = "PickedUp"
		_play_sound("pickup")
		player.set_carrying(true)
		city.set_objective(active_order["delivery_position"], "Доставить: " + str(active_order["delivery_name"]), Color("42c4b5"))
		hud.notify("Коробка у вас. Доставьте ее к бирюзовому маркеру.")
	elif active_order["state"] == "PickedUp":
		_complete_delivery()
	_update_hud()

func _complete_delivery() -> void :
	if _lan_active() or player.is_riding():
		return
	if active_order.is_empty() or active_order.get("state", "") != "PickedUp":
		return

	var completed: Dictionary = active_order.duplicate(true)
	active_order.clear()
	if navigation != null:
		navigation.clear()
	var money: int = int(completed["reward"])
	var xp: int = int(completed["xp"])
	if completed["type"] == "express":
		money += int(round(float(completed["remaining"]) / float(completed["time_limit"]) * 80.0))
		profile["express_deliveries"] = int(profile["express_deliveries"]) + 1
	elif completed["type"] == "fragile":
		money += FragileRules.quality_bonus(completed)
	var event_bonus: int = DistrictEventRules.bonus_for_delivery(completed, money, _solo_elapsed_seconds, district_event_config)
	money += event_bonus
	if DistrictEventRules.is_event_order(completed):
		_solo_event_delivered += 1
		_solo_event_bonus_money += event_bonus
		shift_stats["event_deliveries"] = int(shift_stats.get("event_deliveries", 0)) + 1
		shift_stats["event_bonus_money"] = int(shift_stats.get("event_bonus_money", 0)) + event_bonus
	var previous_level: int = int(profile["level"])
	profile["money"] = mini(CheatCodeRules.MAX_PROFILE_VALUE, int(profile["money"]) + money)
	profile["xp"] = mini(CheatCodeRules.MAX_PROFILE_VALUE, int(profile["xp"]) + xp)
	profile["total_deliveries"] = int(profile["total_deliveries"]) + 1
	profile["total_money_earned"] = int(profile["total_money_earned"]) + money
	profile["level"] = _level_for_xp(int(profile["xp"]))
	profile["rank"] = _rank_for_level(int(profile["level"]))
	shift_stats["deliveries"] = int(shift_stats["deliveries"]) + 1
	shift_stats["money"] = int(shift_stats["money"]) + money
	shift_stats["xp"] = int(shift_stats["xp"]) + xp
	shift_stats["best_delivery"] = maxi(int(shift_stats["best_delivery"]), money)
	profile["best_shift"] = maxi(int(profile["best_shift"]), int(shift_stats["money"]))
	player.set_carrying(false)
	city.clear_objective()
	var saved: bool = _save_profile()
	_play_sound("delivery")
	if int(profile["level"]) > previous_level:
		_play_sound("level_up")
	var event_notice: String = " · Бонус обеденного часа +%d ₸" % event_bonus if event_bonus > 0 else (" · Заказ события: обычная награда" if DistrictEventRules.is_event_order(completed) else "")
	hud.notify("Доставка завершена! +%d ₸ · +%d XP%s%s" % [money, xp, event_notice,
		" · Новый уровень %d!" % int(profile["level"]) if int(profile["level"]) > previous_level else ""])
	if not saved:
		hud.notify("Доставка засчитана, но файл прогресса не удалось записать.")
	_fill_orders()

func _abandon_order() -> void :
	if _lan_active():
		if state == "playing":
			lan_session.request_action("abandon")
		return
	if active_order.is_empty():
		return
	active_order.clear()
	if navigation != null:
		navigation.clear()
	player.set_carrying(false)
	city.clear_objective()
	hud.notify("Заказ отменен. За завершенные доставки прогресс сохранен.")
	_update_hud()

func _update_hud() -> void :
	var order_title: String = "Готовы к следующей доставке?"
	var status: String = "Откройте заказы клавишей Tab"
	var target_name: String = ""
	var interaction: String = "Tab — выбрать заказ"
	var distance: float = 0.0
	if not active_order.is_empty():
		order_title = str(active_order["type_name"]) + " · " + str(active_order["title"])
		var picked: bool = active_order["state"] == "PickedUp"
		status = "Доставьте коробку клиенту" if picked else "Заберите коробку"
		target_name = str(active_order["delivery_name"] if picked else active_order["pickup_name"])
		distance = player.global_position.distance_to(_target_position())
		if active_order["type"] == "express":
			status += " · осталось %d с" % int(ceil(float(active_order["remaining"])))
		interaction = ("E — передать коробку" if picked else "E — забрать коробку") if _can_interact() else "Идите к маркеру · M — карта"
	if player.is_riding():
		interaction = "W/S — газ / тормоз · A/D — поворот · F — выйти после остановки"
		if _active_vehicle_name() == "car":
			interaction += " · Space — ручной тормоз"
		elif _active_vehicle_name() == "airplane":
			interaction = "WASD — полёт · Space ↑ · Ctrl ↓"
			interaction += " · F — выйти" if player.riding_vehicle.can_disembark() and absf(float(player.riding_vehicle.speed)) <= 1.5 else " · F — после посадки"
	elif _near_garage():
		interaction = "E — открыть гараж"
	elif _nearest_vehicle_owner() >= 0:
		interaction = "F — сесть в свой транспорт" if _nearest_vehicle_owner() == _local_vehicle_owner() else "Этот транспорт принадлежит другому курьеру"
	var route_key: String = "" if active_order.is_empty() else "%s:%s:%s" % [active_order.get("id", 0), active_order.get("state", ""), _target_position()]
	var route_data: Dictionary = navigation.guidance(player.global_position, _target_position(), route_key, _active_vehicle_name())
	if not active_order.is_empty():
		distance = float(route_data.get("distance", 0.0))
	var handoffs: Dictionary = _handoff_view()
	if not handoffs.get("incoming", []).is_empty() and not player.is_riding():
		interaction = "Tab — друг предлагает посылку · подтвердите передачу"
	elif not _handoff_candidates().is_empty():
		interaction += " · Tab — передать другу"
	var pose: Dictionary = player.get_network_pose()
	var aim: Dictionary = _aircraft_aim_view()
	hud.update_hud({
		"team": _network_team, "handoffs": handoffs,
		"district_event": _district_event_view(), "order_event": _order_event_view(),
		"handoff_candidates": _handoff_candidates(),
		"navigation": route_data, "player_yaw": float(pose.get("yaw", 0.0)),
		"money": int(profile["money"]), "xp": int(profile["xp"]), "level": int(profile["level"]), 
		"rank": str(profile["rank"]), "shift_remaining": shift_remaining, 
		"order_title": order_title, "order_status": status, "target_name": target_name, 
		"distance": distance, "interaction": interaction, "deliveries": int(shift_stats["deliveries"]), 
		"carrying": player.is_carrying, "player_position": player.global_position, 
		"target_position": _target_position(), "has_target": not active_order.is_empty(), 
		"other_players": _other_player_map_positions(), 
		"active_vehicle": _active_vehicle_name(),
		"vehicle_health": int(player.riding_vehicle.combat_health) if player.is_riding() else AircraftCombatRules.MAX_HEALTH,
		"air_kills": int(_network_air_combat.get("kills", 0)), "air_losses": int(_network_air_combat.get("losses", 0)),
		"can_fire": _can_fire_aircraft(), "aim_screen": aim.get("position", Vector2.ZERO), "aim_visible": bool(aim.get("visible", false)),
		"vehicle_altitude": maxf(0.0, player.riding_vehicle.global_position.y) if player.is_riding() else 0.0,
		"vehicle_grounded": player.riding_vehicle.can_disembark() and VehiclePlacementScript.is_near_floor(city, player.riding_vehicle.global_position) if player.is_riding() else true,
		"order_type": str(active_order.get("type", "")), 
		"order_state": str(active_order.get("state", "")), 
		"quality": float(active_order.get("quality", 100.0)), 
		"quality_bonus": FragileRules.quality_bonus(active_order), 
		"quality_bonus_max": int(active_order.get("quality_bonus_max", 0)), 
		"vehicle_speed": absf(float(player.riding_vehicle.speed)) if player.is_riding() else 0.0
	})

func _open_orders() -> void :
	if state != "playing" or modal in ["cheats", "customization", "settings"]:
		return
	hud.show_map(false)
	hud.hide_garage()
	modal = "orders"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	if not _lan_active():
		for order: Dictionary in orders:
			DistrictEventRules.publish_order_fields(order, _solo_elapsed_seconds, state == "playing", district_event_config)
	hud.set_orders(orders)
	hud.show_orders(true)

func _open_map() -> void :
	if state != "playing" or modal in ["cheats", "customization", "settings"]:
		return
	hud.show_orders(false)
	hud.hide_garage()
	modal = "map"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	_update_hud()
	hud.show_map(true, player.global_position, _target_position())

func _close_modal() -> void :
	_dismiss_cheats()
	hud.show_orders(false)
	hud.show_map(false)
	hud.hide_garage()
	hud.hide_customization()
	_customization_return_modal = ""
	modal = ""
	if state == "playing":
		hud.show_game()
		_set_gameplay_controls(true)
		player.set_mouse_captured(true)

func _pause() -> void :
	if state != "playing":
		return
	_dismiss_cheats()
	hud.show_orders(false)
	hud.show_map(false)
	hud.hide_garage()
	hud.hide_customization()
	_customization_return_modal = ""
	modal = ""
	state = "paused"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	hud.show_pause(profile)

func _resume() -> void :
	if state != "paused" or not modal.is_empty():
		return
	state = "playing"
	hud.show_game()
	_set_gameplay_controls(true)
	player.set_mouse_captured(true)

func _end_shift() -> void :
	_dismiss_settings()
	_dismiss_cheats()
	state = "results"
	_solo_event_phase = "ended"
	for index: int in range(orders.size() - 1, -1, -1):
		if DistrictEventRules.is_event_order(orders[index]):
			orders.remove_at(index)
	modal = ""
	shift_stats["time_used"] = float(balance.get("shift_seconds", 900)) - shift_remaining
	_record_best_shift()
	active_order.clear()
	if navigation != null:
		navigation.clear()
	player.set_carrying(false)
	city.clear_objective()
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	var results: Dictionary = shift_stats.duplicate(true)
	results["district_event"] = _district_event_view()
	hud.show_results(results)

func _record_best_shift() -> void :
	profile["best_shift"] = maxi(int(profile["best_shift"]), int(shift_stats.get("money", 0)))
	_save_profile()

func _quit_game() -> void :
	_dismiss_settings()
	_dismiss_cheats()
	if not profile.is_empty():
		_record_best_shift()
	if _lan_active():
		lan_session.leave("Host disconnected." if lan_session.is_host() else "")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit()


func _open_settings() -> void :
	if modal in ["cheats", "customization"]:
		return
	if state == "playing":
		_pause()
	if state not in ["menu", "paused"] or modal == "settings":
		return
	modal = "settings"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	hud.show_settings(settings_service.get_values(), settings_service.supported_resolutions(), settings_service.sanitize(SettingsService.default_values()))


func _apply_settings(candidate: Dictionary) -> void :
	if modal != "settings":
		return
	var pending: bool = settings_service.apply_candidate(candidate)
	if not settings_service.last_error.is_empty():
		hud.set_settings_notice(settings_service.last_error)
	elif pending:
		hud.update_settings_preview(true, settings_service.preview_seconds_remaining())
	else:
		hud.show_settings(settings_service.get_values(), settings_service.supported_resolutions(), settings_service.sanitize(SettingsService.default_values()))
		hud.set_settings_notice("Настройки сохранены.")


func _confirm_settings_preview() -> void :
	if modal != "settings" or not settings_service.has_pending_preview():
		return
	var saved: bool = settings_service.confirm_preview()
	var message: String = "Настройки сохранены." if saved else settings_service.last_error
	if message.is_empty():
		message = "Время подтверждения вышло. Настройки экрана возвращены."
	hud.set_settings_notice(message)


func _revert_settings_preview() -> void :
	if modal != "settings" or not settings_service.has_pending_preview():
		return
	settings_service.cancel_preview()
	hud.set_settings_notice("Настройки экрана возвращены.")


func _on_settings_preview_changed(pending: bool, seconds: float) -> void :
	if modal != "settings" or hud == null:
		return
	if not pending:
		hud.show_settings(settings_service.get_values(), settings_service.supported_resolutions(), settings_service.sanitize(SettingsService.default_values()))
		hud.set_settings_notice("Настройки экрана возвращены.")
	hud.update_settings_preview(pending, seconds)


func _close_settings() -> void :
	if modal != "settings":
		return
	_dismiss_settings()
	if state == "menu":
		hud.show_menu(profile)
	elif state == "paused":
		hud.show_pause(profile)


func _dismiss_settings() -> void :


	if settings_service != null and settings_service.has_pending_preview():
		if modal == "settings":
			modal = ""
		settings_service.cancel_preview()
	if hud != null:
		hud.hide_settings()
	if modal == "settings":
		modal = ""

func _default_profile() -> Dictionary:
	return {"version": 1, "player_name": "Courier", "money": 0, "xp": 0, "level": 1, 
		"rank": "Rookie Courier", "total_deliveries": 0, "express_deliveries": 0, 
		"total_money_earned": 0, "best_shift": 0, "owned_vehicles": [], "selected_vehicle": "",
		"appearance": CosmeticCatalog.default_appearance(), "owned_cosmetics": []}

func _load_balance() -> Dictionary:
	var file: = FileAccess.open("res://assets/balance.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _load_profile() -> Dictionary:
	var result: Dictionary = _default_profile()
	if test_mode:
		return result

	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(SAVE_PATH + ".backup"):
		DirAccess.rename_absolute(SAVE_PATH + ".backup", SAVE_PATH)
	if not FileAccess.file_exists(SAVE_PATH):
		return result
	var file: = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		load_notice = "Не удалось прочитать профиль. Создан временный новый профиль."
		return result
	var parser: = JSON.new()
	var error: int = parser.parse(file.get_as_text())
	var parsed: Variant = parser.data
	file.close()
	if error != OK or not parsed is Dictionary:
		load_notice = "Поврежденный профиль сохранен как резервная копия. Создан новый."
		DirAccess.rename_absolute(SAVE_PATH, "user://profile.corrupt-%d.json" % Time.get_unix_time_from_system())
		return result
	for key in ["money", "xp", "total_deliveries", "express_deliveries", "total_money_earned", "best_shift"]:
		var value: Variant = parsed.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
			load_notice = "Профиль содержит неверные данные. Загружены безопасные значения."
			continue
		result[key] = int(minf(float(value), float(CheatCodeRules.MAX_PROFILE_VALUE)))
	if parsed.get("player_name", "Courier") is String:
		result["player_name"] = _clean_player_name(str(parsed.get("player_name", "Courier")))
	result["level"] = _level_for_xp(int(result["xp"]))
	result["rank"] = _rank_for_level(int(result["level"]))
	result.merge(VehicleCatalogScript.sanitize_profile_vehicles(parsed), true)
	result.merge(CosmeticCatalog.sanitize_profile(parsed), true)
	return result

func _save_profile() -> bool:
	profile.merge(CosmeticCatalog.sanitize_profile(profile), true)
	if test_mode:
		return true
	var temporary: String = SAVE_PATH + ".tmp"
	var file: = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	if not ok:
		return false
	var replacement: int = DirAccess.rename_absolute(temporary, SAVE_PATH)
	if replacement != OK:

		var backup: String = SAVE_PATH + ".backup"
		if FileAccess.file_exists(SAVE_PATH):
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				return false
			if DirAccess.rename_absolute(SAVE_PATH, backup) != OK:
				return false
		replacement = DirAccess.rename_absolute(temporary, SAVE_PATH)
		if replacement == OK:
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
		elif FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, SAVE_PATH)
	return replacement == OK

func _level_for_xp(xp: int) -> int:
	var level: int = 1
	var step: int = maxi(1, int(balance.get("level_xp_step", 150)))
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


func _lan_active() -> bool:
	return lan_session != null and lan_session.is_active()


func _local_vehicle_owner() -> int:
	return int(lan_session.local_id) if _lan_active() else 0


func _active_vehicle_name() -> String:
	return str(player.riding_vehicle.definition.get("id", "walking")) if player.is_riding() else "walking"


func _vehicle_label(type: String) -> String:
	return str({"bicycle": "Велосипед", "scooter": "Скутер", "car": "Автомобиль", "airplane": "Самолёт Air Courier"}.get(type, "Транспорт"))


func _next_vehicle_generation(owner_id: int) -> int:
	var current: int = int(vehicles[owner_id].get_meta("generation", 0)) if vehicles.has(owner_id) else 0
	return maxi(current, int(_vehicle_generation_floor.get(owner_id, 0))) + 1


func _network_pose() -> Dictionary:
	var pose: Dictionary = player.get_network_pose()
	pose["active_vehicle"] = _active_vehicle_name()
	pose["vehicle_generation"] = int(player.riding_vehicle.get_meta("generation", 0)) if player.is_riding() else 0
	return pose


func _near_garage() -> bool:
	return VehiclePlacementScript.can_use_garage(player.global_position, city)


func _set_gameplay_controls(enabled: bool) -> void :
	if not enabled:
		_aircraft_fire_armed = false
	if not enabled and is_instance_valid(audio_manager):
		audio_manager.stop_gameplay()
	player.set_controls_enabled(enabled)
	for owner_id in vehicles:
		var vehicle = vehicles[owner_id]
		vehicle.set_controls_enabled(enabled and int(owner_id) == _local_vehicle_owner() and vehicle.occupied)


func _nearest_vehicle_owner() -> int:
	var own_id: int = _local_vehicle_owner()
	if vehicles.has(own_id) and player.global_position.distance_to(vehicles[own_id].global_position) <= 2.8:
		return own_id
	var nearest: int = -1
	var distance: float = 2.8
	for owner_id in vehicles:
		var candidate: float = player.global_position.distance_to(vehicles[owner_id].global_position)
		if candidate <= distance:
			distance = candidate
			nearest = int(owner_id)
	return nearest


func _can_use_cheats() -> bool:
	if not _lan_active():
		return state in ["menu", "playing", "paused"]
	return state in ["playing", "paused"] and lan_session.phase == "playing"


func _open_cheats() -> void:
	if modal == "cheats":
		return
	if not _can_use_cheats():
		hud.notify("Чит-коды доступны в профиле перед подключением и во время активной смены.")
		return
	if modal == "settings" or (settings_service != null and settings_service.has_pending_preview()):
		hud.notify("Сначала закройте настройки и подтвердите или отмените изменения экрана.")
		return
	_cheat_return_modal = modal
	_cheat_return_customization_modal = _customization_return_modal
	hud.show_orders(false)
	hud.show_map(false)
	hud.hide_garage()
	hud.hide_customization()
	modal = "cheats"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	hud.show_cheats(profile)


func _close_cheats() -> void:
	if modal != "cheats":
		return
	var previous_modal: String = _cheat_return_modal
	var previous_customization_modal: String = _cheat_return_customization_modal
	_dismiss_cheats()
	if previous_modal == "customization" and _can_edit_cosmetics():
		modal = "customization"
		_customization_return_modal = previous_customization_modal
		hud.show_customization(profile, cosmetic_defs)
	elif state == "menu":
		hud.show_menu(profile)
	elif state == "paused":
		hud.show_pause(profile)
	elif state == "playing":
		if previous_modal == "garage" and not player.is_riding() and _near_garage():
			_open_garage()
		elif previous_modal == "orders":
			_open_orders()
		elif previous_modal == "map":
			_open_map()
		else:
			_close_modal()


func _dismiss_cheats() -> void:
	if hud != null:
		hud.hide_cheats()
	if modal == "cheats":
		modal = ""
	_cheat_return_modal = ""
	_cheat_return_customization_modal = ""


func _submit_cheat_code(raw_code: String) -> void:
	if modal != "cheats" or not _can_use_cheats():
		return
	if _lan_active():
		if CheatCodeRules.normalize_code(raw_code).is_empty():
			hud.set_cheat_notice("Введите код длиной от 1 до 64 символов без переносов строк.", true)
			return
		hud.set_cheat_notice("Код отправлен Host…")
		# Clients submit only a bounded code; amounts and targets are never sent.
		lan_session.request_action("cheat_code", {"code": raw_code})
		return
	var previous_level: int = int(profile.get("level", 1))
	var step: int = maxi(1, int(balance.get("level_xp_step", 150)))
	var result: Dictionary = CheatCodeRules.apply(profile, raw_code, step)
	if bool(result.get("changed", false)):
		var saved: bool = _save_profile()
		hud.update_cheats_profile(profile)
		if int(profile["level"]) > previous_level:
			_play_sound("level_up")
		if state in ["playing", "paused"]:
			_update_hud()
		if not saved:
			result["message"] = str(result.get("message", "")) + " Профиль не удалось записать: проверьте папку сохранений."
	hud.set_cheat_notice(str(result.get("message", "")), not bool(result.get("ok", false)))


func _can_edit_cosmetics() -> bool:
	if not _lan_active() and state == "menu":
		return true
	return state in ["playing", "paused"] and not player.is_riding() and _near_garage() and (not _lan_active() or lan_session.phase == "playing")


func _open_customization() -> void:
	if modal in ["cheats", "settings"]:
		return
	if not _can_edit_cosmetics():
		hud.notify("Стиль доступен в профиле перед подключением или в гараже пешком.")
		return
	_customization_return_modal = modal
	modal = "customization"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	hud.show_customization(profile, cosmetic_defs)


func _close_customization() -> void:
	if modal != "customization":
		return
	hud.hide_customization()
	var previous_modal: String = _customization_return_modal
	_customization_return_modal = ""
	modal = ""
	if state == "menu":
		hud.show_menu(profile)
	elif state == "paused":
		hud.show_pause(profile)
	elif state == "playing" and previous_modal == "garage" and _near_garage() and not player.is_riding():
		_open_garage()
	elif state == "playing":
		_close_modal()


func _buy_cosmetic(category: String, item_id: String) -> void:
	_cosmetic_action(category, item_id, true)


func _select_cosmetic(category: String, item_id: String) -> void:
	_cosmetic_action(category, item_id, false)


func _cosmetic_action(category: String, item_id: String, purchasing: bool) -> void:
	if modal != "customization" or not _can_edit_cosmetics():
		return
	if _lan_active():
		lan_session.request_action("cosmetic_buy" if purchasing else "cosmetic_select", {"category": category, "id": item_id})
		return
	var result: Dictionary = CosmeticCatalog.buy(profile, category, item_id) if purchasing else CosmeticCatalog.select(profile, category, item_id)
	if bool(result.get("changed", false)):
		_apply_profile_appearance()
		var saved: bool = _save_profile()
		hud.update_customization(profile, cosmetic_defs)
		if purchasing and bool(result.get("ok", false)) and int(CosmeticCatalog.get_item(category, item_id).get("price", 0)) > 0:
			_play_sound("purchase")
		if not saved:
			result["message"] = str(result.get("message", "")) + " Профиль не удалось записать: проверьте папку сохранений."
	hud.set_customization_notice(str(result.get("message", "")), not bool(result.get("ok", false)))


func _apply_profile_appearance() -> void:
	var appearance: Dictionary = CosmeticCatalog.sanitize_profile(profile)["appearance"]
	if player != null and is_instance_valid(player) and player.has_method("apply_appearance"):
		player.apply_appearance(appearance)
	var owner_id: int = _local_vehicle_owner() if lan_session != null else 0
	if vehicles.has(owner_id) and is_instance_valid(vehicles[owner_id]):
		vehicles[owner_id].apply_appearance(appearance)


func _open_garage() -> void :
	if state != "playing" or modal in ["cheats", "customization", "settings"] or player.is_riding() or not _near_garage():
		return
	modal = "garage"
	_set_gameplay_controls(false)
	player.set_mouse_captured(false)
	hud.show_game()
	hud.show_garage(profile, vehicle_defs)


func _buy_vehicle(type: String) -> void :
	if state != "playing":
		return
	if _lan_active():
		lan_session.request_action("vehicle_buy", {"type": type})
		return
	if player.is_riding() or not _near_garage() or not vehicle_defs.has(type):
		hud.notify("Для покупки подойдите к гаражу пешком и нажмите E.")
		return
	var definition: Dictionary = vehicle_defs[type]
	var label: String = _vehicle_label(type)
	var owned: Array = profile.get("owned_vehicles", []).duplicate()
	if owned.has(type):
		hud.notify("%s уже куплен." % label)
		return
	if int(profile["level"]) < int(definition["required_level"]):
		hud.notify("%s открывается на уровне %d." % [label, int(definition["required_level"])])
		return
	if int(profile["money"]) < int(definition["price"]):
		hud.notify("Недостаточно денег: %s стоит %d ₸." % [label.to_lower(), int(definition["price"])])
		return
	var yaw: float = float(player.get_network_pose().get("yaw", PI))
	var parking: Variant = VehiclePlacementScript.find_spawn(city, player.global_position, yaw, [], definition)
	if not parking is Vector3:
		hud.notify("Рядом нет места для транспорта. Отойдите от стены.")
		return
	owned.append(type)
	profile["owned_vehicles"] = owned
	profile["selected_vehicle"] = type
	profile["money"] = int(profile["money"]) - int(definition["price"])
	_upsert_vehicle(_local_vehicle_owner(), {"owner_id": _local_vehicle_owner(), "type": type, "position": parking, "yaw": yaw, "occupied": false, "generation": _next_vehicle_generation(_local_vehicle_owner())}, true)
	var saved: bool = _save_profile()
	hud.update_garage(profile, vehicle_defs)
	_play_sound("purchase")
	hud.notify("%s куплен! Закройте гараж и нажмите F возле него." % label if saved else "%s куплен, но профиль не удалось записать. Проверьте доступ к папке сохранений." % label)
	_update_hud()


func _spawn_vehicle(type: String) -> void :
	if state != "playing":
		return
	if _lan_active():
		lan_session.request_action("vehicle_spawn", {"type": type})
		return
	if player.is_riding() or not _near_garage() or not vehicle_defs.has(type) or not profile.get("owned_vehicles", []).has(type):
		hud.notify("Купленный транспорт можно вызвать у гаража пешком.")
		return
	if int(profile["level"]) < int(vehicle_defs[type]["required_level"]):
		hud.notify("Ваш уровень пока не позволяет использовать этот транспорт.")
		return
	var yaw: float = float(player.get_network_pose().get("yaw", PI))
	var parking: Variant = VehiclePlacementScript.find_spawn(city, player.global_position, yaw, [], vehicle_defs[type])
	if not parking is Vector3:
		hud.notify("Нет свободного места возле курьера.")
		return
	profile["selected_vehicle"] = type
	_upsert_vehicle(_local_vehicle_owner(), {"owner_id": _local_vehicle_owner(), "type": type, "position": parking, "yaw": yaw, "occupied": false, "generation": _next_vehicle_generation(_local_vehicle_owner())}, true)
	var saved: bool = _save_profile()
	hud.notify("%s рядом. Закройте гараж и нажмите F." % _vehicle_label(type) if saved else "Транспорт подан, но профиль не удалось записать.")
	hud.update_garage(profile, vehicle_defs)
	_update_hud()


func _toggle_vehicle(owner_id: int = -1) -> void :
	if state != "playing" or not modal.is_empty():
		return
	var own_id: int = _local_vehicle_owner()
	var requested_id: int = own_id if player.is_riding() else (_nearest_vehicle_owner() if owner_id < 0 else owner_id)
	if requested_id < 0:
		hud.notify("Подойдите к своему транспорту. Его можно купить у гаража.")
		return
	if _lan_active():
		lan_session.send_pose(_network_pose())
		lan_session.request_action("vehicle_toggle", {"owner_id": requested_id})
		return
	if requested_id != own_id or not vehicles.has(own_id):
		hud.notify("Можно использовать только свой транспорт.")
		return
	var vehicle = vehicles[own_id]
	if not player.is_riding() and int(profile["level"]) < int(vehicle.definition["required_level"]):
		hud.notify("Ваш уровень пока не позволяет использовать этот транспорт.")
		return
	if player.is_riding():
		if not vehicle.can_disembark() or not VehiclePlacementScript.is_near_floor(city, vehicle.global_position):
			hud.notify("Для выхода сначала приземлитесь на свободную площадку и остановитесь.")
			return
		if absf(float(vehicle.speed)) > 1.5:
			hud.notify("Сначала остановите транспорт клавишей S.")
			return
		var exit_position: Variant = VehiclePlacementScript.find_exit(city, vehicle.global_position, vehicle.rotation.y, [], vehicle.definition)
		if not exit_position is Vector3:
			hud.notify("Рядом нет безопасного места для выхода. Отъедьте от стены.")
			return
		player.set_riding_vehicle(null)
		vehicle.set_occupied(false)
		vehicle.set_controls_enabled(false)
		player.correct_network_position(exit_position)
	else:
		if not vehicle.can_disembark() or not VehiclePlacementScript.is_near_floor(city, vehicle.global_position):
			hud.notify("Сесть в транспорт можно после его приземления.")
			return
		if player.global_position.distance_to(vehicle.global_position) > 2.8 or not VehiclePlacementScript.has_line_of_sight(city, player.global_position, vehicle.global_position):
			hud.notify("Подойдите ближе к своему транспорту.")
			return
		if not VehiclePlacementScript.position_is_free(city, vehicle.global_position, vehicle.rotation.y, vehicle.definition):
			hud.notify("Транспорт заблокирован. Подайте его снова в гараже.")
			return
		vehicle.set_occupied(true)
		player.set_riding_vehicle(vehicle)
	vehicle.set_meta("generation", _next_vehicle_generation(own_id))
	_set_gameplay_controls(true)
	_update_hud()


func _spawn_owned_vehicle_at_start() -> void :
	var type: String = str(profile.get("selected_vehicle", ""))
	if not vehicle_defs.has(type) or not profile.get("owned_vehicles", []).has(type) or int(profile["level"]) < int(vehicle_defs[type]["required_level"]):
		return
	var parking: Variant = VehiclePlacementScript.find_spawn(city, city.spawn_position, PI, [], vehicle_defs[type])
	if parking is Vector3:
		_upsert_vehicle(0, {"owner_id": 0, "type": type, "position": parking, "yaw": PI, "occupied": false, "generation": 1}, true)


func _upsert_vehicle(owner_id: int, data: Dictionary, force_transform: bool = false) -> void :
	var type: String = str(data.get("type", ""))
	if not vehicle_defs.has(type):
		return
	var generation: int = maxi(0, int(data.get("generation", 0)))
	if generation < int(_vehicle_generation_floor.get(owner_id, 0)):
		return
	if vehicles.has(owner_id):
		if generation < int(vehicles[owner_id].get_meta("generation", 0)):
			return
		if str(vehicles[owner_id].definition.get("id", "")) != type:
			_remove_vehicle(owner_id)
	var created: bool = not vehicles.has(owner_id)
	if created:
		var vehicle = VehicleScript.new()
		vehicle.name = "Vehicle_%d" % owner_id
		vehicle.configure(vehicle_defs[type], owner_id, owner_id != _local_vehicle_owner())
		vehicle.impact.connect(_on_vehicle_impact.bind(owner_id))
		add_child(vehicle)
		vehicles[owner_id] = vehicle
	var vehicle = vehicles[owner_id]
	var replaced_generation: bool = generation > int(vehicle.get_meta("generation", 0))
	vehicle.set_meta("generation", generation)
	var previous_occupied: bool = vehicle.occupied
	var occupied: bool = bool(data.get("occupied", false))
	var incoming: Dictionary = data.duplicate(true)

	if occupied and previous_occupied and not force_transform and not created and not replaced_generation:
		incoming.erase("position")
		incoming.erase("yaw")
		incoming.erase("velocity")
	vehicle.apply_network_state(incoming)
	vehicle.set_combat_health(int(data.get("health", AircraftCombatRules.MAX_HEALTH)))
	if created or force_transform or replaced_generation or previous_occupied != occupied:
		vehicle.reset_at(data.get("position", vehicle.global_position), float(data.get("yaw", vehicle.rotation.y)))
	vehicle.set_occupied(occupied)
	var member: Dictionary = lan_session.members.get(owner_id, {}) if _lan_active() else {}
	var ids: Array = lan_session.members.keys() if _lan_active() else [0]
	ids.sort()
	vehicle.set_network_identity(str(member.get("name", profile.get("player_name", "Courier"))), maxi(0, ids.find(owner_id)))
	var fallback_appearance: Dictionary = profile.get("appearance", {}) if owner_id == _local_vehicle_owner() else member.get("appearance", {})
	vehicle.apply_appearance(CosmeticCatalog.normalize_appearance(data.get("appearance", fallback_appearance)))
	var courier = player if owner_id == _local_vehicle_owner() else remote_players.get(owner_id)
	if courier != null and is_instance_valid(courier):
		courier.set_riding_vehicle(vehicle if occupied else null)
		vehicle.set_carrying(courier.is_carrying)
	vehicle.set_controls_enabled(owner_id == _local_vehicle_owner() and occupied and state == "playing" and modal.is_empty())


func _on_vehicle_impact(normal_speed: float, owner_id: int) -> void :


	if _lan_active() or state != "playing" or not modal.is_empty() or owner_id != 0 or not player.is_riding():
		return
	if FragileRules.apply_impact(active_order, normal_speed, Time.get_ticks_msec(), balance):
		hud.notify("Хрупкий груз: состояние %d%% · бонус %d ₸" % [int(round(float(active_order["quality"]))), FragileRules.quality_bonus(active_order)])
		_update_hud()


func _sync_vehicles(states: Array) -> void :
	var present: Dictionary = {}
	for value in states:
		if not value is Dictionary:
			continue
		var owner_id: int = int(value.get("owner_id", -1))
		if owner_id < 0 or (_lan_active() and not lan_session.members.has(owner_id)):
			continue
		present[owner_id] = true
		_upsert_vehicle(owner_id, value)
	for owner_id in vehicles.keys():
		if not present.has(owner_id):
			_remove_vehicle(int(owner_id))


func _remove_vehicle(owner_id: int) -> void :
	if not vehicles.has(owner_id):
		return
	var vehicle = vehicles[owner_id]
	if player.riding_vehicle == vehicle:
		player.set_riding_vehicle(null)
	for avatar in remote_players.values():
		if is_instance_valid(avatar) and avatar.riding_vehicle == vehicle:
			avatar.set_riding_vehicle(null)
	vehicles.erase(owner_id)
	remove_child(vehicle)
	vehicle.queue_free()


func _clear_vehicles() -> void :
	_reset_aircraft_combat()
	if is_instance_valid(audio_manager):
		audio_manager.stop_gameplay()
	for owner_id in vehicles.keys():
		_remove_vehicle(int(owner_id))


func _clean_player_name(value: String) -> String:
	var result: = value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(32)
	return "Courier" if result.is_empty() else result


func _play_solo() -> void :
	if _lan_active():
		_leave_lan()
	hud.set_network_mode(false, false)
	player.set_network_identity("", 0)
	_begin_shift()


func _restart_shift() -> void :
	if not _lan_active():
		_begin_shift()
		return
	if not lan_session.is_host():
		hud.notify("Следующую смену запускает Host.")
		return
	for peer_id in lan_session.members:
		var confirmed: Dictionary = lan_authority.get_profile(int(peer_id))
		if not confirmed.is_empty():
			lan_session.update_member_profile(int(peer_id), confirmed)
	lan_authority.stop_session()
	lan_session.return_to_lobby()


func _open_lan_menu() -> void :
	_dismiss_cheats()
	state = "network_menu"
	modal = ""
	player.set_controls_enabled(false)
	player.set_mouse_captured(false)
	hud.show_lan_menu(profile)


func _host_lan(player_name: String, room_name: String, max_players: int, shift_seconds: int, shift_mode: String = "competitive") -> void :
	if _lan_active():
		return
	profile["player_name"] = _clean_player_name(player_name)
	_save_profile()
	state = "connecting"
	hud.set_connecting("Создание LAN-комнаты…")
	var error: int = lan_session.host_game(profile, room_name, max_players, shift_seconds, shift_mode)
	if error != OK:
		state = "network_menu"
		hud.show_lan_menu(profile, "Не удалось создать комнату. Возможно, порт 7777 уже занят.")


func _join_lan(player_name: String, address: String) -> void :
	if _lan_active():
		return
	profile["player_name"] = _clean_player_name(player_name)
	_save_profile()
	state = "connecting"
	hud.set_connecting("Подключение к Host…")
	var error: int = lan_session.join_game(profile, address)
	if error != OK:
		state = "network_menu"
		hud.show_lan_menu(profile, "Проверьте IP-адрес Host и наличие активной комнаты.")


func _set_lan_ready(ready: bool) -> void :
	if _lan_active():
		lan_session.set_ready(ready)


func _start_lan_shift() -> void :
	if _lan_active() and lan_session.is_host():
		lan_session.start_game()


func _on_lan_lobby(data: Dictionary) -> void :
	if _closing_lan or not _lan_active():
		return
	if str(data.get("phase", "lobby")) != "lobby":
		return
	lan_authority.stop_session()
	_dismiss_cheats()
	state = "lobby"
	modal = ""
	active_order.clear()
	if navigation != null:
		navigation.clear()
	orders.clear()
	_network_team.clear()
	_network_handoffs.clear()
	_network_district_event.clear()
	_network_order_event.clear()
	_clear_vehicles()
	city.clear_objective()
	player.set_carrying(false)
	player.set_controls_enabled(false)
	player.set_mouse_captured(false)
	_clear_remote_players()
	hud.set_network_mode(true, lan_session.is_host())
	hud.show_lobby(data, lan_session.is_host())


func _on_lan_started(data: Dictionary) -> void :
	if _closing_lan or not _lan_active():
		return
	_dismiss_cheats()
	_has_lan_started = true
	_last_network_revision = -1
	_last_pose_msec = Time.get_ticks_msec()
	_snapshot_time_msec = _last_pose_msec
	_snapshot_remaining = float(data.get("shift_seconds", 900))
	shift_remaining = _snapshot_remaining
	active_order.clear()
	if navigation != null:
		navigation.clear()
	orders.clear()
	_network_team.clear()
	_network_handoffs.clear()
	_network_district_event.clear()
	_network_order_event.clear()
	_network_leaderboard.clear()
	_reset_shift_stats()
	_clear_vehicles()
	_clear_remote_players()
	city.clear_objective()
	player.set_carrying(false)
	state = "playing"
	modal = ""
	var roster: Array = data.get("players", [])
	for index in range(roster.size()):
		var member: Dictionary = roster[index]
		var peer_id: int = int(member.get("id", 0))
		var spawn: Vector3 = city.spawn_position + Vector3(float(index % 2) * 2.0, 0, floorf(float(index) / 2.0) * 2.0)
		if peer_id == lan_session.local_id:
			player.reset_at(spawn)
			player.set_network_identity(str(member.get("name", "Courier")), index)
			player.apply_appearance(CosmeticCatalog.normalize_appearance(member.get("appearance", profile.get("appearance", {}))))
		else:
			_spawn_remote_player(peer_id, str(member.get("name", "Courier")), spawn, index, CosmeticCatalog.normalize_appearance(member.get("appearance", {})))
	player.set_view_direction(PI)
	player.set_controls_enabled(true)
	player.set_mouse_captured(true)
	hud.set_network_mode(true, lan_session.is_host())
	hud.show_game()
	if lan_session.is_host():
		lan_authority.start_session(data, roster, city, balance, str(data.get("session_id", "")))
	_update_hud()
	_open_orders()
	hud.notify("Командная смена: выполняйте общий план. Tab — передать посылку другу рядом." if str(data.get("shift_mode", "competitive")) == "team" else "Общие заказы: кто первым принял, тот и выполняет доставку.")


func _on_lan_request(peer_id: int, action: String, payload: Dictionary) -> void :
	if _lan_active() and lan_session.is_host():
		lan_authority.handle_request(peer_id, action, payload)


func _broadcast_lan_state() -> void :
	if not _lan_active() or not lan_session.is_host() or lan_authority.phase not in ["playing", "results"]:
		return
	for peer_id in lan_session.members:
		var snapshot: Dictionary = lan_authority.snapshot_for(int(peer_id))
		if not snapshot.is_empty():
			lan_session.send_state(int(peer_id), snapshot)


func _send_lan_event(peer_id: int, event: Dictionary) -> void :
	if _lan_active() and lan_session.is_host():
		lan_session.send_event(peer_id, event)


func _publish_lan_pose(peer_id: int, pose: Dictionary) -> void :
	if _lan_active() and lan_session.is_host():
		lan_session.publish_pose(peer_id, pose)


func _order_list_signature(values: Array) -> Array:
	var signature: Array = []
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var order: Dictionary = value.duplicate(true)
		# Countdown changes must not replace focused/scrolling order cards every 500 ms.
		for key: String in ["event_remaining", "event_bonus_money", "event_bonus_available"]:
			order.erase(key)
		signature.append(order)
	return signature


func _on_lan_state(data: Dictionary) -> void :
	if _closing_lan or not _lan_active():
		return
	if str(data.get("session_id", "")) != lan_session.session_id:
		return
	var revision: int = int(data.get("revision", -1))
	if revision <= _last_network_revision:
		return
	var had_snapshot: bool = _last_network_revision >= 0
	var previous_deliveries: int = int(shift_stats.get("deliveries", 0))
	var previous_level: int = int(profile.get("level", 1))
	var previous_owned: Array = profile.get("owned_vehicles", []).duplicate()
	var previous_cosmetics: Array = profile.get("owned_cosmetics", []).duplicate()
	_last_network_revision = revision
	var prior_order: Dictionary = active_order.duplicate(true)
	var confirmed: Dictionary = data.get("profile", {})
	var profile_changed: bool = not confirmed.is_empty() and confirmed != profile
	if profile_changed:
		profile = confirmed.duplicate(true)
		profile.merge(CosmeticCatalog.sanitize_profile(profile), true)
		_apply_profile_appearance()
		if not _save_profile():
			hud.notify("Награда подтверждена, но файл профиля не удалось записать.")
	shift_stats = data.get("shift_stats", {}).duplicate(true)
	_network_team = data.get("team", {}).duplicate(true)
	_network_handoffs = data.get("handoffs", {}).duplicate(true)
	_network_district_event = data.get("district_event", {}).duplicate(true)
	_network_order_event = data.get("order_event", {}).duplicate(true)
	_network_air_combat = data.get("air_combat", {}).duplicate(true)
	shift_stats["air_kills"] = int(_network_air_combat.get("kills", 0))
	shift_stats["air_losses"] = int(_network_air_combat.get("losses", 0))
	var received_orders: Array = data.get("orders", [])
	var orders_changed: bool = _order_list_signature(orders) != _order_list_signature(received_orders)
	orders.assign(received_orders)
	active_order = data.get("active_order", {}).duplicate(true)
	if had_snapshot:
		_play_confirmed_lan_audio(prior_order, previous_deliveries, previous_level, previous_owned)
		if previous_cosmetics.size() < profile.get("owned_cosmetics", []).size():
			_play_sound("purchase")
	_snapshot_time_msec = Time.get_ticks_msec()
	_snapshot_remaining = float(data.get("remaining", 900.0))
	_snapshot_order_remaining = float(active_order.get("remaining", 0.0))
	shift_remaining = _snapshot_remaining
	_network_players = data.get("players", []).duplicate(true)
	_network_leaderboard = data.get("leaderboard", []).duplicate(true)
	_sync_remote_roster(_network_players)
	_sync_vehicles(data.get("vehicles", []))
	var carrying: bool = active_order.get("state", "") == "PickedUp"
	player.set_carrying(carrying)
	if profile_changed and modal == "garage":
		hud.update_garage(profile, vehicle_defs)
	elif profile_changed and modal == "customization":
		hud.update_customization(profile, cosmetic_defs)
	elif profile_changed and modal == "cheats":
		hud.update_cheats_profile(profile)
	if prior_order.get("id", -1) != active_order.get("id", -1) or prior_order.get("state", "") != active_order.get("state", ""):
		city.clear_objective()
		if not active_order.is_empty():
			city.set_objective(_target_position(), 
				("Доставить: " + str(active_order["delivery_name"])) if carrying else ("Забрать: " + str(active_order["pickup_name"])), 
				Color("42c4b5") if carrying else Color("efb84e"))
			if prior_order.is_empty():
				_close_modal()

	if orders_changed:
		hud.set_orders(orders)
	_update_hud()
	if str(data.get("phase", "playing")) == "results":
		_dismiss_settings()
		_dismiss_cheats()
		lan_session.phase = "results"
		state = "results"
		modal = ""
		_set_gameplay_controls(false)
		player.set_mouse_captured(false)
		var results: Dictionary = shift_stats.duplicate(true)
		results["leaderboard"] = _network_leaderboard
		results["team"] = _network_team.duplicate(true)
		results["district_event"] = _network_district_event.duplicate(true)
		hud.show_results(results)


func _play_sound(event_name: String) -> void :
	if is_instance_valid(audio_manager):
		audio_manager.play_event(event_name)


func _play_confirmed_lan_audio(prior_order: Dictionary, previous_deliveries: int, previous_level: int, previous_owned: Array) -> void :

	var same_order: bool = not active_order.is_empty() and int(prior_order.get("id", -1)) == int(active_order.get("id", -2))
	if active_order.get("state", "") == "Accepted" and not same_order:
		_play_sound("order_accept")
	elif active_order.get("state", "") == "PickedUp" and (not same_order or prior_order.get("state", "") != "PickedUp"):
		_play_sound("pickup")
	if int(shift_stats.get("deliveries", 0)) > previous_deliveries:
		_play_sound("delivery")
	if int(profile.get("level", 1)) > previous_level:
		_play_sound("level_up")
	for owned: Variant in profile.get("owned_vehicles", []):
		if not previous_owned.has(owned):
			_play_sound("purchase")
			break


func _on_lan_event(event: Dictionary) -> void :
	if _closing_lan or not _lan_active():
		return
	if event.has("session_id") and str(event["session_id"]) != lan_session.session_id:
		return
	if str(event.get("type", event.get("kind", ""))) == "aircraft_shot":
		_display_aircraft_shot(event)
		return
	if str(event.get("type", "")) == "aircraft_recovery":
		var owner_id: int = _local_vehicle_owner()
		var recovery_generation: int = int(event.get("generation", 0))
		if recovery_generation < int(_vehicle_generation_floor.get(owner_id, 0)) or (vehicles.has(owner_id) and int(vehicles[owner_id].get_meta("generation", 0)) > recovery_generation):
			return
		_vehicle_generation_floor[owner_id] = maxi(int(_vehicle_generation_floor.get(owner_id, 0)), recovery_generation)
		_remove_vehicle(owner_id)
		_aircraft_fire_armed = false
		var recovery_position: Variant = event.get("position")
		if recovery_position is Vector3 and recovery_position.is_finite():
			player.correct_network_position(recovery_position)
		hud.notify(str(event.get("message", "Самолёт сбит! Ваш курьер спасён у гаража.")))
		_update_hud()
		return
	if str(event.get("type", "notice")) == "vehicle_state":
		var vehicle_data: Variant = event.get("vehicle", {})
		if vehicle_data is Dictionary:
			if vehicle_data.is_empty():
				_remove_vehicle(_local_vehicle_owner())
			else:
				_upsert_vehicle(_local_vehicle_owner(), vehicle_data, true)
		var confirmed_position: Variant = event.get("position")
		if confirmed_position is Vector3:
			player.correct_network_position(confirmed_position)
	elif str(event.get("type", "notice")) == "correction":
		var vehicle_data: Variant = event.get("vehicle", {})
		if vehicle_data is Dictionary:
			if vehicle_data.is_empty():
				_remove_vehicle(_local_vehicle_owner())
			else:
				_upsert_vehicle(_local_vehicle_owner(), vehicle_data, true)
		var position_value: Variant = event.get("position")
		if position_value is Vector3:
			player.correct_network_position(position_value)
	elif str(event.get("type", "")) == "cheat_result":
		if modal == "cheats":
			hud.set_cheat_notice(str(event.get("message", "")), not bool(event.get("ok", false)))
		else:
			hud.notify(str(event.get("message", "")))
	elif str(event.get("type", "")) == "cosmetic_result":
		if modal == "customization":
			hud.set_customization_notice(str(event.get("message", "")), not bool(event.get("ok", false)))
		else:
			hud.notify(str(event.get("message", "")))
	elif event.get("message", "") is String:
		hud.notify(str(event.get("message", "")))


func _on_lan_message(message: String) -> void :
	if _closing_lan:
		return
	if state in ["network_menu", "connecting"]:
		if _lan_active():
			hud.set_connecting(message)
		else:
			hud.show_lan_menu(profile, message)
	else:
		hud.notify(message)


func _spawn_remote_player(peer_id: int, display_name: String, position_value: Vector3, color_index: int, appearance: Dictionary = {}) -> void :
	if peer_id <= 0 or peer_id == lan_session.local_id or remote_players.has(peer_id):
		return
	var avatar = PlayerScript.new()
	avatar.name = "Remote_%d" % peer_id
	avatar.configure_remote(display_name, color_index)
	add_child(avatar)
	avatar.reset_at(position_value)
	avatar.apply_appearance(CosmeticCatalog.normalize_appearance(appearance))
	avatar.apply_network_pose({"position": position_value, "yaw": PI, "velocity": Vector3.ZERO, "grounded": true, "carrying": false})
	remote_players[peer_id] = avatar


func _sync_remote_roster(roster: Array) -> void :
	var present: Dictionary = {}
	for index in range(roster.size()):
		var record: Dictionary = roster[index]
		var peer_id: int = int(record.get("id", 0))
		if not bool(record.get("connected", true)) or peer_id == lan_session.local_id:
			continue
		present[peer_id] = true
		_spawn_remote_player(peer_id, str(record.get("name", "Courier")), record.get("position", city.spawn_position), index)
		if remote_players.has(peer_id):
			remote_players[peer_id].apply_appearance(CosmeticCatalog.normalize_appearance(record.get("appearance", {})))
			remote_players[peer_id].set_carrying(bool(record.get("carrying", false)))
	for peer_id in remote_players.keys():
		if not present.has(peer_id):
			_remove_remote_player(int(peer_id))


func _on_lan_pose(peer_id: int, pose: Dictionary) -> void :
	if not _lan_active() or peer_id == lan_session.local_id or state not in ["playing", "paused"]:
		return
	if not lan_session.members.has(peer_id):
		return
	if not remote_players.has(peer_id):
		var member: Dictionary = lan_session.members[peer_id]
		_spawn_remote_player(peer_id, str(member.get("name", "Courier")), pose.get("position", city.spawn_position), 0)
	if remote_players.has(peer_id):
		var vehicle_data: Variant = pose.get("vehicle", {})
		if vehicle_data is Dictionary and not vehicle_data.is_empty():
			if int(vehicle_data.get("generation", 0)) < int(_vehicle_generation_floor.get(peer_id, 0)):
				return
			if vehicles.has(peer_id) and int(vehicle_data.get("generation", 0)) < int(vehicles[peer_id].get_meta("generation", 0)):
				return
			_upsert_vehicle(peer_id, vehicle_data)
			if vehicles.has(peer_id):
				vehicles[peer_id].apply_network_state(vehicle_data)
		elif vehicle_data is Dictionary and vehicle_data.is_empty() and str(pose.get("active_vehicle", "walking")) == "walking" and int(pose.get("vehicle_generation", 0)) > 0:
			var walking_generation: int = int(pose["vehicle_generation"])
			if walking_generation < int(_vehicle_generation_floor.get(peer_id, 0)) or (vehicles.has(peer_id) and int(vehicles[peer_id].get_meta("generation", 0)) > walking_generation):
				return
			_vehicle_generation_floor[peer_id] = maxi(int(_vehicle_generation_floor.get(peer_id, 0)), walking_generation)
			_remove_vehicle(peer_id)
		remote_players[peer_id].apply_network_pose(pose)


func _other_player_map_positions() -> Array:
	var positions: Array = []
	for peer_id in remote_players:
		var avatar = remote_players[peer_id]
		var member: Dictionary = lan_session.members.get(peer_id, {}) if _lan_active() else {}
		var map_pose: Dictionary = avatar.get_network_pose()
		var vehicle_type: String = str(avatar.riding_vehicle.definition.get("id", "walking")) if avatar.is_riding() else "walking"
		positions.append({"id": int(peer_id), "name": str(member.get("name", "Courier")), "position": avatar.global_position, "active_vehicle": vehicle_type, "yaw": float(map_pose.get("yaw", 0.0))})
	return positions


func _remove_remote_player(peer_id: int) -> void :
	_remove_vehicle(peer_id)
	if not remote_players.has(peer_id):
		return
	var avatar = remote_players[peer_id]
	remote_players.erase(peer_id)
	remove_child(avatar)
	avatar.queue_free()


func _clear_remote_players() -> void :
	for peer_id in remote_players.keys():
		_remove_remote_player(int(peer_id))
	_network_players.clear()


func _on_lan_peer_left(peer_id: int) -> void :
	_remove_remote_player(peer_id)
	if _lan_active() and lan_session.is_host():
		lan_authority.remove_player(peer_id)


func _leave_lan() -> void :
	if _closing_lan:
		return
	_closing_lan = true
	_record_best_shift()
	lan_authority.stop_session()
	if _lan_active():
		lan_session.leave()
	_return_to_main_menu()
	_closing_lan = false


func _on_lan_disconnected(reason: String) -> void :
	if _closing_lan:
		return
	var was_in_room: bool = _has_lan_started or state in ["lobby", "playing", "paused", "results"]
	_record_best_shift()
	lan_authority.stop_session()
	_return_to_main_menu()
	if was_in_room:
		hud.notify(reason if not reason.is_empty() else "Host disconnected.")
	else:
		state = "network_menu"
		hud.show_lan_menu(profile, reason)


func _return_to_main_menu() -> void :
	_dismiss_settings()
	_dismiss_cheats()
	state = "menu"
	modal = ""
	_has_lan_started = false
	_last_network_revision = -1
	active_order.clear()
	if navigation != null:
		navigation.clear()
	orders.clear()
	_network_team.clear()
	_network_handoffs.clear()
	_network_district_event.clear()
	_network_order_event.clear()
	_network_leaderboard.clear()
	_clear_vehicles()
	_clear_remote_players()
	city.clear_objective()
	player.set_carrying(false)
	player.set_network_identity("", 0)
	_apply_profile_appearance()
	player.reset_at(city.spawn_position)
	player.set_view_direction(PI)
	player.set_controls_enabled(false)
	player.set_mouse_captured(false)
	hud.set_network_mode(false, false)
	hud.show_menu(profile)

func _handoff_view() -> Dictionary:
	if not _lan_active() or not bool(_network_team.get("enabled", false)):
		return {"incoming": [], "outgoing": {}}
	var view: Dictionary = _network_handoffs.duplicate(true)
	var elapsed: float = maxf(0.0, float(Time.get_ticks_msec() - _snapshot_time_msec) / 1000.0)
	var incoming: Array = []
	for offer: Dictionary in view.get("incoming", []):
		offer["remaining"] = maxf(0.0, float(offer.get("remaining", 0.0)) - elapsed)
		if float(offer["remaining"]) > 0.0:
			incoming.append(offer)
	view["incoming"] = incoming
	var outgoing: Dictionary = view.get("outgoing", {})
	if not outgoing.is_empty():
		outgoing["remaining"] = maxf(0.0, float(outgoing.get("remaining", 0.0)) - elapsed)
		if float(outgoing["remaining"]) <= 0.0:
			outgoing = {}
	view["outgoing"] = outgoing
	return view


func _handoff_candidates() -> Array:
	var candidates: Array = []
	if not _lan_active() or not bool(_network_team.get("enabled", false)) or player.is_riding() or active_order.get("state", "") != "PickedUp":
		return candidates
	for member: Dictionary in _network_players:
		var peer_id: int = int(member.get("id", 0))
		if peer_id == lan_session.local_id or not bool(member.get("connected", false)) or bool(member.get("has_order", true)):
			continue
		if str(member.get("active_vehicle", "walking")) != "walking":
			continue
		var position: Vector3 = member.get("position", Vector3.INF)
		if player.global_position.distance_to(position) <= 3.2:
			candidates.append({"id": peer_id, "name": str(member.get("name", "Курьер"))})
	return candidates


func _request_handoff(action: String, payload: Dictionary = {}) -> void:
	if state != "playing" or not _lan_active() or not bool(_network_team.get("enabled", false)):
		return
	lan_session.send_pose(_network_pose())
	lan_session.request_action(action, payload)


func _offer_handoff(target_id: int) -> void:
	_request_handoff("offer_handoff", {"target_id": target_id})


func _accept_handoff(sender_id: int, offer_id: int) -> void:
	_request_handoff("accept_handoff", {"sender_id": sender_id, "offer_id": offer_id})


func _decline_handoff(sender_id: int, offer_id: int) -> void:
	_request_handoff("decline_handoff", {"sender_id": sender_id, "offer_id": offer_id})


func _cancel_handoff() -> void:
	_request_handoff("cancel_handoff")


# Aircraft guns always follow the fuselage heading. Camera orbit changes only
# the projected aim marker, never the authoritative shot direction.
func _aircraft_aim_view() -> Dictionary:
	if player == null or not player.is_riding() or _active_vehicle_name() != "airplane" or not is_instance_valid(player.camera):
		return {"position": Vector2.ZERO, "visible": false}
	var vehicle = player.riding_vehicle
	var muzzle: Vector3 = AircraftCombatRules.muzzle(vehicle.global_position, vehicle.rotation.y)
	var direction: Vector3 = AircraftCombatRules.shot_direction(vehicle.rotation.y)
	var distance: float = AircraftCombatRules.RANGE
	var obstruction: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, muzzle + direction * distance, 1))
	if not obstruction.is_empty():
		distance = muzzle.distance_to(obstruction["position"])
	# Project the visible first hit, so a nearby opponent aligns with the marker
	# despite the third-person camera's offset from the nose. This is UI only;
	# the Host independently validates the eventual shot and damage.
	for other in vehicles.values():
		if other == vehicle or not is_instance_valid(other) or not other.is_airplane() or not bool(other.occupied) or other.global_position.y < AircraftCombatRules.MIN_COMBAT_ALTITUDE or int(other.combat_health) <= 0:
			continue
		distance = minf(distance, AircraftCombatRules.ray_hit_distance(muzzle, direction, other.global_position, other.rotation.y, other.definition))
	var target: Vector3 = muzzle + direction * distance
	if player.camera.is_position_behind(target):
		return {"position": Vector2.ZERO, "visible": false}
	var screen: Vector2 = player.camera.unproject_position(target)
	return {"position": screen, "visible": get_viewport().get_visible_rect().grow(-24.0).has_point(screen)}


func _can_fire_aircraft() -> bool:
	if state != "playing" or not modal.is_empty() or player == null or not player.is_riding() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var vehicle = player.riding_vehicle
	return _active_vehicle_name() == "airplane" and vehicle.owner_peer_id == _local_vehicle_owner() and bool(vehicle.controls_enabled) and bool(vehicle.occupied) and vehicle.global_position.y >= AircraftCombatRules.MIN_COMBAT_ALTITUDE and int(vehicle.combat_health) > 0


func _update_aircraft_fire() -> void:
	if not _can_fire_aircraft():
		_aircraft_fire_armed = false
		return
	if _aircraft_fire_armed and Input.is_action_pressed("aircraft_fire"):
		_request_aircraft_fire()


func _request_aircraft_fire() -> void:
	if not _can_fire_aircraft():
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_aircraft_fire_msec < AircraftCombatRules.COOLDOWN_MSEC:
		return
	_last_aircraft_fire_msec = now
	var vehicle = player.riding_vehicle
	if _lan_active():
		# Give Host the latest validated pose before asking to fire. No target,
		# reward, damage amount or arbitrary direction is accepted from a client.
		lan_session.send_pose(_network_pose())
		lan_session.request_action("aircraft_fire", {"generation": int(vehicle.get_meta("generation", 0))})
		return
	var origin: Vector3 = AircraftCombatRules.muzzle(vehicle.global_position, vehicle.rotation.y)
	var endpoint: Vector3 = origin + AircraftCombatRules.shot_direction(vehicle.rotation.y) * AircraftCombatRules.RANGE
	var ray: = PhysicsRayQueryParameters3D.create(origin, endpoint, 1)
	ray.hit_from_inside = true
	var obstruction: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(ray)
	if not obstruction.is_empty():
		endpoint = obstruction["position"]
	var nose_ray: = PhysicsRayQueryParameters3D.create(vehicle.global_position + Vector3.UP * AircraftCombatRules.MUZZLE_HEIGHT, origin, 1)
	nose_ray.hit_from_inside = true
	var nose_obstruction: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(nose_ray)
	if not nose_obstruction.is_empty():
		origin = nose_obstruction["position"]
		endpoint = origin
	_solo_aircraft_shot_id += 1
	_display_aircraft_shot({"type": "aircraft_shot", "shot_id": _solo_aircraft_shot_id, "shooter_id": _local_vehicle_owner(), "shooter_generation": int(vehicle.get_meta("generation", 0)), "from": origin, "to": endpoint, "hit_id": 0, "health": 0, "destroyed": false, "target_position": endpoint})


func _display_aircraft_shot(event: Dictionary) -> void:
	if state not in ["playing", "paused"] or not is_instance_valid(combat_effects):
		return
	var shot_id: int = int(event.get("shot_id", 0))
	if shot_id <= _last_aircraft_shot_id:
		return
	var shooter_id: int = int(event.get("shooter_id", -1))
	if _lan_active() and not lan_session.members.has(shooter_id):
		return
	if vehicles.has(shooter_id) and int(event.get("shooter_generation", 0)) != int(vehicles[shooter_id].get_meta("generation", 0)):
		return
	var from: Variant = event.get("from")
	var to: Variant = event.get("to")
	if not from is Vector3 or not to is Vector3 or not from.is_finite() or not to.is_finite():
		return
	_last_aircraft_shot_id = shot_id
	combat_effects.show_shot(event)
	if shooter_id == _local_vehicle_owner():
		_play_sound("aircraft_fire")
	var target_id: int = int(event.get("hit_id", 0))
	if target_id <= 0:
		return
	if target_id == _local_vehicle_owner() or shooter_id == _local_vehicle_owner():
		_play_sound("aircraft_hit")
	if vehicles.has(target_id) and int(event.get("target_generation", 0)) == int(vehicles[target_id].get_meta("generation", 0)):
		vehicles[target_id].set_combat_health(int(event.get("health", 0)))
	if shooter_id == _local_vehicle_owner():
		hud.notify_aircraft_hit(bool(event.get("destroyed", false)))
	if bool(event.get("destroyed", false)):
		var destroyed_generation: int = int(event.get("target_generation", 0))
		_vehicle_generation_floor[target_id] = maxi(int(_vehicle_generation_floor.get(target_id, 0)), destroyed_generation + 1)
		# A delayed event for the old airframe must not remove a newly spawned one.
		if not vehicles.has(target_id) or int(vehicles[target_id].get_meta("generation", 0)) <= destroyed_generation:
			_remove_vehicle(target_id)
			if target_id == _local_vehicle_owner():
				_aircraft_fire_armed = false


func _reset_aircraft_combat() -> void:
	_aircraft_fire_armed = false
	_last_aircraft_fire_msec = -1000
	_last_aircraft_shot_id = 0
	_solo_aircraft_shot_id = 0
	_vehicle_generation_floor.clear()
	_network_air_combat.clear()
	if is_instance_valid(combat_effects):
		combat_effects.clear_effects()
