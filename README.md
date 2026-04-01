# 🥌 whgame_Curling — 冰壶多人在线游戏

基于 Godot 4.6.1 的 2D 多人在线冰壶游戏，采用公网 ENet 专用服务器架构。

## 🎮 游戏特色

- **真实冰壶规则**：4 位置 × 2 角色制，交替投壶，后手权系统
- **2D 俯视角**：简洁高效的物理模拟
- **多人联机**：公网 ENet 服务器，最多 8 人同场竞技（4v4）
- **服务器权威**：物理模拟全部在服务器端运行，有效杜绝作弊

## 📂 项目结构

```
whgame_Curling/
├── project.godot                    # 项目配置
├── DESIGN.md                        # 设计蓝图
├── README.md                        # 本文件
│
├── scenes/                          # .tscn 场景文件
│   ├── ui/                          # UI 界面
│   │   ├── login.tscn               # 登录界面
│   │   ├── lobby.tscn               # 大厅
│   │   ├── create_room_dialog.tscn  # 创建房间弹窗
│   │   ├── prep_team_select.tscn    # 选边界面
│   │   ├── prep_role_select.tscn    # 选位置界面
│   │   ├── game_hud.tscn            # 游戏 HUD
│   │   └── result_screen.tscn       # 结算界面
│   ├── game/                        # 游戏核心
│   │   ├── curling_stone.tscn       # 冰壶预制体
│   │   ├── curling_sheet.tscn       # 赛道
│   │   ├── house_marker.tscn        # 大本营标记
│   │   └── game_main.tscn           # 游戏主场景
│   ├── camera/
│   │   └── game_camera.tscn         # 游戏摄像机
│   └── effects/                     # 特效（开发中）
│
├── scripts/                         # .gd 脚本
│   ├── autoload/                    # 全局单例
│   │   ├── game_manager.gd          # 游戏管理器（模式判断、场景切换）
│   │   └── network_manager.gd       # 网络管理器（ENet、RPC）
│   ├── ui/                          # UI 逻辑
│   ├── game/                        # 游戏逻辑
│   └── network/                     # 网络层
│
├── assets/                          # 资源文件
│   ├── sprites/                     # 图片素材
│   ├── audio/                       # 音效
│   └── fonts/                       # 字体
│
└── resources/                       # Godot 资源
    ├── physics/                     # 物理材质
    └── themes/                      # UI 主题
```

## 🚀 客户端使用

1. 双击 `whgame_Curling.exe` 启动游戏
2. 输入用户名、服务器地址和端口
3. 点击"连接"进入大厅
4. 创建或加入房间，选择队伍和位置后开始游戏

### 操作方式

| 操作         | 按键              |
| ------------ | ----------------- |
| 瞄准方向     | 鼠标移动 / A、D   |
| 逆时针旋转   | Q                 |
| 顺时针旋转   | E                 |
| 蓄力投壶     | 鼠标左键 按住     |
| 释放冰壶     | 鼠标左键 松开     |
| 擦冰         | 鼠标左键 按住     |
| 缩放视角     | 鼠标滚轮          |

## 🖥️ 服务端部署与启动

### 环境要求

- **操作系统**：Windows 或 Linux（公网可访问）
- **端口**：UDP 7777（默认，可自定义）
- **防火墙**：确保服务器端口对外开放

### 启动命令

```bash
# 方式 1：使用导出的 exe + headless 模式
./whgame_Curling.exe --headless -- --server --port 7777

# 方式 2：使用 Godot 编辑器直接运行（开发调试用）
godot --headless --main-pack game.pck -- --server --port 7777
```

### 命令行参数说明

| 参数         | 说明                                      |
| ------------ | ----------------------------------------- |
| `--headless` | Godot 引擎参数：无头模式，不渲染画面      |
| `--`         | Godot 分隔符：之后的参数传给游戏脚本      |
| `--server`   | 游戏参数：以服务器模式启动                |
| `--port N`   | 游戏参数：指定 ENet 监听端口（默认 7777） |

### 服务器模式行为

- 不加载任何 UI（无头运行）
- 自动创建 ENet Server 并监听指定端口
- 管理大厅、房间、准备阶段
- 运行权威物理模拟
- 广播游戏状态给所有客户端

### 部署步骤

1. 在 Godot 编辑器中导出为 Windows 或 Linux 可执行文件
2. 上传至公网服务器
3. 开放 UDP 端口（默认 7777）
4. 运行启动命令
5. 客户端输入服务器地址和端口连接

## 🛠️ 技术栈

| 项目     | 选型                            |
| -------- | ------------------------------- |
| 引擎     | Godot 4.6.1 (GDScript)         |
| 维度     | 2D 俯视角                      |
| 物理     | Godot 内置 2D 物理引擎         |
| 网络     | ENet（公网专用服务器模式）      |
| 服务器   | Godot Headless（无头模式）      |

## 📖 详细设计

请参阅 [DESIGN.md](DESIGN.md) 了解完整的架构设计、规则详解和技术决策。
