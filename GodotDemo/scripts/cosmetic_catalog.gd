extends RefCounted

# Only these locally shipped IDs and palettes can reach a material.
# Local career files are trusted as before; in a running LAN shift the Host
# owns all purchases and selections.
const DATA_PATH: String = "res://assets/cosmetics.json"
const CATEGORIES: Array[String] = ["outfit", "backpack", "vehicle_paint"]
const DEFAULTS: Dictionary = {"outfit": "classic_blue", "backpack": "classic", "vehicle_paint": "factory"}
const FALLBACK_DATA: String = "{\"version\":1,\"categories\":{\"outfit\":[{\"id\":\"classic_blue\",\"name\":\"Классический синий\",\"price\":0,\"palette\":{\"jacket\":\"#246cdb\",\"dark\":\"#164293\",\"light\":\"#428ae4\",\"cap\":\"#246cdb\",\"pants\":\"#213044\"}},{\"id\":\"mint\",\"name\":\"Мятный курьер\",\"price\":0,\"palette\":{\"jacket\":\"#32bca8\",\"dark\":\"#17695c\",\"light\":\"#a0ecd8\",\"cap\":\"#f7df83\",\"pants\":\"#293f50\"}},{\"id\":\"sunshine\",\"name\":\"Солнечная смена\",\"price\":0,\"palette\":{\"jacket\":\"#f2b84b\",\"dark\":\"#aa6533\",\"light\":\"#ffe9a5\",\"cap\":\"#f1f4eb\",\"pants\":\"#3a4455\"}},{\"id\":\"night\",\"name\":\"Ночной экспресс\",\"price\":1500,\"palette\":{\"jacket\":\"#303b58\",\"dark\":\"#1d263e\",\"light\":\"#667caa\",\"cap\":\"#b8eb91\",\"pants\":\"#1b2435\"}},{\"id\":\"retro\",\"name\":\"Ретро доставка\",\"price\":2000,\"palette\":{\"jacket\":\"#dc7659\",\"dark\":\"#8b423a\",\"light\":\"#ffb395\",\"cap\":\"#68c6bc\",\"pants\":\"#384f60\"}},{\"id\":\"express\",\"name\":\"Экспресс про\",\"price\":2500,\"palette\":{\"jacket\":\"#8d66cf\",\"dark\":\"#4e3784\",\"light\":\"#ceb8ff\",\"cap\":\"#f7cf60\",\"pants\":\"#302947\"}}],\"backpack\":[{\"id\":\"classic\",\"name\":\"Классический рюкзак\",\"price\":0,\"palette\":{\"style\":\"classic\",\"color\":\"#164293\",\"trim\":\"#246cdb\"}},{\"id\":\"compact\",\"name\":\"Компактный рюкзак\",\"price\":0,\"palette\":{\"style\":\"compact\",\"color\":\"#2e8b80\",\"trim\":\"#b9dfcc\"}},{\"id\":\"rolltop\",\"name\":\"Рюкзак роллтоп\",\"price\":750,\"palette\":{\"style\":\"rolltop\",\"color\":\"#e4ab50\",\"trim\":\"#8c5b39\"}},{\"id\":\"messenger\",\"name\":\"Сумка через плечо\",\"price\":1500,\"palette\":{\"style\":\"messenger\",\"color\":\"#954e61\",\"trim\":\"#f0b1a4\"}}],\"vehicle_paint\":[{\"id\":\"factory\",\"name\":\"Заводской цвет\",\"price\":0,\"palette\":{\"paint\":\"\",\"trim\":\"\"}},{\"id\":\"mint\",\"name\":\"Мята\",\"price\":0,\"palette\":{\"paint\":\"#54c8ad\",\"trim\":\"#173e40\"}},{\"id\":\"coral\",\"name\":\"Коралл\",\"price\":0,\"palette\":{\"paint\":\"#e98173\",\"trim\":\"#5e3442\"}},{\"id\":\"amber\",\"name\":\"Янтарь\",\"price\":750,\"palette\":{\"paint\":\"#f4bd4c\",\"trim\":\"#78542e\"}},{\"id\":\"plum\",\"name\":\"Слива\",\"price\":750,\"palette\":{\"paint\":\"#946aca\",\"trim\":\"#382b61\"}},{\"id\":\"night\",\"name\":\"Полночь\",\"price\":1000,\"palette\":{\"paint\":\"#334562\",\"trim\":\"#b6cf70\"}}]}}"
static var _definitions: Dictionary = {}


static func load_definitions() -> Dictionary:
	if _definitions.is_empty():
		var fallback: Dictionary = JSON.parse_string(FALLBACK_DATA)
		var source: Dictionary = fallback
		if FileAccess.file_exists(DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary and parsed.get("categories") is Dictionary:
				source = parsed
		for category: String in CATEGORIES:
			var fallback_items: Array = fallback["categories"][category]
			var raw_items: Variant = source.get("categories", {}).get(category, [])
			var safe_items: Array[Dictionary] = []
			for fallback_item: Dictionary in fallback_items:
				var item: Dictionary = fallback_item.duplicate(true)
				if raw_items is Array:
					for raw: Variant in raw_items:
						if raw is Dictionary and raw.get("id") == item["id"]:
							var price: Variant = raw.get("price", item["price"])
							if (price is int or price is float) and is_finite(float(price)):
								item["price"] = int(clampf(float(price), 0.0, 100000.0))
							var label: Variant = raw.get("name", item["name"])
							if label is String and not label.strip_edges().is_empty():
								item["name"] = label.strip_edges().left(48)
							var palette: Variant = raw.get("palette", {})
							if palette is Dictionary:
								for key: String in item["palette"]:
									var value: Variant = palette.get(key)
									if value is String:
										if key == "style" and value in ["classic", "compact", "rolltop", "messenger"]:
											item["palette"][key] = value
										elif key != "style" and Color.html_is_valid(value):
											item["palette"][key] = value
							break
				if item["id"] == DEFAULTS[category]:
					item["price"] = 0
				safe_items.append(item)
			_definitions[category] = safe_items
	return _definitions.duplicate(true)


static func get_items(category: String) -> Array[Dictionary]:
	if _definitions.is_empty():
		load_definitions()
	var result: Array[Dictionary] = []
	for item: Dictionary in _definitions.get(category, []):
		result.append(item.duplicate(true))
	return result


static func get_item(category: String, item_id: String) -> Dictionary:
	if _definitions.is_empty():
		load_definitions()
	for item: Dictionary in _definitions.get(category, []):
		if item["id"] == item_id:
			return item.duplicate(true)
	return {}


static func default_appearance() -> Dictionary:
	return DEFAULTS.duplicate()


static func normalize_appearance(raw: Variant) -> Dictionary:
	var result: Dictionary = default_appearance()
	if not raw is Dictionary:
		return result
	for category: String in CATEGORIES:
		var value: Variant = raw.get(category)
		if value is String and not get_item(category, value).is_empty():
			result[category] = value
	return result


static func _owned_keys(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw is Array:
		return result
	for value: Variant in raw.slice(0, 64):
		if not value is String or value.length() > 64:
			continue
		var parts: PackedStringArray = value.split(":")
		if parts.size() != 2:
			continue
		var item: Dictionary = get_item(parts[0], parts[1])
		if item.is_empty() or result.has(value):
			continue
		result.append(value)
	return result


static func sanitize_profile(source: Dictionary) -> Dictionary:
	var owned: Array[String] = _owned_keys(source.get("owned_cosmetics", []))
	var appearance: Dictionary = normalize_appearance(source.get("appearance", {}))
	for category: String in CATEGORIES:
		var item_id: String = appearance[category]
		var item: Dictionary = get_item(category, item_id)
		if int(item.get("price", 0)) > 0 and not owned.has(category + ":" + item_id):
			appearance[category] = DEFAULTS[category]
	return {"appearance": appearance, "owned_cosmetics": owned}


static func owns(profile: Dictionary, category: String, item_id: String) -> bool:
	var item: Dictionary = get_item(category, item_id)
	if item.is_empty():
		return false
	return int(item["price"]) == 0 or _owned_keys(profile.get("owned_cosmetics", [])).has(category + ":" + item_id)


static func outfit_palette(item_id: String) -> Dictionary:
	var item: Dictionary = get_item("outfit", item_id)
	if item.is_empty():
		item = get_item("outfit", DEFAULTS["outfit"])
	return item["palette"].duplicate(true)


static func backpack_palette(item_id: String) -> Dictionary:
	var item: Dictionary = get_item("backpack", item_id)
	if item.is_empty():
		item = get_item("backpack", DEFAULTS["backpack"])
	return item["palette"].duplicate(true)


static func paint_palette(item_id: String) -> Dictionary:
	var item: Dictionary = get_item("vehicle_paint", item_id)
	if item.is_empty():
		item = get_item("vehicle_paint", DEFAULTS["vehicle_paint"])
	return item["palette"].duplicate(true)


static func _request_item(category: Variant, item_id: Variant) -> Dictionary:
	if not category is String or not item_id is String:
		return {}
	if category.length() > 32 or item_id.length() > 32:
		return {}
	return get_item(category, item_id)


static func buy(profile: Dictionary, category: Variant, item_id: Variant) -> Dictionary:
	var item: Dictionary = _request_item(category, item_id)
	if item.is_empty():
		return {"ok": false, "changed": false, "message": "Неизвестный предмет стиля."}
	var fields: Dictionary = sanitize_profile(profile)
	var owned: Array = fields["owned_cosmetics"].duplicate()
	var key: String = category + ":" + item_id
	var price: int = int(item["price"])
	if price == 0:
		return select(profile, category, item_id)
	if owned.has(key):
		return {"ok": false, "changed": false, "message": "Уже куплено. Можно выбрать бесплатно."}
	var money: Variant = profile.get("money", 0)
	if not (money is int or money is float) or not is_finite(float(money)) or float(money) < float(price) or float(money) > 1000000000.0:
		return {"ok": false, "changed": false, "message": "Недостаточно денег: нужно %d ₸." % price}
	owned.append(key)
	fields["owned_cosmetics"] = owned
	fields["appearance"][category] = item_id
	profile.merge(fields, true)
	profile["money"] = int(money) - price
	return {"ok": true, "changed": true, "message": "%s куплено и выбрано." % item["name"]}


static func select(profile: Dictionary, category: Variant, item_id: Variant) -> Dictionary:
	var item: Dictionary = _request_item(category, item_id)
	if item.is_empty():
		return {"ok": false, "changed": false, "message": "Неизвестный предмет стиля."}
	if not owns(profile, category, item_id):
		return {"ok": false, "changed": false, "message": "Сначала купите этот предмет."}
	var fields: Dictionary = sanitize_profile(profile)
	var changed: bool = fields["appearance"][category] != item_id or profile.get("appearance") != fields["appearance"] or profile.get("owned_cosmetics") != fields["owned_cosmetics"]
	fields["appearance"][category] = item_id
	profile.merge(fields, true)
	return {"ok": true, "changed": changed, "message": "%s выбрано." % item["name"]}
