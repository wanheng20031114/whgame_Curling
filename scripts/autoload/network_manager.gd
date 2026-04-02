# ============================================================================
# network_manager.gd — 全局网络管理器（Autoload 单例）
# ============================================================================
# 职责：
#   1. 管理 ENet 连接（创建服务器 / 连接到服务器）
#   2. 管理已连接的玩家信息
#   3. 提供网络层的信号供其他模块监听
#   4. 大厅房间管理（服务器端）
#
# 架构说明（参考 DESIGN.md 第 3 节）：
#   - 公网 ENet 专用服务器模式
#   - 所有数据（大厅、准备、游戏）全部经过服务器转发
#   - 全程使用同一条 ENet 连接
#   - 服务器拥有完全权威
# ============================================================================

extends Node

# ============================================================================
# 信号定义
# ============================================================================

## 成功连接到服务器（仅客户端触发）
signal connected_to_server()

## 连接服务器失败（仅客户端触发）
signal connection_failed()

## 与服务器断开连接（仅客户端触发）
signal disconnected_from_server()

## 有新玩家加入（服务器和客户端都会触发）
signal player_connected(peer_id: int, username: String)

## 有玩家离开（服务器和客户端都会触发）
signal player_disconnected(peer_id: int)

## 收到大厅房间列表更新
signal lobby_updated(rooms: Array)

# ============================================================================
# 数据结构
# ============================================================================

## 玩家信息字典
## 格式：{ peer_id: int -> { "username": String, "room_id": int, "team": int } }
var players: Dictionary = {}

## 房间列表（仅服务器端维护完整数据）
## 格式：[{ "id": int, "name": String, "host_id": int, "players": Array,
##          "max_players": int, "rounds": int, "state": String }]
var rooms: Array = []

## 下一个房间 ID（服务器端自增）
var _next_room_id: int = 1

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 连接 Godot 多人游戏框架的内置信号
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ============================================================================
# 公开方法 — 连接管理
# ============================================================================

## 创建 ENet 服务器（服务器模式调用）
## @param port: 监听端口
## @param max_clients: 最大客户端数量
func create_server(port: int, max_clients: int = 8) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, max_clients)
	
	if error != OK:
		print("[NetworkManager] ❌ 创建服务器失败！错误码: ", error)
		return error
	
	# 将 ENet peer 设置为当前多人游戏的传输层
	multiplayer.multiplayer_peer = peer
	
	# 服务器自身的 peer_id 固定为 1
	print("[NetworkManager] ✅ 服务器创建成功，端口: %d，peer_id: %d" % [port, multiplayer.get_unique_id()])
	return OK


## 连接到服务器（客户端模式调用）
## @param address: 服务器 IP 或域名
## @param port: 服务器端口
func connect_to_server(address: String, port: int) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	
	if error != OK:
		print("[NetworkManager] ❌ 连接失败！错误码: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] 正在连接到 %s:%d ..." % [address, port])
	return OK


## 断开连接
func disconnect_from_server() -> void:
	print("[NetworkManager] 断开连接")
	multiplayer.multiplayer_peer = null
	players.clear()
	rooms.clear()


## 获取本地 peer_id
func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


## 判断当前是否为服务器端
func is_server() -> bool:
	return multiplayer.is_server()


# ============================================================================
# RPC 方法 — 玩家注册
# ============================================================================

## 客户端调用：向服务器注册自己的用户名
## @rpc("any_peer", "reliable") 表示任何 peer 都可以调用，且使用可靠传输
@rpc("any_peer", "reliable")
func register_player(username: String) -> void:
	# 此函数在服务器端执行
	var sender_id: int = multiplayer.get_remote_sender_id()
	print("[NetworkManager] 玩家注册 - peer_id: %d, 用户名: %s" % [sender_id, username])
	
	# 存储玩家信息
	players[sender_id] = {
		"username": username,
		"room_id": -1,  # -1 表示不在任何房间中
		"team": -1,     # -1 表示未选队
	}
	
	# 通知所有客户端有新玩家加入
	_sync_player_joined.rpc(sender_id, username)
	
	# 向新加入的玩家发送完整的旧玩家列表（解决"问号"或"未知"的问题）
	_sync_all_players.rpc_id(sender_id, players)
	
	# 向新加入的玩家发送当前房间列表
	_sync_room_list.rpc_id(sender_id, rooms)


## 服务器下发：将所有的玩家列表完整地同步给某个客户端
@rpc("authority", "reliable")
func _sync_all_players(all_players: Dictionary) -> void:
	# 由于 JSON 序列化的键会变成字符串，我们需要转回 int
	players.clear()
	for pid_str in all_players:
		players[int(pid_str)] = all_players[pid_str]
	print("[NetworkManager] 本地已同步全服 %d 名玩家数据" % players.size())


## 服务器广播：通知所有客户端有新玩家加入
@rpc("authority", "reliable")
func _sync_player_joined(peer_id: int, username: String) -> void:
	players[peer_id] = {
		"username": username,
		"room_id": -1,
		"team": -1,
	}
	player_connected.emit(peer_id, username)
	print("[NetworkManager] 玩家加入: %s (peer_id: %d)" % [username, peer_id])


## 服务器广播：同步房间列表给客户端
@rpc("authority", "reliable")
func _sync_room_list(room_list: Array) -> void:
	rooms = room_list
	lobby_updated.emit(rooms)
	print("[NetworkManager] 房间列表已更新，共 %d 个房间" % rooms.size())


# ============================================================================
# RPC 方法 — 房间管理
# ============================================================================

## 客户端调用：请求创建房间
@rpc("any_peer", "reliable")
func request_create_room(room_name: String, rounds: int) -> void:
	# 仅在服务器端执行
	var sender_id: int = multiplayer.get_remote_sender_id()
	var username: String = players.get(sender_id, {}).get("username", "未知")
	
	print("[NetworkManager] 玩家 %s 请求创建房间: %s (局数: %d)" % [username, room_name, rounds])
	
	# 创建房间数据
	var room: Dictionary = {
		"id": _next_room_id,
		"name": room_name,
		"host_id": sender_id,       # 房主的 peer_id
		"players": [sender_id],      # 房间内的玩家列表
		"max_players": 8,            # 最大 8 人（两队各 4 人）
		"rounds": rounds,            # 比赛局数
		"state": "waiting",          # 房间状态：waiting / preparing / playing
	}
	rooms.append(room)
	_next_room_id += 1
	
	# 更新该玩家的房间信息
	if sender_id in players:
		players[sender_id]["room_id"] = room["id"]
	
	# 广播更新后的房间列表给所有人
	_sync_room_list.rpc(rooms)
	
	# 房主创建后自动进入准备阶段（选边）
	# 使用 call_deferred 确保 RPC 先发出
	call_deferred("_trigger_enter_prep", sender_id, room)
	
	print("[NetworkManager] 房间创建成功: %s (ID: %d)" % [room_name, room["id"]])


## 客户端调用：请求加入房间
@rpc("any_peer", "reliable")
func request_join_room(room_id: int) -> void:
	# 仅在服务器端执行
	var sender_id: int = multiplayer.get_remote_sender_id()
	
	# 查找目标房间
	for room in rooms:
		if room["id"] == room_id:
			# 检查房间是否已满
			if room["players"].size() >= room["max_players"]:
				print("[NetworkManager] 房间 %d 已满，拒绝玩家 %d" % [room_id, sender_id])
				return
			
			# 检查房间状态（允许在 waiting 或 preparing 时加入）
			if room["state"] not in ["waiting", "preparing"]:
				print("[NetworkManager] 房间 %d 状态为 %s，拒绝加入" % [room_id, room["state"]])
				return
			
			# 加入房间
			room["players"].append(sender_id)
			if sender_id in players:
				players[sender_id]["room_id"] = room_id
			
			# 广播更新
			_sync_room_list.rpc(rooms)
			
			# 新玩家加入后也进入准备阶段
			call_deferred("_trigger_enter_prep", sender_id, room)
			
			print("[NetworkManager] 玩家 %d 加入房间 %d" % [sender_id, room_id])
			return
	
	print("[NetworkManager] 房间 %d 不存在" % room_id)


# ============================================================================
# 房间流程辅助方法
# ============================================================================

## 触发玩家进入准备阶段（服务器端调用）
## 向指定玩家发送准备阶段通知
func _trigger_enter_prep(peer_id: int, room: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	
	# 更新房间状态
	room["state"] = "preparing"
	
	# 通知该玩家进入准备阶段
	GameSync.notify_enter_prep.rpc_id(peer_id, room)
	
	# 必须把当前房间里已经选了队伍的老玩家的数据单发给这位新玩家，否则他看别人是未选边
	var team_data: Dictionary = {}
	for pid in room["players"]:
		team_data[str(pid)] = players.get(pid, {}).get("team", -1)
	GameSync.sync_team_data.rpc_id(peer_id, team_data)
	
	print("[NetworkManager] 通知玩家 %d 进入准备阶段" % peer_id)


# ============================================================================
# 内部信号回调
# ============================================================================

## 有新的 peer 连接
func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer 连接: %d" % id)


## 有 peer 断开
func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer 断开: %d" % id)
	
	# 从玩家列表和房间中移除
	if id in players:
		var room_id: int = players[id].get("room_id", -1)
		# 从房间中移除该玩家
		if room_id > 0:
			for room in rooms:
				if room["id"] == room_id:
					room["players"].erase(id)
					# 如果房间空了，删除房间
					if room["players"].is_empty():
						rooms.erase(room)
					# 如果房主离开，转移房主
					elif room["host_id"] == id and not room["players"].is_empty():
						room["host_id"] = room["players"][0]
					break
		
		players.erase(id)
		
		# 广播更新
		if multiplayer.is_server():
			_sync_room_list.rpc(rooms)
	
	player_disconnected.emit(id)


## 成功连接到服务器（仅客户端触发）
func _on_connected_to_server() -> void:
	print("[NetworkManager] ✅ 已连接到服务器！peer_id: %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


## 连接失败（仅客户端触发）
func _on_connection_failed() -> void:
	print("[NetworkManager] ❌ 连接服务器失败！")
	connection_failed.emit()


## 服务器断开（仅客户端触发）
func _on_server_disconnected() -> void:
	print("[NetworkManager] ⚠️ 与服务器断开连接")
	players.clear()
	rooms.clear()
	disconnected_from_server.emit()
