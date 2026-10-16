# 主界面、选关与缩略图

普通运行项目会进入 B「风过群岛」主界面。开始旅程沿用教学偏好：未进入正式挑战时进入水库入门；已有偏好时进入正式关序第一项。本次运行已有进行中的局面时显示“继续本局”。返回主界面保留天气并暂停，关闭程序后不恢复本局天气。

选关卡片单击只改变预览，点击“开始本关”才重新开局；从游戏中打开选关，返回恢复之前的暂停状态。游戏内 Esc 打开菜单，子页面 Esc 返回来源；空格只在游戏中暂停／继续。主界面、选关、说明和设置期间不推进天气、时限或风源寿命。声音开关／音量仍用原有偏好文件。

## 风雨转场

主界面与选关用风线掠过；开始／继续、下一关、重试和返回主界面用薄云合拢再散开；说明、设置与暂停使用短淡入。转场期间取消拨风并暂时冻结天气，画面揭开、可以操作后才继续计时，连点不会反复加载。

设置中的“减少转场动态（本次运行）”可将整屏风幕／云幕改为短淡入，下次启动恢复默认。动画基准时长和绘制位于 `scripts/weather_transition.gd`；遮挡加载与等新画面就绪的时间另计，避免露出半成品场景。详见[转场接入说明](theme-transition-implementation.md)。

## 调整关卡与画面

- 正式关序继续编辑 `configs/campaign.tres` 的 Levels 数组；可以添加、移除、排序，选关不会写死九张。打开选关或点“重新读取关卡”重读配置，坏配置保留上次有效列表。
- 名称、说明、目标和工具继续编辑地图资源；选关信息直接读取资源。风纹纪录按地图 ID 保留，改顺序不会丢纪录。
- 共同颜色、按钮、面板和正文字体在 `themes/front_menu.tres`；外边距在 `scenes/front_menu.tscn` 的 Margin 节点。页面内部使用原生容器自动排布，文案在 `scripts/front_menu.gd`。
- 中央程序云展示使用 FrontMenu 的 `preview_map_path`，默认 level03；它是独立显示模型，不推进天气、不参与游戏，不会把展示云放入玩家开局。离开主界面即停止展示视口更新。

## 地图缩略图

缩略图为正常开局的实际地图渲染，文件在 `assets/ui/level_previews/<地图ID>.png`，仅用于菜单。新增或修改地图后，在项目根目录 PowerShell 执行：

```powershell
$previewEngine = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
Start-Process -FilePath $previewEngine -ArgumentList @('--path', ('"' + (Get-Location).Path + '"'), '--script', 'res://tests/generate_level_previews.gd') -WindowStyle Hidden -Wait
```

工具按 campaign 串行生成教学和正式关图，960×540 渲染后保存为640×360，不模拟通关、不修改地图或玩家资料。临时图写入 `.godot/level-preview-build/`，写入成功后才替换原图。Godot 编辑器随后导入图像，保留对应 `.import` 元数据。缺少缩略图时只缺图，不影响名称、详情及开始关卡。

## 开发与检查

地图编辑器试玩、`--map`、`--layout`、`--free-play`、`--single-plot`、云／冷风小样仍直达玩法。需要直接测试原玩法的独立脚本加 `--skip-menu`，或创建主场景实例后、加入树之前设置 `show_front_menu=false`。

`--fresh-guide` 仍表示不读取／不写入正式玩家资料，单独使用它仍会看见新主界面。完整检查脚本为旧玩法项补上 `--skip-menu`，新菜单专项和完整入口回放覆盖正常启动。

原生菜单专项为 `tests/test_front_menu.gd`；`tests/profile_front_menu.gd` 仅测新入口的短期渲染／暂停表现，不替代 V1 正式天气压力验收。实际记录见[入口界面审阅](front-menu-review.json)。
