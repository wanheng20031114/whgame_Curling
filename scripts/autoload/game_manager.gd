# ============================================================================
# game_manager.gd — 全局游戏管理器（Autoload 单例）
# ============================================================================
# 职责：
#   1. 判断当前运行模式（客户端 / 服务器）
#   2. 管理全局游戏状态（当前界面、房间信息等）
#   3. 场景切换调度
#
# 模式判断依据：
#   - 服务器模式：通过命令行参数 --server 启动
#     示例：./whgame_Curling.exe --headless -- --server --port 7777
#   - 客户端模式：正常启动（无 --server 参数）
#
# 参考 DESIGN.md 第 3.6 节
# ============================================================================

extends Node

# ============================================================================
# 信号定义
# ============================================================================

## 当运行模式确定后发出
signal mode_determined(is_server: bool)

## 当场景切换时发出
signal scene_changing(scene_name: String)

# ============================================================================
# 枚举
# ============================================================================

## 游戏状态枚举，对应 UI 流转图（DESIGN.md 4.1）
enum GameState {
	NONE,           ## 未初始化
	LOGIN,          ## 登录界面
	LOBBY,          ## 大厅
	PREP_TEAM,      ## 准备阶段1：选边
	PREP_ROLE,      ## 准备阶段2：选位置
	PLAYING,        ## 游戏进行中
	RESULT,         ## 结算界面
}

# ============================================================================
# 导出参数
# ============================================================================

## 默认 ENet 端口（服务器模式使用）
@export var default_port: int = 7777

## 最大连接数
@export var max_clients: int = 8

# ============================================================================
# 公开变量
# ============================================================================

## 当前是否为服务器模式
var is_server: bool = false

## 当前游戏状态
var current_state: GameState = GameState.NONE

## 本地玩家用户名
var local_username: String = ""

## 服务器地址（客户端模式下使用）
var server_address: String = ""

## 服务器端口
var server_port: int = 7777

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 解析命令行参数，判断运行模式
	_parse_command_line_args()
	
	if is_server:
		print("[GameManager] ===== 服务器模式启动 =====")
		_start_server_mode()
	else:
		print("[GameManager] ===== 客户端模式启动 =====")
		_start_client_mode()
	
	mode_determined.emit(is_server)


# ============================================================================
# 私有方法
# ============================================================================

## 解析命令行参数
## Godot 的 `--` 之后的参数通过 OS.get_cmdline_user_args() 获取
## 例如：godot --headless -- --server --port 7777
## 则 user_args = ["--server", "--port", "7777"]
func _parse_command_line_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	print("[GameManager] 命令行用户参数: ", args)
	
	for i in range(args.size()):
		match args[i]:
			"--server":
				is_server = true
			"--port":
				# 读取 --port 后面的数值
				if i + 1 < args.size():
					var port_str: String = args[i + 1]
					if port_str.is_valid_int():
						server_port = port_str.to_int()
						default_port = server_port
						print("[GameManager] 端口设置为: ", server_port)


## 启动服务器模式
## 服务器不加载 UI，直接创建 ENet Server 并等待连接
## 服务器模式下不切换任何场景（headless 不需要 UI）
func _start_server_mode() -> void:
	print("[GameManager] 服务器将在端口 %d 上监听" % default_port)
	
	# 等待 NetworkManager 初始化完成后再创建服务器
	# （因为 autoload 的加载顺序：GameManager 先于 NetworkManager）
	call_deferred("_create_enet_server")
	current_state = GameState.LOBBY


## 延迟创建 ENet 服务器（确保 NetworkManager 已就绪）
func _create_enet_server() -> void:
	var error: Error = NetworkManager.create_server(default_port, max_clients)
	if error != OK:
		print("[GameManager] ❌ 服务器创建失败！程序退出。")
		get_tree().quit(1)
	else:
		print("[GameManager] ✅ ENet 服务器已启动，等待客户端连接...")


## 启动客户端模式
## 加载登录界面，等待用户操作
func _start_client_mode() -> void:
	current_state = GameState.LOGIN
	# 切换到登录场景
	# 使用 call_deferred 确保场景树初始化完成后再切换
	call_deferred("_load_login_scene")


# 加载登录场景
func _load_login_scene() -> void:
	print("[GameManager] 加载登录界面...")
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")


# ============================================================================
# 公开方法 — 场景切换
# ============================================================================

# 切换到大厅
func go_to_lobby() -> void:
	print("[GameManager] 切换到大厅")
	current_state = GameState.LOBBY
	scene_changing.emit("lobby")
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


## 切换到准备阶段1：选边
func go_to_prep_team() -> void:
	print("[GameManager] 切换到准备阶段 - 选边")
	current_state = GameState.PREP_TEAM
	scene_changing.emit("prep_team")
	get_tree().change_scene_to_file("res://scenes/ui/prep_team_select.tscn")


## 切换到准备阶段2：选位置
func go_to_prep_role() -> void:
	print("[GameManager] 切换到准备阶段 - 选位置")
	current_state = GameState.PREP_ROLE
	scene_changing.emit("prep_role")
	get_tree().change_scene_to_file("res://scenes/ui/prep_role_select.tscn")


## 切换到游戏主场景
func go_to_game() -> void:
	print("[GameManager] 切换到游戏场景")
	current_state = GameState.PLAYING
	scene_changing.emit("game")
	get_tree().change_scene_to_file("res://scenes/game/game_main.tscn")


## 切换到结算界面
func go_to_result() -> void:
	print("[GameManager] 切换到结算界面")
	current_state = GameState.RESULT
	scene_changing.emit("result")
	get_tree().change_scene_to_file("res://scenes/ui/result_screen.tscn")


## 返回登录界面（断开连接时调用）
func go_to_login() -> void:
	print("[GameManager] 返回登录界面")
	current_state = GameState.LOGIN
	scene_changing.emit("login")
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")
