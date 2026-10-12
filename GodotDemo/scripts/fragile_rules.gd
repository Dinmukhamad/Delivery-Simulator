extends RefCounted


const DEFAULT_LEVEL: = 5
const DEFAULT_QUALITY_BONUS: = 100
const DEFAULT_IMPACT_THRESHOLD: = 4.0
const DEFAULT_IMPACT_COOLDOWN_MSEC: = 1000
const DEFAULT_DAMAGE_PER_MPS: = 4.0


static func required_level(balance: Dictionary) -> int:
	return maxi(1, int(_number(balance, "fragile_required_level", DEFAULT_LEVEL)))


static func initial_fields(balance: Dictionary) -> Dictionary:
	var maximum: int = maxi(0, roundi(_number(balance, "fragile_quality_bonus", DEFAULT_QUALITY_BONUS)))
	return {"quality": 100.0, "quality_bonus_max": maximum, "quality_bonus": maximum, "last_impact_msec": -1}


static func quality_bonus(order: Dictionary) -> int:
	var maximum: float = maxf(0.0, _number(order, "quality_bonus_max", DEFAULT_QUALITY_BONUS))
	var quality: float = clampf(_number(order, "quality", 100.0), 0.0, 100.0)
	return roundi(maximum * quality / 100.0)


static func apply_impact(order: Dictionary, normal_speed: float, now_msec: int, balance: Dictionary) -> bool:
	if str(order.get("type", "")) != "fragile" or str(order.get("state", "")) != "PickedUp":
		return false
	if not is_finite(normal_speed) or now_msec < 0:
		return false
	var threshold: float = maxf(0.0, _number(balance, "fragile_impact_threshold", DEFAULT_IMPACT_THRESHOLD))
	if normal_speed < threshold or normal_speed <= 0.0:
		return false
	var previous: int = int(_number(order, "last_impact_msec", -1))
	var cooldown: int = maxi(0, int(_number(balance, "fragile_impact_cooldown_msec", DEFAULT_IMPACT_COOLDOWN_MSEC)))
	if previous >= 0 and now_msec - previous < cooldown:
		return false
	var quality: float = clampf(_number(order, "quality", 100.0), 0.0, 100.0)
	var damage: float = clampf(normal_speed * maxf(0.0, _number(balance, "fragile_damage_per_mps", DEFAULT_DAMAGE_PER_MPS)), 0.0, 100.0)
	if quality <= 0.0 or damage <= 0.0:
		return false
	order["quality"] = maxf(0.0, quality - damage)
	order["quality_bonus"] = quality_bonus(order)
	order["last_impact_msec"] = now_msec
	return true


static func wall_normal(world: Node3D, definition: Dictionary, position: Vector3, yaw: float) -> Vector3:
	if not is_instance_valid(world) or not world.is_inside_tree() or not _finite(position) or not is_finite(yaw):
		return Vector3.ZERO
	var width: float = _number(definition, "collision_width", 0.8)
	var height: float = _number(definition, "collision_height", 1.65)
	var length: float = _number(definition, "collision_length", 2.2)
	if width <= 0.0 or height <= 0.0 or length <= 0.0:
		return Vector3.ZERO
	var shape: = BoxShape3D.new()

	shape.size = Vector3(width + 0.1, height, length + 0.1)
	var query: = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), position + Vector3.UP * height * 0.5)
	query.collision_mask = 1
	query.margin = 0.0
	var space: = world.get_world_3d().direct_space_state

	var ground_query: = PhysicsRayQueryParameters3D.create(Vector3(position.x, 0.5, position.z), Vector3(position.x, -0.2, position.z), 1)
	ground_query.hit_from_inside = true
	var ground: Dictionary = space.intersect_ray(ground_query)
	if not ground.is_empty():
		var ground_position: Vector3 = ground["position"]
		var ground_normal: Vector3 = ground["normal"]
		if absf(ground_position.y) < 0.01 and ground_normal.y > 0.99:
			query.exclude = [ground["rid"]]
	var contact: Dictionary = space.get_rest_info(query)
	if contact.is_empty():
		return Vector3.ZERO
	var collider: Object = instance_from_id(int(contact.get("collider_id", 0)))
	if not collider is StaticBody3D:
		return Vector3.ZERO
	var normal: Vector3 = contact.get("normal", Vector3.ZERO)
	if not _finite(normal) or absf(normal.y) > 0.5:
		return Vector3.ZERO
	var horizontal: = Vector3(normal.x, 0.0, normal.z)
	return horizontal.normalized() if horizontal.length_squared() > 0.01 else Vector3.ZERO


static func _number(values: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = values.get(key, fallback)
	if not value is float and not value is int:
		return fallback
	var number: = float(value)
	return number if is_finite(number) else fallback


static func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
