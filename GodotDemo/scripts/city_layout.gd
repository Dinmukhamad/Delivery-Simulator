extends RefCounted
## Authored city dimensions shared by movement, authority, navigation and HUD.
## X is east/west, Z is north/south. Negative Z is north.
const SIZE: float = 516.0
const HALF_SIZE: float = 258.0
const PLAYABLE_BOUNDS: Rect2 = Rect2(-255.5, -255.5, 511.0, 511.0)
const ROAD_AXES: Array[float] = [-240.0, -200.0, -160.0, -120.0, -84.0, -40.0, 0.0, 40.0, 84.0, 120.0, 160.0, 200.0, 240.0]
const NORTH_PARK: Rect2 = Rect2(-233.0, -233.0, 146.0, 146.0)
const SOUTH_PARK: Rect2 = Rect2(87.0, 127.0, 146.0, 106.0)
const ORIGINAL_PARK: Rect2 = Rect2(48.0, -82.0, 34.0, 34.0)

static func get_bounds() -> Rect2:
	return Rect2(-HALF_SIZE, -HALF_SIZE, SIZE, SIZE)

static func contains_position(position: Vector3, margin: float = 0.0) -> bool:
	if not position.is_finite() or not is_finite(margin):
		return false
	var safe_bounds: Rect2 = PLAYABLE_BOUNDS.grow(-maxf(margin, 0.0))
	# Clamping uses both ends inclusively; reject only coordinates beyond them.
	return position.x >= safe_bounds.position.x and position.x <= safe_bounds.end.x and position.z >= safe_bounds.position.y and position.z <= safe_bounds.end.y

static func contains_point(position: Vector3, margin: float = 0.0) -> bool:
	return contains_position(position, margin)

static func inside_playable(position: Vector3) -> bool:
	return contains_position(position)

static func get_districts() -> Array[Dictionary]:
	return [
		{"id": "parks", "name": "Городской парк", "rect": Rect2(-240, -240, 156, 156), "color": Color("a4ca90")},
		{"id": "business", "name": "Деловой центр", "rect": Rect2(-240, -84, 156, 168), "color": Color("a9bfce")},
		{"id": "civic", "name": "Торговый и общественный район", "rect": Rect2(-84, -240, 168, 156), "color": Color("e7c18b")},
		{"id": "industrial", "name": "Логистический район", "rect": Rect2(84, -240, 156, 156), "color": Color("c8b5a4")},
		{"id": "residential", "name": "Жилые кварталы", "rect": Rect2(-240, 84, 480, 156), "color": Color("d8c4a4")},
		{"id": "old_town", "name": "Старый город", "rect": Rect2(-84, -84, 324, 168), "color": Color("eed7b2")}
	]

static func get_district_id(position: Vector3) -> String:
	var flat: Vector2 = Vector2(position.x, position.z)
	if NORTH_PARK.has_point(flat) or SOUTH_PARK.has_point(flat):
		return "parks"
	for district in get_districts():
		if district["rect"].has_point(flat):
			return str(district["id"])
	return "old_town"

static func get_district_name(position: Vector3) -> String:
	if SOUTH_PARK.has_point(Vector2(position.x, position.z)):
		return "Парк «Лесной»"
	var wanted: String = get_district_id(position)
	for district in get_districts():
		if district["id"] == wanted:
			return str(district["name"])
	return "Старый город"

## Fixed, reviewed block addresses. This is a hand-authored catalogue, not random city generation.
static func get_extension_buildings() -> Array[Dictionary]:
	return [
		{"id": "northstar", "name": "Northstar Tower", "position": Vector3(-220, 0, -60), "size": Vector3(24, 36, 22), "kind": "office", "district": "business", "color": Color("8eafbf"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "metro", "name": "Metro Business", "position": Vector3(-180, 0, -60), "size": Vector3(24, 45, 22), "kind": "office", "district": "business", "color": Color("b8c7cb"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "vertex", "name": "Vertex Offices", "position": Vector3(-140, 0, -60), "size": Vector3(22, 28, 22), "kind": "office", "district": "business", "color": Color("82afa9"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "courier_hub", "name": "Офис городских сервисов", "position": Vector3(-102, 0, -60), "size": Vector3(22, 24, 22), "kind": "office", "district": "business", "color": Color("a8b4c9"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "riverbank", "name": "Riverbank Offices", "position": Vector3(-220, 0, -20), "size": Vector3(24, 24, 24), "kind": "office", "district": "business", "color": Color("8eafbf"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "city_bank", "name": "Городской банк", "position": Vector3(-140, 0, -20), "size": Vector3(26, 18, 22), "kind": "civic", "district": "business", "color": Color("a7c1ba"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "espresso", "name": "Кофейня делового центра", "position": Vector3(-102, 0, -20), "size": Vector3(22, 8, 18), "kind": "shop", "district": "business", "color": Color("d7ae8b"), "pickup": true, "delivery": false, "sign": "COFFEE"},
		{"id": "hotel", "name": "Отель Skyline", "position": Vector3(-220, 0, 20), "size": Vector3(24, 30, 22), "kind": "office", "district": "business", "color": Color("a8b4c9"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "summit", "name": "Summit Tower", "position": Vector3(-180, 0, 20), "size": Vector3(24, 54, 24), "kind": "office", "district": "business", "color": Color("8eafbf"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "innovation", "name": "Innovation Hub", "position": Vector3(-140, 0, 20), "size": Vector3(24, 36, 22), "kind": "office", "district": "business", "color": Color("b8c7cb"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "insurance", "name": "Страховой центр", "position": Vector3(-102, 0, 20), "size": Vector3(22, 21, 22), "kind": "office", "district": "business", "color": Color("82afa9"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "deli", "name": "Гастроном «Площадь»", "position": Vector3(-220, 0, 60), "size": Vector3(24, 8, 18), "kind": "shop", "district": "business", "color": Color("dcb3aa"), "pickup": true, "delivery": false, "sign": "DELI"},
		{"id": "print", "name": "Типография «Печать»", "position": Vector3(-180, 0, 60), "size": Vector3(24, 9, 18), "kind": "shop", "district": "business", "color": Color("d7ae8b"), "pickup": true, "delivery": false, "sign": "PRINT"},
		{"id": "clinic", "name": "Медицинский центр", "position": Vector3(-140, 0, 60), "size": Vector3(24, 12, 22), "kind": "civic", "district": "business", "color": Color("ccbaa1"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "media", "name": "Media House", "position": Vector3(-102, 0, 60), "size": Vector3(22, 24, 22), "kind": "office", "district": "business", "color": Color("82afa9"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "mall", "name": "Торговый дом", "position": Vector3(-60, 0, -220), "size": Vector3(26, 12, 22), "kind": "shop", "district": "civic", "color": Color("d7ae8b"), "pickup": true, "delivery": false, "sign": "MALL"},
		{"id": "foodcourt", "name": "Ресторан «Север»", "position": Vector3(-20, 0, -220), "size": Vector3(24, 9, 22), "kind": "shop", "district": "civic", "color": Color("9bbeb3"), "pickup": true, "delivery": false, "sign": "BISTRO"},
		{"id": "grocer", "name": "Северный супермаркет", "position": Vector3(20, 0, -220), "size": Vector3(26, 9, 22), "kind": "shop", "district": "civic", "color": Color("dcb3aa"), "pickup": true, "delivery": false, "sign": "MARKET"},
		{"id": "sports", "name": "Спортивный центр", "position": Vector3(60, 0, -220), "size": Vector3(24, 13, 24), "kind": "civic", "district": "civic", "color": Color("e8d6b1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "library", "name": "Городская библиотека", "position": Vector3(-60, 0, -180), "size": Vector3(26, 15, 22), "kind": "civic", "district": "civic", "color": Color("ccbaa1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "book_store", "name": "Книжная лавка", "position": Vector3(-20, 0, -180), "size": Vector3(24, 8, 20), "kind": "shop", "district": "civic", "color": Color("dcb3aa"), "pickup": false, "delivery": false, "sign": "BOOKS"},
		{"id": "hospital", "name": "Городская больница", "position": Vector3(60, 0, -180), "size": Vector3(24, 20, 24), "kind": "civic", "district": "civic", "color": Color("e8d6b1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "cinema", "name": "Кинотеатр «Луч»", "position": Vector3(-60, 0, -140), "size": Vector3(26, 14, 22), "kind": "civic", "district": "civic", "color": Color("ccbaa1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "municipal", "name": "Городская администрация", "position": Vector3(20, 0, -140), "size": Vector3(26, 18, 24), "kind": "civic", "district": "civic", "color": Color("a7c1ba"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "pharmacy_north", "name": "Аптека «Здоровье»", "position": Vector3(60, 0, -140), "size": Vector3(24, 8, 20), "kind": "shop", "district": "civic", "color": Color("d7ae8b"), "pickup": true, "delivery": false, "sign": "PHARMACY"},
		{"id": "bakery_north", "name": "Северная пекарня", "position": Vector3(-60, 0, -102), "size": Vector3(24, 9, 20), "kind": "shop", "district": "civic", "color": Color("9bbeb3"), "pickup": false, "delivery": false, "sign": "BAKERY"},
		{"id": "gallery", "name": "Галерея современного искусства", "position": Vector3(-20, 0, -102), "size": Vector3(24, 13, 22), "kind": "civic", "district": "civic", "color": Color("a7c1ba"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "civic_office", "name": "Общественный центр", "position": Vector3(20, 0, -102), "size": Vector3(24, 12, 22), "kind": "civic", "district": "civic", "color": Color("e8d6b1"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "music", "name": "Музыкальный магазин", "position": Vector3(60, 0, -102), "size": Vector3(24, 8, 20), "kind": "shop", "district": "civic", "color": Color("9bbeb3"), "pickup": false, "delivery": false, "sign": "MUSIC"},
		{"id": "logistics_north", "name": "Северный логистический склад", "position": Vector3(102, 0, -220), "size": Vector3(26, 9, 22), "kind": "warehouse", "district": "industrial", "color": Color("c79c80"), "pickup": true, "delivery": true, "sign": ""},
		{"id": "parcel_east", "name": "Сортировочный центр", "position": Vector3(140, 0, -220), "size": Vector3(26, 10, 22), "kind": "warehouse", "district": "industrial", "color": Color("a7b8ba"), "pickup": true, "delivery": false, "sign": ""},
		{"id": "cold_store", "name": "Холодильный склад", "position": Vector3(180, 0, -220), "size": Vector3(26, 8, 22), "kind": "warehouse", "district": "industrial", "color": Color("c7b29b"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "factory", "name": "Мастерская «Восток»", "position": Vector3(220, 0, -220), "size": Vector3(26, 10, 22), "kind": "warehouse", "district": "industrial", "color": Color("c79c80"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "furniture", "name": "Мебельный склад", "position": Vector3(102, 0, -180), "size": Vector3(26, 9, 22), "kind": "warehouse", "district": "industrial", "color": Color("a7b8ba"), "pickup": true, "delivery": false, "sign": ""},
		{"id": "printing_east", "name": "Печатный цех", "position": Vector3(180, 0, -180), "size": Vector3(26, 8, 22), "kind": "warehouse", "district": "industrial", "color": Color("c7b29b"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "service_east", "name": "Технический центр", "position": Vector3(220, 0, -180), "size": Vector3(26, 10, 22), "kind": "warehouse", "district": "industrial", "color": Color("c79c80"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "packaging", "name": "Упаковочный цех", "position": Vector3(102, 0, -140), "size": Vector3(26, 8, 22), "kind": "warehouse", "district": "industrial", "color": Color("a7b8ba"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "warehouse_blue", "name": "Склад Blue Cargo", "position": Vector3(140, 0, -140), "size": Vector3(26, 8, 22), "kind": "warehouse", "district": "industrial", "color": Color("c7b29b"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "wholesale", "name": "Оптовый склад", "position": Vector3(180, 0, -140), "size": Vector3(26, 10, 22), "kind": "warehouse", "district": "industrial", "color": Color("c79c80"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "repair", "name": "Ремонтная мастерская", "position": Vector3(140, 0, -102), "size": Vector3(26, 8, 20), "kind": "warehouse", "district": "industrial", "color": Color("a7b8ba"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "textiles", "name": "Текстильный склад", "position": Vector3(180, 0, -102), "size": Vector3(26, 9, 20), "kind": "warehouse", "district": "industrial", "color": Color("c7b29b"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "dispatch", "name": "Диспетчерский центр", "position": Vector3(220, 0, -102), "size": Vector3(24, 13, 22), "kind": "office", "district": "industrial", "color": Color("b8c7cb"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_01", "name": "Жилой корпус 1", "position": Vector3(-220, 0, 102), "size": Vector3(26, 18, 22), "kind": "apartment", "district": "residential", "color": Color("ddbf9c"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_02", "name": "Жилой корпус 2", "position": Vector3(-180, 0, 102), "size": Vector3(26, 21, 22), "kind": "apartment", "district": "residential", "color": Color("abc5bf"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_03", "name": "Жилой корпус 3", "position": Vector3(-140, 0, 102), "size": Vector3(26, 24, 22), "kind": "apartment", "district": "residential", "color": Color("d6b2a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_04", "name": "Жилой корпус 4", "position": Vector3(-102, 0, 102), "size": Vector3(26, 15, 22), "kind": "apartment", "district": "residential", "color": Color("ddbf9c"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_05", "name": "Жилой корпус 5", "position": Vector3(-60, 0, 102), "size": Vector3(26, 18, 22), "kind": "apartment", "district": "residential", "color": Color("abc5bf"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_06", "name": "Жилой корпус 6", "position": Vector3(-20, 0, 102), "size": Vector3(26, 21, 22), "kind": "apartment", "district": "residential", "color": Color("d6b2a3"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_07", "name": "Жилой корпус 7", "position": Vector3(-220, 0, 140), "size": Vector3(26, 24, 22), "kind": "apartment", "district": "residential", "color": Color("ddbf9c"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_08", "name": "Жилой корпус 8", "position": Vector3(-180, 0, 140), "size": Vector3(26, 15, 22), "kind": "apartment", "district": "residential", "color": Color("abc5bf"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_09", "name": "Жилой корпус 9", "position": Vector3(-102, 0, 140), "size": Vector3(26, 18, 22), "kind": "apartment", "district": "residential", "color": Color("d6b2a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_10", "name": "Жилой корпус 10", "position": Vector3(-60, 0, 140), "size": Vector3(26, 21, 22), "kind": "apartment", "district": "residential", "color": Color("ddbf9c"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_11", "name": "Жилой корпус 11", "position": Vector3(-220, 0, 180), "size": Vector3(26, 24, 22), "kind": "apartment", "district": "residential", "color": Color("abc5bf"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_12", "name": "Жилой корпус 12", "position": Vector3(-140, 0, 180), "size": Vector3(26, 15, 22), "kind": "apartment", "district": "residential", "color": Color("d6b2a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_13", "name": "Жилой корпус 13", "position": Vector3(-102, 0, 180), "size": Vector3(26, 18, 22), "kind": "apartment", "district": "residential", "color": Color("ddbf9c"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_14", "name": "Жилой корпус 14", "position": Vector3(-20, 0, 180), "size": Vector3(26, 21, 22), "kind": "apartment", "district": "residential", "color": Color("abc5bf"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_15", "name": "Жилой корпус 15", "position": Vector3(-180, 0, 220), "size": Vector3(26, 24, 22), "kind": "apartment", "district": "residential", "color": Color("d6b2a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "apartment_16", "name": "Жилой корпус 16", "position": Vector3(-140, 0, 220), "size": Vector3(26, 15, 22), "kind": "apartment", "district": "residential", "color": Color("ddbf9c"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_17", "name": "Жилой корпус 17", "position": Vector3(-60, 0, 220), "size": Vector3(26, 18, 22), "kind": "apartment", "district": "residential", "color": Color("abc5bf"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "apartment_18", "name": "Жилой корпус 18", "position": Vector3(-20, 0, 220), "size": Vector3(26, 21, 22), "kind": "apartment", "district": "residential", "color": Color("d6b2a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_1", "name": "House 11", "position": Vector3(20, 0, 102), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("e9c48f"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_2", "name": "House 12", "position": Vector3(60, 0, 102), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("c3cfad"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "garden_house_3", "name": "House 13", "position": Vector3(102, 0, 102), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("d8b4a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_4", "name": "House 14", "position": Vector3(140, 0, 102), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("e9c48f"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "garden_house_5", "name": "House 15", "position": Vector3(180, 0, 102), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("c3cfad"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_6", "name": "House 16", "position": Vector3(220, 0, 102), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("d8b4a3"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "garden_house_7", "name": "House 17", "position": Vector3(20, 0, 140), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("e9c48f"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_8", "name": "House 18", "position": Vector3(60, 0, 140), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("c3cfad"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "garden_house_9", "name": "House 19", "position": Vector3(20, 0, 180), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("d8b4a3"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_10", "name": "House 20", "position": Vector3(60, 0, 180), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("e9c48f"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "garden_house_11", "name": "House 21", "position": Vector3(20, 0, 220), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("c3cfad"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "garden_house_12", "name": "House 22", "position": Vector3(60, 0, 220), "size": Vector3(11, 6.4, 15), "kind": "house", "district": "residential", "color": Color("d8b4a3"), "pickup": false, "delivery": false, "sign": ""},
		{"id": "tech_store", "name": "Магазин техники", "position": Vector3(102, 0, -60), "size": Vector3(24, 9, 20), "kind": "shop", "district": "old_town", "color": Color("d7ae8b"), "pickup": true, "delivery": false, "sign": "TECH"},
		{"id": "artisan", "name": "Мастерская ремесленников", "position": Vector3(140, 0, -60), "size": Vector3(24, 12, 22), "kind": "civic", "district": "old_town", "color": Color("ccbaa1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "food_east", "name": "Кафе «Восточный двор»", "position": Vector3(180, 0, -20), "size": Vector3(24, 8, 20), "kind": "shop", "district": "old_town", "color": Color("dcb3aa"), "pickup": true, "delivery": false, "sign": "CAFE"},
		{"id": "school", "name": "Начальная школа", "position": Vector3(220, 0, -20), "size": Vector3(24, 13, 22), "kind": "civic", "district": "old_town", "color": Color("e8d6b1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "creative", "name": "Creative Studios", "position": Vector3(102, 0, 20), "size": Vector3(24, 18, 22), "kind": "office", "district": "old_town", "color": Color("8eafbf"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "local_store", "name": "Районный магазин", "position": Vector3(140, 0, 20), "size": Vector3(24, 8, 20), "kind": "shop", "district": "old_town", "color": Color("dcb3aa"), "pickup": false, "delivery": false, "sign": "STORE"},
		{"id": "community", "name": "Культурный центр", "position": Vector3(180, 0, 60), "size": Vector3(24, 13, 22), "kind": "civic", "district": "old_town", "color": Color("e8d6b1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "flowers_east", "name": "Цветочный магазин «Сад»", "position": Vector3(220, 0, 60), "size": Vector3(24, 8, 20), "kind": "shop", "district": "old_town", "color": Color("9bbeb3"), "pickup": false, "delivery": false, "sign": "FLOWERS"},
		{"id": "park_cafe", "name": "Кафе городского парка", "position": Vector3(-102, 0, -224), "size": Vector3(14, 6, 14), "kind": "shop", "district": "parks", "color": Color("dcb3aa"), "pickup": true, "delivery": false, "sign": "PARK CAFE"},
		{"id": "park_station", "name": "Служба городского парка", "position": Vector3(-224, 0, -102), "size": Vector3(14, 6, 14), "kind": "civic", "district": "parks", "color": Color("e8d6b1"), "pickup": false, "delivery": true, "sign": ""},
		{"id": "forest_kiosk", "name": "Павильон парка «Лесной»", "position": Vector3(102, 0, 140), "size": Vector3(14, 6, 14), "kind": "shop", "district": "parks", "color": Color("9bbeb3"), "pickup": false, "delivery": true, "sign": "PARK"},
		{"id": "residential_grocery", "name": "Магазин «У дома»", "position": Vector3(-140, 0, 140), "size": Vector3(24, 8, 20), "kind": "shop", "district": "residential", "color": Color("aac0a2"), "pickup": true, "delivery": false, "sign": "GROCERY"}
	]
