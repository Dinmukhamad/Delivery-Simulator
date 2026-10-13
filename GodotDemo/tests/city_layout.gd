extends SceneTree

const WorldScript = preload("res://scripts/world.gd")
const HudScript = preload("res://scripts/hud.gd")
const VehicleScript = preload("res://scripts/vehicle_controller.gd")
const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
var city
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("City checks require --test-mode.")
		quit(2)
		return
	city = WorldScript.new()
	root.add_child(city)
	await process_frame
	await physics_frame
	test_layout()
	test_usable_endpoints()
	await test_map_projection()
	await test_driving_across_old_boundary()
	city.queue_free()
	await process_frame
	print("CITY_LAYOUT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_layout() -> void:
	var layout: Dictionary = city.get_map_layout()
	var bounds: Rect2 = layout.get("bounds", Rect2())
	check(bounds == Rect2(-258.0, -258.0, 516.0, 516.0), "Map is three times wider and longer than the original 172 m city")
	check(is_equal_approx(bounds.get_area(), 172.0 * 172.0 * 9.0), "Expanded city has nine times the original playable map area")
	var districts: Array = layout.get("districts", [])
	check(districts.size() >= 6, "City has at least six distinct urban districts")
	var district_ids: Dictionary = {}
	var district_colors: Dictionary = {}
	for entry: Dictionary in districts:
		var id: String = str(entry.get("id", ""))
		var name: String = str(entry.get("name", ""))
		var rect: Rect2 = entry.get("rect", Rect2())
		check(not id.is_empty() and not name.is_empty() and not district_ids.has(id), "Every district has a unique identity and a readable name")
		check(rect.has_area() and bounds.encloses(rect), "District %s is inside the actual city bounds" % id)
		district_ids[id] = true
		district_colors[str(entry.get("color", Color.WHITE))] = true
	check(district_colors.size() >= 4, "Map districts have visibly different colors")
	var buildings: Array = layout.get("buildings", [])
	var roads: Array = layout.get("roads", [])
	var outer_buildings: int = 0
	check(buildings.size() >= 80, "Expanded city adds buildings rather than only scaling the old geometry")
	check(roads.size() >= 20, "Additional neighborhoods have connecting streets")
	for i: int in range(buildings.size()):
		var rect: Rect2 = buildings[i].get("rect", Rect2())
		check(rect.has_area() and bounds.encloses(rect), "Building %d footprint is inside the city" % i)
		var center: Vector2 = rect.get_center()
		if absf(center.x) > 86.0 or absf(center.y) > 86.0:
			outer_buildings += 1
		var road_overlap: bool = false
		for road: Rect2 in roads:
			if rect.intersects(road):
				road_overlap = true
				break
		check(not road_overlap, "Building %d does not obstruct asphalt streets" % i)
		var building_overlap: bool = false
		for j: int in range(i):
			if rect.intersects(buildings[j]["rect"]):
				building_overlap = true
				break
		check(not building_overlap, "Building %d does not overlap another building" % i)
	check(outer_buildings >= 60, "Most new buildings inhabit the expanded districts outside the old boundary")

	var pending: Array[Node] = [city]
	var tallest_solid: float = 0.0
	var collider_count: int = 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is CollisionShape3D:
			var collider: CollisionShape3D = node
			if collider.shape is BoxShape3D:
				var box: BoxShape3D = collider.shape
				collider_count += 1
				tallest_solid = maxf(tallest_solid, box.size.y)
	check(tallest_solid >= 30.0, "Business district contains real high-rise geometry and full-height collision")
	check(collider_count >= buildings.size(), "Expanded buildings have real static collision bodies")
	var parks: Array = layout.get("parks", [])
	check(parks.size() >= 2, "City contains multiple usable green areas")
	for park: Rect2 in parks:
		check(park.has_area() and bounds.encloses(park), "Park lies inside the real city map")
	check(bounds.has_point(Vector2(city.spawn_position.x, city.spawn_position.z)), "Courier starts inside the city")
	var garage: Vector3 = layout.get("garage", Vector3.INF)
	check(garage.is_finite() and bounds.has_point(Vector2(garage.x, garage.z)), "Garage remains accessible in the expanded city")

func test_usable_endpoints() -> void:
	var layout: Dictionary = city.get_map_layout()
	var bounds: Rect2 = layout["bounds"]
	check(city.pickup_points[0].get("id") == "warehouse" and city.delivery_points[0].get("id") == "house_01", "First delivery keeps the existing warehouse-to-house onboarding route")
	check(city.pickup_points[0]["position"] == Vector3(-23, 0, 10) and city.delivery_points[0]["position"] == Vector3(12, 0, 10), "The first order remains a short walk after city expansion")
	check(city.pickup_points.size() >= 12, "Businesses offer at least twelve pickup locations")
	check(city.delivery_points.size() >= 40, "City offers at least forty destinations")
	var points: Array = []
	points.append_array(city.pickup_points)
	points.append_array(city.delivery_points)
	var ids: Dictionary = {}
	var positions: Dictionary = {}
	var outer_points: int = 0
	var served_districts: Dictionary = {}
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.38
	for point: Dictionary in points:
		var id: String = str(point.get("id", ""))
		var position: Vector3 = point.get("position", Vector3.INF)
		check(not id.is_empty() and not ids.has(id), "Every delivery interaction point has a unique ID")
		ids[id] = true
		check(position.is_finite() and bounds.has_point(Vector2(position.x, position.z)), "Point %s is inside the city" % id)
		check(not positions.has(position), "Point %s does not duplicate another interaction point" % id)
		positions[position] = true
		if absf(position.x) > 86.0 or absf(position.z) > 86.0:
			outer_points += 1
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, position + Vector3(0.0, 1.0, 0.0))
		query.collision_mask = 1
		check(city.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Courier can stand at point %s without being inside a building" % id)
		for district: Dictionary in layout.get("districts", []):
			var rect: Rect2 = district["rect"]
			if rect.has_point(Vector2(position.x, position.z)):
				served_districts[district["id"]] = true
	check(outer_points >= 30, "New neighborhoods supply real order endpoints beyond the old map")
	check(served_districts.size() >= 6, "Orders reach every urban district")

func test_driving_across_old_boundary() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var definitions: Dictionary = VehicleCatalog.load_definitions()
	for vehicle_id: String in ["bicycle", "scooter", "car"]:
		var vehicle = VehicleScript.new()
		vehicle.configure(definitions[vehicle_id])
		root.add_child(vehicle)
		vehicle.reset_at(Vector3(0.0, 0.15, 82.0), PI)
		vehicle.set_occupied(true)
		vehicle.set_controls_enabled(true)
		Input.action_press("move_forward")
		for frame: int in range(120):
			await physics_frame
			# Production controller and real physics run unchanged; pacing is test-only.
			OS.delay_msec(17)
		Input.action_release("move_forward")
		check(vehicle.global_position.is_finite() and vehicle.global_position.z > 90.0, "%s can drive along real asphalt beyond the former 84 m boundary" % vehicle_id)
		check(vehicle.speed > 1.0 and vehicle.global_position.y > -1.0, "%s retains motion and ground contact in the new district" % vehicle_id)
		vehicle.set_controls_enabled(false)
		vehicle.set_occupied(false)
		vehicle.queue_free()
		await process_frame
		await physics_frame

func test_map_projection() -> void:
	var layout: Dictionary = city.get_map_layout()
	var bounds: Rect2 = layout["bounds"]
	var hud = HudScript.new()
	root.add_child(hud)
	await process_frame
	hud.set_map_layout(layout)
	check(hud._full_map._view_bounds() == bounds, "M map preserves the complete 516 m city extent")
	for position: Vector3 in [Vector3(-245, 0, -245), Vector3(245, 0, -245), Vector3(-245, 0, 245), Vector3(245, 0, 245), Vector3.ZERO]:
		hud._mini_map.update_positions(position, Vector3.ZERO, false)
		var visible: Rect2 = hud._mini_map._view_bounds()
		check(visible.size == Vector2(128.0, 128.0), "Minimap keeps a readable neighborhood scale instead of shrinking the enlarged city")
		check(bounds.encloses(visible) and visible.has_point(Vector2(position.x, position.z)), "Minimap keeps the player and visible streets inside the city at every edge")
		var player_point: Vector2 = hud._mini_map._point(position)
		check(hud._mini_map._map_rect().has_point(player_point), "Player marker stays inside the minimap viewport at the city edge")
	for district: Dictionary in layout.get("districts", []):
		var center: Vector2 = district["rect"].get_center()
		hud._mini_map.update_positions(Vector3(center.x, 0, center.y), Vector3.ZERO, false)
		check(hud._mini_map.current_district() == str(district["name"]), "Minimap identifies the player's current district")
	hud.queue_free()
	await process_frame
