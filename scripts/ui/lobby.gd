# ============================================================================
# lobby.gd — 大厅界面控制脚本
# ============================================================================
# 对应场景：scenes/ui/lobby.tscn
# 参考 DESIGN.md 第 4.3 节
#
# 功能：
#   1. 显示在线人数
#   2. 显示房间列表（房间名、人数、状态、操作按钮）
#   3. 点击"创建房间"弹出创建房间对话框（独立场景）
#   4. 点击"加入"加入对应房间
#   5. 点击"断开连接"返回登录界面
# ============================================================================

extends Control

# ============================================================================
# 预加载/常量
# ============================================================================

## 创建房间弹窗场景（独立 .tscn，运行时实例化叠加）
## 参考 DESIGN.md 4.3 节：弹窗作为独立场景，运行时 add_child() 实例化
const CreateRoomDialog: PackedScene = preload("res://scenes/ui/create_room_dialog.tscn")

# ============================================================================
# 节点引用
# ============================================================================

@onready var online_label: Label = %OnlineLabel              ## 在线人数显示
@onready var disconnect_button: Button = %DisconnectButton    ## 断开连接按钮
@onready var room_list: VBoxContainer = %RoomList              ## 房间列表容器
@onready var create_room_button: Button = %CreateRoomButton    ## 创建房间按钮
@onready var status_label: Label = %StatusLabel                ## 状态标签

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 连接网络信号
	NetworkManager.lobby_updated.connect(_on_lobby_updated)
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	
	# 连接按钮事件
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	create_room_button.pressed.connect(_on_create_room_pressed)
	
	# 更新在线人数
	_update_online_count()
	
	# 更新房间列表
	_refresh_room_list(NetworkManager.rooms)
	
	print("[Lobby] 大厅界面已加载")


# ============================================================================
# 按钮事件处理
# ============================================================================

## 点击"断开连接"
func _on_disconnect_pressed() -> void:
	print("[Lobby] 用户主动断开连接")
	NetworkManager.disconnect_from_server()
	GameManager.go_to_login()


## 点击"创建房间" — 弹出独立的创建房间对话框场景
func _on_create_room_pressed() -> void:
	print("[Lobby] 打开创建房间对话框")
	
	# 实例化弹窗场景并叠加到当前界面
	var dialog: Control = CreateRoomDialog.instantiate()
	add_child(dialog)
	
	# 连接弹窗的确认信号
	if dialog.has_signal("room_created"):
		dialog.room_created.connect(_on_room_creation_confirmed)


## 创建房间弹窗的确认回调
func _on_room_creation_confirmed(room_name: String, rounds: int) -> void:
	print("[Lobby] 请求创建房间: %s (%d局)" % [room_name, rounds])
	status_label.text = "正在创建房间..."
	
	# 通过 RPC 发送创建房间请求给服务器
	NetworkManager.request_create_room.rpc_id(1, room_name, rounds)


## 点击房间列表中的"加入"按钮
func _on_join_room_pressed(room_id: int) -> void:
	print("[Lobby] 请求加入房间 ID: %d" % room_id)
	status_label.text = "正在加入房间..."
	
	# 通过 RPC 发送加入房间请求给服务器
	NetworkManager.request_join_room.rpc_id(1, room_id)


# ============================================================================
# 网络信号回调
# ============================================================================

## 房间列表更新
func _on_lobby_updated(rooms: Array) -> void:
	_refresh_room_list(rooms)
	_update_online_count()
	status_label.text = ""


## 有新玩家加入服务器
func _on_player_joined(_peer_id: int, _username: String) -> void:
	_update_online_count()


## 有玩家离开服务器
func _on_player_left(_peer_id: int) -> void:
	_update_online_count()


## 与服务器断开连接
func _on_disconnected() -> void:
	print("[Lobby] 与服务器断开连接，返回登录界面")
	GameManager.go_to_login()


# ============================================================================
# UI 更新方法
# ============================================================================

## 更新在线人数显示
func _update_online_count() -> void:
	var count: int = NetworkManager.players.size()
	online_label.text = "在线: %d 人" % count


## 刷新房间列表
## @param rooms: 房间数据数组（来自 NetworkManager）
func _refresh_room_list(rooms: Array) -> void:
	# 清空现有列表
	for child in room_list.get_children():
		child.queue_free()
	
	# 如果没有房间，显示提示
	if rooms.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "暂无房间，点击下方按钮创建一个吧！"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.modulate = Color(0.6, 0.6, 0.6, 1)
		room_list.add_child(empty_label)
		return
	
	# 为每个房间创建一行
	for room in rooms:
		var row: HBoxContainer = _create_room_row(room)
		room_list.add_child(row)


## 创建单行房间显示
## 格式: [ 房间名 | 人数 | 状态 | 操作按钮 ]
func _create_room_row(room: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	
	# 房间名
	var name_label: Label = Label.new()
	name_label.text = room.get("name", "未知")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	
	# 人数
	var count_label: Label = Label.new()
	var current: int = room.get("players", []).size()
	var max_p: int = room.get("max_players", 8)
	count_label.text = "%d/%d" % [current, max_p]
	count_label.custom_minimum_size.x = 60
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count_label)
	
	# 状态
	var state_label: Label = Label.new()
	var state: String = room.get("state", "unknown")
	match state:
		"waiting":
			state_label.text = "等待中"
		"preparing":
			state_label.text = "准备中"
		"playing":
			state_label.text = "游戏中"
		_:
			state_label.text = state
	state_label.custom_minimum_size.x = 80
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(state_label)
	
	# 加入按钮（waiting 和 preparing 状态且未满时可用）
	var join_button: Button = Button.new()
	join_button.text = "加入"
	join_button.disabled = (not state in ["waiting", "preparing"]) or (current >= max_p)
	var room_id: int = room.get("id", -1)
	join_button.pressed.connect(_on_join_room_pressed.bind(room_id))
	row.add_child(join_button)
	
	return row
