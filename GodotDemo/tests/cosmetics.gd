extends SceneTree

# Run against source and exported packs with --test-mode. All careers are
# in-memory fixtures; no profile, settings or audio preference files are written.
const Catalog = preload("res://scripts/cosmetic_catalog.gd")
const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
const Placement = preload("res://scripts/vehicle_placement.gd")
const AuthorityScript = preload("res://scripts/lan_authority.gd")
const SessionScript = preload("res://scripts/lan_session.gd")
const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const VehicleScript = preload("res://scripts/vehicle_controller.gd")
var checks: int = 0
var failures: Array[String] = []
var cosmetic_events: Array[Dictionary] = []
var change_count: int = 0
var definitions: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("Cosmetic tests require --test-mode")
		quit(2)
		return
	seed(130013)
	definitions = VehicleCatalog.load_definitions()
	test_catalog_and_migration()
	test_transactions()
	await test_authority()
	test_models()
	await process_frame
	await test_solo()
	print("COSMETIC_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func career() -> Dictionary:
	return {"version": 1, "player_name": "Old courier", "money": 9000, "xp": 3900,
		"total_deliveries": 47, "express_deliveries": 8, "total_money_earned": 24000,
		"best_shift": 7100, "owned_vehicles": ["bicycle", "scooter"], "selected_vehicle": "scooter"}

func check_career(actual: Dictionary, original: Dictionary, message: String, include_money: bool = true) -> void:
	for key: String in ["xp", "total_deliveries", "express_deliveries", "total_money_earned", "best_shift", "owned_vehicles", "selected_vehicle"]:
		check(actual.get(key) == original.get(key), "%s preserves %s" % [message, key])
	if include_money:
		check(actual.get("money") == original.get("money"), message + " preserves career balance")

func test_catalog_and_migration() -> void:
	check(FileAccess.file_exists(Catalog.DATA_PATH), "The exported game includes the editable cosmetic catalog")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Catalog.DATA_PATH))
	check(data is Dictionary and data.get("version") == 1, "The shipped catalog parses with version one")
	var counts: Dictionary = {"outfit": 6, "backpack": 4, "vehicle_paint": 6}
	for category: String in Catalog.CATEGORIES:
		var items: Array[Dictionary] = Catalog.get_items(category)
		check(items.size() == int(counts[category]), category + " has all advertised choices")
		var ids: Array[String] = []
		var free_count: int = 0
		for item: Dictionary in items:
			var item_id: String = str(item["id"])
			check(not ids.has(item_id) and not item_id.is_empty(), category + " IDs are unique")
			ids.append(item_id)
			check(int(item["price"]) >= 0 and not str(item["name"]).is_empty(), category + ":" + item_id + " has a name and nonnegative price")
			if int(item["price"]) == 0:
				free_count += 1
			for channel: String in item["palette"]:
				var value: String = str(item["palette"][channel])
				check(channel == "style" or (category == "vehicle_paint" and item_id == "factory" and value.is_empty()) or Color.html_is_valid(value), category + ":" + item_id + " uses a valid palette")
		check(free_count >= 2 and int(Catalog.get_item(category, Catalog.DEFAULTS[category])["price"]) == 0, category + " offers free choices and a free default")
	var copied: Dictionary = Catalog.load_definitions()
	copied["outfit"][0]["price"] = 999999
	copied["outfit"][0]["palette"]["jacket"] = "#ff0000"
	check(int(Catalog.get_item("outfit", "classic_blue")["price"]) == 0 and Catalog.outfit_palette("classic_blue")["jacket"] == "#246cdb", "Mutating a returned definition cannot alter prices or palettes")
	var original: Dictionary = career()
	var authority = AuthorityScript.new()
	var session = SessionScript.new()
	for migrated: Dictionary in [authority._sanitize_profile(original), session._sanitize_profile(original)]:
		check(migrated["appearance"] == Catalog.default_appearance() and migrated["owned_cosmetics"].is_empty(), "A 0.12 career receives safe default appearance without paid ownership")
		check_career(migrated, original, "A 0.12 migration")
		var round_trip: Dictionary = JSON.parse_string(JSON.stringify(migrated))
		check(Catalog.sanitize_profile(round_trip) == Catalog.sanitize_profile(migrated), "Serialized migrated cosmetic fields round-trip without changing IDs")
	check(not original.has("appearance") and not original.has("owned_cosmetics"), "Migration does not mutate its legacy input")
	var hostile: Dictionary = original.duplicate(true)
	hostile["appearance"] = {"outfit": "night", "backpack": "missing", "vehicle_paint": ["mint"], "palette": {"jacket": "#ffffff"}}
	hostile["owned_cosmetics"] = ["outfit:night", "outfit:night", "outfit:unknown", "wrong:night", 12, "outfit:night:extra"]
	var safe: Dictionary = Catalog.sanitize_profile(hostile)
	check(safe["appearance"] == {"outfit": "night", "backpack": "classic", "vehicle_paint": "factory"} and safe["owned_cosmetics"] == ["outfit:night"], "Valid ownership survives while malformed fields and duplicate ownership are removed")
	check(Catalog.sanitize_profile({"appearance": {"outfit": "night", "backpack": "rolltop", "vehicle_paint": "amber"}})["appearance"] == Catalog.default_appearance(), "Unowned premium appearance cannot be loaded from a profile")
	for malformed: Variant in [null, [], "mint", 12]:
		check(Catalog.normalize_appearance(malformed) == Catalog.default_appearance(), "A non-dictionary appearance falls back safely")
		check(Catalog.sanitize_profile({"owned_cosmetics": malformed})["owned_cosmetics"].is_empty(), "Non-array ownership falls back safely")
	check(Catalog.normalize_appearance({"outfit": "unknown", "backpack": {}, "vehicle_paint": 3}) == Catalog.default_appearance(), "Unknown IDs and wrong field types fall back per category")
	# Ownership is a purchase history. Repricing a formerly paid item to free must
	# not silently delete it on save; old legitimate known tokens remain valid.
	check(Catalog.sanitize_profile({"owned_cosmetics": ["outfit:mint"]})["owned_cosmetics"] == ["outfit:mint"], "A valid purchase token survives a later free price")
	authority.free()
	session.free()

func test_transactions() -> void:
	for category: String in Catalog.CATEGORIES:
		for item: Dictionary in Catalog.get_items(category):
			var profile: Dictionary = career()
			profile.merge(Catalog.sanitize_profile(profile), true)
			var before: Dictionary = profile.duplicate(true)
			var item_id: String = str(item["id"])
			var price: int = int(item["price"])
			var result: Dictionary = Catalog.buy(profile, category, item_id)
			check(bool(result["ok"]) and profile["appearance"][category] == item_id, category + ":" + item_id + " buys or freely selects and equips")
			check(int(profile["money"]) == int(before["money"]) - price, category + ":" + item_id + " deducts exactly the catalog price")
			check_career(profile, before, category + ":" + item_id + " purchase", false)
			var key: String = category + ":" + item_id
			check(profile["owned_cosmetics"].has(key) == (price > 0), category + ":" + item_id + " records only an actual paid purchase")
			var paid: Dictionary = profile.duplicate(true)
			result = Catalog.buy(profile, category, item_id)
			check(profile == paid and not bool(result["changed"]), category + ":" + item_id + " repeated purchase never double charges")
			check(bool(result["ok"]) == (price == 0), category + ":" + item_id + " repeated paid purchase reports already owned")
			result = Catalog.select(profile, category, item_id)
			check(bool(result["ok"]) and not bool(result["changed"]) and profile == paid, category + ":" + item_id + " repeated selection is idempotent")
			if price > 0:
				profile = career()
				profile["money"] = price - 1
				before = profile.duplicate(true)
				result = Catalog.buy(profile, category, item_id)
				check(not bool(result["ok"]) and not bool(result["changed"]) and profile == before, category + ":" + item_id + " insufficient money rejects without mutation")
				result = Catalog.select(profile, category, item_id)
				check(not bool(result["ok"]) and profile == before, category + ":" + item_id + " cannot equip an unowned premium item")
	var invalid_requests: Array = [["missing", "night"], ["outfit", "missing"], ["backpack", "night"], [null, "night"], ["outfit", 1500], [{}, []], ["outfit", "x".repeat(80)]]
	for request: Array in invalid_requests:
		var profile: Dictionary = career()
		var before: Dictionary = profile.duplicate(true)
		for purchasing: bool in [true, false]:
			var result: Dictionary = Catalog.buy(profile, request[0], request[1]) if purchasing else Catalog.select(profile, request[0], request[1])
			check(not bool(result["ok"]) and not bool(result["changed"]) and profile == before, "Unknown or wrongly typed cosmetic requests preserve the profile")
	for money: Variant in [-1, "9000", null, NAN, INF, 1000000001]:
		var profile: Dictionary = career()
		profile["money"] = money
		var before_appearance: Dictionary = Catalog.sanitize_profile(profile)
		var result: Dictionary = Catalog.buy(profile, "outfit", "night")
		check(not bool(result["ok"]) and not bool(result["changed"]) and not profile.has("appearance") and Catalog.sanitize_profile(profile) == before_appearance, "Invalid balance cannot buy or grant premium ownership")
	var exact: Dictionary = career()
	exact["money"] = 1500
	check(bool(Catalog.buy(exact, "outfit", "night")["ok"]) and int(exact["money"]) == 0, "An exact catalog-price balance can buy the item")

func _on_cosmetic_event(peer_id: int, event: Dictionary) -> void:
	if event.get("type") == "cosmetic_result":
		var value: Dictionary = event.duplicate(true)
		value["peer_id"] = peer_id
		cosmetic_events.append(value)

func _on_authority_changed() -> void:
	change_count += 1

func request_check(authority, action: String, payload: Dictionary, ok: bool, changed: bool, message: String) -> void:
	var before: Dictionary = authority.get_profile(1)
	var revision: int = authority.revision
	var events: int = cosmetic_events.size()
	var changes: int = change_count
	authority.handle_request(1, action, payload)
	check(cosmetic_events.size() == events + 1, message + " returns one explicit result")
	if cosmetic_events.size() > events:
		var result: Dictionary = cosmetic_events.back()
		check(bool(result["ok"]) == ok and bool(result["changed"]) == changed and int(result["peer_id"]) == 1 and result["session_id"] == "cosmetic-regression", message + " result identifies the requester and session")
	check(authority.revision == revision + (1 if changed else 0) and change_count == changes + (1 if changed else 0), message + " broadcasts only confirmed changes")
	if not changed:
		check(authority.get_profile(1) == before, message + " preserves money, ownership and appearance")

func test_authority() -> void:
	var city = WorldScript.new()
	root.add_child(city)
	var authority = AuthorityScript.new()
	root.add_child(authority)
	await process_frame
	await physics_frame
	authority.start_session({"shift_seconds": -1}, [
		{"id": 1, "name": "First courier", "profile": career()},
		{"id": 2, "name": "Second courier", "profile": career()}
	], city, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")), "cosmetic-regression")
	authority.set_process(false)
	authority.changed.connect(_on_authority_changed)
	authority.event_ready.connect(_on_cosmetic_event)
	var other: Dictionary = authority.get_profile(2)
	authority.records[1]["position"] = city.spawn_position
	request_check(authority, "cosmetic_buy", {"category": "outfit", "id": "night", "price": 0, "position": Placement.GARAGE_POSITION, "money": 999999}, false, false, "Forged remote garage and balance")
	authority.records[1]["position"] = Placement.GARAGE_POSITION + Vector3(5.01, 0, 0)
	request_check(authority, "cosmetic_select", {"category": "outfit", "id": "mint"}, false, false, "Outside the actual garage radius")
	authority.records[1]["position"] = Placement.GARAGE_POSITION + Vector3(0, 0.15, -3)
	check(Placement.can_use_garage(authority.records[1]["position"], city), "The real garage approach is reachable on foot")
	authority.records[1]["vehicle"] = authority._new_vehicle(1, "bicycle", Placement.GARAGE_POSITION + Vector3(3, 0.1, 0), PI)
	authority.records[1]["vehicle"]["occupied"] = true
	request_check(authority, "cosmetic_buy", {"category": "outfit", "id": "night"}, false, false, "A riding courier at the garage")
	authority.records[1]["vehicle"]["occupied"] = false
	request_check(authority, "cosmetic_select", {"category": "outfit", "id": "night"}, false, false, "Selecting unowned premium clothing")
	request_check(authority, "cosmetic_buy", {"category": [], "id": "night"}, false, false, "Malformed category")
	request_check(authority, "cosmetic_buy", {"category": "outfit", "id": "missing"}, false, false, "Unknown item")
	var before: Dictionary = authority.get_profile(1)
	request_check(authority, "cosmetic_buy", {"category": "outfit", "id": "night", "price": -100000, "money": 999999, "reward": 999999, "appearance": {"outfit": "express"}}, true, true, "Host-priced clothing purchase")
	check(int(authority.get_profile(1)["money"]) == int(before["money"]) - 1500 and authority.get_profile(1)["appearance"]["outfit"] == "night", "Host ignores every supplied price, reward and appearance")
	request_check(authority, "cosmetic_buy", {"category": "outfit", "id": "night", "price": 0}, false, false, "Repeated Host purchase")
	request_check(authority, "cosmetic_select", {"category": "outfit", "id": "night"}, true, false, "Repeated Host selection")
	request_check(authority, "cosmetic_select", {"category": "backpack", "id": "compact"}, true, true, "Free backpack selection")
	request_check(authority, "cosmetic_buy", {"category": "vehicle_paint", "id": "amber", "price": 0}, true, true, "Host-priced paint purchase")
	var appearance: Dictionary = authority.get_profile(1)["appearance"]
	check(authority.records[1]["vehicle"]["appearance"] == appearance, "A parked owned vehicle receives the confirmed appearance")
	var snapshot: Dictionary = authority.snapshot_for(2)
	check(snapshot["players"][0]["appearance"] == appearance and snapshot["vehicles"][0]["appearance"] == appearance, "Other peers receive the confirmed courier and vehicle appearance")
	check(authority.get_profile(2) == other, "One courier's purchases never alter another career")
	authority.records[1]["profile"]["money"] = 0
	request_check(authority, "cosmetic_buy", {"category": "backpack", "id": "rolltop", "price": 0}, false, false, "An insufficient Host balance")
	# Real physics, rather than a mock garage flag, prevents shopping through a wall.
	var blocker: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 0.3)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Placement.GARAGE_POSITION + Vector3(0, 1.0, -1.5)
	city.add_child(blocker)
	await physics_frame
	check(not Placement.can_use_garage(authority.records[1]["position"], city), "Real geometry blocks garage line of sight")
	request_check(authority, "cosmetic_select", {"category": "outfit", "id": "mint"}, false, false, "Shopping through an obstruction")
	blocker.queue_free()
	var events: int = cosmetic_events.size()
	authority.handle_request(999, "cosmetic_buy", {"category": "outfit", "id": "night"})
	authority.records[1]["connected"] = false
	authority.handle_request(1, "cosmetic_select", {"category": "outfit", "id": "mint"})
	authority.records[1]["connected"] = true
	authority.phase = "results"
	authority.handle_request(1, "cosmetic_select", {"category": "outfit", "id": "mint"})
	check(cosmetic_events.size() == events, "Unknown, disconnected and ended-session requests are ignored")
	authority.queue_free()
	city.queue_free()
	await process_frame

func capture_model(model) -> Dictionary:
	var result: Dictionary = {"nodes": {}, "meshes": {}, "materials": {}, "protected": {}, "collisions": {},
		"physics": [model.collision_layer, model.collision_mask, model.floor_snap_length, model.floor_max_angle, model.velocity, model.controls_enabled]}
	capture_node(model, model, result)
	return result

func capture_node(node: Node, model: Node, result: Dictionary) -> void:
	var path: String = str(model.get_path_to(node))
	result["nodes"][path] = [node.get_instance_id(), node.get_class(), (node as Node3D).transform if node is Node3D else null]
	if node is MeshInstance3D and node.mesh != null:
		var material: Material = node.material_override
		result["meshes"][path] = [node.mesh.get_instance_id(), material.get_instance_id() if material != null else 0]
		if material is StandardMaterial3D:
			var state: Array = [material.albedo_color, material.metallic, material.roughness, material.transparency, material.emission_enabled, material.emission]
			result["materials"][material.get_instance_id()] = state
			var lower: String = str(node.name).to_lower()
			if lower.begins_with("eye") or lower.begins_with("tire") or lower.begins_with("rim") or lower.begins_with("spoke") or lower.contains("glass") or lower.contains("window") or lower.begins_with("wheelhub"):
				result["protected"][path] = state
	if node is CollisionShape3D:
		var dimensions: Variant = node.shape.size if node.shape is BoxShape3D else Vector2(node.shape.radius, node.shape.height)
		result["collisions"][path] = [node.shape.get_instance_id(), dimensions, node.disabled]
	for child: Node in node.get_children():
		capture_node(child, model, result)

func mutable_material_ids(model) -> Array[int]:
	var ids: Array[int] = []
	for material: StandardMaterial3D in model._outfit_materials.values():
		ids.append(material.get_instance_id())
	for material: StandardMaterial3D in model._backpack_materials:
		ids.append(material.get_instance_id())
	if model is VehicleScript:
		for material: StandardMaterial3D in model._paint_materials:
			ids.append(material.get_instance_id())
	return ids

func check_model_invariants(model, before: Dictionary, message: String) -> void:
	var after: Dictionary = capture_model(model)
	for field: String in ["nodes", "meshes", "collisions", "physics", "protected"]:
		check(after[field] == before[field], message + " preserves " + field)
	var mutable: Array[int] = mutable_material_ids(model)
	var same_material_properties: bool = after["materials"].keys() == before["materials"].keys()
	for material_id: int in before["materials"]:
		if not after["materials"].has(material_id):
			same_material_properties = false
			continue
		var old: Array = before["materials"][material_id]
		var current: Array = after["materials"][material_id]
		if current.slice(1) != old.slice(1) or (not mutable.has(material_id) and current[0] != old[0]):
			same_material_properties = false
	check(same_material_properties, message + " changes only the intended material colors")

func check_courier_palette(model, appearance: Dictionary, message: String) -> void:
	check(model.get_appearance() == appearance, message + " retains normalized appearance IDs")
	if model._outfit_materials.is_empty():
		return
	var palette: Dictionary = Catalog.outfit_palette(str(appearance["outfit"]))
	var correct: bool = true
	for channel: String in model._outfit_materials:
		if model._outfit_materials[channel].albedo_color != Color(str(palette[channel])):
			correct = false
	check(correct, message + " applies every outfit channel")
	var bag: Dictionary = Catalog.backpack_palette(str(appearance["backpack"]))
	check(model._backpack_materials[0].albedo_color == Color(str(bag["color"])) and model._backpack_materials[1].albedo_color == Color(str(bag["trim"])), message + " applies backpack color and trim")
	var visible: Array[String] = []
	for style: String in model._backpack_variants:
		if model._backpack_variants[style].visible:
			visible.append(style)
	check(visible == [str(bag["style"])], message + " shows exactly the selected backpack")
	var straps_correct: bool = true
	for strap: Node3D in model._backpack_straps:
		if strap.visible != (bag["style"] != "messenger"):
			straps_correct = false
	check(straps_correct, message + " uses the correct backpack or crossbody straps")

func exercise_courier(model, before: Dictionary, label: String) -> void:
	for item: Dictionary in Catalog.get_items("outfit"):
		var appearance: Dictionary = model.get_appearance()
		appearance["outfit"] = str(item["id"])
		model.apply_appearance(appearance)
		check_courier_palette(model, appearance, label + " outfit " + str(item["id"]))
		check_model_invariants(model, before, label + " outfit " + str(item["id"]))
	for item: Dictionary in Catalog.get_items("backpack"):
		var appearance: Dictionary = model.get_appearance()
		appearance["backpack"] = str(item["id"])
		model.apply_appearance(appearance)
		check_courier_palette(model, appearance, label + " backpack " + str(item["id"]))
		check_model_invariants(model, before, label + " backpack " + str(item["id"]))
	var appearance: Dictionary = model.get_appearance()
	for repeat_index: int in range(32):
		model.apply_appearance(appearance.duplicate(true))
	check_model_invariants(model, before, label + " repeated snapshots")
	var copied: Dictionary = model.get_appearance()
	copied["outfit"] = "unknown"
	check(model.get_appearance() == appearance, label + " returns an independent appearance dictionary")
	model.set_network_identity("Courier", 3)
	check_courier_palette(model, appearance, label + " network identity")
	model.apply_appearance({"outfit": "missing", "backpack": "missing", "vehicle_paint": "missing"})
	check_courier_palette(model, Catalog.default_appearance(), label + " safe fallback")
	check_model_invariants(model, before, label + " safe fallback")

func test_models() -> void:
	for remote: bool in [false, true]:
		var player = PlayerScript.new()
		if remote:
			player.configure_remote("Remote courier", 2)
		player.apply_appearance({"outfit": "night", "backpack": "rolltop", "vehicle_paint": "amber"})
		root.add_child(player)
		player.set_physics_process(false)
		player.set_controls_enabled(not remote)
		var before: Dictionary = capture_model(player)
		check_courier_palette(player, {"outfit": "night", "backpack": "rolltop", "vehicle_paint": "amber"}, "Appearance supplied before player ready")
		exercise_courier(player, before, "Remote player" if remote else "Local player")
		player.queue_free()
	for vehicle_id: String in ["bicycle", "scooter", "car"]:
		var vehicle = VehicleScript.new()
		vehicle.configure(definitions[vehicle_id], 7, false)
		vehicle.apply_appearance({"outfit": "retro", "backpack": "messenger", "vehicle_paint": "plum"})
		root.add_child(vehicle)
		vehicle.set_physics_process(false)
		vehicle.set_occupied(true)
		vehicle.set_controls_enabled(true)
		vehicle.speed = 7.5
		vehicle.velocity = Vector3(1.0, 0.0, 2.0)
		var before: Dictionary = capture_model(vehicle)
		var original_definition: Dictionary = vehicle.definition.duplicate(true)
		check_courier_palette(vehicle, {"outfit": "retro", "backpack": "messenger", "vehicle_paint": "plum"}, vehicle_id + " appearance supplied before ready")
		exercise_courier(vehicle, before, vehicle_id)
		for item: Dictionary in Catalog.get_items("vehicle_paint"):
			var paint_id: String = str(item["id"])
			vehicle.apply_paint(paint_id)
			var palette: Dictionary = Catalog.paint_palette(paint_id)
			var correct: bool = true
			for index: int in range(vehicle._paint_materials.size()):
				var expected: Color = vehicle._factory_paint_colors[index] if paint_id == "factory" else Color(str(palette["paint" if index == 0 else "trim"]))
				if vehicle._paint_materials[index].albedo_color != expected:
					correct = false
			check(correct and vehicle.get_appearance()["vehicle_paint"] == paint_id, vehicle_id + " applies or restores paint " + paint_id)
			check_model_invariants(vehicle, before, vehicle_id + " paint " + paint_id)
		vehicle.apply_paint("factory")
		check(vehicle._paint_materials[0].albedo_color == vehicle._factory_paint_colors[0] and vehicle._paint_materials[1].albedo_color == vehicle._factory_paint_colors[1], vehicle_id + " returns to its individual factory colors")
		check(vehicle.definition == original_definition and vehicle.speed == 7.5 and vehicle.occupied and vehicle.owner_peer_id == 7, vehicle_id + " appearance never changes motion tuning, speed or ownership")
		vehicle.queue_free()

func test_solo() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app.set_process(false)
	app.player.set_physics_process(false)
	check(app.test_mode and not app._lan_active(), "The Solo harness uses normal UI and disables personal profile writes")
	var original: Dictionary = career()
	app.profile = app.lan_authority._sanitize_profile(original)
	app._apply_profile_appearance()
	app._open_customization()
	check(app.modal == "customization" and not app.player.controls_enabled, "Menu customization opens and releases gameplay controls")
	app._buy_cosmetic("outfit", "night")
	app._select_cosmetic("backpack", "compact")
	app._select_cosmetic("vehicle_paint", "coral")
	check(int(app.profile["money"]) == int(original["money"]) - 1500 and app.profile["owned_cosmetics"] == ["outfit:night"], "Offline menu purchase uses the same prices and ownership policy")
	check(app.player.get_appearance() == app.profile["appearance"], "Solo selection updates the existing courier immediately")
	check_career(app.profile, original, "Solo customization", false)
	var confirmed: Dictionary = app.profile.duplicate(true)
	app._buy_cosmetic("outfit", "night")
	check(app.profile == confirmed and app._save_profile(), "A repeated Solo purchase and test-mode save cannot charge twice")
	app._close_customization()
	check(app.modal.is_empty() and app.state == "menu", "Closing menu customization returns to the profile menu")
	app._begin_shift()
	app.set_process(false)
	app.player.set_physics_process(false)
	app._close_modal()
	app.player.reset_at(app.city.spawn_position)
	app._open_customization()
	check(app.modal.is_empty(), "Solo shopping away from the garage is rejected")
	app.player.reset_at(Placement.GARAGE_POSITION + Vector3(0, 0.15, -3))
	app._open_garage()
	app._open_customization()
	check(app.modal == "customization", "A pedestrian can open customization from the real garage")
	app._select_cosmetic("outfit", "mint")
	check(app.profile["appearance"]["outfit"] == "mint" and int(app.profile["money"]) == int(confirmed["money"]), "A free Solo garage selection leaves career balance intact")
	app._close_customization()
	check(app.modal == "garage" and not app.player.controls_enabled, "Closing customization restores the garage and its control state")
	app._close_modal()
	check(app.player.controls_enabled, "Leaving the garage restores gameplay controls")
	app._open_customization()
	app._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(app.state == "paused" and app.modal.is_empty() and not app.hud._customization.visible, "Losing focus during garage customization pauses and closes its modal")
	app._resume()
	check(app.state == "playing" and app.player.controls_enabled, "Resuming after customization loses focus restores gameplay controls")
	app.queue_free()
	await process_frame
