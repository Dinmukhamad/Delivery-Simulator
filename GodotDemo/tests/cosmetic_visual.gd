extends SceneTree

# Render real production cosmetics, models and purchase/equip controls.
# Only starting Money/XP and the initial location are test fixtures.
# Purchase/equip and garage placement go through Main; test-mode never writes
# the user's career profile. Player physics stay active for the SpringArm.
func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	printerr("COSMETIC_VISUAL: " + message)
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("Cosmetic captures require --test-mode.")
		quit(2)
		return
	var capture: String = ""
	var width: int = 1280
	var screen: String = "customization"
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--screen="):
			screen = arg.trim_prefix("--screen=")
	if capture.is_empty() or width not in [960, 1280] or screen not in ["customization", "garage", "game"]:
		printerr("Use --capture=PATH --width=960|1280 --screen=customization|garage|game.")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(width, width * 9 / 16))
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.set_process(false)
	app.set_process_input(false)
	app.player.set_controls_enabled(false)
	app.player.set_mouse_captured(false)
	app.profile["money"] = 60000
	app.profile["xp"] = 4000
	app.profile["level"] = app._level_for_xp(4000)
	app.profile["rank"] = app._rank_for_level(int(app.profile["level"]))
	app._open_customization()
	# These are real catalog items and real currency deductions, not UI-only
	# owned/selected fixtures or forged network snapshots.
	for choice: Array in [["outfit", "night", 1500], ["backpack", "rolltop", 750], ["vehicle_paint", "plum", 750]]:
		var before: int = int(app.profile["money"])
		app._buy_cosmetic(str(choice[0]), str(choice[1]))
		if int(app.profile["money"]) != before - int(choice[2]):
			_fail("Production purchase did not debit the catalog price for %s." % str(choice[1]))
			return
		if not app.profile.get("owned_cosmetics", []).has("%s:%s" % [choice[0], choice[1]]):
			_fail("Production purchase did not retain cosmetic ownership.")
			return
		app._select_cosmetic(str(choice[0]), str(choice[1]))
		if str(app.profile.get("appearance", {}).get(choice[0], "")) != str(choice[1]):
			_fail("Production equip did not retain the selected cosmetic.")
			return
	if int(app.profile["money"]) != 57000:
		_fail("Cosmetic purchases changed money beyond their catalog prices.")
		return
	app._select_cosmetic("outfit", "mint")
	if str(app.profile.get("appearance", {}).get("outfit", "")) != "mint" or int(app.profile["money"]) != 57000:
		_fail("A free appearance selection incorrectly charged money or failed.")
		return
	app._select_cosmetic("outfit", "night")
	if app.player.has_method("get_appearance") and app.player.get_appearance() != app.profile["appearance"]:
		_fail("The production courier did not apply its equipped profile.")
		return
	if screen != "customization":
		app._close_customization()
		app._play_solo()
		app._close_modal()
		app.player.reset_at(Vector3(-66.0, 0.15, 10.0))
		app.player.set_view_direction(PI)
		app.player.set_controls_enabled(false)
		app.player.set_mouse_captured(false)
		app._open_garage()
		app._buy_vehicle("car")
		if not app.profile.get("owned_vehicles", []).has("car") or not app.vehicles.has(app._local_vehicle_owner()):
			_fail("The production garage failed to buy and place the car.")
			return
		if int(app.profile["money"]) != 42000:
			_fail("The garage purchase did not preserve cosmetic spending.")
			return
		var vehicle = app.vehicles[app._local_vehicle_owner()]
		if vehicle.has_method("get_appearance") and vehicle.get_appearance() != app.profile["appearance"]:
			_fail("The real car did not apply the profile's selected appearance.")
			return
		if screen == "game":
			app._close_modal()
	_clear_toasts(app)
	for i: int in range(8):
		await process_frame
		if screen != "customization":
			app._update_hud()
	var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
	if screen == "customization":
		var customization_ok: bool = await _check_customization(app, view, width)
		if not customization_ok:
			return
	elif screen == "garage":
		if not _check_garage(app, view):
			return
	var ready_at: int = Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < ready_at:
		await process_frame
		if screen != "customization":
			app._update_hud()
	if screen == "game":
		var camera_distance: float = app.player.camera.global_position.distance_to(app.player.global_position)
		if not app.player.camera.is_current() or camera_distance < 2.0 or camera_distance > 7.0:
			_fail("The real third-person SpringArm camera did not settle.")
			return
		var car = app.vehicles[app._local_vehicle_owner()]
		var car_center: Vector3 = car.global_position + Vector3(0.0, 0.6, 0.0)
		if app.player.camera.is_position_behind(car_center) or not view.has_point(app.player.camera.unproject_position(car_center)):
			_fail("The painted production car is outside the gameplay capture.")
			return
		if not app.hud._game.is_visible_in_tree():
			_fail("The gameplay HUD is not visible.")
			return
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	if rendered.is_empty() or rendered.get_width() != width or rendered.get_height() != width * 9 / 16:
		_fail("Rendered capture has an unexpected size.")
		return
	if _sampled_colors(rendered) < 24:
		_fail("The capture contains too little actual rendered detail.")
		return
	if rendered.save_png(capture) != OK:
		_fail("Could not save the rendered customization capture.")
		return
	print("COSMETIC_VISUAL: %s rendered at %dx%d; real purchases/equip, appearance models and visible actions verified" % [screen, rendered.get_width(), rendered.get_height()])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)

func _check_customization(app, view: Rect2, width: int) -> bool:
	var panel: Control = app.hud.find_child("CosmeticCustomization", true, false)
	var close: Button = app.hud.find_child("CosmeticClose", true, false)
	var preview: SubViewportContainer = app.hud.find_child("CosmeticPreview", true, false)
	var viewport: SubViewport = app.hud.find_child("CosmeticPreviewViewport", true, false)
	var scroll: ScrollContainer = app.hud.find_child("CosmeticItemsScroll", true, false)
	if panel == null or not panel.is_visible_in_tree() or close == null or not _inside_visible_scroll(close, view):
		_fail("The customization window or close action is absent/clipped.")
		return false
	if preview == null or viewport == null or scroll == null or not _inside_visible_scroll(preview, view):
		_fail("The real character preview or item scroll area is absent/clipped.")
		return false
	if preview.get_global_rect().intersects(scroll.get_global_rect()):
		_fail("The real 3D preview overlaps the cosmetic item list.")
		return false
	for category: String in ["outfit", "backpack", "vehicle_paint"]:
		var tab: Button = app.hud.find_child("CosmeticTab_" + category, true, false)
		if tab == null or not _inside_visible_scroll(tab, view) or tab.disabled:
			_fail("A customization category cannot be reached in the visible window.")
			return false
		app.hud._select_customization_category(category)
		for i: int in range(4):
			await process_frame
		var actions: Array[Node] = []
		_collect_named(scroll, "CosmeticAction_", actions)
		if actions.is_empty():
			_fail("A category has no actual purchase/equip controls.")
			return false
		for action: Node in actions:
			if not action is Button:
				continue
			var button: Button = action
			scroll.ensure_control_visible(button)
			for i: int in range(3):
				await process_frame
			if not _inside_visible_scroll(button, view) or not _inside_visible_scroll(close, view) or not _inside_visible_scroll(tab, view):
				_fail("Scrolling a category cannot reveal its action while preserving close/tabs.")
				return false
	# Finish on clothing at 1280 and backpack at 960 to capture both actual
	# model changes; showing a candidate never purchases or equips it.
	var final_category: String = "outfit" if width == 1280 else "backpack"
	var final_id: String = "night" if width == 1280 else "rolltop"
	var before: Dictionary = app.profile.duplicate(true)
	app.hud._select_customization_category(final_category)
	app.hud._preview_cosmetic(final_category, final_id)
	if app.profile != before:
		_fail("Previewing a cosmetic modified the career profile.")
		return false
	for i: int in range(5):
		await process_frame
	var selected_action: Button = app.hud.find_child("CosmeticAction_" + final_id, true, false)
	if selected_action == null:
		_fail("The owned, selected item has no action/status control.")
		return false
	scroll.ensure_control_visible(selected_action)
	for i: int in range(5):
		await process_frame
	if not _inside_visible_scroll(selected_action, view):
		_fail("The selected appearance's control is outside the visible scroll area.")
		return false
	var courier: Node = preview.find_child("PreviewCourier", true, false)
	if courier == null or not courier.has_method("apply_appearance"):
		_fail("Preview does not contain the actual production courier model.")
		return false
	var profile_before_rotation: Dictionary = app.profile.duplicate(true)
	preview.rotate_model(0.35)
	if app.profile != profile_before_rotation:
		_fail("Rotating the real preview modified purchases or equipped cosmetics.")
		return false
	await RenderingServer.frame_post_draw
	var portrait: Image = viewport.get_texture().get_image()
	if portrait.is_empty() or portrait.get_width() < 128 or portrait.get_height() < 128 or _sampled_colors(portrait) < 8:
		_fail("The real 3D preview is blank or too small.")
		return false
	return true

func _check_garage(app, view: Rect2) -> bool:
	if not app.hud._garage.is_visible_in_tree():
		_fail("The real garage window is not visible.")
		return false
	var visible_close: bool = false
	var visible_customization: bool = false
	var nodes: Array[Node] = []
	_collect_buttons(app.hud._garage, nodes)
	for node: Node in nodes:
		var button: Button = node
		if button.text.contains("Закрыть") and _inside_visible_scroll(button, view):
			visible_close = true
		if str(button.name) == "OpenCustomizationGarage":
			if not button.disabled and _inside_visible_scroll(button, view):
				visible_customization = true
	if not visible_close or not visible_customization:
		_fail("The garage's close/customization entry is clipped or disabled.")
		return false
	if not app.hud._garage_profile.text.contains("42"):
		_fail("The garage balance does not reflect actual cosmetic and car purchases.")
		return false
	return true

func _collect_named(node: Node, prefix: String, result: Array[Node]) -> void:
	for child: Node in node.get_children():
		if str(child.name).begins_with(prefix):
			result.append(child)
		_collect_named(child, prefix, result)

func _collect_buttons(node: Node, result: Array[Node]) -> void:
	for child: Node in node.get_children():
		if child is Button:
			result.append(child)
		_collect_buttons(child, result)

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
