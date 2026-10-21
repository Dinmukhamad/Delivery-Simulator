extends Node3D

# One lightweight updater, reusable visual groups, and shared meshes/materials.
# Shots never own physics bodies, damage logic, RPCs, or player state.
const MAX_SHOTS: int = 16
const MAX_WRECKS: int = 8
const SHOT_SECONDS: float = 0.16
const WRECK_SECONDS: float = 2.1

var _shots: Array[Dictionary] = []
var _wrecks: Array[Dictionary] = []
var _sphere: SphereMesh
var _cylinder: CylinderMesh
var _box: BoxMesh
var _flash_material: StandardMaterial3D
var _tracer_material: StandardMaterial3D
var _spark_material: StandardMaterial3D
var _wreck_material: StandardMaterial3D
var _smoke_material: StandardMaterial3D


func _ready() -> void:
	set_process(false)


func show_shot(event: Dictionary) -> void:
	var origin: Variant = event.get("from", Vector3.INF)
	var endpoint: Variant = event.get("to", Vector3.INF)
	if not _valid_position(origin) or not _valid_position(endpoint):
		return
	var distance: float = origin.distance_to(endpoint)
	if distance < 0.01 or distance > 250.0:
		return
	_prepare_resources()
	var effect: Dictionary = _shot_slot()
	var group: Node3D = effect["node"]
	group.visible = true
	effect["age"] = 0.0
	effect["active"] = true
	effect["origin"] = origin
	effect["endpoint"] = endpoint
	effect["hit"] = int(event.get("hit_id", 0)) > 0
	var direction: Vector3 = (endpoint - origin) / distance
	var tracer: MeshInstance3D = effect["tracer"]
	tracer.position = (origin + endpoint) * 0.5
	tracer.basis = Basis(Quaternion(Vector3.UP, direction))
	tracer.scale = Vector3(0.035, distance, 0.035)
	var flash: MeshInstance3D = effect["flash"]
	flash.position = origin
	flash.scale = Vector3.ONE * 0.30
	for index in range(4):
		var spark: MeshInstance3D = effect["sparks"][index]
		spark.visible = bool(effect["hit"])
		spark.position = endpoint
		spark.scale = Vector3.ONE * 0.15
	if bool(event.get("destroyed", false)) and bool(effect["hit"]):
		var target: Variant = event.get("target_position", endpoint)
		if _valid_position(target):
			_show_wreck(target, direction)
	set_process(true)


func clear_effects() -> void:
	for effect: Dictionary in _shots:
		effect["active"] = false
		effect["node"].visible = false
	for effect: Dictionary in _wrecks:
		effect["active"] = false
		effect["node"].visible = false
	set_process(false)


func active_effect_count() -> int:
	var count: int = 0
	for effect: Dictionary in _shots:
		if bool(effect["active"]):
			count += 1
	for effect: Dictionary in _wrecks:
		if bool(effect["active"]):
			count += 1
	return count


func _process(delta: float) -> void:
	var step: float = clampf(delta, 0.0, 0.1)
	for effect: Dictionary in _shots:
		if not bool(effect["active"]):
			continue
		effect["age"] = float(effect["age"]) + step
		var age: float = float(effect["age"])
		if age >= SHOT_SECONDS:
			effect["active"] = false
			effect["node"].visible = false
			continue
		var fade: float = 1.0 - age / SHOT_SECONDS
		var tracer: MeshInstance3D = effect["tracer"]
		tracer.scale.x = 0.035 * fade
		tracer.scale.z = 0.035 * fade
		var flash: MeshInstance3D = effect["flash"]
		flash.scale = Vector3.ONE * maxf(0.001, 0.30 * fade)
		for index in range(4):
			var spark: MeshInstance3D = effect["sparks"][index]
			var angle: float = float(index) * TAU / 4.0 + 0.4
			spark.position = effect["endpoint"] + Vector3(cos(angle), sin(angle), 0.4) * age * 5.0
			spark.scale = Vector3.ONE * maxf(0.001, 0.15 * fade)
	for effect: Dictionary in _wrecks:
		if not bool(effect["active"]):
			continue
		effect["age"] = float(effect["age"]) + step
		var age: float = float(effect["age"])
		if age >= WRECK_SECONDS:
			effect["active"] = false
			effect["node"].visible = false
			continue
		var group: Node3D = effect["node"]
		var start: Vector3 = effect["origin"]
		var direction: Vector3 = effect["direction"]
		group.position = start + direction * age * 3.0 + Vector3.DOWN * minf(maxf(0.0, start.y - 0.3), age * age * 5.0)
		var plane: Node3D = effect["plane"]
		plane.rotation = Vector3(age * 0.65, float(effect["yaw"]) + age * 0.25, age * 1.9)
		var shrink: float = clampf((WRECK_SECONDS - age) / 0.35, 0.001, 1.0)
		plane.scale = Vector3.ONE * shrink
		var burst: MeshInstance3D = effect["burst"]
		burst.visible = age < 0.4
		burst.scale = Vector3.ONE * maxf(0.001, (0.4 - age) * 4.5)
		for index in range(4):
			var puff: MeshInstance3D = effect["smoke"][index]
			var phase: float = fmod(age * 0.7 + float(index) / 4.0, 1.0)
			puff.position = Vector3(sin(float(index) * 2.4) * phase, 0.8 + phase * 3.3, phase * 1.1)
			puff.scale = Vector3.ONE * (0.35 + phase * 1.2) * shrink
	if active_effect_count() == 0:
		set_process(false)


func _shot_slot() -> Dictionary:
	for effect: Dictionary in _shots:
		if not bool(effect["active"]):
			return effect
	if _shots.size() >= MAX_SHOTS:
		# Reuse the oldest slot if a burst arrives in one network frame.
		var oldest: Dictionary = _shots[0]
		for candidate: Dictionary in _shots:
			if float(candidate["age"]) > float(oldest["age"]):
				oldest = candidate
		return oldest
	var group: Node3D = Node3D.new()
	group.name = "AircraftShotEffect"
	add_child(group)
	var sparks: Array[MeshInstance3D] = []
	for index in range(4):
		sparks.append(_mesh(group, "HitSpark", _sphere, _spark_material))
	var effect: Dictionary = {"node": group, "active": false, "age": 0.0,
		"tracer": _mesh(group, "Tracer", _cylinder, _tracer_material),
		"flash": _mesh(group, "MuzzleFlash", _sphere, _flash_material), "sparks": sparks}
	_shots.append(effect)
	return effect


func _show_wreck(origin: Vector3, direction: Vector3) -> void:
	var effect: Dictionary = {}
	for candidate: Dictionary in _wrecks:
		if not bool(candidate["active"]):
			effect = candidate
			break
	if effect.is_empty():
		if _wrecks.size() >= MAX_WRECKS:
			effect = _wrecks[0]
			for candidate: Dictionary in _wrecks:
				if float(candidate["age"]) > float(effect["age"]):
					effect = candidate
		else:
			effect = _new_wreck()
	var group: Node3D = effect["node"]
	group.visible = true
	group.position = origin
	effect["active"] = true
	effect["age"] = 0.0
	effect["origin"] = origin
	effect["direction"] = direction
	effect["yaw"] = atan2(-direction.x, -direction.z)
	var plane: Node3D = effect["plane"]
	plane.rotation = Vector3(0.0, float(effect["yaw"]), 0.0)
	plane.scale = Vector3.ONE
	var burst: MeshInstance3D = effect["burst"]
	burst.visible = true
	burst.scale = Vector3.ONE * 1.8


func _new_wreck() -> Dictionary:
	var group: Node3D = Node3D.new()
	group.name = "FallingAircraftEffect"
	add_child(group)
	var plane: Node3D = Node3D.new()
	plane.name = "DamagedAirframe"
	group.add_child(plane)
	var fuselage: MeshInstance3D = _mesh(plane, "RoundedFuselage", _sphere, _wreck_material)
	fuselage.scale = Vector3(0.9, 0.9, 3.8)
	fuselage.position.y = 1.0
	var wing: MeshInstance3D = _mesh(plane, "Wing", _box, _wreck_material)
	wing.scale = Vector3(5.8, 0.17, 1.25)
	wing.position = Vector3(0.0, 1.0, -0.25)
	var tail: MeshInstance3D = _mesh(plane, "Tail", _box, _wreck_material)
	tail.scale = Vector3(2.1, 0.13, 0.7)
	tail.position = Vector3(0.0, 1.1, 1.8)
	var smoke: Array[MeshInstance3D] = []
	for index in range(4):
		smoke.append(_mesh(group, "WreckSmokePuff", _sphere, _smoke_material))
	var effect: Dictionary = {"node": group, "plane": plane, "smoke": smoke,
		"burst": _mesh(group, "DestructionFlash", _sphere, _flash_material), "active": false, "age": 0.0}
	_wrecks.append(effect)
	return effect


func _prepare_resources() -> void:
	if _sphere != null:
		return
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 10
	_sphere.rings = 5
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = 1.0
	_cylinder.bottom_radius = 1.0
	_cylinder.height = 1.0
	_cylinder.radial_segments = 6
	_box = BoxMesh.new()
	_flash_material = _material(Color("#ffca64"), true)
	_tracer_material = _material(Color("#fff4b0"), true)
	_spark_material = _material(Color("#ff8e39"), true)
	_wreck_material = _material(Color("#6a625b"))
	_smoke_material = _material(Color("#4b505b"))


func _material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.3
	return material


func _mesh(parent: Node3D, node_name: String, shape: Mesh, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = shape
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _valid_position(value: Variant) -> bool:
	return value is Vector3 and value.is_finite() and absf(value.x) < 2000.0 and absf(value.y) < 2000.0 and absf(value.z) < 2000.0
