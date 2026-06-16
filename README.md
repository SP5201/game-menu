<div align="center">

# 游戏菜单 · QDesktop

**Windows 桌面快捷方式启动器** — Delphi XE2 · Win32 / Win64 · XCGUI 自绘界面

[![Delphi](https://img.shields.io/badge/Delphi-XE2-ee1f35?style=flat-square)](https://www.embarcadero.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20Win32%20%7C%20Win64-0078d4?style=flat-square)](https://learn.microsoft.com/windows/win32/winprog64/wow64-implementation-details)
[![UI](https://img.shields.io/badge/UI-XCGUI-5c6bc0?style=flat-square)](库/XCGUI/)

</div>

## 这是什么

QDesktop 把常用程序、文件夹、快捷方式按**分类**收纳在主界面网格里：左侧选分类，右侧点图标即可启动。支持拖放入库、全库搜索、右键编辑；底部状态栏展示外网 IP、天气、网速与 CPU / 内存 / GPU 占用，悬停可看硬件与网卡详情。

## 运行

> 演示程序在 **`Debug/`** 下，无需安装 Delphi。
>
> 进入 `Debug/Win32/` 或 `Debug/Win64/`，双击 **`QDesktop.exe`** 即可。

| 运行期数据 | 路径 | 说明 |
| :--- | :--- | :--- |
| 配置 | `Debug/*/Data/QDesktop.ini` | 窗口位置、采样开关、GDI/D2D 等 |
| 启动项库 | `Debug/*/Data/games.db` | SQLite：分类与条目 |
| 图标缓存 | `Debug/*/Data/IconCache/` | 程序图标本地缓存 |
| 搜索索引库 | `Debug/*/Data/Everything.db` | NTFS 全盘索引缓存（本地生成） |

`games.db`、`Everything.db` 仅本地使用，**不入 Git**。

---

## 功能一览

### 启动器

| 能力 | 说明 |
| :--- | :--- |
| 分类管理 | 自定义名称、图标（`Resource/CategoryIcons/`）、条目宽度、排序方式 |
| 入库 | 拖放 `.exe`、快捷方式、文件夹到主界面；Shell 提取图标写入 SQLite |
| 启动 | 双击或右键打开；支持参数、工作目录、管理员运行 |
| 编辑 | 改显示名、路径、图标；分类对话框、条目编辑对话框 |
| 系统工具 | 右键菜单快捷打开注册表、设备管理器、服务、磁盘管理等 |

### 搜索

| 能力 | 说明 |
| :--- | :--- |
| 库内搜索 | 在当前分类 / 全库中按名称筛选启动项 |
| 全盘索引 | `功能/索引/`：读取 NTFS MFT 建索引，USN 日志增量更新；结果供主界面搜索框使用 |

### 状态栏

| 显示 | 数据来源 |
| :--- | :--- |
| CPU / 内存 / GPU 占用 | 后台采样线程 → `功能/硬件/`（PDH、Native API、PawnIO MSR 等） |
| 上 / 下行网速 | `GetIfTable2` 汇总 |
| 外网 IP、归属地 | HTTP → myip.ipip.net |
| 天气、温度 | HTTP → Open-Meteo |
| 悬停详情 | CPU 型号、内存条、网卡 MAC、GPU 显存等（按需查询，非采样线程拼接） |

### 其它

| 能力 | 说明 |
| :--- | :--- |
| 二维码 | 内置生成器（圆角、颜色、液化），可导出 PNG |
| 设置 | GDI/D2D、绘制频率、开机启动、状态栏采样开关等 |
| 反馈 | 邮件反馈对话框 |
| 单实例 | 重复启动时激活已有窗口 |

---

## 目录与文件

### 工程根（源码与工程）

| 路径 | 代表什么 |
| :--- | :--- |
| `QDesktop.dpr` | 程序入口：单实例、读配置、初始化 XCGUI、加载主布局、消息循环 |
| `QDesktop.dproj` | Delphi 工程（Win32 + Win64，UTF-8 源码页 65001） |
| `QDesktopResource.rc` | 编译进 exe 的资源脚本 |
| `编译测试.bat` | 一键清理 DCU、编译 Debug Win32/Win64（编码与 Delphi 环境写法见 `.cursor/rules/encoding.mdc`） |
| `Dcu/` | 编译中间文件（`Win32/`、`Win64/`） |

### `窗口/` — 页面与交互

绑定 `Resource/Layout/*.xml`，注册事件，调用 `功能/`；**不写**磁盘/注册表/驱动等底层 I/O。

| 单元（示例） | 作用 |
| :--- | :--- |
| `UI_MainWindow.pas` | 主窗口：分类、列表、拖放、搜索、状态栏编排 |
| `UI_MainWindowStat.pas` | 状态栏后台线程与 `WM_QD_*` 回 UI |
| `UI_MainWindowTools.pas` | 系统工具菜单等 |
| `UI_SettingsDialog.pas` | 设置对话框 |
| `UI_QrCodeDialog.pas` / `UI_QrCodeRender.pas` | 二维码生成与绘制 |
| `UI_FeedbackDialog.pas` | 反馈邮件 |
| `UI_ColorPickerDialog.pas` | 取色 |
| `UI_ListViewSettingsDialog.pas` | 列表显示选项 |
| `UI_HintPopup.pas` / `UI_SliderValuePopup.pas` | 提示、滑块弹层 |
| `UI_SafeLogWindow.pas` | 启动日志窗口 |

### `样式/` — 可复用 UI 组件

XCGUI 封装、默认样式、主题色；**不含**业务逻辑。

| 单元（示例） | 作用 |
| :--- | :--- |
| `UI_Theme.pas` | **唯一色板**（`UITheme_*`），全程序语义色来源 |
| `UI_Button.pas` / `UI_Edit.pas` / `UI_ComboBox.pas` | 基础控件 |
| `UI_Icon_ListView.pas` / `UI_ListBox.pas` / `UI_List.pas` | 图标网格、列表 |
| `UI_SearchBox.pas` | 搜索框 |
| `UI_InfoListPopup.pas` | 状态栏悬停详情列表 |
| `UI_ProgressBar.pas` / `UI_ScrollBar.pas` / `UI_SliderBar.pas` | 进度、滚动、滑块 |
| `UI_Form.pas` / `UI_Ele.pas` | 窗体、元素基类 |

### `功能/` — 业务与系统访问

不调用 `XEle_*` / `XDraw_*` 等 UI API；需刷新界面时发消息，由 `窗口/` 消费。

| 子目录 | 代表什么 |
| :--- | :--- |
| `功能/配置/` | `AppConfig.pas`、`AppPaths.pas` — `QDesktop.ini`、路径、GDI/D2D、绘制频率、开机启动 |
| `功能/数据库/` | `LibraryStore.pas` — SQLite 分类与启动项 CRUD |
| `功能/Shell/` | 图标提取、拖放、启动执行（`ShellExecuteEx`）、打开方式、磁盘路径 |
| `功能/索引/` | NTFS MFT 索引（`MftReader`、`EverythingDb`、`EverythingIndex`）、USN 增量（`UsnMonitor`）、搜索 VM（`SearchVM`） |
| `功能/硬件/` | CPU / 内存 / GPU / 网速详情与采样；`PawnIoClient` 驱动传感器 |
| `功能/硬件/CPU/` · `Mem/` · `GPU/` · `Net/` | 各硬件 `*Info*.pas`、Native / PawnIO 分层 |
| `功能/天气IP/` | 外网 IP、城市坐标、天气拉取与解析 |
| `功能/网络/` | `NetHttpWorker.pas`（libcurl）、`FeedbackMailer.pas` |
| `功能/日志/` | `SafeLog.pas` — 启动与诊断日志 |
| `ListItemTypes.pas` | 启动项、分类等共享类型 |

### `库/` — 第三方与 API 绑定

**只读引用**，业务逻辑不要写进此目录。

| 路径 | 代表什么 |
| :--- | :--- |
| `库/XCGUI/` | 炫彩界面库 Delphi 封装 |
| `库/SQLite3/` | SQLite C API + `SQLite3Wrap` |
| `库/libcurl/` | libcurl 声明（运行时 DLL 在 `Debug/*/Bin/`） |
| `库/ZXingQRCode/` | 二维码生成 |

### `Debug/Win32/` · `Debug/Win64/` — 编译输出与运行目录

| 路径 | 代表什么 |
| :--- | :--- |
| `QDesktop.exe` | 可执行文件 |
| `Bin/` | 运行时 DLL：`XCGUI_*.dll`、`Sqlite3.dll`、libcurl、OpenSSL、`PawnIO.sys` 与 CPU 模块（`IntelMSR.bin` 等） |
| `Resource/` | 界面资源（随 exe 旁加载） |
| `Resource/Layout/` | 布局 XML 源稿（Win64 与 Win32 同步） |
| `Resource/CategoryIcons/` | 分类可选 SVG 图标 |
| `Resource/Category/default.svg` | 默认分类图标 |
| `Resource/QWeatherIcons/` | 天气图标 |
| `Resource/CpuVendor/` | CPU 厂商 SVG |
| `Resource/*.svg` | 工具栏、菜单等界面图标 |
| `Resource/Resource.res` | 打包进程序的资源（字体、色板等 ID） |
| `Data/` | 运行期数据（见上文 [运行](#运行)） |

### 其它

| 路径 | 代表什么 |
| :--- | :--- |
| `.cursor/rules/` | Cursor Agent 约定（`global.mdc`、`ui.mdc`、`feature.mdc`、`encoding.mdc`） |
| `README.md` | 本说明 |

---

## 技术概要

| 项 | 说明 |
| :--- | :--- |
| 语言 | Delphi XE2，Win32 / Win64（Win32 为 WOW64 进程） |
| UI | XCGUI：XML 布局 + 自绘，GDI / D2D |
| 分层 | `窗口/` → `样式/` → `功能/` → `库/`；UI 与业务分离 |
| 线程 | 采样、索引、HTTP 在后台线程；回 UI 用 `XC_PostMessage` / `PostMessageW` + `WM_QD_*` |
| 硬件 | 优先驱动（PawnIO）→ Native API → WMI/注册表兜底 |

**启动顺序**：读 `QDesktop.ini` → 初始化 XCGUI → 加载 `Resource.res` 与 `MainWindow.xml` → `XRunXCGUI` 消息循环。

**编译**（需本机 Delphi XE2）：

```bat
cd /d "d:\游戏菜单"
编译测试.bat nopause
```

---

<div align="center">

<sub>文档随仓库维护 · 新增子目录请在上表补充</sub>

</div>
