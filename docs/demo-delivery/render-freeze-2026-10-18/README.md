# 画面冻结：图形后端对照启动

这是针对“画面停住，但声音和点击反馈仍在”的诊断启动脚本。受影响的Iris Xe机器已反馈Vulkan启动后不再卡住；脚本不改变游戏规则、地图、存档或原EXE。

## 先试这一项

1. 把本ZIP中的三个`.cmd`文件解压到`WeavingRain.exe`旁边。不要在压缩包内直接运行。
2. 完全退出原来的游戏，再双击 **Start-Vulkan.cmd**。像平时一样游玩，尤其试一试主界面进入教学、教学结束和前两关。
3. 记下是否仍卡住、出现在哪个界面、声音和点击反馈是否继续。若卡住，可试最小化再恢复／调整窗口大小，记录能否恢复。
4. 退出后，把本次日志反馈给开发者。日志在资源管理器地址栏输入 **%LOCALAPPDATA%\WeavingRain\Diagnostics** 即可找到；每次启动独立命名，不会覆盖旧日志。

普通双击EXE仍沿用原D3D12设置。脚本只对本次启动指定后端；想恢复原方式，直接正常运行EXE即可。不用安装Godot，也不用重下载整个包。

## 三个文件的作用

| 文件 | 作用 |
| --- | --- |
| Start-Vulkan.cmd | 首先尝试：保留Forward+，仅改用Vulkan后端，记录详细日志 |
| Start-D3D12.cmd | 原D3D12后端对照，也记录详细日志 |
| Start-Vulkan-LowResolution.cmd | 若普通Vulkan仍卡住，再尝试1100×700窗口，初步区分分辨率负载与后端问题；不更改云采样或天气数值 |

同一时间只开一份游戏。窗口关闭后，启动脚本会显示退出码和日志路径，按键关闭即可。日志由Godot生成，可能含本地路径，分享前可以先查看；脚本不自动上传任何信息。

## 当前实际情况

用户报告的机器为Intel Core i5-13500H、16GB RAM、Intel Iris Xe，Windows具体版本／驱动版本及最小化恢复结果未知。此机原先可在主界面或第二关等处高频冻结；用户现已确认Start-Vulkan.cmd启动后不再卡住。完整日志实际使用Intel Iris Xe、Vulkan 1.4.323、Forward+；无ERROR、SCRIPT ERROR或DEVICE_LOST，一条加载器注册表清单查找警告，含level01／level02资源加载。没有游玩时长与完整通关证据，不能断言底层根因或所有机器均已稳定。

本地同一份Release EXE已经分别在Intel UHD（D3D12）与RaptorLake-S Mobile Graphics Controller（Vulkan）短时启动显示，以及Intel／RTX 4060的Vulkan第二关启动显示，均退出0。这只是本机短测，不是对方Iris Xe验收或整局稳定性证明。

本机Vulkan日志有OBS JSON及mediasdkhook DLL缺失的加载错误，虽然画面能够显示，也不能写成所有日志干净；未修改系统录屏软件、注册表、显卡驱动或图层设置。实际低分辨率启动脚本的调用、日志创建、退出码与截图已验证。

[Godot官方图形后端说明](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-driver-windows)支持在Windows的Forward+路径选择D3D12或Vulkan；[Intel D3D12画面异常报告](https://github.com/godotengine/godot/issues/116919)仅用于说明调查方向，不能证明本项目是同一个问题。当前建议下一版将Windows默认后端改为Vulkan，并做相关显示／流程复验；本次仅更新记录，项目配置及现有EXE仍是D3D12，玩家继续使用Start-Vulkan.cmd。诊断ZIP保留最初交付字节，其内README早于本次反馈。
