class_name VehicleController
extends CharacterBody3D



signal impact(normal_speed: float)

const RoundedGeometry = preload("res://scripts/rounded_geometry.gd")
const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
const GRAVITY: = 24.0
const CityLayout = preload("res://scripts/city_layout.gd")
const WORLD_BOUND: = CityLayout.HALF_SIZE - 2.5
const WHEEL_RADIUS: = 0.43
const IDENTITY_COLORS: = [
	[Color("#246cdb"), Color("#164293"), Color("#428ae4")], 
	[Color("#168c83"), Color("#0d5958"), Color("#35b3a2")], 
	[Color("#d89524"), Color("#946019"), Color("#edb24e")], 
	[Color("#8558cb"), Color("#51368b"), Color("#aa7de4")], 
]

var owner_peer_id: = 0
var definition: Dictionary = {}
var occupied: = false
var controls_enabled: = false
var speed: = 0.0
var remote_mode: = false
var is_carrying: = false

var _remote: = false
var _visual: Node3D
var _rider: Node3D
var _front_assembly: Node3D
var _front_wheel: Node3D
var _rear_wheel: Node3D
var _crank: Node3D
var _parcel: Node3D
var _upper_legs: Array[MeshInstance3D] = []
var _lower_legs: Array[MeshInstance3D] = []
var _feet: Array[MeshInstance3D] = []
var _identity_name: = ""
var _identity_index: = 0
var _identity_materials: Array[StandardMaterial3D] = []
var _identity_label: Label3D
var _target_position: = Vector3.ZERO
var _target_yaw: = PI
var _received_velocity: = Vector3.ZERO
var _remote_grounded: = false
var _pose_initialized: = false
var _spawn: = Vector3.ZERO
var _spawn_initialized: = false
var _pedal_phase: = 0.0
var _steering: = 0.0
var _wheels: Array[Node3D] = []
var _front_pivots: Array[Node3D] = []
var _wheel_radius: = WHEEL_RADIUS
var _collision_shape: BoxShape3D
var _remote_steering_initialized: = false
var _brake_lights: Array[StandardMaterial3D] = []
var _last_visual_speed: = 0.0


func configure(vehicle_definition: Dictionary, vehicle_owner_peer_id: int = 0, remote: bool = false) -> void :
	definition = vehicle_definition.duplicate(true)
	owner_peer_id = vehicle_owner_peer_id
	_remote = remote
	remote_mode = remote
	controls_enabled = false
	rotation.y = PI


func _ready() -> void :
	if definition.is_empty():
		definition = VehicleCatalog.load_definitions()["bicycle"]
	if _remote:
		collision_layer = 0
		collision_mask = 0
		if not _pose_initialized:
			_target_position = global_position
			_target_yaw = rotation.y
	else:
		collision_layer = 4
		collision_mask = 1
		floor_snap_length = 0.35
		floor_max_angle = deg_to_rad(48.0)
		var box: = BoxShape3D.new()
		box.size = Vector3(_value("collision_width", 0.8), _value("collision_height", 1.65), _value("collision_length", 2.2))
		_collision_shape = box
		var collision: = CollisionShape3D.new()
		collision.name = "VehicleCollision"
		collision.shape = box
		collision.position.y = box.size.y / 2.0
		add_child(collision)
	match str(definition.get("id", "bicycle")):
		"scooter": _build_scooter()
		"car": _build_car()
		_: _build_bicycle()
	_build_identity_label()
	set_occupied(occupied)
	set_network_identity(_identity_name, _identity_index)


func _physics_process(delta: float) -> void :
	if _remote:
		global_position = global_position.lerp(_target_position, 1.0 - exp(-18.0 * delta))
		var previous_yaw: = rotation.y
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-14.0 * delta))
		if _remote_steering_initialized and delta > 0.0 and absf(speed) > 0.3:
			_steering = clampf( - angle_difference(previous_yaw, rotation.y) / (delta * _value("steer_rate", 2.2) * signf(speed)), -1.0, 1.0)
		else:
			_steering = 0.0
		_remote_steering_initialized = true
		velocity = _received_velocity
		speed = velocity.dot( - global_basis.z)
		_animate(delta)
		return
	if not _spawn_initialized:
		_spawn = global_position
		_spawn_initialized = true
	_steering = 0.0
	if occupied and controls_enabled:
		var throttle: = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		var max_speed: = _value("max_speed", 13.0)
		var reverse_speed: = _value("reverse_speed", 3.0)
		var acceleration: = _value("acceleration", 8.0)
		var braking: = _value("braking", 12.0)
		var handbrake: = str(definition.get("id", "")) == "car" and Input.is_action_pressed("jump")
		if handbrake:
			speed = move_toward(speed, 0.0, _value("handbrake", 28.0) * delta)
		elif throttle > 0.01:
			speed = move_toward(speed, max_speed * throttle, (braking if speed < 0.0 else acceleration) * delta)
		elif throttle < -0.01:
			speed = move_toward(speed, reverse_speed * throttle, (braking if speed > 0.0 else acceleration) * delta)
		else:
			speed = move_toward(speed, 0.0, 2.4 * delta)
		_steering = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		var moving_factor: = clampf(absf(speed) / 3.0, 0.0, 1.0)
		var next_yaw: = rotation.y - _steering * _value("steer_rate", 2.2) * moving_factor * signf(speed) * delta
		if _rotation_is_free(next_yaw):
			rotation.y = next_yaw
	else:
		speed = 0.0
	var forward: = - global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1



	var incoming_horizontal_velocity: = Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if occupied and controls_enabled:
		var strongest_impact: = 0.0
		for index in range(get_slide_collision_count()):
			var normal: = get_slide_collision(index).get_normal()
			if absf(normal.y) < 0.6:
				strongest_impact = maxf(strongest_impact, - incoming_horizontal_velocity.dot(normal))
		if strongest_impact > 0.0:
			impact.emit(strongest_impact)

	if is_on_wall():
		speed = Vector2(velocity.x, velocity.z).dot(Vector2(forward.x, forward.z))
	if absf(global_position.x) > WORLD_BOUND or absf(global_position.z) > WORLD_BOUND:
		global_position.x = clampf(global_position.x, - WORLD_BOUND, WORLD_BOUND)
		global_position.z = clampf(global_position.z, - WORLD_BOUND, WORLD_BOUND)
		speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
	if global_position.y < -10.0:
		reset_at(_spawn)
	_animate(delta)


func set_occupied(value: bool) -> void :
	occupied = value
	if not value:
		set_controls_enabled(false)
	if is_instance_valid(_rider):
		_rider.visible = value
	if is_instance_valid(_parcel):
		_parcel.visible = is_carrying and occupied
	if is_instance_valid(_identity_label):
		_identity_label.position.y = (2.3 if is_carrying and occupied else 1.9) if str(definition.get("id", "")) == "car" else (2.48 if value else 1.65)


func set_controls_enabled(enabled: bool) -> void :
	controls_enabled = enabled and not _remote
	if not controls_enabled:
		speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0


func set_network_identity(display_name: String, color_index: int = 0) -> void :
	_identity_name = display_name
	_identity_index = posmod(color_index, IDENTITY_COLORS.size())
	for index in range(_identity_materials.size()):
		_identity_materials[index].albedo_color = IDENTITY_COLORS[_identity_index][index]
	if is_instance_valid(_identity_label):
		_identity_label.text = display_name
		_identity_label.visible = not display_name.is_empty()


func set_carrying(carrying: bool) -> void :
	is_carrying = carrying
	if is_instance_valid(_parcel):
		_parcel.visible = carrying and occupied
	if is_instance_valid(_identity_label) and str(definition.get("id", "")) == "car":
		_identity_label.position.y = 2.3 if carrying and occupied else 1.9


func apply_network_state(state: Dictionary) -> void :
	if not _remote:
		return
	var received_position: Variant = state.get("position")
	if received_position is Vector3 and received_position.is_finite():
		_target_position = received_position
		_pose_initialized = true
	var received_yaw: Variant = state.get("yaw")
	if (received_yaw is float or received_yaw is int) and is_finite(float(received_yaw)):
		_target_yaw = float(received_yaw)
	var received_velocity: Variant = state.get("velocity")
	if received_velocity is Vector3 and received_velocity.is_finite():
		_received_velocity = received_velocity
	if state.has("grounded"):
		_remote_grounded = bool(state["grounded"])
	if state.has("occupied"):
		set_occupied(bool(state["occupied"]))
	if state.has("carrying"):
		set_carrying(bool(state["carrying"]))


func get_network_pose() -> Dictionary:
	return {
		"position": global_position, 
		"yaw": rotation.y, 
		"velocity": _received_velocity if _remote else velocity, 
		"grounded": _remote_grounded if _remote else is_on_floor(), 
	}


func reset_at(position: Vector3, yaw: float = PI) -> void :
	_spawn = position
	_spawn_initialized = true
	correct_network_position(position, yaw)


func correct_network_position(position: Vector3, yaw: float = NAN) -> void :
	if not position.is_finite():
		return
	global_position = position
	if is_finite(yaw):
		rotation.y = yaw
	speed = 0.0
	velocity = Vector3.ZERO
	_target_position = position
	_target_yaw = rotation.y
	_received_velocity = Vector3.ZERO
	_pose_initialized = true
	reset_physics_interpolation()


func _value(key: String, fallback: float) -> float:
	var supplied: Variant = definition.get(key, fallback)
	if not (supplied is float or supplied is int) or not is_finite(float(supplied)):
		return fallback
	return maxf(0.01, float(supplied))


func _rotation_is_free(yaw: float) -> bool:
	if _collision_shape == null or is_equal_approx(yaw, rotation.y):
		return true
	var query: = PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * (_collision_shape.size.y / 2.0))
	query.collision_mask = 1
	query.margin = 0.0
	var ground_query: = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position - Vector3.UP * 0.2, 1)
	var ground: Dictionary = get_world_3d().direct_space_state.intersect_ray(ground_query)
	if not ground.is_empty() and absf(Vector3(ground["position"]).y) < 0.01 and Vector3(ground["normal"]).y > 0.99:
		query.exclude = [ground["rid"]]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _build_scooter() -> void :
	_visual = Node3D.new()
	_visual.name = "ScooterVisual"
	add_child(_visual)
	_wheel_radius = 0.34
	var paint: = _material(Color("#ee806a"))
	var paint_dark: = _material(Color("#bb5149"))
	var cream: = _material(Color("#fff1d6"))
	var dark: = _material(Color("#273341"))
	var metal: = _material(Color("#b6c6d0"), 0.45, 0.4)
	var tire: = _material(Color("#202630"))
	_box(_visual, "Footboard", Vector3(0.74, 0.1, 1.29), Vector3(0, 0.46, -0.08), dark, 0.04)
	for stripe in range(5):
		_box(_visual, "FootboardGrip", Vector3(0.55, 0.014, 0.018), Vector3(0, 0.518, -0.44 + float(stripe) * 0.16), metal, 0.005)
	_box(_visual, "RearEngineBody", Vector3(0.78, 0.51, 0.99), Vector3(0, 0.71, 0.6), paint, 0.13)
	_box(_visual, "EngineInset", Vector3(0.81, 0.24, 0.62), Vector3(0, 0.67, 0.63), paint_dark, 0.05)
	for side in [-1.0, 1.0]:
		for vent in range(4):
			_box(_visual, "EngineVent", Vector3(0.023, 0.017, 0.16), Vector3(side * 0.418, 0.67 + float(vent) * 0.044, 0.69), dark, 0.006)
	_box(_visual, "Seat", Vector3(0.63, 0.16, 0.81), Vector3(0, 1.015, 0.35), dark, 0.07)
	_box(_visual, "SeatPiping", Vector3(0.63, 0.033, 0.77), Vector3(0, 1.024, 0.35), cream, 0.016)
	_box(_visual, "SeatTop", Vector3(0.59, 0.07, 0.73), Vector3(0, 1.081, 0.35), dark, 0.033)
	_box(_visual, "FrontLegShield", Vector3(0.8, 0.77, 0.21), Vector3(0, 0.9, -0.6), paint, 0.095)
	_box(_visual, "LegShieldInset", Vector3(0.61, 0.6, 0.024), Vector3(0, 0.87, -0.718), cream, 0.06)
	_box(_visual, "ShieldBadge", Vector3(0.09, 0.15, 0.018), Vector3(0, 1.04, -0.741), metal, 0.014)
	_box(_visual, "FrontMudguard", Vector3(0.36, 0.13, 0.56), Vector3(0, 0.72, -0.88), paint, 0.06)
	_box(_visual, "RearMudguard", Vector3(0.37, 0.18, 0.63), Vector3(0, 0.64, 0.83), paint_dark, 0.07)
	var exhaust: = _cylinder(_visual, "Exhaust", 0.073, 0.6, Vector3(0.36, 0.38, 0.69), metal)
	exhaust.rotation.x = PI / 2.0
	var exhaust_tip: = _cylinder(_visual, "ExhaustTip", 0.048, 0.018, Vector3(0.36, 0.38, 0.998), dark)
	exhaust_tip.rotation.x = PI / 2.0
	_tube(_visual, "Kickstand", Vector3(-0.23, 0.44, 0.31), Vector3(-0.41, 0.035, 0.41), 0.026, dark)
	_rear_wheel = _motor_wheel(_visual, "RearWheel", Vector3(0, 0.34, 0.81), 0.34, 0.17, tire, metal)
	_front_assembly = Node3D.new()
	_front_assembly.name = "SteeringAssembly"
	_front_assembly.position = Vector3(0, 0, -0.9)
	_visual.add_child(_front_assembly)
	_front_wheel = _motor_wheel(_front_assembly, "FrontWheel", Vector3(0, 0.34, 0), 0.34, 0.17, tire, metal)
	for side in [-1.0, 1.0]:
		_tube(_front_assembly, "FrontFork", Vector3(side * 0.13, 0.34, 0), Vector3(side * 0.13, 1.12, 0.08), 0.034, metal)
		_tube(_front_assembly, "Handlebar", Vector3(0, 1.33, 0.06), Vector3(side * 0.36, 1.33, 0.17), 0.032, metal)
		_box(_front_assembly, "HandlebarGrip", Vector3(0.16, 0.068, 0.07), Vector3(side * 0.34, 1.33, 0.17), dark, 0.025)
		_tube(_front_assembly, "BrakeLever", Vector3(side * 0.25, 1.3, 0.14), Vector3(side * 0.38, 1.3, 0.1), 0.012, metal)
		_tube(_front_assembly, "MirrorStem", Vector3(side * 0.24, 1.35, 0.11), Vector3(side * 0.38, 1.65, 0.02), 0.017, metal)
		_box(_front_assembly, "MirrorHousing", Vector3(0.18, 0.12, 0.05), Vector3(side * 0.39, 1.68, 0.02), paint_dark, 0.043)
		_box(_front_assembly, "MirrorGlass", Vector3(0.15, 0.085, 0.018), Vector3(side * 0.39, 1.68, 0.053), metal, 0.025)
	_box(_front_assembly, "HeadlightHousing", Vector3(0.41, 0.26, 0.27), Vector3(0, 1.27, 0.03), paint, 0.065)
	_box(_front_assembly, "Headlight", Vector3(0.29, 0.16, 0.03), Vector3(0, 1.27, -0.12), _lamp(Color("#fff2c9")), 0.035)
	_box(_front_assembly, "Dashboard", Vector3(0.21, 0.11, 0.028), Vector3(0, 1.36, 0.175), dark, 0.02)
	_box(_front_assembly, "Speedometer", Vector3(0.13, 0.06, 0.014), Vector3(0, 1.37, 0.194), cream, 0.015)
	for side in [-1.0, 1.0]:
		_box(_visual, "FrontIndicator", Vector3(0.085, 0.09, 0.045), Vector3(side * 0.32, 1.05, -0.749), _lamp(Color("#f9bf54")), 0.02)
	var tail: = _lamp(Color("#f86255"))
	_brake_lights.append(tail)
	_box(_visual, "TailLamp", Vector3(0.3, 0.12, 0.036), Vector3(0, 0.85, 1.114), tail, 0.025)
	_box(_visual, "NumberPlate", Vector3(0.24, 0.11, 0.023), Vector3(0, 0.63, 1.115), cream, 0.01)
	_box(_visual, "RearRack", Vector3(0.52, 0.06, 0.48), Vector3(0, 1.04, 0.9), metal, 0.02)
	_make_parcel(Vector3(0, 1.26, 0.89), Vector3(0.48, 0.38, 0.42))
	_wheels = [_front_wheel, _rear_wheel]
	_front_pivots = [_front_assembly]
	_build_rider()
	_rider.position.y = -0.09
	for index in range(_upper_legs.size()):
		var side: = -1.0 if index == 0 else 1.0
		_place_tube(_upper_legs[index], Vector3(side * 0.14, 1.17, 0.27), Vector3(side * 0.27, 0.83, -0.15))
		_place_tube(_lower_legs[index], Vector3(side * 0.27, 0.83, -0.15), Vector3(side * 0.27, 0.61, -0.14))
		_feet[index].position = Vector3(side * 0.27, 0.61, -0.24)


func _build_car() -> void :
	_visual = Node3D.new()
	_visual.name = "CarVisual"
	add_child(_visual)
	_wheel_radius = 0.36
	var paint: = _material(Color("#56aabb"))
	var paint_dark: = _material(Color("#2b7b91"))
	var cream: = _material(Color("#fbf1d7"))
	var dark: = _material(Color("#283541"))
	var rubber: = _material(Color("#1e2631"))
	var metal: = _material(Color("#b7c6cf"), 0.55, 0.36)
	var glass: = _material(Color("#3c6277"), 0.25, 0.2)
	_box(_visual, "Body", Vector3(1.77, 0.59, 3.8), Vector3(0, 0.59, 0), paint, 0.2)
	_box(_visual, "Sill", Vector3(1.82, 0.13, 2.46), Vector3(0, 0.36, 0.12), paint_dark, 0.045)
	_box(_visual, "Bonnet", Vector3(1.67, 0.16, 1.16), Vector3(0, 0.89, -1.29), paint, 0.07)
	_box(_visual, "BonnetCenterLine", Vector3(0.019, 0.013, 0.85), Vector3(0, 0.979, -1.31), paint_dark, 0.005)
	_box(_visual, "RearHatch", Vector3(1.62, 0.19, 0.82), Vector3(0, 0.88, 1.48), paint, 0.075)
	_box(_visual, "Cabin", Vector3(1.65, 0.66, 1.88), Vector3(0, 1.14, 0.12), paint, 0.15)
	_box(_visual, "Roof", Vector3(1.55, 0.11, 1.68), Vector3(0, 1.488, 0.16), cream, 0.055)
	var windshield: = _box(_visual, "Windshield", Vector3(1.4, 0.48, 0.038), Vector3(0, 1.18, -0.844), glass, 0.045)
	windshield.rotation.x = -0.18
	_box(_visual, "WindshieldTopTrim", Vector3(1.39, 0.034, 0.05), Vector3(0, 1.419, -0.798), cream, 0.012)
	_box(_visual, "RearWindow", Vector3(1.36, 0.4, 0.035), Vector3(0, 1.18, 1.081), glass, 0.04)
	_tube(_visual, "RearWiper", Vector3(-0.39, 1.03, 1.113), Vector3(0.21, 1.18, 1.113), 0.012, dark)
	for side in [-1.0, 1.0]:
		_box(_visual, "FrontSideWindow", Vector3(0.028, 0.44, 0.75), Vector3(side * 0.833, 1.18, -0.345), glass, 0.03)
		_box(_visual, "RearSideWindow", Vector3(0.028, 0.44, 0.7), Vector3(side * 0.833, 1.18, 0.495), glass, 0.03)
		_box(_visual, "WindowPillar", Vector3(0.05, 0.58, 0.092), Vector3(side * 0.85, 1.14, 0.078), dark, 0.012)
		_box(_visual, "WindowSillTrim", Vector3(0.052, 0.03, 1.66), Vector3(side * 0.859, 0.947, 0.05), metal, 0.011)
		for z_offset in [-0.43, 0.49]:
			_box(_visual, "DoorInset", Vector3(0.023, 0.33, 0.81), Vector3(side * 0.893, 0.745, z_offset), paint_dark, 0.025)
			_box(_visual, "DoorPanel", Vector3(0.034, 0.29, 0.765), Vector3(side * 0.91, 0.753, z_offset), paint, 0.025)
			_box(_visual, "DoorHandle", Vector3(0.041, 0.042, 0.17), Vector3(side * 0.94, 0.87, z_offset + 0.23), metal, 0.014)
		_box(_visual, "DoorDeliveryBadge", Vector3(0.038, 0.17, 0.28), Vector3(side * 0.944, 0.74, -0.43), cream, 0.025)
		_box(_visual, "DeliveryBadgeStripe", Vector3(0.047, 0.034, 0.18), Vector3(side * 0.95, 0.745, -0.43), paint_dark, 0.009)
		_tube(_visual, "MirrorStem", Vector3(side * 0.84, 1.01, -0.68), Vector3(side * 0.97, 1.06, -0.73), 0.026, dark)
		_box(_visual, "MirrorHousing", Vector3(0.17, 0.13, 0.23), Vector3(side * 1.005, 1.09, -0.74), paint, 0.045)
		_box(_visual, "MirrorGlass", Vector3(0.135, 0.09, 0.021), Vector3(side * 1.005, 1.1, -0.613), metal, 0.023)
		_box(_visual, "FrontLamp", Vector3(0.48, 0.21, 0.056), Vector3(side * 0.56, 0.75, -1.91), _lamp(Color("#fff0ca")), 0.045)
		_box(_visual, "FrontIndicator", Vector3(0.11, 0.11, 0.047), Vector3(side * 0.79, 0.7, -1.931), _lamp(Color("#f7b94d")), 0.02)
		var tail: = _lamp(Color("#ec6558"))
		_brake_lights.append(tail)
		_box(_visual, "RearLamp", Vector3(0.37, 0.24, 0.055), Vector3(side * 0.62, 0.72, 1.91), tail, 0.045)
		_box(_visual, "RearReverseLamp", Vector3(0.14, 0.065, 0.062), Vector3(side * 0.59, 0.66, 1.913), cream, 0.016)
		for z_offset in [-1.2, 1.23]:
			_box(_visual, "WheelArchTrim", Vector3(0.1, 0.25, 0.83), Vector3(side * 0.882, 0.62, z_offset), paint_dark, 0.075)
			var wheel_parent: Node3D = _visual
			var wheel_position: = Vector3(side * 0.86, 0.36, z_offset)
			if z_offset < 0.0:
				var pivot: = Node3D.new()
				pivot.name = "FrontWheelSteering"
				pivot.position = wheel_position
				_visual.add_child(pivot)
				_front_pivots.append(pivot)
				wheel_parent = pivot
				wheel_position = Vector3.ZERO
			_wheels.append(_motor_wheel(wheel_parent, "CarWheel", wheel_position, 0.36, 0.24, rubber, metal))
	_box(_visual, "FrontBumper", Vector3(1.78, 0.17, 0.16), Vector3(0, 0.43, -1.925), cream, 0.065)
	_box(_visual, "RearBumper", Vector3(1.78, 0.17, 0.16), Vector3(0, 0.43, 1.925), cream, 0.065)
	_box(_visual, "FrontGrille", Vector3(0.64, 0.25, 0.035), Vector3(0, 0.71, -1.927), dark, 0.04)
	for line in range(4):
		_box(_visual, "GrilleSlat", Vector3(0.53, 0.016, 0.018), Vector3(0, 0.625 + float(line) * 0.055, -1.952), metal, 0.005)
	_box(_visual, "GrilleBadge", Vector3(0.082, 0.072, 0.023), Vector3(0, 0.76, -1.976), cream, 0.018)
	for z_offset in [-2.012, 2.012]:
		_box(_visual, "NumberPlate", Vector3(0.44, 0.12, 0.022), Vector3(0, 0.43, z_offset), cream, 0.01)
		for stripe in range(7):
			_box(_visual, "PlateLetter", Vector3(0.026, 0.055, 0.008), Vector3(-0.15 + float(stripe) * 0.046, 0.43, z_offset + signf(z_offset) * 0.016), dark, 0.004)
	for side in [-1.0, 1.0]:
		_tube(_visual, "WindshieldWiper", Vector3(side * 0.44, 1.0, -0.91), Vector3(side * 0.13, 1.145, -0.875), 0.01, dark)
		_box(_visual, "RoofRackRail", Vector3(0.055, 0.045, 1.19), Vector3(side * 0.5, 1.576, 0.21), metal, 0.018)
	for z_offset in [-0.32, 0.7]:
		_box(_visual, "RoofRackCrossbar", Vector3(1.07, 0.045, 0.055), Vector3(0, 1.61, z_offset), dark, 0.018)
	_make_parcel(Vector3(0, 1.84, 0.43), Vector3(0.69, 0.43, 0.58))




func _make_parcel(origin: Vector3, dimensions: Vector3) -> void :
	_parcel = Node3D.new()
	_parcel.name = "SecuredDeliveryParcel"
	_parcel.position = origin
	_visual.add_child(_parcel)
	var cardboard: = _material(Color("#c89459"))
	var cream: = _material(Color("#fff0d7"))
	var dark: = _material(Color("#29333f"))
	_box(_parcel, "Parcel", dimensions, Vector3.ZERO, cardboard, 0.03)
	_box(_parcel, "TopTape", Vector3(0.07, 0.011, dimensions.z - 0.02), Vector3(0, dimensions.y / 2.0 + 0.004, 0), cream, 0.004)
	for side in [-1.0, 1.0]:
		_box(_parcel, "SecuringStrap", Vector3(0.033, dimensions.y + 0.026, dimensions.z + 0.026), Vector3(side * dimensions.x * 0.33, 0, 0), dark, 0.01)
	_box(_parcel, "ShippingLabel", Vector3(0.18, 0.12, 0.014), Vector3( - dimensions.x * 0.22, 0.035, dimensions.z / 2.0 + 0.011), cream, 0.01)
	for stripe in range(7):
		_box(_parcel, "ParcelBarcode", Vector3(0.007, 0.052, 0.008), Vector3( - dimensions.x * 0.22 - 0.065 + float(stripe) * 0.019, 0.025, dimensions.z / 2.0 + 0.022), dark, 0.002)
	_parcel.visible = is_carrying


func _motor_wheel(parent: Node3D, mesh_name: String, center: Vector3, radius: float, width: float, tire: StandardMaterial3D, rim: StandardMaterial3D) -> Node3D:
	var wheel: = Node3D.new()
	wheel.name = mesh_name
	wheel.position = center
	parent.add_child(wheel)
	var rubber: = _cylinder(wheel, "Tire", radius, width, Vector3.ZERO, tire, 24)
	rubber.rotation.z = PI / 2.0
	for side in [-1.0, 1.0]:
		var hub: = _cylinder(wheel, "Rim", radius * 0.67, 0.014, Vector3(side * (width / 2.0 + 0.006), 0, 0), rim, 20)
		hub.rotation.z = PI / 2.0
		var inset: = _cylinder(wheel, "RimInset", radius * 0.53, 0.019, Vector3(side * (width / 2.0 + 0.012), 0, 0), tire, 20)
		inset.rotation.z = PI / 2.0
		for spoke in range(5):
			var angle: = float(spoke) * TAU / 5.0
			_tube(wheel, "RimSpoke", Vector3(side * (width / 2.0 + 0.027), 0, 0), Vector3(side * (width / 2.0 + 0.027), cos(angle) * radius * 0.6, sin(angle) * radius * 0.6), 0.025, rim, 8)
		var cap: = _cylinder(wheel, "HubCap", radius * 0.18, 0.027, Vector3(side * (width / 2.0 + 0.028), 0, 0), rim)
		cap.rotation.z = PI / 2.0
	return wheel


func _lamp(color: Color) -> StandardMaterial3D:
	var material: = _material(color, 0.0, 0.45)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.12
	return material

func _build_bicycle() -> void :
	_visual = Node3D.new()
	_visual.name = "BicycleVisual"
	add_child(_visual)
	var paint: = _material(Color("#efb64a"))
	var trim: = _material(Color("#d58030"))
	var dark: = _material(Color("#253746"))
	var tire: = _material(Color("#202936"))
	var metal: = _material(Color("#b9ced0"), 0.25, 0.65)
	var cream: = _material(Color("#f4eddc"))
	var red: = _material(Color("#ed6a65"))
	var crank_position: = Vector3(0.0, 0.43, 0.04)
	var seat_joint: = Vector3(0.0, 1.03, 0.32)
	var steering_joint: = Vector3(0.0, 1.1, -0.55)
	var rear_axle: = Vector3(0.0, 0.43, 0.82)
	_tube(_visual, "SeatTube", crank_position, seat_joint, 0.045, paint)
	_tube(_visual, "TopTube", seat_joint, steering_joint, 0.045, paint)
	_tube(_visual, "DownTube", steering_joint, crank_position, 0.047, paint)
	_tube(_visual, "SeatPost", seat_joint, Vector3(0, 1.16, 0.36), 0.031, metal)
	for side in [-1.0, 1.0]:
		_tube(_visual, "SeatStay", seat_joint + Vector3(side * 0.065, 0, 0), rear_axle + Vector3(side * 0.14, 0, 0), 0.022, paint)
		_tube(_visual, "ChainStay", crank_position + Vector3(side * 0.06, 0, 0), rear_axle + Vector3(side * 0.14, 0, 0), 0.025, paint)
		_ellipsoid(_visual, "RearAxleBolt", Vector3(0.065, 0.065, 0.065), rear_axle + Vector3(side * 0.18, 0, 0), metal)
	for joint in [crank_position, seat_joint, steering_joint]:
		_ellipsoid(_visual, "FrameJoint", Vector3(0.11, 0.11, 0.11), joint, paint)
	var badge: = _box(_visual, "FrameBadge", Vector3(0.025, 0.08, 0.24), Vector3(0.051, 0.79, -0.24), cream, 0.012)
	badge.rotation.x = -0.5
	_box(_visual, "FrameBadgeStripe", Vector3(0.014, 0.018, 0.12), Vector3(0.069, 0.79, -0.24), trim, 0.005)
	_box(_visual, "Saddle", Vector3(0.3, 0.11, 0.43), Vector3(0, 1.2, 0.3), dark, 0.045)
	_box(_visual, "SaddleInset", Vector3(0.22, 0.018, 0.29), Vector3(0, 1.256, 0.33), trim, 0.007)
	_box(_visual, "RearRack", Vector3(0.44, 0.055, 0.4), Vector3(0, 0.98, 0.9), dark, 0.015)
	for side in [-1.0, 1.0]:
		_tube(_visual, "RackSupport", rear_axle + Vector3(side * 0.17, 0, 0), Vector3(side * 0.18, 0.98, 0.9), 0.018, metal)
	_box(_visual, "RearReflector", Vector3(0.15, 0.065, 0.035), Vector3(0, 0.98, 1.116), red, 0.012)
	_parcel = Node3D.new()
	_parcel.name = "RearRackParcel"
	_parcel.position = Vector3(0, 1.165, 0.9)
	_visual.add_child(_parcel)
	var cardboard: = _material(Color("#ca9861"))
	_box(_parcel, "Box", Vector3(0.43, 0.32, 0.35), Vector3.ZERO, cardboard, 0.025)
	_box(_parcel, "TopTape", Vector3(0.06, 0.008, 0.32), Vector3(0, 0.164, 0), cream, 0.003)
	_box(_parcel, "BackTape", Vector3(0.06, 0.29, 0.008), Vector3(0, 0, 0.178), cream, 0.003)
	_box(_parcel, "ShippingLabel", Vector3(0.14, 0.1, 0.012), Vector3(-0.11, 0.026, 0.181), cream, 0.006)
	for stripe in range(6):
		_box(_parcel, "LabelBarcode", Vector3(0.006, 0.036, 0.009), Vector3(-0.157 + float(stripe) * 0.016, 0.02, 0.191), dark, 0.002)
	_parcel.visible = is_carrying
	_tube(_visual, "Kickstand", Vector3(-0.14, 0.43, 0.43), Vector3(-0.24, 0.075, 0.54), 0.025, dark)
	_rear_wheel = _wheel(_visual, "RearWheel", rear_axle, tire, metal)
	_front_assembly = Node3D.new()
	_front_assembly.name = "SteeringAssembly"
	_front_assembly.position = steering_joint
	_visual.add_child(_front_assembly)
	for side in [-1.0, 1.0]:
		_tube(_front_assembly, "Fork", Vector3(side * 0.13, 0.04, 0), Vector3(side * 0.13, -0.67, -0.27), 0.026, paint)
	_tube(_front_assembly, "HandlebarStem", Vector3.ZERO, Vector3(0, 0.26, -0.08), 0.033, metal)
	_tube(_front_assembly, "Handlebar", Vector3(-0.37, 0.27, -0.08), Vector3(0.37, 0.27, -0.08), 0.025, metal)
	for side in [-1.0, 1.0]:
		_tube(_front_assembly, "HandlebarEnd", Vector3(side * 0.37, 0.27, -0.08), Vector3(side * 0.37, 0.29, -0.22), 0.024, metal)
		_box(_front_assembly, "HandlebarGrip", Vector3(0.065, 0.065, 0.16), Vector3(side * 0.37, 0.29, -0.18), dark, 0.023)
		_tube(_front_assembly, "BrakeLever", Vector3(side * 0.3, 0.26, -0.1), Vector3(side * 0.3, 0.26, -0.2), 0.012, dark)
	_box(_front_assembly, "FrontLight", Vector3(0.12, 0.09, 0.08), Vector3(0, 0.24, -0.15), dark, 0.02)
	_box(_front_assembly, "LightLens", Vector3(0.1, 0.065, 0.02), Vector3(0, 0.24, -0.2), cream, 0.01)
	_ellipsoid(_front_assembly, "Bell", Vector3(0.1, 0.05, 0.09), Vector3(-0.21, 0.31, -0.08), metal)
	_front_wheel = _wheel(_front_assembly, "FrontWheel", Vector3(0, -0.67, -0.27), tire, metal)

	var sprocket: = _cylinder(_visual, "Chainring", 0.13, 0.035, crank_position + Vector3(0.14, 0, 0), metal)
	sprocket.rotation.z = PI / 2.0
	for tooth in range(10):
		var angle: = float(tooth) * TAU / 10.0
		_ellipsoid(_visual, "ChainringTooth", Vector3(0.035, 0.035, 0.035), crank_position + Vector3(0.16, cos(angle) * 0.13, sin(angle) * 0.13), dark)
	_tube(_visual, "UpperChain", Vector3(0.17, 0.54, 0.06), Vector3(0.17, 0.505, 0.82), 0.012, dark)
	_tube(_visual, "LowerChain", Vector3(0.17, 0.32, 0.06), Vector3(0.17, 0.355, 0.82), 0.012, dark)
	_crank = Node3D.new()
	_crank.name = "PedalCrank"
	_crank.position = crank_position
	_visual.add_child(_crank)
	for side in [-1.0, 1.0]:
		_tube(_crank, "CrankArm", Vector3(side * 0.18, 0, 0), Vector3(side * 0.18, 0, side * 0.18), 0.018, metal)
		_box(_crank, "Pedal", Vector3(0.15, 0.04, 0.11), Vector3(side * 0.23, 0, side * 0.18), dark, 0.012)
		_box(_crank, "PedalReflector", Vector3(0.08, 0.018, 0.015), Vector3(side * 0.23, 0, side * 0.18 - 0.06), paint, 0.006)
	_wheels = [_front_wheel, _rear_wheel]
	_front_pivots = [_front_assembly]
	_build_rider()


func _build_identity_label() -> void :
	_identity_label = Label3D.new()
	_identity_label.name = "VehicleOwnerName"
	_identity_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_identity_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_identity_label.font_size = 36
	_identity_label.pixel_size = 0.008
	_identity_label.outline_size = 6
	_identity_label.outline_modulate = Color("#182331")
	add_child(_identity_label)


func _build_rider() -> void :
	_rider = Node3D.new()
	_rider.name = "SeatedCourier"
	_visual.add_child(_rider)
	var jacket: = _material(IDENTITY_COLORS[_identity_index][0])
	var jacket_dark: = _material(IDENTITY_COLORS[_identity_index][1])
	var jacket_light: = _material(IDENTITY_COLORS[_identity_index][2])
	_identity_materials = [jacket, jacket_dark, jacket_light]
	var pants: = _material(Color("#213044"))
	var skin: = _material(Color("#efb886"))
	var hair: = _material(Color("#47332e"))
	var cream: = _material(Color("#f0f1eb"))
	var badge: = _material(Color("#f2cd86"))
	var torso: = _box(_rider, "Jacket", Vector3(0.58, 0.54, 0.38), Vector3(0, 1.49, 0.1), jacket, 0.09)
	torso.rotation.x = -0.22
	_box(_rider, "TrouserHips", Vector3(0.46, 0.16, 0.32), Vector3(0, 1.17, 0.27), pants, 0.06)
	_box(_rider, "DeliveryBackpack", Vector3(0.48, 0.5, 0.25), Vector3(0, 1.48, 0.4), jacket_dark, 0.055)
	_box(_rider, "BackpackPocket", Vector3(0.38, 0.18, 0.05), Vector3(0, 1.36, 0.54), jacket, 0.025)
	_box(_rider, "BackpackStripe", Vector3(0.38, 0.04, 0.018), Vector3(0, 1.51, 0.54), badge, 0.008)
	_box(_rider, "BackpackPocketZip", Vector3(0.3, 0.012, 0.014), Vector3(0, 1.425, 0.573), cream, 0.004)
	for side in [-1.0, 1.0]:
		_box(_rider, "BackpackStrap", Vector3(0.05, 0.39, 0.022), Vector3(side * 0.22, 1.5, -0.1), jacket_dark, 0.01)
		_tube(_rider, "UpperArm", Vector3(side * 0.3, 1.66, 0.02), Vector3(side * 0.34, 1.45, -0.31), 0.093, jacket)
		_tube(_rider, "LowerArm", Vector3(side * 0.34, 1.45, -0.31), Vector3(side * 0.37, 1.39, -0.73), 0.08, jacket_light)
		_ellipsoid(_rider, "Hand", Vector3(0.14, 0.13, 0.16), Vector3(side * 0.37, 1.39, -0.73), skin)
		_upper_legs.append(_tube(_rider, "UpperLeg", Vector3.ZERO, Vector3.UP, 0.098, pants))
		_lower_legs.append(_tube(_rider, "LowerLeg", Vector3.ZERO, Vector3.UP, 0.085, pants))
		_feet.append(_box(_rider, "RiderShoe", Vector3(0.23, 0.13, 0.33), Vector3.ZERO, cream, 0.045))
	_ellipsoid(_rider, "Neck", Vector3(0.16, 0.19, 0.17), Vector3(0, 1.78, -0.01), skin)
	_ellipsoid(_rider, "Head", Vector3(0.39, 0.42, 0.35), Vector3(0, 1.96, -0.025), skin)
	_ellipsoid(_rider, "Hair", Vector3(0.38, 0.18, 0.35), Vector3(0, 2.075, -0.005), hair)
	_ellipsoid(_rider, "Cap", Vector3(0.43, 0.2, 0.4), Vector3(0, 2.145, -0.01), jacket)
	_ellipsoid(_rider, "CapPeak", Vector3(0.35, 0.035, 0.23), Vector3(0, 2.13, -0.23), jacket)
	for side in [-1.0, 1.0]:
		_ellipsoid(_rider, "Ear", Vector3(0.07, 0.12, 0.065), Vector3(side * 0.19, 1.96, -0.01), skin)
		_ellipsoid(_rider, "Eye", Vector3(0.033, 0.045, 0.02), Vector3(side * 0.076, 1.985, -0.196), pants)
	_ellipsoid(_rider, "Nose", Vector3(0.05, 0.046, 0.05), Vector3(0, 1.95, -0.208), skin)
	_box(_rider, "Smile", Vector3(0.054, 0.012, 0.012), Vector3(0, 1.9, -0.195), hair, 0.004)
	_animate(0.0)


func _animate(delta: float) -> void :
	var spin: = speed * delta / _wheel_radius
	for wheel: Node3D in _wheels:
		wheel.rotation.x += spin
	for pivot: Node3D in _front_pivots:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, - _steering * 0.35, 1.0 - exp(-12.0 * delta))
	var braking: = absf(speed) < absf(_last_visual_speed) - 0.01
	if not _remote and controls_enabled and occupied:
		braking = braking or (speed > 0.1 and Input.is_action_pressed("move_back")) or (str(definition.get("id", "")) == "car" and Input.is_action_pressed("jump"))
	for lamp: StandardMaterial3D in _brake_lights:
		lamp.emission_energy_multiplier = 0.5 if braking else 0.12
	_last_visual_speed = speed
	if str(definition.get("id", "bicycle")) != "bicycle" or not is_instance_valid(_crank):
		return
	if occupied and absf(speed) > 0.1:
		_pedal_phase += absf(speed) * delta * 1.7
	_crank.rotation.x = _pedal_phase
	for index in range(_upper_legs.size()):
		var side: = -1.0 if index == 0 else 1.0
		var hip: = Vector3(side * 0.14, 1.17, 0.27)
		var pedal: = _crank.position + Basis(Vector3.RIGHT, _pedal_phase) * Vector3(side * 0.23, 0.0, side * 0.18)
		var ankle: = pedal + Vector3(0, 0.075, -0.015)
		var knee: = Vector3(side * 0.18, 0.88 + (ankle.y - 0.43) * 0.3, -0.12)
		_place_tube(_upper_legs[index], hip, knee)
		_place_tube(_lower_legs[index], knee, ankle)
		_feet[index].position = ankle + Vector3(0, -0.015, -0.045)


func _wheel(parent: Node3D, mesh_name: String, center: Vector3, tire: StandardMaterial3D, rim: StandardMaterial3D) -> Node3D:
	var wheel: = Node3D.new()
	wheel.name = mesh_name
	wheel.position = center
	parent.add_child(wheel)
	for data in [[0.335, WHEEL_RADIUS, tire, "Tire"], [0.3, 0.328, rim, "Rim"]]:
		var instance: = MeshInstance3D.new()
		instance.name = data[3]
		var torus: = TorusMesh.new()
		torus.inner_radius = data[0]
		torus.outer_radius = data[1]
		torus.ring_segments = 8
		torus.rings = 32
		instance.mesh = torus
		instance.material_override = data[2]
		instance.rotation.z = PI / 2.0
		wheel.add_child(instance)
	var hub: = _cylinder(wheel, "WheelHub", 0.055, 0.17, Vector3.ZERO, rim)
	hub.rotation.z = PI / 2.0
	for spoke in range(12):
		var angle: = float(spoke) * TAU / 12.0
		_tube(wheel, "Spoke", Vector3(0.035 if spoke % 2 == 0 else -0.035, 0, 0), Vector3(0, cos(angle) * 0.315, sin(angle) * 0.315), 0.006, rim, 6)
	_box(wheel, "WheelReflector", Vector3(0.022, 0.075, 0.12), Vector3(0.035, 0.205, 0), _material(Color("#f2cb72")), 0.005)
	return wheel


func _material(color: Color, metallic: float = 0.0, roughness: float = 0.85) -> StandardMaterial3D:
	var material: = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _box(parent: Node3D, mesh_name: String, dimensions: Vector3, origin: Vector3, material: StandardMaterial3D, radius: float = 0.02) -> MeshInstance3D:
	var instance: = MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = RoundedGeometry.box(dimensions, radius, 3)
	instance.material_override = material
	instance.position = origin
	parent.add_child(instance)
	return instance


func _ellipsoid(parent: Node3D, mesh_name: String, dimensions: Vector3, origin: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: = MeshInstance3D.new()
	instance.name = mesh_name
	var sphere: = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	instance.mesh = sphere
	instance.scale = dimensions
	instance.material_override = material
	instance.position = origin
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node3D, mesh_name: String, radius: float, height: float, origin: Vector3, material: StandardMaterial3D, segments: int = 12) -> MeshInstance3D:
	var instance: = MeshInstance3D.new()
	instance.name = mesh_name
	var cylinder: = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = segments
	instance.mesh = cylinder
	instance.material_override = material
	instance.position = origin
	parent.add_child(instance)
	return instance


func _tube(parent: Node3D, mesh_name: String, start: Vector3, end: Vector3, radius: float, material: StandardMaterial3D, segments: int = 12) -> MeshInstance3D:
	var instance: = _cylinder(parent, mesh_name, radius, 1.0, Vector3.ZERO, material, segments)
	_place_tube(instance, start, end)
	return instance


func _place_tube(instance: MeshInstance3D, start: Vector3, end: Vector3) -> void :
	var difference: = end - start
	var length: = difference.length()
	instance.position = (start + end) * 0.5
	if length > 0.001:
		instance.quaternion = Quaternion(Vector3.UP, difference / length)
		instance.scale = Vector3(1.0, length, 1.0)
