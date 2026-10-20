extends RefCounted

const CityLayout = preload("res://scripts/city_layout.gd")


const GARAGE_POSITION: = Vector3(-66.0, 0.0, 10.0)
const GARAGE_DISTANCE: = 5.0
const MAX_FLIGHT_ALTITUDE: = 60.0
const FLOOR_CLEARANCE: = 0.65


static func can_use_garage(position: Vector3, world: Node3D = null) -> bool:
	if not _finite(position) or position.distance_to(GARAGE_POSITION) > GARAGE_DISTANCE:
		return false
	return not is_instance_valid(world) or has_line_of_sight(world, position, GARAGE_POSITION)


static func find_spawn(world: Node3D, origin: Vector3, yaw: float = PI, blocked: Array[Vector3] = [], definition: Dictionary = {}) -> Variant:
	if not _finite(origin) or not is_finite(yaw):
		return null
	var width: float = float(definition.get("collision_width", 0.8))
	var length: float = float(definition.get("collision_length", 2.2))
	var clearance: float = maxf(1.6, Vector2(width, length).length() * 0.5 + 0.45)
	for search_distance: float in [2.2, 3.2, 4.2, 5.2, 6.5, 8.0]:
		for offset_angle: float in [PI / 2.0, - PI / 2.0, 0.0, PI, PI / 4.0, - PI / 4.0, PI * 0.75, - PI * 0.75]:
			var angle: float = yaw + offset_angle
			var footprint: float = absf(sin(offset_angle)) * width * 0.5 + absf(cos(offset_angle)) * length * 0.5
			var distance: float = maxf(search_distance, footprint + 0.85)
			var candidate: Vector3 = origin + Vector3(sin(angle), 0.0, cos(angle)) * distance
			var ground: Variant = grounded_position(world, candidate)
			if not ground is Vector3:
				continue
			var position: Vector3 = ground
			if position_is_free(world, position, yaw, definition) and has_line_of_sight(world, origin, position) and _clear_of_positions(position, blocked, clearance):
				return position
	return null


static func find_exit(world: Node3D, position: Vector3, yaw: float, blocked: Array[Vector3] = [], definition: Dictionary = {}) -> Variant:
	# Ground projection is only safe when the vehicle is already at the floor.
	# Never turn an airborne exit into a teleport to street level.
	if not _finite(position) or not is_finite(yaw) or not is_near_floor(world, position):
		return null

	var width: float = float(definition.get("collision_width", 0.8))
	var length: float = float(definition.get("collision_length", 2.2))
	for offset_angle: float in [PI / 2.0, - PI / 2.0, PI]:
		var angle: float = yaw + offset_angle
		var distance: float = maxf(1.8, (length if is_equal_approx(offset_angle, PI) else width) * 0.5 + 0.85)
		var candidate: Vector3 = position + Vector3(sin(angle), 0.0, cos(angle)) * distance
		var ground: Variant = grounded_position(world, candidate)
		if not ground is Vector3:
			continue
		var feet: Vector3 = ground
		if position_is_free(world, feet, yaw, false) and has_line_of_sight(world, position, feet) and _clear_of_positions(feet, blocked, 0.9):
			return feet
	return null


static func is_near_floor(world: Node3D, position: Vector3) -> bool:
	if not _finite(position) or position.y < -0.01 or position.y > FLOOR_CLEARANCE:
		return false
	var ground: Variant = grounded_position(world, position)
	if not ground is Vector3:
		return false
	var floor_height: float = Vector3(ground).y - 0.1
	return absf(position.y - floor_height) <= FLOOR_CLEARANCE


static func grounded_position(world: Node3D, candidate: Vector3) -> Variant:
	if not is_instance_valid(world) or not world.is_inside_tree() or not _finite(candidate):
		return null
	var from: Vector3 = Vector3(candidate.x, 2.0, candidate.z)
	var to: Vector3 = Vector3(candidate.x, -1.0, candidate.z)
	var query: = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.hit_from_inside = true
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var hit_position: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if hit_position.y > 0.6 or normal.y < 0.8:
		return null
	var feet: Vector3 = hit_position + Vector3.UP * 0.1
	return feet if _inside_bounds(feet) else null


static func position_is_free(world: Node3D, position: Vector3, yaw: float, vehicle: Variant) -> bool:
	var definition: Dictionary = vehicle if vehicle is Dictionary else {}
	var airplane: bool = str(definition.get("id", "")) == "airplane"
	var maximum_height: float = minf(MAX_FLIGHT_ALTITUDE, float(definition.get("max_altitude", MAX_FLIGHT_ALTITUDE))) if airplane else 6.0
	if not _inside_bounds(position, maximum_height) or not is_instance_valid(world) or not world.is_inside_tree() or not is_finite(yaw):
		return false
	if position.y < -0.01:
		return false
	var query: = PhysicsShapeQueryParameters3D.new()
	var is_vehicle: bool = vehicle is Dictionary or (vehicle is bool and vehicle)
	if is_vehicle:
		var shape: = BoxShape3D.new()
		shape.size = Vector3(float(definition.get("collision_width", 0.8)), float(definition.get("collision_height", 1.65)), float(definition.get("collision_length", 2.2)))
		query.shape = shape
		query.transform = Transform3D(Basis(Vector3.UP, yaw), position + Vector3.UP * shape.size.y * 0.5)
	else:
		var shape: = CapsuleShape3D.new()
		shape.radius = 0.36
		shape.height = 2.0
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 1.03)
	query.collision_mask = 1


	query.margin = 0.0 if is_vehicle else 0.01


	var ground_query: = PhysicsRayQueryParameters3D.create(Vector3(position.x, 0.5, position.z), Vector3(position.x, -0.2, position.z), 1)
	ground_query.hit_from_inside = true
	var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ground_query)
	if not ground.is_empty():
		var ground_position: Vector3 = ground["position"]
		var ground_normal: Vector3 = ground["normal"]
		if absf(ground_position.y) < 0.01 and ground_normal.y > 0.99:
			query.exclude = [ground["rid"]]
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


static func flight_path_is_free(world: Node3D, from: Vector3, from_yaw: float, to: Vector3, to_yaw: float, definition: Dictionary) -> bool:
	if str(definition.get("id", "")) != "airplane" or not position_is_free(world, from, from_yaw, definition) or not position_is_free(world, to, to_yaw, definition):
		return false
	var yaw_delta: float = angle_difference(from_yaw, to_yaw)
	var steps: int = maxi(1, ceili(absf(yaw_delta) / 0.04))
	var size: = Vector3(float(definition.get("collision_width", 6.0)), float(definition.get("collision_height", 2.45)), float(definition.get("collision_length", 5.3)))
	var radius: float = Vector2(size.x, size.z).length() * 0.5
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for index: int in range(steps):
		var start_fraction: float = float(index) / steps
		var end_fraction: float = float(index + 1) / steps
		var start: Vector3 = from.lerp(to, start_fraction)
		var finish: Vector3 = from.lerp(to, end_fraction)
		var mid_yaw: float = from_yaw + yaw_delta * (start_fraction + end_fraction) * 0.5
		# This expanded box contains every orientation within the segment; a
		# center ray cannot detect a wing crossing a wall or roof edge.
		var rotation_padding: float = radius * absf(yaw_delta) / steps * 0.5
		var shape: = BoxShape3D.new()
		shape.size = size + Vector3(rotation_padding * 2.0, 0.0, rotation_padding * 2.0)
		var query: = PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(Vector3.UP, mid_yaw), start + Vector3.UP * size.y * 0.5)
		query.motion = finish - start
		query.collision_mask = 1
		query.margin = 0.0
		# The city ground is a separate flat collider. Keep every wall and roof
		# in the sweep, and independently reject all below-ground poses.
		var ground_query: = PhysicsRayQueryParameters3D.create(Vector3(start.x, 0.5, start.z), Vector3(start.x, -0.2, start.z), 1)
		ground_query.hit_from_inside = true
		var ground: Dictionary = space.intersect_ray(ground_query)
		if not ground.is_empty() and absf(Vector3(ground["position"]).y) < 0.01 and Vector3(ground["normal"]).y > 0.99:
			query.exclude = [ground["rid"]]
		if not space.intersect_shape(query, 1).is_empty():
			return false
		var result: PackedFloat32Array = space.cast_motion(query)
		if result.size() < 2 or result[0] < 0.9999:
			return false
	return true


static func has_line_of_sight(world: Node3D, from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(world) or not world.is_inside_tree() or not _finite(from) or not _finite(to):
		return false
	if from.distance_squared_to(to) < 1e-06:
		return true
	var query: = PhysicsRayQueryParameters3D.create(from + Vector3.UP, to + Vector3.UP, 1)
	query.hit_from_inside = true
	return world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func _clear_of_positions(position: Vector3, blocked: Array[Vector3], minimum: float) -> bool:
	for other: Vector3 in blocked:
		if position.distance_to(other) < minimum:
			return false
	return true


static func _inside_bounds(position: Vector3, maximum_height: float = 6.0) -> bool:
	return _finite(position) and CityLayout.contains_position(position) and position.y >= -1.0 and position.y <= maximum_height


static func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
