extends CharacterBody3D


const RoundedGeometry = preload("res://scripts/rounded_geometry.gd")
const CosmeticCatalog = preload("res://scripts/cosmetic_catalog.gd")

const WALK_SPEED: = 4.5
const RUN_SPEED: = 8.5
const GRAVITY: = 24.0
const JUMP_SPEED: = 5.8
const BASE_MOUSE_SENSITIVITY: = 0.0026
const IDENTITY_COLORS: = [
	[Color("#246cdb"), Color("#164293"), Color("#428ae4")], 
	[Color("#168c83"), Color("#0d5958"), Color("#35b3a2")], 
	[Color("#d89524"), Color("#946019"), Color("#edb24e")], 
	[Color("#8558cb"), Color("#51368b"), Color("#aa7de4")], 
]

var camera: Camera3D
var is_carrying: = false
var controls_enabled: = false
var riding_vehicle: Node3D

var _visual: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _parcel: Node3D
var _camera_pivot: Node3D
var _camera_arm: SpringArm3D
var _excluded_vehicle_rid: = RID()
var _riding_active: = false
var _camera_yaw: = 0.0
var _camera_pitch: = deg_to_rad(-18.0)
var _sensitivity: = 1.0
var _gait_phase: = 0.0
var _spawn: = Vector3.ZERO
var _spawn_initialized: = false
var _is_remote: = false
var _remote_target_position: = Vector3.ZERO
var _remote_target_yaw: = 0.0
var _received_velocity: = Vector3.ZERO
var _remote_grounded: = false
var _remote_pose_initialized: = false
var _identity_name: = ""
var _identity_index: = 0
var _identity_label: Label3D
var _identity_materials: Array[StandardMaterial3D] = []

var _appearance: Dictionary = {"outfit": "classic_blue", "backpack": "classic", "vehicle_paint": "factory"}
var _appearance_explicit: = false
var _appearance_key: = ""
var _outfit_materials: Dictionary = {}
var _backpack_materials: Array[StandardMaterial3D] = []
var _backpack_variants: Dictionary = {}
var _backpack_straps: Array[Node3D] = []



func _ready() -> void :
	if _is_remote:
		collision_layer = 0
		collision_mask = 0
		if not _remote_pose_initialized:
			_remote_target_position = global_position
		_build_courier()
		_update_riding_visibility()
		return
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(48.0)

	var capsule: = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 2.0
	var collision: = CollisionShape3D.new()
	collision.name = "CourierCollision"
	collision.shape = capsule
	collision.position.y = 1.0
	add_child(collision)

	_build_courier()
	_build_camera()
	_update_riding_visibility()


func _physics_process(delta: float) -> void :
	if _riding_active and not is_instance_valid(riding_vehicle):
		set_riding_vehicle(null)
	_update_camera_distance(delta)
	if is_riding():

		global_position = riding_vehicle.global_position
		velocity = riding_vehicle.velocity if riding_vehicle is CharacterBody3D else Vector3.ZERO
		return
	if _is_remote:
		global_position = global_position.lerp(_remote_target_position, 1.0 - exp(-18.0 * delta))
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _remote_target_yaw, 1.0 - exp(-14.0 * delta))
		velocity = _received_velocity
		var running: = Vector2(velocity.x, velocity.z).length() > WALK_SPEED + 0.1
		_animate_courier(delta, running)
		return

	if not _spawn_initialized:
		_spawn = global_position
		_spawn_initialized = true

	var input_direction: = Vector2.ZERO
	if controls_enabled:
		input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: = Basis(Vector3.UP, _camera_yaw) * Vector3(input_direction.x, 0.0, input_direction.y)
	var running: = controls_enabled and Input.is_action_pressed("sprint")
	var speed: = RUN_SPEED if running else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	if controls_enabled and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED

	move_and_slide()
	if global_position.y < -10.0:
		reset_at(_spawn)
		return

	if direction.length_squared() > 0.001:
		var target_yaw: = atan2( - direction.x, - direction.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))
	_animate_courier(delta, running)


func _unhandled_input(event: InputEvent) -> void :
	if _is_remote or not controls_enabled or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_camera_yaw -= event.relative.x * BASE_MOUSE_SENSITIVITY * _sensitivity
		_camera_pitch -= event.relative.y * BASE_MOUSE_SENSITIVITY * _sensitivity
		_camera_pitch = clampf(_camera_pitch, deg_to_rad(-70.0), deg_to_rad(25.0))
		_camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _notification(what: int) -> void :
	if not _is_remote and what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func set_controls_enabled(enabled: bool) -> void :
	if _is_remote:
		controls_enabled = false
		return
	controls_enabled = enabled
	if not enabled:
		velocity.x = 0.0
		velocity.z = 0.0


func set_mouse_captured(captured: bool) -> void :
	if _is_remote:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if captured and controls_enabled else Input.MOUSE_MODE_VISIBLE)


func set_carrying(carrying: bool) -> void :
	is_carrying = carrying
	if is_instance_valid(_parcel):
		_parcel.visible = carrying and not is_riding()
	if is_riding() and riding_vehicle.has_method("set_carrying"):
		riding_vehicle.set_carrying(carrying)


func set_riding_vehicle(vehicle: Node3D) -> void :
	var next_vehicle: Node3D = vehicle if is_instance_valid(vehicle) else null


	if _riding_active == is_instance_valid(next_vehicle) and riding_vehicle == next_vehicle:
		return
	if is_instance_valid(_camera_arm) and _excluded_vehicle_rid.is_valid():
		_camera_arm.remove_excluded_object(_excluded_vehicle_rid)
	_excluded_vehicle_rid = RID()
	riding_vehicle = next_vehicle
	var mounted: = is_riding()
	_riding_active = mounted
	collision_layer = 0 if mounted or _is_remote else 2
	collision_mask = 0 if mounted or _is_remote else 1
	velocity = Vector3.ZERO
	if mounted:
		if is_instance_valid(_camera_arm) and riding_vehicle is CollisionObject3D:
			_excluded_vehicle_rid = riding_vehicle.get_rid()
			_camera_arm.add_excluded_object(_excluded_vehicle_rid)
		if riding_vehicle.has_method("set_carrying"):
			riding_vehicle.set_carrying(is_carrying)
	_update_riding_visibility()


func is_riding() -> bool:
	return is_instance_valid(riding_vehicle)


func _update_riding_visibility() -> void :
	var mounted: = is_riding()
	if is_instance_valid(_visual):
		_visual.visible = not mounted
	if is_instance_valid(_identity_label):
		_identity_label.visible = not mounted and not _identity_name.is_empty()
	if is_instance_valid(_parcel):
		_parcel.visible = is_carrying and not mounted


func _update_camera_distance(delta: float) -> void :
	if not is_instance_valid(_camera_arm) or not is_instance_valid(_camera_pivot):
		return
	var target_distance: = 4.5
	var target_height: = 1.5
	if is_riding():
		target_distance = 6.0
		target_height = 1.7
		var vehicle_definition: Variant = riding_vehicle.get("definition")
		if vehicle_definition is Dictionary:
			var distance: Variant = vehicle_definition.get("camera_distance", target_distance)
			var height: Variant = vehicle_definition.get("camera_height", target_height)
			if (distance is float or distance is int) and is_finite(float(distance)) and float(distance) > 0.0:
				target_distance = float(distance)
			if (height is float or height is int) and is_finite(float(height)) and float(height) > 0.0:
				target_height = float(height)
	var blend: = 1.0 - exp(-8.0 * delta)
	_camera_arm.spring_length = lerpf(_camera_arm.spring_length, target_distance, blend)
	_camera_pivot.position.y = lerpf(_camera_pivot.position.y, target_height, blend)


func set_sensitivity(multiplier: float) -> void :
	_sensitivity = clampf(multiplier, 0.2, 3.0)


func set_view_direction(yaw_angle: float) -> void :
	_camera_yaw = yaw_angle
	if _is_remote:
		_remote_target_yaw = yaw_angle
	if is_instance_valid(_camera_pivot):
		_camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)
	if is_instance_valid(_visual):
		_visual.rotation.y = yaw_angle


func reset_at(position: Vector3) -> void :
	set_riding_vehicle(null)
	_spawn = position
	_spawn_initialized = true
	correct_network_position(position)


func configure_remote(display_name: String, color_index: int = 0) -> void :
	_is_remote = true
	controls_enabled = false
	collision_layer = 0
	collision_mask = 0
	set_network_identity(display_name, color_index)


func set_network_identity(display_name: String, color_index: int = 0) -> void :
	_identity_name = display_name
	_identity_index = posmod(color_index, IDENTITY_COLORS.size())
	if is_instance_valid(_identity_label):
		_identity_label.text = display_name
		_identity_label.visible = not is_riding() and not display_name.is_empty()
	if not _appearance_explicit:
		for index in range(_identity_materials.size()):
			_identity_materials[index].albedo_color = IDENTITY_COLORS[_identity_index][index]



# Appearance contains catalog IDs only; snapshots never provide colors or materials.
# It can be applied before _ready, and repeated snapshots preserve all mesh resources.
func apply_appearance(raw: Dictionary) -> void:
	var normalized: Dictionary = CosmeticCatalog.normalize_appearance(raw)
	var key: String = "%s:%s:%s" % [normalized["outfit"], normalized["backpack"], normalized["vehicle_paint"]]
	_appearance = normalized
	_appearance_explicit = true
	if key == _appearance_key:
		return
	_appearance_key = key
	if not _outfit_materials.is_empty():
		_apply_courier_appearance()


func get_appearance() -> Dictionary:
	return _appearance.duplicate(true)


func _apply_courier_appearance() -> void:
	var palette: Dictionary = CosmeticCatalog.outfit_palette(str(_appearance["outfit"]))
	for channel: String in _outfit_materials:
		var material: StandardMaterial3D = _outfit_materials[channel]
		material.albedo_color = Color(str(palette[channel]))
	var bag_palette: Dictionary = CosmeticCatalog.backpack_palette(str(_appearance["backpack"]))
	_backpack_materials[0].albedo_color = Color(str(bag_palette["color"]))
	_backpack_materials[1].albedo_color = Color(str(bag_palette["trim"]))
	var style: String = str(bag_palette["style"])
	for variant_id: String in _backpack_variants:
		var variant: Node3D = _backpack_variants[variant_id]
		variant.visible = variant_id == style
	for strap: Node3D in _backpack_straps:
		strap.visible = style != "messenger"


func apply_network_pose(pose: Dictionary) -> void :
	if not _is_remote:
		return
	var received_position: Variant = pose.get("position")
	if received_position is Vector3 and received_position.is_finite():
		_remote_target_position = received_position
		_remote_pose_initialized = true
	var received_yaw: Variant = pose.get("yaw")
	if received_yaw is float or received_yaw is int:
		var yaw: = float(received_yaw)
		if is_finite(yaw):
			_remote_target_yaw = yaw
	var received_velocity: Variant = pose.get("velocity")
	if received_velocity is Vector3 and received_velocity.is_finite():
		_received_velocity = received_velocity
	if pose.has("grounded"):
		_remote_grounded = bool(pose["grounded"])
	if pose.has("carrying"):
		set_carrying(bool(pose["carrying"]))


func get_network_pose() -> Dictionary:
	if is_riding() and riding_vehicle.has_method("get_network_pose"):
		var vehicle_pose: Dictionary = riding_vehicle.get_network_pose().duplicate(true)
		vehicle_pose["carrying"] = is_carrying
		return vehicle_pose
	return {
		"position": global_position, 
		"yaw": _visual.rotation.y if is_instance_valid(_visual) else _camera_yaw, 
		"velocity": _received_velocity if _is_remote else velocity, 
		"grounded": _remote_grounded if _is_remote else is_on_floor(), 
		"carrying": is_carrying, 
	}


func correct_network_position(position: Vector3) -> void :
	if is_riding():
		if riding_vehicle.has_method("correct_network_position"):
			riding_vehicle.correct_network_position(position)
		else:
			riding_vehicle.global_position = position
	global_position = position
	velocity = Vector3.ZERO
	if _is_remote:
		_remote_target_position = position
		_received_velocity = Vector3.ZERO
		_remote_pose_initialized = true
	reset_physics_interpolation()


func _build_camera() -> void :
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_camera_pivot.position = Vector3(0.0, 1.5, 0.0)
	_camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)
	add_child(_camera_pivot)

	var arm: = SpringArm3D.new()
	_camera_arm = arm
	arm.name = "CameraSpringArm"
	arm.spring_length = 4.5
	arm.margin = 0.08
	arm.collision_mask = 1
	var sphere: = SphereShape3D.new()
	sphere.radius = 0.25
	arm.shape = sphere
	arm.add_excluded_object(get_rid())
	_camera_pivot.add_child(arm)

	camera = Camera3D.new()
	camera.name = "CourierCamera"
	camera.fov = 65.0
	camera.near = 0.1
	camera.far = 250.0
	camera.current = true
	arm.add_child(camera)


func _build_courier() -> void :
	_visual = Node3D.new()
	_visual.name = "CourierVisual"
	add_child(_visual)
	var jacket: = _material(IDENTITY_COLORS[_identity_index][0])
	var jacket_dark: = _material(IDENTITY_COLORS[_identity_index][1])
	var jacket_light: = _material(IDENTITY_COLORS[_identity_index][2])
	_identity_materials = [jacket, jacket_dark, jacket_light]
	var pants: = _material(Color("#213044"))
	var cap: = _material(IDENTITY_COLORS[_identity_index][0])
	_outfit_materials = {"jacket": jacket, "dark": jacket_dark, "light": jacket_light, "cap": cap, "pants": pants}
	var bag_color: = _material(Color("#164293"))
	var bag_trim: = _material(Color("#246cdb"))
	_backpack_materials = [bag_color, bag_trim]
	var skin: = _material(Color("#efb886"))
	var cheeks: = _material(Color("#e89d7f"))
	var shoes: = _material(Color("#f0f1eb"))
	var hair: = _material(Color("#47332e"))
	var eyes: = _material(Color("#232b36"))
	var cardboard: = _material(Color("#ca9861"))
	var tape: = _material(Color("#f2cd86"))
	var box_ink: = _material(Color("#705544"))


	_box(_visual, "Jacket", Vector3(0.66, 0.58, 0.43), Vector3(0.0, 1.25, 0.0), jacket, 0.11)
	_box(_visual, "JacketHem", Vector3(0.63, 0.09, 0.4), Vector3(0.0, 0.985, 0.0), jacket_dark, 0.035)
	_box(_visual, "JacketZip", Vector3(0.021, 0.46, 0.014), Vector3(0.0, 1.25, -0.222), shoes)
	_box(_visual, "ZipPull", Vector3(0.035, 0.05, 0.017), Vector3(0.0, 1.45, -0.23), tape)
	_box(_visual, "CourierBadge", Vector3(0.14, 0.08, 0.018), Vector3(-0.145, 1.4, -0.219), tape, 0.014)
	_box(_visual, "BadgeParcel", Vector3(0.043, 0.037, 0.008), Vector3(-0.176, 1.4, -0.234), jacket_dark, 0.006)
	_box(_visual, "BadgeLine", Vector3(0.048, 0.009, 0.007), Vector3(-0.116, 1.408, -0.234), jacket_dark)
	for side in [-1.0, 1.0]:
		_box(_visual, "ChestPocket", Vector3(0.14, 0.12, 0.025), Vector3(side * 0.145, 1.16, -0.218), jacket_light, 0.021)
		_box(_visual, "PocketWelt", Vector3(0.115, 0.012, 0.009), Vector3(side * 0.145, 1.205, -0.237), jacket_dark)
		_backpack_straps.append(_box(_visual, "BackpackFrontStrap", Vector3(0.045, 0.45, 0.022), Vector3(side * 0.24, 1.25, -0.207), bag_color, 0.009))
		_backpack_straps.append(_box(_visual, "BackpackShoulderStrap", Vector3(0.047, 0.036, 0.36), Vector3(side * 0.24, 1.53, 0.025), bag_color, 0.012))
		_backpack_straps.append(_box(_visual, "StrapBuckle", Vector3(0.052, 0.04, 0.028), Vector3(side * 0.24, 1.195, -0.225), tape, 0.008))

	_ellipsoid(_visual, "Neck", Vector3(0.18, 0.2, 0.19), Vector3(0.0, 1.57, 0.0), skin)
	_ellipsoid(_visual, "Head", Vector3(0.4, 0.43, 0.365), Vector3(0.0, 1.765, -0.006), skin)
	_ellipsoid(_visual, "Hair", Vector3(0.392, 0.18, 0.357), Vector3(0.0, 1.89, 0.015), hair)
	for side in [-1.0, 1.0]:
		_ellipsoid(_visual, "Ear", Vector3(0.067, 0.12, 0.07), Vector3(side * 0.19, 1.765, -0.005), skin)
		_ellipsoid(_visual, "EarInset", Vector3(0.018, 0.06, 0.025), Vector3(side * 0.221, 1.768, -0.021), cheeks)
		_ellipsoid(_visual, "Eye", Vector3(0.037, 0.049, 0.019), Vector3(side * 0.077, 1.801, -0.181), eyes)
		_ellipsoid(_visual, "EyeHighlight", Vector3(0.01, 0.013, 0.006), Vector3(side * 0.077 - 0.006, 1.81, -0.192), shoes)
		var brow: = _box(_visual, "Eyebrow", Vector3(0.063, 0.014, 0.012), Vector3(side * 0.077, 1.85, -0.164), hair, 0.006)
		brow.rotation.z = side * -0.1
		_ellipsoid(_visual, "Cheek", Vector3(0.042, 0.025, 0.012), Vector3(side * 0.122, 1.742, -0.149), cheeks)
	_ellipsoid(_visual, "Nose", Vector3(0.053, 0.047, 0.05), Vector3(0.0, 1.765, -0.19), skin)
	_box(_visual, "Smile", Vector3(0.058, 0.011, 0.011), Vector3(0.0, 1.711, -0.184), hair, 0.004)

	_ellipsoid(_visual, "Cap", Vector3(0.433, 0.205, 0.405), Vector3(0.0, 1.948, 0.008), cap)
	_ellipsoid(_visual, "CapPeak", Vector3(0.355, 0.032, 0.25), Vector3(0.0, 1.941, -0.213), cap)
	_ellipsoid(_visual, "CapEmblem", Vector3(0.069, 0.047, 0.015), Vector3(0.0, 1.982, -0.184), tape)
	_box(_visual, "CapEmblemStripe", Vector3(0.036, 0.009, 0.008), Vector3(0.0, 1.982, -0.196), jacket_dark)

	_build_backpack_variants(_visual, Vector3(0.0, 1.26, 0.31), Vector3.ONE, bag_color, bag_trim, tape, shoes)

	_box(_visual, "TrouserHips", Vector3(0.52, 0.15, 0.33), Vector3(0.0, 0.935, 0.0), pants, 0.045)
	_left_leg = _limb(_visual, "LeftLeg", Vector3(-0.16, 0.94, 0.0))
	_right_leg = _limb(_visual, "RightLeg", Vector3(0.16, 0.94, 0.0))
	for leg in [_left_leg, _right_leg]:
		_box(leg, "Trousers", Vector3(0.23, 0.68, 0.255), Vector3(0.0, -0.36, 0.0), pants, 0.09)
		_box(leg, "TrouserCuff", Vector3(0.2, 0.075, 0.22), Vector3(0.0, -0.697, 0.0), pants, 0.025)
		_box(leg, "Shoe", Vector3(0.265, 0.17, 0.4), Vector3(0.0, -0.79, -0.065), shoes, 0.065)
		_box(leg, "ShoeSole", Vector3(0.27, 0.045, 0.405), Vector3(0.0, -0.869, -0.065), pants, 0.018)
		_box(leg, "ShoeTongue", Vector3(0.12, 0.018, 0.15), Vector3(0.0, -0.705, -0.088), tape, 0.008)
		for lace in range(3):
			_box(leg, "ShoeLace", Vector3(0.135, 0.014, 0.016), Vector3(0.0, -0.696, -0.135 + lace * 0.04), jacket_dark)

	_left_arm = _limb(_visual, "LeftArm", Vector3(-0.4, 1.46, 0.0))
	_right_arm = _limb(_visual, "RightArm", Vector3(0.4, 1.46, 0.0))
	for arm in [_left_arm, _right_arm]:
		_capsule(arm, "Sleeve", Vector3(0.22, 0.5, 0.235), Vector3(0.0, -0.22, 0.0), jacket)
		_box(arm, "SleeveCuff", Vector3(0.202, 0.06, 0.215), Vector3(0.0, -0.448, 0.0), jacket_dark, 0.027)
		_ellipsoid(arm, "Hand", Vector3(0.17, 0.17, 0.19), Vector3(0.0, -0.525, 0.0), skin)

	_parcel = Node3D.new()
	_parcel.name = "CarriedParcel"
	_parcel.position = Vector3(0.0, 1.08, -0.52)
	_visual.add_child(_parcel)
	_box(_parcel, "Box", Vector3(0.48, 0.34, 0.36), Vector3.ZERO, cardboard, 0.028)
	_box(_parcel, "TopTape", Vector3(0.067, 0.007, 0.322), Vector3(0.0, 0.172, 0.0), tape)
	_box(_parcel, "FrontTape", Vector3(0.067, 0.288, 0.007), Vector3(0.0, 0.0, -0.182), tape)
	_box(_parcel, "ShippingLabel", Vector3(0.137, 0.105, 0.009), Vector3(-0.12, 0.034, -0.185), shoes, 0.008)
	_box(_parcel, "LabelAddress", Vector3(0.096, 0.009, 0.007), Vector3(-0.12, 0.063, -0.193), box_ink)
	for stripe in range(8):
		var stripe_width: = 0.003 if stripe % 3 == 0 else 0.006
		_box(_parcel, "LabelBarcode", Vector3(stripe_width, 0.025, 0.007), Vector3(-0.161 + stripe * 0.012, 0.027, -0.193), box_ink)
	_box(_parcel, "ParcelSideMark", Vector3(0.008, 0.08, 0.055), Vector3(0.242, 0.017, 0.035), box_ink)
	_parcel.visible = is_carrying

	_identity_label = Label3D.new()
	_identity_label.name = "CourierName"
	_identity_label.position = Vector3(0.0, 2.35, 0.0)
	_identity_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_identity_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_identity_label.font_size = 36
	_identity_label.pixel_size = 0.008
	_identity_label.outline_size = 6
	_identity_label.outline_modulate = Color("#182331")
	_identity_label.text = _identity_name
	_identity_label.visible = not is_riding() and not _identity_name.is_empty()
	add_child(_identity_label)
	if _appearance_explicit:
		_apply_courier_appearance()



# Four small static variant groups are built once, then only visibility/materials
# change. The group is a visual child; it owns no collider or movement script.
func _build_backpack_variants(parent: Node3D, center: Vector3, fit: Vector3, color: StandardMaterial3D, trim: StandardMaterial3D, badge: StandardMaterial3D, cream: StandardMaterial3D) -> void:
	var variants: = Node3D.new()
	variants.name = "BackpackVariants"
	parent.add_child(variants)
	var classic: = _backpack_group(variants, "BackpackClassic", center, fit)
	_box(classic, "DeliveryBackpack", Vector3(0.53, 0.57, 0.26), Vector3(0.0, 1.26, 0.31) - Vector3(0.0, 1.26, 0.31), color, 0.065)
	_box(classic, "BackpackFlap", Vector3(0.465, 0.155, 0.035), Vector3(0.0, 1.415, 0.443) - Vector3(0.0, 1.26, 0.31), trim, 0.025)
	_box(classic, "BackpackStripe", Vector3(0.425, 0.055, 0.012), Vector3(0.0, 1.294, 0.447) - Vector3(0.0, 1.26, 0.31), badge, 0.011)
	_box(classic, "BackpackPocket", Vector3(0.425, 0.19, 0.063), Vector3(0.0, 1.148, 0.448) - Vector3(0.0, 1.26, 0.31), trim, 0.037)
	_box(classic, "BackpackPocketZip", Vector3(0.34, 0.015, 0.012), Vector3(0.0, 1.214, 0.484) - Vector3(0.0, 1.26, 0.31), cream)
	_box(classic, "BackpackZipPull", Vector3(0.015, 0.04, 0.013), Vector3(0.13, 1.199, 0.495) - Vector3(0.0, 1.26, 0.31), badge)
	_box(classic, "BackpackParcelBadge", Vector3(0.08, 0.063, 0.012), Vector3(0.0, 1.145, 0.486) - Vector3(0.0, 1.26, 0.31), badge, 0.013)
	_box(classic, "BackpackParcelTape", Vector3(0.012, 0.05, 0.009), Vector3(0.0, 1.145, 0.496) - Vector3(0.0, 1.26, 0.31), cream)
	for side in [-1.0, 1.0]:
		_box(classic, "BackpackSeam", Vector3(0.012, 0.31, 0.011), Vector3(side * 0.221, 1.297, 0.433) - Vector3(0.0, 1.26, 0.31), trim)
		_box(classic, "BackpackSidePocket", Vector3(0.07, 0.19, 0.15), Vector3(side * 0.262, 1.135, 0.3) - Vector3(0.0, 1.26, 0.31), trim, 0.028)
	_box(classic, "BackpackHandle", Vector3(0.12, 0.034, 0.052), Vector3(0.0, 1.568, 0.3) - Vector3(0.0, 1.26, 0.31), color, 0.015)

	var compact: Node3D = classic.duplicate(0) as Node3D
	compact.name = "BackpackCompact"
	compact.scale = fit * Vector3(0.79, 0.74, 0.82)
	compact.position = center + Vector3(0.0, -0.025, -0.015)
	variants.add_child(compact)

	var rolltop: = _backpack_group(variants, "BackpackRolltop", center, fit)
	_box(rolltop, "DeliveryBackpack", Vector3(0.43, 0.65, 0.25), Vector3(0.0, 0.03, 0.0), color, 0.065)
	_box(rolltop, "RolltopFold", Vector3(0.435, 0.12, 0.25), Vector3(0.0, 0.338, 0.0), trim, 0.034)
	_ellipsoid(rolltop, "RolltopRoll", Vector3(0.48, 0.105, 0.13), Vector3(0.0, 0.412, 0.0), color)
	_box(rolltop, "RolltopClosure", Vector3(0.035, 0.29, 0.023), Vector3(0.0, 0.245, 0.139), color, 0.008)
	_box(rolltop, "RolltopBuckle", Vector3(0.066, 0.052, 0.032), Vector3(0.0, 0.133, 0.151), badge, 0.012)
	_box(rolltop, "RolltopPocket", Vector3(0.35, 0.21, 0.058), Vector3(0.0, -0.151, 0.139), trim, 0.027)
	_box(rolltop, "RolltopPocketZip", Vector3(0.28, 0.013, 0.016), Vector3(0.0, -0.064, 0.174), cream, 0.004)
	for side in [-1.0, 1.0]:
		_box(rolltop, "RolltopSidePocket", Vector3(0.064, 0.23, 0.13), Vector3(side * 0.219, -0.132, 0.0), trim, 0.018)
	_box(rolltop, "RolltopStripe", Vector3(0.26, 0.029, 0.016), Vector3(0.0, -0.171, 0.177), badge, 0.005)

	var messenger: = _backpack_group(variants, "BackpackMessenger", center, fit)
	var messenger_body: = Node3D.new()
	messenger_body.name = "MessengerBody"
	messenger_body.position = Vector3(0.19, -0.115, 0.02)
	messenger_body.rotation.z = 0.1
	messenger.add_child(messenger_body)
	_box(messenger_body, "DeliveryBackpack", Vector3(0.57, 0.35, 0.2), Vector3.ZERO, color, 0.055)
	_box(messenger_body, "MessengerFlap", Vector3(0.525, 0.22, 0.035), Vector3(0.0, 0.055, 0.107), trim, 0.034)
	_box(messenger_body, "MessengerStripe", Vector3(0.39, 0.029, 0.016), Vector3(0.0, 0.018, 0.132), badge, 0.008)
	for side in [-1.0, 1.0]:
		_box(messenger_body, "MessengerClosure", Vector3(0.033, 0.16, 0.02), Vector3(side * 0.163, -0.074, 0.127), color, 0.005)
		_box(messenger_body, "MessengerBuckle", Vector3(0.061, 0.045, 0.027), Vector3(side * 0.163, -0.05, 0.141), badge, 0.009)
	var front_strap: = _box(messenger, "CrossbodyFrontStrap", Vector3(0.064, 0.75, 0.025), Vector3(0.0, 0.045, -0.537), color, 0.012)
	front_strap.rotation.z = -0.52
	var rear_strap: = _box(messenger, "CrossbodyRearStrap", Vector3(0.063, 0.7, 0.025), Vector3(0.0, 0.052, -0.077), color, 0.012)
	rear_strap.rotation.z = 0.52

	_backpack_variants = {"classic": classic, "compact": compact, "rolltop": rolltop, "messenger": messenger}
	for style: String in _backpack_variants:
		var group: Node3D = _backpack_variants[style]
		group.visible = style == "classic"


func _backpack_group(parent: Node3D, group_name: String, center: Vector3, fit: Vector3) -> Node3D:
	var group: = Node3D.new()
	group.name = group_name
	group.position = center
	group.scale = fit
	parent.add_child(group)
	return group


func _animate_courier(delta: float, running: bool) -> void :
	var horizontal_speed: = Vector2(velocity.x, velocity.z).length()
	var grounded: = _remote_grounded if _is_remote else is_on_floor()
	var walking: = horizontal_speed > 0.1 and grounded
	var stride: = 0.0
	if walking:
		_gait_phase += delta * (14.0 if running else 10.0)
		stride = sin(_gait_phase) * (0.75 if running else 0.48)
	var blend: = 1.0 - exp(-16.0 * delta)
	_left_leg.rotation.x = lerpf(_left_leg.rotation.x, stride, blend)
	_right_leg.rotation.x = lerpf(_right_leg.rotation.x, - stride, blend)
	_visual.position.y = absf(sin(_gait_phase)) * 0.035 if walking else 0.0
	if is_carrying:
		_left_arm.rotation.x = lerpf(_left_arm.rotation.x, 0.95, blend)
		_right_arm.rotation.x = lerpf(_right_arm.rotation.x, 0.95, blend)
		_left_arm.rotation.z = lerpf(_left_arm.rotation.z, 0.28, blend)
		_right_arm.rotation.z = lerpf(_right_arm.rotation.z, -0.28, blend)
	else:
		_left_arm.rotation.x = lerpf(_left_arm.rotation.x, - stride * 0.8, blend)
		_right_arm.rotation.x = lerpf(_right_arm.rotation.x, stride * 0.8, blend)
		_left_arm.rotation.z = lerpf(_left_arm.rotation.z, 0.08, blend)
		_right_arm.rotation.z = lerpf(_right_arm.rotation.z, -0.08, blend)


func _material(color: Color) -> StandardMaterial3D:
	var material: = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


func _limb(parent: Node3D, limb_name: String, origin: Vector3) -> Node3D:
	var limb: = Node3D.new()
	limb.name = limb_name
	limb.position = origin
	parent.add_child(limb)
	return limb


func _box(parent: Node3D, mesh_name: String, size: Vector3, origin: Vector3, material: StandardMaterial3D, radius: float = -1.0) -> MeshInstance3D:
	var instance: = MeshInstance3D.new()
	instance.name = mesh_name
	var edge_radius: = radius if radius >= 0.0 else minf(minf(size.x, size.y), size.z) * 0.3
	instance.mesh = RoundedGeometry.box(size, edge_radius, 3)
	instance.material_override = material
	instance.position = origin
	parent.add_child(instance)
	return instance


func _ellipsoid(parent: Node3D, mesh_name: String, size: Vector3, origin: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: = MeshInstance3D.new()
	instance.name = mesh_name
	var sphere: = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	instance.mesh = sphere
	instance.scale = size
	instance.material_override = material
	instance.position = origin
	parent.add_child(instance)
	return instance


func _capsule(parent: Node3D, mesh_name: String, size: Vector3, origin: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: = MeshInstance3D.new()
	instance.name = mesh_name
	var capsule: = CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	capsule.radial_segments = 16
	capsule.rings = 4
	instance.mesh = capsule
	instance.scale = Vector3(size.x, size.y * 0.5, size.z)
	instance.material_override = material
	instance.position = origin
	parent.add_child(instance)
	return instance
