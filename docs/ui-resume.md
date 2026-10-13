# UI实施接续

2026-10-14：用户提醒电脑即将没电关机，立即结束耗时验证并保存检查点。

UI已接入；雨滴／水位／状态／悬浮字／风纹／原生工具与结果均可在项目F5查看。验收没有全部完成，见 [ui-review.json](ui-review.json)。旧独立zip还不是这轮UI版。

继续时先运行 `tests/capture_ui_review.gd` 审阅最后的结果按钮配色和池水线裁切，再重跑 `tests/test_ui_visuals.gd` 两种尺寸。正常参数为 `--fresh-guide --layout=needs_lab`，GPU不可用headless代替。

保留 `.godot/vortex-viewport-route-check.log` 的失败证据，再用 `tests/run_checks.ps1 -StartAt vortex-viewport-route` 继续后段。该次失败为幼苗55.0424超过55，不改玩法阈值、不注水、不清天气来制造通过。若复跑通过也记录先前失败，保留V6回放波动。

相关检查完成后做短UI开／关压力对照（profile_runtime新增 `--hud-off`，JSON／CSV含hud_draw_ms），正式长性能依原安排。最后用4.7.2模板重导出、烟测和压缩包更新，再完成文档状态。

参考图和视觉规范已归档于 `docs/visual-language/`，完整计划为 `docs/ui-implementation-plan.md`。场景美术、声音、开始／选关页面未扩展。
