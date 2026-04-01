# ============================================================================
# result_screen.gd — 结算界面控制脚本
# ============================================================================
# 对应场景：scenes/ui/result_screen.tscn
# 参考 DESIGN.md 第 4.7 节
#
# 功能：
#   1. 显示最终比分（红队 vs 蓝队）
#   2. 显示逐局得分明细
#   3. 点击"返回大厅"回到大厅界面
# ============================================================================

extends Control

# ============================================================================
# 节点引用
# ============================================================================

@onready var score_label: Label = %ScoreLabel          ## 总比分显示
@onready var score_grid: GridContainer = %ScoreGrid    ## 逐局得分网格
@onready var return_button: Button = %ReturnButton     ## 返回大厅按钮

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	return_button.pressed.connect(_on_return_pressed)
	
	# TODO: 从 GameManager 或 NetworkManager 获取实际比赛数据
	# 目前使用占位数据展示
	_display_results()
	
	print("[ResultScreen] 结算界面已加载")


# ============================================================================
# 按钮事件
# ============================================================================

## 点击"返回大厅"
func _on_return_pressed() -> void:
	print("[ResultScreen] 返回大厅")
	GameManager.go_to_lobby()


# ============================================================================
# 结果展示
# ============================================================================

## 显示比赛结果
## TODO: 接入实际比赛数据后完善此函数
func _display_results() -> void:
	# 占位数据 — 后续从 GameManager 中读取实际比赛结果
	var red_total: int = 0
	var blue_total: int = 0
	
	score_label.text = "🔴 红队  %d  :  %d  🔵 蓝队" % [red_total, blue_total]
	
	# TODO: 根据实际局数填充逐局得分网格
	var placeholder: Label = Label.new()
	placeholder.text = "（比赛数据将在游戏逻辑完成后接入）"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.modulate = Color(0.6, 0.6, 0.6, 1)
	score_grid.add_child(placeholder)
