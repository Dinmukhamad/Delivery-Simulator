extends SceneTree

# Render the production console over the real menu/game, starting with the
# default test-mode career. Enter and Apply grant Money/XP through HUD signals;
# no profile JSON, fabricated rewards or UI-only balances are used.
# Only the gameplay location and frozen visual clock are capture fixtures.
# Player physics stay active so the real SpringArm camera can settle.
const CODES: Array[String] = ["MONEY10000", "MONEY50000", "XP1000", "LEVELUP", "DELIVERYMASTER", "ALLVEHICLES"]
var _submitted_codes: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	printerr("CHEAT_VISUAL: " + message)
	quit(1)

func _track_code(code: String) -> void:
	_submitted_codes.append(code.strip_edges().to_upper())

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("CHEAT_VISUAL: captures require --test-mode.")
		quit(2)
		return
	var capture: String = ""
	var width: int = 1280
	var screen: String = "menu"
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--screen="):
			screen = arg.trim_prefix("--screen=")
	if capture.is_empty() or width not in [960, 1280] or screen not in ["menu", "game"]:
		printerr("CHEAT_VISUAL: use --capture=PATH --width=960|1280 --screen=menu|game.")
		quit(2)
		return
	var height: int = width * 9 / 16
	DisplayServer.window_set_size(Vector2i(width, height))
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.set_process(false)
	if not app.test_mode or int(app.profile.get("money", -1)) != 0 or int(app.profile.get("xp", -1)) != 0 or int(app.profile.get("level", -1)) != 1:
		_fail("The isolated capture did not start with the default 0 Money/XP, level 1 career.")
		return
	if screen == "game":
		app._play_solo()
		app._close_modal()
		app.player.reset_at(Vector3(-66.0, 0.15, 10.0))
		app.player.set_view_direction(PI)
	app.player.set_controls_enabled(false)
	app.player.set_mouse_captured(false)
	var before: Dictionary = app.profile.duplicate(true)
	var shift_before: Dictionary = app.shift_stats.duplicate(true)
	app.hud.cheat_code_requested.connect(_track_code)
	if screen == "menu":
		var menu_button: Button = app.hud.find_child("OpenCheatsMenu", true, false)
		if menu_button == null or menu_button.disabled or not menu_button.is_visible_in_tree():
			_fail("The real main menu has no available cheat entry.")
			return
		menu_button.pressed.emit()
	else:
		# Send a genuine physical-key event through Godot's input dispatch.
		var open_key: InputEventKey = InputEventKey.new()
		open_key.physical_keycode = KEY_F2
		open_key.keycode = KEY_F2
		open_key.pressed = true
		Input.parse_input_event(open_key)
		await process_frame
		open_key = InputEventKey.new()
		open_key.physical_keycode = KEY_F2
		open_key.keycode = KEY_F2
		open_key.pressed = false
		Input.parse_input_event(open_key)
	for i: int in range(4):
		await process_frame
	var input: LineEdit = app.hud.find_child("CheatCodeInput", true, false)
	var apply: Button = app.hud.find_child("CheatApply", true, false)
	var notice: Label = app.hud.find_child("CheatNotice", true, false)
	if app.modal != "cheats" or input == null or apply == null or notice == null or not input.is_visible_in_tree():
		_fail("The production menu/F2 entry did not open the real console.")
		return
	if not input.has_focus():
		_fail("Opening the real console did not focus its code input.")
		return
	# Enter submits exactly one code, including real trim/case normalization.
	input.text = "  money10000  "
	input.text_submitted.emit(input.text)
	await process_frame
	if _submitted_codes != ["MONEY10000"] or int(app.profile.get("money", -1)) != 10000:
		_fail("Enter did not apply MONEY10000 exactly once through the real form.")
		return
	if input.text != "  money10000  " or notice.text.strip_edges().is_empty():
		_fail("A successful Enter did not preserve its editable code and show a response.")
		return
	# The other user-facing submit action uses the same production path.
	input.text = "levelup"
	apply.pressed.emit()
	await process_frame
	if _submitted_codes != ["MONEY10000", "LEVELUP"] or int(app.profile.get("money", -1)) != 10000 or int(app.profile.get("xp", -1)) != 150 or int(app.profile.get("level", -1)) != 2:
		_fail("Apply did not grant the next real XP threshold exactly once.")
		return
	for key: Variant in before:
		if str(key) not in ["money", "xp", "level", "rank"] and app.profile.get(key) != before[key]:
			_fail("The real cheat form altered non-career-grant data: %s." % str(key))
			return
	if app.shift_stats != shift_before:
		_fail("The form counted a cheat as shift earnings or delivery statistics.")
		return
	if input.text != "levelup" or notice.text.strip_edges().is_empty():
		_fail("A successful Apply did not retain its editable code and console response.")
		return
	if screen == "game":
		app._update_hud()
		if int(app.hud._last_data.get("money", -1)) != 10000 or int(app.hud._last_data.get("level", -1)) != 2:
			_fail("The production gameplay HUD did not receive the granted profile.")
			return
	app.set_process_input(false)
	app.player.set_controls_enabled(false)
	app.player.set_mouse_captured(false)
	_clear_toasts(app)
	var ready_at: int = Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < ready_at:
		await process_frame
		if screen == "game":
			app._update_hud()
	var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
	if not _check_console(app, view):
		return
	if screen == "game":
		var camera_distance: float = app.player.camera.global_position.distance_to(app.player.global_position)
		if not app.player.camera.is_current() or camera_distance < 2.0 or camera_distance > 7.0:
			_fail("The actual gameplay SpringArm camera did not settle.")
			return
		if not app.hud._game.is_visible_in_tree():
			_fail("The console capture lost the real gameplay HUD.")
			return
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	if rendered.is_empty() or rendered.get_width() != width or rendered.get_height() != height:
		_fail("The actual console render has an unexpected size.")
		return
	if _sampled_colors(rendered) < 24:
		_fail("The console capture contains too little actual rendered detail.")
		return
	if rendered.save_png(capture) != OK:
		_fail("Could not save the actual console render.")
		return
	print("CHEAT_VISUAL: %s rendered at %dx%d; real Enter/Apply, live 10000 Money/150 XP/level 2, all six codes and visible controls verified" % [screen, width, height])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)

func _check_console(app, view: Rect2) -> bool:
	var panel: Control = app.hud.find_child("CheatConsole", true, false)
	if panel == null or not _inside_visible_scroll(panel, view):
		_fail("The real console panel is absent or clipped.")
		return false
	for node_name: String in ["CheatCodeInput", "CheatApply", "CheatClose", "CheatHelp", "CheatProfile", "CheatNotice"]:
		var control: Control = app.hud.find_child(node_name, true, false)
		if control == null or not _inside_visible_scroll(control, view) or not panel.get_global_rect().encloses(control.get_global_rect()):
			_fail("A console control or help/profile response is clipped: %s." % node_name)
			return false
		if control is Button and control.disabled:
			_fail("A visible console action is disabled: %s." % node_name)
			return false
	for label: Label in panel.find_children("*", "Label", true, false):
		if not _inside_visible_scroll(label, view):
			_fail("A console instruction, profile or response is outside the visible panel.")
			return false
	var help: Label = app.hud.find_child("CheatHelp", true, false)
	for code: String in CODES:
		if not help.text.contains(code):
			_fail("The visible production help omits code %s." % code)
			return false
	var profile: Label = app.hud.find_child("CheatProfile", true, false)
	var profile_text: String = profile.text.replace(" ", "").replace("\u00a0", "").replace("\u202f", "")
	if not profile_text.contains("10000") or not profile_text.contains("150") or not profile_text.contains("2"):
		_fail("The visible console profile did not update its actual Money/XP/level.")
		return false
	var input: LineEdit = app.hud.find_child("CheatCodeInput", true, false)
	var apply: Button = app.hud.find_child("CheatApply", true, false)
	if input.get_global_rect().intersects(apply.get_global_rect()):
		_fail("The console input overlaps Apply.")
		return false
	return true

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
