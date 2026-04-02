# ============================================================================
# game_hud.gd — 游戏 HUD 控制脚本
# ============================================================================
# 对应场景：scenes/ui/game_hud.tscn
# 参考 DESIGN.md 第 4.6 节
#
# HUD 显示内容：
#   - 当前局数 / 总局数
#   - 双方累计得分
#   - 当前投壶方（队伍 + 位置 + 第几壶）
#   - 后手标记（Hammer）
#   - 各队剩余壶数
#   - 逐局得分明细（右下角得分板）
# ============================================================================

extends CanvasLayer

# ============================================================================
# 节点引用
# ============================================================================

@onready var round_label: Label = %RoundLabel              ## 局数显示
@onready var score_label: Label = %ScoreLabel              ## 总分显示
@onready var turn_label: Label = %TurnLabel                ## 当前投壶信息
@onready var hammer_label: Label = %HammerLabel            ## 后手标记
@onready var stones_left_label: Label = %StonesLeftLabel   ## 剩余壶数
@onready var score_grid: GridContainer = %ScoreGrid        ## 逐局得分板
@onready var my_team_label: Label = %MyTeamLabel            ## 我的队伍显示

# ============================================================================
# 位置名称（用于显示）
# ============================================================================

const POSITION_NAMES: Array[String] = ["一垒", "二垒", "三垒", "四垒"]

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	print("[GameHUD] HUD 已加载")


# ============================================================================
# 公开方法 — 由 GameMain 调用更新显示
# ============================================================================

## 更新局数显示
## @param current: 当前局数（从 1 开始）
## @param total: 总局数
func update_round(current: int, total: int) -> void:
	round_label.text = "第 %d 局 / 共 %d 局" % [current, total]


## 更新总分
## @param red_score: 红队总分
## @param blue_score: 蓝队总分
func update_score(red_score: int, blue_score: int) -> void:
	score_label.text = "🔴 红队 %d : %d 🔵 蓝队" % [red_score, blue_score]


## 更新当前投壶信息
## @param team: 队伍 ID（0=红, 1=蓝）
## @param position_index: 位置索引（0~3）
## @param stone_number: 壶编号（1~8）
func update_turn(team: int, position_index: int, stone_number: int) -> void:
	var team_name: String = "红队" if team == 0 else "蓝队"
	var pos_name: String = POSITION_NAMES[position_index] if position_index < POSITION_NAMES.size() else "?"
	turn_label.text = "当前: %s %s #%d壶" % [team_name, pos_name, stone_number]


## 更新后手标记
## @param team: 拥有后手的队伍（0=红, 1=蓝）
func update_hammer(team: int) -> void:
	var team_emoji: String = "🔴 红队" if team == 0 else "🔵 蓝队"
	hammer_label.text = "后手: %s" % team_emoji


## 更新剩余壶数
## @param red_left: 红队剩余壶数
## @param blue_left: 蓝队剩余壶数
func update_stones_left(red_left: int, blue_left: int) -> void:
	stones_left_label.text = "剩余壶数: 红 %d  蓝 %d" % [red_left, blue_left]


## 更新本地玩家所属队伍显示
func update_my_team(team: int) -> void:
	if team == 0:
		my_team_label.text = "我的队伍: 🔴 红色方"
		my_team_label.modulate = Color(1, 0.4, 0.4, 1) # 浅红
	elif team == 1:
		my_team_label.text = "我的队伍: 🔵 蓝色方"
		my_team_label.modulate = Color(0.4, 0.6, 1, 1) # 浅蓝
	else:
		my_team_label.text = "我的队伍: 观众"
		my_team_label.modulate = Color.WHITE


## 更新逐局得分板
## @param round_scores: 逐局得分数据
##   格式: [{ "red": int, "blue": int }, ...]
func update_scoreboard(round_scores: Array) -> void:
	# 清空现有内容
	for child in score_grid.get_children():
		child.queue_free()
	
	# 设置列数：局数标题 + 每局分数 + Total
	var total_columns: int = round_scores.size() + 2
	score_grid.columns = total_columns
	
	# --- 表头行 ---
	var header_label: Label = Label.new()
	header_label.text = "局"
	score_grid.add_child(header_label)
	
	for i in range(round_scores.size()):
		var col_label: Label = Label.new()
		col_label.text = str(i + 1)
		col_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_grid.add_child(col_label)
	
	var total_header: Label = Label.new()
	total_header.text = "合计"
	total_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_grid.add_child(total_header)
	
	# --- 红队行 ---
	var red_header: Label = Label.new()
	red_header.text = "红队"
	red_header.modulate = Color(1, 0.4, 0.4, 1)
	score_grid.add_child(red_header)
	
	var red_total: int = 0
	for score_data in round_scores:
		var val: int = score_data.get("red", 0)
		red_total += val
		var cell: Label = Label.new()
		cell.text = str(val) if val > 0 else "0"
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_grid.add_child(cell)
	
	var red_total_label: Label = Label.new()
	red_total_label.text = str(red_total)
	red_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_grid.add_child(red_total_label)
	
	# --- 蓝队行 ---
	var blue_header: Label = Label.new()
	blue_header.text = "蓝队"
	blue_header.modulate = Color(0.4, 0.6, 1, 1)
	score_grid.add_child(blue_header)
	
	var blue_total: int = 0
	for score_data in round_scores:
		var val: int = score_data.get("blue", 0)
		blue_total += val
		var cell: Label = Label.new()
		cell.text = str(val) if val > 0 else "0"
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_grid.add_child(cell)
	
	var blue_total_label: Label = Label.new()
	blue_total_label.text = str(blue_total)
	blue_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_grid.add_child(blue_total_label)
