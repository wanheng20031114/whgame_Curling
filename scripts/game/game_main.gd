# ============================================================================
# game_main.gd — 游戏主场景控制脚本
# ============================================================================
# 对应场景：scenes/game/game_main.tscn
# 参考 DESIGN.md 第 5.2 节（游戏主场景节点树）、第 2 节（冰壶规则）
#
# 职责：
#   1. 回合管理（TurnManager 逻辑）
#   2. 冰壶实例化和管理
#   3. 投壶操作交互（瞄准、蓄力、旋转选择）
#   4. 擦冰操作
#   5. 得分计算（ScoreCalculator 逻辑）
#   6. 协调 HUD 和相机
#   7. 网络同步（RPC 接收/发送）
#
# 投壶流程（参考 DESIGN.md 2.4 + 6.3）：
#   瞄准阶段 → 蓄力/释放 → 冰壶滑行 + 擦冰 → 停止 → 下一壶
# ============================================================================

extends Node2D

# ============================================================================
# 预加载
# ============================================================================

## 冰壶预制体
const CurlingStoneScene: PackedScene = preload("res://scenes/game/curling_stone.tscn")

# ============================================================================
# 节点引用
# ============================================================================

@onready var curling_sheet: Node2D = $CurlingSheet          ## 赛道
@onready var stones_container: Node2D = $StonesContainer    ## 冰壶容器
@onready var game_camera: Camera2D = $GameCamera            ## 相机
@onready var game_hud: CanvasLayer = $GameHUD                ## HUD

var aim_overlay: Node2D                                     ## 瞄准显示层


# ============================================================================
# 游戏状态常量
# ============================================================================

## 每队每局壶数（参考 DESIGN.md 2.1：每队 8 壶）
const STONES_PER_TEAM: int = 8

## 投壶顺序表：交替投壶，每个位置投 2 壶
## 索引对应第几次投壶（0~15）→ { team, position_index, stone_number }
## 双方交替：红1 蓝1 红2 蓝2 ... 红8 蓝8

# ============================================================================
# 游戏状态
# ============================================================================

## 当前局数（从 1 开始）
var current_round: int = 1

## 总局数
var total_rounds: int = 8

## 当前是第几次投壶（每局 0~15，双方合计 16 壶交替投）
var current_throw_index: int = 0

## 后手方（0=红, 1=蓝，拥有后手的队伍在每局最后投壶）
var hammer_team: int = 1

## 各队本局剩余壶数
var stones_left: Array[int] = [8, 8]

## 逐局得分记录
var round_scores: Array = []  # [{ "red": int, "blue": int }, ...]

## 红队和蓝队总分
var red_total_score: int = 0
var blue_total_score: int = 0

## 场上所有冰壶引用列表
var active_stones: Array = []

## 当前投壶阶段
enum ThrowPhase {
	WAITING,      ## 等待（非当前投壶手）
	AIMING,       ## 瞄准中（选择方向）
	CHARGING,     ## 蓄力中（按住鼠标）
	SWEEPING,     ## 冰壶滑行中（擦冰阶段）
	ROUND_END,    ## 一局结束（得分判定展示）
}

var throw_phase: ThrowPhase = ThrowPhase.WAITING

## 当前投壶参数
var aim_direction: Vector2 = Vector2.UP      ## 瞄准方向
var aim_angle: float = 0.0                    ## 瞄准角度（弧度）
var charge_power: float = 0.0                 ## 蓄力值（0~1）
var selected_spin: int = 0                    ## 旋转方向：-1/0/1

## 蓄力相关
var is_charging: bool = false
var charge_speed: float = 1.5                  ## 蓄力速度（每秒填满比例）

## 当前正在滑行的冰壶
var current_sliding_stone: RigidBody2D = null

## 是否为联网模式（有 multiplayer peer 且已连接）
var is_networked: bool = false

## 是否为服务器端实例（服务器负责物理模拟）
var is_server_instance: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 判断是否联网模式
	is_networked = multiplayer.has_multiplayer_peer()
	is_server_instance = has_meta("is_server_instance") and get_meta("is_server_instance")
	
	# 注册到 GameSync（让同步管理器能读取我们的冰壶数据）
	GameSync.register_game_main(self)
	
	# 联网模式下，客户端连接 GameSync 信号接收服务器广播
	if is_networked and not is_server_instance:
		GameSync.throw_received.connect(_on_throw_received)
		GameSync.stones_sync_received.connect(_on_stones_sync)
		GameSync.sweep_state_changed.connect(_on_sweep_sync)
		GameSync.turn_changed.connect(_on_turn_sync)
		GameSync.score_received.connect(_on_score_sync)
		GameSync.game_ended.connect(_on_game_ended_sync)
	
	# 初始化游戏
	_init_round()
	
	# 设置全局层级（主体层级为0）
	z_index = 0
	
	# 动态创建高层级 Overlay 用于绘制瞄准线（解决层级被赛道遮挡问题）
	aim_overlay = Node2D.new()
	aim_overlay.name = "AimOverlay"
	aim_overlay.z_index = 100 # 极高层级，确保在所有物体之上
	add_child(aim_overlay)
	aim_overlay.draw.connect(_on_aim_overlay_draw)
	
	print("[GameMain] 游戏主场景已加载，总局数: %d, 联网: %s, 服务器: %s" % [
		total_rounds, is_networked, is_server_instance
	])
	
	# 初始化 HUD 的队伍显示
	if not is_server_instance:
		var my_id: int = NetworkManager.get_local_peer_id()
		var my_team: int = NetworkManager.players.get(my_id, {}).get("team", -1)
		game_hud.update_my_team(my_team)


func _exit_tree() -> void:
	# 场景卸载时注销
	GameSync.unregister_game_main()


func _process(delta: float) -> void:
	match throw_phase:
		ThrowPhase.AIMING:
			_process_aiming(delta)
		ThrowPhase.CHARGING:
			_process_charging(delta)
		ThrowPhase.SWEEPING:
			_process_sweeping(delta)


func _unhandled_input(event: InputEvent) -> void:
	# 检查是否轮到我操作（网络模式下，非法回合忽略输入）
	if is_networked and not _is_my_turn():
		return
		
	match throw_phase:
		ThrowPhase.AIMING:
			_input_aiming(event)
		ThrowPhase.CHARGING:
			_input_charging(event)
		ThrowPhase.SWEEPING:
			_input_sweeping(event)


# ============================================================================
# 游戏初始化
# ============================================================================

## 初始化一局（开始新的一局）
func _init_round() -> void:
	current_throw_index = 0
	stones_left = [8, 8]
	
	# 清除场上所有冰壶
	for stone in active_stones:
		if is_instance_valid(stone):
			stone.queue_free()
	active_stones.clear()
	
	# 更新 HUD
	_update_hud()
	
	# 相机回到投壶端
	game_camera.return_to_spawn()
	
	# 开始第一次投壶
	_start_next_throw()
	
	print("[GameMain] === 第 %d 局开始 ===" % current_round)


## 开始下一次投壶
func _start_next_throw() -> void:
	if current_throw_index >= 16:
		# 16 壶全部投完 → 一局结束
		_end_round()
		return
	
	# 确定当前投壶方
	# 投壶顺序：先手方先投第一壶，然后交替
	# hammer_team 后手 = 最后一壶是他的
	var first_team: int = 1 - hammer_team  # 先手方
	var current_team: int
	if current_throw_index % 2 == 0:
		current_team = first_team
	else:
		current_team = hammer_team
	
	# 确定位置和壶号
	@warning_ignore("integer_division")
	var team_throw: int = current_throw_index / 2  # 该队第几壶（0~7）
	@warning_ignore("integer_division")
	var position_index: int = team_throw / 2        # 几垒（0~3）
	var stone_number: int = team_throw + 1           # 壶编号（1~8）
	
	# 更新 HUD
	game_hud.update_turn(current_team, position_index, stone_number)
	game_hud.update_stones_left(stones_left[0], stones_left[1])
	
	# 进入瞄准阶段
	throw_phase = ThrowPhase.AIMING
	aim_angle = 0.0
	charge_power = 0.0
	selected_spin = 0
	
	# 相机回到投壶端
	game_camera.return_to_spawn()
	
	print("[GameMain] 第 %d 壶 - %s %s (壶 #%d)" % [
		current_throw_index + 1,
		"红队" if current_team == 0 else "蓝队",
		["一垒", "二垒", "三垒", "四垒"][position_index],
		stone_number
	])
	
	# 提前在投壶点生成冰壶供玩家瞄准时观察
	# (客户端和服务器都会生成，但此时它被冻结)
	_spawn_aiming_stone(current_team, stone_number)
	
	# 联网模式：服务器广播回合信息给所有客户端
	if is_networked and multiplayer.is_server():
		GameSync.sync_turn.rpc(current_throw_index, current_team, position_index, stone_number)

## 在准备投壶阶段生成等待被投的冰壶
func _spawn_aiming_stone(team: int, stone_index: int) -> void:
	# 如果存在老的则清除（防错）
	if current_sliding_stone and is_instance_valid(current_sliding_stone):
		if current_sliding_stone not in active_stones:
			current_sliding_stone.queue_free()
	
	var stone: RigidBody2D = CurlingStoneScene.instantiate()
	stone.team = team
	stone.stone_index = stone_index
	stone.freeze = true  # 瞄准阶段不动
	stones_container.add_child(stone)
	stone.global_position = curling_sheet.get_spawn_position()
	
	current_sliding_stone = stone


# ============================================================================
# 阶段处理：瞄准
# ============================================================================

## 瞄准阶段的帧更新
func _process_aiming(_delta: float) -> void:
	# 更新瞄准方向显示（由鼠标位置控制）
	queue_redraw()  # 重绘瞄准线


## 瞄准阶段的输入处理
func _input_aiming(event: InputEvent) -> void:
	# 鼠标移动 → 更新瞄准方向
	if event is InputEventMouseMotion:
		var spawn_pos: Vector2 = curling_sheet.get_spawn_position()
		var mouse_world: Vector2 = get_global_mouse_position()
		aim_direction = (mouse_world - spawn_pos).normalized()
		# 限制投壶方向只能朝上（Y < 0）
		if aim_direction.y > -0.1:
			aim_direction = Vector2(aim_direction.x, -0.1).normalized()
		aim_angle = aim_direction.angle()
	
	# A/D 键 → 微调方向
	if event.is_action_pressed("aim_left"):
		aim_angle -= 0.02
		aim_direction = Vector2.from_angle(aim_angle)
	elif event.is_action_pressed("aim_right"):
		aim_angle += 0.02
		aim_direction = Vector2.from_angle(aim_angle)
	
	# Q/E 键 → 选择旋转方向（参考 DESIGN.md 7.1）
	if event.is_action_pressed("spin_ccw"):
		selected_spin = -1
		print("[GameMain] 旋转: 逆时针")
	elif event.is_action_pressed("spin_cw"):
		selected_spin = 1
		print("[GameMain] 旋转: 顺时针")
	
	# 鼠标左键按下 → 进入蓄力阶段
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		throw_phase = ThrowPhase.CHARGING
		is_charging = true
		charge_power = 0.0
		print("[GameMain] 开始蓄力...")


# ============================================================================
# 阶段处理：蓄力
# ============================================================================

## 蓄力阶段的帧更新
func _process_charging(delta: float) -> void:
	if is_charging:
		# 力度从 0 增长到 1
		charge_power = minf(charge_power + charge_speed * delta, 1.0)
	queue_redraw()  # 重绘力度条


## 蓄力阶段的输入处理
func _input_charging(event: InputEvent) -> void:
	# 鼠标左键松开 → 释放冰壶
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_charging = false
		_release_stone()


# ============================================================================
# 阶段处理：擦冰/滑行
# ============================================================================

## 擦冰阶段的帧更新
func _process_sweeping(_delta: float) -> void:
	if current_sliding_stone and is_instance_valid(current_sliding_stone):
		# 如果已经出界，就不再重复检测，防止死循环
		if current_sliding_stone.is_out_of_bounds:
			current_sliding_stone = null # 释放引用
			return
			
		# 检测出界
		if curling_sheet.is_stone_out_of_bounds(current_sliding_stone.global_position):
			current_sliding_stone.mark_out_of_bounds()
			current_sliding_stone = null # 立即置空，防止下一帧重复触发
	
	# 每一帧请求重绘 Overlay（确保瞄准线/力度条平滑）
	if aim_overlay:
		aim_overlay.queue_redraw()


## 擦冰阶段的输入处理
func _input_sweeping(event: InputEvent) -> void:
	if current_sliding_stone == null:
		return
	
	# 鼠标左键按住 → 擦冰（参考 DESIGN.md 6.3 步骤 4）
	# 投壶手释放后直接可操作擦冰（自然衔接，DESIGN.md 已确认决策）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var sweeping: bool = event.pressed
		if is_networked:
			# 联网模式：发送擦冰状态给服务器
			GameSync.send_sweep.rpc_id(1, sweeping)
		else:
			# 单机模式：直接设置
			current_sliding_stone.set_sweep(sweeping)


# ============================================================================
# 投壶释放
# ============================================================================

## 释放冰壶
func _release_stone() -> void:
	# 计算实际投壶力度（charge_power 0~1 映射到 200~1200 px/s）
	# 参考 DESIGN.md 6.1：投掷初速度范围 200 ~ 1200 px/s
	var actual_power: float = lerpf(200.0, 1200.0, charge_power)
	
	if is_networked:
		# === 联网模式：发送投壶参数给服务器，由服务器执行物理模拟 ===
		# 客户端不直接实例化冰壶，等服务器广播后再创建视觉冰壶
		GameSync.send_throw_params.rpc_id(1, aim_direction, actual_power, selected_spin)
		print("[GameMain] 已发送投壶参数到服务器")
		# 进入擦冰阶段（等服务器广播后更新视觉）
		throw_phase = ThrowPhase.SWEEPING
	else:
		# === 单机模式：直接本地投壶 ===
		_local_throw_stone(aim_direction, actual_power, selected_spin)


## 本地投壶（单机模式和服务器端共用）
func _local_throw_stone(direction: Vector2, power: float, spin: int) -> void:
	# 服务器或单机执行真正的投壶
	if current_sliding_stone and is_instance_valid(current_sliding_stone):
		var stone: RigidBody2D = current_sliding_stone
		# 将其正式加入场上冰壶数组
		if not stone in active_stones:
			active_stones.append(stone)
			stones_left[stone.team] -= 1
		
		# 投掷！
		stone.throw(direction, power, spin)
		
		# 连接冰壶停止信号
		if not stone.stone_stopped.is_connected(_on_stone_stopped):
			stone.stone_stopped.connect(_on_stone_stopped)
		if not stone.stone_out_of_bounds.is_connected(_on_stone_out):
			stone.stone_out_of_bounds.connect(_on_stone_out)
			
		# 相机跟随冰壶
		game_camera.start_following(stone)
	
	# 进入擦冰阶段
	throw_phase = ThrowPhase.SWEEPING
	
	print("[GameMain] 冰壶释放！力度: %.0f px/s, 旋转: %d" % [power, spin])


## 服务器端投壶（由 GameSync.send_throw_params 触发）
func _server_throw_stone(direction: Vector2, power: float, spin: int) -> void:
	print("[GameMain] 服务器执行投壶...")
	_local_throw_stone(direction, power, spin)


# ============================================================================
# 网络信号回调（仅客户端）
# ============================================================================

## 客户端收到服务器广播的投壶命令（创建视觉冰壶）
func _on_throw_received(_direction: Vector2, _power: float, _spin: int, team: int, stone_index: int) -> void:
	print("[GameMain] 客户端收到投壶广播: 队伍 %d, 壶 #%d" % [team, stone_index])
	
	# 客户端收到广播：确认将瞄准用冰壶投入实战
	if current_sliding_stone and is_instance_valid(current_sliding_stone):
		var stone: RigidBody2D = current_sliding_stone
		if not stone in active_stones:
			active_stones.append(stone)
			stones_left[team] -= 1
		
		stone.freeze = true  # 客户端仍不跑物理
		game_camera.start_following(stone)
	
	throw_phase = ThrowPhase.SWEEPING


## 客户端收到服务器广播的冰壶位置同步（插值平滑）
func _on_stones_sync(stones_data: Array) -> void:
	for data in stones_data:
		var s_team: int = data.get("team", 0)
		var s_index: int = data.get("index", 0)
		var s_pos: Vector2 = Vector2(data.get("pos_x", 0), data.get("pos_y", 0))
		var s_rot: float = data.get("rot", 0.0)
		var s_stopped: bool = data.get("stopped", false)
		
		# 查找对应的本地冰壶并插值
		for stone in active_stones:
			if is_instance_valid(stone) and stone.team == s_team and stone.stone_index == s_index:
				# 用插值平滑移动，避免抽搏
				stone.global_position = stone.global_position.lerp(s_pos, 0.5)
				stone.rotation = lerp_angle(stone.rotation, s_rot, 0.5)
				stone.is_stopped = s_stopped
				break


## 客户端收到擦冰同步
func _on_sweep_sync(_is_sweeping: bool) -> void:
	if current_sliding_stone and is_instance_valid(current_sliding_stone):
		# 视觉效果（客户端不影响物理）
		pass  # TODO: 擦冰视觉特效


## 客户端收到回合变更
func _on_turn_sync(throw_index: int, current_team: int, position_index: int, stone_number: int) -> void:
	current_throw_index = throw_index
	game_hud.update_turn(current_team, position_index, stone_number)
	game_hud.update_stones_left(stones_left[0], stones_left[1])
	game_camera.return_to_spawn()
	
	# 根据权限决定进入什么状态
	if _is_my_turn():
		print("[GameMain] 轮到我投壶！切换至瞄准阶段")
		throw_phase = ThrowPhase.AIMING
		aim_angle = 0.0
		charge_power = 0.0
		selected_spin = 0
		# 客户端在收到回合通知时同步生成用于瞄准的冰壶（视觉用）
		_spawn_aiming_stone(current_team, stone_number)
	else:
		throw_phase = ThrowPhase.WAITING


## 客户端收到得分同步
func _on_score_sync(_round_score: Dictionary, all_round_scores: Array, red_total: int, blue_total: int) -> void:
	round_scores = all_round_scores
	red_total_score = red_total
	blue_total_score = blue_total
	game_hud.update_score(red_total, blue_total)
	game_hud.update_scoreboard(all_round_scores)
	game_camera.view_house()


## 客户端收到比赛结束
func _on_game_ended_sync(_red_total: int, _blue_total: int, _all_round_scores: Array) -> void:
	GameManager.go_to_result()


# ============================================================================
# 辅助方法（供 GameSync 调用）
# ============================================================================

## 获取当前投壶队伍
func _get_current_team() -> int:
	var first_team: int = 1 - hammer_team
	if current_throw_index % 2 == 0:
		return first_team
	else:
		return hammer_team


## 获取当前壶编号
func _get_current_stone_number() -> int:
	@warning_ignore("integer_division")
	var team_throw: int = current_throw_index / 2
	return team_throw + 1


# ============================================================================
# 冰壶事件回调
# ============================================================================

## 冰壶停止
func _on_stone_stopped(_stone: RigidBody2D) -> void:
	# 检查是否所有运动中的冰壶都停了
	var all_stopped: bool = true
	for s in active_stones:
		if is_instance_valid(s) and not s.is_stopped and not s.is_out_of_bounds:
			all_stopped = false
			break
	
	if all_stopped:
		current_sliding_stone = null
		print("[GameMain] 所有冰壶已停止")
		
		# 进入下一次投壶
		current_throw_index += 1
		_update_hud()
		
		# 延迟一小会再开始下一壶（让玩家看到结果）
		await get_tree().create_timer(1.0).timeout
		_start_next_throw()


## 冰壶出界
func _on_stone_out(stone: RigidBody2D) -> void:
	print("[GameMain] 冰壶 #%d (%s) 出界" % [
		stone.stone_index, "红" if stone.team == 0 else "蓝"
	])
	
	# 出界视为一种特殊的停止状态，触发回合检查逻辑
	_on_stone_stopped(stone)


# ============================================================================
# 一局结束 & 得分计算
# ============================================================================

## 一局结束 — 计算得分（参考 DESIGN.md 2.5 得分规则）
func _end_round() -> void:
	throw_phase = ThrowPhase.ROUND_END
	print("[GameMain] === 第 %d 局结束，计算得分 ===" % current_round)
	
	# 相机移到大本营
	game_camera.view_house()
	
	# 计算得分
	var score: Dictionary = _calculate_score()
	round_scores.append(score)
	red_total_score += score["red"]
	blue_total_score += score["blue"]
	
	print("[GameMain] 本局得分: 红 %d  蓝 %d" % [score["red"], score["blue"]])
	
	# 联网模式：服务器广播得分给所有客户端
	if is_networked and multiplayer.is_server():
		GameSync.sync_round_score.rpc(score, round_scores, red_total_score, blue_total_score)
	
	# 更新 HUD
	game_hud.update_score(red_total_score, blue_total_score)
	game_hud.update_scoreboard(round_scores)
	
	# 更新后手权（得分方下一局失去后手，参考 DESIGN.md 2.1）
	if score["red"] > 0:
		hammer_team = 1  # 红队得分 → 蓝队获得后手
	elif score["blue"] > 0:
		hammer_team = 0  # 蓝队得分 → 红队获得后手
	# 如果双方 0 分 → 后手权不变
	
	# 延迟后进入下一局或结算
	await get_tree().create_timer(3.0).timeout
	
	current_round += 1
	if current_round > total_rounds:
		# 比赛结束！
		_end_game()
	else:
		_init_round()


## 计算本局得分
## 规则（DESIGN.md 2.5）：
##   - 仅大本营内的冰壶参与
##   - 最近圆心的壶的队伍得分
##   - 该队所有比对手最近壶更接近圆心的壶数 = 得分
func _calculate_score() -> Dictionary:
	var tee_pos: Vector2 = curling_sheet.get_tee_position()
	
	# 收集大本营内的冰壶及其到圆心的距离
	var red_distances: Array[float] = []
	var blue_distances: Array[float] = []
	
	for stone in active_stones:
		if not is_instance_valid(stone) or stone.is_out_of_bounds:
			continue
		
		if curling_sheet.is_stone_in_house(stone.global_position):
			var dist: float = stone.global_position.distance_to(tee_pos)
			if stone.team == 0:
				red_distances.append(dist)
			else:
				blue_distances.append(dist)
	
	# 排序（距离从小到大）
	red_distances.sort()
	blue_distances.sort()
	
	var result: Dictionary = { "red": 0, "blue": 0 }
	
	# 如果没有壶在大本营内 → 双方 0 分
	if red_distances.is_empty() and blue_distances.is_empty():
		return result
	
	# 如果只有一方有壶在内
	if red_distances.is_empty():
		result["blue"] = blue_distances.size()
		return result
	if blue_distances.is_empty():
		result["red"] = red_distances.size()
		return result
	
	# 双方都有壶 → 比较最近壶
	var red_closest: float = red_distances[0]
	var blue_closest: float = blue_distances[0]
	
	if red_closest < blue_closest:
		# 红队最近 → 计算红队有几壶比蓝队最近壶更近
		for dist in red_distances:
			if dist < blue_closest:
				result["red"] += 1
			else:
				break
	else:
		# 蓝队最近 → 计算蓝队有几壶比红队最近壶更近
		for dist in blue_distances:
			if dist < red_closest:
				result["blue"] += 1
			else:
				break
	
	return result


# ============================================================================
# 比赛结束
# ============================================================================

## 比赛结束 → 进入结算界面
func _end_game() -> void:
	print("[GameMain] ===== 比赛结束！红队 %d : %d 蓝队 =====" % [
		red_total_score, blue_total_score
	])
	
	# 联网模式：服务器广播比赛结束
	if is_networked and multiplayer.is_server():
		GameSync.sync_game_end.rpc(red_total_score, blue_total_score, round_scores)
	
	# 延迟后切换到结算界面
	await get_tree().create_timer(2.0).timeout
	if not is_server_instance:
		GameManager.go_to_result()


# ============================================================================
# 工具方法
# ============================================================================

func _is_my_turn() -> bool:
	if not is_networked:
		return true
	
	# 服务器端不需要操作 UI（Headless 模式，没有人在玩）
	if is_server_instance:
		return false
	
	var my_id: int = NetworkManager.get_local_peer_id()
	var current_team: int = _get_current_team()
	
	# 如果有精确的槽位分配（经过了选位阶段），则严格匹配
	if not GameSync.slot_assignments.is_empty():
		@warning_ignore("integer_division")
		var position_idx: int = (current_throw_index / 2) / 2
		var role_idx: int = 0  # 投壶手
		var slot_key: String = "%d_%d_%d" % [current_team, position_idx, role_idx]
		var assigned_peer: int = GameSync.slot_assignments.get(slot_key, -1)
		
		# 调试日志
		if current_throw_index % 8 == 0: # 减少日志频率
			print("[GameMain] 权限检查(Slot): Me:%d, Assigned:%d, Key:%s" % [my_id, assigned_peer, slot_key])
			
		if assigned_peer != -1:
			return my_id == assigned_peer
	
	# 降级策略：没有槽位分配时，只要你属于当前投壶队伍就允许操作
	var my_data: Dictionary = NetworkManager.players.get(my_id, {})
	var my_team: int = my_data.get("team", -1)
	
	# 调试日志
	if current_throw_index % 8 == 0:
		print("[GameMain] 权限检查(Team): Me:%d, MyTeam:%d, Target:%d, LocalPlayers:%d" % [
			my_id, my_team, current_team, NetworkManager.players.size()
		])
	
	return my_team == current_team



# ============================================================================
# HUD 更新
# ============================================================================

func _update_hud() -> void:
	game_hud.update_round(current_round, total_rounds)
	game_hud.update_score(red_total_score, blue_total_score)
	game_hud.update_hammer(hammer_team)
	game_hud.update_stones_left(stones_left[0], stones_left[1])
	game_hud.update_scoreboard(round_scores)


# ============================================================================
# 绘制（瞄准线和力度条）
# ============================================================================

func _on_aim_overlay_draw() -> void:
	if throw_phase == ThrowPhase.AIMING or throw_phase == ThrowPhase.CHARGING:
		var spawn_pos: Vector2 = curling_sheet.get_spawn_position() - global_position
		
		# --- 瞄准线 ---
		var line_length: float = 200.0
		var line_end: Vector2 = spawn_pos + aim_direction * line_length
		var aim_color: Color = Color(0.2, 1.0, 0.2, 0.9)  # 增强可见度
		aim_overlay.draw_line(spawn_pos, line_end, aim_color, 4.0)
		
		# 方向箭头
		aim_overlay.draw_circle(line_end, 5.0, aim_color)
		
		# --- 旋转方向指示 ---
		if selected_spin == -1:
			aim_overlay.draw_circle(spawn_pos + Vector2(-40, 0), 8, Color(1, 1, 0, 0.9))  # 左
		elif selected_spin == 1:
			aim_overlay.draw_circle(spawn_pos + Vector2(40, 0), 8, Color(1, 1, 0, 0.9))   # 右
	
	if throw_phase == ThrowPhase.CHARGING:
		var spawn_pos: Vector2 = curling_sheet.get_spawn_position() - global_position
		
		# --- 力度条 ---
		var bar_width: float = 120.0
		var bar_height: float = 12.0
		var bar_pos: Vector2 = spawn_pos + Vector2(-bar_width / 2, 40)
		
		# 背景（深色半透明）
		aim_overlay.draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.1, 0.1, 0.1, 0.7))
		# 进度填充
		var fill_color: Color = Color.GREEN.lerp(Color.RED, charge_power)
		aim_overlay.draw_rect(Rect2(bar_pos, Vector2(bar_width * charge_power, bar_height)), fill_color)
		# 亮白色边框，增强对比度
		aim_overlay.draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color.WHITE, false, 2.0)
