# ============================================================================
# create_room_dialog.gd — 创建房间弹窗控制脚本
# ============================================================================
# 对应场景：scenes/ui/create_room_dialog.tscn
# 参考 DESIGN.md 第 4.3 节
#
# 设计理念：
#   弹窗作为独立 .tscn 场景，运行时 add_child() 实例化叠加在大厅之上，
#   便于解耦和未来扩展。确认后通过信号通知父场景（大厅）。
#
# 功能：
#   1. 输入房间名
#   2. 选择局数（4/6/8/10，默认 8 局）
#   3. 确认创建 → 发出信号 → 关闭弹窗
#   4. 取消 → 关闭弹窗
# ============================================================================

extends Control

# ============================================================================
# 信号定义
# ============================================================================

## 用户确认创建房间时发出
## @param room_name: 房间名称
## @param rounds: 局数
signal room_created(room_name: String, rounds: int)

# ============================================================================
# 节点引用
# ============================================================================

@onready var room_name_input: LineEdit = %RoomNameInput    ## 房间名输入框
@onready var rounds_option: OptionButton = %RoundsOption    ## 局数下拉选择
@onready var cancel_button: Button = %CancelButton          ## 取消按钮
@onready var confirm_button: Button = %ConfirmButton        ## 确认按钮

# ============================================================================
# 局数映射表 — OptionButton 的 index 对应实际局数
# ============================================================================

## OptionButton 各选项对应的实际局数值
const ROUNDS_MAP: Array[int] = [4, 6, 8, 10]

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 连接按钮事件
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	
	# 默认聚焦房间名输入框
	room_name_input.grab_focus()
	
	print("[CreateRoomDialog] 创建房间弹窗已打开")


# ============================================================================
# 按钮事件处理
# ============================================================================

## 点击"取消"— 关闭弹窗
func _on_cancel_pressed() -> void:
	print("[CreateRoomDialog] 用户取消创建房间")
	_close()


## 点击"确认创建"
func _on_confirm_pressed() -> void:
	var room_name: String = room_name_input.text.strip_edges()
	
	# 验证房间名
	if room_name.is_empty():
		room_name_input.placeholder_text = "⚠️ 房间名不能为空！"
		return
	
	# 获取选中的局数
	var selected_index: int = rounds_option.selected
	var rounds: int = ROUNDS_MAP[selected_index] if selected_index < ROUNDS_MAP.size() else 8
	
	print("[CreateRoomDialog] 确认创建房间: %s (%d局)" % [room_name, rounds])
	
	# 发出信号通知父场景（大厅）
	room_created.emit(room_name, rounds)
	
	# 关闭弹窗
	_close()


# ============================================================================
# 工具方法
# ============================================================================

## 关闭弹窗（从场景树中移除自身）
func _close() -> void:
	queue_free()


## 支持 ESC 键关闭弹窗
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		# 消费此事件，防止传递给下层
		get_viewport().set_input_as_handled()
