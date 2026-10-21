extends RefCounted
## Fixed arcade rules shared by Host validation and local presentation.
## Neither a shot request nor a profile can supply damage, aim or a target.

const MAX_HEALTH: int = 100
const DAMAGE: int = 25
const COOLDOWN_MSEC: int = 250
const RANGE: float = 160.0
const MIN_COMBAT_ALTITUDE: float = 2.0
const MUZZLE_HEIGHT: float = 1.25
const MUZZLE_FORWARD: float = 2.8


static func shot_direction(yaw: float) -> Vector3:
	return -Basis(Vector3.UP, yaw).z if is_finite(yaw) else Vector3.ZERO


static func muzzle(position: Vector3, yaw: float) -> Vector3:
	return position + Vector3.UP * MUZZLE_HEIGHT + shot_direction(yaw) * MUZZLE_FORWARD


static func eligible(vehicle: Dictionary) -> bool:
	var position: Variant = vehicle.get("position", null)
	return str(vehicle.get("type", "")) == "airplane" and bool(vehicle.get("occupied", false)) and int(vehicle.get("health", 0)) > 0 and position is Vector3 and finite_vector(position) and position.y >= MIN_COMBAT_ALTITUDE


static func ray_hit_distance(origin: Vector3, direction: Vector3, position: Vector3, yaw: float, definition: Dictionary, maximum_distance: float = RANGE) -> float:
	if not finite_vector(origin) or not finite_vector(direction) or not finite_vector(position) or not is_finite(yaw) or not is_finite(maximum_distance) or maximum_distance <= 0.0 or direction.length_squared() < 0.0001:
		return INF
	var basis: = Basis(Vector3.UP, yaw)
	var local_origin: Vector3 = basis.inverse() * (origin - position)
	var local_direction: Vector3 = basis.inverse() * direction.normalized()
	var width: float = clampf(float(definition.get("collision_width", 6.0)), 0.5, 7.0)
	var height: float = clampf(float(definition.get("collision_height", 2.45)), 0.5, 3.0)
	var length: float = clampf(float(definition.get("collision_length", 5.3)), 0.5, 7.0)
	if not is_finite(width) or not is_finite(height) or not is_finite(length):
		return INF
	var minimum: = Vector3(-width * 0.5, 0.0, -length * 0.5)
	var maximum: = Vector3(width * 0.5, height, length * 0.5)
	var entry: float = 0.0
	var exit: float = maximum_distance
	# Slab intersection in the aircraft's rotated frame; a ray can hit a wing
	# even when it misses the center. Remote visuals have no physics colliders.
	for axis: int in range(3):
		if absf(local_direction[axis]) < 0.000001:
			if local_origin[axis] < minimum[axis] or local_origin[axis] > maximum[axis]:
				return INF
			continue
		var first: float = (minimum[axis] - local_origin[axis]) / local_direction[axis]
		var last: float = (maximum[axis] - local_origin[axis]) / local_direction[axis]
		entry = maxf(entry, minf(first, last))
		exit = minf(exit, maxf(first, last))
		if entry > exit:
			return INF
	return entry if entry <= maximum_distance and exit >= 0.0 else INF


static func finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
