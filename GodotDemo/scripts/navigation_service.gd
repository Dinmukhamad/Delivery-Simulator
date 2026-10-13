extends RefCounted

# Local guidance only. Orders, movement and rewards remain authoritative elsewhere.
# Static footprints are shared by routing and by both map views.
# Buckets contain only static rectangle indices. Long road edges inspect the
# buckets they cross; a HUD update never scans every building in the city.
class RectangleIndex extends RefCounted:
	const BUCKET_SIZE: float = 16.0
	var rectangles: Array[Rect2] = []
	var buckets: Dictionary = {}

	func configure(source: Array[Rect2]) -> void:
		rectangles = source
		buckets.clear()
		for index: int in range(rectangles.size()):
			var box: Rect2 = rectangles[index]
			var first: Vector2i = cell(box.position)
			var last: Vector2i = cell(box.end)
			for y: int in range(first.y, last.y + 1):
				for x: int in range(first.x, last.x + 1):
					var key: Vector2i = Vector2i(x, y)
					if not buckets.has(key):
						buckets[key] = []
					buckets[key].append(index)

	func cell(point: Vector2) -> Vector2i:
		return Vector2i(floori(point.x / BUCKET_SIZE), floori(point.y / BUCKET_SIZE))

	func contains(point: Vector2) -> bool:
		for index: int in buckets.get(cell(point), []):
			if rectangles[index].has_point(point):
				return true
		return false

	# AStar edges are short. Checking a rectangle twice in adjacent buckets is
	# cheaper than allocating candidate arrays and dictionaries for every edge.
	func segment_hits(a: Vector2, b: Vector2) -> bool:
		var first: Vector2i = cell(Vector2(minf(a.x, b.x), minf(a.y, b.y)))
		var last: Vector2i = cell(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)))
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				for index: int in buckets.get(Vector2i(x, y), []):
					var box: Rect2 = rectangles[index]
					var direction: Vector2 = b - a
					var entry: float = 0.0
					var exit_value: float = 1.0
					var hit: bool = true
					for axis: int in range(2):
						if absf(direction[axis]) < 0.00001:
							if a[axis] < box.position[axis] or a[axis] > box.end[axis]:
								hit = false
								break
						else:
							var low: float = (box.position[axis] - a[axis]) / direction[axis]
							var high: float = (box.end[axis] - a[axis]) / direction[axis]
							entry = maxf(entry, minf(low, high))
							exit_value = minf(exit_value, maxf(low, high))
							if entry > exit_value:
								hit = false
								break
					if hit:
						return true
		return false

	func candidates(a: Vector2, b: Vector2) -> Array[Rect2]:
		var result: Array[Rect2] = []
		var visited: Dictionary = {}
		var first: Vector2i = cell(Vector2(minf(a.x, b.x), minf(a.y, b.y)))
		var last: Vector2i = cell(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)))
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				for index: int in buckets.get(Vector2i(x, y), []):
					if not visited.has(index):
						visited[index] = true
						result.append(rectangles[index])
		return result

class SafeGrid extends AStarGrid2D:
	var blocks: Array[Rect2] = []
	var roads: Array[Rect2] = []
	var road_only: bool = false
	var safe_bounds: Rect2
	var block_index: RectangleIndex = RectangleIndex.new()
	var road_index: RectangleIndex = RectangleIndex.new()

	static func interval(a: Vector2, b: Vector2, box: Rect2) -> Vector2:
		var direction: Vector2 = b - a
		var first: float = 0.0
		var last: float = 1.0
		for axis: int in range(2):
			if absf(direction[axis]) < 0.00001:
				if a[axis] < box.position[axis] or a[axis] > box.end[axis]:
					return Vector2(1.0, -1.0)
			else:
				var entry: float = (box.position[axis] - a[axis]) / direction[axis]
				var exit_value: float = (box.end[axis] - a[axis]) / direction[axis]
				first = maxf(first, minf(entry, exit_value))
				last = minf(last, maxf(entry, exit_value))
				if first > last:
					return Vector2(1.0, -1.0)
		return Vector2(first, last)

	static func covered(a: Vector2, b: Vector2, areas: Array[Rect2]) -> bool:
		var pieces: Array[Vector2] = []
		for area: Rect2 in areas:
			var part: Vector2 = interval(a, b, area)
			if part.x <= 0.00001 and part.y >= 0.99999:
				return true
			if part.x <= part.y:
				pieces.append(part)
		pieces.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
		var cursor: float = 0.0
		for part: Vector2 in pieces:
			if part.x > cursor + 0.00001:
				return false
			cursor = maxf(cursor, part.y)
			if cursor >= 0.99999:
				return true
		return false

	func segment_clear(a: Vector2, b: Vector2) -> bool:
		if not safe_bounds.has_point(a) or not safe_bounds.has_point(b):
			return false
		return not block_index.segment_hits(a, b)

	func allowed(a: Vector2, b: Vector2) -> bool:
		return segment_clear(a, b) and (not road_only or covered(a, b, road_index.candidates(a, b)))

	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		var a: Vector2 = get_point_position(from_id)
		var b: Vector2 = get_point_position(to_id)
		return a.distance_to(b) if allowed(a, b) else INF

	func _estimate_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		return get_point_position(from_id).distance_to(get_point_position(to_id))

var _layout: Dictionary = {}
var _profiles: Dictionary = {}
var _road_index: RectangleIndex = RectangleIndex.new()
var _profile_build_msec: Dictionary = {}
var _cached: Dictionary = {}
var _key: String = ""
var _mode: String = ""
var _last_query: int = -10000
var query_count: int = 0

func configure(layout: Dictionary) -> void:
	_layout = layout.duplicate(true)
	_profiles.clear()
	_profile_build_msec.clear()
	var original_roads: Array[Rect2] = []
	original_roads.assign(_layout.get("roads", []))
	_road_index.configure(original_roads)
	clear()

func clear() -> void:
	_cached.clear()
	_key = ""
	_mode = ""
	_last_query = -10000

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func _world(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)

# Rasterize rectangle centres with native grid operations. A metre-wide grid
# remains accurate after enlarging the map; it does not perform a GDScript
# obstacle/road scan for each of the 260,000 city cells.
func _cell_region(box: Rect2, grid: SafeGrid, inclusive_end: bool = false) -> Rect2i:
	var first: Vector2i = Vector2i(
		ceili((box.position.x - grid.offset.x) / grid.cell_size.x),
		ceili((box.position.y - grid.offset.y) / grid.cell_size.y))
	var epsilon: float = 0.0 if inclusive_end else 0.00001
	var last: Vector2i = Vector2i(
		floori((box.end.x - epsilon - grid.offset.x) / grid.cell_size.x),
		floori((box.end.y - epsilon - grid.offset.y) / grid.cell_size.y))
	var region: Rect2i = Rect2i(first, Vector2i(maxi(0, last.x - first.x + 1), maxi(0, last.y - first.y + 1)))
	return region.intersection(grid.region)

func _profile(mode: String) -> SafeGrid:
	if _profiles.has(mode):
		return _profiles[mode]
	var began: int = Time.get_ticks_msec()
	var grid: SafeGrid = SafeGrid.new()
	# Playable limits exclude the border colliders; fixtures only need bounds.
	var bounds: Rect2 = _layout.get("playable_bounds", _layout.get("bounds", Rect2()))
	var clearance: float = 2.3 if mode == "car" else (0.65 if mode == "scooter" else (0.5 if mode == "bicycle" else 0.4))
	grid.safe_bounds = bounds.grow(-clearance)
	grid.road_only = mode in ["car", "scooter"]
	for obstacle: Rect2 in _layout.get("obstacles", []):
		grid.blocks.append(obstacle.grow(clearance))
	for road: Rect2 in _layout.get("roads", []):
		var inside: Rect2 = road.grow(-clearance)
		if inside.size.x > 0.0 and inside.size.y > 0.0:
			grid.roads.append(inside)
	grid.block_index.configure(grid.blocks)
	grid.road_index.configure(grid.roads)
	# Door approaches are two metres wide. Their resolution must not degrade
	# as city bounds grow. Motor traffic only needs the wider road network.
	var step: float = 2.0 if grid.road_only and maxf(bounds.size.x, bounds.size.y) > 300.0 else 1.0
	var dimensions: Vector2i = Vector2i(maxi(1, ceili(bounds.size.x / step)), maxi(1, ceili(bounds.size.y / step)))
	grid.region = Rect2i(Vector2i.ZERO, dimensions)
	grid.cell_size = Vector2(bounds.size.x / dimensions.x, bounds.size.y / dimensions.y)
	grid.offset = bounds.position + grid.cell_size * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.jumping_enabled = false
	grid.update()
	grid.fill_solid_region(grid.region, true)
	if grid.road_only:
		for road: Rect2 in grid.roads:
			grid.fill_solid_region(_cell_region(road.intersection(grid.safe_bounds), grid), false)
	else:
		grid.fill_solid_region(_cell_region(grid.safe_bounds, grid), false)
		grid.fill_weight_scale_region(grid.region, 3.0)
		for path: Rect2 in _layout.get("paths", []):
			grid.fill_weight_scale_region(_cell_region(path, grid), 1.0)
		for road: Rect2 in _layout.get("roads", []):
			grid.fill_weight_scale_region(_cell_region(road, grid), 1.15)
	for block: Rect2 in grid.blocks:
		grid.fill_solid_region(_cell_region(block, grid, true), true)
	_profiles[mode] = grid
	_profile_build_msec[mode] = Time.get_ticks_msec() - began
	return grid

func diagnostics() -> Dictionary:
	var cells: Dictionary = {}
	for mode: String in _profiles:
		var grid: SafeGrid = _profiles[mode]
		cells[mode] = grid.region.size.x * grid.region.size.y
	return {"profiles": _profiles.size(), "grid_cells": cells, "profile_build_msec": _profile_build_msec.duplicate(), "guidance_queries": query_count}

func _anchor(point: Vector2, grid: SafeGrid, connector: SafeGrid = null) -> Vector2i:
	if connector == null:
		connector = grid
	var road_point: bool = _road_index.contains(point)
	var limit: float = 24.0 if grid.road_only else 5.0
	var center: Vector2i = Vector2i(((point - grid.offset) / grid.cell_size).round())
	var radius: int = ceili(limit / minf(grid.cell_size.x, grid.cell_size.y)) + 1
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = limit * limit
	for y: int in range(maxi(0, center.y - radius), mini(grid.region.size.y, center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(grid.region.size.x, center.x + radius + 1)):
			var id: Vector2i = Vector2i(x, y)
			if grid.is_point_solid(id):
				continue
			var candidate: Vector2 = grid.get_point_position(id)
			var distance: float = point.distance_squared_to(candidate)
			if distance >= best_distance or not connector.segment_clear(point, candidate):
				continue
			if grid.road_only and road_point and not SafeGrid.covered(point, candidate, _road_index.candidates(point, candidate)):
				continue
			best = id
			best_distance = distance
	return best

func route(start: Vector3, target: Vector3, mode: String = "walking") -> Dictionary:
	var empty: Array[Vector3] = []
	var bounds: Rect2 = _layout.get("playable_bounds", _layout.get("bounds", Rect2()))
	if _layout.is_empty() or bounds.size.x <= 1.0 or bounds.size.y <= 1.0 or not start.is_finite() or not target.is_finite():
		return {"points": empty, "distance": 0.0, "status": "no_route", "walk_last": false}
	var grid: SafeGrid = _profile(mode)
	var a: Vector2 = _xz(start)
	var b: Vector2 = _xz(target)
	# A motor route stops on the road; its final access to an off-road door
	# uses courier clearance rather than requiring the car to fit by the door.
	var target_grid: SafeGrid = _profile("walking") if grid.road_only and not _road_index.contains(b) else grid
	if not grid.segment_clear(a, a) or not target_grid.segment_clear(b, b):
		return {"points": empty, "distance": 0.0, "status": "no_route", "walk_last": false}
	if a.distance_to(b) < 0.1:
		var arrived: Array[Vector3] = [_world(b)]
		return {"points": arrived, "distance": 0.0, "status": "arrived", "walk_last": false}
	var from_id: Vector2i = _anchor(a, grid)
	var to_id: Vector2i = _anchor(b, grid, target_grid)
	if from_id.x < 0 or to_id.x < 0:
		return {"points": empty, "distance": 0.0, "status": "no_route", "walk_last": false}
	var ids: Array[Vector2i] = grid.get_id_path(from_id, to_id, false)
	if ids.is_empty():
		return {"points": empty, "distance": 0.0, "status": "no_route", "walk_last": false}
	var points: Array[Vector3] = [_world(a)]
	var previous: Vector2 = grid.get_point_position(ids[0])
	for id: Vector2i in ids:
		var point: Vector2 = grid.get_point_position(id)
		if not grid.allowed(previous, point):
			return {"points": empty, "distance": 0.0, "status": "no_route", "walk_last": false}
		var next: Vector3 = _world(point)
		if points[-1].distance_to(next) > 0.01:
			points.append(next)
		previous = point
	var access: Vector3 = _world(grid.get_point_position(to_id))
	if points[-1].distance_to(_world(b)) > 0.01:
		points.append(_world(b))
	points = _simplify(points, grid)
	var walk_last: bool = grid.road_only and not SafeGrid.covered(_xz(access), b, _road_index.candidates(_xz(access), b))
	return {"points": points, "distance": _length(points), "status": "ok", "walk_last": walk_last, "access": access}

func _simplify(source: Array[Vector3], grid: SafeGrid) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in source:
		result.append(point)
		while result.size() >= 3:
			var last: int = result.size() - 1
			var a: Vector2 = _xz(result[last - 2])
			var b: Vector2 = _xz(result[last - 1])
			var c: Vector2 = _xz(result[last])
			var first: Vector2 = b - a
			var second: Vector2 = c - b
			if first.dot(second) < 0.0 or absf(first.cross(second)) > 0.0001:
				break
			if not grid.segment_clear(a, c):
				break
			# Keep endpoint access legs separate from the road-only middle.
			if grid.road_only and not SafeGrid.covered(a, c, grid.road_index.candidates(a, c)):
				break
			result.remove_at(last - 1)
	return result

func _length(points: Array[Vector3]) -> float:
	var distance: float = 0.0
	for i: int in range(1, points.size()):
		distance += points[i - 1].distance_to(points[i])
	return distance

func _projection(position: Vector3, points: Array[Vector3]) -> Dictionary:
	var best: Dictionary = {"distance": INF, "index": 0, "point": position}
	for i: int in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var delta: Vector3 = b - a
		var progress: float = clampf((position - a).dot(delta) / maxf(delta.length_squared(), 0.00001), 0.0, 1.0)
		var point: Vector3 = a + delta * progress
		var distance: float = position.distance_to(point)
		if distance < float(best["distance"]):
			best = {"distance": distance, "index": i, "point": point}
	return best

func guidance(position: Vector3, target: Vector3, key: String, mode: String) -> Dictionary:
	if key.is_empty():
		clear()
		return {"points": [], "distance": 0.0, "status": "idle", "hint": "", "walk_last": false}
	position.y = 0.0
	target.y = 0.0
	var now: int = Time.get_ticks_msec()
	var changed: bool = key != _key or mode != _mode
	var needs_query: bool = changed or _cached.is_empty()
	var old_points: Array[Vector3] = []
	old_points.assign(_cached.get("points", []))
	if old_points.size() > 1:
		var old_nearest: Dictionary = _projection(position, old_points)
		needs_query = needs_query or float(old_nearest["distance"]) > (6.0 if mode in ["car", "scooter"] else 3.0)
		needs_query = needs_query or not _profile(mode).segment_clear(_xz(position), _xz(old_nearest["point"]))
	elif not _cached.is_empty():
		needs_query = needs_query or position.distance_to(target) > 0.5
	if needs_query and (changed or now - _last_query >= 400):
		_cached = route(position, target, mode)
		_key = key
		_mode = mode
		_last_query = now
		query_count += 1
	var points: Array[Vector3] = []
	points.assign(_cached.get("points", []))
	if points.is_empty():
		return {"points": [], "distance": 0.0, "status": "no_route", "hint": "Путь не найден · выберите другую улицу", "walk_last": false}
	var trimmed: Array[Vector3] = [position]
	if points.size() > 1:
		var nearest: Dictionary = _projection(position, points)
		if not _profile(mode).segment_clear(_xz(position), _xz(nearest["point"])):
			return {"points": [], "distance": 0.0, "status": "recalculating", "hint": "Перестраиваем маршрут…", "walk_last": false}
		if position.distance_to(nearest["point"]) > 0.1:
			trimmed.append(nearest["point"])
		for i: int in range(int(nearest["index"]) + 1, points.size()):
			if trimmed[-1].distance_to(points[i]) > 0.1:
				trimmed.append(points[i])
	var hint: String = _turn_hint(trimmed)
	if position.distance_to(target) <= 3.0:
		hint = "Вы у точки · E — действие" if not mode in ["car", "scooter", "bicycle"] else "Остановитесь · F — выйти, затем E"
	elif bool(_cached.get("walk_last", false)):
		hint += " · от дороги до входа — пешком"
	return {"points": trimmed, "distance": _length(trimmed), "status": "ok", "hint": hint, "walk_last": bool(_cached.get("walk_last", false)), "access": _cached.get("access", target)}

func _turn_hint(points: Array[Vector3]) -> String:
	var distance: float = 0.0
	for i: int in range(1, points.size() - 1):
		var first: Vector2 = _xz(points[i] - points[i - 1])
		var second: Vector2 = _xz(points[i + 1] - points[i])
		distance += first.length()
		if first.length() < 1.5 or second.length() < 1.5:
			continue
		var angle: float = first.angle_to(second)
		if absf(angle) >= 0.6:
			return "Через %d м — %s" % [maxi(1, roundi(distance)), "направо" if angle > 0.0 else "налево"]
	return "Следуйте по выделенному маршруту"
