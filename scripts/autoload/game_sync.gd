# ============================================================================
# game_sync.gd — 游戏内网络同步管理器（Autoload 单例）
# ============================================================================
# 职责（参考 DESIGN.md 3.3 ~ 3.5）：
#   1. 投壶参数网络同步（客户端→服务器→广播）
#   2. 冰壶物理状态广播（服务器→所有客户端，每帧位置+角度）
#   3. 擦冰操作同步（客户端→服务器）
#   4. 回合控制同步（服务器→所有客户端）
#   5. 得分广播（服务器→所有客户端）
#   6. 房间流程协调（加入房间→选边→选位→开始游戏→结算→返回大厅）
#
# 为什么独立为一个 Autoload？
#   NetworkManager 负责连接层面（登录、大厅、房间管理），
#   GameSync 负责游戏进行中的实时同步。
#   这样解耦后，场景切换时不会丢失同步状态。
# ============================================================================

extends Node

# ============================================================================
# 信号定义
# ============================================================================

## 收到投壶命令（客户端收到服务器广播后触发）
signal throw_received(direction: Vector2, power: float, spin: int, team: int, stone_index: int)

## 收到冰壶位置同步
signal stones_sync_received(stones_data: Array)

## 收到擦冰状态变化
signal sweep_state_changed(is_sweeping: bool)

## 收到回合变更通知
signal turn_changed(throw_index: int, current_team: int, position_index: int, stone_number: int)

## 收到得分广播
signal score_received(round_score: Dictionary, round_scores: Array, red_total: int, blue_total: int)

## 收到一局结束通知
signal round_ended()

## 收到比赛结束通知
signal game_ended(red_total: int, blue_total: int, round_scores: Array)

## 收到准备阶段（选队）的队伍数据更新
signal team_data_updated(team_data: Dictionary)

## 收到准备阶段（选位）的槽位数据更新
signal role_slots_updated(slot_assignments: Dictionary)

## 收到准备阶段（选位）的准备状态更新
signal ready_states_updated(ready_states: Dictionary)

## 收到进入准备阶段通知
signal enter_prep_phase(room_data: Dictionary)

## 收到房间数据更新（如新玩家加入）
signal room_data_updated(room_data: Dictionary)

## 收到返回大厅通知
signal return_to_lobby()

# ============================================================================
# 状态变量
# ============================================================================

## 当前房间数据（客户端和服务器都持有一份）
var current_room: Dictionary = {}

## 【选位阶段】槽位分配表 (服务器权威)
var slot_assignments: Dictionary = {}

## 【选位阶段】各玩家准备状态 (服务器权威)
var ready_states: Dictionary = {}

## 物理同步帧率（每秒发送多少次位置更新）
## 参考 DESIGN.md 3.5：使用不可靠传输发送高频物理数据
var sync_fps: int = 20

## 同步计时器
var _sync_timer: float = 0.0

## 当前游戏主场景引用（服务器端用于获取冰壶位置）
var _game_main_ref: Node2D = null

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	print("[GameSync] 游戏同步管理器初始化")


func _physics_process(delta: float) -> void:
	# 仅服务器端执行物理状态广播
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if _game_main_ref == null:
		return
	
	# 按固定频率广播冰壶位置
	_sync_timer += delta
	var interval: float = 1.0 / sync_fps
	if _sync_timer >= interval:
		_sync_timer -= interval
		_broadcast_stones_positions()


# ============================================================================
# 公开方法 — 由 game_main.gd 调用
# ============================================================================

## 注册游戏主场景引用（场景加载后调用）
func register_game_main(game_main: Node2D) -> void:
	_game_main_ref = game_main
	print("[GameSync] 游戏主场景已注册")


## 注销游戏主场景引用（场景卸载时调用）
func unregister_game_main() -> void:
	_game_main_ref = null
	print("[GameSync] 游戏主场景已注销")


# ============================================================================
# RPC 方法 — 投壶同步（DESIGN.md 3.5）
# ============================================================================

## 客户端 → 服务器：发送投壶参数
## 投壶手客户端在释放冰壶时调用此方法
@rpc("any_peer", "reliable")
func send_throw_params(direction: Vector2, power: float, spin: int) -> void:
	# 仅在服务器端执行
	var sender_id: int = multiplayer.get_remote_sender_id()
	print("[GameSync] 收到投壶参数 - 来自 peer %d, 方向: %s, 力度: %.1f, 旋转: %d" % [
		sender_id, direction, power, spin
	])
	
	# TODO: 验证该玩家是否是当前投壶手
	
	# 获取当前投壶队伍和壶号（从 game_main 获取）
	var team: int = 0
	var stone_idx: int = 1
	if _game_main_ref:
		team = _game_main_ref._get_current_team()
		stone_idx = _game_main_ref._get_current_stone_number()
	
	# 服务器本地执行投壶（物理模拟在服务器端运行）
	if _game_main_ref:
		_game_main_ref._server_throw_stone(direction, power, spin)
	
	# 广播给所有客户端（让客户端也实例化冰壶做视觉展示）
	_broadcast_throw.rpc(direction, power, spin, team, stone_idx)


## 服务器 → 所有客户端：广播投壶
@rpc("authority", "reliable")
func _broadcast_throw(direction: Vector2, power: float, spin: int, team: int, stone_index: int) -> void:
	print("[GameSync] 收到投壶广播 - 队伍: %d, 壶 #%d" % [team, stone_index])
	throw_received.emit(direction, power, spin, team, stone_index)


# ============================================================================
# RPC 方法 — 冰壶位置同步（DESIGN.md 3.5）
# ============================================================================

## 服务器端内部调用：广播所有冰壶的当前位置和角度
## 使用 unreliable 传输（高频数据，丢包可接受）
func _broadcast_stones_positions() -> void:
	if _game_main_ref == null:
		return
	
	var stones_data: Array = []
	for stone in _game_main_ref.active_stones:
		if is_instance_valid(stone) and not stone.is_out_of_bounds:
			stones_data.append({
				"team": stone.team,
				"index": stone.stone_index,
				"pos_x": stone.global_position.x,
				"pos_y": stone.global_position.y,
				"rot": stone.rotation,
				"stopped": stone.is_stopped,
			})
	
	if stones_data.size() > 0:
		_sync_stones.rpc(stones_data)


## 服务器 → 所有客户端：同步冰壶位置
## 使用 unreliable 获得更低延迟（位置数据丢几帧没关系）
@rpc("authority", "unreliable")
func _sync_stones(stones_data: Array) -> void:
	stones_sync_received.emit(stones_data)


# ============================================================================
# RPC 方法 — 擦冰同步（DESIGN.md 3.5）
# ============================================================================

## 客户端 → 服务器：发送擦冰状态
@rpc("any_peer", "unreliable")
func send_sweep(is_sweeping: bool) -> void:
	# 仅在服务器端执行
	# TODO: 验证该玩家是否是当前擦冰员
	if _game_main_ref and _game_main_ref.current_sliding_stone:
		_game_main_ref.current_sliding_stone.set_sweep(is_sweeping)
	
	# 广播给其他客户端（视觉效果）
	_broadcast_sweep.rpc(is_sweeping)


## 服务器 → 所有客户端：广播擦冰状态
@rpc("authority", "unreliable")
func _broadcast_sweep(is_sweeping: bool) -> void:
	sweep_state_changed.emit(is_sweeping)


# ============================================================================
# RPC 方法 — 回合控制（DESIGN.md 3.3 游戏中阶段）
# ============================================================================

## 服务器 → 所有客户端：通知回合变更
@rpc("authority", "reliable")
func sync_turn(throw_index: int, current_team: int, position_index: int, stone_number: int) -> void:
	print("[GameSync] 回合变更: 投壶 #%d, %s %s #%d壶" % [
		throw_index + 1,
		"红队" if current_team == 0 else "蓝队",
		["一垒", "二垒", "三垒", "四垒"][position_index],
		stone_number
	])
	turn_changed.emit(throw_index, current_team, position_index, stone_number)


## 服务器 → 所有客户端：通知一局结束和得分
@rpc("authority", "reliable")
func sync_round_score(round_score: Dictionary, all_round_scores: Array, red_total: int, blue_total: int) -> void:
	print("[GameSync] 本局得分: 红 %d  蓝 %d (总 红 %d : %d 蓝)" % [
		round_score.get("red", 0), round_score.get("blue", 0), red_total, blue_total
	])
	score_received.emit(round_score, all_round_scores, red_total, blue_total)
	round_ended.emit()


## 服务器 → 所有客户端：通知比赛结束
@rpc("authority", "reliable")
func sync_game_end(red_total: int, blue_total: int, all_round_scores: Array) -> void:
	print("[GameSync] ===== 比赛结束！红 %d : %d 蓝 =====" % [red_total, blue_total])
	game_ended.emit(red_total, blue_total, all_round_scores)


# ============================================================================
# RPC 方法 — 房间流程协调（DESIGN.md 3.3 各阶段跳转）
# ============================================================================

## 服务器 → 房间内所有客户端：进入准备阶段（选边）
## 当房主点击"开始准备"或房间满足条件时调用
@rpc("authority", "reliable")
func notify_enter_prep(room_data: Dictionary) -> void:
	print("[GameSync] 收到进入准备阶段通知")
	current_room = room_data
	enter_prep_phase.emit(room_data)
	GameManager.go_to_prep_team()

@rpc("authority", "reliable")
func sync_room_data(data: Dictionary) -> void:
	print("[GameSync] 收到房间数据更新")
	current_room = data
	room_data_updated.emit(data)

## 服务器 → 房间内所有客户端：进入游戏
@rpc("authority", "reliable")
func notify_enter_game(room_data: Dictionary) -> void:
	print("[GameSync] 收到开始游戏通知")
	current_room = room_data
	GameManager.go_to_game()


## 服务器 → 房间内所有客户端：返回大厅
@rpc("authority", "reliable")
func notify_return_lobby() -> void:
	print("[GameSync] 收到返回大厅通知")
	current_room = {}
	return_to_lobby.emit()
	GameManager.go_to_lobby()


# ============================================================================
# RPC 方法 — 选边阶段（来自原 prep_team_select）
# ============================================================================

@rpc("any_peer", "reliable")
func request_join_team(team: int) -> void:
	if not multiplayer.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	
	if sender_id in NetworkManager.players:
		NetworkManager.players[sender_id]["team"] = team
	
	var room_id: int = NetworkManager.players.get(sender_id, {}).get("room_id", -1)
	var room: Dictionary = _find_room(room_id)
	if room.is_empty(): return
	
	var team_data: Dictionary = {}
	# 仅下发此房间内的队伍数据
	for peer_id in room["players"]:
		team_data[str(peer_id)] = NetworkManager.players.get(peer_id, {}).get("team", -1)
	
	for peer_id in room["players"]:
		sync_team_data.rpc_id(peer_id, team_data)


@rpc("authority", "reliable")
func sync_team_data(team_data: Dictionary) -> void:
	for peer_id_str in team_data:
		var peer_id: int = int(peer_id_str)
		if peer_id in NetworkManager.players:
			NetworkManager.players[peer_id]["team"] = team_data[peer_id_str]
	team_data_updated.emit(team_data)

@rpc("any_peer", "reliable")
func request_start_role_select() -> void:
	if not multiplayer.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var room_id: int = NetworkManager.players.get(sender_id, {}).get("room_id", -1)
	var room: Dictionary = _find_room(room_id)
	if room.is_empty(): return
	
	var red_count: int = 0
	var blue_count: int = 0
	for peer_id in room["players"]:
		var team: int = NetworkManager.players.get(peer_id, {}).get("team", -1)
		if team == 0: red_count += 1
		elif team == 1: blue_count += 1
	
	if red_count >= 1 and blue_count >= 1:
		room["state"] = "role_selecting"  # 锁定房间状态，大厅玩家无法再加入
		NetworkManager._sync_room_list.rpc(NetworkManager.rooms)
		
		for peer_id in room["players"]:
			notify_enter_role_select.rpc_id(peer_id)

@rpc("authority", "reliable")
func notify_enter_role_select() -> void:
	print("[GameSync] 收到选位置阶段通知")
	GameManager.go_to_prep_role()


# ============================================================================
# RPC 方法 — 选位阶段（来自原 prep_role_select）
# ============================================================================

@rpc("any_peer", "reliable")
func request_toggle_slot(slot_key: String) -> void:
	if not multiplayer.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	
	if slot_assignments.get(slot_key) == sender_id:
		slot_assignments.erase(slot_key)
	elif slot_key not in slot_assignments:
		slot_assignments[slot_key] = sender_id
	else:
		return
	var room_id: int = NetworkManager.players.get(sender_id, {}).get("room_id", -1)
	var room: Dictionary = _find_room(room_id)
	if room.is_empty(): return
	
	for peer_id in room["players"]:
		sync_slots.rpc_id(peer_id, slot_assignments)

@rpc("authority", "reliable")
func sync_slots(data: Dictionary) -> void:
	slot_assignments = data
	role_slots_updated.emit(data)

@rpc("any_peer", "reliable")
func request_player_ready(is_ready: bool) -> void:
	if not multiplayer.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	ready_states[sender_id] = is_ready
	var room_id: int = NetworkManager.players.get(sender_id, {}).get("room_id", -1)
	var room: Dictionary = _find_room(room_id)
	if room.is_empty(): return
	
	for peer_id in room["players"]:
		sync_ready_states.rpc_id(peer_id, ready_states)
	
	_check_start_conditions(sender_id)

@rpc("authority", "reliable")
func sync_ready_states(data: Dictionary) -> void:
	ready_states = data
	ready_states_updated.emit(data)

func _check_start_conditions(sender_id: int) -> void:
	var room_id: int = NetworkManager.players.get(sender_id, {}).get("room_id", -1)
	var room: Dictionary = _find_room(room_id)
	if room.is_empty(): return

	if slot_assignments.size() < 16: return
	for peer_id in room["players"]:
		if not ready_states.get(peer_id, false): return
	
	# 所有人都准备好了，开启游戏
	server_start_game(room_id)


# ============================================================================
# 服务器端方法 — 房间流程触发
# ============================================================================

## 服务器端调用：让房间内所有玩家进入准备阶段
func server_start_prep(room_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var room: Dictionary = _find_room(room_id)
	if room.is_empty():
		return
	
	room["state"] = "preparing"
	
	# 向房间内所有玩家发送通知
	for peer_id in room["players"]:
		notify_enter_prep.rpc_id(peer_id, room)
	
	# 广播更新后的房间列表（大厅其他人看到状态变化）
	NetworkManager._sync_room_list.rpc(NetworkManager.rooms)
	
	print("[GameSync] 房间 %d 进入准备阶段" % room_id)


## 服务器端调用：让房间内所有玩家开始游戏
func server_start_game(room_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var room: Dictionary = _find_room(room_id)
	if room.is_empty():
		return
	
	room["state"] = "playing"
	
	# 向房间内所有玩家发送通知
	for peer_id in room["players"]:
		notify_enter_game.rpc_id(peer_id, room)
	
	# 服务器自身也需要加载游戏场景来运行物理模拟
	# 使用 call_deferred 确保 RPC 先发出
	call_deferred("_server_load_game_scene", room)
	
	# 广播更新后的房间列表
	NetworkManager._sync_room_list.rpc(NetworkManager.rooms)
	
	print("[GameSync] 房间 %d 开始游戏" % room_id)


## 服务器端调用：比赛结束，让房间内所有玩家返回大厅
func server_end_game(room_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var room: Dictionary = _find_room(room_id)
	if room.is_empty():
		return
	
	room["state"] = "waiting"
	
	# 重置玩家队伍信息
	for peer_id in room["players"]:
		if peer_id in NetworkManager.players:
			NetworkManager.players[peer_id]["team"] = -1
		notify_return_lobby.rpc_id(peer_id)
	
	# 广播更新
	NetworkManager._sync_room_list.rpc(NetworkManager.rooms)
	
	print("[GameSync] 房间 %d 游戏结束，返回大厅" % room_id)


# ============================================================================
# 服务器端内部方法
# ============================================================================

## 服务器端加载游戏场景（用于运行权威物理模拟）
## 服务器 headless 模式下，场景树中会有一个 game_main 实例
func _server_load_game_scene(room: Dictionary) -> void:
	print("[GameSync] 服务器加载游戏场景进行物理模拟...")
	
	# 加载游戏主场景
	var game_scene: PackedScene = load("res://scenes/game/game_main.tscn")
	if game_scene == null:
		print("[GameSync] ❌ 无法加载游戏场景！")
		return
	
	var game_instance: Node2D = game_scene.instantiate()
	
	# 设置总局数（从房间配置获取）
	game_instance.total_rounds = room.get("rounds", 8)
	
	# 标记为服务器端实例（game_main 内部会根据此判断是否执行物理）
	game_instance.set_meta("is_server_instance", true)
	
	# 添加到场景树
	get_tree().root.add_child(game_instance)
	
	print("[GameSync] ✅ 服务器游戏场景已加载，局数: %d" % room.get("rounds", 8))


## 查找房间（服务器端）
func _find_room(room_id: int) -> Dictionary:
	for room in NetworkManager.rooms:
		if room["id"] == room_id:
			return room
	return {}
