extends SceneTree

# Render actual production event orders and HUD in isolated test mode.
# Only the visual clock and player location are advanced by the fixture.
# Controls stay disabled while physics/SpringArm run to settle the real camera.
# Reward authority, timing boundaries and LAN ownership have separate tests.
func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	printerr("DISTRICT_EVENT_VISUAL: " + message)
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("Event captures require --test-mode.")
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
	if capture.is_empty() or width not in [960, 1280] or screen not in ["game", "orders", "map"]:
		printerr("Use --capture=PATH --width=960|1280 --screen=game|orders|map.")
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
	# This calls the same generation/update path as a Solo game, without
	# fabricating event metadata or inserting a synthetic delivery.
	app._solo_elapsed_seconds = 50.0
	app.shift_remaining = 850.0
	app._advance_solo_event()
	var event: Dictionary = app._district_event_view()
	if str(event.get("phase", "")) != "active" or str(event.get("district_id", "")) != "business":
		_fail("The production clock did not start Lunch Rush in the business district.")
		return
	var event_order: Dictionary = {}
	var event_count: int = 0
	var normal_count: int = 0
	for order: Dictionary in app.orders:
		if str(order.get("event_id", "")).is_empty():
			normal_count += 1
		else:
			event_count += 1
			if event_order.is_empty() or str(order.get("title", "")).length() > str(event_order.get("title", "")).length():
				event_order = order
	if event_count != 3 or normal_count != 6 or event_order.is_empty():
		_fail("Lunch Rush must add three real offers while keeping six normal orders.")
		return
	if not _real_city_order(app, event_order):
		return
	if screen != "orders":
		app._accept_order(int(event_order["id"]))
		app._close_modal()
		if int(app.active_order.get("id", -1)) != int(event_order["id"]):
			_fail("The production order-accept path did not preserve the event order.")
			return
		if screen == "map":
			# A carry-state fixture displays delivery guidance. Pickup validation
			# is checked separately; the actual production order and deadline stay.
			app.active_order["state"] = "PickedUp"
			app.player.set_carrying(true)
		app.player.reset_at(Vector3(-160.0, 0.15, -54.0))
		app.player.set_view_direction(PI)
		app.player.set_controls_enabled(false)
		app.player.set_mouse_captured(false)
		app._update_hud()
	else:
		app._update_hud()
	app.hud._pending_notices.clear()
	app.hud._toast_panel.hide()
	app.hud._toast_timer.stop()
	if screen == "orders":
		app._open_orders()
	elif screen == "map":
		app._open_map()
	for i: int in range(6):
		await process_frame
		app._update_hud()
	var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
	if not app.hud._event_panel.is_visible_in_tree() or not _inside_visible_scroll(app.hud._event_panel, view):
		_fail("The event banner is outside the visible game viewport.")
		return
	if not app.hud._event_title.text.contains("Обеденный час") or not app.hud._event_title.text.contains(":"):
		_fail("The event banner omits the event name or remaining time.")
		return
	if not app.hud._event_bonus.text.contains("50"):
		_fail("The event banner omits the on-time reward increase.")
		return
	if screen == "orders":
		if not _check_orders(app, view, event_order):
			return
	elif screen == "map":
		if not _check_map(app, view):
			return
	else:
		if not app.hud._order_event_hint.is_visible_in_tree() or not _inside_visible_scroll(app.hud._order_event_hint, view):
			_fail("The accepted event order has no visible deadline/bonus hint.")
			return
		if not app.hud._order_event_hint.text.contains("Обеденный") or not app.hud._order_event_hint.text.contains("+"):
			_fail("The active order hint omits its event or extra payout.")
			return
		var active_rect: Rect2 = app.hud._active_order_panel.get_global_rect()
		if not view.encloses(active_rect) or active_rect.intersects(app.hud._event_panel.get_global_rect()):
			_fail("The active order and event banner overlap or leave the viewport.")
			return
		for summary: Control in [app.hud._deliveries, app.hud._vehicle]:
			if not _inside_visible_scroll(summary, view) or active_rect.intersects(summary.get_global_rect()):
				_fail("The long event order clips or overlaps delivery/vehicle statistics.")
				return
	var ready_at: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < ready_at:
		await process_frame
		app._update_hud()
	if screen == "game":
		var guidance: Dictionary = app.hud._last_data.get("navigation", {})
		if str(guidance.get("status", "")) != "ok" or guidance.get("points", []).size() < 2:
			_fail("The event game capture has no completed production street route.")
			return
		var camera_distance: float = app.player.camera.global_position.distance_to(app.player.global_position)
		if not app.player.camera.is_current() or camera_distance < 2.0 or camera_distance > 7.0:
			_fail("The production third-person camera did not settle outside the courier model.")
			return
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
		_fail("Capture contains too little rendered detail.")
		return
	if rendered.save_png(capture) != OK:
		_fail("Could not save the production event capture.")
		return
	print("DISTRICT_EVENT_VISUAL: %s rendered at %dx%d; actual generated offers, countdown, bonus and visible actions verified" % [screen, rendered.get_width(), rendered.get_height()])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)

func _real_city_order(app, order: Dictionary) -> bool:
	var pickup_found: bool = false
	var destination_found: bool = false
	for point: Dictionary in app.city.pickup_points:
		if point["position"] == order.get("pickup_position") and str(point.get("district_id", "")) == "business":
			pickup_found = true
	for point: Dictionary in app.city.delivery_points:
		if point["position"] == order.get("delivery_position") and str(point.get("district_id", "")) == "business":
			destination_found = true
	if not pickup_found or not destination_found:
		_fail("Event route does not use real pickup/delivery addresses in the business district.")
		return false
	if str(order.get("event_id", "")) != "lunch_rush:1" or int(order.get("event_bonus_money", 0)) <= 0:
		_fail("Generated offer omits its event identity or extra payout.")
		return false
	return true

func _check_orders(app, view: Rect2, event_order: Dictionary) -> bool:
	if not app.hud._orders.visible or not app.hud._orders_event_panel.is_visible_in_tree():
		_fail("The orders window omits the district-event summary.")
		return false
	if not app.hud._orders_event_text.text.contains("Обеденный"):
		_fail("The orders summary does not identify Lunch Rush.")
		return false
	var visible_badge: bool = false
	var pending: Array[Node] = [app.hud._orders_list]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Label and bool(node.get_meta("district_event_badge", false)):
			var badge: Label = node
			if str(badge.get_meta("event_id", "")) == str(event_order["event_id"]) and _inside_visible_scroll(badge, view):
				visible_badge = true
	if not visible_badge:
		_fail("No generated event-order badge is visible without scrolling.")
		return false
	if not _has_visible_close(app.hud._orders, view):
		_fail("The orders close action is outside the visible viewport.")
		return false
	return true

func _check_map(app, view: Rect2) -> bool:
	if not app.hud._map.visible or not app.hud._full_map.is_visible_in_tree():
		_fail("The full map is not visible.")
		return false
	if not app.hud._map_event_label.is_visible_in_tree() or not app.hud._map_event_label.text.contains("Обеденный"):
		_fail("The map omits the active district event.")
		return false
	if str(app.hud._full_map.district_event.get("district_id", "")) != "business":
		_fail("The real full map does not highlight the active business district.")
		return false
	var area: Rect2 = app.hud._full_map._map_rect()
	if not _inside_rect_scroll(app.hud._full_map, Rect2(app.hud._full_map.global_position + area.position, area.size), view):
		_fail("The entire map is not initially visible.")
		return false
	if not _has_visible_close(app.hud._map, view):
		_fail("The map close action is outside the visible viewport.")
		return false
	var navigation: Dictionary = app.hud._last_data.get("navigation", {})
	if str(navigation.get("status", "")) != "ok" or navigation.get("points", []).size() < 2:
		_fail("The accepted event parcel has no real city route.")
		return false
	return true

func _has_visible_close(panel: Node, view: Rect2) -> bool:
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Button:
			var button: Button = node
			if button.text.contains("Закрыть") and _inside_visible_scroll(button, view):
				return true
	return false

func _inside_visible_scroll(control: Control, view: Rect2) -> bool:
	return _inside_rect_scroll(control, control.get_global_rect(), view)

func _inside_rect_scroll(control: Control, target_rect: Rect2, view: Rect2) -> bool:
	if not control.is_visible_in_tree():
		return false
	var visible_rect: Rect2 = view
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect.encloses(target_rect)
