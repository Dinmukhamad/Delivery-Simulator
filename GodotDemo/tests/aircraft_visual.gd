extends SceneTree

# Capture the production garage and a genuinely moving production aircraft.
# Starting career values and the courier's initial garage/boarding positions
# are fixtures. Purchase, placement, boarding and flight use the real game.
# --test-mode keeps the user's profile outside this harness.
const AIRCRAFT_ID: String = "airplane"
const STARTING_MONEY: int = 60000
const STARTING_XP: int = 12150

func _initialize() -> void:
	call_deferred("_run")

func _release_flight_inputs() -> void:
	for action: String in ["jump", "flight_descend", "move_forward", "move_back", "move_left", "move_right"]:
		if InputMap.has_action(action):
			Input.action_release(action)

func _fail(message: String) -> void:
	_release_flight_inputs()
	printerr("AIRCRAFT_VISUAL: " + message)
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("AIRCRAFT_VISUAL: captures require --test-mode.")
		quit(2)
		return
	var capture: String = ""
	var width: int = 1280
	var screen: String = "game"
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--screen="):
			screen = arg.trim_prefix("--screen=")
	if capture.is_empty() or width not in [960, 1280] or screen not in ["game", "garage"]:
		printerr("AIRCRAFT_VISUAL: use --capture=PATH --width=960|1280 --screen=game|garage.")
		quit(2)
		return
	var height: int = width * 9 / 16
	DisplayServer.window_set_size(Vector2i(width, height))
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.set_process(false)
	app.set_process_input(false)
	if not app.test_mode or int(app.profile.get("money", -1)) != 0 or int(app.profile.get("xp", -1)) != 0 or not app.profile.get("owned_vehicles", []).is_empty():
		_fail("The isolated capture did not start with the default career.")
		return
	app.profile["money"] = STARTING_MONEY
	app.profile["xp"] = STARTING_XP
	app.profile["level"] = app._level_for_xp(STARTING_XP)
	app.profile["rank"] = app._rank_for_level(int(app.profile["level"]))
	app._play_solo()
	app._close_modal()
	app.player.reset_at(Vector3(-66.0, 0.15, 10.0))
	app.player.set_view_direction(PI)
	app.player.set_controls_enabled(false)
	app.player.set_mouse_captured(false)
	if screen == "game" and not app.orders.is_empty():
		app._accept_order(int(app.orders[0]["id"]))
	var shift_before: Dictionary = app.shift_stats.duplicate(true)
	app._open_garage()
	for i: int in range(6):
		await process_frame
	if app.modal != "garage" or not app.hud._garage_cards.has(AIRCRAFT_ID):
		_fail("The production garage has no aircraft card.")
		return
	var card: Dictionary = app.hud._garage_cards[AIRCRAFT_ID]
	var buy: Button = card["buy"]
	if buy.disabled or not buy.is_visible_in_tree():
		_fail("The production aircraft purchase is unavailable at level 10 with enough money.")
		return
	var price: int = int(app.vehicle_defs[AIRCRAFT_ID]["price"])
	buy.pressed.emit()
	await physics_frame
	var owner_id: int = app._local_vehicle_owner()
	if int(app.profile.get("money", -1)) != STARTING_MONEY - price or not app.profile.get("owned_vehicles", []).has(AIRCRAFT_ID) or str(app.profile.get("selected_vehicle", "")) != AIRCRAFT_ID or not app.vehicles.has(owner_id):
		_fail("The real purchase did not debit exactly the catalog price and retain aircraft ownership.")
		return
	var aircraft = app.vehicles[owner_id]
	if str(aircraft.definition.get("id", "")) != AIRCRAFT_ID or aircraft.find_children("*", "MeshInstance3D", true, false).size() < 8:
		_fail("The garage did not create the actual aircraft model.")
		return
	var generation: int = int(aircraft.get_meta("generation", 0))
	var spawn: Button = card["spawn"]
	if spawn.disabled or not spawn.is_visible_in_tree():
		_fail("The purchased aircraft has no available production spawn action.")
		return
	spawn.pressed.emit()
	await physics_frame
	aircraft = app.vehicles[owner_id]
	if int(aircraft.get_meta("generation", 0)) <= generation or int(app.profile.get("money", -1)) != STARTING_MONEY - price:
		_fail("Spawning the owned aircraft failed or charged its price again.")
		return
	if app.shift_stats != shift_before:
		_fail("Buying or spawning an aircraft altered delivery earnings.")
		return
	_clear_toasts(app)
	var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
	if screen == "garage":
		if not await _check_garage(app, view):
			return
	else:
		if not await _fly_and_check(app, aircraft, owner_id, view):
			return
	for i: int in range(5):
		await process_frame
		app._update_hud()
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	_release_flight_inputs()
	if rendered.is_empty() or rendered.get_width() != width or rendered.get_height() != height:
		_fail("The actual viewport render has an unexpected size.")
		return
	if _sampled_colors(rendered) < 24:
		_fail("The capture contains too little actual rendered detail.")
		return
	if rendered.save_png(capture) != OK:
		_fail("Could not save the actual aircraft render.")
		return
	print("AIRCRAFT_VISUAL: %s rendered at %dx%d; real purchase, spawn, aircraft model and tenge verified%s" % [screen, width, height, "; production flight and altitude HUD verified" if screen == "game" else "; all four garage cards and aircraft actions reachable"])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)

func _check_garage(app, view: Rect2) -> bool:
	if not app.hud._garage.is_visible_in_tree() or app.hud._garage_cards.size() != 4:
		_fail("The real garage does not expose all four vehicle cards.")
		return false
	if not app.hud._garage_profile.text.contains("₸") or app.hud._garage_profile.text.contains("₽"):
		_fail("The garage balance does not use tenge.")
		return false
	for vehicle_id: String in ["bicycle", "scooter", "car", AIRCRAFT_ID]:
		var vehicle_card: Dictionary = app.hud._garage_cards[vehicle_id]
		var panel: Control = vehicle_card["panel"]
		var scroll: ScrollContainer = _scroll_parent(panel)
		if scroll == null:
			_fail("The garage has no scroll path to its lower vehicle cards.")
			return false
		for key: String in ["name", "specs", "status", "spawn" if vehicle_id == AIRCRAFT_ID else "buy"]:
			var control: Control = vehicle_card[key]
			scroll.ensure_control_visible(control)
			for i: int in range(3):
				await process_frame
			if not _inside_visible_scroll(control, view):
				_fail("A real garage card label/action cannot be revealed: %s/%s." % [vehicle_id, key])
				return false
	var card: Dictionary = app.hud._garage_cards[AIRCRAFT_ID]
	var aircraft_panel: Control = card["panel"]
	var final_scroll: ScrollContainer = _scroll_parent(aircraft_panel)
	final_scroll.ensure_control_visible(aircraft_panel)
	for i: int in range(5):
		await process_frame
	for key: String in ["name", "specs", "spawn"]:
		if not _inside_visible_scroll(card[key], view):
			_fail("The final garage view clips the aircraft name, tenge price or spawn action.")
			return false
	var specs: Label = card["specs"]
	var label: Label = card["name"]
	if not label.text.contains("Air Courier") or not specs.text.contains("₸") or specs.text.contains("₽"):
		_fail("The visible aircraft card omits its name or tenge price.")
		return false
	return true

func _fly_and_check(app, aircraft, owner_id: int, view: Rect2) -> bool:
	app._close_modal()
	# A freshly respawned body needs real floor-contact physics before the
	# production boarding checks can accept it. Never move the aircraft here.
	for i: int in range(60):
		if aircraft.can_disembark():
			break
		await physics_frame
	if not aircraft.can_disembark():
		_fail("The freshly spawned aircraft did not settle on the ground within 60 physics frames.")
		return false
	# Only place the courier for boarding. The aircraft is never teleported into
	# the air: lift and horizontal movement below come from production physics.
	app.player.correct_network_position(aircraft.global_position + aircraft.global_basis.x * 2.4)
	app._toggle_vehicle(owner_id)
	if not app.player.is_riding() or app.player.riding_vehicle != aircraft or not aircraft.occupied or not aircraft.controls_enabled:
		_fail("The production boarding action did not mount the purchased aircraft.")
		return false
	app.player.set_view_direction(PI)
	app.player.set_mouse_captured(false)
	var start_position: Vector3 = aircraft.global_position
	Input.action_press("jump")
	for i: int in range(180):
		await physics_frame
	Input.action_release("jump")
	if aircraft.global_position.y < start_position.y + 12.0 or aircraft.is_on_floor():
		_fail("The production Space action did not lift the aircraft into real flight.")
		return false
	Input.action_press("move_forward")
	for i: int in range(120):
		await physics_frame
	var horizontal_distance: float = Vector2(aircraft.global_position.x - start_position.x, aircraft.global_position.z - start_position.z).length()
	if horizontal_distance < 5.0 or float(aircraft.speed) < 2.0 or aircraft.can_disembark():
		_fail("The production aircraft did not move in flight or incorrectly allows an airborne exit.")
		return false
	app._update_hud()
	var data: Dictionary = app.hud._last_data
	if str(data.get("active_vehicle", "")) != AIRCRAFT_ID or float(data.get("vehicle_altitude", -1.0)) < 12.0 or bool(data.get("vehicle_grounded", true)):
		_fail("The actual gameplay HUD did not receive airborne aircraft altitude/state.")
		return false
	if not app.hud._money.text.contains("₸") or app.hud._money.text.contains("₽") or not app.hud._vehicle.text.contains("Самолёт"):
		_fail("The visible gameplay labels omit the aircraft or tenge wallet.")
		return false
	for key_hint: String in ["Space", "Ctrl", "F"]:
		if not app.hud._keys.text.contains(key_hint):
			_fail("The production flight controls omit %s." % key_hint)
			return false
	var visible_altitude: bool = false
	for label: Label in app.hud._game.find_children("*", "Label", true, false):
		if label.text.to_lower().contains("высот") and _inside_visible_scroll(label, view):
			visible_altitude = true
	if not visible_altitude or not app.hud._game.is_visible_in_tree():
		_fail("The production altitude indicator is absent or clipped.")
		return false
	var camera: Camera3D = app.player.camera
	var center: Vector3 = aircraft.global_position + Vector3.UP
	if not camera.is_current() or camera.global_position.distance_to(app.player.global_position) < 5.0 or camera.is_position_behind(center) or not view.has_point(camera.unproject_position(center)):
		_fail("The actual gameplay camera does not frame the flying aircraft.")
		return false
	# Use every visible production mesh's actual world transform, including
	# visual pitch/bank, so cropped wings, nose, tail or pilot cannot pass.
	var visible_meshes: int = 0
	for mesh: MeshInstance3D in aircraft.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		visible_meshes += 1
		var bounds: AABB = mesh.get_aabb()
		for corner: int in range(8):
			var world_corner: Vector3 = mesh.global_transform * bounds.get_endpoint(corner)
			if camera.is_position_behind(world_corner) or not view.has_point(camera.unproject_position(world_corner)):
				_fail("A visible aircraft mesh is clipped by the gameplay capture: %s, corner %d." % [str(mesh.get_path()), corner])
				return false
	if visible_meshes < 8:
		_fail("The actual flying aircraft has too few visible model meshes.")
		return false
	_clear_toasts(app)
	return true

func _scroll_parent(node: Node) -> ScrollContainer:
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor
		ancestor = ancestor.get_parent()
	return null

func _clear_toasts(app) -> void:
	app.hud._pending_notices.clear()
	app.hud._toast_panel.hide()
	app.hud._toast_timer.stop()

func _inside_visible_scroll(control: Control, view: Rect2) -> bool:
	if not control.is_visible_in_tree():
		return false
	var visible_rect: Rect2 = view
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect.encloses(control.get_global_rect())

func _sampled_colors(image_value: Image) -> int:
	var shades: Dictionary = {}
	for y: int in range(16):
		for x: int in range(16):
			var pixel: Color = image_value.get_pixel(floori(float((x * 2 + 1) * image_value.get_width()) / 32.0), floori(float((y * 2 + 1) * image_value.get_height()) / 32.0))
			shades[pixel.to_html(false)] = true
	return shades.size()
