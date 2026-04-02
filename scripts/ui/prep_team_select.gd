# ============================================================================
# prep_team_select.gd — 准备阶段1：选择队伍
# ============================================================================
# 对应场景：scenes/ui/prep_team_select.tscn
# 参考 DESIGN.md 第 4.4 节
#
# 功能：
#   1. 显示红队/蓝队双面板，列出已选边的玩家
#   2. 显示未选边的玩家列表
#   3. 玩家点击按钮加入红队或蓝队
#   4. 房主可在每队至少 1 人时点击"开始游戏"
#   5. 所有操作通过 RPC 同步给服务器，再由服务器广播
# ============================================================================

extends Control

# ============================================================================
# 队伍常量（参考 DESIGN.md 2.2）
# ============================================================================

## 队伍 ID：红队 = 0，蓝队 = 1，未选 = -1
const TEAM_RED: int = 0
const TEAM_BLUE: int = 1
const TEAM_NONE: int = -1

# ============================================================================
# 节点引用
# ============================================================================

@onready var room_name_label: Label = %RoomNameLabel ## 房间名显示
@onready var red_player_list: VBoxContainer = %RedPlayerList ## 红队玩家列表
@onready var blue_player_list: VBoxContainer = %BluePlayerList ## 蓝队玩家列表
@onready var join_red_button: Button = %JoinRedButton ## 加入红队按钮
@onready var join_blue_button: Button = %JoinBlueButton ## 加入蓝队按钮
@onready var unassigned_list: HBoxContainer = %UnassignedList ## 未选边玩家列表
@onready var status_label: Label = %StatusLabel ## 状态标签
@onready var start_button: Button = %StartButton ## 开始游戏按钮

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 连接按钮事件
	join_red_button.pressed.connect(_on_join_red_pressed)
	join_blue_button.pressed.connect(_on_join_blue_pressed)
	start_button.pressed.connect(_on_start_pressed)
	
	# 仅房主可见"开始游戏"按钮（TODO: 判断房主身份）
	# 暂时对所有人显示，后续通过 RPC 完善
	start_button.visible = true
	
	# 连接 GameSync 信号以刷新界面
	GameSync.team_data_updated.connect(_on_team_data_updated)
	GameSync.room_data_updated.connect(_on_room_updated)
	
	# 更新房间名显示
	room_name_label.text = "房间: " + GameSync.current_room.get("name", "未知")
	
	# 初始化显示
	_refresh_team_display()
	
	print("[PrepTeamSelect] 选边界面已加载")


# ============================================================================
# 按钮事件处理
# ============================================================================

## 点击"加入红队"
func _on_join_red_pressed() -> void:
	print("[PrepTeamSelect] 点击加入红队")
	GameSync.request_join_team.rpc_id(1, TEAM_RED)


## 点击"加入蓝队"
func _on_join_blue_pressed() -> void:
	print("[PrepTeamSelect] 点击加入蓝队")
	GameSync.request_join_team.rpc_id(1, TEAM_BLUE)


## 点击"开始游戏"（仅房主）
func _on_start_pressed() -> void:
	print("[PrepTeamSelect] 房主点击开始游戏")
	GameSync.request_start_role_select.rpc_id(1)


# ============================================================================
# 数据更新回调
# ============================================================================

func _on_team_data_updated(_data: Dictionary) -> void:
	_refresh_team_display()

func _on_room_updated(_data: Dictionary) -> void:
	_refresh_team_display()



# ============================================================================
# UI 更新方法
# ============================================================================

## 刷新队伍显示
func _refresh_team_display() -> void:
	# 清空列表
	for child in red_player_list.get_children():
		child.queue_free()
	for child in blue_player_list.get_children():
		child.queue_free()
	for child in unassigned_list.get_children():
		child.queue_free()
	
	# 分类显示玩家
	var red_count: int = 0
	var blue_count: int = 0
	# 仅显示当前房间内的玩家
	var room_players: Array = GameSync.current_room.get("players", [])
	
	for peer_id in room_players:
		# 以防数据不同步
		if peer_id not in NetworkManager.players:
			continue
		var player_data: Dictionary = NetworkManager.players[peer_id]
		var username: String = player_data.get("username", "未知")
		var team: int = player_data.get("team", TEAM_NONE)
		
		var label: Label = Label.new()
		label.text = "● " + username
		
		# 标记当前玩家
		if peer_id == NetworkManager.get_local_peer_id():
			label.text += " (你)"
		
		match team:
			TEAM_RED:
				label.modulate = Color(1, 0.4, 0.4, 1) # 红色
				red_player_list.add_child(label)
				red_count += 1
			TEAM_BLUE:
				label.modulate = Color(0.4, 0.6, 1, 1) # 蓝色
				blue_player_list.add_child(label)
				blue_count += 1
			_:
				unassigned_list.add_child(label)
	
	# 更新开始按钮状态
	var can_start: bool = red_count >= 1 and blue_count >= 1
	start_button.disabled = not can_start
	
	if can_start:
		status_label.text = "✅ 红队 %d 人，蓝队 %d 人 — 可以开始！" % [red_count, blue_count]
	else:
		status_label.text = "条件: 每队至少 1 人 (红 %d / 蓝 %d)" % [red_count, blue_count]
