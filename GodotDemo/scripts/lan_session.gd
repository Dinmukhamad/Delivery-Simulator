extends Node
class_name LanSession


signal lobby_changed(data: Dictionary)
signal session_started(data: Dictionary)
signal request_received(peer_id: int, action: String, payload: Dictionary)
signal state_received(data: Dictionary)
signal event_received(data: Dictionary)
signal pose_received(peer_id: int, pose: Dictionary)
signal peer_left(peer_id: int)
signal disconnected(reason: String)
signal message_received(message: String)

const VehicleCatalog = preload("res://scripts/vehicle_catalog.gd")
const CosmeticCatalog = preload("res://scripts/cosmetic_catalog.gd")
const TeamShiftRules = preload("res://scripts/team_shift_rules.gd")
const GAME_VERSION: String = "0.16.0"
const PORT: int = 7777
const SERVER_ID: int = 1
const CONNECT_TIMEOUT_MS: int = 8000
const REJECT_DELAY_MS: int = 250
const PROFILE_LIMIT: int = 1000000000

var role: String = "offline"
var phase: String = "offline"
var members: Dictionary = {}
var local_id: int = 0
var session_id: String = ""
var lobby_config: Dictionary = {}

var _peer: ENetMultiplayerPeer
var _local_profile: Dictionary = {}
var _connecting_since: int = 0
var _lobby_epoch: int = 0
var _pending: Dictionary = {}
var _rejections: Dictionary = {}
var _closing: bool = false
var _signals_bound: bool = false


func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_signals()


func _bind_signals() -> void :
	if _signals_bound:
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_signals_bound = true


func _process(_delta: float) -> void :
	var now: int = Time.get_ticks_msec()
	if role == "client" and phase == "connecting" and now - _connecting_since >= CONNECT_TIMEOUT_MS:
		leave("Connection timed out. Check the Host IP and UDP port 7777.")
		return
	if not is_host():
		return
	for peer_id: int in _pending.keys():
		if now - int(_pending[peer_id]) >= CONNECT_TIMEOUT_MS:
			_reject_peer(peer_id, "Registration timed out. Please reconnect.")
	for peer_id: int in _rejections.keys():
		if now < int(_rejections[peer_id]):
			continue
		_rejections.erase(peer_id)
		if _peer != null:
			_peer.disconnect_peer(peer_id)


func host_game(profile: Dictionary, room_name: String, max_players: int, shift_seconds: int, shift_mode: String = "competitive") -> Error:
	_bind_signals()
	_reset_transport()
	_peer = ENetMultiplayerPeer.new()

	var error: Error = _peer.create_server(PORT, 8, 2)
	if error != OK:
		_reset_transport()
		message_received.emit("Could not host the room. UDP port 7777 may already be in use.")
		return error
	multiplayer.multiplayer_peer = _peer
	role = "host"
	phase = "lobby"
	_lobby_epoch = 1
	local_id = SERVER_ID
	_local_profile = _sanitize_profile(profile)
	members[SERVER_ID] = _member(SERVER_ID, _local_profile, true)
	var duration: int = -1 if shift_seconds == 0 else shift_seconds
	if duration not in [-1, 600, 900, 1200]:
		duration = 600
	lobby_config = {
		"room_name": _clean_text(room_name, 40, "Courier room"), 
		"host_ip": _local_address(), 
		"max_players": clampi(max_players, 1, 4), 
		"shift_seconds": duration,
		"shift_mode": TeamShiftRules.normalize_mode(shift_mode),
		"team_goal_per_player": int(TeamShiftRules.load_config()["deliveries_per_player"]), 
	}
	_broadcast_lobby()
	return OK


func join_game(profile: Dictionary, address: String) -> Error:
	_bind_signals()
	_reset_transport()
	var valid_address: String = _normalize_address(address)
	if valid_address.is_empty():
		message_received.emit("Enter a valid Host IPv4 address, for example 192.168.1.10.")
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(valid_address, PORT, 2)
	if error != OK:
		_reset_transport()
		message_received.emit("Could not connect to the Host.")
		return error
	_local_profile = _sanitize_profile(profile)
	role = "client"
	phase = "connecting"
	_connecting_since = Time.get_ticks_msec()
	multiplayer.multiplayer_peer = _peer
	lobby_changed.emit(_lobby_data(0))
	return OK


func set_ready(ready: bool) -> void :
	if phase != "lobby" or not members.has(local_id):
		return
	if is_host():

		members[SERVER_ID]["ready"] = true
		_broadcast_lobby()
	elif role == "client":
		_rpc_ready.rpc_id(SERVER_ID, _lobby_epoch, ready)


func start_game() -> void :
	if not is_host() or phase != "lobby" or not _can_start():
		return
	session_id = "%x-%x" % [Time.get_ticks_usec(), randi()]
	phase = "playing"
	for peer_id: int in _pending.keys():
		_reject_peer(peer_id, "The shift has already started. Join after the Host returns to the lobby.")
	var data: Dictionary = _start_data()

	for peer_id: int in members.keys():
		if peer_id != SERVER_ID:
			_rpc_start.rpc_id(peer_id, data)
	session_started.emit(data.duplicate(true))


func return_to_lobby() -> void :
	if not is_host() or phase not in ["playing", "results"]:
		return
	phase = "lobby"
	_lobby_epoch += 1
	session_id = ""
	for peer_id: int in members.keys():
		members[peer_id]["ready"] = peer_id == SERVER_ID
	for peer_id: int in members.keys():
		if peer_id != SERVER_ID:
			_rpc_return_to_lobby.rpc_id(peer_id, _lobby_data(peer_id))
	lobby_changed.emit(_lobby_data(SERVER_ID))


func leave(reason: String = "") -> void :
	if not is_active() or _closing:
		return
	_reset_transport()
	disconnected.emit(reason if not reason.is_empty() else "You left the room.")


func request_action(action: String, payload: Dictionary = {}) -> void :
	if phase != "playing" or not members.has(local_id) or action.is_empty() or action.length() > 32:
		return
	if is_host():
		request_received.emit(local_id, action, payload.duplicate(true))
	elif role == "client":
		_rpc_action.rpc_id(SERVER_ID, session_id, action, payload)


func send_pose(pose: Dictionary) -> void :
	if phase != "playing" or not members.has(local_id):
		return
	if is_host():
		request_received.emit(local_id, "pose", pose.duplicate(true))
	elif role == "client":
		_rpc_pose_request.rpc_id(SERVER_ID, session_id, pose)


func send_state(peer_id: int, data: Dictionary) -> void :
	if not is_host() or not members.has(peer_id) or phase not in ["playing", "results"]:
		return
	if not _matches_session(data):
		return
	if String(data.get("phase", "")) == "results":
		phase = "results"
	if peer_id == SERVER_ID:
		state_received.emit(data.duplicate(true))
	else:
		_rpc_state.rpc_id(peer_id, data)


func send_event(peer_id: int, data: Dictionary) -> void :
	if not is_host() or not members.has(peer_id):
		return
	if peer_id == SERVER_ID:
		event_received.emit(data.duplicate(true))
	else:
		_rpc_event.rpc_id(peer_id, data)


func publish_pose(peer_id: int, pose: Dictionary) -> void :
	if not is_host() or phase != "playing" or not members.has(peer_id):
		return
	if peer_id != SERVER_ID:
		pose_received.emit(peer_id, pose.duplicate(true))
	for recipient_id: int in members.keys():
		if recipient_id != SERVER_ID and recipient_id != peer_id:
			_rpc_published_pose.rpc_id(recipient_id, session_id, peer_id, pose)


func update_member_profile(peer_id: int, profile: Dictionary) -> void :
	if not is_host() or not members.has(peer_id):
		return
	var sanitized: Dictionary = _sanitize_profile(profile)
	members[peer_id]["profile"] = sanitized
	members[peer_id]["appearance"] = sanitized["appearance"].duplicate(true)
	members[peer_id]["name"] = sanitized["player_name"]
	if peer_id == SERVER_ID:
		_local_profile = sanitized.duplicate(true)
	_broadcast_lobby()


func is_host() -> bool:
	return role == "host"


func is_active() -> bool:
	return role != "offline"


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_register(version: String, profile: Dictionary) -> void :
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= SERVER_ID or not _pending.has(sender) or _rejections.has(sender):
		return
	if version != GAME_VERSION:
		_reject_peer(sender, "Game versions do not match.")
		return
	if phase != "lobby":
		_reject_peer(sender, "The shift has already started. Join after the Host returns to the lobby.")
		return
	if members.size() >= int(lobby_config.get("max_players", 4)):
		_reject_peer(sender, "The room is full.")
		return
	var sanitized: Dictionary = _sanitize_profile(profile)
	members[sender] = _member(sender, sanitized, false)
	_pending.erase(sender)
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_ready(request_epoch: int, ready: bool) -> void :
	var sender: int = multiplayer.get_remote_sender_id()
	if not _approved_request(sender) or phase != "lobby" or request_epoch != _lobby_epoch:
		return
	members[sender]["ready"] = ready
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_action(request_session: String, action: String, payload: Dictionary) -> void :
	var sender: int = multiplayer.get_remote_sender_id()
	if not _approved_request(sender) or phase != "playing" or request_session != session_id or action.is_empty() or action.length() > 32:
		return
	request_received.emit(sender, action, payload)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_pose_request(request_session: String, pose: Dictionary) -> void :
	var sender: int = multiplayer.get_remote_sender_id()
	if not _approved_request(sender) or phase != "playing" or request_session != session_id:
		return
	request_received.emit(sender, "pose", pose)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_lobby(data: Dictionary) -> void :
	if not _from_host() or phase == "offline":
		return
	_apply_lobby(data)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_start(data: Dictionary) -> void :
	if not _from_host() or phase != "lobby" or not members.has(local_id):
		return
	session_id = String(data.get("session_id", ""))
	if session_id.is_empty():
		return
	phase = "playing"
	var confirmed: Dictionary = data.duplicate(true)
	confirmed["shift_mode"] = TeamShiftRules.normalize_mode(data.get("shift_mode", "competitive"))
	lobby_config["shift_mode"] = confirmed["shift_mode"]
	session_started.emit(confirmed)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_return_to_lobby(data: Dictionary) -> void :
	if not _from_host() or phase not in ["playing", "results"]:
		return
	session_id = ""
	_apply_lobby(data)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_state(data: Dictionary) -> void :
	if not _from_host() or phase not in ["playing", "results"] or not _matches_session(data):
		return
	if String(data.get("phase", "")) == "results":
		phase = "results"
	state_received.emit(data)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_event(data: Dictionary) -> void :
	if not _from_host() or not members.has(local_id):
		return
	event_received.emit(data)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_published_pose(pose_session: String, peer_id: int, pose: Dictionary) -> void :
	if not _from_host() or phase != "playing" or pose_session != session_id or peer_id == local_id or not members.has(peer_id):
		return
	pose_received.emit(peer_id, pose)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_reject(reason: String) -> void :
	if not _from_host():
		return
	leave(reason)


func _on_peer_connected(peer_id: int) -> void :
	if not is_host() or _closing or peer_id <= SERVER_ID:
		return
	_pending[peer_id] = Time.get_ticks_msec()
	if phase != "lobby":
		_reject_peer(peer_id, "The shift has already started. Join after the Host returns to the lobby.")
	elif members.size() >= int(lobby_config.get("max_players", 4)):
		_reject_peer(peer_id, "The room is full.")


func _on_peer_disconnected(peer_id: int) -> void :
	if _closing or not is_host():
		return
	_pending.erase(peer_id)
	_rejections.erase(peer_id)
	if not members.has(peer_id):
		return
	members.erase(peer_id)
	peer_left.emit(peer_id)
	_broadcast_lobby()


func _on_connected_to_server() -> void :
	if role != "client" or phase != "connecting" or _closing:
		return
	local_id = multiplayer.get_unique_id()
	_rpc_register.rpc_id(SERVER_ID, GAME_VERSION, _local_profile)


func _on_connection_failed() -> void :
	if role == "client" and not _closing:
		leave("Could not connect to the Host. Check the IP address and UDP port 7777.")


func _on_server_disconnected() -> void :
	if role == "client" and not _closing:
		leave("The Host disconnected. The room has been closed.")


func _approved_request(sender: int) -> bool:
	return is_host() and sender > SERVER_ID and members.has(sender) and not _rejections.has(sender)


func _from_host() -> bool:
	return role == "client" and multiplayer.get_remote_sender_id() == SERVER_ID and not _closing


func _matches_session(data: Dictionary) -> bool:
	return not data.has("session_id") or String(data["session_id"]) == session_id


func _reject_peer(peer_id: int, reason: String) -> void :
	if not is_host() or _peer == null or _rejections.has(peer_id):
		return
	_pending.erase(peer_id)
	_rpc_reject.rpc_id(peer_id, reason)
	_rejections[peer_id] = Time.get_ticks_msec() + REJECT_DELAY_MS


func _can_start() -> bool:
	if not is_host() or phase != "lobby" or members.is_empty():
		return false
	for member: Dictionary in members.values():
		if not bool(member.get("ready", false)):
			return false
	return true


func _roster() -> Array:
	var result: Array = []
	var ids: Array = members.keys()
	ids.sort()
	for peer_id: int in ids:
		result.append(members[peer_id].duplicate(true))
	return result


func _lobby_data(recipient_id: int) -> Dictionary:
	var data: Dictionary = lobby_config.duplicate(true)
	data["players"] = _roster()
	data["local_id"] = recipient_id
	data["can_start"] = _can_start()
	data["phase"] = phase
	data["session_id"] = session_id
	data["lobby_epoch"] = _lobby_epoch
	return data


func _start_data() -> Dictionary:
	var data: Dictionary = lobby_config.duplicate(true)
	data["session_id"] = session_id
	data["players"] = _roster()
	data["phase"] = "playing"
	return data


func _broadcast_lobby() -> void :
	if not is_host():
		return
	for peer_id: int in members.keys():
		if peer_id != SERVER_ID:
			_rpc_lobby.rpc_id(peer_id, _lobby_data(peer_id))
	lobby_changed.emit(_lobby_data(SERVER_ID))


func _apply_lobby(data: Dictionary) -> void :
	var roster: Array = data.get("players", [])
	var approved: Dictionary = {}
	for entry: Dictionary in roster:
		approved[int(entry.get("id", 0))] = entry.duplicate(true)
	if not approved.has(local_id):
		return

	var departed: Array = []
	for peer_id: int in members.keys():
		if not approved.has(peer_id):
			departed.append(peer_id)
	members = approved
	for key: String in ["room_name", "host_ip", "max_players", "shift_seconds", "team_goal_per_player"]:
		lobby_config[key] = data.get(key, lobby_config.get(key))
	lobby_config["shift_mode"] = TeamShiftRules.normalize_mode(data.get("shift_mode", "competitive"))
	phase = String(data.get("phase", "lobby"))
	session_id = String(data.get("session_id", ""))
	_lobby_epoch = int(data.get("lobby_epoch", _lobby_epoch))
	for peer_id: int in departed:
		peer_left.emit(peer_id)
	lobby_changed.emit(data.duplicate(true))


func _reset_transport() -> void :
	_closing = true

	role = "offline"
	phase = "offline"
	local_id = 0
	session_id = ""
	members.clear()
	lobby_config.clear()
	_pending.clear()
	_rejections.clear()
	_local_profile.clear()
	_connecting_since = 0
	_lobby_epoch = 0
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_closing = false


func _member(peer_id: int, profile: Dictionary, ready: bool) -> Dictionary:
	return {"id": peer_id, "name": profile["player_name"], "profile": profile.duplicate(true), "ready": ready,
		"appearance": CosmeticCatalog.sanitize_profile(profile)["appearance"]}


func _sanitize_profile(source: Dictionary) -> Dictionary:
	var raw_name: Variant = source.get("player_name", "Courier")
	var public_name: String = raw_name if raw_name is String else "Courier"
	var result: Dictionary = {"version": 1, "player_name": _clean_text(public_name, 32, "Courier")}
	for key: String in ["money", "xp", "total_deliveries", "express_deliveries", "total_money_earned", "best_shift"]:
		var value: Variant = source.get(key, 0)
		result[key] = 0
		if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0:
			result[key] = int(minf(float(value), float(PROFILE_LIMIT)))
	var level: int = 1
	while level < 10 and int(result["xp"]) >= level * level * 150:
		level += 1
	result["level"] = level
	result["rank"] = _rank_for_level(level)
	result.merge(VehicleCatalog.sanitize_profile_vehicles(source))
	result.merge(CosmeticCatalog.sanitize_profile(source), true)
	return result


func _rank_for_level(level: int) -> String:
	if level >= 10:
		return "Delivery Master"
	if level >= 6:
		return "Express Pro"
	if level >= 4:
		return "Fast Courier"
	if level >= 2:
		return "City Courier"
	return "Rookie Courier"


func _clean_text(value: String, limit: int, fallback: String) -> String:
	var clean: String = ""

	for index: int in mini(value.length(), limit * 4):
		var code: int = value.unicode_at(index)
		if code >= 32 and code != 127:
			clean += value.substr(index, 1)
		elif not clean.ends_with(" "):
			clean += " "
	clean = clean.strip_edges().left(limit)
	return fallback if clean.is_empty() else clean


func _normalize_address(address: String) -> String:
	var clean: String = address.strip_edges()
	if clean.to_lower() == "localhost":
		return "127.0.0.1"
	var octets: PackedStringArray = clean.split(".")
	if octets.size() != 4:
		return ""
	var normalized: PackedStringArray = []
	for octet: String in octets:
		if octet.is_empty() or octet.length() > 3:
			return ""
		for index: int in octet.length():
			var code: int = octet.unicode_at(index)
			if code < 48 or code > 57:
				return ""
		var value: int = int(octet)
		if value > 255:
			return ""
		normalized.append(str(value))
	var result: String = ".".join(normalized)
	return "" if result in ["0.0.0.0", "255.255.255.255"] else result


func _local_address() -> String:
	for address: String in IP.get_local_addresses():
		var valid: String = _normalize_address(address)
		if not valid.is_empty() and not valid.begins_with("127.") and not valid.begins_with("169.254."):
			return valid
	return "127.0.0.1"
