extends RefCounted

# Deliberate, repeatable profile grants. This allowlist never executes commands
# and never updates delivery, shift, team or district-event earnings.
const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
const MAX_CODE_LENGTH: int = 64
const MAX_PROFILE_VALUE: int = 1000000000
const MAX_LEVEL: int = 10
const DEFAULT_LEVEL_XP_STEP: int = 150


static func code_catalog() -> Array[Dictionary]:
	return [
		{"code": "MONEY10000", "description": "+10 000 ₽"},
		{"code": "MONEY50000", "description": "+50 000 ₽"},
		{"code": "XP1000", "description": "+1 000 XP"},
		{"code": "LEVELUP", "description": "+1 уровень, максимум 10"},
		{"code": "DELIVERYMASTER", "description": "Уровень 10 — Delivery Master"},
		{"code": "ALLVEHICLES", "description": "Выдать весь транспорт; требования к уровню сохраняются"}
	]


static func normalize_code(raw_code: Variant) -> String:
	if not raw_code is String or raw_code.is_empty() or raw_code.length() > MAX_CODE_LENGTH:
		return ""
	for index: int in raw_code.length():
		var character: int = raw_code.unicode_at(index)
		if character < 32 or character == 127:
			return ""
	return raw_code.strip_edges().to_upper()


static func apply(profile: Dictionary, raw_code: Variant, level_xp_step: int = DEFAULT_LEVEL_XP_STEP) -> Dictionary:
	var code: String = normalize_code(raw_code)
	if code.is_empty():
		return _result(false, false, "Введите код длиной от 1 до 64 символов без переносов строк.", code)
	if code not in ["MONEY10000", "MONEY50000", "XP1000", "LEVELUP", "DELIVERYMASTER", "ALLVEHICLES"]:
		return _result(false, false, "Неизвестный чит-код. Выберите код из списка.", code)
	var previous: Dictionary = profile.duplicate(true)
	var money: int = _bounded_number(profile.get("money", 0))
	var xp: int = _bounded_number(profile.get("xp", 0))
	var step: int = clampi(level_xp_step, 1, MAX_PROFILE_VALUE)
	var level: int = level_for_xp(xp, step)
	var message: String = ""
	match code:
		"MONEY10000", "MONEY50000":
			var grant: int = 10000 if code == "MONEY10000" else 50000
			var granted: int = mini(grant, MAX_PROFILE_VALUE - money)
			money += granted
			message = "+%d ₽. Деньги: %d ₽." % [granted, money] if granted > 0 else "Деньги уже достигли лимита 1 000 000 000 ₽."
		"XP1000":
			var granted: int = mini(1000, MAX_PROFILE_VALUE - xp)
			xp += granted
			message = "+%d XP. Опыт: %d XP." % [granted, xp] if granted > 0 else "Опыт уже достиг лимита 1 000 000 000 XP."
		"LEVELUP":
			if level < MAX_LEVEL:
				xp = maxi(xp, mini(MAX_PROFILE_VALUE, level * level * step))
				message = "Уровень повышен до %d." % level_for_xp(xp, step)
			else:
				message = "У вас уже максимальный уровень 10."
		"DELIVERYMASTER":
			xp = maxi(xp, mini(MAX_PROFILE_VALUE, (MAX_LEVEL - 1) * (MAX_LEVEL - 1) * step))
			message = "Delivery Master: уровень %d." % level_for_xp(xp, step)
		"ALLVEHICLES":
			var owned: Array = VehicleCatalog.sanitize_profile_vehicles(profile)["owned_vehicles"].duplicate()
			for vehicle_id: String in VehicleCatalog.SUPPORTED_IDS:
				if not owned.has(vehicle_id):
					owned.append(vehicle_id)
			profile["owned_vehicles"] = owned
			message = "Весь транспорт получен. Вызовите его в гараже; требования к уровню сохраняются."
	profile["money"] = money
	profile["xp"] = xp
	profile["level"] = level_for_xp(xp, step)
	profile["rank"] = rank_for_level(int(profile["level"]))
	return _result(true, profile != previous, message, code)


static func level_for_xp(xp: int, level_xp_step: int = DEFAULT_LEVEL_XP_STEP) -> int:
	var level: int = 1
	var step: int = clampi(level_xp_step, 1, MAX_PROFILE_VALUE)
	while level < MAX_LEVEL and xp >= level * level * step:
		level += 1
	return level


static func rank_for_level(level: int) -> String:
	if level >= 10:
		return "Delivery Master"
	if level >= 6:
		return "Express Pro"
	if level >= 4:
		return "Fast Courier"
	if level >= 2:
		return "City Courier"
	return "Rookie Courier"


static func _bounded_number(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0
	return int(clampf(float(value), 0.0, float(MAX_PROFILE_VALUE)))


static func _result(ok: bool, changed: bool, message: String, code: String) -> Dictionary:
	return {"ok": ok, "changed": changed, "message": message, "code": code}
