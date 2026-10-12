extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--test-mode"):
		printerr("Visual checks require --test-mode.")
		quit(2)
		return
	var capture: String = ""
	var width: int = 1280
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		if arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
	if capture.is_empty():
		quit(2)
		return
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	DisplayServer.window_set_size(Vector2i(width, width * 9 / 16))
	app._play_solo()
	app._close_modal()
	app._accept_order(int(app.orders[0]["id"]))
	app.player.global_position = app._target_position() + Vector3.UP * 0.15
	await physics_frame
	await process_frame
	app._interact()
	if app.active_order.get("state") != "PickedUp":
		printerr("Visual fixture could not pick up its parcel.")
		quit(1)
		return
	app.player.global_position = Vector3(-66, 0.15, -32)
	var ready_at: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < ready_at:
		await process_frame
	app._open_map()
	for i: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.is_empty() or image.get_width() != width:
		printerr("Unexpected rendered image size.")
		quit(1)
		return
	if not app.hud._map.visible or app.hud._full_map.route_points.size() < 3:
		printerr("Large map has no routed detour.")
		quit(1)
		return
	if image.save_png(capture) != OK:
		quit(1)
		return
	print("NAVIGATION_IMAGE_BASE64 " + JSON.stringify({"width": width, "png": Marshalls.raw_to_base64(image.save_png_to_buffer())}))
	print("NAVIGATION_VISUAL: map and route rendered at %dx%d" % [image.get_width(), image.get_height()])
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)
