extends SceneTree

const Navigation = preload("res://scripts/navigation_service.gd")
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
	await create_timer(0.45).timeout
	nav.guidance(Vector3(-20, 0, 20), Vector3(20, 0, 0), "1:Accepted", "walking")
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
	check(layout["roads"].size() == 6, "Map records the city's three streets on each axis")
	check(layout["buildings"].size() == 20, "Map records all twenty actual buildings")
	check(layout["obstacles"].size() >= 24, "Routing includes building and boundary collisions")
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
