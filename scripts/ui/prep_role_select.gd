# ============================================================================
# prep_role_select.gd — 准备阶段2：选择位置和角色
# ============================================================================
# 对应场景：scenes/ui/prep_role_select.tscn
# 参考 DESIGN.md 第 4.5 节
#
# 规则要点（参考 DESIGN.md 2.2 ~ 2.3）：
#   - 每队 4 个位置（一垒~四垒），每个位置 2 个角色（投壶手+擦冰员）
#   - 每队共 8 个槽位，所有槽位必须有人担任
#   - 一个玩家可以认领本队多个槽位
#   - 点击槽位即认领/取消
#   - 所有 16 个槽位填满 + 全员"准备就绪" → 游戏开始
# ============================================================================

extends Control

# ============================================================================
# 常量
# ============================================================================

## 位置名称（一垒到四垒）
const POSITION_NAMES: Array[String] = ["一垒", "二垒", "三垒", "四垒"]

## 角色名称
const ROLE_NAMES: Array[String] = ["投壶手", "擦冰员"]

## 队伍 ID
const TEAM_RED: int = 0
const TEAM_BLUE: int = 1

# ============================================================================
# 节点引用
# ============================================================================

@onready var red_slots: VBoxContainer = %RedSlots        ## 红队槽位容器
@onready var blue_slots: VBoxContainer = %BlueSlots      ## 蓝队槽位容器
@onready var ready_button: Button = %ReadyButton         ## 准备就绪按钮
@onready var status_label: Label = %StatusLabel           ## 状态标签

# ============================================================================
# 数据结构
# ============================================================================

## 槽位分配表
## 格式: { "team_pos_role": peer_id }
## 例如: { "0_0_0": 12345 } 表示红队一垒投壶手由 peer_id=12345 担任
## team: 0=红, 1=蓝 / pos: 0~3 (一垒~四垒) / role: 0=投壶手, 1=擦冰员
var slot_assignments: Dictionary = {}

## 本地玩家是否已准备
var local_ready: bool = false

## 各玩家准备状态 { peer_id: bool }
var ready_states: Dictionary = {}

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 连接按钮事件
	ready_button.pressed.connect(_on_ready_pressed)
	
	# 生成槽位 UI
	_build_slots_ui(red_slots, TEAM_RED)
	_build_slots_ui(blue_slots, TEAM_BLUE)
	
	print("[PrepRoleSelect] 选位置界面已加载")


# ============================================================================
# UI 构建
# ============================================================================

## 为一个队伍构建 4 位置 × 2 角色 的槽位按钮
## @param container: 目标容器节点
## @param team: 队伍 ID（0=红, 1=蓝）
func _build_slots_ui(container: VBoxContainer, team: int) -> void:
	for pos in range(4):
		# 位置标题（如 "一垒 (投壶 #1, #2):"）
		var pos_label: Label = Label.new()
		var stone_start: int = pos * 2 + 1
		pos_label.text = "%s (投壶 #%d, #%d):" % [POSITION_NAMES[pos], stone_start, stone_start + 1]
		container.add_child(pos_label)
		
		# 两个角色槽位
		for role in range(2):
			var slot_row: HBoxContainer = HBoxContainer.new()
			slot_row.add_theme_constant_override("separation", 8)
			
			# 角色标签
			var role_label: Label = Label.new()
			role_label.text = "  " + ROLE_NAMES[role] + ":"
			role_label.custom_minimum_size.x = 80
			slot_row.add_child(role_label)
			
			# 槽位按钮 — 点击认领/取消
			var slot_button: Button = Button.new()
			slot_button.text = "[空位]"
			slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# 存储槽位 key 用于识别
			var slot_key: String = "%d_%d_%d" % [team, pos, role]
			slot_button.set_meta("slot_key", slot_key)
			slot_button.pressed.connect(_on_slot_clicked.bind(slot_key))
			slot_row.add_child(slot_button)
			
			container.add_child(slot_row)
		
		# 位置之间加分隔
		if pos < 3:
			var sep: HSeparator = HSeparator.new()
			container.add_child(sep)


# ============================================================================
# 按钮事件
# ============================================================================

## 点击槽位按钮 — 认领或取消
func _on_slot_clicked(slot_key: String) -> void:
	var my_id: int = NetworkManager.get_local_peer_id()
	
	# 检查此槽位是否属于自己的队伍
	var parts: PackedStringArray = slot_key.split("_")
	var slot_team: int = parts[0].to_int()
	var my_team: int = NetworkManager.players.get(my_id, {}).get("team", -1)
	
	if slot_team != my_team:
		status_label.text = "⚠️ 你只能认领自己队伍的槽位！"
		return
	
	# 发送认领/取消请求给服务器
	_request_toggle_slot.rpc_id(1, slot_key)


## 点击"准备就绪"
func _on_ready_pressed() -> void:
	local_ready = not local_ready
	ready_button.text = "✔ 已准备" if local_ready else "✔ 准备就绪"
	_request_ready.rpc_id(1, local_ready)


# ============================================================================
# RPC 方法
# ============================================================================

## 客户端 → 服务器：切换槽位认领状态
@rpc("any_peer", "reliable")
func _request_toggle_slot(slot_key: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	
	# 如果该槽位已被此玩家认领 → 取消
	if slot_assignments.get(slot_key) == sender_id:
		slot_assignments.erase(slot_key)
		print("[PrepRoleSelect] 玩家 %d 取消槽位 %s" % [sender_id, slot_key])
	# 如果槽位空闲 → 认领
	elif slot_key not in slot_assignments:
		slot_assignments[slot_key] = sender_id
		print("[PrepRoleSelect] 玩家 %d 认领槽位 %s" % [sender_id, slot_key])
	# 如果被别人占了
	else:
		print("[PrepRoleSelect] 槽位 %s 已被占用" % slot_key)
		return
	
	# 广播更新
	_sync_slots.rpc(slot_assignments)


## 客户端 → 服务器：更新准备状态
@rpc("any_peer", "reliable")
func _request_ready(is_ready: bool) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	ready_states[sender_id] = is_ready
	print("[PrepRoleSelect] 玩家 %d 准备状态: %s" % [sender_id, is_ready])
	
	# 广播准备状态
	_sync_ready_states.rpc(ready_states)
	
	# 检查是否可以开始游戏
	_check_start_conditions()


## 服务器 → 所有客户端：同步槽位分配
@rpc("authority", "reliable")
func _sync_slots(data: Dictionary) -> void:
	slot_assignments = data
	_refresh_slots_display()


## 服务器 → 所有客户端：同步准备状态
@rpc("authority", "reliable")
func _sync_ready_states(data: Dictionary) -> void:
	ready_states = data
	_update_status()


## 服务器 → 所有客户端：开始游戏
@rpc("authority", "reliable")
func _start_game() -> void:
	print("[PrepRoleSelect] 所有条件满足，游戏开始！")
	GameManager.go_to_game()


# ============================================================================
# 游戏开始条件检查（服务器端）
# ============================================================================

## 检查是否满足开始条件：
## 1. 所有 16 个槽位全部填满
## 2. 所有玩家都已准备
func _check_start_conditions() -> void:
	# 检查槽位：两队各 4 位置 × 2 角色 = 每队 8 个，共 16 个
	if slot_assignments.size() < 16:
		return
	
	# 检查所有玩家是否准备
	for peer_id in NetworkManager.players:
		if not ready_states.get(peer_id, false):
			return
	
	# 条件全部满足 → 开始游戏！
	print("[PrepRoleSelect] ✅ 所有条件满足，通知开始游戏")
	_start_game.rpc()


# ============================================================================
# UI 刷新
# ============================================================================

## 刷新所有槽位按钮的显示
func _refresh_slots_display() -> void:
	# 遍历红队和蓝队的所有槽位按钮
	_update_team_slots(red_slots)
	_update_team_slots(blue_slots)
	_update_status()


## 更新某队的槽位按钮文字
func _update_team_slots(container: VBoxContainer) -> void:
	for child in container.get_children():
		if child is HBoxContainer:
			for sub_child in child.get_children():
				if sub_child is Button and sub_child.has_meta("slot_key"):
					var slot_key: String = sub_child.get_meta("slot_key")
					if slot_key in slot_assignments:
						var peer_id: int = slot_assignments[slot_key]
						var username: String = NetworkManager.players.get(peer_id, {}).get("username", "???")
						sub_child.text = "[%s]" % username
					else:
						sub_child.text = "[空位]"


## 更新状态文字
func _update_status() -> void:
	var filled: int = slot_assignments.size()
	var ready_count: int = 0
	var total_players: int = NetworkManager.players.size()
	
	for peer_id in NetworkManager.players:
		if ready_states.get(peer_id, false):
			ready_count += 1
	
	status_label.text = "槽位: %d/16 | 准备: %d/%d" % [filled, ready_count, total_players]
