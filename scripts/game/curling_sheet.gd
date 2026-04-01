# ============================================================================
# curling_sheet.gd — 冰壶赛道控制脚本
# ============================================================================
# 对应场景：scenes/game/curling_sheet.tscn
# 参考 DESIGN.md 第 5.2 节（赛道节点树）
#
# 赛道结构（俯视角，赛道方向：从下→上）：
#   底部（投壶端）────────────────── 顶部（大本营端）
#   
#   投壶起点   前卫线1   前卫线2  T线  大本营  后线
#   (Spawn)    (Hog1)    (Hog2)  (Tee) (House) (Back)
#
# 比例参考（标准冰壶赛道 45.72m × 5m）：
#   游戏内使用像素比例，通过 @export 可调
# ============================================================================

extends Node2D

# ============================================================================
# 导出参数 — 赛道尺寸（像素）
# ============================================================================

## 赛道总长度（像素）
@export var sheet_length: float = 2400.0

## 赛道宽度（像素）
@export var sheet_width: float = 280.0

## 前卫线1 距底部的距离（投壶端前卫线）
@export var hog_line_1_y: float = 600.0

## 前卫线2 距底部的距离（大本营端前卫线）
@export var hog_line_2_y: float = 1800.0

## T 线距底部的距离（大本营中心线）
@export var tee_line_y: float = 2040.0

## 后线距底部的距离
@export var back_line_y: float = 2280.0

## 投壶起点距底部的距离
@export var spawn_point_y: float = 300.0



# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 触发绘制
	queue_redraw()
	print("[CurlingSheet] 赛道已加载 (长:%d 宽:%d)" % [sheet_length, sheet_width])


# ============================================================================
# 赛道绘制
# ============================================================================

func _draw() -> void:
	var half_w: float = sheet_width / 2.0
	
	# --- 冰面背景 ---
	# 赛道从 (0, 0) 到 (0, -sheet_length)，以底部为原点向上延伸
	# 注意：Godot 2D 的 Y 轴向下为正，所以赛道向上 = Y 减小
	var ice_color: Color = Color(0.85, 0.92, 0.97, 1.0)  # 浅冰蓝
	var ice_rect: Rect2 = Rect2(-half_w, -sheet_length, sheet_width, sheet_length)
	draw_rect(ice_rect, ice_color, true)
	
	# --- 赛道边界线 ---
	var border_color: Color = Color(0.3, 0.3, 0.4, 1.0)
	var border_width: float = 3.0
	# 左右边界
	draw_line(Vector2(-half_w, 0), Vector2(-half_w, -sheet_length), border_color, border_width)
	draw_line(Vector2(half_w, 0), Vector2(half_w, -sheet_length), border_color, border_width)
	# 上下边界
	draw_line(Vector2(-half_w, 0), Vector2(half_w, 0), border_color, border_width)
	draw_line(Vector2(-half_w, -sheet_length), Vector2(half_w, -sheet_length), border_color, border_width)
	
	# --- 标线绘制 ---
	var line_color: Color = Color(0.4, 0.4, 0.5, 0.8)
	var line_width: float = 2.0
	var hog_color: Color = Color(0.8, 0.2, 0.2, 0.8)  # 前卫线用红色
	
	# 前卫线 1（投壶端，红色粗线）
	var hog1_y: float = -hog_line_1_y
	draw_line(Vector2(-half_w, hog1_y), Vector2(half_w, hog1_y), hog_color, 3.0)
	
	# 前卫线 2（大本营端，红色粗线）
	var hog2_y: float = -hog_line_2_y
	draw_line(Vector2(-half_w, hog2_y), Vector2(half_w, hog2_y), hog_color, 3.0)
	
	# T 线（大本营中心，与大本营的水平十字重合）
	var tee_y: float = -tee_line_y
	draw_line(Vector2(-half_w, tee_y), Vector2(half_w, tee_y), line_color, line_width)
	
	# 后线
	var back_y: float = -back_line_y
	draw_line(Vector2(-half_w, back_y), Vector2(half_w, back_y), line_color, line_width)
	
	# 中线（纵向中心线，贯穿全长）
	draw_line(Vector2(0, 0), Vector2(0, -sheet_length), line_color, 1.0)
	
	# --- 自由防守区标记（Hog2 ~ 大本营之间）---
	# 用半透明区域标示（参考 DESIGN.md 2.6）
	var fgz_color: Color = Color(0.9, 0.9, 0.3, 0.08)  # 淡黄色
	var fgz_rect: Rect2 = Rect2(-half_w, hog2_y, sheet_width, hog2_y - tee_y + 120)
	draw_rect(fgz_rect, fgz_color, true)
	
	# --- 标注文字 ---
	# 投壶起点标记
	var spawn_y: float = -spawn_point_y
	draw_circle(Vector2(0, spawn_y), 5.0, Color(0.2, 0.8, 0.2, 0.8))


# ============================================================================
# 公开方法
# ============================================================================

## 获取投壶起始位置（世界坐标）
func get_spawn_position() -> Vector2:
	return global_position + Vector2(0, -spawn_point_y)


## 获取 T 线位置（大本营中心 Y 坐标）
func get_tee_position() -> Vector2:
	return global_position + Vector2(0, -tee_line_y)


## 检测冰壶是否出界
## 出界条件：超过后线、超出赛道两侧、或未过前卫线1（无效投壶）
func is_stone_out_of_bounds(stone_pos: Vector2) -> bool:
	var local_pos: Vector2 = stone_pos - global_position
	var half_w: float = sheet_width / 2.0
	
	# 超出左右边界
	if abs(local_pos.x) > half_w + 20:
		return true
	
	# 超过后线（Y 更小 = 更上方）
	if local_pos.y < -back_line_y - 20:
		return true
	
	# 回到投壶端后方
	if local_pos.y > 20:
		return true
	
	return false


## 检测冰壶是否在大本营内（用于得分判定）
## 大本营范围：以 T 线位置为中心，12 英尺环半径
func is_stone_in_house(stone_pos: Vector2) -> bool:
	var tee_pos: Vector2 = get_tee_position()
	var distance: float = stone_pos.distance_to(tee_pos)
	# 12 英尺环半径 = 6 英尺 × 20 像素/英尺 = 120 像素
	return distance <= 120.0
