# ============================================================================
# curling_stone.gd — 冰壶控制脚本
# ============================================================================
# 对应场景：scenes/game/curling_stone.tscn
# 参考 DESIGN.md 第 5.2（冰壶节点树）、第 6 节（物理模拟设计）
#
# 冰壶物理特性：
#   - 使用 RigidBody2D 实现刚体物理
#   - 摩擦力：每帧施加与运动方向相反的减速力
#   - 弧线（Curl）：根据旋转方向施加侧向力
#   - 擦冰区域降低摩擦系数
#   - 碰撞由 Godot 物理引擎自动处理
#
# 注意：物理模拟仅在服务器端运行（DESIGN.md 3.5）
#       客户端只做位置和角度的视觉插值
extends RigidBody2D



# ============================================================================
# 导出参数 — 使用 @export 暴露给引擎检查器（DESIGN.md 核心原则 1.1）
# ============================================================================

## 所属队伍（0 = 红队, 1 = 蓝队）
@export var team: int = 0

## 壶编号（1~8，每队 8 壶）
@export var stone_index: int = 1

## 冰面摩擦系数（参考 DESIGN.md 6.1）
## 真实值参考 0.003~0.01，游戏默认 0.006
@export var friction_coefficient: float = 0.006

## 擦冰后摩擦系数倍率（参考 DESIGN.md 6.1）
## 约降低至原来的 60%
@export var sweep_friction_multiplier: float = 0.6

## 弧线系数 — 旋转引起的侧向偏移力度（参考 DESIGN.md 6.1）
@export var curl_factor: float = 0.15

## 速度阈值 — 低于此速度视为停止（参考 DESIGN.md 6.1）
@export var stop_threshold: float = 5.0

# ============================================================================
# 状态变量
# ============================================================================

## 旋转方向：-1 = 逆时针, 0 = 无旋转, 1 = 顺时针
var spin_direction: int = 0

## 当前是否被擦冰（由擦冰员操作驱动）
var is_being_swept: bool = false

## 冰壶是否已停止运动
var is_stopped: bool = true

## 冰壶是否出界（被移除）
var is_out_of_bounds: bool = false

# ============================================================================
# 信号
# ============================================================================

## 冰壶停止运动时发出
signal stone_stopped(stone: RigidBody2D)

## 冰壶出界时发出
signal stone_out_of_bounds(stone: RigidBody2D)

# ============================================================================
# 节点引用
# ============================================================================

## 冰壶编号标签
@onready var stone_label: Label = $StoneLabel

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 设置冰壶显示
	_update_visual()
	
	# 初始状态：冻结（直到被投掷）
	freeze = true
	
	print("[CurlingStone] 冰壶 #%d (队伍 %d) 已创建" % [stone_index, team])


func _physics_process(_delta: float) -> void:
	# 物理模拟仅在服务器端运行
	if not multiplayer.is_server():
		return
	
	# 如果冻结或已停止，跳过物理计算
	if freeze or is_stopped:
		return
	
	# --- 获取当前速度 ---
	var velocity: Vector2 = linear_velocity
	var speed: float = velocity.length()
	
	# --- 停止检测 ---
	if speed < stop_threshold:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		is_stopped = true
		freeze = true
		stone_stopped.emit(self)
		print("[CurlingStone] 冰壶 #%d 已停止" % stone_index)
		return
	
	# --- 摩擦力模拟 ---
	# 计算当前使用的摩擦系数（擦冰时降低）
	var current_friction: float = friction_coefficient
	if is_being_swept:
		current_friction *= sweep_friction_multiplier
	
	# 摩擦减速力 = 摩擦系数 × 重力 × 质量，方向与运动方向相反
	# 简化模型：直接对速度施加反向力
	var friction_force: Vector2 = -velocity.normalized() * current_friction * 9800.0 * mass
	apply_central_force(friction_force)
	
	# --- 弧线（Curl）模拟 ---
	# 仅在有旋转且速度足够时施加侧向力
	if spin_direction != 0 and speed > stop_threshold * 2:
		# 侧向力方向：旋转方向 × 速度方向垂直分量
		# 顺时针旋转(spin=1) → 向右偏, 逆时针(spin=-1) → 向左偏
		var perpendicular: Vector2 = Vector2(-velocity.y, velocity.x).normalized()
		var curl_force: Vector2 = perpendicular * spin_direction * curl_factor * speed
		apply_central_force(curl_force)


# ============================================================================
# 公开方法
# ============================================================================

## 投掷冰壶
## @param direction: 投掷方向（单位向量）
## @param power: 投掷力度（像素/秒）
## @param spin: 旋转方向（-1/0/1）
func throw(direction: Vector2, power: float, spin: int) -> void:
	freeze = false
	is_stopped = false
	spin_direction = spin
	
	# 设置初始线速度
	linear_velocity = direction.normalized() * power
	
	print("[CurlingStone] 冰壶 #%d 投掷 - 方向: %s, 力度: %.1f, 旋转: %d" % [
		stone_index, direction, power, spin
	])


## 设置擦冰状态
func set_sweep(sweeping: bool) -> void:
	is_being_swept = sweeping


## 标记出界
func mark_out_of_bounds() -> void:
	is_out_of_bounds = true
	visible = false
	freeze = true
	stone_out_of_bounds.emit(self)
	print("[CurlingStone] 冰壶 #%d 出界！" % stone_index)


# ============================================================================
# 视觉更新
# ============================================================================

## 根据队伍和编号更新冰壶显示
func _update_visual() -> void:
	# 更新编号标签
	if stone_label:
		stone_label.text = str(stone_index)
	
	# 应用高清冰壶贴图（使用动态 load 防止无头服务器未 import 而崩溃）
	var sprite: Sprite2D = $Sprite2D
	if sprite:
		var tex: Texture2D
		if team == 0:
			tex = load("res://assets/sprites/curling_stone_red.png")
		else:
			tex = load("res://assets/sprites/curling_stone_blue.png")
			
		if tex:
			sprite.texture = tex
		else:
			# 降级：如果找不到图片，则用老办法染色
			if team == 0: modulate = Color(1.0, 0.3, 0.3, 1.0)
			else: modulate = Color(0.3, 0.5, 1.0, 1.0)
