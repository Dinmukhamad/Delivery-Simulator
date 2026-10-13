extends RefCounted

# Host-owned balance; clients cannot supply these values in a request.
const DATA_PATH: String = "res://assets/team_shift.json"
const DEFAULTS: Dictionary = {
	"deliveries_per_player": 4,
	"bonus_money": 500,
	"bonus_xp": 100,
	"offer_seconds": 10.0,
	"handoff_distance": 3.2,
}
const NUMBER_BOUNDS: Dictionary = {
	"deliveries_per_player": [1.0, 25.0],
	"bonus_money": [0.0, 100000.0],
	"bonus_xp": [0.0, 10000.0],
	"offer_seconds": [2.0, 30.0],
	"handoff_distance": [1.0, 3.2],
}


static func normalize_mode(value: Variant) -> String:
	return "team" if value is String and value == "team" else "competitive"


static func load_config() -> Dictionary:
	var source: Variant = null
	if FileAccess.file_exists(DATA_PATH):
		source = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return config_from_data(source)


static func config_from_data(source: Variant) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate(true)
	if not source is Dictionary:
		return result
	for key: String in NUMBER_BOUNDS:
		var value: Variant = source.get(key, DEFAULTS[key])
		if not (value is int or value is float) or not is_finite(float(value)):
			continue
		var bounds: Array = NUMBER_BOUNDS[key]
		var bounded: float = clampf(float(value), float(bounds[0]), float(bounds[1]))
		result[key] = int(bounded) if key in ["deliveries_per_player", "bonus_money", "bonus_xp"] else bounded
	return result
