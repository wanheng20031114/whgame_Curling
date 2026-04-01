# ============================================================================
# game_camera.gd — 游戏摄像机控制脚本
# ============================================================================
# 对应场景：scenes/camera/game_camera.tscn
# 参考 DESIGN.md 第 4.6 节（相机行为表）
#
# 相机行为：
#   投壶前 — 镜头固定在投壶端（赛道底部），鼠标滚轮可缩放
#   投壶后 — 镜头 Y 轴跟随冰壶移动，所有人同步观看
#   擦冰中 — 跟随视角不变，擦冰员操作叠加在视角中
#   壶停止 — 镜头回到投壶端（平滑过渡）
#   一局结束 — 镜头切到大本营俯视，展示得分判定
# ============================================================================

extends Camera2D

# ============================================================================
# 导出参数
# ============================================================================

## 跟随平滑速度（越大越快）
@export var follow_speed: float = 5.0

## 最小缩放（放大极限）
@export var min_zoom: float = 0.5

## 最大缩放（缩小极限）
@export var max_zoom: float = 2.0

## 缩放步长（每次滚轮操作的变化量）
@export var zoom_step: float = 0.1

## 投壶端默认位置（赛道底部）
@export var spawn_view_position: Vector2 = Vector2(0, -300)

## 大本营俯视位置
@export var house_view_position: Vector2 = Vector2(0, -2040)

# ============================================================================
# 枚举 — 相机模式
# ============================================================================

enum CameraMode {
	FIXED_SPAWN,    ## 固定在投壶端
	FOLLOW_STONE,   ## 跟随冰壶
	FIXED_HOUSE,    ## 固定在大本营（得分判定）
	TRANSITION,     ## 过渡中（平滑移动到目标位置）
}

# ============================================================================
# 状态变量
# ============================================================================

## 当前相机模式
var current_mode: CameraMode = CameraMode.FIXED_SPAWN

## 跟随目标节点
var follow_target: Node2D = null

## 过渡目标位置
var transition_target: Vector2 = Vector2.ZERO

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 初始位置：投壶端
	position = spawn_view_position
	zoom = Vector2(1.0, 1.0)
	print("[GameCamera] 摄像机已加载，初始位置: %s" % position)


func _process(delta: float) -> void:
	match current_mode:
		CameraMode.FIXED_SPAWN:
			# 固定在投壶端，不移动
			pass
		
		CameraMode.FOLLOW_STONE:
			# Y 轴跟随冰壶，X 轴可以微调
			if follow_target and is_instance_valid(follow_target):
				var target_pos: Vector2 = Vector2(
					position.x,  # X 轴保持不变（赛道中心）
					follow_target.position.y  # Y 轴跟随冰壶
				)
				position = position.lerp(target_pos, follow_speed * delta)
		
		CameraMode.FIXED_HOUSE:
			# 固定在大本营
			pass
		
		CameraMode.TRANSITION:
			# 平滑过渡到目标位置
			position = position.lerp(transition_target, follow_speed * delta)
			if position.distance_to(transition_target) < 2.0:
				position = transition_target
				# 过渡完成后根据目标位置判断最终模式
				if transition_target.distance_to(spawn_view_position) < 10:
					current_mode = CameraMode.FIXED_SPAWN
				elif transition_target.distance_to(house_view_position) < 10:
					current_mode = CameraMode.FIXED_HOUSE


func _unhandled_input(event: InputEvent) -> void:
	# --- 鼠标滚轮缩放（投壶前可用） ---
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				# 放大（zoom 增大）
				var new_zoom: float = clampf(zoom.x + zoom_step, min_zoom, max_zoom)
				zoom = Vector2(new_zoom, new_zoom)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				# 缩小（zoom 减小）
				var new_zoom: float = clampf(zoom.x - zoom_step, min_zoom, max_zoom)
				zoom = Vector2(new_zoom, new_zoom)


# ============================================================================
# 公开方法 — 由游戏主场景调用
# ============================================================================

## 切换到跟随冰壶模式
func start_following(stone: Node2D) -> void:
	follow_target = stone
	current_mode = CameraMode.FOLLOW_STONE
	print("[GameCamera] 开始跟随冰壶")


## 回到投壶端（平滑过渡）
func return_to_spawn() -> void:
	transition_target = spawn_view_position
	current_mode = CameraMode.TRANSITION
	zoom = Vector2(1.0, 1.0)  # 重置缩放
	print("[GameCamera] 镜头回到投壶端")


## 切换到大本营俯视（一局结束时）
func view_house() -> void:
	transition_target = house_view_position
	current_mode = CameraMode.TRANSITION
	print("[GameCamera] 镜头移到大本营")


## 直接设置位置（无过渡）
func set_position_immediate(pos: Vector2) -> void:
	position = pos
	current_mode = CameraMode.FIXED_SPAWN
