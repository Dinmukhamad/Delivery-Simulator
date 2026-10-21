extends SceneTree

# Renders production HUD with explicit UI fixtures. Network authority is tested
# separately in team_shift.gd and lan_team_peer.gd; no LAN session is forged here.
func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	printerr("TEAM_VISUAL: " + message)
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("Visual checks require --test-mode.")
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
	if capture.is_empty() or width not in [960, 1280] or screen not in ["game", "orders", "results"]:
		printerr("Use --capture=PATH --width=960|1280 --screen=game|orders|results.")
		quit(2)
		return
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	DisplayServer.window_set_size(Vector2i(width, width * 9 / 16))
	app._play_solo()
	app._close_modal()
	app.set_process(false)
	app.set_process_input(false)
	app.player.set_controls_enabled(false)
	app.player.set_mouse_captured(false)
	app.shift_remaining = 520.0
	app.profile["money"] = 1650
	app.profile["xp"] = 250
	app.profile["level"] = 2
	app.profile["rank"] = "City Courier"
	app.shift_stats["deliveries"] = 1
	var friend_position: Vector3 = app.city.spawn_position + Vector3(1.5, 0.0, 2.0)
	app._spawn_remote_player(2, "Айдар", friend_position, 1)
	app.remote_players[2].apply_network_pose({
		"position": friend_position, "yaw": PI, "velocity": Vector3.ZERO,
		"grounded": true, "carrying": true,
	})
	app._update_hud()
	app.hud._pending_notices.clear()
	app.hud._toast_panel.hide()
	app.hud._toast_timer.stop()
	app.hud.set_network_mode(true, true)
	var team: Dictionary = {
		"enabled": true, "target": 8, "delivered": 3, "completed": false,
		"bonus_money": 500, "bonus_xp": 100, "eligible": true,
		"bonus_awarded": false, "contributions": 1,
	}
	var data: Dictionary = app.hud._last_data.duplicate(true)
	data["local_id"] = 1
	data["team"] = team
	data["has_target"] = false
	data["order_state"] = ""
	data["interaction"] = "Друг предлагает посылку · Tab — ответить"
	data["handoff_candidates"] = []
	data["handoffs"] = {
		"incoming": [{
			"offer_id": 31, "sender_id": 2, "name": "Айдар", "order_id": 5,
			"title": "Кофе для офиса", "remaining": 8.0,
		}],
		"outgoing": {},
	}
	app.hud.show_game()
	app.hud.update_hud(data)
	for i: int in range(5):
		await process_frame
	if not app.hud._team_panel.visible or app.hud._team_progress.text != "КОМАНДА · 3 / 8":
		_fail("The shared delivery plan is absent from the game HUD.")
		return
	if not app.hud._team_message.text.contains("Tab"):
		_fail("The incoming parcel has no visible response prompt.")
		return
	# Countdown snapshots must preserve the actual consent button and its focus.
	if app.hud._handoff_timers.size() != 1:
		_fail("The incoming offer did not create consent controls.")
		return
	var timer_entry: Dictionary = app.hud._handoff_timers[0]
	var accept: Button = timer_entry["buttons"][0]
	var decline: Button = timer_entry["buttons"][1]
	var countdown: Label = timer_entry["label"]
	data["handoffs"]["incoming"][0]["remaining"] = 7.0
	app.hud.update_hud(data)
	if app.hud._handoff_timers[0]["buttons"][0] != accept or app.hud._handoff_timers[0]["label"] != countdown or countdown.text != "Ответьте за 7 с":
		_fail("A countdown snapshot replaced consent controls or left a stale timer.")
		return
	if screen == "orders":
		app.hud.show_orders(true)
		for i: int in range(5):
			await process_frame
		if not app.hud._orders.visible or not app.hud._handoff_panel.is_visible_in_tree() or accept.disabled or decline.disabled:
			_fail("The parcel acceptance panel is not usable.")
			return
		var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
		var accept_rect: Rect2 = accept.get_global_rect()
		var decline_rect: Rect2 = decline.get_global_rect()
		if not view.encloses(accept_rect) or not view.encloses(decline_rect):
			_fail("Consent buttons are outside the visible viewport.")
			return
		accept.grab_focus()
		data["handoffs"]["incoming"][0]["remaining"] = 6.0
		app.hud.update_hud(data)
		if not accept.has_focus() or app.hud._handoff_timers[0]["buttons"][0] != accept:
			_fail("Keyboard focus was lost when the offer timer changed.")
			return
		var emitted: Array[Vector2i] = []
		app.hud.handoff_accept_requested.connect(func(sender_id: int, offer_id: int) -> void:
			emitted.append(Vector2i(sender_id, offer_id)))
		accept.pressed.emit()
		if emitted != [Vector2i(2, 31)]:
			_fail("The consent button did not identify the displayed offer.")
			return
	elif screen == "results":
		team = team.duplicate(true)
		team["delivered"] = 8
		team["completed"] = true
		team["contributions"] = 3
		team["bonus_awarded"] = true
		app.hud.show_results({
			"deliveries": 3, "money": 1650, "xp": 250, "best_delivery": 430,
			"time_used": 900.0, "team_bonus_money": 500, "team_bonus_xp": 100,
			"team": team,
		}, [
			{"name": "Айдар", "deliveries": 5, "money": 2180, "xp": 350, "best_delivery": 480, "connected": true},
			{"name": "Вы", "deliveries": 3, "money": 1650, "xp": 250, "best_delivery": 430, "connected": true},
		])
		for i: int in range(5):
			await process_frame
		if not app.hud._results_team.is_visible_in_tree() or not app.hud._results_team_text.text.contains("8 / 8") or not app.hud._results_team_text.text.contains("+500"):
			_fail("Results omit the completed team plan or the confirmed bonus.")
			return
		if not app.hud._results_team_text.text.contains("уже включён"):
			_fail("Results do not explain that the bonus is included in personal totals.")
			return
		if width == 1280:
			for action: Node in app.hud._results_restart.get_parent().get_children():
				if not action is Button:
					continue
				var button: Button = action
				if not _inside_visible_scroll(button, Rect2(Vector2.ZERO, app.hud._root.size)):
					_fail("Results actions are clipped at the standard desktop resolution.")
					return
	else:
		var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
		if not view.encloses(app.hud._team_panel.get_global_rect()):
			_fail("The shared delivery plan is outside the visible viewport.")
			return
	var ready_at: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < ready_at:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.is_empty() or image.get_width() != width or image.get_height() != width * 9 / 16:
		_fail("Unexpected rendered image size.")
		return
	if image.save_png(capture) != OK:
		_fail("Could not write the rendered capture.")
		return
	print("TEAM_VISUAL: %s rendered at %dx%d; shared plan and consent UI checked" % [screen, image.get_width(), image.get_height()])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)

func _inside_visible_scroll(control: Control, viewport_rect: Rect2) -> bool:
	var visible_rect: Rect2 = viewport_rect
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect.encloses(control.get_global_rect())
