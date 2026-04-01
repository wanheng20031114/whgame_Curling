# ============================================================================
# login.gd — 登录界面控制脚本
# ============================================================================
# 对应场景：scenes/ui/login.tscn
# 参考 DESIGN.md 第 4.2 节
#
# 功能：
#   1. 输入用户名（纯显示用，不做身份验证）
#   2. 输入服务器地址和 ENet 端口
#   3. 点击连接 → 通过 ENet 连接到公网服务器
#   4. 连接成功后自动进入大厅
# ============================================================================

extends Control

# ============================================================================
# 节点引用 — 使用 %UniqueNodeName 获取场景中的唯一节点
# ============================================================================

@onready var username_input: LineEdit = %UsernameInput      ## 用户名输入框
@onready var server_input: LineEdit = %ServerInput            ## 服务器地址输入框
@onready var port_input: LineEdit = %PortInput                ## 端口输入框
@onready var connect_button: Button = %ConnectButton          ## 连接按钮
@onready var status_label: Label = %StatusLabel               ## 状态显示

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 连接 NetworkManager 的信号
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	
	# 连接按钮点击事件
	connect_button.pressed.connect(_on_connect_button_pressed)
	
	# 设置状态为等待
	_set_status("等待连接...")
	
	print("[Login] 登录界面已加载")


# ============================================================================
# 按钮事件处理
# ============================================================================

## 点击"连接"按钮
func _on_connect_button_pressed() -> void:
	# --- 验证输入 ---
	var username: String = username_input.text.strip_edges()
	var server: String = server_input.text.strip_edges()
	var port_text: String = port_input.text.strip_edges()
	
	# 检查用户名
	if username.is_empty():
		_set_status("⚠️ 请输入用户名")
		return
	
	# 检查服务器地址
	if server.is_empty():
		_set_status("⚠️ 请输入服务器地址")
		return
	
	# 检查端口
	if not port_text.is_valid_int():
		_set_status("⚠️ 端口必须是数字")
		return
	
	var port: int = port_text.to_int()
	if port < 1 or port > 65535:
		_set_status("⚠️ 端口范围: 1-65535")
		return
	
	# --- 保存信息到 GameManager ---
	GameManager.local_username = username
	GameManager.server_address = server
	GameManager.server_port = port
	
	# --- 发起连接 ---
	_set_status("正在连接到 %s:%d ..." % [server, port])
	connect_button.disabled = true  # 防止重复点击
	
	var error: Error = NetworkManager.connect_to_server(server, port)
	if error != OK:
		_set_status("❌ 连接失败！错误码: %d" % error)
		connect_button.disabled = false


# ============================================================================
# 网络信号回调
# ============================================================================

## 成功连接到服务器
func _on_connected_to_server() -> void:
	_set_status("✅ 已连接！正在进入大厅...")
	
	# 向服务器注册用户名
	# rpc_id(1, ...) 表示只发送给服务器（服务器的 peer_id 固定为 1）
	NetworkManager.register_player.rpc_id(1, GameManager.local_username)
	
	# 延迟一小会后切换到大厅，让注册消息先发出
	await get_tree().create_timer(0.5).timeout
	GameManager.go_to_lobby()


## 连接失败
func _on_connection_failed() -> void:
	_set_status("❌ 连接服务器失败！请检查地址和端口")
	connect_button.disabled = false


## 断开连接
func _on_disconnected() -> void:
	_set_status("⚠️ 与服务器断开连接")
	connect_button.disabled = false


# ============================================================================
# 工具方法
# ============================================================================

## 更新状态标签显示
func _set_status(text: String) -> void:
	status_label.text = "状态: " + text
	print("[Login] %s" % text)
