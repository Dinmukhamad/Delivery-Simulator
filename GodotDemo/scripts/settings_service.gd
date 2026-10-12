extends Node



signal changed(values: Dictionary)
signal preview_changed(pending: bool, seconds: float)

const SAVE_PATH: = "user://settings.json"
const PREVIEW_SECONDS: = 15.0
const RESOLUTIONS: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1280, 720), 
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var last_error: = ""
var load_notice: = ""
var test_mode: = false
var _world: Node3D
var _player: Node3D
var _values: Dictionary = default_values()
var _preview_values: Dictionary = {}
var _preview_deadline_msec: = 0
var _last_preview_second: = -1
var _test_storage_path: = ""
var _test_display_changes: = false


static func default_values() -> Dictionary:
	return {"resolution_width": 1280, "resolution_height": 720, "fullscreen": false, 
		"quality": "medium", "vsync": true, "master_volume": 1.0, 
		"music_volume": 0.35, "sfx_volume": 0.8, "mouse_sensitivity": 1.0}


func initialize(world: Node3D, player: Node3D, use_test_mode: bool) -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = world
	_player = player
	test_mode = use_test_mode
	_preview_values.clear()
	_preview_deadline_msec = 0
	_last_preview_second = -1
	last_error = ""
	load_notice = ""
	_ensure_audio_buses()
	_values = _load_values()
	_apply_runtime(_values)
	changed.emit(get_values())
	preview_changed.emit(false, 0.0)


func get_values() -> Dictionary:
	return _values.duplicate(true)


func supported_resolutions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var screen_size: = _screen_size()
	for resolution: Vector2i in RESOLUTIONS:
		if screen_size == Vector2i.ZERO or (resolution.x <= screen_size.x and resolution.y <= screen_size.y):
			result.append(resolution)
	if result.is_empty():

		result.append(Vector2i(maxi(320, screen_size.x), maxi(240, screen_size.y)))
	return result


func sanitize(source: Dictionary) -> Dictionary:
	var result: = default_values()
	var resolutions: = supported_resolutions()
	var preferred: = Vector2i(1280, 720)
	if not resolutions.has(preferred):
		preferred = resolutions[resolutions.size() - 1]
	var width: = _safe_integer(source.get("resolution_width"), preferred.x)
	var height: = _safe_integer(source.get("resolution_height"), preferred.y)
	var requested: = Vector2i(width, height)
	if not resolutions.has(requested):
		requested = preferred
	result["resolution_width"] = requested.x
	result["resolution_height"] = requested.y
	for key: String in ["fullscreen", "vsync"]:
		if source.get(key) is bool:
			result[key] = source[key]
	var quality: Variant = source.get("quality")
	if quality is String:
		var value: String = quality.strip_edges().to_lower()
		if value in ["low", "medium", "high"]:
			result["quality"] = value
	for key: String in ["master_volume", "music_volume", "sfx_volume"]:
		result[key] = _safe_number(source.get(key), float(result[key]), 0.0, 1.0)
	result["mouse_sensitivity"] = _safe_number(source.get("mouse_sensitivity"), 1.0, 0.2, 3.0)
	return result


func apply_candidate(candidate: Dictionary) -> bool:
	last_error = ""
	if has_pending_preview():
		cancel_preview()
	var merged: = get_values()
	merged.merge(candidate, true)
	var next: = sanitize(merged)
	_apply_runtime(next)
	if _display_changed(next, _values):
		_preview_values = next
		_preview_deadline_msec = Time.get_ticks_msec() + int(PREVIEW_SECONDS * 1000.0)
		_last_preview_second = int(PREVIEW_SECONDS)
		preview_changed.emit(true, PREVIEW_SECONDS)
		return true
	if not _save_values(next):
		_apply_runtime(_values)
		changed.emit(get_values())
		return false
	_values = next
	changed.emit(get_values())
	return false


func confirm_preview() -> bool:
	if not has_pending_preview():
		return false
	last_error = ""
	if preview_seconds_remaining() <= 0.0:
		cancel_preview()
		return false
	if not _save_values(_preview_values):
		cancel_preview()
		return false
	_values = _preview_values.duplicate(true)
	_clear_preview()
	changed.emit(get_values())
	preview_changed.emit(false, 0.0)
	return true


func cancel_preview() -> void :
	if not has_pending_preview():
		return
	_clear_preview()
	_apply_runtime(_values)
	changed.emit(get_values())
	preview_changed.emit(false, 0.0)


func has_pending_preview() -> bool:
	return not _preview_values.is_empty()


func preview_seconds_remaining() -> float:
	if not has_pending_preview():
		return 0.0
	return maxf(0.0, float(_preview_deadline_msec - Time.get_ticks_msec()) / 1000.0)


func _process(_delta: float) -> void :
	if not has_pending_preview():
		return
	var remaining: = preview_seconds_remaining()
	if remaining <= 0.0:
		cancel_preview()
		return
	var second: = int(ceil(remaining))
	if second != _last_preview_second:
		_last_preview_second = second
		preview_changed.emit(true, remaining)


func set_test_storage_path(path: String) -> bool:

	if not OS.get_cmdline_user_args().has("--test-mode"):
		return false
	var private_root: = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--settings-save-root="):
			private_root = argument.trim_prefix("--settings-save-root=").replace("\\", "/").simplify_path().trim_suffix("/")
	var absolute: = path.replace("\\", "/").simplify_path()
	if private_root.is_empty() or not private_root.is_absolute_path() or not DirAccess.dir_exists_absolute(private_root):
		return false
	if not (private_root.begins_with("/tmp/") or private_root.begins_with("/workspace/.godot-runtime/")):
		return false
	if not absolute.is_absolute_path() or not absolute.begins_with(private_root + "/") or absolute.get_file() != "settings.json":
		return false
	_test_storage_path = absolute
	return true


func enable_test_display_changes() -> bool:
	if not OS.get_cmdline_user_args().has("--test-mode") or not OS.get_cmdline_user_args().has("--settings-display-test"):
		return false
	_test_display_changes = true
	return true


func _clear_preview() -> void :
	_preview_values.clear()
	_preview_deadline_msec = 0
	_last_preview_second = -1


func _display_changed(candidate: Dictionary, previous: Dictionary) -> bool:
	return candidate["resolution_width"] != previous["resolution_width"]\
	or candidate["resolution_height"] != previous["resolution_height"]\
	or candidate["fullscreen"] != previous["fullscreen"]


func _apply_runtime(values: Dictionary) -> void :
	if is_inside_tree():
		var viewport: = get_viewport()
		match values["quality"]:
			"low": viewport.msaa_3d = Viewport.MSAA_DISABLED
			"high": viewport.msaa_3d = Viewport.MSAA_4X
			_: viewport.msaa_3d = Viewport.MSAA_2X
	if is_instance_valid(_world):
		for light: Node in _world.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = values["quality"] != "low"
	_ensure_audio_buses()
	_set_bus_volume("Master", float(values["master_volume"]))
	_set_bus_volume("Music", float(values["music_volume"]))
	_set_bus_volume("SFX", float(values["sfx_volume"]))
	if is_instance_valid(_player) and _player.has_method("set_sensitivity"):
		_player.call("set_sensitivity", float(values["mouse_sensitivity"]))
	if DisplayServer.get_name() == "headless" or (test_mode and not _test_display_changes):
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	var mode: = DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	var size: = Vector2i(int(values["resolution_width"]), int(values["resolution_height"]))

	DisplayServer.window_set_mode(mode)
	if not values["fullscreen"]:
		var screen: = _screen_size()
		var minimum: = Vector2i(960, 540)
		if screen != Vector2i.ZERO:
			minimum = Vector2i(mini(minimum.x, screen.x), mini(minimum.y, screen.y))
		DisplayServer.window_set_min_size(minimum)
		DisplayServer.window_set_size(size)
		var usable: = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		if usable.size.x > 0 and usable.size.y > 0:
			DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i.ZERO
	var screen: = DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_size(screen)


func _ensure_audio_buses() -> void :
	for bus: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Master")


func _set_bus_volume(bus: String, volume: float) -> void :
	var index: = AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volume)))
	AudioServer.set_bus_mute(index, volume <= 0.0)


func _storage_path() -> String:
	return _test_storage_path if test_mode else SAVE_PATH


func _load_values() -> Dictionary:
	var defaults: = sanitize(default_values())
	var path: = _storage_path()
	if path.is_empty():
		return defaults
	var backup: = path + ".backup"
	if not FileAccess.file_exists(path) and FileAccess.file_exists(backup):
		if DirAccess.rename_absolute(backup, path) == OK:
			load_notice = "Настройки восстановлены после прерванного сохранения."
		else:
			load_notice = "Не удалось восстановить настройки. Используются безопасные значения."
			return defaults
	if not FileAccess.file_exists(path):
		if not _save_values(defaults):
			load_notice = last_error
		return defaults
	var file: = FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_notice = "Не удалось прочитать настройки. Используются безопасные значения."
		return defaults
	var parser: = JSON.new()
	var error: = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		var corrupt: = path.get_base_dir().path_join("settings.corrupt-%d-%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
		if DirAccess.rename_absolute(path, corrupt) == OK:
			load_notice = "Повреждённые настройки сохранены отдельно. Созданы новые настройки."
			_save_values(defaults)
		else:
			load_notice = "Файл настроек повреждён. Используются безопасные значения; исходный файл сохранён."
		return defaults
	var result: = sanitize(parser.data)
	if not _matches_json_values(result, parser.data):
		load_notice = "Неверные значения настроек заменены безопасными."
		_save_values(result)
	return result


func _matches_json_values(values: Dictionary, saved: Dictionary) -> bool:

	if values.size() != saved.size():
		return false
	for key: String in values:
		if not saved.has(key):
			return false
		var expected: Variant = values[key]
		var actual: Variant = saved[key]
		if expected is int or expected is float:
			if not (actual is int or actual is float) or not is_finite(float(actual)) or float(actual) != float(expected):
				return false
		elif typeof(actual) != typeof(expected) or actual != expected:
			return false
	return true


func _save_values(values: Dictionary) -> bool:
	var path: = _storage_path()
	if path.is_empty():
		return true
	var temporary: = path + ".tmp"
	var file: = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось сохранить настройки. Проверьте доступ к папке сохранений."
		return false
	file.store_string(JSON.stringify(values, "\t"))
	file.flush()
	var successful: = file.get_error() == OK
	file.close()
	if not successful:
		last_error = "Не удалось полностью записать настройки. Предыдущие значения сохранены."
		return false

	var replacement: = DirAccess.rename_absolute(temporary, path)
	var backup: = path + ".backup"
	if replacement != OK:
		if FileAccess.file_exists(path):
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				last_error = "Не удалось обновить резервную копию настроек."
				return false
			if DirAccess.rename_absolute(path, backup) != OK:
				last_error = "Не удалось заменить файл настроек. Предыдущие значения сохранены."
				return false
		replacement = DirAccess.rename_absolute(temporary, path)
		if replacement != OK and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
	if replacement != OK:
		last_error = "Не удалось завершить сохранение настроек. Предыдущие значения сохранены."
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return true


func _safe_number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)


func _safe_integer(value: Variant, fallback: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return int(clampf(float(value), 1.0, 16384.0))
