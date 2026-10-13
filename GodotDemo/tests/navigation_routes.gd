extends SceneTree

const Navigation = preload("res://scripts/navigation_service.gd")
const CityLayout = preload("res://scripts/city_layout.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func fixture(roads: Array = [], paths: Array = [], obstacles: Array = [], bounds: Rect2 = Rect2(-30, -30, 60, 60)) -> Dictionary:
	return {"bounds": bounds, "roads": roads, "paths": paths, "obstacles": obstacles}

func intersects(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i: int in range(4):
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false

func safe_route(result: Dictionary, obstacles: Array, padding: float) -> bool:
	var points: Array = result.get("points", [])
	if points.is_empty():
		return false
	for i: int in range(1, points.size()):
		var a: Vector2 = Vector2(points[i - 1].x, points[i - 1].z)
		var b: Vector2 = Vector2(points[i].x, points[i].z)
		for obstacle: Rect2 in obstacles:
			if intersects(a, b, obstacle.grow(padding)):
				return false
	return true

func road_route(result: Dictionary, roads: Array) -> bool:
	var points: Array = result.get("points", [])
	for i: int in range(1, points.size()):
		var count: int = maxi(1, ceili(points[i - 1].distance_to(points[i]) / 0.2))
		for sample: int in range(count + 1):
			var point: Vector3 = points[i - 1].lerp(points[i], float(sample) / count)
			var inside: bool = false
			for road: Rect2 in roads:
				inside = inside or road.has_point(Vector2(point.x, point.z))
			if not inside:
				return false
	return not points.is_empty()


func route_in_bounds(result: Dictionary, bounds: Rect2) -> bool:
	var points: Array = result.get("points", [])
	for point: Vector3 in points:
		if not bounds.has_point(Vector2(point.x, point.z)):
			return false
	return not points.is_empty()

func motor_middle(result: Dictionary, roads: Array, obstacles: Array, clearance: float) -> bool:
	# First connector reaches the street. Last connector is explicitly on foot.
	# Every intervening segment must stay on asphalt and avoid motor obstacles.
	var points: Array = result.get("points", [])
	if points.size() < 3:
		return false
	var middle: Array = points.slice(1, points.size() - 1)
	return road_route({"points": middle}, roads) and safe_route({"points": middle}, obstacles, clearance)

func _large_city_routes(layout: Dictionary) -> void:
	var nav = Navigation.new()
	nav.configure(layout)
	var bounds: Rect2 = layout["bounds"]
	var playable: Rect2 = layout["playable_bounds"]
	check(bounds.size.is_equal_approx(Vector2(516, 516)), "City width and depth are three times the original 172 m")
	check(playable.size.x > 500.0 and playable.size.y > 500.0, "Navigation uses the expanded playable bounds")
	var started: int = Time.get_ticks_msec()
	var origin: Vector3 = Vector3(-60, 0, 40)
	var addresses: Array = []
	addresses.append_array(layout["pickups"])
	addresses.append_array(layout["deliveries"])
	check(layout["pickups"].size() >= 12 and layout["deliveries"].size() >= 40, "Expanded districts have functioning pickup and delivery addresses")
	for index: int in range(addresses.size()):
		var address: Dictionary = addresses[index]
		var target: Vector3 = address["position"]
		var result: Dictionary = nav.route(origin, target, "walking")
		var label: String = str(address.get("name", index))
		check(result["status"] in ["ok", "arrived"], "Courier can reach city address: " + label)
		check(safe_route(result, layout["obstacles"], 0.35), "No route crosses a building on the way to: " + label)
		check(route_in_bounds(result, playable), "Address route stays inside the expanded city: " + label)
		if not result["points"].is_empty():
			check(result["points"][-1].is_equal_approx(target), "Address route reaches its exact pickup/delivery marker: " + label)
		if index % 20 == 0:
			print("LARGE_CITY_NAVIGATION_PROGRESS: %d/%d addresses" % [index + 1, addresses.size()])
	# Real street corners bracket both parks and the old centre. Different
	# clearances and road-only modes are tested against the identical geometry.
	for mode: String in ["walking", "bicycle", "scooter", "car"]:
		var across: Dictionary = nav.route(Vector3(-240, 0, -240), Vector3(240, 0, 240), mode)
		check(across["status"] == "ok", mode + " can cross the complete 516 m city")
		check(route_in_bounds(across, playable), mode + " cross-city route respects borders")
		var padding: float = 2.25 if mode == "car" else (0.6 if mode == "scooter" else (0.45 if mode == "bicycle" else 0.35))
		check(safe_route(across, layout["obstacles"], padding), mode + " cross-city route keeps vehicle clearance")
		check(float(across["distance"]) >= Vector3(-240, 0, -240).distance_to(Vector3(240, 0, 240)), mode + " reports physical route distance")
		if mode in ["scooter", "car"]:
			check(road_route(across, layout["roads"]), mode + " stays on actual streets instead of cutting through a park")
		# Every district's address must have a safe, short street access. Check
		# anchors directly for all addresses, plus full routes at regular intervals.
		if mode in ["scooter", "car"]:
			var grid = nav._profile(mode)
			var foot_grid = nav._profile("walking")
			for index: int in range(addresses.size()):
				var target: Vector3 = addresses[index]["position"]
				var id: Vector2i = nav._anchor(Vector2(target.x, target.z), grid, foot_grid)
				var label: String = str(addresses[index].get("name", index))
				check(id.x >= 0, mode + " has a safe street access within 24 m: " + label)
				if id.x >= 0:
					var access: Vector2 = grid.get_point_position(id)
					check(access.distance_to(Vector2(target.x, target.z)) <= 24.0, mode + " avoids a long off-road motor connector: " + label)
				if index % 8 == 0:
					var destination: Dictionary = nav.route(origin, target, mode)
					check(destination["status"] in ["ok", "arrived"], mode + " can drive to district address: " + label)
					check(safe_route(destination, layout["obstacles"], 0.35), mode + " final walking access is clear: " + label)
					check(motor_middle(destination, layout["roads"], layout["obstacles"], padding), mode + " district route middle stays on streets: " + label)
		elif mode == "bicycle":
			for index: int in range(0, addresses.size(), 8):
				var target: Vector3 = addresses[index]["position"]
				var destination: Dictionary = nav.route(origin, target, mode)
				check(destination["status"] in ["ok", "arrived"], "Bicycle can reach representative district address %d" % index)
				check(safe_route(destination, layout["obstacles"], 0.45), "Bicycle district access maintains clearance %d" % index)
	var walking_grid = nav._profile("walking")
	check(walking_grid.cell_size.x <= 1.0 and walking_grid.cell_size.y <= 1.0, "Larger map preserves metre-resolution narrow door passages")
	var first: Vector2i = Vector2i(10, 10)
	var last: Vector2i = Vector2i(20, 20)
	check(is_equal_approx(walking_grid._estimate_cost(first, last), walking_grid.get_point_position(first).distance_to(walking_grid.get_point_position(last))), "AStar heuristic remains physical distance after map enlargement")
	var cache_key: String = "large-city:Accepted"
	var target: Vector3 = Vector3(240, 0, 240)
	nav.guidance(Vector3(-240, 0, -240), target, cache_key, "walking")
	var queries: int = nav.query_count
	var profile_count: int = nav.diagnostics()["profiles"]
	for frame: int in range(120):
		nav.guidance(Vector3(-240, 0, -240), target, cache_key, "walking")
	check(nav.query_count == queries, "A full city route is cached across 120 stationary HUD frames")
	check(nav.diagnostics()["profiles"] == profile_count, "HUD frames reuse already-built static navigation profiles")
	check(nav.route(origin, Vector3(260, 0, 0))["status"] == "no_route", "Expanded city rejects a target beyond its boundary")
	check(nav.route(Vector3(-260, 0, 0), origin)["status"] == "no_route", "Expanded city rejects a start beyond its boundary")
	print("LARGE_CITY_NAVIGATION_METRICS: elapsed_ms=%d diagnostics=%s" % [Time.get_ticks_msec() - started, JSON.stringify(nav.diagnostics())])
	# Keep regression coverage for a narrow corridor with the full city extent.
	var walls: Array = [Rect2(-258, -258, 516, 258.17), Rect2(-258, 2.17, 516, 255.83)]
	nav.configure(fixture([], [], walls, Rect2(-258, -258, 516, 516)))
	var passage: Dictionary = nav.route(Vector3(-200, 0, 1.17), Vector3(200, 0, 1.17))
	check(passage["status"] == "ok", "A shifted 2 m passage remains reachable on a 516 m map")
	check(safe_route(passage, walls, 0.35), "Large-map narrow passage has no unsafe connector")
	nav.configure(fixture([], [], [Rect2(-1, -258, 2, 516)], Rect2(-258, -258, 516, 516)))
	var blocked: Dictionary = nav.route(Vector3(-20, 0, 0), Vector3(20, 0, 0))
	check(blocked["status"] == "no_route" and blocked["points"].is_empty(), "A full-height wall never yields a straight-line fallback on a large map")

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		printerr("Tests require --test-mode; refusing to access a real profile.")
		quit(2)
		return
	var nav = Navigation.new()
	var building: Rect2 = Rect2(-8, -8, 16, 16)
	nav.configure(fixture([], [], [building]))
	var route: Dictionary = nav.route(Vector3(-20, 0, 0), Vector3(20, 0, 0))
	check(route["status"] == "ok", "A route around a central building exists")
	check(float(route["distance"]) > 43.0, "Building detour is longer than the direct line")
	check(safe_route(route, [building], 0.35), "Every segment avoids the expanded building")
	check(route["points"][-1].is_equal_approx(Vector3(20, 0, 0)), "Route reaches its exact target")
	var roads: Array = [Rect2(-24, -24, 8, 48), Rect2(-24, 16, 48, 8), Rect2(16, -24, 8, 48)]
	var shortcut: Array = [Rect2(-24, -2, 48, 4)]
	nav.configure(fixture(roads, shortcut))
	var walking: Dictionary = nav.route(Vector3(-20, 0, -20), Vector3(20, 0, -20), "walking")
	var bicycle: Dictionary = nav.route(Vector3(-20, 0, -20), Vector3(20, 0, -20), "bicycle")
	var car: Dictionary = nav.route(Vector3(-20, 0, -20), Vector3(20, 0, -20), "car")
	check(walking["status"] == "ok" and car["status"] == "ok", "Walking and driving can reach U-road destination")
	check(float(walking["distance"]) + 15.0 < float(car["distance"]), "Walking shortcut differs from road-only driving")
	check(float(bicycle["distance"]) + 15.0 < float(car["distance"]), "Bicycle can use the pedestrian shortcut")
	check(road_route(car, roads), "Car middle route is continuously on actual roads")
	var separate: Array = [Rect2(-25, -4, 20, 8), Rect2(5, -4, 20, 8)]
	nav.configure(fixture(separate))
	var disconnected: Dictionary = nav.route(Vector3(-15, 0, 0), Vector3(15, 0, 0), "car")
	check(disconnected["status"] == "no_route" and disconnected["points"].is_empty(), "Disconnected roads never produce a direct-line fallback")
	nav.configure(fixture([], [], [building]))
	check(nav.route(Vector3(-20, 0, 0), Vector3.ZERO)["points"].is_empty(), "An address inside a building has no fake path")
	var walls: Array = [Rect2(-15, -15, 30, 15.17), Rect2(-15, 2.17, 30, 12.83)]
	nav.configure(fixture([], [], walls, Rect2(-15, -15, 30, 30)))
	var narrow: Dictionary = nav.route(Vector3(-10, 0, 1.17), Vector3(10, 0, 1.17))
	check(narrow["status"] == "ok", "A shifted two-metre passage stays navigable")
	check(safe_route(narrow, walls, 0.35), "Narrow-passage connectors also avoid walls")
	nav.configure(fixture([], [], [building]))
	var first: Dictionary = nav.guidance(Vector3(-20, 0, 0), Vector3(20, 0, 0), "1:Accepted", "walking")
	var queries: int = nav.query_count
	for i: int in range(20):
		nav.guidance(Vector3(-20, 0, 0), Vector3(20, 0, 0), "1:Accepted", "walking")
	check(nav.query_count == queries, "Standing still never runs AStar every frame")
	var wait_until: int = Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < wait_until:
		await process_frame
	var off_route: Dictionary = nav.guidance(Vector3(-26, 0, 26), Vector3(20, 0, 0), "1:Accepted", "walking")
	check(nav.query_count == queries + 1, "Leaving the route rebuilds it")
	var switched: Dictionary = nav.guidance(Vector3(-20, 0, 20), Vector3(-20, 0, -20), "1:PickedUp", "walking")
	check(switched["points"][-1].is_equal_approx(Vector3(-20, 0, -20)), "Confirmed pickup switches the exact destination")
	check(nav.guidance(Vector3.ZERO, Vector3.ZERO, "", "walking")["points"].is_empty(), "No active order clears navigation")
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	app._play_solo()
	app._close_modal()
	var layout: Dictionary = app.city.get_map_layout()
	check(layout["roads"].size() >= 26, "Map records expanded streets and clipped park road segments")
	check(layout["buildings"].size() >= 80, "Map records the existing centre and substantial new districts")
	check(layout["obstacles"].size() >= layout["buildings"].size() + 4, "Routing includes every building and boundary collision")
	_large_city_routes(layout)
	var money: int = int(app.profile["money"])
	var order_id: int = int(app.orders[0]["id"])
	app._accept_order(order_id)
	check(app.active_order.get("state") == "Accepted", "Solo order is accepted")
	check(not app.hud._mini_map.route_points.is_empty(), "Accepted order has a mini-map route")
	check(app.hud._mini_map.route_points == app.hud._full_map.route_points, "Both maps receive identical route points")
	check(safe_route({"points": app.hud._mini_map.route_points}, layout["obstacles"], 0.35), "Actual city route avoids all building footprints")
	app.player.global_position = app._target_position() + Vector3.UP * 0.15
	await physics_frame
	await process_frame
	app._interact()
	check(app.active_order.get("state") == "PickedUp", "Pickup is still controlled by real interaction rules")
	check(app.hud._full_map.target_position.is_equal_approx(app.active_order["delivery_position"]), "HUD marker switches to delivery")
	check(app.hud._full_map.target_picked, "Delivery marker changes colour after pickup")
	check(app.hud._navigation_hint.visible and not app.hud._navigation_hint.text.is_empty(), "HUD shows navigation instructions")
	check(safe_route({"points": app.hud._full_map.route_points}, layout["obstacles"], 0.35), "Actual delivery route avoids buildings")
	app._open_map()
	check(app.hud._map.visible, "M-map overlay opens")
	check(app.hud._full_map.route_points == app.hud._mini_map.route_points, "Opening M retains the active route")
	app._close_modal()
	app.player.global_position = app._target_position() + Vector3.UP * 0.15
	await physics_frame
	await process_frame
	app._interact()
	check(app.active_order.is_empty(), "Delivery completes normally")
	check(int(app.profile["money"]) > money and int(app.profile["xp"]) > 0, "Delivery still awards Money and XP")
	check(app.hud._mini_map.route_points.is_empty() and app.hud._full_map.route_points.is_empty(), "Delivered order clears both maps")
	check(app.test_mode, "Tests use an isolated profile")
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("NAVIGATION_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
