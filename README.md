# RustDeskScreenOff

## 中文

RustDesk 远程连接自动熄屏工具，保护你的隐私。

### 功能

- 当有人通过 RustDesk 远程连接到你的 Mac 时，本地屏幕自动变黑，防止旁人看到远程操作内容
- 远程连接断开后，屏幕自动恢复并锁屏
- 远程端画面不受影响，正常显示桌面
- 菜单栏显示当前状态（监控中 / 已熄屏）
- 开机自动启动，无需手动操作

### 使用方法

1. 编译并运行：
   ```bash
   ./build_app.sh
   open RustDeskScreenOff.app
   ```
2. 启动后菜单栏出现眼睛图标，App 在后台自动工作
3. 无需任何配置，开箱即用
4. 点击菜单栏图标可查看状态或退出

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- 已安装 RustDesk

---

## English

Auto screen-off tool for RustDesk remote connections. Protects your privacy.

### Features

- Automatically blacks out the local screen when someone connects to your Mac via RustDesk, preventing bystanders from seeing remote activity
- Restores the screen and locks it when the remote connection ends
- The remote viewer's display is unaffected — they see the desktop normally
- Menu bar icon shows current status (monitoring / screen off)
- Launches automatically at login, no manual action needed

### Usage

1. Build and run:
   ```bash
   ./build_app.sh
   open RustDeskScreenOff.app
   ```
2. An eye icon appears in the menu bar — the app works automatically in the background
3. No configuration needed, works out of the box
4. Click the menu bar icon to check status or quit

### Requirements

- macOS 14.0 (Sonoma) or later
- RustDesk installed
