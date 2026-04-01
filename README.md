# 杭州师范大学校园网助手

这是一个面向杭州师范大学校园网认证场景的 Windows 桌面程序项目，目标是发布为一个可直接双击运行的 exe。

## 当前形态

- 桌面应用：C# + WPF
- 面向系统：Windows
- 认证网络：HZNU
- 认证方式：srun challenge + portal
- 背景图：已内嵌到程序资源中，可直接分发单个 exe

## 用户使用流程

1. 从 GitHub Releases 下载发布包。
2. 双击 `HZNUCampusWifiAssistant.exe`。
3. 程序首次运行时会自动在桌面创建快捷方式。
4. 之后可通过桌面快捷方式打开程序。

## 程序逻辑

### 手动模式

- Wi-Fi 未开启：弹窗提示用户先打开 Wi-Fi。
- 未连接任何 Wi-Fi：弹窗提示先连接 `HZNU`。
- 连接的不是 `HZNU`：弹窗提示当前不是校园网。
- 已连接 `HZNU` 且已在线：弹窗提示无需重新认证。
- 已连接 `HZNU` 且需要认证：进入认证进度页并完成认证。

### 开机自启

- Wi-Fi 未开启：静默退出。
- 未连接任何 Wi-Fi：静默退出。
- 连接的不是 `HZNU`：静默退出。
- 已连接 `HZNU` 且不需要认证：静默退出。
- 已连接 `HZNU` 且需要认证：显示认证进度页，完成后自动退出。

## 项目结构

```text
src/HZNUCampusWifiAssistant/
  App.xaml
  MainWindow.xaml
  Models/
  Services/
  Utilities/
scripts/
  publish.ps1
main_background.jpg
legacy-powershell/
```

## 本地数据存储

程序运行后会将用户数据保存到：

- `%APPDATA%\HZNUCampusWifiAssistant\settings.json`
- `%APPDATA%\HZNUCampusWifiAssistant\credential.dat`

其中账号密码通过 Windows 当前用户加密存储，不写回仓库目录。

## 构建要求

本项目需要安装 `.NET 8 SDK` 或更高版本。

```powershell
dotnet --info
```

## 本地调试

```powershell
dotnet build .\src\HZNUCampusWifiAssistant\HZNUCampusWifiAssistant.csproj
```

## 发布单文件 exe

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish.ps1
```

默认会发布到：

```text
.\artifacts\publish\win-x64\
```

## 说明

- `legacy-powershell/` 中保留了旧的 PowerShell 原型文件，仅用于迁移参考。
- 新版本的目标是整理成一个适合放到 GitHub 并通过 Releases 分发的正式 Windows 客户端项目。
- 当前版本已支持将背景图内嵌到程序资源中，因此发布给用户时可以只提供 exe。
