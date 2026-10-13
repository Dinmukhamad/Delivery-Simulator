extends SubViewportContainer
# This model shares the in-game visuals but has its own world, camera and lights.
const PlayerScript = preload("res://scripts/player.gd")

var _preview_viewport: SubViewport
var _courier: CharacterBody3D
var _appearance: Dictionary = {}
var _angle: float = -0.35


func _ready() -> void:
	name = "CosmeticPreview"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "CosmeticPreviewViewport"
	_preview_viewport.size = Vector2i(360, 440)
	_preview_viewport.own_world_3d = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_preview_viewport)
	var world: Node3D = Node3D.new()
	world.name = "PreviewWorld"
	_preview_viewport.add_child(world)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("eee8d9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fffaf0")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key_light.light_energy = 1.3
	world.add_child(key_light)
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill_light.light_color = Color("c4e3de")
	fill_light.light_energy = 0.45
	world.add_child(fill_light)
	var podium: MeshInstance3D = MeshInstance3D.new()
	var podium_mesh: CylinderMesh = CylinderMesh.new()
	podium_mesh.top_radius = 0.75
	podium_mesh.bottom_radius = 0.82
	podium_mesh.height = 0.1
	podium_mesh.radial_segments = 32
	podium.mesh = podium_mesh
	podium.position.y = -0.055
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("d9d5c6")
	material.roughness = 0.9
	podium.material_override = material
	world.add_child(podium)
	_courier = PlayerScript.new()
	_courier.name = "PreviewCourier"
	_courier.configure_remote("", 0)
	world.add_child(_courier)
	# The preview never moves, reads input or runs the gameplay camera.
	_courier.process_mode = Node.PROCESS_MODE_DISABLED
	_courier.rotation.y = _angle
	_courier.apply_appearance(_appearance)
	var camera: Camera3D = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(3.0, 1.8, -4.2)
	camera.fov = 31.0
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	camera.current = true


func apply_appearance(appearance: Dictionary) -> void:
	_appearance = appearance.duplicate(true)
	if is_instance_valid(_courier):
		_courier.apply_appearance(_appearance)


func rotate_model(angle: float) -> void:
	_angle += angle
	if is_instance_valid(_courier):
		_courier.rotation.y = _angle


func show_back(showing: bool) -> void:
	_angle = PI - 0.3 if showing else -0.35
	if is_instance_valid(_courier):
		_courier.rotation.y = _angle
