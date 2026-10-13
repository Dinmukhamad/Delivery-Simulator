extends SceneTree

# Run two actual ENet processes, with a shared /tmp --coord directory:
# --test-mode --isolated-save --role=host|client --coord=/tmp/...
# DELIVERY_TEAM_TEST_SAVE=1 and separate /tmp/<role>/data and config XDG
# directories are mandatory. Only this verified fixture enables profile writes.
# Orders, cosmetic requests, purchases, selections and F/E actions use production
# lobby/RPC paths. The Host fixture corrects only physical Garage approach poses.
const CosmeticCatalog = preload("res://scripts/cosmetic_catalog.gd")
const VehiclePlacement = preload("res://scripts/vehicle_placement.gd")
const START_MONEY: int = 12000
const CLIENT_FREE: Dictionary = {"outfit": "sunshine", "backpack": "compact", "vehicle_paint": "mint"}
const HOST_FREE: Dictionary = {"outfit": "mint", "backpack": "compact", "vehicle_paint": "coral"}
const CLIENT_PAID: Dictionary = {"outfit": "night", "backpack": "rolltop", "vehicle_paint": "amber"}
const HOST_PAID: Dictionary = {"outfit": "retro", "backpack": "compact", "vehicle_paint": "plum"}
const CAREER_KEYS: Array[String] = ["version", "player_name", "money", "xp", "level", "rank", "total_deliveries", "express_deliveries", "total_money_earned", "best_shift", "owned_vehicles", "selected_vehicle"]
var app
var role: String = ""
var coord: String = ""
var latest_snapshot: Dictionary = {}
var cosmetic_results: Array[Dictionary] = []
var checks: int = 0
var failures: Array[String] = []
var deadline_msec: int = 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func flag(name: String, value: String = "ok") -> void:
	var file: FileAccess = FileAccess.open(coord.path_join(name), FileAccess.WRITE)
	check(file != null, "Coordination marker opens: " + name)
	if file != null:
		file.store_string(value)
		file.close()

func has_flag(name: String) -> bool:
	return FileAccess.file_exists(coord.path_join(name))

func wait_for(condition: Callable, seconds: float = 15.0) -> bool:
	var until: int = mini(deadline_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await process_frame
		OS.delay_msec(17)
	return false

func wait_flag(name: String) -> bool:
	var received: bool = await wait_for(func() -> bool: return has_flag(name))
	check(received, "Other process confirms " + name)
	return received

func _temporary_role_path(path: String) -> bool:
	if not path.is_absolute_path() or not path.simplify_path().begins_with("/tmp/"):
		return false
	var found: bool = false
	for part: String in path.simplify_path().split("/"):
		if part == role or part.begins_with(role + "-") or part.begins_with(role + "_"):
			found = true
		var other: String = "client" if role == "host" else "host"
		if part == other or part.begins_with(other + "-") or part.begins_with(other + "_"):
			return false
	return found

func _timeout() -> void:
	check(false, "Two-process cosmetic regression exceeded 90 seconds")
	print("LAN_COSMETIC_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--coord="):
			coord = arg.trim_prefix("--coord=")
	var data_path: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	var config_path: String = OS.get_environment("XDG_CONFIG_HOME").simplify_path()
	if not args.has("--test-mode") or not args.has("--isolated-save") or role not in ["host", "client"] or OS.get_environment("DELIVERY_TEAM_TEST_SAVE") != "1" or not _temporary_role_path(data_path) or not _temporary_role_path(config_path) or data_path == config_path or not coord.is_absolute_path() or not coord.simplify_path().begins_with("/tmp/"):
		printerr("LAN cosmetic regression refused: --test-mode --isolated-save, save sentinel, shared /tmp coord and distinct role-specific /tmp XDG directories required")
		quit(2)
		return
	coord = coord.simplify_path()
	deadline_msec = Time.get_ticks_msec() + 90000
	create_timer(90.0).timeout.connect(_timeout)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var isolated: bool = user_path.begins_with(data_path.trim_suffix("/") + "/")
	check(app.test_mode and isolated, "Test mode is active and user:// resolves inside the verified role XDG directory")
	if not isolated or not app.test_mode or FileAccess.file_exists(app.SAVE_PATH):
		check(false, "Profile save fixture requires a fresh isolated directory")
		await finish()
		return
	# Preserve normal --test-mode protection until BOTH the explicit sentinel and
	# the resolved user:// save destination have been checked above.
	app.test_mode = false
	app.lan_session.state_received.connect(func(data: Dictionary) -> void: latest_snapshot = data.duplicate(true))
	app.lan_session.event_received.connect(func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "cosmetic_result":
			cosmetic_results.append(event.duplicate(true)))
	check(app.DEMO_VERSION == str(ProjectSettings.get_setting("application/config/version")) and app.lan_session.GAME_VERSION == app.DEMO_VERSION, "Both production compatibility versions match the project version")
	migrate_old_profile()
	choose_offline_style()
	if role == "host":
		await run_host()
	else:
		await run_client()
	await finish()

func finish() -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if is_instance_valid(app):
		app._leave_lan()
		app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("LAN_COSMETIC_%s: %d checks, %d failures" % [role.to_upper(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func migrate_old_profile() -> void:
	# The shipped 0.12 career schema had version 1 and no cosmetic fields.
	var legacy: Dictionary = {"version": 1, "player_name": "Cosmetic " + role.capitalize(), "money": START_MONEY, "xp": 600, "level": 3, "rank": "City Courier", "total_deliveries": 17, "express_deliveries": 4, "total_money_earned": 20500, "best_shift": 3100, "owned_vehicles": ["bicycle"], "selected_vehicle": ""}
	var file: FileAccess = FileAccess.open(app.SAVE_PATH, FileAccess.WRITE)
	check(file != null, "Old 0.12 career JSON opens only in the isolated user directory")
	if file == null:
		return
	file.store_string(JSON.stringify(legacy))
	file.close()
	app.profile = app._load_profile()
	for key: String in CAREER_KEYS:
		check(app.profile.get(key) == legacy.get(key), "0.12 JSON migration preserves " + key)
	check(app.profile.get("appearance") == CosmeticCatalog.default_appearance() and app.profile.get("owned_cosmetics", []).is_empty(), "0.12 JSON gains only free canonical cosmetic defaults")
	check(app._save_profile(), "Migrated career uses the production atomic JSON save")
	check_saved_profile("Migrated " + role)

func choose_offline_style() -> void:
	var expected: Dictionary = HOST_FREE if role == "host" else CLIENT_FREE
	var cache: Array = visual_cache(app.player)
	app._open_customization()
	check(app.modal == "customization", "Profile customization opens before Host/Join")
	for category: String in CosmeticCatalog.CATEGORIES:
		app._select_cosmetic(category, str(expected[category]))
	app._close_customization()
	check(app.profile["appearance"] == expected and int(app.profile["money"]) == START_MONEY and app.profile["owned_cosmetics"].is_empty(), "Free profile choices apply and save without charging Money")
	check_model_appearance(app.player, expected, "Offline courier")
	check(visual_cache(app.player) == cache, "Offline choices retain prebuilt model, mesh and material instances")
	check_saved_profile("Offline " + role)

func check_lobby_locked() -> void:
	var before: Dictionary = app.profile.duplicate(true)
	app._open_customization()
	app._select_cosmetic("outfit", "classic_blue")
	check(app.modal != "customization" and app.profile == before, "Joined lobby cannot edit the previously submitted career style")

func public_player(peer_id: int) -> Dictionary:
	for value: Dictionary in latest_snapshot.get("players", []):
		if int(value.get("id", 0)) == peer_id:
			return value
	return {}

func public_vehicle(peer_id: int) -> Dictionary:
	for value: Dictionary in latest_snapshot.get("vehicles", []):
		if int(value.get("owner_id", 0)) == peer_id:
			return value
	return {}

func visual_cache(model: Node) -> Array:
	var values: Array = [model.get_instance_id()]
	for child: Node in model.get_children():
		values.append_array(visual_cache(child))
	if model is MeshInstance3D:
		var mesh_model: MeshInstance3D = model as MeshInstance3D
		if mesh_model.mesh != null:
			values.append(mesh_model.mesh.get_instance_id())
		if mesh_model.material_override != null:
			values.append(mesh_model.material_override.get_instance_id())
	return values

func check_model_appearance(model, expected: Dictionary, label: String) -> void:
	check(model.get_appearance() == expected, label + " retains exactly the three canonical IDs")
	var outfit: Dictionary = CosmeticCatalog.outfit_palette(str(expected["outfit"]))
	var colors_match: bool = true
	for channel: String in model._outfit_materials:
		if not model._outfit_materials[channel].albedo_color.is_equal_approx(Color(str(outfit[channel]))):
			colors_match = false
	var bag: Dictionary = CosmeticCatalog.backpack_palette(str(expected["backpack"]))
	colors_match = colors_match and model._backpack_materials[0].albedo_color.is_equal_approx(Color(str(bag["color"]))) and model._backpack_materials[1].albedo_color.is_equal_approx(Color(str(bag["trim"])))
	check(colors_match, label + " uses the catalog jacket, cap, pants and bag materials")
	var variants_match: bool = true
	for style: String in model._backpack_variants:
		if model._backpack_variants[style].visible != (style == str(bag["style"])):
			variants_match = false
	check(variants_match, label + " shows exactly its selected cached backpack variant")

func check_vehicle_paint(model, paint_id: String, label: String) -> void:
	var palette: Dictionary = CosmeticCatalog.paint_palette(paint_id)
	var matches: bool = model._paint_materials.size() == 2
	for index: int in range(model._paint_materials.size()):
		var expected: Color = model._factory_paint_colors[index] if paint_id == "factory" else Color(str(palette["paint" if index == 0 else "trim"]))
		matches = matches and model._paint_materials[index].albedo_color.is_equal_approx(expected)
	check(matches, label + " uses exact " + paint_id + " body and trim colors")

func walk_to(target: Vector3, seconds: float = 10.0) -> bool:
	app._close_modal()
	var until: int = mini(deadline_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	while Time.get_ticks_msec() < until:
		var direction: Vector3 = target - app.player.global_position
		direction.y = 0.0
		if direction.length() <= 1.4:
			Input.action_release("move_forward")
			await physics_frame
			return true
		app.player.set_view_direction(atan2(-direction.x, -direction.z))
		Input.action_press("move_forward")
		await process_frame
		OS.delay_msec(17)
	Input.action_release("move_forward")
	return false

func request_cosmetic(action: String, category: String, item_id: String, expect_ok: bool, forged: bool = false) -> bool:
	var before_count: int = cosmetic_results.size()
	var payload: Dictionary = {"category": category, "id": item_id}
	if forged:
		payload.merge({"price": -99999999, "money": 99999999, "xp": 99999999, "appearance": {"outfit": "retro"}, "owned_cosmetics": ["outfit:retro"], "palette": {"jacket": "#ff0000"}, "owner_id": 1}, true)
	app.lan_session.request_action(action, payload)
	var confirmed: bool = await wait_for(func() -> bool: return cosmetic_results.size() > before_count)
	check(confirmed, "%s/%s returns a private Host cosmetic result" % [category, item_id])
	if not confirmed:
		return false
	var result: Dictionary = cosmetic_results[before_count]
	check(bool(result.get("ok", false)) == expect_ok, "%s/%s receives the expected Host decision" % [category, item_id])
	return bool(result.get("ok", false)) == expect_ok

func place_at_garage(client_id: int) -> void:
	# Trusted Host fixture only: keep normal movement credit and cosmetic guards.
	app.player.reset_at(VehiclePlacement.GARAGE_POSITION + Vector3(2.0, 0.15, -2.0))
	app.lan_authority.records[1]["position"] = app.player.global_position
	app.lan_authority.records[1]["velocity"] = Vector3.ZERO
	var record: Dictionary = app.lan_authority.records[client_id]
	record["position"] = VehiclePlacement.GARAGE_POSITION + Vector3(0.0, 0.15, -6.0)
	record["velocity"] = Vector3.ZERO
	record["pose_tick_msec"] = Time.get_ticks_msec()
	app.lan_authority._correct_position(client_id)
	app.lan_authority._mark_changed()

func run_host() -> void:
	app._host_lan(str(app.profile["player_name"]), "Cosmetic integration", 4, 600)
	check(app.lan_session.phase == "lobby", "Host opens an ordinary ENet LAN lobby")
	if app.lan_session.phase != "lobby":
		return
	check_lobby_locked()
	flag("host-ready")
	var ready: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 2 and app.lan_session._can_start())
	check(ready, "Actual Client completes the 0.13 registration and Ready handshake")
	if not ready:
		return
	app._start_lan_shift()
	app._close_modal()
	if not await wait_flag("client-started"):
		return
	var client_id: int = int(FileAccess.get_file_as_string(coord.path_join("client-started")))
	var remote_ready: bool = await wait_for(func() -> bool: return app.remote_players.has(client_id))
	check(remote_ready, "Host creates the real Client's remote courier")
	if not remote_ready:
		return
	var remote = app.remote_players[client_id]
	var courier_cache: Array = visual_cache(remote)
	check_model_appearance(remote, CLIENT_FREE, "Host initial remote courier")
	check(public_player(client_id).get("appearance") == CLIENT_FREE, "Public player snapshot carries the Client's pre-Join style")
	if not await wait_flag("client-carrying"):
		return
	var carrying: bool = await wait_for(func() -> bool: return remote.is_carrying and bool(app.lan_authority.records[client_id]["carrying"]))
	check(carrying and remote._parcel.visible and remote._visual.visible, "Host sees the parcel collected through actual Client walking and E")
	check(visual_cache(remote) == courier_cache, "Walking and carrying retain the same remote model resources")
	place_at_garage(client_id)
	flag("garage-approach")
	check(app._near_garage() and not app.player.is_riding(), "Host fixture stands at the physical Garage on foot")
	var host_before: Dictionary = app.profile.duplicate(true)
	var host_revision: int = app.lan_authority.revision
	app._open_customization()
	app._buy_cosmetic("outfit", "retro")
	app._buy_cosmetic("vehicle_paint", "plum")
	app._close_customization()
	var host_cost: int = int(CosmeticCatalog.get_item("outfit", "retro")["price"]) + int(CosmeticCatalog.get_item("vehicle_paint", "plum")["price"])
	check(int(app.profile["money"]) == int(host_before["money"]) - host_cost and app.profile["appearance"] == HOST_PAID, "Host's own approved purchases update its own career and Money")
	check(app.lan_authority.get_profile(1) == app.profile and app.lan_authority.revision > host_revision, "Host's own purchase broadcasts an authoritative profile revision")
	check_saved_profile("Host purchases")
	flag("host-styled")
	if not await wait_flag("client-styled"):
		return
	var paid: bool = await wait_for(func() -> bool: return remote.get_appearance() == CLIENT_PAID)
	check(paid, "Host receives all Client paid selections in public snapshots")
	check_model_appearance(remote, CLIENT_PAID, "Host paid remote courier")
	check(visual_cache(remote) == courier_cache, "Purchases and repeated selection snapshots reuse the remote model resources")
	var client_profile: Dictionary = app.lan_authority.get_profile(client_id)
	var client_cost: int = int(CosmeticCatalog.get_item("outfit", "night")["price"]) + int(CosmeticCatalog.get_item("backpack", "rolltop")["price"]) + int(CosmeticCatalog.get_item("vehicle_paint", "amber")["price"])
	check(int(client_profile["money"]) == START_MONEY - client_cost and client_profile["owned_cosmetics"].size() == 3, "Host charges the shipped prices once and owns exactly the three paid Client items")
	check(int(client_profile["xp"]) == 600 and int(client_profile["total_deliveries"]) == 17 and not client_profile["owned_cosmetics"].has("outfit:retro"), "Forged wire career, ownership and price fields never become trusted")
	if not await wait_flag("client-bicycle-spawned"):
		return
	var bicycle_ready: bool = await wait_for(func() -> bool: return app.vehicles.has(client_id))
	check(bicycle_ready, "Host receives the Client's normal vehicle_spawn RPC")
	if not bicycle_ready:
		return
	var bicycle = app.vehicles[client_id]
	var bicycle_cache: Array = visual_cache(bicycle)
	check_model_appearance(bicycle, CLIENT_PAID, "Host parked bike rider")
	check_vehicle_paint(bicycle, "amber", "Host parked bike")
	check(public_vehicle(client_id).get("appearance") == CLIENT_PAID, "Public vehicle snapshot includes canonical courier and paint IDs")
	flag("host-bike-observed")
	if not await wait_flag("client-mounted"):
		return
	var mounted: bool = await wait_for(func() -> bool: return remote.is_riding() and bicycle.occupied)
	check(mounted and bicycle._rider.visible and not remote._visual.visible and bicycle._parcel.visible, "Host sees the painted seated Client and its server-confirmed parcel")
	check_model_appearance(bicycle, CLIENT_PAID, "Host seated bike rider")
	check(visual_cache(remote) == courier_cache and visual_cache(bicycle) == bicycle_cache, "Mounting retains remote courier and vehicle resources")
	flag("host-rider-observed")
	if not await wait_flag("client-factory"):
		return
	var factory: bool = await wait_for(func() -> bool: return bicycle.get_appearance()["vehicle_paint"] == "factory" and not remote.is_riding())
	check(factory and remote._visual.visible, "Dismount restores the same courier before repainting")
	check_vehicle_paint(bicycle, "factory", "Host restored bike")
	check(visual_cache(remote) == courier_cache and visual_cache(bicycle) == bicycle_cache, "Dismount and factory repaint reuse every cached model resource")
	var confirmed: Dictionary = app.lan_authority.get_profile(client_id)
	flag("host-verified")
	var left: bool = await wait_for(func() -> bool: return app.lan_session.members.size() == 1)
	check(left and app.state == "playing" and app.remote_players.is_empty(), "Client disconnect removes the remote courier while Host remains in its shift")
	check(app.lan_authority.get_profile(client_id) == confirmed, "Disconnect retains the exact confirmed Client cosmetic career")
	check_saved_profile("Host after Client disconnect")
	await wait_flag("client-reloaded")

func run_client() -> void:
	app._join_lan(str(app.profile["player_name"]), "127.0.0.1")
	var connected: bool = await wait_for(func() -> bool: return app.lan_session.phase == "lobby" and app.lan_session.members.has(app.lan_session.local_id))
	check(connected, "Actual Client joins through loopback IPv4 ENet")
	if not connected:
		return
	check_lobby_locked()
	app._set_lan_ready(true)
	var started: bool = await wait_for(func() -> bool: return app.state == "playing" and not latest_snapshot.is_empty() and app.remote_players.has(1))
	check(started, "Client receives the ordinary authoritative shift snapshot")
	if not started:
		return
	app._close_modal()
	var peer_id: int = app.lan_session.local_id
	var local_cache: Array = visual_cache(app.player)
	var host_remote = app.remote_players[1]
	var host_cache: Array = visual_cache(host_remote)
	check_model_appearance(app.player, CLIENT_FREE, "Client initial courier")
	check_model_appearance(host_remote, HOST_FREE, "Client initial Host courier")
	flag("client-started", str(peer_id))
	var outside_before: Dictionary = app.profile.duplicate(true)
	await request_cosmetic("cosmetic_buy", "outfit", "night", false, true)
	check(app.profile == outside_before, "Forged purchase away from the physical Garage cannot charge or change the Client")
	var first: Dictionary = {}
	for order: Dictionary in app.orders:
		if order.get("pickup_id", "") == "warehouse" and order.get("type", "") == "standard":
			first = order.duplicate(true)
			break
	check(not first.is_empty(), "Unmodified initial shared pool contains the deterministic Delivery Center parcel")
	if first.is_empty():
		return
	app._accept_order(int(first["id"]))
	var accepted: bool = await wait_for(func() -> bool: return int(app.active_order.get("id", 0)) == int(first["id"]))
	check(accepted, "Client claims the actual server-owned order through accept RPC")
	if not accepted:
		return
	check(await walk_to(first["pickup_position"]), "Actual WASD approaches the Delivery Center")
	app._interact()
	var carrying: bool = await wait_for(func() -> bool: return app.active_order.get("state", "") == "PickedUp" and app.player.is_carrying)
	check(carrying, "Actual E pickup is confirmed by Host before the carrying visual changes")
	if not carrying:
		return
	check(visual_cache(app.player) == local_cache, "Walking and carrying keep the same Client model instances")
	flag("client-carrying")
	if not await wait_flag("garage-approach"):
		return
	var approach: Vector3 = VehiclePlacement.GARAGE_POSITION + Vector3(0.0, 0.15, -6.0)
	var corrected: bool = await wait_for(func() -> bool: return Vector2(app.player.global_position.x - approach.x, app.player.global_position.z - approach.z).length() < 0.25)
	check(corrected and not app._near_garage(), "Normal Host correction places the Client outside Garage use distance")
	if not corrected:
		return
	check(await walk_to(VehiclePlacement.GARAGE_POSITION), "Actual Client walking enters the physical Garage use distance")
	app._interact()
	check(app.modal == "garage" and app._near_garage() and not app.player.is_riding(), "E opens Garage only while the Client stands nearby on foot")
	app._open_customization()
	check(app.modal == "customization" and not app.player.controls_enabled, "Garage customization disables movement while retaining the carrying parcel")
	var base_money: int = int(app.profile["money"])
	var revision: int = app._last_network_revision
	var price: int = int(CosmeticCatalog.get_item("outfit", "night")["price"])
	await request_cosmetic("cosmetic_buy", "outfit", "night", true, true)
	var bought: bool = await wait_for(func() -> bool: return app.profile["appearance"]["outfit"] == "night")
	check(bought and int(app.profile["money"]) == base_money - price and app._last_network_revision > revision, "Client applies only the Host revision and shipped price despite forged price and profile data")
	if not bought:
		return
	var paid_once: Dictionary = app.profile.duplicate(true)
	await request_cosmetic("cosmetic_buy", "outfit", "night", false, true)
	check(app.profile == paid_once and not bool(cosmetic_results.back().get("changed", true)), "Repeated premium purchase returns failure and never charges twice")
	await request_cosmetic("cosmetic_select", "outfit", "retro", false)
	check(app.profile == paid_once, "Client cannot select an unowned premium outfit")
	await request_cosmetic("cosmetic_buy", "bogus", "night", false, true)
	check(app.profile == paid_once, "Unknown wire category never changes Money, appearance or ownership")
	var before_bag: Dictionary = app.profile.duplicate(true)
	var before_results: int = cosmetic_results.size()
	app._buy_cosmetic("backpack", "rolltop")
	check(app.profile == before_bag, "Client customization waits for confirmation instead of optimistically granting a bag")
	var bag_bought: bool = await wait_for(func() -> bool: return cosmetic_results.size() > before_results and app.profile["appearance"]["backpack"] == "rolltop")
	check(bag_bought, "Production customization button sends a real cosmetic_buy RPC")
	await request_cosmetic("cosmetic_buy", "vehicle_paint", "amber", true)
	var all_bought: bool = await wait_for(func() -> bool: return app.profile["appearance"] == CLIENT_PAID)
	check(all_bought, "Three paid category IDs arrive through authoritative Client profile snapshots")
	if not all_bought:
		return
	for choice: Array in [["outfit", "sunshine"], ["outfit", "night"], ["backpack", "compact"], ["backpack", "rolltop"], ["vehicle_paint", "factory"], ["vehicle_paint", "amber"]]:
		var money_before: int = int(app.profile["money"])
		await request_cosmetic("cosmetic_select", str(choice[0]), str(choice[1]), true)
		var selected: bool = await wait_for(func() -> bool: return app.profile["appearance"][choice[0]] == choice[1])
		check(selected and int(app.profile["money"]) == money_before, "Free/owned selection changes only canonical style: %s/%s" % [choice[0], choice[1]])
	check_model_appearance(app.player, CLIENT_PAID, "Client paid courier")
	check(visual_cache(app.player) == local_cache, "Purchases and six selection states retain Client nodes, meshes and materials")
	check_saved_profile("Client purchases")
	flag("client-styled")
	if not await wait_flag("host-styled"):
		return
	var host_styled: bool = await wait_for(func() -> bool: return host_remote.get_appearance() == HOST_PAID)
	check(host_styled and visual_cache(host_remote) == host_cache, "Client receives Host purchases in the same cached remote model")
	check_model_appearance(host_remote, HOST_PAID, "Client styled Host courier")
	app._close_customization()
	app._close_modal()
	app._spawn_vehicle("bicycle")
	var spawned: bool = await wait_for(func() -> bool: return app.vehicles.has(peer_id) and not app.vehicles[peer_id].occupied)
	check(spawned, "Normal Garage request spawns the Client's trusted owned bicycle")
	if not spawned:
		return
	var bicycle = app.vehicles[peer_id]
	var bike_cache: Array = visual_cache(bicycle)
	check_model_appearance(bicycle, CLIENT_PAID, "Client parked bike rider")
	check_vehicle_paint(bicycle, "amber", "Client parked bike")
	flag("client-bicycle-spawned")
	if not await wait_flag("host-bike-observed"):
		return
	app._toggle_vehicle(peer_id)
	var mounted: bool = await wait_for(func() -> bool: return app.player.is_riding() and bicycle.occupied)
	check(mounted, "Actual F vehicle RPC confirms mounting the Client's own painted bicycle")
	if not mounted:
		return
	check(bicycle._rider.visible and bicycle._parcel.visible and not app.player._visual.visible, "Seated rider and parcel replace the walking courier visual")
	check_model_appearance(bicycle, CLIENT_PAID, "Client seated bike rider")
	var seated_before: Dictionary = app.profile.duplicate(true)
	await request_cosmetic("cosmetic_select", "outfit", "sunshine", false, true)
	check(app.profile == seated_before, "Wire cosmetic selection is rejected while riding even beside Garage")
	check(visual_cache(app.player) == local_cache and visual_cache(bicycle) == bike_cache, "Riding reuses courier and bike model resources")
	flag("client-mounted")
	if not await wait_flag("host-rider-observed"):
		return
	app._toggle_vehicle(peer_id)
	var dismounted: bool = await wait_for(func() -> bool: return not app.player.is_riding() and not bicycle.occupied)
	check(dismounted and app.player._parcel.visible and app.player._visual.visible, "Confirmed F dismount restores the same carrying courier")
	if not dismounted:
		return
	check(await walk_to(VehiclePlacement.GARAGE_POSITION), "Client walks back inside Garage distance after safe exit")
	app._interact()
	app._open_customization()
	var money_before_factory: int = int(app.profile["money"])
	await request_cosmetic("cosmetic_select", "vehicle_paint", "factory", true)
	var restored: bool = await wait_for(func() -> bool: return bicycle.get_appearance()["vehicle_paint"] == "factory")
	check(restored and int(app.profile["money"]) == money_before_factory, "Selecting factory paint costs nothing and updates the existing bicycle")
	check_vehicle_paint(bicycle, "factory", "Client restored bike")
	check(visual_cache(app.player) == local_cache and visual_cache(bicycle) == bike_cache, "Factory restoration retains all cached materials and model instances")
	app._close_customization()
	app._close_modal()
	app.lan_session.request_action("abandon")
	var abandoned: bool = await wait_for(func() -> bool: return app.active_order.is_empty() and not app.player.is_carrying)
	check(abandoned and int(app.profile["total_deliveries"]) == 17 and int(app.profile["xp"]) == 600, "Abandoning the visual fixture invents no delivery rewards or career XP")
	check_saved_profile("Client factory style")
	flag("client-factory")
	if not await wait_flag("host-verified"):
		return
	var confirmed: Dictionary = app.profile.duplicate(true)
	app._leave_lan()
	check(app.state == "menu" and app.lan_session.phase == "offline" and app.profile == confirmed, "Client disconnect returns to menu with its exact confirmed profile")
	check_saved_profile("Client after disconnect")
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	check(app.test_mode, "Fresh instance still begins with normal test-mode save protection")
	app.test_mode = false
	app.profile = app._load_profile()
	app._apply_profile_appearance()
	check(app.profile == confirmed, "Fresh production JSON loader reloads the exact post-disconnect cosmetic and career profile")
	check_model_appearance(app.player, confirmed["appearance"], "Reloaded Client courier")
	check_saved_profile("Reloaded Client")
	flag("client-reloaded")

func check_saved_profile(label: String) -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.SAVE_PATH))
	# JSON numbers and arrays have different Variant representation from the
	# runtime's int and typed Array[String] values. Compare every serialized
	# field in the same JSON representation, then separately reload production.
	var expected: Variant = JSON.parse_string(JSON.stringify(app.profile))
	check(saved is Dictionary and expected is Dictionary and saved == expected, label + " atomic JSON matches every confirmed profile field")
	check(not FileAccess.file_exists(app.SAVE_PATH + ".tmp"), label + " leaves no unfinished atomic save")
