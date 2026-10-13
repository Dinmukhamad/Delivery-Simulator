extends CanvasLayer


signal play_requested
signal quit_requested
signal resume_requested
signal restart_requested
signal order_requested(order_id: int)
signal abandon_requested
signal modal_closed
signal multiplayer_requested
signal host_requested(player_name: String, room_name: String, max_players: int, shift_seconds: int, shift_mode: String)
signal join_requested(player_name: String, address: String)
signal ready_requested(ready: bool)
signal start_requested
signal leave_requested
signal customization_requested
signal customization_closed
signal cosmetic_select_requested(category: String, id: String)
signal cosmetic_buy_requested(category: String, id: String)
signal vehicle_buy_requested(vehicle_type: String)
signal vehicle_spawn_requested(vehicle_type: String)
signal garage_closed
signal settings_requested
signal settings_apply_requested(values: Dictionary)
signal settings_closed
signal settings_confirm_requested
signal settings_revert_requested
signal ui_click_requested
signal handoff_offer_requested(target_id: int)
signal handoff_accept_requested(sender_id: int, offer_id: int)
signal handoff_decline_requested(sender_id: int, offer_id: int)
signal handoff_cancel_requested

const CosmeticCatalog = preload("res://scripts/cosmetic_catalog.gd")
const CosmeticPreviewScript = preload("res://scripts/cosmetic_preview.gd")
const COSMETIC_CATEGORIES: Array[String] = ["outfit", "backpack", "vehicle_paint"]
const COSMETIC_NAMES: Dictionary = {"outfit": "Одежда", "backpack": "Рюкзаки", "vehicle_paint": "Цвет транспорта"}

const INK: Color = Color("243b3a")
const MUTED: Color = Color("73817c")
const CREAM: Color = Color("fffaf0")
const PAPER: Color = Color("eee8d9")
const TEAL: Color = Color("247b72")
const GOLD: Color = Color("e8b653")
const EVENT_ORANGE: Color = Color("ad571f")
const EVENT_PAPER: Color = Color("fff0d9")
const VEHICLE_TYPES: Array[String] = ["bicycle", "scooter", "car"]
const VEHICLE_NAMES: Dictionary = {"walking": "Пешком", "bicycle": "Велосипед", "scooter": "Скутер", "car": "Автомобиль"}
const VEHICLE_DESCRIPTIONS: Dictionary = {
	"bicycle": "Лёгкий и манёвренный. Для коротких маршрутов и парковых дорожек.", 
	"scooter": "Быстро через весь район. Компактный транспорт для срочных заказов.", 
	"car": "Больше скорости на городских дорогах. Space — ручной тормоз.", 
}

var _root: Control
var _menu: Control
var _game: Control
var _pause: Control
var _results: Control
var _orders: Control
var _map: Control
var _menu_profile: Label
var _pause_profile: Label
var _order_title: Label
var _order_status: Label
var _active_order_panel: PanelContainer
var _order_quality: VBoxContainer
var _quality_text: Label
var _quality_bar: ProgressBar
var _quality_fill: StyleBoxFlat
var _quality_bonus: Label
var _navigation_hint: Label
var _map_route_label: Label
var _target: Label
var _money: Label
var _xp_level: Label
var _rank: Label
var _timer: Label
var _interaction: Label
var _interaction_panel: PanelContainer
var _deliveries: Label
var _vehicle: Label
var _keys: Label
var _orders_list: VBoxContainer
var _orders_empty: Label
var _orders_hint: Label
var _abandon_button: Button
var _accept_buttons: Array[Button] = []
var _has_active_order: bool = false
var _results_title: Label
var _results_summary: Label
var _results_numbers: Label
var _mini_map: MapView
var _full_map: MapView
var _toast: Label
var _toast_panel: PanelContainer
var _toast_timer: Timer
var _pending_notices: Array[String] = []
var _profile: Dictionary = {}
var _last_data: Dictionary = {}
var _lan_menu: Control
var _lobby: Control
var _lan_name: LineEdit
var _lan_room: LineEdit
var _lan_address: LineEdit
var _lan_max_players: OptionButton
var _lan_shift: OptionButton
var _lan_mode: OptionButton
var _lan_status: Label
var _lan_host_button: Button
var _lan_join_button: Button
var _lan_back_button: Button
var _lobby_title: Label
var _lobby_address: Label
var _lobby_details: Label
var _lobby_players: VBoxContainer
var _lobby_ready: CheckBox
var _lobby_start: Button
var _lobby_wait: Label
var _pause_restart: Button
var _pause_leave: Button
var _pause_hint: Label
var _results_restart: Button
var _results_leave: Button
var _results_wait: Label
var _leaderboard_panel: PanelContainer
var _leaderboard_rows: VBoxContainer
var _network_enabled: bool = false
var _network_is_host: bool = false
var _scroll_overlays: Array[Dictionary] = []
var _garage: Control
var _garage_profile: Label
var _garage_name: Label
var _garage_description: Label
var _garage_specs: Label
var _garage_status: Label
var _garage_hint: Label
var _garage_buy: Button
var _garage_spawn: Button
var _garage_last_profile: Dictionary = {}
var _garage_last_definitions: Dictionary = {}
var _garage_cards: Dictionary = {}
var _garage_grid: GridContainer
var _settings: Control
var _settings_controls: Dictionary = {}
var _settings_labels: Dictionary = {}
var _settings_pages: Array[Control] = []
var _settings_tabs: Array[Button] = []
var _settings_apply: Button
var _settings_reset: Button
var _settings_close: Button
var _settings_confirm: Button
var _settings_revert: Button
var _settings_preview: PanelContainer
var _settings_countdown: Label
var _settings_notice: Label
var _settings_pending: bool = false
var _settings_defaults: Dictionary = {}
var _settings_resolution_values: Array[Vector2i] = []
var _menu_settings: Button
var _pause_settings: Button
var _team_panel: PanelContainer
var _team_progress: Label
var _team_status: Label
var _team_message: Label
var _handoff_panel: PanelContainer
var _handoff_rows: VBoxContainer
var _handoff_progress: Label
var _handoff_personal: Label
var _handoff_signature: String = ""
var _handoff_timers: Array[Dictionary] = []
var _results_team: PanelContainer
var _results_team_text: Label
var _event_panel: PanelContainer
var _event_title: Label
var _event_detail: Label
var _event_bonus: Label
var _orders_event_panel: PanelContainer
var _orders_event_text: Label
var _order_event_hint: Label
var _map_event_label: Label
var _event_order_badges: Array[Dictionary] = []


var _customization: Control
var _customization_panel: PanelContainer
var _customization_body: HBoxContainer
var _customization_summary: Label
var _customization_notice: Label
var _customization_category: String = "outfit"
var _customization_profile: Dictionary = {}
var _customization_definitions: Dictionary = {}
var _customization_candidate: Dictionary = {}
var _cosmetic_cards: Dictionary = {}
var _cosmetic_tabs: Dictionary = {}
var _cosmetic_items: GridContainer
var _cosmetic_preview: SubViewportContainer
var _cosmetic_preview_title: Label
var _cosmetic_preview_hint: Label
var _cosmetic_rotation: HBoxContainer
var _cosmetic_vehicle_controls: HBoxContainer
var _cosmetic_vehicle_preview: VehicleIllustration
var _cosmetic_preview_vehicle: String = "bicycle"
var _customization_close: Button


class CosmeticSwatch extends Control:
	var colors: Array[Color] = []

	func _draw() -> void:
		for index: int in colors.size():
			var center: Vector2 = Vector2(14.0 + index * 25.0, size.y * 0.5)
			draw_circle(center, 11.0, colors[index])
			draw_arc(center, 11.0, 0.0, TAU, 24, Color(0.1, 0.2, 0.17, 0.16), 1.0, true)


class VehicleIllustration extends Control:
	var vehicle_type: String = "bicycle"
	var paint_color: Color = Color.TRANSPARENT

	func _paint(default_color: Color) -> Color:
		return paint_color if paint_color.a > 0.0 else default_color

	func _draw() -> void :
		var scale_factor: float = minf(size.x / 210.0, size.y / 150.0)
		var offset: Vector2 = (size - Vector2(210.0, 150.0) * scale_factor) * 0.5
		draw_set_transform(offset, 0.0, Vector2.ONE * scale_factor)
		draw_ellipse_shadow(Vector2(106.0, 133.0))
		match vehicle_type:
			"scooter": _draw_scooter()
			"car": _draw_car()
			_: _draw_bicycle()
		draw_set_transform(Vector2.ZERO)

	func _draw_bicycle() -> void :
		var left: Vector2 = Vector2(45.0, 100.0)
		var right: Vector2 = Vector2(166.0, 100.0)
		var pedal: Vector2 = Vector2(96.0, 103.0)
		var saddle: Vector2 = Vector2(81.0, 65.0)
		var steering: Vector2 = Vector2(141.0, 62.0)
		for wheel: Vector2 in [left, right]:
			draw_circle(wheel, 29.0, Color("243b3a"))
			draw_circle(wheel, 23.0, Color("fffaf0"))
			draw_circle(wheel, 20.0, Color("e5e8d7"), false, 2.0, true)
			for spoke: int in 6:
				var direction: Vector2 = Vector2.RIGHT.rotated(float(spoke) * TAU / 6.0)
				draw_line(wheel, wheel + direction * 21.0, Color("c5cdc1"), 1.5, true)
			draw_circle(wheel, 3.0, Color("243b3a"))
		var frame: Color = _paint(Color("247b72"))
		for pair: Array in [[left, saddle], [saddle, pedal], [pedal, left], [saddle, steering], [steering, pedal], [steering, right]]:
			draw_line(pair[0], pair[1], frame, 5.0, true)
			draw_circle(pair[0], 2.5, frame)
			draw_circle(pair[1], 2.5, frame)
		draw_line(saddle, Vector2(77.0, 52.0), Color("243b3a"), 4.0, true)
		draw_line(Vector2(66.0, 52.0), Vector2(89.0, 52.0), Color("243b3a"), 7.0, true)
		draw_line(steering, Vector2(135.0, 45.0), Color("243b3a"), 4.0, true)
		draw_line(Vector2(135.0, 45.0), Vector2(155.0, 45.0), Color("243b3a"), 5.0, true)
		draw_circle(pedal, 9.0, Color("e8b653"))
		draw_circle(pedal, 4.0, Color("243b3a"))
		draw_line(pedal, pedal + Vector2(11.0, 8.0), Color("243b3a"), 3.0, true)
		draw_line(pedal + Vector2(7.0, 8.0), pedal + Vector2(16.0, 8.0), Color("243b3a"), 3.0, true)

	func _rounded_rect(rect: Rect2, color: Color, radius: int) -> void :
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(radius)
		draw_style_box(style, rect)

	func _wheel(center: Vector2, radius: float) -> void :
		draw_circle(center, radius, Color("243b3a"))
		draw_circle(center, radius * 0.64, Color("d5ded6"))
		draw_circle(center, radius * 0.28, Color("73817c"))

	func _draw_scooter() -> void :
		var body: Color = _paint(Color("d97559"))
		_wheel(Vector2(48, 112), 22.0)
		_wheel(Vector2(164, 112), 22.0)
		_rounded_rect(Rect2(31, 79, 80, 35), body, 15)
		_rounded_rect(Rect2(37, 82, 67, 17), body.lightened(0.2), 8)
		_rounded_rect(Rect2(38, 71, 64, 11), Color("243b3a"), 5)
		draw_polyline(PackedVector2Array([Vector2(99, 105), Vector2(132, 105), Vector2(139, 85), Vector2(135, 60)]), body, 13.0, true)
		draw_line(Vector2(145, 81), Vector2(165, 108), Color("243b3a"), 5.0, true)
		_rounded_rect(Rect2(130, 54, 20, 39), body.lightened(0.12), 8)
		draw_line(Vector2(140, 59), Vector2(137, 45), Color("243b3a"), 4.0, true)
		draw_line(Vector2(127, 44), Vector2(153, 44), Color("243b3a"), 5.0, true)
		draw_circle(Vector2(151, 59), 8.0, Color("fffaf0"))
		_rounded_rect(Rect2(29, 48, 31, 25), Color("e8b653"), 5)
		draw_line(Vector2(44, 49), Vector2(44, 72), Color("fff1c9"), 4.0, true)

	func _draw_car() -> void :
		var body: Color = _paint(Color("658ed1"))
		_rounded_rect(Rect2(52, 56, 110, 48), body, 17)
		_rounded_rect(Rect2(59, 62, 42, 31), Color("c6e1e0"), 8)
		_rounded_rect(Rect2(108, 62, 43, 31), Color("c6e1e0"), 8)
		draw_line(Vector2(65, 69), Vector2(88, 69), Color("fffaf0"), 3.0, true)
		draw_line(Vector2(114, 69), Vector2(138, 69), Color("fffaf0"), 3.0, true)
		_rounded_rect(Rect2(21, 85, 172, 37), body, 14)
		_rounded_rect(Rect2(27, 94, 157, 8), body.lightened(0.2), 4)
		_rounded_rect(Rect2(28, 101, 10, 9), Color("e88062"), 3)
		_rounded_rect(Rect2(177, 97, 10, 11), Color("fff1c9"), 3)
		draw_line(Vector2(104, 90), Vector2(104, 113), body.darkened(0.25), 2.0, true)
		_rounded_rect(Rect2(112, 96, 14, 3), Color("243b3a"), 1)
		_rounded_rect(Rect2(17, 114, 13, 5), Color("d5ded6"), 2)
		_rounded_rect(Rect2(183, 114, 13, 5), Color("d5ded6"), 2)
		_wheel(Vector2(56, 119), 18.0)
		_wheel(Vector2(161, 119), 18.0)

	func draw_ellipse_shadow(center: Vector2) -> void :
		var points: PackedVector2Array = PackedVector2Array()
		for index: int in 24:
			var angle: float = float(index) * TAU / 24.0
			points.append(center + Vector2(cos(angle) * 76.0, sin(angle) * 10.0))
		draw_colored_polygon(points, Color(0.14, 0.23, 0.23, 0.09))


class MapView extends Control:
	var player_position: Vector3 = Vector3.ZERO
	var target_position: Vector3 = Vector3.ZERO
	var has_target: bool = false
	var large: bool = false
	var other_players: Array = []
	var layout: Dictionary = {}
	var route_points: Array[Vector3] = []
	var player_yaw: float = 0.0
	var walk_last: bool = false
	var target_picked: bool = false
	var district_event: Dictionary = {}
	const MINI_SPAN: float = 128.0
	const PLAYER_COLORS: Array[Color] = [Color("e88062"), Color("658ed1"), Color("ae78b3"), Color("82a962")]

	func _init() -> void:
		clip_contents = true

	func set_layout(value: Dictionary) -> void:
		layout = value.duplicate(true)
		queue_redraw()

	func update_positions(player: Vector3, target: Vector3, target_visible: bool = true) -> void:
		player_position = player
		target_position = target
		has_target = target_visible
		queue_redraw()

	func update_navigation(value: Dictionary, yaw: float, picked: bool) -> void:
		route_points.clear()
		if has_target:
			route_points.assign(value.get("points", []))
		player_yaw = yaw
		walk_last = bool(value.get("walk_last", false))
		target_picked = picked
		queue_redraw()

	func update_other_players(players: Array) -> void:
		other_players = players.duplicate(true)
		queue_redraw()

	func update_district_event(value: Dictionary) -> void:
		district_event = value.duplicate(true)
		queue_redraw()

	func _draw_event_district() -> void:
		if String(district_event.get("phase", "")) != "active":
			return
		var active_id: String = String(district_event.get("district_id", ""))
		for entry: Dictionary in layout.get("districts", []):
			if String(entry.get("id", "")) != active_id:
				continue
			var box: Rect2 = _rect(entry.get("rect", Rect2()))
			if not box.has_area():
				continue
			# Highlight the district under route, markers and labels, never cover navigation.
			draw_rect(box, Color(1.0, 0.59, 0.19, 0.10))
			draw_rect(box.grow(-1.0), Color("c16d2a"), false, 3.0 if large else 1.5)
			if not large:
				draw_circle(box.position + Vector2(6.0, 6.0), 4.0, Color("c16d2a"))

	func _world_bounds() -> Rect2:
		return layout.get("bounds", Rect2(-258.0, -258.0, 516.0, 516.0))

	func _view_bounds() -> Rect2:
		var bounds: Rect2 = _world_bounds()
		if large:
			return bounds
		var span: Vector2 = Vector2(minf(MINI_SPAN, bounds.size.x), minf(MINI_SPAN, bounds.size.y))
		var origin: Vector2 = Vector2(player_position.x, player_position.z) - span * 0.5
		origin = origin.clamp(bounds.position, bounds.end - span)
		return Rect2(origin, span)

	func _map_rect() -> Rect2:
		var padding: float = 20.0 if large else 9.0
		var side: float = maxf(1.0, minf(size.x, size.y) - padding * 2.0)
		return Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)

	func _point(position: Vector3) -> Vector2:
		var bounds: Rect2 = _view_bounds()
		var uv: Vector2 = (Vector2(position.x, position.z) - bounds.position) / bounds.size
		var area: Rect2 = _map_rect()
		# Keep the projection unbounded: clamping every route vertex would create false edge routes.
		return area.position + area.size * uv

	func _rect(rect: Rect2) -> Rect2:
		var visible: Rect2 = rect.intersection(_view_bounds())
		if not visible.has_area():
			return Rect2()
		var a: Vector2 = _point(Vector3(visible.position.x, 0.0, visible.position.y))
		var b: Vector2 = _point(Vector3(visible.end.x, 0.0, visible.end.y))
		return Rect2(a, b - a)

	func _visible(position: Vector3) -> bool:
		return _view_bounds().has_point(Vector2(position.x, position.z))

	func _paint_rect(rect: Rect2, color: Color) -> void:
		var box: Rect2 = _rect(rect)
		if box.has_area():
			draw_rect(box, color)

	func _caption(point: Vector2, value: String, color: Color) -> void:
		var location: Vector2 = Vector2(clampf(point.x + 9.0, 8.0, maxf(8.0, size.x - 128.0)), clampf(point.y - 6.0, 18.0, size.y - 6.0))
		draw_string(ThemeDB.fallback_font, location, value, HORIZONTAL_ALIGNMENT_LEFT, 126.0, 12, color)

	func _arrow(a: Vector2, b: Vector2, color: Color) -> void:
		var direction: Vector2 = (b - a).normalized()
		var tip: Vector2 = a.lerp(b, 0.6)
		var length: float = 6.0 if large else 4.0
		draw_line(tip, tip - direction.rotated(0.55) * length, color, 2.0, true)
		draw_line(tip, tip - direction.rotated(-0.55) * length, color, 2.0, true)

	func _clip_segment(a: Vector2, b: Vector2) -> PackedVector2Array:
		# Liang-Barsky clipping preserves the actual road segment at the local map boundary.
		var area: Rect2 = _map_rect()
		var delta: Vector2 = b - a
		var first: float = 0.0
		var last: float = 1.0
		for pair: Vector2 in [Vector2(-delta.x, a.x - area.position.x), Vector2(delta.x, area.end.x - a.x), Vector2(-delta.y, a.y - area.position.y), Vector2(delta.y, area.end.y - a.y)]:
			if absf(pair.x) < 0.00001:
				if pair.y < 0.0:
					return PackedVector2Array()
				continue
			var fraction: float = pair.y / pair.x
			if pair.x < 0.0:
				first = maxf(first, fraction)
			else:
				last = minf(last, fraction)
			if first > last:
				return PackedVector2Array()
		return PackedVector2Array([a + delta * first, a + delta * last])

	func _draw_district_labels() -> void:
		var font: Font = ThemeDB.fallback_font
		for entry: Dictionary in layout.get("districts", []):
			var box: Rect2 = _rect(entry.get("rect", Rect2()))
			if not box.has_area():
				continue
			var name_value: String = String(entry.get("name", ""))
			var width: float = maxf(1.0, box.size.x - 8.0)
			var font_size: int = 11
			var lines: Array[String] = [name_value]
			if font.get_string_size(name_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > width:
				var split: int = name_value.rfind(" ")
				if split > 0:
					lines = [name_value.substr(0, split), name_value.substr(split + 1)]
			var center: Vector2 = box.get_center()
			var label_height: float = lines.size() * 13.0 + 6.0
			draw_rect(Rect2(center - Vector2(width * 0.5, label_height * 0.5), Vector2(width, label_height)), Color(1.0, 0.98, 0.94, 0.82))
			for index: int in lines.size():
				var text_width: float = minf(width, font.get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
				var baseline: Vector2 = center + Vector2(-text_width * 0.5, -label_height * 0.5 + 14.0 + index * 13.0)
				draw_string(font, baseline, lines[index], HORIZONTAL_ALIGNMENT_LEFT, width, font_size, Color("435b57"))

	func current_district() -> String:
		var position: Vector2 = Vector2(player_position.x, player_position.z)
		for entry: Dictionary in layout.get("districts", []):
			var rect: Rect2 = entry.get("rect", Rect2())
			if rect.has_point(position):
				return String(entry.get("name", "Город"))
		return "Город"

	func _draw_target() -> void:
		var target_color: Color = Color("247b72") if target_picked else Color("e8b653")
		if _visible(target_position):
			var target: Vector2 = _point(target_position)
			draw_circle(target, 10.0 if large else 6.0, Color("fffaf0"))
			draw_circle(target, 7.0 if large else 4.0, target_color)
			if large:
				_caption(target, "Доставка" if target_picked else "Получение", Color("243b3a"))
		elif not large:
			# This is only a direction marker; the route itself always follows confirmed navigation points.
			var area: Rect2 = _map_rect().grow(-8.0)
			var player_point: Vector2 = _point(player_position)
			var origin: Vector2 = player_point.clamp(area.position, area.end)
			var direction: Vector2 = (_point(target_position) - player_point).normalized()
			var distance_x: float = INF
			var distance_y: float = INF
			if direction.x > 0.0001:
				distance_x = (area.end.x - origin.x) / direction.x
			elif direction.x < -0.0001:
				distance_x = (area.position.x - origin.x) / direction.x
			if direction.y > 0.0001:
				distance_y = (area.end.y - origin.y) / direction.y
			elif direction.y < -0.0001:
				distance_y = (area.position.y - origin.y) / direction.y
			var reach: float = maxf(0.0, minf(distance_x, distance_y))
			var edge: Vector2 = origin + direction * reach
			draw_circle(edge, 7.0, Color("fffaf0"))
			draw_colored_polygon(PackedVector2Array([edge + direction * 6.0, edge + direction.rotated(2.45) * 5.0, edge + direction.rotated(-2.45) * 5.0]), target_color)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("eae9dc"))
		draw_rect(_map_rect(), Color("b9d1a2"))
		for district: Dictionary in layout.get("districts", []):
			var district_color: Color = district.get("color", Color("cbd5bb"))
			_paint_rect(district.get("rect", Rect2()), district_color.lerp(Color("dfe5d1"), 0.55))
		var parks: Array = layout.get("parks", [])
		if parks.is_empty() and layout.has("park"):
			parks = [layout["park"]]
		for park: Rect2 in parks:
			_paint_rect(park, Color("89b67b"))
		for path: Rect2 in layout.get("paths", []):
			_paint_rect(path, Color("e5dac0"))
		for road: Rect2 in layout.get("roads", []):
			_paint_rect(road, Color("f8f5ea"))
		for entry: Dictionary in layout.get("buildings", []):
			var box: Rect2 = _rect(entry["rect"])
			if not box.has_area():
				continue
			var tint: Color = entry.get("color", Color("c7c3b1"))
			draw_rect(box, tint.lerp(Color("c6c5b5"), 0.6))
			draw_rect(box, Color("a9b2a1"), false, 1.0)
		var fountains: Array = layout.get("fountains", [{"position": Vector3(64.0, 0.0, -65.0), "radius": 5.3}])
		for fountain: Dictionary in fountains:
			var position: Vector3 = fountain.get("position", Vector3.ZERO)
			if _visible(position):
				var radius: float = float(fountain.get("radius", 5.3)) * _map_rect().size.x / _view_bounds().size.x
				draw_circle(_point(position), radius, Color("69bdca"))
		_draw_event_district()
		if large:
			_draw_district_labels()
		for pickup: Dictionary in layout.get("pickups", []):
			var position: Vector3 = pickup["position"]
			if _visible(position):
				draw_circle(_point(position), 3.5 if large else 2.2, Color("c9a55b"))
		if large:
			for delivery: Dictionary in layout.get("deliveries", []):
				var position: Vector3 = delivery["position"]
				if _visible(position):
					draw_circle(_point(position), 2.3, Color("8b9c87"))
		var garage_position: Vector3 = layout.get("garage", Vector3(-66.0, 0.0, 23.0))
		if _visible(garage_position):
			var garage: Vector2 = _point(garage_position)
			draw_rect(Rect2(garage - Vector2.ONE * 4.0, Vector2.ONE * 8.0), Color("567a83"))
			if large:
				_caption(garage, "Гараж", Color("243b3a"))
		if large:
			_caption(_point(layout.get("depot", Vector3(-23.0, 0.0, 23.0))), "Склад", Color("243b3a"))
		# No player-to-target straight-line fallback.
		if has_target:
			for i: int in range(1, route_points.size()):
				var segment: PackedVector2Array = _clip_segment(_point(route_points[i - 1]), _point(route_points[i]))
				if segment.size() != 2:
					continue
				var a: Vector2 = segment[0]
				var b: Vector2 = segment[1]
				var walking: bool = walk_last and i == route_points.size() - 1
				var color: Color = Color("dca438") if walking else Color("247b72")
				draw_line(a, b, Color("fffaf0"), 7.0 if large else 5.0, true)
				if walking:
					var segments: int = maxi(1, ceili(a.distance_to(b) / 10.0))
					for dash: int in range(segments):
						var start: float = float(dash) / segments
						var end: float = minf(1.0, (float(dash) + 0.6) / segments)
						draw_line(a.lerp(b, start), a.lerp(b, end), color, 4.0 if large else 2.5, true)
				else:
					draw_line(a, b, color, 4.0 if large else 2.5, true)
				if a.distance_to(b) > 13.0:
					_arrow(a, b, color.darkened(0.2))
			_draw_target()
		for value: Variant in other_players:
			if not value is Dictionary:
				continue
			var entry: Dictionary = value
			if not bool(entry.get("connected", true)) or not entry.get("position", Vector3.ZERO) is Vector3:
				continue
			if not _visible(entry["position"]):
				continue
			var peer: Vector2 = _point(entry["position"])
			var color_index: int = posmod(int(entry.get("id", 0)), PLAYER_COLORS.size())
			draw_circle(peer, 7.0 if large else 4.5, Color("fffaf0"))
			draw_circle(peer, 5.0 if large else 3.0, PLAYER_COLORS[color_index])
			if large:
				_caption(peer, String(entry.get("name", "Курьер")).substr(0, 16), Color("243b3a"))
		var player: Vector2 = _point(player_position)
		draw_circle(player, 9.0 if large else 6.0, Color("fffaf0"))
		var forward: Vector2 = Vector2(-sin(player_yaw), -cos(player_yaw))
		var radius: float = 8.0 if large else 5.0
		var triangle: PackedVector2Array = PackedVector2Array([player + forward * radius, player + forward.rotated(2.45) * radius, player + forward.rotated(-2.45) * radius])
		draw_colored_polygon(triangle, Color("195b57"))
		var area: Rect2 = _map_rect()
		if not large:
			draw_rect(Rect2(area.position, Vector2(area.size.x, 18.0)), Color(1.0, 0.98, 0.94, 0.86))
			draw_string(ThemeDB.fallback_font, area.position + Vector2(4, 13), current_district(), HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, area.size.x - 29.0), 9, Color("435b57"))
		draw_string(ThemeDB.fallback_font, area.position + Vector2(area.size.x - 25, 13), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11 if large else 9, Color("526454"))
		var meters: float = 100.0 if large else 25.0
		var scale_width: float = meters * area.size.x / _view_bounds().size.x
		var scale_start: Vector2 = area.position + Vector2(7.0, area.size.y - 10.0)
		draw_rect(Rect2(scale_start - Vector2(3.0, 15.0), Vector2(scale_width + 6.0, 21.0)), Color(1.0, 0.98, 0.94, 0.88))
		draw_line(scale_start, scale_start + Vector2(scale_width, 0.0), Color("526454"), 2.0, true)
		draw_line(scale_start - Vector2(0.0, 3.0), scale_start + Vector2(0.0, 3.0), Color("526454"), 1.0, true)
		draw_line(scale_start + Vector2(scale_width, -3.0), scale_start + Vector2(scale_width, 3.0), Color("526454"), 1.0, true)
		draw_string(ThemeDB.fallback_font, scale_start - Vector2(0.0, 5.0), "%d м" % int(meters), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color("526454"))


func _ready() -> void :
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var theme: Theme = Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_color("font_pressed_color", "Button", CREAM)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("normal", "Button", _style(TEAL, 12))
	theme.set_stylebox("hover", "Button", _style(TEAL.lightened(0.12), 12))
	theme.set_stylebox("pressed", "Button", _style(TEAL.darkened(0.12), 12))
	theme.set_stylebox("disabled", "Button", _style(PAPER, 12))
	theme.set_stylebox("focus", "Button", _focus_style())
	_root.theme = theme
	_root.resized.connect(_resize_scroll_overlays)
	_build_game()
	_build_menu()
	_build_lan_menu()
	_build_lobby()
	_build_pause()
	_build_results()
	_build_orders()
	_build_map()
	_build_garage()
	_build_settings()
	_build_customization()
	_build_toast()
	_resize_scroll_overlays()
	_hide_layers()


func _style(color: Color, radius: int = 18) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style


func _focus_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = _style(Color.TRANSPARENT, 12)
	style.border_color = GOLD
	style.set_border_width_all(2)
	return style


func _label(text_value: String, font_size: int = 16, color: Color = INK) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text_value: String, callback: Callable, secondary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 48.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect( func() -> void : ui_click_requested.emit())
	button.pressed.connect(callback)
	if secondary:
		button.add_theme_stylebox_override("normal", _style(PAPER, 12))
		button.add_theme_stylebox_override("hover", _style(PAPER.darkened(0.06), 12))
		button.add_theme_stylebox_override("pressed", _style(PAPER.darkened(0.12), 12))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
	return button


func _vbox(parent: Node, separation: int = 12) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column


func _card(parent: Node, color: Color = CREAM) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _spacer(parent: Node, height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)
	return spacer


func _overlay(panel_size: Vector2) -> Array[Control]:
	var overlay: Control = Control.new()
	_root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.08, 0.16, 0.15, 0.73)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = _card(center)
	panel.custom_minimum_size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return [overlay, panel]


func _scroll_overlay(panel_size: Vector2) -> Array[Control]:
	var overlay: Control = Control.new()
	_root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.08, 0.16, 0.15, 0.73)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	center.add_child(scroll)
	var panel: PanelContainer = _card(scroll)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_overlays.append({"scroll": scroll, "panel": panel, "desired_size": panel_size})
	return [overlay, panel]


func _resize_scroll_overlays() -> void :
	var available: Vector2 = _root.size - Vector2(48.0, 36.0)
	if available.x < 1.0 or available.y < 1.0:
		available = get_viewport().get_visible_rect().size - Vector2(48.0, 36.0)
	for entry: Dictionary in _scroll_overlays:
		var desired: Vector2 = entry["desired_size"]
		var scroll: ScrollContainer = entry["scroll"]
		var panel: PanelContainer = entry["panel"]
		scroll.custom_minimum_size = Vector2(minf(desired.x, maxf(320.0, available.x)), minf(desired.y, maxf(240.0, available.y)))
		panel.custom_minimum_size.x = scroll.custom_minimum_size.x - 14.0
	if is_instance_valid(_garage_grid):
		_garage_grid.columns = 3 if available.x >= 800.0 else (2 if available.x >= 570.0 else 1)
	if is_instance_valid(_customization_panel):
		_customization_panel.custom_minimum_size = Vector2(minf(940.0, maxf(320.0, available.x)), minf(600.0, maxf(320.0, available.y)))
		if is_instance_valid(_cosmetic_items):
			_cosmetic_items.columns = 2 if available.x >= 790.0 else 1
	if is_instance_valid(_full_map):
		# Keep the whole city visible when M opens, including on a 960 × 540 window.
		_full_map.custom_minimum_size.y = clampf(available.y - 185.0, 260.0, 440.0)


func _compact_button(text_value: String, callback: Callable, secondary: bool = false) -> Button:
	var button: Button = _button(text_value, callback, secondary)
	button.custom_minimum_size.y = 42.0
	var colors: Array = [PAPER, PAPER.darkened(0.06), PAPER.darkened(0.12)] if secondary else [TEAL, TEAL.lightened(0.12), TEAL.darkened(0.12)]
	var states: Array[String] = ["normal", "hover", "pressed"]
	for index: int in states.size():
		var box: StyleBoxFlat = _style(colors[index], 10)
		box.content_margin_top = 8.0
		box.content_margin_bottom = 8.0
		button.add_theme_stylebox_override(states[index], box)
	var disabled_box: StyleBoxFlat = _style(PAPER, 10)
	disabled_box.content_margin_top = 8.0
	disabled_box.content_margin_bottom = 8.0
	button.add_theme_stylebox_override("disabled", disabled_box)
	return button


func _field(parent: Node, caption: String, placeholder: String) -> LineEdit:
	parent.add_child(_label(caption, 13, MUTED))
	var field: LineEdit = LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = 48
	field.custom_minimum_size.y = 40.0
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", MUTED)
	var box: StyleBoxFlat = _style(Color("ffffff"), 8)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	box.border_color = Color("d5ddcf")
	box.set_border_width_all(1)
	field.add_theme_stylebox_override("normal", box)
	field.add_theme_stylebox_override("focus", _focus_style())
	parent.add_child(field)
	return field


func _build_menu() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(880, 510))
	_menu = items[0]
	var layout: HBoxContainer = HBoxContainer.new()
	layout.add_theme_constant_override("separation", 38)
	items[1].add_child(layout)
	var copy: VBoxContainer = _vbox(layout, 10)
	copy.custom_minimum_size.x = 420.0
	copy.add_child(_label("DELIVERY / 01", 13, TEAL))
	_spacer(copy, 8.0)
	copy.add_child(_label("Delivery\nSimulator", 48))
	var subtitle: Label = _label("Маленький город. Большая карьера.", 19, MUTED)
	copy.add_child(subtitle)
	copy.add_child(_label("Демоверсия · Solo / LAN", 13, TEAL))
	_spacer(copy, 10.0)
	_menu_profile = _label("", 15, MUTED)
	_menu_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_menu_profile)
	_spacer(copy, 6.0)
	copy.add_child(_compact_button("Начать смену", func() -> void : play_requested.emit()))
	var actions: HBoxContainer = HBoxContainer.new()
	copy.add_child(actions)
	var multiplayer_button: Button = _compact_button("Мультиплеер / LAN", func() -> void : multiplayer_requested.emit(), true)
	multiplayer_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(multiplayer_button)
	actions.add_child(_compact_button("Выйти", func() -> void : quit_requested.emit(), true))
	var profile_actions: HBoxContainer = HBoxContainer.new()
	profile_actions.add_theme_constant_override("separation", 10)
	copy.add_child(profile_actions)
	var style_button: Button = _compact_button("Профиль / стиль", func() -> void: customization_requested.emit(), true)
	style_button.name = "OpenCustomizationMenu"
	style_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_actions.add_child(style_button)
	_menu_settings = _compact_button("Настройки", func() -> void : settings_requested.emit(), true)
	_menu_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_actions.add_child(_menu_settings)
	var side: PanelContainer = _card(layout, PAPER)
	side.custom_minimum_size.x = 340.0
	var info: VBoxContainer = _vbox(side, 12)
	info.add_child(_label("СМЕНА КУРЬЕРА", 12, MUTED))
	var map_preview: MapView = MapView.new()
	map_preview.custom_minimum_size = Vector2(290, 180)
	map_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_preview.update_positions(Vector3(-55, 0, 55), Vector3(30, 0, -25))
	info.add_child(map_preview)
	info.add_child(_label("01  Выберите заказ", 17))
	info.add_child(_label("02  Заберите посылку", 17))
	info.add_child(_label("03  Доставьте и заработайте", 17))
	var note: Label = _label("Прогресс сохраняется автоматически.\nWASD — движение · мышь — камера\nE — гараж · F — сесть / выйти", 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(note)


func _build_lan_menu() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(900, 580))
	_lan_menu = items[0]
	var content: VBoxContainer = _vbox(items[1], 10)
	content.add_child(_label("DELIVERY / LAN", 12, TEAL))
	content.add_child(_label("Смена с друзьями", 30))
	content.add_child(_label("Одна сеть · до четырёх курьеров · общий город и заказы", 14, MUTED))
	var identity: HBoxContainer = HBoxContainer.new()
	identity.add_theme_constant_override("separation", 14)
	content.add_child(identity)
	var name_caption: Label = _label("Ваше имя", 14)
	name_caption.custom_minimum_size.x = 105.0
	identity.add_child(name_caption)
	_lan_name = LineEdit.new()
	_lan_name.placeholder_text = "Курьер"
	_lan_name.max_length = 32
	_lan_name.custom_minimum_size.y = 40.0
	_lan_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_name.add_theme_color_override("font_color", INK)
	_lan_name.add_theme_color_override("font_placeholder_color", MUTED)
	var name_style: StyleBoxFlat = _style(PAPER, 8)
	name_style.content_margin_top = 8.0
	name_style.content_margin_bottom = 8.0
	_lan_name.add_theme_stylebox_override("normal", name_style)
	_lan_name.add_theme_stylebox_override("focus", _focus_style())
	identity.add_child(_lan_name)
	var cards: HBoxContainer = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	content.add_child(cards)
	var host_card: PanelContainer = _card(cards, PAPER)
	host_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var host: VBoxContainer = _vbox(host_card, 8)
	host.add_child(_label("Создать комнату", 22))
	_lan_room = _field(host, "Название комнаты", "Курьерская смена")
	_lan_room.max_length = 32
	var options: HBoxContainer = HBoxContainer.new()
	options.add_theme_constant_override("separation", 12)
	host.add_child(options)
	var count: VBoxContainer = _vbox(options, 5)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.add_child(_label("Игроков", 13, MUTED))
	_lan_max_players = OptionButton.new()
	_lan_max_players.item_selected.connect( func(_index: int) -> void : ui_click_requested.emit())
	_lan_max_players.custom_minimum_size.y = 40.0
	for value: int in range(1, 5):
		_lan_max_players.add_item(str(value), value)
	_lan_max_players.select(3)
	count.add_child(_lan_max_players)
	var duration: VBoxContainer = _vbox(options, 5)
	duration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration.add_child(_label("Длительность", 13, MUTED))
	_lan_shift = OptionButton.new()
	_lan_shift.item_selected.connect( func(_index: int) -> void : ui_click_requested.emit())
	_lan_shift.custom_minimum_size.y = 40.0
	_lan_shift.add_item("10 минут", 600)
	_lan_shift.add_item("15 минут", 900)
	_lan_shift.add_item("20 минут", 1200)

	_lan_shift.add_item("Без ограничения", 0)
	_lan_shift.select(1)
	duration.add_child(_lan_shift)
	host.add_child(_label("Режим смены", 13, MUTED))
	_lan_mode = OptionButton.new()
	_lan_mode.custom_minimum_size.y = 40.0
	_lan_mode.add_item("Соревнование", 0)
	_lan_mode.add_item("Командная смена", 1)
	_lan_mode.select(0)
	_lan_mode.item_selected.connect(func(_index: int) -> void: ui_click_requested.emit())
	host.add_child(_lan_mode)
	var mode_note: Label = _label("Командная смена: общий план и личный бонус за вклад. Можно передать посылку другу с его согласия.", 12, MUTED)
	mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_note.custom_minimum_size.x = 280.0
	host.add_child(mode_note)
	host.add_child(_label("Host запускает смену, когда все готовы.", 12, MUTED))
	_lan_host_button = _compact_button("Создать · Host", _request_host)
	host.add_child(_lan_host_button)
	var join_card: PanelContainer = _card(cards, PAPER)
	join_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join: VBoxContainer = _vbox(join_card, 8)
	join.add_child(_label("Войти в комнату", 22))
	_lan_address = _field(join, "IP-адрес Host", "192.168.1.20")
	join.add_child(_label("UDP · порт 7777", 14, TEAL))
	var join_note: Label = _label("Попросите IP у Host. Компьютеры должны быть в одной локальной сети.", 13, MUTED)
	join_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_note.custom_minimum_size = Vector2(300.0, 54.0)
	join.add_child(join_note)
	_lan_join_button = _compact_button("Подключиться · Join", _request_join)
	join.add_child(_lan_join_button)
	_lan_status = _label("", 14, TEAL)
	_lan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_lan_status)
	_lan_back_button = _compact_button("Главное меню", func() -> void : leave_requested.emit(), true)
	content.add_child(_lan_back_button)


func _request_host() -> void :
	var player_name: String = _lan_name.text.strip_edges()
	var room_name: String = _lan_room.text.strip_edges()
	var shift_seconds: int = _lan_shift.get_selected_id()
	var shift_mode: String = "team" if _lan_mode.get_selected_id() == 1 else "competitive"
	host_requested.emit(player_name if not player_name.is_empty() else "Курьер", room_name if not room_name.is_empty() else "Курьерская смена", _lan_max_players.get_selected_id(), -1 if shift_seconds == 0 else shift_seconds, shift_mode)


func _request_join() -> void :
	var player_name: String = _lan_name.text.strip_edges()
	join_requested.emit(player_name if not player_name.is_empty() else "Курьер", _lan_address.text.strip_edges())


func _build_lobby() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(900, 560))
	_lobby = items[0]
	var content: VBoxContainer = _vbox(items[1], 10)
	content.add_child(_label("DELIVERY / КОМНАТА", 12, TEAL))
	_lobby_title = _label("Курьерская смена", 30)
	_lobby_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_lobby_title)
	_lobby_address = _label("Host IP · UDP 7777", 15, TEAL)
	content.add_child(_lobby_address)
	_lobby_details = _label("", 14, MUTED)
	_lobby_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_lobby_details)
	var roster: PanelContainer = _card(content, PAPER)
	var roster_content: VBoxContainer = _vbox(roster, 8)
	_add_roster_row(roster_content, "Игрок", "Готовность", "Уровень / ранг", "Курьер / транспорт", true)
	_lobby_players = _vbox(roster_content, 8)
	_lobby_players.custom_minimum_size.y = 136.0
	_lobby_ready = CheckBox.new()
	_lobby_ready.pressed.connect( func() -> void : ui_click_requested.emit())
	_lobby_ready.text = "Я готов к смене"
	_lobby_ready.custom_minimum_size.y = 36.0
	_lobby_ready.add_theme_color_override("font_color", INK)
	_lobby_ready.toggled.connect( func(value: bool) -> void : ready_requested.emit(value))
	content.add_child(_lobby_ready)
	_lobby_wait = _label("Ожидаем Host…", 14, MUTED)
	_lobby_wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_lobby_wait)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	_lobby_start = _compact_button("Начать общую смену", func() -> void : start_requested.emit())
	_lobby_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_lobby_start)
	var leave: Button = _compact_button("Выйти из комнаты", func() -> void : leave_requested.emit(), true)
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(leave)


func _add_roster_row(parent: Node, player_name: String, ready_text: String, career: String, character: String, heading: bool = false) -> void :
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size.y = 26.0 if heading else 42.0
	parent.add_child(row)
	var values: Array[String] = [player_name, ready_text, career, character]
	var widths: Array[float] = [205.0, 115.0, 240.0, 145.0]
	for index: int in values.size():
		var cell: Label = _label(values[index], 12 if heading else 14, MUTED if heading else INK)
		cell.custom_minimum_size.x = widths[index]
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.clip_text = true
		cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if not heading:
			cell.tooltip_text = values[index]
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
		if index == 1 and not heading:
			cell.add_theme_color_override("font_color", TEAL if ready_text == "Готов" else MUTED)
		row.add_child(cell)


func _build_game() -> void :
	_game = Control.new()
	_root.add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var active: PanelContainer = _card(_game)
	_active_order_panel = active
	active.position = Vector2(24, 24)
	active.custom_minimum_size = Vector2(320, 150)
	active.resized.connect(_position_order_summary)
	var content: VBoxContainer = _vbox(active, 6)
	content.add_child(_label("АКТИВНЫЙ ЗАКАЗ", 11, MUTED))
	_order_title = _label("Готовы к первой доставке?", 20)
	_order_title.custom_minimum_size.x = 280.0
	_order_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_order_title)
	_order_status = _label("Tab — выберите заказ", 14, TEAL)
	content.add_child(_order_status)
	_target = _label("", 14, MUTED)
	content.add_child(_target)
	_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_navigation_hint = _label("", 13, TEAL)
	_navigation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_navigation_hint.custom_minimum_size.x = 280.0
	content.add_child(_navigation_hint)
	_order_event_hint = _label("", 12, EVENT_ORANGE)
	_order_event_hint.name = "ActiveOrderEventHint"
	_order_event_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_event_hint.custom_minimum_size.x = 280.0
	content.add_child(_order_event_hint)
	_order_event_hint.hide()
	_order_quality = _vbox(content, 4)
	_quality_text = _label("Состояние посылки · 100%", 13, TEAL)
	_order_quality.add_child(_quality_text)
	_quality_bar = ProgressBar.new()
	_quality_bar.custom_minimum_size.y = 9.0
	_quality_bar.min_value = 0.0
	_quality_bar.max_value = 100.0
	_quality_bar.value = 100.0
	_quality_bar.show_percentage = false
	_quality_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quality_bar.add_theme_stylebox_override("background", _quality_bar_style(PAPER))
	_quality_fill = _quality_bar_style(TEAL)
	_quality_bar.add_theme_stylebox_override("fill", _quality_fill)
	_order_quality.add_child(_quality_bar)
	_quality_bonus = _label("", 12, MUTED)
	_order_quality.add_child(_quality_bonus)
	_order_quality.hide()
	var finances: PanelContainer = _card(_game)
	finances.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	finances.offset_left = -260.0
	finances.offset_right = -24.0
	finances.offset_top = 24.0
	finances.offset_bottom = 156.0
	var stats: VBoxContainer = _vbox(finances, 5)
	_money = _label("0 ₽", 27)
	stats.add_child(_money)
	_xp_level = _label("Уровень 1 · 0 XP", 14, TEAL)
	stats.add_child(_xp_level)
	_rank = _label("Rookie Courier", 12, MUTED)
	stats.add_child(_rank)
	var mini_panel: PanelContainer = _card(_game)
	mini_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mini_panel.offset_left = -216.0
	mini_panel.offset_right = -24.0
	mini_panel.offset_top = 171.0
	mini_panel.offset_bottom = 363.0
	mini_panel.add_theme_stylebox_override("panel", _style(CREAM, 16))
	_mini_map = MapView.new()
	_mini_map.custom_minimum_size = Vector2(152, 152)
	_mini_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_panel.add_child(_mini_map)
	var clock: PanelContainer = _card(_game)
	clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	clock.offset_left = -64.0
	clock.offset_right = 64.0
	clock.offset_top = 24.0
	clock.offset_bottom = 79.0
	_timer = _label("10:00", 22)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_child(_timer)
	_build_team_progress()
	_build_district_event()
	_deliveries = _label("Доставлено: 0", 13, CREAM)
	_deliveries.add_theme_color_override("font_outline_color", INK)
	_deliveries.add_theme_constant_override("outline_size", 3)
	_game.add_child(_deliveries)
	_deliveries.position = Vector2(24, 192)
	_vehicle = _label("Пешком", 13, CREAM)
	_vehicle.add_theme_color_override("font_outline_color", INK)
	_vehicle.add_theme_constant_override("outline_size", 3)
	_game.add_child(_vehicle)
	_vehicle.position = Vector2(24, 216)
	_interaction_panel = _card(_game)
	_interaction_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_interaction_panel.offset_left = -260.0
	_interaction_panel.offset_right = 260.0
	_interaction_panel.offset_top = -104.0
	_interaction_panel.offset_bottom = -52.0
	_interaction = _label("", 16)
	_interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_panel.add_child(_interaction)
	_keys = _label("WASD движение · Shift бег · Space прыжок · E действие · F транспорт · Tab заказы · M карта · Esc пауза", 12, CREAM)
	_game.add_child(_keys)
	_keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_keys.offset_top = -37.0
	_keys.offset_bottom = -14.0
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keys.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	_keys.add_theme_constant_override("shadow_offset_x", 1)
	_keys.add_theme_constant_override("shadow_offset_y", 1)
	_keys.add_theme_color_override("font_outline_color", INK)
	_keys.add_theme_constant_override("outline_size", 3)
	_interaction_panel.hide()
	_ignore_mouse(_game)
	_position_order_summary()



func _build_district_event() -> void:
	_event_panel = _card(_game, EVENT_PAPER)
	_event_panel.name = "DistrictEventBanner"
	_event_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_event_panel.offset_left = -130.0
	_event_panel.offset_right = 130.0
	_event_panel.offset_top = 92.0
	_event_panel.offset_bottom = 178.0
	var box: StyleBoxFlat = _style(EVENT_PAPER, 14)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.border_color = Color("e1b778")
	box.set_border_width_all(1)
	_event_panel.add_theme_stylebox_override("panel", box)
	var content: VBoxContainer = _vbox(_event_panel, 3)
	_event_title = _label("", 14, EVENT_ORANGE)
	_event_title.name = "DistrictEventTitle"
	_event_title.custom_minimum_size.x = 220.0
	_event_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_event_title)
	_event_detail = _label("", 12, MUTED)
	_event_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_event_detail)
	_event_bonus = _label("", 12, EVENT_ORANGE)
	_event_bonus.name = "DistrictEventBonus"
	_event_bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_event_bonus)
	_event_panel.hide()
	_ignore_mouse(_event_panel)


func _position_district_event() -> void:
	if not is_instance_valid(_event_panel) or not is_instance_valid(_team_panel):
		return
	var top: float = _team_panel.offset_top + maxf(_team_panel.size.y, _team_panel.get_combined_minimum_size().y) + 10.0 if _team_panel.visible else 92.0
	_event_panel.offset_top = top
	_event_panel.offset_bottom = top + 86.0


func _event_percent(multiplier: float) -> int:
	return maxi(0, roundi((multiplier - 1.0) * 100.0)) if is_finite(multiplier) else 0


func _update_district_event(data: Dictionary) -> void:
	var event: Dictionary = data.get("district_event", {})
	var phase: String = String(event.get("phase", "ended"))
	var active: bool = phase == "active"
	var waiting: bool = phase in ["waiting", "cooldown"] and float(event.get("starts_in", 0.0)) > 0.0
	_event_panel.visible = active or waiting
	_orders_event_panel.visible = active or waiting
	var name_value: String = String(event.get("name", "Обеденный час"))
	var district_name: String = String(event.get("district_name", "Деловой центр"))
	var percent: int = _event_percent(float(event.get("bonus_multiplier", 1.5)))
	var countdown: String = _time(float(event.get("remaining", 0.0))) if active else _time(float(event.get("starts_in", 0.0)))
	_event_title.text = "%s · %s" % [name_value, countdown] if active else "Событие через " + countdown
	_event_detail.text = district_name if active else "%s · %s" % [name_value, district_name]
	_event_bonus.text = "+%d%% за доставку вовремя · Tab" % percent
	_event_bonus.visible = active
	_orders_event_text.text = "%s · %s · осталось %s\nКафе → офисы: +%d%% к базовой награде, если доставить до конца события." % [name_value, district_name, countdown, percent] if active else "%s начнётся через %s · %s. Короткие доставки кафе → офисы с бонусом +%d%%." % [name_value, countdown, district_name, percent]
	_position_district_event()
	_mini_map.update_district_event(event)
	_full_map.update_district_event(event)
	_map_event_label.text = "▲ Вы · ● Получение / доставка · ■ Гараж · пунктир — пешком · M — закрыть\nОранжевый контур: %s · %s · %s · +%d%% вовремя." % [name_value, district_name, countdown, percent] if active else "▲ Вы · ● Получение / доставка · ■ Гараж · пунктир — пешком · M — закрыть\nМини-карта показывает соседние улицы; здесь — весь город и его районы."
	var order_event: Dictionary = data.get("order_event", {})
	var was_visible: bool = _order_event_hint.visible
	_order_event_hint.visible = _has_active_order and not String(order_event.get("id", "")).is_empty()
	if _order_event_hint.visible:
		var bonus_available: bool = bool(order_event.get("bonus_available", false))
		var order_name: String = String(order_event.get("name", name_value))
		var bonus: int = maxi(0, int(order_event.get("bonus_money", 0)))
		_order_event_hint.text = "%s · %s · +%s ₽ вовремя" % [order_name, _time(float(order_event.get("remaining", 0.0))), _amount(bonus)] if bonus_available else "%s завершён · обычная награда" % order_name
	else:
		_order_event_hint.text = ""
	if was_visible != _order_event_hint.visible:
		_active_order_panel.reset_size.call_deferred()
	_update_event_order_badges(event)


func _update_event_order_badges(event: Dictionary) -> void:
	for entry: Dictionary in _event_order_badges:
		var label: Label = entry["label"]
		if not is_instance_valid(label):
			continue
		var order_id: String = String(entry.get("id", ""))
		var current: bool = String(event.get("phase", "")) == "active" and String(event.get("id", "")) == order_id
		var remaining: float = maxf(0.0, float(event.get("remaining", 0.0))) if current else maxf(0.0, float(entry.get("remaining", 0.0)))
		# Snapshot phase closes the current cycle. Never guess the deadline from a client wall clock.
		var available: bool = current and remaining > 0.0 and bool(entry.get("available", false))
		label.text = "%s · %s · +%s ₽ вовремя" % [String(entry.get("name", "Обеденный час")), _time(remaining), _amount(int(entry.get("bonus", 0)))] if available else "%s · обычная награда после события" % String(entry.get("name", "Обеденный час"))
		label.set_meta("event_bonus_available", available)
		label.set_meta("event_remaining", remaining if available else 0.0)


func _build_team_progress() -> void:
	_team_panel = _card(_game)
	_team_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_team_panel.offset_left = -130.0
	_team_panel.offset_right = 130.0
	_team_panel.offset_top = 92.0
	_team_panel.offset_bottom = 180.0
	var box: StyleBoxFlat = _style(CREAM, 14)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	_team_panel.add_theme_stylebox_override("panel", box)
	var content: VBoxContainer = _vbox(_team_panel, 4)
	_team_progress = _label("", 14, TEAL)
	content.add_child(_team_progress)
	_team_status = _label("", 12, MUTED)
	_team_status.custom_minimum_size.x = 220.0
	_team_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_team_status)
	_team_message = _label("", 12, TEAL)
	_team_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_team_message)
	_team_panel.hide()
	_ignore_mouse(_team_panel)
	_team_panel.resized.connect(_position_district_event)


func _team_goal_text(team: Dictionary) -> String:
	return "Общий план: %d / %d доставок%s" % [int(team.get("delivered", 0)), int(team.get("target", 0)), " — выполнен!" if bool(team.get("completed", false)) else ""]


func _team_personal_text(team: Dictionary) -> String:
	var contribution: int = int(team.get("contributions", 0))
	var reward: String = "+%s ₽ · +%d XP" % [_amount(int(team.get("bonus_money", 0))), int(team.get("bonus_xp", 0))]
	if bool(team.get("bonus_awarded", false)):
		return "Ваш вклад: %d доставок. Командный бонус получен: %s." % [contribution, reward]
	if contribution < 1:
		return "Для личного бонуса %s завершите хотя бы одну доставку. Получение и передача посылки не считаются доставкой." % reward
	return "Ваш вклад: %d доставок. Бонус %s начисляется один раз после общего плана, пока вы в сессии." % [contribution, reward]


func _update_team_hud(data: Dictionary) -> void:
	var team: Dictionary = data.get("team", {})
	var enabled: bool = _network_enabled and bool(team.get("enabled", false))
	_team_panel.visible = enabled
	_handoff_panel.visible = enabled
	if not enabled:
		_handoff_signature = ""
		return
	_team_progress.text = "КОМАНДА · %d / %d" % [int(team.get("delivered", 0)), int(team.get("target", 0))]
	_team_status.text = "План выполнен · бонус получен" if bool(team.get("bonus_awarded", false)) else ("Ваш вклад: %d · ждём общий план" % int(team.get("contributions", 0)) if bool(team.get("eligible", false)) else "Доставьте 1 заказ для личного бонуса")
	var handoffs: Dictionary = data.get("handoffs", {})
	var incoming: Array = handoffs.get("incoming", [])
	var outgoing: Dictionary = handoffs.get("outgoing", {})
	_team_message.text = "Вам предлагают посылку · Tab" if not incoming.is_empty() else ("Передача ожидает друга · Tab" if not outgoing.is_empty() else "")
	_team_message.visible = not _team_message.text.is_empty()
	_update_handoffs(data)
	if is_instance_valid(_handoff_progress):
		_handoff_progress.text = _team_goal_text(team)
		_handoff_personal.text = _team_personal_text(team)


func _handoff_key(entry: Dictionary, incoming: bool) -> Dictionary:
	return {
		"offer_id": int(entry.get("offer_id", 0)),
		"peer_id": int(entry.get("sender_id" if incoming else "target_id", 0)),
		"order_id": int(entry.get("order_id", 0)),
		"name": String(entry.get("name", "Курьер")),
		"title": String(entry.get("title", "Посылка")),
	}


func _update_handoffs(data: Dictionary) -> void:
	var handoffs: Dictionary = data.get("handoffs", {})
	var incoming: Array = handoffs.get("incoming", [])
	var outgoing: Dictionary = handoffs.get("outgoing", {})
	var candidates: Array = data.get("handoff_candidates", [])
	var incoming_keys: Array = []
	var candidate_keys: Array = []
	for value: Variant in incoming:
		if value is Dictionary:
			incoming_keys.append(_handoff_key(value, true))
	for value: Variant in candidates:
		if value is Dictionary:
			candidate_keys.append({"id": int(value.get("id", 0)), "name": String(value.get("name", "Курьер"))})
	var signature: String = JSON.stringify({"incoming": incoming_keys, "outgoing": _handoff_key(outgoing, false) if not outgoing.is_empty() else {}, "candidates": candidate_keys, "picked": String(data.get("order_state", "")) == "PickedUp"})
	if signature != _handoff_signature:
		_handoff_signature = signature
		_rebuild_handoffs(incoming, outgoing, candidates, String(data.get("order_state", "")) == "PickedUp")
	# Remaining time changes every snapshot; keep controls and keyboard focus intact.
	for timer: Dictionary in _handoff_timers:
		var entry: Dictionary = {}
		if bool(timer.get("incoming", false)):
			for value: Variant in incoming:
				if value is Dictionary and int(value.get("sender_id", 0)) == int(timer["sender_id"]) and int(value.get("offer_id", 0)) == int(timer["offer_id"]):
					entry = value
					break
		else:
			entry = outgoing
		var remaining: float = maxf(0.0, float(entry.get("remaining", 0.0)))
		var label: Label = timer["label"]
		label.text = "Ответьте за %d с" % ceili(remaining) if bool(timer.get("incoming", false)) else "Ожидаем согласия · %d с" % ceili(remaining)
		for button: Button in timer["buttons"]:
			button.disabled = remaining <= 0.0


func _rebuild_handoffs(incoming: Array, outgoing: Dictionary, candidates: Array, picked_up: bool) -> void:
	_handoff_timers.clear()
	for child: Node in _handoff_rows.get_children():
		_handoff_rows.remove_child(child)
		child.queue_free()
	_handoff_rows.add_child(_label("КОМАНДНАЯ СМЕНА", 12, TEAL))
	_handoff_progress = _label("", 16)
	_handoff_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_handoff_rows.add_child(_handoff_progress)
	_handoff_personal = _label("", 12, MUTED)
	_handoff_personal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_handoff_rows.add_child(_handoff_personal)
	var help: Label = _label("Передача: оба пешком и рядом, у получателя нет заказа. Друг должен согласиться. Деньги и XP за заказ получает тот, кто доставит посылку.", 12, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_handoff_rows.add_child(help)
	for value: Variant in incoming:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var sender_id: int = int(entry.get("sender_id", 0))
		var offer_id: int = int(entry.get("offer_id", 0))
		var name: String = String(entry.get("name", "Курьер"))
		var title: Label = _label("Посылка от %s: %s" % [name, String(entry.get("title", "Доставка"))], 15, TEAL)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_handoff_rows.add_child(title)
		var countdown: Label = _label("", 12, MUTED)
		_handoff_rows.add_child(countdown)
		var actions: HBoxContainer = HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		_handoff_rows.add_child(actions)
		var accept: Button = _compact_button("Принять посылку", func() -> void: handoff_accept_requested.emit(sender_id, offer_id))
		accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(accept)
		var decline: Button = _compact_button("Отказаться", func() -> void: handoff_decline_requested.emit(sender_id, offer_id), true)
		decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(decline)
		_handoff_timers.append({"incoming": true, "sender_id": sender_id, "offer_id": offer_id, "label": countdown, "buttons": [accept, decline]})
	if not outgoing.is_empty():
		var title: Label = _label("Предложено %s: %s" % [String(outgoing.get("name", "Курьер")), String(outgoing.get("title", "Посылка"))], 15)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_handoff_rows.add_child(title)
		var countdown: Label = _label("", 12, MUTED)
		_handoff_rows.add_child(countdown)
		var cancel: Button = _compact_button("Отменить предложение", func() -> void: handoff_cancel_requested.emit(), true)
		_handoff_rows.add_child(cancel)
		_handoff_timers.append({"incoming": false, "label": countdown, "buttons": [cancel]})
	elif not candidates.is_empty():
		_handoff_rows.add_child(_label("Передать вашу посылку:", 14))
		for value: Variant in candidates:
			if not value is Dictionary:
				continue
			var candidate: Dictionary = value
			var target_id: int = int(candidate.get("id", 0))
			var name: String = String(candidate.get("name", "Курьер"))
			_handoff_rows.add_child(_compact_button("Предложить · " + name, func() -> void: handoff_offer_requested.emit(target_id), true))
	else:
		var reason: Label = _label("Подойдите пешком к свободному другу, чтобы предложить посылку." if picked_up else "Сначала заберите посылку. Затем её можно предложить свободному другу.", 12, MUTED)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_handoff_rows.add_child(reason)


func _update_team_results(stats: Dictionary) -> void:
	var team: Dictionary = stats.get("team", {})
	_results_team.visible = bool(team.get("enabled", false))
	if not _results_team.visible:
		return
	var money: int = int(stats.get("team_bonus_money", 0))
	var xp: int = int(stats.get("team_bonus_xp", 0))
	var outcome: String = "Ваш командный бонус: +%s ₽ · +%d XP (уже включён в итоги)." % [_amount(money), xp]
	if money <= 0 and xp <= 0:
		outcome = "Командный бонус не получен: вы не завершили личную доставку." if int(team.get("contributions", 0)) < 1 else "Командный бонус не получен: общий план не выполнен."
	_results_team_text.text = "%s\nДоставлено вами: %d. %s" % [_team_goal_text(team), int(team.get("contributions", 0)), outcome]


func _quality_bar_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style


func _position_order_summary() -> void :
	if not is_instance_valid(_active_order_panel) or not is_instance_valid(_deliveries) or not is_instance_valid(_vehicle):
		return
	var below: float = _active_order_panel.position.y + _active_order_panel.size.y + 12.0
	_deliveries.position = Vector2(24.0, below)
	_vehicle.position = Vector2(24.0, below + 24.0)


func _update_order_quality(data: Dictionary) -> void :
	var fragile: bool = _has_active_order and String(data.get("order_type", "")) == "fragile"
	var was_visible: bool = _order_quality.visible
	_order_quality.visible = fragile
	if was_visible != fragile:
		_active_order_panel.reset_size.call_deferred()
	if not fragile:
		_quality_text.text = ""
		_quality_bar.value = 100.0
		_quality_bonus.text = ""
		return
	var picked_up: bool = String(data.get("order_state", "")) == "PickedUp"
	var quality: float = float(data.get("quality", 100.0))
	quality = clampf(quality, 0.0, 100.0) if is_finite(quality) else 100.0
	if not picked_up:
		quality = 100.0
	var color: Color = TEAL if quality >= 80.0 else GOLD.darkened(0.3) if quality >= 40.0 else Color("c25446")
	_quality_text.text = "Состояние посылки · %d%%" % roundi(quality) if picked_up else "Посылка · получите груз"
	_quality_text.add_theme_color_override("font_color", color)
	_quality_bar.value = quality
	_quality_fill.bg_color = color
	var maximum: int = maxi(0, int(data.get("quality_bonus_max", 0)))
	var bonus: int = clampi(int(data.get("quality_bonus", maximum)), 0, maximum)
	_quality_bonus.text = "За качество: +%s ₽ из +%s ₽" % [_amount(bonus), _amount(maximum)] if picked_up else "За качество: до +%s ₽" % _amount(maximum)


func _ignore_mouse(control: Control) -> void :
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in control.get_children():
		if child is Control:
			_ignore_mouse(child as Control)


func _build_pause() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(500, 470))
	_pause = items[0]
	var content: VBoxContainer = _vbox(items[1], 12)
	content.add_child(_label("ПАУЗА", 12, TEAL))
	content.add_child(_label("Можно перевести дух.", 29))
	_pause_profile = _label("", 15, MUTED)
	_pause_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_pause_profile)
	_spacer(content, 8.0)
	content.add_child(_compact_button("Продолжить смену", func() -> void : resume_requested.emit()))
	_pause_settings = _compact_button("Настройки", func() -> void : settings_requested.emit(), true)
	content.add_child(_pause_settings)
	_pause_restart = _compact_button("Начать новую смену", func() -> void : restart_requested.emit(), true)
	content.add_child(_pause_restart)
	_pause_leave = _compact_button("Выйти из комнаты · главное меню", func() -> void : leave_requested.emit(), true)
	content.add_child(_pause_leave)
	_pause_leave.hide()
	content.add_child(_compact_button("Выйти из игры", func() -> void : quit_requested.emit(), true))
	_pause_hint = _label("Карьерный прогресс уже сохранён.", 13, MUTED)
	_pause_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_pause_hint)


func _build_results() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(900, 600))
	_results = items[0]
	var content: VBoxContainer = _vbox(items[1], 10)
	content.add_child(_label("ИТОГИ СМЕНЫ", 12, TEAL))
	_results_title = _label("Хорошая работа, курьер!", 30)
	content.add_child(_results_title)
	_results_summary = _label("", 16, MUTED)
	content.add_child(_results_summary)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	content.add_child(columns)
	var numbers: PanelContainer = _card(columns, PAPER)
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_numbers = _label("", 19)
	_results_numbers.add_theme_constant_override("line_spacing", 8)
	numbers.add_child(_results_numbers)
	_leaderboard_panel = _card(columns, PAPER)
	_leaderboard_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var board: VBoxContainer = _vbox(_leaderboard_panel, 8)
	board.add_child(_label("КУРЬЕРЫ ЭТОЙ СМЕНЫ", 11, TEAL))
	_add_leaderboard_row(board, {"name": "Игрок"}, true)
	_leaderboard_rows = _vbox(board, 6)
	_leaderboard_rows.custom_minimum_size.y = 116.0
	_leaderboard_panel.hide()
	_results_team = _card(content, PAPER)
	_results_team_text = _label("", 14, TEAL)
	_results_team_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_team.add_child(_results_team_text)
	_results_team.hide()
	content.add_child(_label("Награды добавлены в ваш профиль.", 14, TEAL))
	_results_wait = _label("", 14, MUTED)
	content.add_child(_results_wait)
	_results_wait.hide()
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	_results_restart = _compact_button("Следующая смена  →", _request_next_shift)
	_results_restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_results_restart)
	_results_leave = _compact_button("Главное меню", func() -> void : leave_requested.emit(), true)
	_results_leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_results_leave)
	_results_leave.hide()
	actions.add_child(_compact_button("Выйти из игры", func() -> void : quit_requested.emit(), true))


func _add_leaderboard_row(parent: Node, entry: Dictionary, heading: bool = false) -> void :
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 23.0
	parent.add_child(row)
	var player_name: String = String(entry.get("name", "Курьер"))
	if not heading and not bool(entry.get("connected", true)):
		player_name = "Вышел · " + player_name
	var values: Array = ["Игрок", "Дост.", "₽", "XP", "Лучшая"] if heading else [player_name, str(int(entry.get("deliveries", 0))), _amount(int(entry.get("money", 0))), str(int(entry.get("xp", 0))), _amount(int(entry.get("best_delivery", 0)))]
	var widths: Array[float] = [132.0, 34.0, 63.0, 46.0, 66.0]
	for index: int in values.size():
		var cell: Label = _label(values[index], 11 if heading else 13, MUTED if heading or not bool(entry.get("connected", true)) else INK)
		cell.custom_minimum_size.x = widths[index]
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if index == 0 else Control.SIZE_FILL
		cell.clip_text = true
		cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if index == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		if index == 0:
			cell.tooltip_text = player_name
		row.add_child(cell)


func _request_next_shift() -> void :
	if _network_enabled:
		restart_requested.emit()
	else:
		play_requested.emit()


func _build_orders() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(800, 660))
	_orders = items[0]
	var content: VBoxContainer = _vbox(items[1], 10)
	var header: HBoxContainer = HBoxContainer.new()
	content.add_child(header)
	var title: Label = _label("Доска заказов", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Закрыть", _close_modal, true))
	_orders_hint = _label("Выберите маршрут и отправляйтесь к точке получения.", 14, MUTED)
	_orders_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_orders_hint)
	_orders_event_panel = _card(content, EVENT_PAPER)
	_orders_event_panel.name = "DistrictEventOrdersSummary"
	_orders_event_text = _label("", 13, EVENT_ORANGE)
	_orders_event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_orders_event_panel.add_child(_orders_event_text)
	_orders_event_panel.hide()
	_handoff_panel = _card(content, PAPER)
	_handoff_rows = _vbox(_handoff_panel, 8)
	_handoff_panel.hide()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_orders_list = _vbox(scroll, 9)
	_orders_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orders_empty = _label("Сейчас доступных заказов нет.", 17, MUTED)
	_orders_list.add_child(_orders_empty)
	_abandon_button = _button("Отказаться от активного заказа", func() -> void : abandon_requested.emit(), true)
	content.add_child(_abandon_button)
	_abandon_button.hide()


func _build_map() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(650, 610))
	_map = items[0]
	var content: VBoxContainer = _vbox(items[1], 10)
	var header: HBoxContainer = HBoxContainer.new()
	content.add_child(header)
	var title: Label = _label("Карта города", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Закрыть", _close_modal, true))
	_full_map = MapView.new()
	_full_map.large = true
	_full_map.custom_minimum_size = Vector2(580, 440)
	_full_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_full_map)
	_map_event_label = _label("▲ Вы · ● Получение / доставка · ■ Гараж · пунктир — пешком · M — закрыть\nМини-карта показывает соседние улицы; здесь — весь город и его районы.", 12, MUTED)
	_map_event_label.name = "DistrictEventMapLegend"
	_map_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_map_event_label)
	_map_route_label = _label("", 13, TEAL)
	_map_route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_map_route_label)


func _build_garage() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(940, 610))
	_garage = items[0]
	var content: VBoxContainer = _vbox(items[1], 12)
	content.add_child(_label("DELIVERY / ГАРАЖ", 12, TEAL))
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var title: Label = _label("Гараж курьера", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var style_button: Button = _compact_button("Стиль", func() -> void: customization_requested.emit(), true)
	style_button.name = "OpenCustomizationGarage"
	header.add_child(style_button)
	header.add_child(_compact_button("Закрыть", _request_close_garage, true))
	_garage_profile = _label("", 14, MUTED)
	_garage_profile.add_theme_constant_override("line_spacing", 3)
	_garage_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_garage_profile)
	_garage_grid = GridContainer.new()
	_garage_grid.columns = 3
	_garage_grid.add_theme_constant_override("h_separation", 12)
	_garage_grid.add_theme_constant_override("v_separation", 12)
	_garage_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_garage_grid)
	for vehicle_type: String in VEHICLE_TYPES:
		_build_vehicle_card(vehicle_type)

	var bicycle_card: Dictionary = _garage_cards["bicycle"]
	_garage_name = bicycle_card["name"]
	_garage_description = bicycle_card["description"]
	_garage_specs = bicycle_card["specs"]
	_garage_status = bicycle_card["status"]
	_garage_buy = bicycle_card["buy"]
	_garage_spawn = bicycle_card["spawn"]
	_garage_hint = _label("", 14, MUTED)
	_garage_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_garage_hint)
	var walking: HBoxContainer = HBoxContainer.new()
	walking.add_theme_constant_override("separation", 10)
	content.add_child(walking)
	walking.add_child(_label("Пешком", 14, TEAL))
	var walking_note: Label = _label("Бесплатно · доступно всегда · F — выйти из транспорта", 13, MUTED)
	walking_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	walking_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	walking.add_child(walking_note)


func _build_vehicle_card(vehicle_type: String) -> void :
	var card: PanelContainer = _card(_garage_grid, PAPER)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content: VBoxContainer = _vbox(card, 7)
	var category: Label = _label("", 11, TEAL)
	content.add_child(category)
	var name_label: Label = _label(_vehicle_name(vehicle_type), 23)
	content.add_child(name_label)
	var illustration: VehicleIllustration = VehicleIllustration.new()
	illustration.vehicle_type = vehicle_type
	illustration.custom_minimum_size = Vector2(180.0, 118.0)
	illustration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(illustration)
	var specs: Label = _label("", 14)
	specs.add_theme_constant_override("line_spacing", 3)
	content.add_child(specs)
	var description: Label = _label(String(VEHICLE_DESCRIPTIONS.get(vehicle_type, "")), 13, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 43.0
	content.add_child(description)
	var status: Label = _label("", 14, TEAL)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 36.0
	content.add_child(status)
	var space: Control = _spacer(content, 2.0)
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var buy: Button = _compact_button("Купить", func() -> void : vehicle_buy_requested.emit(vehicle_type))
	content.add_child(buy)
	var spawn: Button = _compact_button("Поставить / выбрать", func() -> void : vehicle_spawn_requested.emit(vehicle_type))
	content.add_child(spawn)
	spawn.hide()
	_garage_cards[vehicle_type] = {"panel": card, "category": category, "name": name_label, "description": description, 
		"specs": specs, "status": status, "buy": buy, "spawn": spawn, "illustration": illustration}


func _request_close_garage() -> void :
	hide_garage()
	garage_closed.emit()


func show_garage(profile: Dictionary, definitions: Dictionary) -> void :
	_orders.hide()
	_map.hide()
	_pause.hide()
	update_garage(profile, definitions)
	_garage.show()
	_hide_current_notice()


func hide_garage() -> void :
	_garage.hide()
	_flush_pending_notice()


func update_garage(profile: Dictionary, definitions: Dictionary) -> void :


	if profile == _garage_last_profile and definitions == _garage_last_definitions:
		return
	_garage_last_profile = profile.duplicate(true)
	_garage_last_definitions = definitions.duplicate(true)
	var level: int = int(profile.get("level", 1))
	var money: int = int(profile.get("money", 0))
	_garage_profile.text = _profile_line(profile)
	for vehicle_type: String in VEHICLE_TYPES:
		var definition: Dictionary = definitions.get(vehicle_type, {})
		var card: Dictionary = _garage_cards[vehicle_type]
		var illustration: VehicleIllustration = card["illustration"]
		var appearance: Dictionary = CosmeticCatalog.normalize_appearance(profile.get("appearance", {}))
		var paint: Dictionary = CosmeticCatalog.paint_palette(String(appearance.get("vehicle_paint", "factory")))
		var paint_html: String = String(paint.get("paint", ""))
		illustration.paint_color = Color(paint_html) if Color.html_is_valid(paint_html) else Color.TRANSPARENT
		illustration.queue_redraw()
		var card_panel: PanelContainer = card["panel"]
		card_panel.visible = not definition.is_empty()
		if definition.is_empty():
			continue
		var price: int = maxi(0, int(definition.get("price", 0)))
		var required_level: int = maxi(1, int(definition.get("required_level", 1)))
		var speed: float = maxf(0.0, float(definition.get("max_speed", definition.get("speed", 0.0))))
		var owned: bool = _owns_vehicle(profile, vehicle_type)
		var selected: bool = owned and String(profile.get("selected_vehicle", "")) == vehicle_type
		var category: Label = card["category"]
		category.text = "УРОВЕНЬ %d" % required_level
		var name_label: Label = card["name"]
		name_label.text = _vehicle_name(vehicle_type, definition)
		var specs: Label = card["specs"]
		specs.text = "До %d км/ч\nСтоимость: %s ₽" % [roundi(speed * 3.6), _amount(price)]
		var buy: Button = card["buy"]
		var spawn: Button = card["spawn"]
		buy.visible = not owned
		buy.disabled = owned or level < required_level or money < price
		buy.text = "Нужен уровень %d" % required_level if level < required_level else "Купить · %s ₽" % _amount(price)
		spawn.visible = owned
		spawn.disabled = not owned or level < required_level
		spawn.text = "Поставить транспорт" if selected else "Поставить / выбрать"
		var status: Label = card["status"]
		status.add_theme_color_override("font_color", TEAL if owned or level >= required_level else GOLD.darkened(0.3))
		if level < required_level:
			status.text = "Откроется на уровне %d" % required_level
		elif owned:
			status.text = "Куплен · выбран" if selected else "Куплен · готов к поездке"
		elif money < price:
			status.text = "Не хватает %s ₽" % _amount(price - money)
		else:
			status.text = "Можно купить"
		var card_style: StyleBoxFlat = _style(Color("e0ece0") if selected else PAPER)
		if selected:
			card_style.border_color = TEAL
			card_style.set_border_width_all(2)
		card_panel.add_theme_stylebox_override("panel", card_style)
	_garage_hint.text = "Покупки сохраняются в профиле. Поставьте выбранный транспорт у гаража и нажмите F рядом с ним. Перед передачей посылки остановитесь и выйдите."
	if level == 1:
		_garage_hint.text = "Начните с пеших доставок. Первый велосипед откроется на уровне 2. Скутер — на уровне 4, автомобиль — на уровне 6."


func _owns_bicycle(profile: Dictionary) -> bool:
	return _owns_vehicle(profile, "bicycle")


func _owns_vehicle(profile: Dictionary, vehicle_type: String) -> bool:
	var owned: Variant = profile.get("owned_vehicles", [])
	return (owned is Array or owned is PackedStringArray) and owned.has(vehicle_type)


func _vehicle_name(vehicle_type: String, definition: Dictionary = {}) -> String:
	var display_name: String = String(definition.get("name", ""))

	if display_name.is_empty() or display_name.to_lower() == vehicle_type:
		return String(VEHICLE_NAMES.get(vehicle_type, "Транспорт"))
	return display_name


func _build_customization() -> void:
	var items: Array[Control] = _overlay(Vector2(940.0, 600.0))
	_customization = items[0]
	_customization.name = "CosmeticCustomization"
	_customization_panel = items[1]
	var content: VBoxContainer = _vbox(_customization_panel, 8)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var title: Label = _label("Профиль / стиль", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_customization_close = _compact_button("Назад", _request_close_customization, true)
	_customization_close.name = "CosmeticClose"
	header.add_child(_customization_close)
	_customization_summary = _label("", 14, MUTED)
	_customization_summary.name = "CosmeticProfileSummary"
	_customization_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_customization_summary)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.name = "CosmeticTabs"
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	for category: String in COSMETIC_CATEGORIES:
		var tab: Button = _compact_button(String(COSMETIC_NAMES[category]), func() -> void: _select_customization_category(category), true)
		tab.name = "CosmeticTab_" + category
		tab.custom_minimum_size.y = 38.0
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
		_cosmetic_tabs[category] = tab
	_customization_body = HBoxContainer.new()
	_customization_body.add_theme_constant_override("separation", 14)
	_customization_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_customization_body)
	var preview_panel: PanelContainer = _card(_customization_body, PAPER)
	preview_panel.custom_minimum_size.x = 230.0
	var preview_style: StyleBoxFlat = _style(PAPER, 14)
	preview_style.content_margin_left = 10.0
	preview_style.content_margin_right = 10.0
	preview_style.content_margin_top = 10.0
	preview_style.content_margin_bottom = 10.0
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	var preview_column: VBoxContainer = _vbox(preview_panel, 6)
	_cosmetic_preview_title = _label("", 17)
	_cosmetic_preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_column.add_child(_cosmetic_preview_title)
	_cosmetic_preview = CosmeticPreviewScript.new()
	_cosmetic_preview.custom_minimum_size = Vector2(200.0, 152.0)
	_cosmetic_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(_cosmetic_preview)
	_cosmetic_vehicle_preview = VehicleIllustration.new()
	_cosmetic_vehicle_preview.name = "CosmeticPaintPreview"
	_cosmetic_vehicle_preview.custom_minimum_size = Vector2(200.0, 152.0)
	_cosmetic_vehicle_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cosmetic_vehicle_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_column.add_child(_cosmetic_vehicle_preview)
	_cosmetic_vehicle_preview.hide()
	_cosmetic_rotation = HBoxContainer.new()
	_cosmetic_rotation.add_theme_constant_override("separation", 6)
	preview_column.add_child(_cosmetic_rotation)
	var rotate_left: Button = _compact_button("↶", func() -> void: _cosmetic_preview.rotate_model(-PI * 0.25), true)
	rotate_left.custom_minimum_size.y = 32.0
	rotate_left.tooltip_text = "Повернуть курьера влево"
	rotate_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cosmetic_rotation.add_child(rotate_left)
	var rotate_right: Button = _compact_button("↷", func() -> void: _cosmetic_preview.rotate_model(PI * 0.25), true)
	rotate_right.custom_minimum_size.y = 32.0
	rotate_right.tooltip_text = "Повернуть курьера вправо"
	rotate_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cosmetic_rotation.add_child(rotate_right)
	_cosmetic_vehicle_controls = HBoxContainer.new()
	_cosmetic_vehicle_controls.add_theme_constant_override("separation", 4)
	preview_column.add_child(_cosmetic_vehicle_controls)
	for vehicle_type: String in VEHICLE_TYPES:
		var short_name: String = {"bicycle": "Вело", "scooter": "Скутер", "car": "Авто"}[vehicle_type]
		var button: Button = _compact_button(short_name, func() -> void: _set_cosmetic_preview_vehicle(vehicle_type), true)
		button.custom_minimum_size.y = 32.0
		button.add_theme_font_size_override("font_size", 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cosmetic_vehicle_controls.add_child(button)
	_cosmetic_vehicle_controls.hide()
	_cosmetic_preview_hint = _label("", 12, MUTED)
	_cosmetic_preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cosmetic_preview_hint.custom_minimum_size = Vector2(195.0, 30.0)
	preview_column.add_child(_cosmetic_preview_hint)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "CosmeticItemsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_customization_body.add_child(scroll)
	_cosmetic_items = GridContainer.new()
	_cosmetic_items.columns = 2
	_cosmetic_items.add_theme_constant_override("h_separation", 10)
	_cosmetic_items.add_theme_constant_override("v_separation", 10)
	_cosmetic_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cosmetic_items)
	_customization_notice = _label("Примерьте любой стиль. Покупка или выбор — отдельной кнопкой.", 13, MUTED)
	_customization_notice.name = "CosmeticNotice"
	_customization_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_customization_notice.custom_minimum_size.y = 34.0
	content.add_child(_customization_notice)


func show_customization(profile: Dictionary, definitions: Dictionary) -> void:
	_hide_layers()
	_customization_candidate = CosmeticCatalog.normalize_appearance(profile.get("appearance", {}))
	_customization_profile = {}
	_customization_definitions = {}
	update_customization(profile, definitions)
	_customization.show()
	_resize_scroll_overlays()
	_hide_current_notice()
	set_customization_notice("Примерьте любой стиль. Покупка или выбор — отдельной кнопкой.")


func hide_customization() -> void:
	_customization.hide()
	_flush_pending_notice()


func _request_close_customization() -> void:
	hide_customization()
	customization_closed.emit()


func update_customization(profile: Dictionary, definitions: Dictionary) -> void:
	var previous: Dictionary = CosmeticCatalog.normalize_appearance(_customization_profile.get("appearance", {}))
	var appearance: Dictionary = CosmeticCatalog.normalize_appearance(profile.get("appearance", {}))
	for category: String in COSMETIC_CATEGORIES:
		# A confirmed purchase/selection replaces only that category's draft.
		if _customization_profile.is_empty() or previous.get(category) != appearance.get(category):
			_customization_candidate[category] = appearance[category]
	_customization_profile = profile.duplicate(true)
	_profile = profile.duplicate(true)
	var rebuild: bool = _customization_definitions != definitions or _cosmetic_cards.is_empty()
	_customization_definitions = definitions.duplicate(true)
	_customization_summary.text = "%s · уровень %d · %s ₽" % [String(profile.get("player_name", "Курьер")), int(profile.get("level", 1)), _amount(int(profile.get("money", 0)))]
	_menu_profile.text = _profile_line(profile)
	if rebuild:
		_rebuild_cosmetic_items()
	_update_cosmetic_cards()
	_update_cosmetic_preview()


func set_customization_notice(message: String, error: bool = false) -> void:
	_customization_notice.text = message
	_customization_notice.add_theme_color_override("font_color", Color("a64f35") if error else TEAL)


func _select_customization_category(category: String) -> void:
	if not category in COSMETIC_CATEGORIES:
		return
	_customization_category = category
	_rebuild_cosmetic_items()
	_cosmetic_preview.show_back(category == "backpack")
	_update_cosmetic_cards()
	_update_cosmetic_preview()


func _rebuild_cosmetic_items() -> void:
	for child: Node in _cosmetic_items.get_children():
		_cosmetic_items.remove_child(child)
		child.queue_free()
	_cosmetic_cards.clear()
	var items: Array = _customization_definitions.get(_customization_category, [])
	for value: Variant in items:
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		var id: String = String(item.get("id", ""))
		var category: String = _customization_category
		if id.is_empty():
			continue
		var panel: PanelContainer = _card(_cosmetic_items, PAPER)
		panel.name = "CosmeticItem_" + category + "_" + id
		panel.set_meta("category", category)
		panel.set_meta("item_id", id)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column: VBoxContainer = _vbox(panel, 5)
		var name_button: Button = _compact_button(String(item.get("name", id)), func() -> void: _preview_cosmetic(category, id), true)
		name_button.name = "CosmeticPreview_" + id
		name_button.custom_minimum_size.y = 32.0
		name_button.add_theme_font_size_override("font_size", 15)
		name_button.tooltip_text = "Примерить: " + String(item.get("name", id))
		column.add_child(name_button)
		var swatch: CosmeticSwatch = CosmeticSwatch.new()
		swatch.custom_minimum_size.y = 24.0
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var palette: Dictionary = item.get("palette", {})
		for color_value: Variant in palette.values():
			if color_value is String and Color.html_is_valid(color_value):
				var color: Color = Color(color_value)
				if not swatch.colors.has(color) and swatch.colors.size() < 3:
					swatch.colors.append(color)
		if swatch.colors.is_empty():
			swatch.colors = [TEAL, Color("d97559"), Color("658ed1")]
		column.add_child(swatch)
		var status: Label = _label("", 12, MUTED)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.custom_minimum_size.y = 17.0
		column.add_child(status)
		var action: Button = _compact_button("", func() -> void: _request_cosmetic_action(category, id))
		action.name = "CosmeticAction_" + id
		action.custom_minimum_size.y = 36.0
		column.add_child(action)
		_cosmetic_cards[id] = {"panel": panel, "status": status, "action": action, "preview": name_button, "item": item}


func _update_cosmetic_cards() -> void:
	var appearance: Dictionary = CosmeticCatalog.normalize_appearance(_customization_profile.get("appearance", {}))
	var money: int = int(_customization_profile.get("money", 0))
	for category: String in COSMETIC_CATEGORIES:
		var tab: Button = _cosmetic_tabs[category]
		var active: bool = category == _customization_category
		tab.add_theme_stylebox_override("normal", _style(TEAL if active else PAPER, 10))
		tab.add_theme_color_override("font_color", CREAM if active else INK)
	for id: String in _cosmetic_cards:
		var card: Dictionary = _cosmetic_cards[id]
		var item: Dictionary = card["item"]
		var price: int = maxi(0, int(item.get("price", 0)))
		var owned: bool = CosmeticCatalog.owns(_customization_profile, _customization_category, id)
		var selected: bool = String(appearance.get(_customization_category, "")) == id
		var candidate: bool = String(_customization_candidate.get(_customization_category, "")) == id
		var status: Label = card["status"]
		status.text = "Выбрано · бесплатно" if selected and price == 0 else ("Выбрано · куплено" if selected else ("Бесплатно · доступно" if price == 0 else ("Куплено · доступно" if owned else "Стоимость: %s ₽" % _amount(price))))
		status.add_theme_color_override("font_color", TEAL if selected else MUTED)
		var action: Button = card["action"]
		action.text = "Выбрано" if selected else ("Выбрать" if owned else "Купить · %s ₽" % _amount(price))
		action.disabled = selected or (not owned and money < price)
		action.tooltip_text = "Не хватает %s ₽" % _amount(price - money) if not owned and money < price else ""
		var panel: PanelContainer = card["panel"]
		panel.set_meta("selected", selected)
		panel.set_meta("owned", owned)
		panel.set_meta("candidate", candidate)
		var style: StyleBoxFlat = _style(Color("e0ece0") if selected else PAPER, 12)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 9.0
		style.content_margin_bottom = 9.0
		if selected or candidate:
			style.border_color = TEAL if selected else GOLD
			style.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", style)


func _preview_cosmetic(category: String, id: String) -> void:
	if category != _customization_category or CosmeticCatalog.get_item(category, id).is_empty():
		return
	_customization_candidate[category] = id
	_update_cosmetic_cards()
	_update_cosmetic_preview()


func _request_cosmetic_action(category: String, id: String) -> void:
	# Only identifiers leave this page; the Host/offline catalog resolves the cost.
	if CosmeticCatalog.owns(_customization_profile, category, id):
		cosmetic_select_requested.emit(category, id)
	else:
		cosmetic_buy_requested.emit(category, id)


func _update_cosmetic_preview() -> void:
	var paint_category: bool = _customization_category == "vehicle_paint"
	_cosmetic_preview.visible = not paint_category
	_cosmetic_rotation.visible = not paint_category
	_cosmetic_vehicle_preview.visible = paint_category
	_cosmetic_vehicle_controls.visible = paint_category
	_cosmetic_preview.apply_appearance(_customization_candidate)
	var item: Dictionary = CosmeticCatalog.get_item(_customization_category, String(_customization_candidate.get(_customization_category, "")))
	_cosmetic_preview_title.text = String(item.get("name", "Стиль курьера"))
	var appearance: Dictionary = CosmeticCatalog.normalize_appearance(_customization_profile.get("appearance", {}))
	var draft: bool = _customization_candidate != appearance
	_cosmetic_preview_hint.text = "Примерка · ещё не выбрано" if draft else "Ваш выбранный стиль"
	if paint_category:
		_cosmetic_preview_hint.text = "Один цвет для всего транспорта. Транспорт покупается отдельно."
	var paint: Dictionary = CosmeticCatalog.paint_palette(String(_customization_candidate.get("vehicle_paint", "factory")))
	var html: String = String(paint.get("paint", ""))
	_cosmetic_vehicle_preview.paint_color = Color(html) if Color.html_is_valid(html) else Color.TRANSPARENT
	_cosmetic_vehicle_preview.vehicle_type = _cosmetic_preview_vehicle
	_cosmetic_vehicle_preview.queue_redraw()


func _set_cosmetic_preview_vehicle(vehicle_type: String) -> void:
	if vehicle_type in VEHICLE_TYPES:
		_cosmetic_preview_vehicle = vehicle_type
		_update_cosmetic_preview()


func _build_settings() -> void :
	var items: Array[Control] = _scroll_overlay(Vector2(660, 610))
	_settings = items[0]
	var content: VBoxContainer = _vbox(items[1], 12)
	content.add_child(_label("DELIVERY / НАСТРОЙКИ", 12, TEAL))
	content.add_child(_label("Играйте по-своему.", 29))
	var hint: Label = _label("Выберите удобные настройки и нажмите «Применить».", 14, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	_settings_preview = _card(content, PAPER)
	var preview_content: VBoxContainer = _vbox(_settings_preview, 8)
	preview_content.add_child(_label("Сохранить настройки экрана?", 19))
	_settings_countdown = _label("", 14, MUTED)
	_settings_countdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_content.add_child(_settings_countdown)
	var preview_actions: HBoxContainer = HBoxContainer.new()
	preview_content.add_child(preview_actions)
	_settings_confirm = _compact_button("Оставить", func() -> void : settings_confirm_requested.emit())
	_settings_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_actions.add_child(_settings_confirm)
	_settings_revert = _compact_button("Вернуть", func() -> void : settings_revert_requested.emit(), true)
	_settings_revert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_actions.add_child(_settings_revert)
	_settings_preview.hide()
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	var tab_names: Array[String] = ["Графика", "Звук", "Управление"]
	for index: int in tab_names.size():
		var tab: Button = _compact_button(tab_names[index], _select_settings_tab.bind(index), true)
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
		_settings_tabs.append(tab)
	var graphics: VBoxContainer = _vbox(_card(content, PAPER), 10)
	_settings_pages.append(graphics.get_parent())
	var display_choices: HBoxContainer = HBoxContainer.new()
	display_choices.add_theme_constant_override("separation", 14)
	graphics.add_child(display_choices)
	var resolution_column: VBoxContainer = _vbox(display_choices, 6)
	resolution_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_option(resolution_column, "Разрешение окна", "resolution", [])
	var quality_column: VBoxContainer = _vbox(display_choices, 6)
	quality_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_option(quality_column, "Качество графики", "quality", ["Низкое", "Среднее", "Высокое"])
	var display_hint: Label = _label("В полноэкранном режиме используется размер экрана.", 13, MUTED)
	display_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graphics.add_child(display_hint)
	var display_toggles: HBoxContainer = HBoxContainer.new()
	display_toggles.add_theme_constant_override("separation", 14)
	graphics.add_child(display_toggles)
	var fullscreen: CheckBox = _settings_checkbox(display_toggles, "Полноэкранный режим", "fullscreen")
	fullscreen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullscreen.tooltip_text = "Использовать весь экран для игры"
	var vsync: CheckBox = _settings_checkbox(display_toggles, "VSync", "vsync")
	vsync.tooltip_text = "Вертикальная синхронизация"
	var audio: VBoxContainer = _vbox(_card(content, PAPER), 12)
	_settings_pages.append(audio.get_parent())
	_settings_slider(audio, "Общая громкость", "master_volume", 0.0, 1.0, 0.01)
	_settings_slider(audio, "Музыка", "music_volume", 0.0, 1.0, 0.01)
	_settings_slider(audio, "Звуковые эффекты", "sfx_volume", 0.0, 1.0, 0.01)
	var controls: VBoxContainer = _vbox(_card(content, PAPER), 12)
	_settings_pages.append(controls.get_parent())
	_settings_slider(controls, "Чувствительность мыши", "mouse_sensitivity", 0.2, 3.0, 0.05)
	var control_hint: Label = _label("WASD — движение · Shift — бег · Space — прыжок\nМышь — камера · E — взаимодействие · F — транспорт\nM — карта · Tab — заказы · Esc — пауза", 14, MUTED)
	control_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(control_hint)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	_settings_apply = _compact_button("Применить", _request_settings_apply)
	_settings_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_settings_apply)
	_settings_reset = _compact_button("По умолчанию", _reset_settings_draft, true)
	actions.add_child(_settings_reset)
	_settings_close = _compact_button("Назад", func() -> void : settings_closed.emit(), true)
	actions.add_child(_settings_close)
	_settings_notice = _label("", 13, MUTED)
	_settings_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_settings_notice)
	_select_settings_tab(0)


func _settings_option(parent: Node, caption: String, key: String, choices: Array) -> OptionButton:
	parent.add_child(_label(caption, 14, MUTED))
	var control: OptionButton = OptionButton.new()
	control.item_selected.connect( func(_index: int) -> void : ui_click_requested.emit())
	control.custom_minimum_size.y = 42.0
	control.add_theme_color_override("font_color", INK)
	control.add_theme_color_override("font_hover_color", INK)
	control.add_theme_color_override("font_pressed_color", INK)
	control.add_theme_color_override("font_disabled_color", MUTED)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		control.add_theme_stylebox_override(state, _style(CREAM, 8))
	control.add_theme_stylebox_override("focus", _focus_style())
	for choice: String in choices:
		control.add_item(choice)
	parent.add_child(control)
	_settings_controls[key] = control
	return control


func _settings_checkbox(parent: Node, caption: String, key: String) -> CheckBox:
	var control: CheckBox = CheckBox.new()
	control.pressed.connect( func() -> void : ui_click_requested.emit())
	control.text = caption
	control.custom_minimum_size.y = 38.0
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		control.add_theme_color_override(state, INK)
	control.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, 8))
	control.add_theme_stylebox_override("pressed", _style(Color.TRANSPARENT, 8))
	control.add_theme_stylebox_override("hover", _style(CREAM, 8))
	parent.add_child(control)
	_settings_controls[key] = control
	return control


func _settings_slider(parent: Node, caption: String, key: String, minimum: float, maximum: float, step: float) -> void :
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var caption_label: Label = _label(caption, 16)
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption_label)
	var value_label: Label = _label("", 16, TEAL)
	value_label.custom_minimum_size.x = 62.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_settings_labels[key] = value_label
	var slider: HSlider = HSlider.new()
	slider.drag_started.connect( func() -> void : ui_click_requested.emit())
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size.y = 28.0
	var track: StyleBoxFlat = _style(CREAM, 4)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	slider.add_theme_stylebox_override("slider", track)
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = TEAL
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.value_changed.connect(_update_settings_slider_label.bind(key))
	parent.add_child(slider)
	_settings_controls[key] = slider


func _update_settings_slider_label(value: float, key: String) -> void :
	var label: Label = _settings_labels[key]
	label.text = "%.2f×" % value if key == "mouse_sensitivity" else "%d%%" % roundi(value * 100.0)


func _select_settings_tab(index: int) -> void :
	for page_index: int in _settings_pages.size():
		_settings_pages[page_index].visible = page_index == index
	for tab_index: int in _settings_tabs.size():
		_settings_tabs[tab_index].set_pressed_no_signal(tab_index == index)


func show_settings(values: Dictionary, resolutions: Array, defaults: Dictionary = {}) -> void :
	_hide_layers()
	_hide_current_notice()
	_settings_defaults = defaults.duplicate(true) if not defaults.is_empty() else {
		"resolution_width": 1280, "resolution_height": 720, "fullscreen": false, 
		"quality": "medium", "vsync": true, "master_volume": 1.0, 
		"music_volume": 0.35, "sfx_volume": 0.8, "mouse_sensitivity": 1.0, 
	}
	_settings_resolution_values.clear()
	for resolution: Variant in resolutions:
		var dimensions: Vector2i = Vector2i.ZERO
		if resolution is Vector2i or resolution is Vector2:
			dimensions = Vector2i(resolution)
		elif resolution is Dictionary:
			dimensions = Vector2i(int(resolution.get("width", 0)), int(resolution.get("height", 0)))
		if dimensions.x > 0 and dimensions.y > 0 and not dimensions in _settings_resolution_values:
			_settings_resolution_values.append(dimensions)
	var current: Vector2i = Vector2i(int(values.get("resolution_width", 1280)), int(values.get("resolution_height", 720)))
	if not current in _settings_resolution_values:
		_settings_resolution_values.append(current)
	var default_resolution: Vector2i = Vector2i(int(_settings_defaults.get("resolution_width", 1280)), int(_settings_defaults.get("resolution_height", 720)))
	if not default_resolution in _settings_resolution_values:
		_settings_resolution_values.append(default_resolution)
	var resolution_control: OptionButton = _settings_controls["resolution"]
	resolution_control.clear()
	for dimensions: Vector2i in _settings_resolution_values:
		resolution_control.add_item("%d × %d" % [dimensions.x, dimensions.y])
	_set_settings_draft(values)
	set_settings_notice("")
	_select_settings_tab(0)
	update_settings_preview(false, 0.0)
	_settings.show()
	_settings_close.grab_focus()


func _set_settings_draft(values: Dictionary) -> void :
	var current: Vector2i = Vector2i(int(values.get("resolution_width", 1280)), int(values.get("resolution_height", 720)))
	var resolution_control: OptionButton = _settings_controls["resolution"]
	resolution_control.select(maxi(0, _settings_resolution_values.find(current)))
	for key: String in ["fullscreen", "vsync"]:
		var checkbox: CheckBox = _settings_controls[key]
		checkbox.set_pressed_no_signal(bool(values.get(key, _settings_defaults.get(key, false))))
	var quality: OptionButton = _settings_controls["quality"]
	quality.select(maxi(0, ["low", "medium", "high"].find(str(values.get("quality", "medium")))))
	for key: String in ["master_volume", "music_volume", "sfx_volume", "mouse_sensitivity"]:
		var slider: HSlider = _settings_controls[key]
		slider.value = float(values.get(key, _settings_defaults.get(key, 1.0)))
		_update_settings_slider_label(slider.value, key)


func get_settings_draft() -> Dictionary:
	var resolution_control: OptionButton = _settings_controls["resolution"]
	var dimensions: Vector2i = _settings_resolution_values[maxi(0, resolution_control.selected)]
	var fullscreen: CheckBox = _settings_controls["fullscreen"]
	var vsync: CheckBox = _settings_controls["vsync"]
	var quality: OptionButton = _settings_controls["quality"]
	var values: Dictionary = {
		"resolution_width": dimensions.x, "resolution_height": dimensions.y, 
		"fullscreen": fullscreen.button_pressed, "vsync": vsync.button_pressed, 
		"quality": ["low", "medium", "high"][maxi(0, quality.selected)], 
	}
	for key: String in ["master_volume", "music_volume", "sfx_volume", "mouse_sensitivity"]:
		values[key] = (_settings_controls[key] as HSlider).value
	return values


func _request_settings_apply() -> void :
	if not _settings_pending:
		settings_apply_requested.emit(get_settings_draft())


func _reset_settings_draft() -> void :
	if not _settings_pending:
		_set_settings_draft(_settings_defaults)


func hide_settings() -> void :
	_settings.hide()
	update_settings_preview(false, 0.0)


func set_settings_notice(message: String) -> void :
	_settings_notice.text = message
	_settings_notice.visible = not message.is_empty()


func update_settings_preview(pending: bool, seconds: float) -> void :
	var changed: bool = _settings_pending != pending
	_settings_pending = pending
	_settings_preview.visible = pending
	_settings_countdown.text = "Прежние настройки вернутся через %d с." % maxi(0, ceili(seconds)) if pending else ""
	_settings_apply.disabled = pending
	_settings_reset.disabled = pending
	for control: Control in _settings_controls.values():
		if control is BaseButton:
			control.disabled = pending
		elif control is Slider:
			control.editable = not pending
	if changed and pending:
		_select_settings_tab(0)
		_settings_confirm.grab_focus()
	elif changed and _settings.visible:
		_settings_apply.grab_focus()


func _build_toast() -> void :
	_toast_panel = _card(_root, INK)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_left = -275.0
	_toast_panel.offset_right = 275.0
	_toast_panel.offset_top = 105.0
	_toast_panel.offset_bottom = 159.0
	_toast = _label("", 16, CREAM)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast)
	_toast_panel.hide()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 4.0
	_toast_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_toast_timer.timeout.connect(_on_toast_timeout)
	add_child(_toast_timer)


func _hide_layers() -> void :
	for layer_control: Control in [_menu, _game, _pause, _results, _orders, _map, _lan_menu, _lobby, _garage, _settings, _customization]:
		layer_control.hide()


func _profile_line(profile: Dictionary) -> String:
	var summary: String = "Уровень %d   ·   %d XP   ·   %s ₽\nВсего доставок: %d" % [int(profile.get("level", 1)), int(profile.get("xp", 0)), _amount(int(profile.get("money", 0))), int(profile.get("total_deliveries", 0))]
	var owned_names: Array[String] = []
	for vehicle_type: String in VEHICLE_TYPES:
		if _owns_vehicle(profile, vehicle_type):
			owned_names.append(_vehicle_name(vehicle_type).to_lower())
	if not owned_names.is_empty():
		summary += "\nКуплено: " + ", ".join(owned_names)
		var selected: String = String(profile.get("selected_vehicle", ""))
		if _owns_vehicle(profile, selected):
			summary += "\nВыбран: " + _vehicle_name(selected).to_lower()
	var appearance: Dictionary = CosmeticCatalog.normalize_appearance(profile.get("appearance", {}))
	var outfit: Dictionary = CosmeticCatalog.get_item("outfit", String(appearance.get("outfit", "classic_blue")))
	summary += "\nСтиль: " + String(outfit.get("name", "Классический синий"))
	return summary


func _amount(value: int) -> String:
	var digits: String = str(value)
	var formatted: String = ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += " "
		formatted += digits[index]
	return formatted


func show_menu(profile: Dictionary) -> void :
	_profile = profile.duplicate(true)
	_hide_layers()
	_menu_profile.text = _profile_line(profile)
	_menu.show()
	_hide_current_notice()


func show_lan_menu(profile: Dictionary, notice: String = "") -> void :
	_profile = profile.duplicate(true)
	_hide_layers()
	_lan_name.text = String(profile.get("name", profile.get("player_name", "Курьер")))
	_lan_host_button.disabled = false
	_lan_join_button.disabled = false
	_lan_name.editable = true
	_lan_room.editable = true
	_lan_address.editable = true
	_lan_max_players.disabled = false
	_lan_shift.disabled = false
	_lan_mode.disabled = false
	_lan_back_button.text = "Главное меню"
	_lan_status.text = notice
	_lan_status.visible = not notice.is_empty()
	_lan_menu.show()
	_hide_current_notice()


func set_connecting(message: String) -> void :
	_hide_layers()
	_lan_host_button.disabled = true
	_lan_join_button.disabled = true
	_lan_name.editable = false
	_lan_room.editable = false
	_lan_address.editable = false
	_lan_max_players.disabled = true
	_lan_shift.disabled = true
	_lan_mode.disabled = true
	_lan_status.text = message
	_lan_status.show()
	_lan_back_button.text = "Отменить подключение"
	_lan_menu.show()
	_hide_current_notice()


func show_lobby(data: Dictionary, is_host: bool) -> void :
	_hide_layers()
	var config: Dictionary = data.get("lobby_config", data.get("config", data))
	_lobby_title.text = String(config.get("room_name", data.get("room_name", "Курьерская смена")))
	_lobby_address.text = "Host IP: %s · UDP 7777" % String(config.get("host_ip", data.get("host_ip", "—")))
	var players: Array = data.get("players", [])
	var shift_seconds: int = int(config.get("shift_seconds", data.get("shift_seconds", 900)))
	var duration: String = "без ограничения" if shift_seconds < 0 else "%d мин" % (shift_seconds / 60)
	var team_mode: bool = String(config.get("shift_mode", data.get("shift_mode", "competitive"))) == "team"
	_lobby_details.text = "%d / %d игроков · смена %s · %s" % [players.size(), int(config.get("max_players", data.get("max_players", 4))), duration, "Командная смена" if team_mode else "Соревнование"]
	if team_mode:
		_lobby_details.text += "\nОбщий план — %d доставки на каждого участника старта. Личный бонус: завершите хотя бы одну доставку." % int(config.get("team_goal_per_player", 4))
	for child: Node in _lobby_players.get_children():
		_lobby_players.remove_child(child)
		child.queue_free()
	var local_id: int = int(data.get("local_id", 1 if is_host else 0))
	var own_ready: bool = false
	var own_member_found: bool = false
	for value: Variant in players:
		if not value is Dictionary:
			continue
		var member: Dictionary = value
		var member_profile: Dictionary = member.get("profile", {})
		var peer_id: int = int(member.get("id", 0))
		var member_name: String = String(member.get("name", member_profile.get("name", "Курьер")))
		if peer_id == local_id:
			member_name += " · вы"
			own_ready = bool(member.get("ready", false))
			own_member_found = true
		elif peer_id == 1:
			member_name += " · Host"
		var career: String = "%d · %s" % [int(member.get("level", member_profile.get("level", 1))), String(member.get("rank", member_profile.get("rank", "Rookie Courier")))]
		var selected: String = String(member_profile.get("selected_vehicle", "walking"))
		var appearance: Dictionary = CosmeticCatalog.normalize_appearance(member_profile.get("appearance", member.get("appearance", {})))
		var outfit: Dictionary = CosmeticCatalog.get_item("outfit", String(appearance.get("outfit", "classic_blue")))
		var backpack: Dictionary = CosmeticCatalog.get_item("backpack", String(appearance.get("backpack", "classic")))
		var character: String = String(outfit.get("name", "Курьер")) + "\n" + String(backpack.get("name", "Рюкзак")) + " · " + (_vehicle_name(selected).to_lower() if _owns_vehicle(member_profile, selected) else "пешком")
		_add_roster_row(_lobby_players, member_name, "Готов" if bool(member.get("ready", false)) else "Ожидает", career, character)
	_lobby_ready.set_pressed_no_signal(own_ready)
	_lobby_ready.disabled = not own_member_found
	_lobby_start.visible = is_host
	_lobby_start.disabled = not bool(data.get("can_start", false))
	_lobby_wait.text = "Все курьеры готовы — можно начинать." if is_host and bool(data.get("can_start", false)) else ("Отметьте готовность. Для старта нужны все курьеры." if is_host else "Ожидаем Host: он начнёт смену, когда все будут готовы.")
	_lobby.show()
	_hide_current_notice()


func set_network_mode(enabled: bool, is_host: bool) -> void :
	_network_enabled = enabled
	_network_is_host = is_host
	_pause_restart.text = "В лобби" if enabled and is_host else ("Ожидаем Host" if enabled else "Начать новую смену")
	_pause_restart.disabled = enabled and not is_host
	_pause_leave.visible = enabled
	_pause_hint.text = "В LAN время смены продолжается. Карьерный прогресс сохранён." if enabled else "Карьерный прогресс уже сохранён."
	_results_restart.text = "В лобби" if enabled and is_host else ("Ожидаем Host" if enabled else "Следующая смена  →")
	_results_restart.disabled = enabled and not is_host
	_results_leave.visible = enabled
	_results_wait.text = "Host вернёт всех в лобби для следующей смены." if enabled and not is_host else ""
	_results_wait.visible = enabled and not is_host
	if not enabled:
		_team_panel.hide()
		_handoff_panel.hide()
		_handoff_signature = ""
		_handoff_timers.clear()
		_mini_map.update_other_players([])
		_full_map.update_other_players([])


func show_game() -> void :
	_hide_layers()
	_game.show()
	_flush_pending_notice()


func show_pause(profile: Dictionary) -> void :
	_profile = profile.duplicate(true)
	_orders.hide()
	_map.hide()
	_garage.hide()
	_settings.hide()
	_customization.hide()
	_pause_profile.text = _profile_line(profile)
	_pause.show()
	_hide_current_notice()


func show_results(stats: Dictionary, leaderboard: Array = []) -> void :
	_hide_layers()
	var deliveries: int = int(stats.get("deliveries", 0))
	_results_title.text = "Хорошая работа, курьер!" if deliveries > 0 else "Первый шаг сделан."
	_results_summary.text = "Смена завершена · время %s" % _time(float(stats.get("time_used", 0.0)))
	_results_numbers.text = "Доставки     %d\nЗаработано   %s ₽\nОпыт             +%d XP\nЛучшая доставка   %s ₽" % [deliveries, _amount(int(stats.get("money", 0))), int(stats.get("xp", 0)), _amount(int(stats.get("best_delivery", 0)))]
	_update_team_results(stats)
	var entries: Array = leaderboard if not leaderboard.is_empty() else stats.get("leaderboard", [])
	for child: Node in _leaderboard_rows.get_children():
		_leaderboard_rows.remove_child(child)
		child.queue_free()
	for index: int in mini(4, entries.size()):
		if entries[index] is Dictionary:
			_add_leaderboard_row(_leaderboard_rows, entries[index])
	_leaderboard_panel.visible = not entries.is_empty()
	_results.show()
	_hide_current_notice()


func set_orders(orders: Array[Dictionary]) -> void :
	_accept_buttons.clear()
	_event_order_badges.clear()
	for child: Node in _orders_list.get_children():
		_orders_list.remove_child(child)
		child.queue_free()
	if orders.is_empty():
		_orders_list.add_child(_label("Сейчас доступных заказов нет.", 17, MUTED))
		return
	# Put the live district offers first for Tab; keep the shared authority list unchanged.
	var displayed: Array[Dictionary] = []
	for order: Dictionary in orders:
		if not String(order.get("event_id", "")).is_empty() and bool(order.get("event_bonus_available", false)):
			displayed.append(order)
	for order: Dictionary in orders:
		if String(order.get("event_id", "")).is_empty() or not bool(order.get("event_bonus_available", false)):
			displayed.append(order)
	for order: Dictionary in displayed:
		var event_id: String = String(order.get("event_id", ""))
		var card: PanelContainer = _card(_orders_list, EVENT_PAPER if not event_id.is_empty() else PAPER)
		card.set_meta("district_event_id", event_id)
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		card.add_child(row)
		var details: VBoxContainer = _vbox(row, 3)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_title: Label = _label(String(order.get("title", "Доставка")), 17)
		card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_title.custom_minimum_size.x = 180.0
		details.add_child(card_title)
		if not event_id.is_empty():
			var badge: Label = _label("", 12, EVENT_ORANGE)
			badge.name = "DistrictEventBadge"
			badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			badge.set_meta("district_event_badge", true)
			badge.set_meta("event_id", event_id)
			details.add_child(badge)
			_event_order_badges.append({"label": badge, "id": event_id, "name": String(order.get("event_name", "Обеденный час")), "remaining": float(order.get("event_remaining", 0.0)), "available": bool(order.get("event_bonus_available", false)), "bonus": maxi(0, int(order.get("event_bonus_money", order.get("event_bonus", 0))))})
		var route: Label = _label("%s → %s" % [String(order.get("pickup_name", "")), String(order.get("delivery_name", ""))], 13, MUTED)
		route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(route)
		var district_route: String = String(order.get("district_route", ""))
		if not district_route.is_empty():
			var district_hint: Label = _label(district_route, 12, MUTED)
			district_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			details.add_child(district_hint)
		if String(order.get("route_band", "")) == "regional":
			details.add_child(_label("Между районами · удобно на транспорте", 12, TEAL))
		details.add_child(_label("%s · %d м · %d XP" % [String(order.get("type_name", "Обычная")), int(order.get("distance", 0)), int(order.get("xp", 0))], 12, TEAL))
		var action: VBoxContainer = _vbox(row, 4)
		var fragile: bool = String(order.get("type", "")) == "fragile"
		var base_reward: int = maxi(0, int(order.get("reward", 0)))
		var quality_bonus: int = maxi(0, int(order.get("quality_bonus", 0))) if fragile else 0
		var reward_text: String = "до %s ₽" % _amount(base_reward + quality_bonus) if fragile else "%s ₽" % _amount(base_reward)
		var reward: Label = _label(reward_text, 20)
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		action.add_child(reward)
		if fragile:
			var bonus_hint: Label = _label("Качество: до +%s ₽" % _amount(quality_bonus), 12, MUTED)
			bonus_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			action.add_child(bonus_hint)
		var locked: bool = bool(order.get("locked", false))
		var id: int = int(order.get("id", 0))
		var required_level: int = maxi(1, int(order.get("required_level", 1)))
		var button: Button = _button("Уровень %d" % required_level if locked else "Принять", func() -> void : order_requested.emit(id))
		button.custom_minimum_size = Vector2(125, 40)
		button.set_meta("level_locked", locked)
		button.disabled = locked or _has_active_order
		_accept_buttons.append(button)
		action.add_child(button)
	_update_event_order_badges(_last_data.get("district_event", {}))


func show_orders(visible: bool) -> void :
	_orders.visible = visible
	if visible:
		_map.hide()
		_pause.hide()
		_garage.hide()
		_hide_current_notice()
	else:
		_flush_pending_notice()


func show_map(visible: bool, player_position: Vector3 = Vector3.ZERO, target_position: Vector3 = Vector3.ZERO) -> void :
	_map.visible = visible
	_full_map.update_positions(player_position, target_position, bool(_last_data.get("has_target", false)))
	if visible:
		_orders.hide()
		_pause.hide()
		_garage.hide()
		_hide_current_notice()
	else:
		_flush_pending_notice()


func _close_modal() -> void :
	_orders.hide()
	_map.hide()
	_garage.hide()
	modal_closed.emit()
	_flush_pending_notice()


func _time(seconds: float) -> String:
	if seconds < 0.0:
		return "∞"
	var remaining: int = maxi(0, ceili(seconds))
	return "%02d:%02d" % [floori(float(remaining) / 60.0), remaining % 60]


func update_hud(data: Dictionary, other_players: Array = []) -> void :
	_last_data = data.duplicate()
	_money.text = "%s ₽" % _amount(int(data.get("money", 0)))
	_xp_level.text = "Уровень %d · %d XP" % [int(data.get("level", 1)), int(data.get("xp", 0))]
	_rank.text = String(data.get("rank", "Rookie Courier"))
	_timer.text = _time(float(data.get("shift_remaining", 0.0)))
	var remaining: float = float(data.get("shift_remaining", 900.0))
	_timer.add_theme_color_override("font_color", GOLD.darkened(0.3) if remaining >= 0.0 and remaining < 60.0 else INK)
	var title: String = String(data.get("order_title", ""))
	var target: String = String(data.get("target_name", ""))
	_has_active_order = bool(data.get("has_target", not target.is_empty()))
	_order_title.text = title if not title.is_empty() else "Готовы к следующей доставке?"
	_order_status.text = String(data.get("order_status", "")) if not title.is_empty() else "Tab — выберите заказ"
	var nav: Dictionary = data.get("navigation", {})
	var route_status: String = String(nav.get("status", "idle"))
	_target.text = ("%s · %d м по маршруту" % [target, ceili(float(data.get("distance", 0.0)))]) if not target.is_empty() and route_status == "ok" else target
	_navigation_hint.text = String(nav.get("hint", ""))
	_navigation_hint.visible = _has_active_order
	_map_route_label.text = "%s · %s" % [_target.text, _navigation_hint.text] if _has_active_order else "Tab — выберите заказ, чтобы увидеть маршрут"

	_update_order_quality(data)
	_update_team_hud(data)
	_update_district_event(data)
	_deliveries.text = "Доставлено: %d" % int(data.get("deliveries", 0))
	var active_vehicle: String = String(data.get("active_vehicle", "walking"))
	var riding: bool = active_vehicle in VEHICLE_TYPES
	_vehicle.text = "%s · %d км/ч" % [_vehicle_name(active_vehicle), roundi(absf(float(data.get("vehicle_speed", 0.0))) * 3.6)] if riding else "Пешком"
	if active_vehicle == "car":
		_keys.text = "W/S газ / тормоз · A/D поворот · Space ручной тормоз · F выйти · Tab заказы · M карта · Esc пауза"
	elif riding:
		_keys.text = "W/S газ / тормоз · A/D поворот · F выйти · Tab заказы · M карта · Esc пауза"
	else:
		_keys.text = "WASD движение · Shift бег · Space прыжок · E действие · F транспорт · Tab заказы · M карта · Esc пауза"
	var interaction: String = String(data.get("interaction", ""))
	_interaction.text = interaction
	_interaction_panel.visible = not interaction.is_empty()
	_orders_hint.text = "Активный заказ уже принят. Завершите доставку или откажитесь." if _has_active_order else "Выберите маршрут и отправляйтесь к точке получения."
	_abandon_button.visible = _has_active_order
	for button: Button in _accept_buttons:
		button.disabled = _has_active_order or bool(button.get_meta("level_locked", false))
	var player_position: Vector3 = data.get("player_position", Vector3.ZERO)
	var target_position: Vector3 = data.get("target_position", Vector3.ZERO)
	_mini_map.update_positions(player_position, target_position, _has_active_order)
	_full_map.update_positions(player_position, target_position, _has_active_order)
	_mini_map.update_navigation(nav, float(data.get("player_yaw", 0.0)), String(data.get("order_state", "")) == "PickedUp")
	_full_map.update_navigation(nav, float(data.get("player_yaw", 0.0)), String(data.get("order_state", "")) == "PickedUp")
	var peers: Array = other_players if not other_players.is_empty() else data.get("other_players", [])
	var visible_peers: Array = []
	var local_id: int = int(data.get("local_id", -1))
	for value: Variant in peers:
		if value is Dictionary and int(value.get("id", -2)) != local_id:
			visible_peers.append(value)
	_mini_map.update_other_players(visible_peers)
	_full_map.update_other_players(visible_peers)


func notify(message: String) -> void :
	if _has_blocking_overlay():
		_queue_notice(message)
		return
	_show_notice(message)


func _show_notice(message: String) -> void :
	_toast.text = message
	_toast_panel.show()
	_toast_timer.start()


func _queue_notice(message: String) -> void :
	if _pending_notices.is_empty() or _pending_notices.back() != message:
		_pending_notices.append(message)


func _has_blocking_overlay() -> bool:
	return _orders.visible or _map.visible or _pause.visible or _results.visible or _lan_menu.visible or _lobby.visible or _garage.visible or _settings.visible or _customization.visible


func _hide_current_notice() -> void :
	if _toast_panel.visible:
		_toast_panel.hide()
		_toast_timer.stop()


func _flush_pending_notice() -> void :
	if _game.visible and not _has_blocking_overlay() and not _toast_panel.visible and not _pending_notices.is_empty():
		_show_notice(_pending_notices.pop_front())


func _on_toast_timeout() -> void :
	_toast_panel.hide()
	_flush_pending_notice()


func set_map_layout(layout: Dictionary) -> void:
	_mini_map.set_layout(layout)
	_full_map.set_layout(layout)
