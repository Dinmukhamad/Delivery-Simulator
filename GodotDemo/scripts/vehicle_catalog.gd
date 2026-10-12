extends RefCounted


const DATA_PATH: = "res://assets/vehicles.json"
const SUPPORTED_IDS: = ["bicycle", "scooter", "car"]
const DEFAULT_BICYCLE: = {
	"id": "bicycle", "name": "Bicycle", "price": 1500, "required_level": 2, 
	"max_speed": 13.0, "reverse_speed": 3.0, "acceleration": 8.0, 
	"braking": 12.0, "steer_rate": 2.2, 
	"collision_width": 0.8, "collision_height": 1.65, "collision_length": 2.2, 
	"camera_distance": 6.0, "camera_height": 1.7, 
}
const DEFAULT_SCOOTER: = {
	"id": "scooter", "name": "Scooter", "price": 5000, "required_level": 4, 
	"max_speed": 17.0, "reverse_speed": 3.0, "acceleration": 10.0, 
	"braking": 12.0, "steer_rate": 2.0, 
	"collision_width": 0.95, "collision_height": 1.75, "collision_length": 2.45, 
	"camera_distance": 6.5, "camera_height": 1.9, 
}
const DEFAULT_CAR: = {
	"id": "car", "name": "Car", "price": 15000, "required_level": 6, 
	"max_speed": 23.0, "reverse_speed": 5.0, "acceleration": 8.0, 
	"braking": 14.0, "steer_rate": 1.35, "handbrake": 28.0, 
	"collision_width": 2.0, "collision_height": 1.55, "collision_length": 4.0, 
	"camera_distance": 7.5, "camera_height": 1.7, 
}
const DEFAULTS: = {"bicycle": DEFAULT_BICYCLE, "scooter": DEFAULT_SCOOTER, "car": DEFAULT_CAR}
const NUMBER_BOUNDS: = {
	"price": [0.0, 1000000.0], "required_level": [1.0, 10.0], 
	"max_speed": [1.0, 40.0], "reverse_speed": [0.5, 10.0], 
	"acceleration": [0.5, 30.0], "braking": [1.0, 40.0], 
	"steer_rate": [0.25, 6.0], "handbrake": [1.0, 60.0], 
	"collision_width": [0.5, 4.0], "collision_height": [0.5, 3.0], 
	"collision_length": [1.0, 8.0], "camera_distance": [3.0, 12.0], 
	"camera_height": [0.8, 4.0], 
}


static func load_definitions() -> Dictionary:
	var source: Variant = null
	if FileAccess.file_exists(DATA_PATH):
		source = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return definitions_from_data(source)


static func definitions_from_data(source: Variant) -> Dictionary:

	var result: Dictionary = {}
	for vehicle_id in SUPPORTED_IDS:
		var definition: Dictionary = DEFAULTS[vehicle_id].duplicate(true)
		if source is Dictionary and source.get(vehicle_id) is Dictionary:
			var saved: Dictionary = source[vehicle_id]
			var display_name: Variant = saved.get("name", definition["name"])
			if display_name is String and not display_name.strip_edges().is_empty():
				definition["name"] = display_name.strip_edges().left(40)
			for key: String in NUMBER_BOUNDS:
				if not definition.has(key):
					continue
				var bounds: Array = NUMBER_BOUNDS[key]
				var number: = _number(saved, key, float(definition[key]), bounds[0], bounds[1])
				definition[key] = int(number) if key in ["price", "required_level"] else number
		definition["id"] = vehicle_id
		result[vehicle_id] = definition
	return result


static func sanitize_profile_vehicles(source: Dictionary) -> Dictionary:
	var owned: Array[String] = []
	var supplied: Variant = source.get("owned_vehicles", [])
	if supplied is Array:
		for value in supplied:
			if value is String and value in SUPPORTED_IDS and not owned.has(value):
				owned.append(value)
	var selected: String = ""
	var supplied_selection: Variant = source.get("selected_vehicle", "")
	if supplied_selection is String and owned.has(supplied_selection):
		selected = supplied_selection
	return {"owned_vehicles": owned, "selected_vehicle": selected}


static func _number(source: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var supplied: Variant = source.get(key, fallback)
	if not (supplied is float or supplied is int) or not is_finite(float(supplied)):
		return fallback
	return clampf(float(supplied), minimum, maximum)
