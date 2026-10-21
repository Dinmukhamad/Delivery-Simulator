extends SceneTree

# The logical Host roster, level-eight careers and aligned airborne formation
# are explicit, test-only visual fixtures. Both aircraft purchases, shots,
# health changes and event rendering use production authority/game methods.
# Actual two-process networking is covered by lan_air_combat_peer.gd.
var app
var shot_events: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func fail(message: String) -> void:
	printerr("AIR_COMBAT_VISUAL: " + message)
	if is_instance_valid(app):
		app.lan_session.members.erase(2)
		app.queue_free()
	quit(1)

func forward_event(peer_id: int, event: Dictionary) -> void:
	if peer_id != 1:
		return
	if str(event.get("type", "")) == "aircraft_shot":
		shot_events.append(event.duplicate(true))
	app._on_lan_event(event)

func formation(peer_id: int, position: Vector3, yaw: float) -> void:
	var record: Dictionary = app.lan_authority.records[peer_id]
	var vehicle: Dictionary = record["vehicle"]
	vehicle["position"] = position
	vehicle["yaw"] = yaw
	vehicle["velocity"] = Vector3.ZERO
	vehicle["grounded"] = false
	vehicle["occupied"] = true
	record["position"] = position
	record["yaw"] = yaw
	record["velocity"] = Vector3.ZERO
	record["grounded"] = false
	app.lan_authority._advance_vehicle_generation(record)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var width: int = 1280
	var capture: String = ""
	for arg: String in args:
		if arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	if not args.has("--test-mode") or width not in [960, 1280] or capture.is_empty():
		printerr("AIR_COMBAT_VISUAL: use --test-mode --width=960|1280 --capture=PATH")
		quit(2)
		return
	var height: int = width * 9 / 16
	DisplayServer.window_set_size(Vector2i(width, height))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	if not app.test_mode or int(app.profile["money"]) != 0 or not app.profile["owned_vehicles"].is_empty():
		fail("Capture must begin with an isolated default career")
		return
	app.set_process(false)
	app.set_process_input(false)
	app.lan_authority.changed.disconnect(app._broadcast_lan_state)
	app.lan_authority.event_ready.disconnect(app._send_lan_event)
	app.lan_authority.pose_ready.disconnect(app._publish_lan_pose)
	app.lan_authority.event_ready.connect(forward_event)
	# No sockets or real peer are fabricated: only the visual Host's membership
	# context is a fixture, with RPC fan-out deliberately disconnected above.
	app.profile["money"] = 60000
	app.profile["xp"] = 7350
	app.profile["level"] = 8
	app.profile["rank"] = app._rank_for_level(8)
	app.profile["player_name"] = "Air Courier"
	var rival: Dictionary = app.profile.duplicate(true)
	rival["player_name"] = "Друг"
	var roster: Array = [
		{"id": 1, "name": "Air Courier", "profile": app.profile.duplicate(true)},
		{"id": 2, "name": "Друг", "profile": rival}
	]
	app.lan_session.role = "host"
	app.lan_session.phase = "playing"
	app.lan_session.local_id = 1
	app.lan_session.session_id = "guarded-air-combat-visual"
	app.lan_session.members = {1: roster[0].duplicate(true), 2: roster[1].duplicate(true)}
	var config: Dictionary = {"players": roster, "session_id": app.lan_session.session_id, "shift_seconds": 900, "shift_mode": "competitive"}
	app._on_lan_started(config)
	app._close_modal()
	for peer_id: int in [1, 2]:
		app.lan_authority.records[peer_id]["position"] = Vector3(-66.0, 0.15, 10.0) + Vector3(float(peer_id - 1) * 3.0, 0.0, 0.0)
		app.lan_authority.handle_request(peer_id, "vehicle_buy", {"type": "airplane"})
		if not app.lan_authority.records[peer_id]["profile"]["owned_vehicles"].has("airplane") or int(app.lan_authority.records[peer_id]["profile"]["money"]) != 30000:
			fail("Both fixture couriers must really buy their own aircraft")
			return
	formation(1, Vector3(0.0, 32.0, -18.0), PI)
	formation(2, Vector3(0.0, 32.0, 18.0), 0.0)
	app.lan_authority._mark_changed()
	app._on_lan_state(app.lan_authority.snapshot_for(1))
	app.player.correct_network_position(Vector3(0.0, 32.0, -18.0))
	app.player.set_view_direction(PI)
	app.player.set_mouse_captured(true)
	for vehicle in app.vehicles.values():
		vehicle.set_physics_process(false)
	for index: int in range(8):
		app.player._update_camera_distance(0.25)
		await physics_frame
		await process_frame
	if not app.player.is_riding() or app.vehicles.size() != 2:
		fail("The actual camera must follow a piloted plane opposite another real aircraft model")
		return
	# Two real authority requests damage each plane once. Capture the player's
	# own confirmed shot, while freezing only short-lived presentation effects.
	for peer_id: int in [2, 1]:
		var vehicle: Dictionary = app.lan_authority.records[peer_id]["vehicle"]
		app.lan_authority.handle_request(peer_id, "aircraft_fire", {"generation": int(vehicle["generation"])})
	app.combat_effects.set_process(false)
	app._on_lan_state(app.lan_authority.snapshot_for(1))
	app._update_hud()
	app.hud._pending_notices.clear()
	app.hud._toast_panel.hide()
	app.hud._toast_timer.stop()
	for index: int in range(4):
		await process_frame
		app._update_hud()
	var view: Rect2 = Rect2(Vector2.ZERO, app.hud._root.size)
	if shot_events.size() != 2 or int(shot_events[0].get("hit_id", 0)) != 1 or int(shot_events[1].get("hit_id", 0)) != 2 or app.player.riding_vehicle.combat_health != 75 or app.vehicles[2].combat_health != 75:
		fail("Both real shots must confirm the proper target and HP75")
		return
	for control: Control in [app.hud._air_combat_panel, app.hud._air_health, app.hud._air_health_bar, app.hud._air_score, app.hud._air_gun_hint, app.hud._air_crosshair, app.hud._interaction_panel, app.hud._keys]:
		if not control.is_visible_in_tree() or not view.encloses(control.get_global_rect()):
			fail("Actual combat HUD control is absent or clipped: " + str(control.name))
			return
	if not app.hud._air_health.text.contains("75") or not bool(app.hud._last_data.get("can_fire", false)) or not bool(app.hud._last_data.get("aim_visible", false)) or app.combat_effects.active_effect_count() < 1:
		fail("Capture must show confirmed health, live aim and actual shot effects")
		return
	var camera: Camera3D = app.player.camera
	for vehicle in app.vehicles.values():
		var center: Vector3 = vehicle.global_position + Vector3.UP
		if camera.is_position_behind(center) or not view.has_point(camera.unproject_position(center)):
			fail("Both real aircraft models must appear inside the camera view")
			return
	# A nearby aircraft on the actual firing ray must line up with the reticle,
	# despite the third-person camera being above and behind the gun muzzle.
	var opponent = app.vehicles[2]
	var definition: Dictionary = opponent.definition
	var extent: Vector3 = Vector3(float(definition["collision_width"]), float(definition["collision_height"]), float(definition["collision_length"]))
	var target_box: AABB = AABB(Vector3(-extent.x * 0.5, 0.0, -extent.z * 0.5), extent)
	var projected_min: Vector2 = Vector2(INF, INF)
	var projected_max: Vector2 = Vector2(-INF, -INF)
	for corner: int in range(8):
		var point: Vector3 = opponent.global_position + Basis(Vector3.UP, opponent.rotation.y) * target_box.get_endpoint(corner)
		var projected: Vector2 = camera.unproject_position(point)
		projected_min = projected_min.min(projected)
		projected_max = projected_max.max(projected)
	var aim: Vector2 = app.hud._last_data.get("aim_screen", Vector2.ZERO)
	if not Rect2(projected_min, projected_max - projected_min).grow(1.0).has_point(aim):
		fail("The live reticle misses the projected aircraft that the actual gun ray hits")
		return
	var visible_meshes: int = 0
	for mesh: MeshInstance3D in app.player.riding_vehicle.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		visible_meshes += 1
		for corner: int in range(8):
			var point: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
			if camera.is_position_behind(point) or not view.has_point(camera.unproject_position(point)):
				fail("A real aircraft wing, gun or body mesh is clipped: " + str(mesh.name))
				return
	if visible_meshes < 20:
		fail("The capture must contain the detailed production aircraft")
		return
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	if rendered.is_empty() or rendered.get_size() != Vector2i(width, height) or rendered.save_png(capture) != OK:
		fail("Could not save the actual combat viewport PNG")
		return
	print("AIR_COMBAT_VISUAL: %dx%d; two actual aircraft purchases, two authoritative hits, HP75, projected aim and full combat HUD verified; formation/roster are guarded visual fixtures" % [width, height])
	app.lan_session.members.erase(2)
	app._leave_lan()
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(0)
