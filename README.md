# DSH 开机静默启动

登录 Windows 后自动启动 **DeepSeek Harness** 桌面端，并立刻把主窗口隐藏到系统托盘：
不弹控制台、不显示窗口、任务栏也不留痕迹，托盘里点一下即可恢复。

---

## 一、先说清楚"开机"这件事

Windows 的图形界面程序**不可能在用户登录前显示**（session 0 隔离）。所以对 GUI 程序来说，
严格意义的"开机启动"不存在，业界做法都是"**登录时启动**"。

本方案在**每个用户登录时**触发，效果等同于"开机进去就已经在后台跑着了"。

---

## 二、当前已安装的内容

| 项目 | 值 |
| --- | --- |
| 计划任务名 | `DSH Silent Autostart` |
| 作用范围 | 当前用户 `赵鹏琪\zqp` |
| 启动器 | `C:\Users\zqp\AppData\Local\DshAutostart\Start-DshSilent.vbs` |
| 日志 | `C:\Users\zqp\AppData\Local\DshAutostart\autostart.log` |
| 触发条件 | 登录时（At Logon），先等 10 秒让桌面就绪 |
| 目标程序 | `E:\DeepSeek Harness\DeepSeek Harness.exe` |

> 已实测：手动触发任务返回 `0`，日志正常写入。

---

## 三、文件说明

| 文件 | 作用 |
| --- | --- |
| `Start-DshSilent.ps1` | 核心逻辑：检查 → 启动 → 轮询并隐藏主窗口 → 写日志 |
| `Start-DshSilent.vbs` | 用 `WScript.Shell.Run(..., 0, False)` 无窗口调用上面的 ps1 |
| `Install-DshAutostart.ps1` | 安装 / 卸载计划任务（会把前两个文件复制到 LOCALAPPDATA） |
| `安装dsh自启动.cmd` | 双击：装给当前用户（不需要管理员） |
| `安装dsh自启动-所有用户.cmd` | 双击：装给本机所有用户（会弹 UAC 要管理员） |
| `卸载dsh自启动.cmd` | 双击：卸载 |

---

## 四、安装

**当前用户（推荐，已装好，无需管理员）**

```bat
安装dsh自启动.cmd
```

或命令行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-DshAutostart.ps1
```

**本机所有用户（需要管理员，会弹 UAC）**

```bat
安装dsh自启动-所有用户.cmd
```

脚本检测到没有管理员权限时，会自动用 `Start-Process -Verb RunAs` 重新以管理员身份拉起自己，
所以只要在 UAC 弹窗点"是"即可。

> 每次重装都会把 `Start-DshSilent.ps1` / `.vbs` 的最新版本同步到
> `%LOCALAPPDATA%\DshAutostart\`，因此**改完脚本重新跑一次安装命令就生效**。

---

## 五、验证

**立即验证（不用重启）**

1. 先彻底退出 DSH（托盘图标右键 → 退出），确认任务管理器里没有 `DeepSeek Harness` 进程；
2. 运行：

```powershell
Start-ScheduledTask -TaskName "DSH Silent Autostart"
```

3. 约 15 秒后：屏幕不出现窗口、任务栏无新图标，但**托盘里出现 DSH 图标**；
4. 看日志确认：

```powershell
Get-Content "$env:LOCALAPPDATA\DshAutostart\autostart.log" -Tail 10
```

正常应看到 `started pid xxxx` 和 `hidden 1 window(s)`。

**真实验证**：注销再登录（或重启），观察是否静默进入托盘。

---

## 六、卸载

```bat
卸载dsh自启动.cmd
```

会删除计划任务和 `%LOCALAPPDATA%\DshAutostart\` 整个目录。

---

## 七、工作原理

1. 计划任务在登录时执行 `wscript.exe //B //Nologo "...\Start-DshSilent.vbs"`；
2. VBS 用 `Run(cmd, 0, False)` 以**隐藏窗口**方式启动 PowerShell（所以完全没有黑框一闪）；
3. PowerShell 先 `Start-Sleep 10` 等桌面就绪，然后检查：同名进程已在运行 → 直接跳过，不重复启动；
   （端口 2119 被占用只会记一条日志，不阻止启动 —— 桌面端会自己挑空闲端口，本机实测用过 2119 和 11653）
4. 通过检查才 `Start-Process` 启动 `DeepSeek Harness.exe`；
5. 之后每 200ms 枚举该进程的顶层窗口，一旦出现**可见的、类名为 `Chrome_WidgetWin_1`、尺寸大于 200×200**
   的主窗口，就调用 `ShowWindow(hwnd, SW_HIDE)` 把它隐藏；
6. **只是隐藏，绝不关闭**。窗口一旦被关闭，Electron 会触发 `window-all-closed` 直接退出应用；
   隐藏则应用继续常驻，托盘图标保留，点托盘即可把窗口恢复出来。

---

## 八、注意事项

- **启动瞬间仍可能有一次极短的窗口闪现**：Electron 应用没有内置的"静默启动"参数，主窗口创建后必然
  先 `show()` 一次，我们只能在它出现后的 200ms 内隐藏掉。实测通常快到肉眼难以察觉。
- **和 `dsh web` 可以共存**：桌面端启动时自己挑一个空闲端口（本机先后见过 2119、11653），不强制占用
  2119，所以 web 版在跑也不影响它启动。
- **别移动/删除** `%LOCALAPPDATA%\DshAutostart\`，计划任务指向那里。
- **DSH 换了安装路径**：改 `Start-DshSilent.ps1` 顶部的 `$ExePath` 默认值，再重跑一次安装命令。
- 日志会一直追加，随时可以删掉，不影响运行。
