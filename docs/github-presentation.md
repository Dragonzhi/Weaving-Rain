<!-- contentType: Reference -->
# GitHub 页面维护

2026-10-21。本页记录仓库首页的内容分工和素材来源，方便更新版本时同步入口。

## 页面分工

- 根 README：介绍玩法、展示实机、引导试玩，再提供源码入口
- `docs/README.md`：按游玩、制图、开发和交付组织文档导航
- `AGENTS.md`：开发协作约束与验证方式
- 任务看板、策划、各阶段 review：保留开发进度、决定与技术证据

当前公开 PC 入口由作者提供，页面访问校验为200且标题为《风织雨》：<https://www.taptap.cn/app/981551?os=pc>。作者确认已交稿；不据此推断平台审核、五篇日志或50名有效试玩要求已经达成。

## 仓库简介与主题

建议简介：

> 风织雨 / Weaving Rain · 拨动空气，组织云雨，为群岛上的田地与水库送雨。Godot 天气操控解谜游戏｜聚光灯 21 天 GameJam 作品。

主页链接使用上方 TapTap PC 页面。主题为 `godot`、`godot4`、`gdscript`、`game-jam`、`weather`、`puzzle-game`、`simulation`、`windows`、`indie-game`。以上简介、主页和九个主题已于2026-10-21通过GitHub CLI实际应用并读取回验。README源码随后通过Git同步，发布结果见TASKS.md本轮交接。

## 配图与徽章

README 复用仓库中三份已审阅的实机素材，不新增 AI 插画或修改游戏资产：

| 位置 | 文件 | 来源 |
| --- | --- | --- |
| 封面 | `demo-delivery/visuals/cover-sunny-sea-draft.png` | 正常第三关实机，隐藏 HUD 后排字 |
| 留风聚云 | `demo-delivery/visuals/tools-source.png` | 第七关真实鼠标工具操作的原图 |
| 海上借雨 | `demo-delivery/visuals/storm-source.png` | 第八关正常风暴局面的原图 |

以上为开发期画面，界面细节以当前 Demo 为准。来源证据保留在 `demo-delivery/visual-review.json` 与 `media-review.json`。视频使用已完成的35秒宣传片，不重录或重混音。

四枚 Shields.io 静态徽章表示引擎版本、语言、Windows 平台与 Demo 版本，不表示 CI、性能或平台审核通过。第三方徽章不可用时，README 的文字、试玩和文档链接仍可使用。

## 更新版本时核对

更新 Demo 徽章和交付记录链接，核对 TapTap 入口以及分发版本。未上传 GitHub Release 附件时，不把忽略的 `builds/` 路径当成下载按钮。没有统一项目许可证时，不添加 MIT／开源许可徽章，也不将第三方 CC0 音乐写成原创或整个游戏的授权。
