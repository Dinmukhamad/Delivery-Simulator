extends SceneTree

# Captures the production world and HUD. A map capture uses a test delivery
# between real city endpoints; network authority is checked in the LAN tests.
func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	printerr("CITY_VISUAL: " + message)
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("City captures require --test-mode.")
		quit(2)
		return
	var capture: String = ""
	var width: int = 1280
	var district: String = "business"
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--district="):
			district = arg.trim_prefix("--district=")
	if capture.is_empty() or width not in [960, 1280] or district not in ["business", "residential", "industrial", "park", "street", "map"]:
		printerr("Use --capture=PATH --width=960|1280 --district=business|residential|industrial|park|street|map.")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(width, width * 9 / 16))
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app._play_solo()
	app._close_modal()
	app.set_process(false)
	app.set_process_input(false)
	app.player.set_controls_enabled(false)
	app.player.set_mouse_captured(false)
	app.player.process_mode = Node.PROCESS_MODE_DISABLED
	app.shift_remaining = 520.0
	app.profile["money"] = 1650
	app.profile["xp"] = 250
	app.profile["level"] = 2
	app.profile["rank"] = "City Courier"
	app._update_hud()
	app.hud._pending_notices.clear()
	app.hud._toast_panel.hide()
	app.hud._toast_timer.stop()
	app.city.clear_objective()
	var layout: Dictionary = app.city.get_map_layout()
	var bounds: Rect2 = layout.get("bounds", Rect2())
	if bounds != Rect2(-258.0, -258.0, 516.0, 516.0) or layout.get("districts", []).size() < 6:
		_fail("The render is not using the expanded production city.")
		return
	if district == "map":
		if not _set_map_delivery(app):
			return
		app._open_map()
	else:
		if not _set_district_camera(app, district):
			return
	for i: int in range(6):
		await process_frame
	if district == "map":
		if not _check_map(app, bounds):
			return
	var ready_at: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < ready_at:
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	if rendered.is_empty() or rendered.get_width() != width or rendered.get_height() != width * 9 / 16:
		_fail("Rendered image has an unexpected size.")
		return
	var shades: Dictionary = {}
	for y: int in range(16):
		for x: int in range(16):
			var pixel: Color = rendered.get_pixel(floori(float((x * 2 + 1) * width) / 32.0), floori(float((y * 2 + 1) * rendered.get_height()) / 32.0))
			shades[pixel.to_html(false)] = true
	if shades.size() < 20:
		_fail("Capture contains too little rendered scene detail.")
		return
	if rendered.save_png(capture) != OK:
		_fail("Could not save the production capture.")
		return
	print("CITY_VISUAL: %s rendered at %dx%d; production geometry and city extent verified" % [district, rendered.get_width(), rendered.get_height()])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)

func _set_district_camera(app, district: String) -> bool:
	if not app.city.has_method("get_city_showcases"):
		_fail("Production city does not expose district capture locations.")
		return false
	var selected: Dictionary = {}
	for value: Dictionary in app.city.get_city_showcases():
		if str(value.get("id", "")) == district:
			selected = value
			break
	if selected.is_empty() or not selected.get("focus") is Vector3 or not selected.get("camera") is Vector3:
		_fail("Missing production camera location for %s." % district)
		return false
	var focus: Vector3 = selected["focus"]
	var location: Vector3 = selected["camera"]
	var bounds: Rect2 = app.city.get_map_layout()["bounds"]
	if not focus.is_finite() or not location.is_finite() or not bounds.has_point(Vector2(focus.x, focus.z)):
		_fail("Invalid district showcase coordinates.")
		return false
	app.player.camera.current = false
	if district == "street":
		app.player.reset_at(Vector3(focus.x, 0.15, focus.z))
		app.player.set_view_direction(PI)
	else:
		app.player.hide()
		app.hud._game.hide()
	var camera: Camera3D = Camera3D.new()
	camera.name = "CityCaptureCamera"
	camera.near = 0.1
	camera.far = 800.0
	camera.fov = 65.0
	app.add_child(camera)
	camera.global_position = location
	camera.look_at(focus)
	camera.make_current()
	return true

func _set_map_delivery(app) -> bool:
	var pickup: Dictionary = app.city.pickup_points[0]
	var destination: Dictionary = {}
	var furthest: float = -1.0
	for point: Dictionary in app.city.delivery_points:
		var distance: float = app.player.global_position.distance_to(point["position"])
		if distance > furthest:
			furthest = distance
			destination = point
	if destination.is_empty() or furthest < 200.0:
		_fail("Map has no real distant destination in the new neighborhoods.")
		return false
	app.active_order = {
		"id": 90001, "state": "PickedUp", "type": "standard", "type_name": "Обычная доставка",
		"title": "%s → %s" % [pickup["name"], destination["name"]],
		"pickup_name": pickup["name"], "pickup_position": pickup["position"],
		"delivery_name": destination["name"], "delivery_position": destination["position"],
		"reward": 650, "xp": 50, "time_limit": 0.0, "remaining": 0.0,
	}
	app.player.set_carrying(true)
	app._update_hud()
	var route: Dictionary = app.hud._last_data.get("navigation", {})
	if route.get("points", []).size() < 3 or float(route.get("distance", 0.0)) <= furthest:
		_fail("Map capture is missing a real street/path route to the distant destination.")
		return false
	return true

func _check_map(app, bounds: Rect2) -> bool:
	if not app.hud._map.visible or not app.hud._full_map.is_visible_in_tree():
		_fail("M map is not visible.")
		return false
	if app.hud._full_map._view_bounds() != bounds or app.hud._full_map.layout.get("buildings", []).size() < 80:
		_fail("M map omits expanded districts or building footprints.")
		return false
	if app.hud._mini_map._view_bounds().size != Vector2(128.0, 128.0):
		_fail("Minimap has lost its readable neighborhood scale.")
		return false
	var map_area: Rect2 = app.hud._full_map._map_rect()
	var visible_area: Rect2 = Rect2(app.hud._full_map.global_position + map_area.position, map_area.size)
	var viewport_area: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
	if not _inside_visible_scroll(app.hud._full_map, visible_area, viewport_area):
		_fail("The entire city map is not initially visible at this desktop resolution.")
		return false
	var has_close_button: bool = false
	var pending: Array[Node] = [app.hud._map]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Button:
			var button: Button = node
			if not button.is_visible_in_tree() or not button.text.contains("Закрыть"):
				continue
			var button_rect: Rect2 = button.get_global_rect()
			if _inside_visible_scroll(button, button_rect, viewport_area):
				has_close_button = true
	if not has_close_button:
		_fail("The map's close action is clipped or absent.")
		return false
	return true

func _inside_visible_scroll(control: Control, target_rect: Rect2, viewport_rect: Rect2) -> bool:
	var visible_rect: Rect2 = viewport_rect
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect.encloses(target_rect)
