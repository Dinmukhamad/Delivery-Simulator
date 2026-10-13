extends Node3D

const RoundedGeometry = preload("res://scripts/rounded_geometry.gd")
const CityLayout = preload("res://scripts/city_layout.gd")




var pickup_points: Array[Dictionary] = []
var delivery_points: Array[Dictionary] = []
var spawn_position: Vector3 = Vector3(-23.0, 0.15, 4.0)

var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _objective: Node3D
var _objective_ring: Node3D
var _elapsed: float = 0.0
var _built: bool = false
var _map_roads: Array[Rect2] = []
var _map_paths: Array[Rect2] = []
var _map_obstacles: Array[Rect2] = []
var _map_buildings: Array[Dictionary] = []
var _extension_windows: bool = false
var _extension_pickups: Array[Dictionary] = []
var _extension_deliveries: Array[Dictionary] = []
var _map_fountains: Array[Dictionary] = []

const SIZE: float = CityLayout.SIZE
const GRASS: = Color("9ac47a")
const ROAD: = Color("535f6c")
const SIDEWALK: = Color("e9dfc7")
const CREAM: = Color("fff0d1")
const TEAL: = Color("39a9a6")
const ORANGE: = Color("f5a353")
const DARK: = Color("284653")


func _ready() -> void :
	if _built:
		return
	_built = true
	_make_lighting()
	_make_ground_and_roads()
	_make_city()
	_make_expanded_city()
	_make_park()
	_make_large_parks()
	_make_street_details()
	_make_delivery_points()
	_batch_static_geometry()


func _process(delta: float) -> void :
	_elapsed += delta
	if is_instance_valid(_objective_ring):
		_objective_ring.rotation.y += delta * 0.8
		_objective_ring.position.y = 5.2 + sin(_elapsed * 2.0) * 0.18


func set_objective(position_value: Vector3, title: String, color: Color) -> void :
	clear_objective()
	_objective = Node3D.new()
	_objective.name = "CurrentDeliveryObjective"
	_objective.position = position_value
	add_child(_objective)
	var beam_material: = StandardMaterial3D.new()
	beam_material.albedo_color = Color(color, 0.16)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam: = _cylinder(_objective, Vector3(0, 8, 0), 0.5, 0.5, 16.0, beam_material, 12)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var marker_material: = _material("objective_" + color.to_html(), color, true)
	_objective_ring = Node3D.new()
	_objective.add_child(_objective_ring)
	var pointer: = _cylinder(_objective_ring, Vector3.ZERO, 0.0, 0.8, 1.0, marker_material, 4)
	pointer.rotation.z = PI
	_label(_objective, title, Vector3(0, 6.5, 0), 0.018, color, 52)
	var circle: = TorusMesh.new()
	circle.inner_radius = 0.9
	circle.outer_radius = 1.08
	circle.rings = 16
	circle.ring_segments = 8
	var ground_ring: = MeshInstance3D.new()
	ground_ring.mesh = circle
	ground_ring.material_override = marker_material
	ground_ring.position = Vector3(0, 0.1, 0)
	ground_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_objective.add_child(ground_ring)


func clear_objective() -> void :
	if is_instance_valid(_objective):
		_objective.queue_free()
	_objective = null
	_objective_ring = null


func _make_lighting() -> void :
	var environment: = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: = Sky.new()
	var sky_material: = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("78c5e9")
	sky_material.sky_horizon_color = Color("e1ecda")
	sky_material.ground_bottom_color = Color("79986b")
	sky_material.ground_horizon_color = Color("e1ecda")
	sky_material.sky_curve = 0.2
	sky_material.sun_angle_max = 12.0
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7ddeb")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment: = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sunlight: = DirectionalLight3D.new()
	sunlight.name = "AfternoonSun"
	sunlight.rotation_degrees = Vector3(-48, -35, 0)
	sunlight.light_color = Color("fff0d2")
	sunlight.light_energy = 0.65
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 110.0
	add_child(sunlight)


func _make_ground_and_roads() -> void:
	_box(self, Vector3(0, -0.3, 0), Vector3(SIZE, 0.6, SIZE), _material("grass", GRASS), true)
	var pavement: Material = _material("sidewalk", SIDEWALK)
	var asphalt: Material = _material("road", ROAD)
	var markings: Material = _material("road_markings", CREAM)
	# Keep the twenty original buildings. Perimeter streets use +/-84m rather
	# than +/-80m so they do not cross the old houses and flower shop.
	for axis in CityLayout.ROAD_AXES:
		for vertical in [true, false]:
			for segment in _road_segments(axis, vertical):
				var length_value: float = segment.y - segment.x
				var midpoint: float = (segment.x + segment.y) * 0.5
				var location: Vector3 = Vector3(axis, 0.013, midpoint) if vertical else Vector3(midpoint, 0.013, axis)
				var size_value: Vector3 = Vector3(14, 0.025, length_value) if vertical else Vector3(length_value, 0.025, 14)
				_box(self, location, size_value, pavement)
	for axis in CityLayout.ROAD_AXES:
		for vertical in [true, false]:
			for segment in _road_segments(axis, vertical):
				var length_value: float = segment.y - segment.x
				var midpoint: float = (segment.x + segment.y) * 0.5
				var location: Vector3 = Vector3(axis, 0.035, midpoint) if vertical else Vector3(midpoint, 0.037, axis)
				var size_value: Vector3 = Vector3(9, 0.03, length_value) if vertical else Vector3(length_value, 0.03, 9)
				_box(self, location, size_value, asphalt)
				for dash_index in range(-31, 32):
					var along: float = float(dash_index) * 8.0
					if along < segment.x + 2.0 or along > segment.y - 2.0 or _at_junction(along):
						continue
					location = Vector3(axis, 0.066, along) if vertical else Vector3(along, 0.068, axis)
					size_value = Vector3(0.16, 0.025, 3.2) if vertical else Vector3(3.2, 0.025, 0.16)
					_box(self, location, size_value, markings)
	for junction_x in CityLayout.ROAD_AXES:
		for junction_z in CityLayout.ROAD_AXES:
			if not _is_road(Vector2(junction_x, junction_z)):
				continue
			for stripe_index in range(5):
				var stripe_x: float = junction_x - 3.4 + float(stripe_index) * 1.7
				if _is_road(Vector2(stripe_x, junction_z + 7.5)):
					_box(self, Vector3(stripe_x, 0.075, junction_z + 7.5), Vector3(0.75, 0.025, 2.2), markings)
	var hedge_material: Material = _material("boundary_hedge", Color("5b945d"))
	for axis_index in [0, 1]:
		for sign_value in [-1.0, 1.0]:
			var location: Vector3 = Vector3(sign_value * 257.1, 0.8, 0) if axis_index == 0 else Vector3(0, 0.8, sign_value * 257.1)
			var dimensions: Vector3 = Vector3(1.6, 1.6, SIZE) if axis_index == 0 else Vector3(SIZE, 1.6, 1.6)
			_rounded_box(self, location, dimensions, hedge_material, 0.45)
			var wall_dimensions: Vector3 = Vector3(1.6, 7, SIZE) if axis_index == 0 else Vector3(SIZE, 7, 1.6)
			_static_box(location + Vector3(0, 2.7, 0), wall_dimensions)


func _road_segments(axis: float, vertical: bool) -> Array[Vector2]:
	var result: Array[Vector2] = [Vector2(-256.5, 256.5)]
	# Interior roads end at perimeter-road centrelines, leaving large parks
	# continuous while their edges remain connected to the street network.
	for park_gap in [Rect2(-240, -240, 156, 156), Rect2(84, 120, 156, 120)]:
		var across_min: float = park_gap.position.x if vertical else park_gap.position.y
		var across_max: float = park_gap.end.x if vertical else park_gap.end.y
		if axis <= across_min or axis >= across_max:
			continue
		var gap_min: float = park_gap.position.y if vertical else park_gap.position.x
		var gap_max: float = park_gap.end.y if vertical else park_gap.end.x
		var next: Array[Vector2] = []
		for segment in result:
			if gap_max <= segment.x or gap_min >= segment.y:
				next.append(segment)
				continue
			if gap_min > segment.x:
				next.append(Vector2(segment.x, gap_min))
			if gap_max < segment.y:
				next.append(Vector2(gap_max, segment.y))
		result = next
	return result


func _at_junction(along: float) -> bool:
	for axis in CityLayout.ROAD_AXES:
		if absf(along - axis) < 7.0:
			return true
	return false


func _is_road(flat: Vector2) -> bool:
	for rect in _map_roads:
		if rect.has_point(flat):
			return true
	return false


func _make_expanded_city() -> void:
	_extension_windows = true
	for definition in CityLayout.get_extension_buildings():
		var location: Vector3 = definition["position"]
		var dimensions: Vector3 = definition["size"]
		var kind: String = str(definition["kind"])
		var name_value: String = str(definition["name"])
		if kind == "house":
			_house(name_value, location, definition["color"])
		elif kind == "shop":
			_shop(name_value, location, dimensions, definition["color"], str(definition["sign"]), TEAL if definition["district"] != "industrial" else ORANGE)
		else:
			var building: Node3D = _building(name_value, location, dimensions, definition["color"], false, kind == "warehouse")
			if kind == "warehouse":
				_roller_door(building, Vector3(-3.8, 2.05, -dimensions.z * 0.5 - 0.03), 9.0, 4.0)
				_door(building, Vector3(8.0, 0, -dimensions.z * 0.5 - 0.03), true)
				_facade_label(building, name_value, Vector3(0, dimensions.y - 1.6, -dimensions.z * 0.5 - 0.4), 0.010, CREAM, 42)
				for parcel_x in [-10.0, -8.5]:
					_parcel(location + Vector3(parcel_x, 0, -dimensions.z * 0.5 - 2.3))
				_rounded_box(building, Vector3(dimensions.x * 0.35, dimensions.y + 0.7, 0), Vector3(2.3, 1.4, 3.5), _material("warehouse_ac", Color("8d9da5")), 0.12)
			elif kind == "apartment":
				for balcony_floor in range(1, mini(4, maxi(2, int(dimensions.y / 4.0)))):
					for side in [-1.0, 1.0]:
						_balcony(building, Vector3(side * 7.5, 3.9 + float(balcony_floor - 1) * 3.8, -dimensions.z * 0.5 - 0.3))
				_facade_label(building, "№ " + str(definition["id"]).get_slice("_", 1), Vector3(3.5, 2.0, -dimensions.z * 0.5 - 0.3), 0.010, CREAM, 42)
				_bin(location + Vector3(dimensions.x * 0.5 - 1.5, 0, -dimensions.z * 0.5 - 1.3), true)
			elif kind == "office":
				_office_crown(building, dimensions, name_value)
			else:
				_facade_label(building, name_value, Vector3(0, dimensions.y - 1.3, -dimensions.z * 0.5 - 0.35), 0.010, DARK, 42)
				for post_x in [-dimensions.x * 0.40, dimensions.x * 0.40]:
					_rounded_box(building, Vector3(post_x, 2.2, -dimensions.z * 0.5 - 0.12), Vector3(0.5, 4.2, 0.5), _material("civic_columns", CREAM), 0.12)
		# Footprints and district identities come from this exact built geometry.
		if not _map_buildings.is_empty():
			_map_buildings[-1]["id"] = str(definition["id"])
			_map_buildings[-1]["kind"] = kind
			_map_buildings[-1]["district"] = str(definition["district"])
			_map_buildings[-1]["height"] = dimensions.y
		var front: float = -dimensions.z * 0.5 - 3.0
		var point_position: Vector3 = location + Vector3(0, 0, front)
		var connection_z: float = _nearest_road_axis(point_position.z)
		var path_length: float = absf(point_position.z - connection_z)
		if path_length > 0.01:
			_box(self, Vector3(point_position.x, 0.025, (point_position.z + connection_z) * 0.5), Vector3(2.8, 0.03, path_length), _material("door_path", Color("d9caae")))
		_box(self, location + Vector3(0, 0.025, -dimensions.z * 0.5 - 1.8), Vector3(minf(18, dimensions.x), 0.03, 3.6), _material("forecourt", Color("ead4ac")))
		if bool(definition["pickup"]):
			var pickup_position: Vector3 = point_position + Vector3(-4.0 if bool(definition["delivery"]) else 0.0, 0, 0)
			_extension_pickups.append({"id": "pickup_" + str(definition["id"]), "name": name_value, "position": pickup_position, "district": str(definition["district"])})
		if bool(definition["delivery"]):
			var delivery_position: Vector3 = point_position + Vector3(4.0 if bool(definition["pickup"]) else 0.0, 0, 0)
			_extension_deliveries.append({"id": "delivery_" + str(definition["id"]), "name": "Дом на Садовой " + name_value.trim_prefix("House ") if kind == "house" else name_value, "position": delivery_position, "district": str(definition["district"])})
	_extension_windows = false
	_make_district_forecourts()
	_make_extended_street_details()


func _office_crown(building: Node3D, dimensions: Vector3, title: String) -> void:
	var trim: Material = _material("office_trim", Color("536d7a"))
	for floor_band in range(1, mini(8, maxi(2, int(dimensions.y / 4.0)))):
		var y_value: float = float(floor_band) * dimensions.y / float(mini(8, maxi(2, int(dimensions.y / 4.0))))
		_rounded_box(building, Vector3(0, y_value, -dimensions.z * 0.5 - 0.05), Vector3(dimensions.x + 0.18, 0.18, 0.25), trim, 0.04)
		_rounded_box(building, Vector3(0, y_value, dimensions.z * 0.5 + 0.05), Vector3(dimensions.x + 0.18, 0.18, 0.25), trim, 0.04)
	var canopy: MeshInstance3D = _rounded_box(building, Vector3(0, 3.6, -dimensions.z * 0.5 - 1.2), Vector3(6.5, 0.25, 2.9), _material("office_canopy", TEAL), 0.11)
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_facade_label(building, title, Vector3(0, dimensions.y - 1.8, -dimensions.z * 0.5 - 0.35), 0.014, DARK, 48)
	_rounded_box(building, Vector3(0, dimensions.y + 0.9, 0), Vector3(dimensions.x * 0.45, 1.5, dimensions.z * 0.4), _material("office_roof", Color("788e99")), 0.18)
	_cylinder(building, Vector3(0, dimensions.y + 3.8, 0), 0.07, 0.1, 5.0, _material("metal", DARK), 12)
	for post_x in [-2.7, 2.7]:
		_cylinder(building, Vector3(post_x, 1.7, -dimensions.z * 0.5 - 2.2), 0.07, 0.08, 3.4, _material("metal", DARK), 12)


func _extension_window(parent: Node3D, location: Vector3, width: float, height: float, yaw: float, variation: int) -> void:
	# Fewer meshes on the new district façades; the original detailed windows stay.
	var window: Node3D = Node3D.new()
	window.name = "DistrictWindow"
	window.position = location
	window.rotation.y = yaw
	parent.add_child(window)
	_rounded_box(window, Vector3(0, 0, -0.08), Vector3(width + 0.26, height + 0.26, 0.18), _material("window_frame", CREAM), 0.07)
	_rounded_box(window, Vector3(0, 0, -0.19), Vector3(width, height, 0.045), _material("district_glass_" + str(variation == 4), Color("7baebe") if variation != 4 else Color("dbcda9")), 0.024)
	_box(window, Vector3(0, 0, -0.23), Vector3(0.07, height, 0.035), _material("window_frame", CREAM))


func _nearest_road_axis(value: float) -> float:
	var nearest: float = 0.0
	var distance_value: float = INF
	for axis in CityLayout.ROAD_AXES:
		if absf(value - axis) < distance_value:
			nearest = axis
			distance_value = absf(value - axis)
	return nearest


func _add_point_district(point: Dictionary) -> void:
	var point_position: Vector3 = point["position"]
	var district: String = str(point.get("district", CityLayout.get_district_id(point_position)))
	point["district"] = district
	point["district_id"] = district
	point["district_name"] = CityLayout.get_district_name(point_position)


func _make_district_forecourts() -> void:
	_parking_lot(Vector3(-180, 0, -20), Vector2(28, 26), 3)
	_parking_lot(Vector3(140, 0, -180), Vector2(28, 26), 2)
	_parking_lot(Vector3(220, 0, -140), Vector2(28, 26), 1)
	_parking_lot(Vector3(220, 0, -60), Vector2(26, 26), 2)
	_plaza(Vector3(20, 0, -180), Vector2(28, 28), true)
	_plaza(Vector3(-20, 0, -140), Vector2(28, 28), false)
	_plaza(Vector3(140, 0, -20), Vector2(28, 28), false)
	_plaza(Vector3(180, 0, 20), Vector2(28, 28), true)
	for courtyard in [Vector3(-20, 0, 140), Vector3(-180, 0, 180), Vector3(-60, 0, 180), Vector3(-220, 0, 220), Vector3(-102, 0, 220)]:
		_plaza(courtyard, Vector2(24, 22), false)
		_tree(courtyard + Vector3(-8, 0, 5), 1.15, 0)
		_tree(courtyard + Vector3(8, 0, 5), 1.05, 1)
	for yard in [Vector3(140, 0, -180), Vector3(220, 0, -140), Vector3(102, 0, -102)]:
		for index in range(2):
			var container_position: Vector3 = yard + Vector3(-7 + float(index) * 14, 1.5, 5)
			_rounded_box(self, container_position, Vector3(5.5, 3, 10), _material("container_" + str(index), TEAL if index == 0 else Color("b27a5c")), 0.13, true)
			for rib in range(7):
				_box(self, container_position + Vector3(-2.4 + float(rib) * 0.8, 0, -5.02), Vector3(0.07, 2.8, 0.045), _material("container_ribs", Color("d2c6b3")))
	_label(self, "ДЕЛОВОЙ ЦЕНТР", Vector3(-180, 3, -84), 0.016, DARK, 56)
	_label(self, "СЕВЕРНЫЙ РАЙОН", Vector3(-20, 3, -240), 0.016, DARK, 56)
	_label(self, "ЛОГИСТИЧЕСКИЙ РАЙОН", Vector3(180, 3, -240), 0.016, DARK, 56)
	_label(self, "ЖИЛЫЕ КВАРТАЛЫ", Vector3(-100, 3, 84), 0.016, DARK, 56)


func _parking_lot(location: Vector3, dimensions: Vector2, car_count: int) -> void:
	_box(self, location + Vector3(0, 0.035, 0), Vector3(dimensions.x, 0.035, dimensions.y), _material("parking_asphalt", Color("69747a")))
	for bay in range(6):
		_box(self, location + Vector3(-12 + float(bay) * 4.8, 0.07, -4), Vector3(0.12, 0.025, 8), _material("parking_lines", CREAM))
	for index in range(car_count):
		var car_position: Vector3 = location + Vector3(-8 + float(index) * 7, 0, -4)
		_parked_van(car_position, index)
	_lamp(location + Vector3(12, 0, 10))
	_bin(location + Vector3(-12, 0, 10), true)


func _parked_van(location: Vector3, variation: int) -> void:
	var paint: Material = _material("parked_car_" + str(variation % 3), [Color("d3ad86"), Color("84aeb7"), Color("c8b9ca")][variation % 3])
	_rounded_box(self, location + Vector3(0, 0.9, 0), Vector3(2.1, 1.35, 4.4), paint, 0.27, true)
	_rounded_box(self, location + Vector3(0, 1.8, 0.2), Vector3(1.8, 0.85, 2.6), paint, 0.22)
	_rounded_box(self, location + Vector3(0, 1.83, -1.15), Vector3(1.6, 0.59, 0.05), _material("car_window", Color("6e99a8")), 0.07)
	for side in [-1.0, 1.0]:
		for axle in [-1.35, 1.35]:
			var wheel: MeshInstance3D = _cylinder(self, location + Vector3(side * 1.05, 0.48, axle), 0.39, 0.39, 0.22, _material("car_tyre", DARK), 12)
			wheel.rotation.z = PI / 2.0
		_rounded_box(self, location + Vector3(side * 0.66, 0.97, -2.23), Vector3(0.43, 0.25, 0.06), _material("car_light", CREAM), 0.05)


func _plaza(location: Vector3, dimensions: Vector2, fountain: bool) -> void:
	_box(self, location + Vector3(0, 0.025, 0), Vector3(dimensions.x, 0.03, dimensions.y), _material("forecourt", Color("ead4ac")))
	for side in [-1.0, 1.0]:
		_bench(location + Vector3(side * 8.0, 0, 4), -side * PI / 2.0)
		_planter(location + Vector3(side * 10.0, 0, -8), 0.9, true)
	if fountain:
		_small_fountain(location, 3.6)
	else:
		_cylinder(self, location + Vector3(0, 0.1, 0), 2.8, 2.8, 0.12, _material("plaza_circle", CREAM), 16)


func _small_fountain(location: Vector3, radius: float) -> void:
	_map_fountains.append({"position": location, "radius": radius})
	_cylinder(self, location + Vector3(0, 0.12, 0), radius, radius, 0.18, _material("fountain_rim", CREAM), 20)
	_cylinder(self, location + Vector3(0, 0.23, 0), radius - 0.4, radius - 0.4, 0.06, _material("water", Color("69bdca")), 20)
	_cylinder(self, location + Vector3(0, 0.7, 0), 0.75, 1.0, 1.0, _material("fountain_stone", Color("cdd5ce")), 12)
	_cylinder(self, location + Vector3(0, 1.22, 0), 1.6, 1.0, 0.22, _material("fountain_stone", Color("cdd5ce")), 16)


func _make_large_parks() -> void:
	var path_material: Material = _material("park_path", Color("dfcfaa"))
	# Two continuous park areas, each with actual walkable paths on the HUD.
	_box(self, Vector3(-160, 0.025, -160), Vector3(146, 0.03, 5), path_material)
	_box(self, Vector3(-160, 0.026, -160), Vector3(5, 0.03, 146), path_material)
	_box(self, Vector3(-160, 0.027, -222), Vector3(146, 0.03, 4), path_material)
	_box(self, Vector3(-222, 0.028, -160), Vector3(4, 0.03, 146), path_material)
	_box(self, Vector3(160, 0.025, 180), Vector3(146, 0.03, 5), path_material)
	_box(self, Vector3(160, 0.026, 180), Vector3(5, 0.03, 106), path_material)
	_box(self, Vector3(160, 0.027, 130), Vector3(146, 0.03, 4), path_material)
	_small_fountain(Vector3(-160, 0, -160), 6.0)
	_small_fountain(Vector3(160, 0, 180), 5.0)
	for location in [Vector3(-160, 0, -160), Vector3(160, 0, 180)]:
		for corner in [Vector3(-12, 0, -8), Vector3(12, 0, -8), Vector3(-12, 0, 8), Vector3(12, 0, 8)]:
			_bench(location + corner, 0.0 if corner.z < 0 else PI)
			_bin(location + corner + Vector3(2, 0, 0), true)
	# Fixed planting rows are decorative; they never become synchronized NPCs.
	for row in range(5):
		for column in range(5):
			var location: Vector3 = Vector3(-224 + float(column) * 31, 0, -220 + float(row) * 30)
			if absf(location.x + 160) < 11 or absf(location.z + 160) < 11:
				continue
			if location.x > -115 and location.z < -210:
				continue
			_tree(location, 1.0 + float((column + row) % 3) * 0.12, (column + row) % 2)
	for row in range(3):
		for column in range(5):
			var location: Vector3 = Vector3(96 + float(column) * 31, 0, 146 + float(row) * 35)
			if absf(location.x - 160) < 12 or absf(location.z - 180) < 11 or (column == 0 and row == 0):
				continue
			_tree(location, 1.05 + float(column % 3) * 0.1, (column + row) % 2)
	_make_park_tree_clusters()
	_label(self, "ГОРОДСКОЙ ПАРК", Vector3(-160, 3, -87), 0.018, DARK, 54)
	_label(self, "ПАРК «ЛЕСНОЙ»", Vector3(160, 3, 127), 0.018, DARK, 54)
	# Small court beside the forest park pavilion.
	_box(self, Vector3(210, 0.04, 146), Vector3(24, 0.03, 15), _material("court", Color("afbfaa")))
	for side in [-1.0, 1.0]:
		_box(self, Vector3(210 + side * 10, 0.07, 146), Vector3(0.12, 0.025, 13), _material("court_lines", CREAM))
		_box(self, Vector3(210, 0.07, 146 + side * 6.5), Vector3(20, 0.025, 0.12), _material("court_lines", CREAM))
	_box(self, Vector3(210, 0.07, 146), Vector3(0.12, 0.025, 13), _material("court_lines", CREAM))


func _make_park_tree_clusters() -> void:
	# Fixed extra groves, clear of paths, plaza benches, entrances and the court.
	# Like the original trees, these are decorative static meshes without colliders.
	var north_grove: Array[Vector3] = [
		Vector3(-211, 0, -208),
		Vector3(-197, 0, -208),
		Vector3(-183, 0, -208),
		Vector3(-147, 0, -208),
		Vector3(-133, 0, -208),
		Vector3(-119, 0, -208),
		Vector3(-105, 0, -208),
		Vector3(-211, 0, -194),
		Vector3(-197, 0, -194),
		Vector3(-183, 0, -194),
		Vector3(-147, 0, -194),
		Vector3(-119, 0, -194),
		Vector3(-105, 0, -194),
		Vector3(-211, 0, -180),
		Vector3(-197, 0, -180),
		Vector3(-183, 0, -180),
		Vector3(-147, 0, -180),
		Vector3(-133, 0, -180),
		Vector3(-119, 0, -180),
		Vector3(-105, 0, -180),
		Vector3(-211, 0, -144),
		Vector3(-197, 0, -144),
		Vector3(-183, 0, -144),
		Vector3(-133, 0, -144),
		Vector3(-119, 0, -144),
		Vector3(-105, 0, -144),
		Vector3(-211, 0, -130),
		Vector3(-183, 0, -130),
		Vector3(-147, 0, -130),
		Vector3(-119, 0, -130),
		Vector3(-105, 0, -130),
		Vector3(-197, 0, -116),
		Vector3(-183, 0, -116),
		Vector3(-147, 0, -116),
		Vector3(-133, 0, -116),
		Vector3(-119, 0, -116),
		Vector3(-105, 0, -116),
		Vector3(-183, 0, -102),
		Vector3(-147, 0, -102),
		Vector3(-119, 0, -102),
		Vector3(-105, 0, -102)
	]
	var south_grove: Array[Vector3] = [
		Vector3(124, 0, 140),
		Vector3(138, 0, 140),
		Vector3(180, 0, 140),
		Vector3(96, 0, 154),
		Vector3(110, 0, 154),
		Vector3(124, 0, 154),
		Vector3(138, 0, 154),
		Vector3(180, 0, 154),
		Vector3(96, 0, 166),
		Vector3(110, 0, 166),
		Vector3(124, 0, 166),
		Vector3(138, 0, 166),
		Vector3(180, 0, 166),
		Vector3(194, 0, 166),
		Vector3(208, 0, 166),
		Vector3(222, 0, 166),
		Vector3(96, 0, 196),
		Vector3(110, 0, 196),
		Vector3(124, 0, 196),
		Vector3(138, 0, 196),
		Vector3(180, 0, 196),
		Vector3(194, 0, 196),
		Vector3(208, 0, 196),
		Vector3(222, 0, 196),
		Vector3(96, 0, 208),
		Vector3(110, 0, 208),
		Vector3(124, 0, 208),
		Vector3(138, 0, 208),
		Vector3(180, 0, 208),
		Vector3(194, 0, 208),
		Vector3(208, 0, 208),
		Vector3(222, 0, 208),
		Vector3(96, 0, 222),
		Vector3(110, 0, 222),
		Vector3(124, 0, 222),
		Vector3(138, 0, 222),
		Vector3(180, 0, 222),
		Vector3(194, 0, 222),
		Vector3(208, 0, 222),
		Vector3(222, 0, 222)
	]
	for index in range(north_grove.size()):
		_tree(north_grove[index], 0.90 + float(index % 4) * 0.09, index % 2)
	for index in range(south_grove.size()):
		_tree(south_grove[index], 0.92 + float(index % 4) * 0.08, (index + 1) % 2)


func _make_extended_street_details() -> void:
	for axis in CityLayout.ROAD_AXES:
		for along in [-220.0, -180.0, -140.0, -102.0, 102.0, 140.0, 180.0, 220.0]:
			var flat: Vector2 = Vector2(axis, along)
			if _is_road(flat):
				_lamp(Vector3(axis - 6.0, 0, along))
				if int(absf(axis)) % 80 == 0:
					_tree(Vector3(axis + 6.0, 0, along + 8), 0.6, 1)
	for sign_position in [Vector3(-84, 0, -6), Vector3(-6, 0, -84), Vector3(90, 0, -120), Vector3(-6, 0, 84), Vector3(-84, 0, -240), Vector3(84, 0, 120)]:
		_cylinder(self, sign_position + Vector3(0, 1.4, 0), 0.075, 0.075, 2.8, _material("metal", DARK), 12)
		_rounded_box(self, sign_position + Vector3(0, 2.3, 0), Vector3(2.5, 0.7, 0.13), _material("direction_sign", TEAL), 0.08)


func get_city_showcases() -> Array[Dictionary]:
	return [
		{"id": "business", "name": "Деловой центр", "focus": Vector3(-174, 16, -12), "camera": Vector3(-87, 88, 77)},
		{"id": "residential", "name": "Жилые кварталы", "focus": Vector3(-72, 4, 145), "camera": Vector3(-10, 63, 214)},
		{"id": "industrial", "name": "Логистический район", "focus": Vector3(164, 2, -172), "camera": Vector3(96, 65, -87)},
		{"id": "park", "name": "Городской парк", "focus": Vector3(-159, 2, -158), "camera": Vector3(-94, 68, -98)},
		{"id": "street", "name": "Деловой бульвар", "focus": Vector3(-160, 7, -54), "camera": Vector3(-160, 9, 6)},
		{"id": "forest", "name": "Парк «Лесной»", "focus": Vector3(160, 2, 179), "camera": Vector3(88, 64, 246)}
	]


func _make_city() -> void :

	var center: = _building("Delivery Center", Vector3(-23, 0, 23), Vector3(25, 8, 18), ORANGE, false, true)
	_roller_door(center, Vector3(-5.7, 2.05, -9.03), 8.0, 4.0)
	_door(center, Vector3(7, 0, -9.03), true)
	for window_x in [-8.6, -2.9, 2.9, 8.6]:
		_window(center, Vector3(window_x, 5.1, -9.02), 2.55, 1.35, 0.0, false, 0)
	_rounded_box(center, Vector3(0, 6.85, -9.18), Vector3(18, 1.05, 0.32), _material("center_sign", DARK), 0.12)
	_facade_label(center, "DELIVERY CENTER", Vector3(0, 6.85, -9.36), 0.014, CREAM, 54)
	for pillar_x in [-11.8, 11.8]:
		_rounded_box(center, Vector3(pillar_x, 3.2, -9.06), Vector3(0.42, 6.1, 0.3), _material("warehouse_trim", CREAM), 0.08)
	_box(self, Vector3(-23, 0.025, 10), Vector3(25, 0.03, 8), _material("forecourt", Color("ead4ac")))
	_parcel(Vector3(-32.5, 0, 11.0))
	_parcel(Vector3(-30.7, 0, 11.5))
	_parcel(Vector3(-32.5, 0.9, 11.0))
	_planter(Vector3(-12.0, 0, 12.1), 0.8, true)
	_bin(Vector3(-34, 0, 18), false)
	var garage: = _building("Garage", Vector3(-66, 0, 23), Vector3(22, 6.5, 18), TEAL, false, true)
	_roller_door(garage, Vector3(0, 2.05, -9.03), 14.0, 4.0)
	for window_x in [-8.9, 8.9]:
		_window(garage, Vector3(window_x, 2.8, -9.02), 1.1, 1.5, 0.0, false, 0)
	_rounded_box(garage, Vector3(0, 5.3, -9.2), Vector3(8, 0.95, 0.35), _material("garage_sign", DARK), 0.12)
	_facade_label(garage, "GARAGE", Vector3(0, 5.3, -9.39), 0.014, CREAM, 54)
	_bin(Vector3(-76.2, 0, 12.8), true)
	_label(self, "Гараж — E: купить и выбрать транспорт", Vector3(-66, 2.0, 8.5), 0.009, DARK, 40)

	_shop("Кофейня «Утро»", Vector3(-66, 0, -21), Vector3(21, 8, 17), Color("edb579"), "COFFEE", TEAL)
	_shop("Пекарня «Крошка»", Vector3(-22, 0, -22), Vector3(25, 9, 17), Color("df916c"), "BAKERY", Color("f7d071"))
	_shop("Городской маркет", Vector3(22, 0, -21), Vector3(25, 8, 18), Color("79b7ad"), "MARKET", ORANGE)
	_building("City Offices", Vector3(66, 0, -21), Vector3(23, 20, 20), Color("a3bbc9"), false)
	_shop("Цветочная лавка", Vector3(-72, 0, -66), Vector3(12, 7, 15), Color("e1b7aa"), "FLOWERS", TEAL)
	_shop("Аптека", Vector3(-54, 0, -66), Vector3(12, 8, 15), Color("adc7a0"), "PHARMACY", Color("edcb70"))
	_shop("Книжный дом", Vector3(-22, 0, -66), Vector3(24, 12, 17), Color("d2b28d"), "BOOKS", Color("d77958"))
	_building("Design Studio", Vector3(22, 0, -66), Vector3(24, 15, 17), Color("8fc0bf"), false)
	_label(self, "DOWNTOWN", Vector3(-22, 1.6, -48), 0.018, DARK, 52)

	_house("House 01", Vector3(12, 0, 23), Color("f0c484"))
	_house("House 02", Vector3(29, 0, 23), Color("b3c6a1"))
	_house("House 03", Vector3(55, 0, 23), Color("eab6a0"))
	_house("House 04", Vector3(74, 0, 23), Color("a5c5d0"))
	_house("House 05", Vector3(-66, 0, 65), Color("efbc83"))
	_house("House 06", Vector3(-28, 0, 65), Color("b2cbb5"))
	_house("House 07", Vector3(-12, 0, 65), Color("d9b4a0"))
	_house("House 08", Vector3(12, 0, 65), Color("efcd91"))
	_house("House 09", Vector3(29, 0, 65), Color("a9c7c1"))
	_house("House 10", Vector3(66, 0, 65), Color("e4b3a3"))
	_label(self, "RESIDENTIAL AREA", Vector3(22, 1.6, 48), 0.017, DARK, 50)


func _make_park() -> void :
	_map_fountains.append({"position": Vector3(64, 0, -65), "radius": 5.3})
	var sand: = _material("park_path", Color("dfcfaa"))
	_box(self, Vector3(65, 0.025, -65), Vector3(34, 0.03, 4), sand)
	_box(self, Vector3(64, 0.026, -65), Vector3(4, 0.03, 34), sand)
	_cylinder(self, Vector3(64, 0.04, -65), 5.3, 5.3, 0.05, _material("fountain_rim", CREAM), 16)
	_cylinder(self, Vector3(64, 0.09, -65), 4.5, 4.5, 0.06, _material("water", Color("69bdca")), 16)
	_cylinder(self, Vector3(64, 0.42, -65), 0.8, 1.05, 0.6, _material("fountain_stone", Color("cdd5ce")), 8)
	_cylinder(self, Vector3(64, 0.86, -65), 1.8, 1.0, 0.3, _material("fountain_stone", Color("cdd5ce")), 12)
	_cylinder(self, Vector3(64, 1.06, -65), 1.45, 1.45, 0.06, _material("water", Color("69bdca")), 12)
	for tree_position in [Vector3(51, 0, -77), Vector3(58, 0, -79), Vector3(73, 0, -77), Vector3(79, 0, -71), Vector3(52, 0, -54), Vector3(58, 0, -51), Vector3(75, 0, -53), Vector3(79, 0, -60)]:
		_tree(tree_position, 0.9, 0)
	_bench(Vector3(57, 0, -70), 0.0)
	_bench(Vector3(72, 0, -59), PI)
	_bench(Vector3(57, 0, -59), PI / 2.0)
	_label(self, "CITY PARK", Vector3(65, 2.5, -47), 0.023, DARK, 54)

	for flower_index in range(12):
		var flower_position: = Vector3(49.5 + float(flower_index % 3) * 0.55, 0.45, -57.0 + float(flower_index / 3) * 0.55)
		_cylinder(self, flower_position, 0.23, 0.15, 0.18, _material("flowers_" + str(flower_index % 2), Color("e7887e") if flower_index % 2 == 0 else Color("f8cf69")), 5)


func _make_street_details() -> void :

	for street_position in [-40.0, 0.0, 40.0]:
		for along_position in [-79.0, -54.0, -13.0, 16.0, 55.0, 79.0]:
			_tree(Vector3(street_position + 6.0, 0, along_position), 0.58, 1)
		for along_position in [-62.0, -21.0, 22.0, 65.0]:
			_lamp(Vector3(street_position - 6.0, 0, along_position))
	for sign_position in [Vector3(-6, 0, -8), Vector3(34, 0, 32), Vector3(-46, 0, 48)]:
		_cylinder(self, sign_position + Vector3(0, 1.3, 0), 0.065, 0.065, 2.6, _material("metal", DARK), 12)
		_rounded_box(self, sign_position + Vector3(0, 2.1, 0), Vector3(1.65, 0.65, 0.1), _material("direction_sign", TEAL), 0.045)

	var line_material: = _material("parking_lines", CREAM)
	for bay_index in range(5):
		_box(self, Vector3(-77 + float(bay_index) * 5, 0.065, 7.8), Vector3(0.13, 0.025, 4.5), line_material)
	_bench(Vector3(-8.5, 0, 59), PI / 2.0)
	_bench(Vector3(48, 0, 68), PI / 2.0)
	for bin_position in [Vector3(-7.8, 0, -18), Vector3(7.6, 0, 21), Vector3(48.0, 0, -56), Vector3(34, 0, 64)]:
		_bin(bin_position, true)

	for house_position in [Vector3(12, 0, 23), Vector3(29, 0, 23), Vector3(55, 0, 23), Vector3(74, 0, 23), Vector3(-66, 0, 65), Vector3(-28, 0, 65), Vector3(-12, 0, 65), Vector3(12, 0, 65), Vector3(29, 0, 65), Vector3(66, 0, 65)]:
		_box(self, house_position + Vector3(0, 0.05, -11), Vector3(2, 0.06, 8), _material("door_path", Color("d9caae")))
		_rounded_box(self, house_position + Vector3(4, 0.4, -10), Vector3(2, 0.8, 1), _material("hedge", Color("679966")), 0.32)


func _make_delivery_points() -> void :
	pickup_points = [
		{"id": "warehouse", "name": "Delivery Center", "position": Vector3(-23, 0, 10)}, 
		{"id": "coffee", "name": "Кофейня «Утро»", "position": Vector3(-66, 0, -32)}, 
		{"id": "bakery", "name": "Пекарня «Крошка»", "position": Vector3(-22, 0, -33)}, 
		{"id": "market", "name": "Городской маркет", "position": Vector3(22, 0, -33)}
	]
	delivery_points = [
		{"id": "house_01", "name": "Дом 1", "position": Vector3(12, 0, 10)}, 
		{"id": "house_02", "name": "Дом 2", "position": Vector3(29, 0, 10)}, 
		{"id": "house_03", "name": "Дом 3", "position": Vector3(55, 0, 10)}, 
		{"id": "house_04", "name": "Дом 4", "position": Vector3(74, 0, 10)}, 
		{"id": "house_05", "name": "Дом 5", "position": Vector3(-66, 0, 53)}, 
		{"id": "house_06", "name": "Дом 6", "position": Vector3(-28, 0, 53)}, 
		{"id": "house_07", "name": "Дом 7", "position": Vector3(-12, 0, 53)}, 
		{"id": "house_08", "name": "Дом 8", "position": Vector3(12, 0, 53)}, 
		{"id": "house_09", "name": "Дом 9", "position": Vector3(29, 0, 53)}, 
		{"id": "house_10", "name": "Дом 10", "position": Vector3(66, 0, 53)}, 
		{"id": "offices", "name": "Городские офисы", "position": Vector3(66, 0, -34)}, 
		{"id": "studio", "name": "Дизайн-студия", "position": Vector3(22, 0, -78)}
	]
	pickup_points.append_array(_extension_pickups)
	delivery_points.append_array(_extension_deliveries)
	for point in pickup_points:
		_add_point_district(point)
		_point_marker(point["position"], point["name"], true)
	for point in delivery_points:
		_add_point_district(point)
		_point_marker(point["position"], point["name"], false)


func _building(building_name: String, location: Vector3, dimensions: Vector3, color: Color, pitched_roof: bool = false, plain_front: bool = false) -> Node3D:
	var building: = Node3D.new()
	building.name = building_name.validate_node_name()
	building.position = location
	add_child(building)
	_map_buildings.append({"name": building_name, "rect": Rect2(Vector2(location.x - dimensions.x * 0.5, location.z - dimensions.z * 0.5), Vector2(dimensions.x, dimensions.z)), "color": color, "height": dimensions.y, "kind": "house" if pitched_roof else "core", "district": CityLayout.get_district_id(location)})
	_rounded_box(building, Vector3(0, dimensions.y / 2.0, 0), dimensions, _material("wall_" + color.to_html(), color), 0.42, true)
	var foundation: = _material("foundation", Color("d9cfb8"))
	_rounded_box(building, Vector3(0, 0.3, 0), Vector3(dimensions.x + 0.35, 0.6, dimensions.z + 0.35), foundation, 0.18)
	_rounded_box(building, Vector3(0, dimensions.y - 0.24, 0), Vector3(dimensions.x + 0.25, 0.38, dimensions.z + 0.25), _material("cornice", CREAM), 0.14)
	if not pitched_roof:
		_rounded_box(building, Vector3(0, dimensions.y + 0.15, 0), Vector3(dimensions.x + 0.6, 0.35, dimensions.z + 0.6), _material("flat_roof", Color("677c82")), 0.16)
		_roof_vent(building, Vector3( - dimensions.x * 0.25, dimensions.y + 0.65, 1))

	var floors: int = mini(8, maxi(1, int(dimensions.y / 3.2)))
	var columns: int = maxi(2, int(dimensions.x / 4.6))
	var side_columns: int = maxi(2, int(dimensions.z / 5.0))
	for floor_index in range(floors):
		var floor_step: float = (dimensions.y - 3.4) / float(maxi(floors - 1, 1)) if _extension_windows and not pitched_roof else (3.0 if pitched_roof else 3.25)
		var window_y: float = 2.2 + float(floor_index) * floor_step
		for window_index in range(columns):
			var window_x: float = - dimensions.x / 2.0 + (float(window_index) + 0.5) * dimensions.x / float(columns)
			var variation: int = (window_index + floor_index * 2) % 5
			if not plain_front and not (floor_index == 0 and absf(window_x) < 1.9):
				_window(building, Vector3(window_x, window_y, - dimensions.z / 2.0 - 0.02), 1.65, 1.7, 0.0, pitched_roof and floor_index == 0, variation)
			_window(building, Vector3( - window_x, window_y, dimensions.z / 2.0 + 0.02), 1.65, 1.7, PI, false, variation)
		for side_index in range(side_columns):
			var window_z: float = - dimensions.z / 2.0 + (float(side_index) + 0.5) * dimensions.z / float(side_columns)
			for side in [-1.0, 1.0]:
				_window(building, Vector3(side * (dimensions.x / 2.0 + 0.02), window_y, window_z), 1.65, 1.7, - side * PI / 2.0, false, (side_index + floor_index) % 5)
	if not plain_front:
		_door(building, Vector3(0, 0, - dimensions.z / 2.0 - 0.02), not pitched_roof)
		_rounded_box(building, Vector3(0, 0.17, - dimensions.z / 2.0 - 0.7), Vector3(3, 0.34, 1.6), foundation, 0.1)
	return building


func _house(house_name: String, location: Vector3, color: Color) -> void :
	var house: = _building(house_name, location, Vector3(11, 6.4, 15), color, true)
	var roof_material: = _material("tile_roof", Color("b67559"))

	var vertices: = PackedVector3Array([
		Vector3(-6, 6.4, -8), Vector3(6, 6.4, -8), Vector3(0, 9.5, -8), 
		Vector3(6, 6.4, 8), Vector3(-6, 6.4, 8), Vector3(0, 9.5, 8), 
		Vector3(-6, 6.4, 8), Vector3(-6, 6.4, -8), Vector3(0, 9.5, -8), 
		Vector3(-6, 6.4, 8), Vector3(0, 9.5, -8), Vector3(0, 9.5, 8), 
		Vector3(6, 6.4, -8), Vector3(6, 6.4, 8), Vector3(0, 9.5, 8), 
		Vector3(6, 6.4, -8), Vector3(0, 9.5, 8), Vector3(0, 9.5, -8)
	])
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var roof: = MeshInstance3D.new()
	roof.mesh = surface.commit()
	roof.material_override = roof_material
	house.add_child(roof)
	_rounded_box(house, Vector3(2.7, 8.2, 3), Vector3(1.2, 3, 1.2), _material("chimney", Color("986d5c")), 0.12)
	_rounded_box(house, Vector3(2.7, 9.75, 3), Vector3(1.5, 0.23, 1.5), _material("chimney_cap", CREAM), 0.1)
	for brick_index in range(4):
		_box(house, Vector3(2.7, 7.4 + float(brick_index) * 0.52, 2.38), Vector3(1.2, 0.035, 0.018), _material("chimney_grout", Color("bd947c")))

	for side in [-1.0, 1.0]:
		var trim: = _rounded_box(house, Vector3(side * 3.0, 7.95, -8.03), Vector3(6.75, 0.17, 0.2), _material("gable_trim", CREAM), 0.07)
		trim.rotation.z = - side * atan2(3.1, 6.0)
	_rounded_box(house, Vector3(0, 9.5, 0), Vector3(0.32, 0.25, 16.15), roof_material, 0.11)
	_rounded_box(house, Vector3(2.0, 1.75, -7.73), Vector3(0.82, 0.5, 0.12), _material("number_plate", DARK), 0.08)
	_facade_label(house, house_name.replace("House ", "№ "), Vector3(2.0, 1.75, -7.8), 0.007, CREAM, 36)
	var canopy: = _rounded_box(house, Vector3(0, 3.18, -8.03), Vector3(2.9, 0.18, 1.4), _material("door_canopy", Color("699c99")), 0.09)
	canopy.rotation.x = deg_to_rad(7)
	for post_x in [-1.22, 1.22]:
		_cylinder(house, Vector3(post_x, 1.5, -8.45), 0.06, 0.06, 3.0, _material("porch_posts", CREAM), 12)
	_mailbox(house, Vector3(-2.0, 0, -8.5))
	_planter(location + Vector3(4.2, 0, -8.9), 0.58, true)

	if int(house_name.right(2)) % 2 == 0:
		_balcony(house, Vector3(-2.75, 4.45, -7.76))


func _shop(shop_name: String, location: Vector3, dimensions: Vector3, color: Color, sign_text: String, awning_color: Color) -> void :
	var shop: = _building(shop_name, location, dimensions, color, false, true)
	var front_z: float = - dimensions.z / 2.0
	_rounded_box(shop, Vector3(0, 5.0, front_z - 0.3), Vector3(dimensions.x - 1.4, 1.05, 0.4), _material("shop_sign_" + awning_color.to_html(), awning_color), 0.14)
	_facade_label(shop, sign_text, Vector3(0, 5.0, front_z - 0.52), 0.012, CREAM, 54)
	var awning: = _rounded_box(shop, Vector3(0, 3.6, front_z - 1.0), Vector3(dimensions.x - 1.4, 0.22, 2.1), _material("awning_" + awning_color.to_html(), awning_color), 0.1)
	awning.rotation.x = deg_to_rad(8)
	for stripe_index in range(int((dimensions.x - 1.4) / 2.0)):
		var stripe: = _rounded_box(shop, Vector3( - dimensions.x / 2.0 + 1.9 + float(stripe_index) * 2.0, 3.61, front_z - 1.0), Vector3(0.85, 0.24, 2.1), _material("awning_white", CREAM), 0.08)
		stripe.rotation.x = deg_to_rad(8)
	_rounded_box(shop, Vector3(0, 3.32, front_z - 2.0), Vector3(dimensions.x - 1.4, 0.4, 0.16), _material("awning_" + awning_color.to_html(), awning_color), 0.07)
	_window(shop, Vector3( - dimensions.x * 0.26, 1.8, front_z - 0.02), minf(4.3, dimensions.x * 0.3), 2.4, 0.0, false, 0)
	_window(shop, Vector3(dimensions.x * 0.26, 1.8, front_z - 0.02), minf(4.3, dimensions.x * 0.3), 2.4, 0.0, false, 0)
	_door(shop, Vector3(0, 0, front_z - 0.02), true)
	if dimensions.y >= 8.0:
		for index in range(maxi(2, int(dimensions.x / 4.8))):
			var columns: int = maxi(2, int(dimensions.x / 4.8))
			_window(shop, Vector3( - dimensions.x / 2.0 + (float(index) + 0.5) * dimensions.x / float(columns), 6.65, front_z - 0.02), 1.6, 1.3, 0.0, false, index % 5)
	_planter(location + Vector3( - dimensions.x / 2.0 + 0.4, 0, front_z - 1.3), 0.55, sign_text != "FLOWERS")
	_planter(location + Vector3(dimensions.x / 2.0 - 0.4, 0, front_z - 1.3), 0.55, true)
	if sign_text == "COFFEE" or sign_text == "BAKERY":
		_cafe_table(location + Vector3( - dimensions.x * 0.38, 0, front_z - 3.4))
	if sign_text == "FLOWERS":
		_planter(location + Vector3(3.4, 0, front_z - 2.6), 0.66, false)


func _window(parent: Node3D, location: Vector3, width: float, height: float, yaw: float, shutters: bool, variation: int) -> void :
	if _extension_windows and not shutters:
		_extension_window(parent, location, width, height, yaw, variation)
		return
	var window: = Node3D.new()
	window.name = "FramedWindow"
	window.position = location
	window.rotation.y = yaw
	parent.add_child(window)
	var frame: = _material("window_frame", CREAM)
	_rounded_box(window, Vector3(0, 0, -0.09), Vector3(width + 0.3, height + 0.3, 0.2), frame, 0.09)
	var glass_color: = Color("72a6b5") if variation != 4 else Color("d4c49e")
	var glass: = _material("glass_" + str(variation == 4), glass_color)
	glass.roughness = 0.34
	_rounded_box(window, Vector3(0, 0, -0.205), Vector3(width, height, 0.055), glass, 0.025)
	_box(window, Vector3(0, 0, -0.25), Vector3(0.085, height, 0.055), frame)
	_box(window, Vector3(0, height * 0.02, -0.25), Vector3(width, 0.085, 0.055), frame)
	_rounded_box(window, Vector3(0, - height / 2.0 - 0.15, -0.16), Vector3(width + 0.5, 0.15, 0.49), frame, 0.055)
	var reflection: = _rounded_box(window, Vector3( - width * 0.24, height * 0.24, -0.244), Vector3(0.07, height * 0.31, 0.017), _material("glass_glint", Color("b6d7d8")), 0.008)
	reflection.rotation.z = deg_to_rad(-22)
	if width > 2.0:
		var other_reflection: = _rounded_box(window, Vector3(width * 0.3, height * 0.15, -0.244), Vector3(0.1, height * 0.38, 0.017), _material("glass_glint", Color("b6d7d8")), 0.008)
		other_reflection.rotation.z = deg_to_rad(-22)
	if shutters:
		var shutter_material: = _material("shutters", Color("598f88"))
		for side in [-1.0, 1.0]:
			var shutter_x: float = side * (width / 2.0 + 0.39)
			_rounded_box(window, Vector3(shutter_x, 0, -0.12), Vector3(0.44, height + 0.1, 0.17), shutter_material, 0.06)
			for slat in range(5):
				_box(window, Vector3(shutter_x, - height * 0.33 + float(slat) * height * 0.16, -0.22), Vector3(0.32, 0.055, 0.025), _material("shutter_slats", Color("91b5a4")))


func _door(parent: Node3D, location: Vector3, glazed: bool) -> void :
	var door: = Node3D.new()
	door.position = location
	parent.add_child(door)
	_rounded_box(door, Vector3(0, 1.48, -0.08), Vector3(2.1, 3.04, 0.22), _material("door_surround", CREAM), 0.09)
	_rounded_box(door, Vector3(0, 1.45, -0.215), Vector3(1.76, 2.85, 0.1), _material("door", DARK), 0.065)
	if glazed:
		_rounded_box(door, Vector3(0, 1.86, -0.285), Vector3(1.43, 1.63, 0.04), _material("glass_false", Color("72a6b5")), 0.03)
		_box(door, Vector3(0, 1.86, -0.315), Vector3(0.07, 1.63, 0.04), _material("door_surround", CREAM))
	else:
		_rounded_box(door, Vector3(0, 2.07, -0.285), Vector3(1.3, 0.89, 0.04), _material("door_panel", Color("50737a")), 0.04)
		_rounded_box(door, Vector3(0, 0.71, -0.285), Vector3(1.3, 0.94, 0.04), _material("door_panel", Color("50737a")), 0.04)
	_sphere(door, Vector3(0.59, 1.22, -0.36), Vector3(0.14, 0.14, 0.14), _material("door_brass", Color("d6b470")))


func _roller_door(parent: Node3D, location: Vector3, width: float, height: float) -> void :
	_rounded_box(parent, location + Vector3(0, 0, -0.07), Vector3(width + 0.45, height + 0.25, 0.25), _material("loading_door_surround", CREAM), 0.1)
	_rounded_box(parent, location + Vector3(0, 0, -0.225), Vector3(width, height, 0.1), _material("loading_door", Color("577784")), 0.055)
	for slat in range(8):
		_box(parent, location + Vector3(0, - height * 0.43 + float(slat) * height * 0.12, -0.295), Vector3(width - 0.16, 0.065, 0.03), _material("loading_door_slats", Color("9bb1b7")))
	for pane in range(4):
		_window(parent, location + Vector3( - width * 0.35 + float(pane) * width * 0.23, height * 0.26, -0.31), width * 0.16, 0.48, 0.0, false, 0)
	_rounded_box(parent, location + Vector3(0, - height * 0.33, -0.33), Vector3(0.88, 0.12, 0.13), _material("door_brass", Color("d6b470")), 0.045)


func _roof_vent(parent: Node3D, location: Vector3) -> void :
	_rounded_box(parent, location, Vector3(2, 1, 2), _material("roof_vents", Color("d0d9d5")), 0.16)
	_rounded_box(parent, location + Vector3(0, 0.54, 0), Vector3(2.17, 0.16, 2.17), _material("vent_cap", Color("819499")), 0.07)
	for slat in range(4):
		_box(parent, location + Vector3(0, -0.28 + float(slat) * 0.18, -1.016), Vector3(1.45, 0.07, 0.03), _material("vent_grille", DARK))


func _mailbox(parent: Node3D, location: Vector3) -> void :
	_cylinder(parent, location + Vector3(0, 0.55, 0), 0.045, 0.045, 1.1, _material("mailbox_post", DARK), 12)
	_rounded_box(parent, location + Vector3(0, 1.1, 0), Vector3(0.7, 0.46, 0.5), _material("mailbox", Color("dc9474")), 0.16)
	_box(parent, location + Vector3(0, 1.16, -0.256), Vector3(0.4, 0.035, 0.022), _material("mailbox_slot", DARK))
	_rounded_box(parent, location + Vector3(0.39, 1.34, 0.03), Vector3(0.11, 0.29, 0.035), _material("mail_flag", CREAM), 0.014)


func _balcony(parent: Node3D, location: Vector3) -> void :
	_rounded_box(parent, location + Vector3(0, 0, -0.38), Vector3(2.8, 0.18, 1.05), _material("balcony_floor", CREAM), 0.065)
	_rounded_box(parent, location + Vector3(0, 0.9, -0.86), Vector3(2.75, 0.11, 0.11), _material("balcony_rail", DARK), 0.05)
	for bar in range(7):
		_cylinder(parent, location + Vector3(-1.3 + float(bar) * 0.43, 0.48, -0.86), 0.025, 0.025, 0.84, _material("balcony_rail", DARK), 8)
	for side in [-1.0, 1.0]:
		_rounded_box(parent, location + Vector3(side * 1.31, 0.9, -0.37), Vector3(0.11, 0.11, 1.04), _material("balcony_rail", DARK), 0.05)


func _planter(location: Vector3, radius: float, leafy: bool) -> void :
	_cylinder(self, location + Vector3(0, 0.3, 0), radius, radius * 0.76, 0.6, _material("terracotta", Color("bf8364")), 16)
	_cylinder(self, location + Vector3(0, 0.59, 0), radius * 1.05, radius * 1.05, 0.13, _material("pot_rim", Color("d49b77")), 16)
	_cylinder(self, location + Vector3(0, 0.67, 0), radius * 0.86, radius * 0.86, 0.03, _material("soil", Color("665347")), 16)
	if leafy:
		_sphere(self, location + Vector3(0, 0.96, 0), Vector3(radius * 1.6, radius * 1.1, radius * 1.6), _material("topiary", Color("71a170")))
	else:
		for flower in range(5):
			var angle: float = TAU * float(flower) / 5.0
			var offset: = Vector3(cos(angle) * radius * 0.5, 0.86, sin(angle) * radius * 0.5)
			_cylinder(self, location + offset, 0.025, 0.025, 0.35, _material("flower_stems", Color("6b9262")), 8)
			_sphere(self, location + offset + Vector3(0, 0.19, 0), Vector3(0.28, 0.19, 0.28), _material("flower_heads", Color("e39c96")))


func _bin(location: Vector3, recycling: bool) -> void :
	_rounded_box(self, location + Vector3(0, 0.57, 0), Vector3(0.76, 1.14, 0.72), _material("bin_" + str(recycling), TEAL if recycling else DARK), 0.15)
	_rounded_box(self, location + Vector3(0, 1.18, 0), Vector3(0.88, 0.17, 0.84), _material("bin_lid", Color("416770")), 0.07)
	_box(self, location + Vector3(0, 0.86, -0.367), Vector3(0.43, 0.15, 0.035), _material("bin_slot", Color("213b43")))
	_rounded_box(self, location + Vector3(0, 0.42, -0.378), Vector3(0.25, 0.31, 0.027), _material("bin_label", CREAM), 0.035)


func _cafe_table(location: Vector3) -> void :
	_cylinder(self, location + Vector3(0, 0.79, 0), 0.62, 0.62, 0.12, _material("cafe_table", Color("c5a07a")), 20)
	_cylinder(self, location + Vector3(0, 0.38, 0), 0.055, 0.08, 0.76, _material("metal", DARK), 12)
	_cylinder(self, location + Vector3(0, 0.06, 0), 0.35, 0.35, 0.08, _material("metal", DARK), 16)
	for side in [-1.0, 1.0]:
		_cylinder(self, location + Vector3(side * 0.92, 0.47, 0), 0.3, 0.3, 0.1, _material("cafe_seat", TEAL), 16)
		_cylinder(self, location + Vector3(side * 0.92, 0.23, 0), 0.055, 0.1, 0.43, _material("metal", DARK), 12)
	_cylinder(self, location + Vector3(0.14, 0.93, 0), 0.075, 0.07, 0.17, _material("coffee_cup", CREAM), 12)


func _point_marker(location: Vector3, title: String, is_pickup: bool) -> void :
	var color: Color = ORANGE if is_pickup else TEAL
	var ring_mesh: = TorusMesh.new()
	ring_mesh.inner_radius = 0.66
	ring_mesh.outer_radius = 0.82
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 8
	var ring: = MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = _material("point_ring_" + str(is_pickup), color)
	ring.position = location + Vector3(0, 0.1, 0)
	add_child(ring)
	_cylinder(self, location + Vector3(1.1, 0.65, 0), 0.07, 0.07, 1.3, _material("metal", DARK), 12)
	_rounded_box(self, location + Vector3(1.1, 1.4, 0), Vector3(0.65, 0.5, 0.14), _material("point_sign_" + str(is_pickup), color), 0.06)
	var title_label: Label3D = _label(self, title, location + Vector3(0, 2.4, 0), 0.009, CREAM, 40)
	title_label.visibility_range_end = 80.0


func _tree(location: Vector3, scale_value: float, type_value: int) -> void :
	var trunk_material: = _material("tree_trunk", Color("8f7961"))
	_cylinder(self, location + Vector3(0, 1.4 * scale_value, 0), 0.26 * scale_value, 0.36 * scale_value, 2.8 * scale_value, trunk_material, 12)
	if type_value == 0:
		_sphere(self, location + Vector3(-0.65, 3.3, 0.0) * scale_value, Vector3(3.8, 3.8, 3.8) * scale_value, _material("leaves_light", Color("70ab65")))
		_sphere(self, location + Vector3(1.0, 3.5, 0.3) * scale_value, Vector3(3.5, 3.5, 3.5) * scale_value, _material("leaves_dark", Color("5a965c")))
		_sphere(self, location + Vector3(0.1, 4.8, -0.15) * scale_value, Vector3(3.6, 3.6, 3.6) * scale_value, _material("leaves_light", Color("70ab65")))
	else:
		_sphere(self, location + Vector3(0, 3.6 * scale_value, 0), Vector3(4.6, 4.5, 4.3) * scale_value, _material("leaves_round", Color("72a962")))
		_cylinder(self, location + Vector3(0, 0.09, 0), 0.68 * scale_value, 0.68 * scale_value, 0.14, _material("tree_pit", Color("d3bf9e")), 16)


func _lamp(location: Vector3) -> void :
	_cylinder(self, location + Vector3(0, 2.5, 0), 0.085, 0.11, 5.0, _material("metal", DARK), 12)
	_cylinder(self, location + Vector3(0, 0.3, 0), 0.2, 0.24, 0.6, _material("metal", DARK), 12)
	_rounded_box(self, location + Vector3(0.35, 4.8, 0), Vector3(0.8, 0.14, 0.2), _material("metal", DARK), 0.06)
	_rounded_box(self, location + Vector3(0.65, 4.7, 0), Vector3(0.65, 0.23, 0.5), _material("lamp_case", DARK), 0.08)
	_rounded_box(self, location + Vector3(0.65, 4.59, 0), Vector3(0.5, 0.07, 0.37), _material("lamp", CREAM), 0.03)


func _bench(location: Vector3, yaw: float) -> void :
	var bench: = Node3D.new()
	bench.position = location
	bench.rotation.y = yaw
	add_child(bench)
	var wood: = _material("bench_wood", Color("b88b5d"))
	for slat_index in range(3):
		_rounded_box(bench, Vector3(0, 0.58, -0.26 + float(slat_index) * 0.25), Vector3(2.4, 0.15, 0.2), wood, 0.055)
		_rounded_box(bench, Vector3(0, 0.82 + float(slat_index) * 0.22, 0.35), Vector3(2.4, 0.17, 0.13), wood, 0.045)
	for foot_x in [-0.8, 0.8]:
		_rounded_box(bench, Vector3(foot_x, 0.26, 0), Vector3(0.14, 0.52, 0.6), _material("metal", DARK), 0.06)
		_rounded_box(bench, Vector3(foot_x, 0.8, 0.03), Vector3(0.11, 0.14, 0.83), _material("metal", DARK), 0.045)


func _parcel(location: Vector3) -> void :
	_rounded_box(self, location + Vector3(0, 0.42, 0), Vector3(1.1, 0.84, 0.9), _material("parcel", Color("c49b68")), 0.07)
	_box(self, location + Vector3(0, 0.85, 0), Vector3(0.17, 0.02, 0.92), _material("parcel_tape", Color("ead1a2")))
	_box(self, location + Vector3(0.23, 0.5, -0.455), Vector3(0.3, 0.24, 0.015), _material("parcel_label", CREAM))


func _material(key: String, color: Color, unshaded: bool = false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material


func _box(parent: Node3D, location: Vector3, dimensions: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var mesh_key: String = "box_" + str(dimensions)
	if not _meshes.has(mesh_key):
		var new_mesh: = BoxMesh.new()
		new_mesh.size = dimensions
		_meshes[mesh_key] = new_mesh
	var instance: = MeshInstance3D.new()
	instance.mesh = _meshes[mesh_key] as Mesh
	instance.position = location
	instance.material_override = material
	parent.add_child(instance)
	var footprint: Rect2 = _map_footprint(instance.global_transform, dimensions)
	if material == _materials.get("road"):
		_map_roads.append(footprint)
	elif material == _materials.get("sidewalk") or material == _materials.get("park_path") or material == _materials.get("door_path") or material == _materials.get("forecourt"):
		_map_paths.append(footprint)
	if solid and dimensions.y > 1.0:
		_map_obstacles.append(footprint)
	if solid:
		var body: = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 2
		var collision: = CollisionShape3D.new()
		var shape: = BoxShape3D.new()
		shape.size = dimensions
		collision.shape = shape
		body.position = location
		body.add_child(collision)
		parent.add_child(body)
	return instance


func _rounded_box(parent: Node3D, location: Vector3, dimensions: Vector3, material: Material, radius: float = 0.1, solid: bool = false) -> MeshInstance3D:

	var instance: = _box(parent, location, dimensions, material, solid)
	instance.mesh = RoundedGeometry.box(dimensions, radius, 2)
	return instance


func _sphere(parent: Node3D, location: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	if not _meshes.has("sphere"):
		var sphere: = SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 16
		sphere.rings = 8
		_meshes["sphere"] = sphere
	var instance: = MeshInstance3D.new()
	instance.mesh = _meshes["sphere"] as Mesh
	instance.material_override = material
	instance.position = location
	instance.scale = dimensions
	parent.add_child(instance)
	return instance


func _batch_static_geometry() -> void :



	var buckets: Dictionary = {}
	var pending: Array[Node] = [self]
	var root_inverse: Transform3D = global_transform.affine_inverse()
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh_instance: = node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.material_override == null:
			continue
		var relative_transform: Transform3D = root_inverse * mesh_instance.global_transform
		var cell_x: int = floori(relative_transform.origin.x / 40.0)
		var cell_z: int = floori(relative_transform.origin.z / 40.0)
		var key: String = str(mesh_instance.mesh.get_instance_id()) + "_" + str(mesh_instance.material_override.get_instance_id()) + "_" + str(mesh_instance.cast_shadow) + "_" + str(cell_x) + "_" + str(cell_z)
		if not buckets.has(key):
			buckets[key] = {"mesh": mesh_instance.mesh, "material": mesh_instance.material_override, "shadow": mesh_instance.cast_shadow, "nodes": [], "transforms": []}
		var bucket: Dictionary = buckets[key]
		bucket["nodes"].append(mesh_instance)
		bucket["transforms"].append(relative_transform)
	for key in buckets:
		var bucket: Dictionary = buckets[key]
		if bucket["nodes"].size() < 4:
			continue
		var multimesh: = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = bucket["mesh"]
		multimesh.instance_count = bucket["transforms"].size()
		for index in range(multimesh.instance_count):
			multimesh.set_instance_transform(index, bucket["transforms"][index])
		var batch: = MultiMeshInstance3D.new()
		batch.name = "StaticDetailsBatch"
		batch.multimesh = multimesh
		batch.material_override = bucket["material"]
		batch.cast_shadow = bucket["shadow"]
		add_child(batch)
		for mesh_instance in bucket["nodes"]:
			mesh_instance.queue_free()


func _static_box(location: Vector3, dimensions: Vector3) -> void :
	_map_obstacles.append(_map_footprint(Transform3D(Basis.IDENTITY, location), dimensions))
	var body: = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = location
	var collision: = CollisionShape3D.new()
	var shape: = BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _cylinder(parent: Node3D, location: Vector3, top_radius: float, bottom_radius: float, height: float, material: Material, segments: int = 8) -> MeshInstance3D:
	var mesh_key: String = "cylinder_" + str(Vector3(top_radius, bottom_radius, height)) + "_" + str(segments)
	if not _meshes.has(mesh_key):
		var cylinder_mesh: = CylinderMesh.new()
		cylinder_mesh.top_radius = top_radius
		cylinder_mesh.bottom_radius = bottom_radius
		cylinder_mesh.height = height
		cylinder_mesh.radial_segments = segments
		_meshes[mesh_key] = cylinder_mesh
	var instance: = MeshInstance3D.new()
	instance.mesh = _meshes[mesh_key] as Mesh
	instance.material_override = material
	instance.position = location
	parent.add_child(instance)
	return instance


func _facade_label(parent: Node3D, title: String, location: Vector3, pixel_size_value: float, color: Color, size_value: int) -> Label3D:
	var label: = _label(parent, title, location, pixel_size_value, color, size_value)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation.y = PI
	label.outline_size = 3
	label.visibility_range_end = 120.0
	return label


func _label(parent: Node3D, title: String, location: Vector3, pixel_size_value: float, color: Color, size_value: int) -> Label3D:
	var label: = Label3D.new()
	label.text = title
	label.position = location
	label.pixel_size = pixel_size_value
	label.font_size = size_value
	label.modulate = color
	label.outline_modulate = DARK
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	parent.add_child(label)
	return label


func _map_footprint(transform_value: Transform3D, dimensions: Vector3) -> Rect2:
	var half: Vector3 = dimensions * 0.5
	var basis_value: Basis = transform_value.basis
	var extent: Vector2 = Vector2(
		absf(basis_value.x.x) * half.x + absf(basis_value.y.x) * half.y + absf(basis_value.z.x) * half.z,
		absf(basis_value.x.z) * half.x + absf(basis_value.y.z) * half.y + absf(basis_value.z.z) * half.z)
	var center: Vector2 = Vector2(transform_value.origin.x, transform_value.origin.z)
	return Rect2(center - extent, extent * 2.0)

func get_map_layout() -> Dictionary:
	return {
		"bounds": CityLayout.get_bounds(),
		"playable_bounds": CityLayout.PLAYABLE_BOUNDS,
		"districts": CityLayout.get_districts(),
		"parks": [CityLayout.ORIGINAL_PARK, CityLayout.NORTH_PARK, CityLayout.SOUTH_PARK],
		"fountains": _map_fountains.duplicate(true),
		"depot": Vector3(-23.0, 0.0, 23.0),
		"roads": _map_roads.duplicate(),
		"paths": _map_paths.duplicate(),
		"obstacles": _map_obstacles.duplicate(),
		"buildings": _map_buildings.duplicate(true),
		"pickups": pickup_points.duplicate(true),
		"deliveries": delivery_points.duplicate(true),
		"park": Rect2(48.0, -82.0, 34.0, 34.0),
		"garage": Vector3(-66.0, 0.0, 23.0),
	}
