<!-- contentType: Landing; audience: players, level authors and developers; goal: find the appropriate current guide without treating historical reviews as current specifications. -->
# 风织雨文档导航

从你想完成的事情进入。游玩操作、地图制作和开发记录分别维护，历史方案与验证报告保留当时的版本和边界。

[返回项目首页](../README.md) · [TapTap PC 试玩](https://www.taptap.cn/app/981551?os=pc) · [任务看板](task-board.md)

## 游玩与反馈

| 文档 | 内容 |
| --- | --- |
| [游玩指南](demo-delivery/PLAYER_GUIDE.md) | 从水库教学开始，认识工具、田池、雨量与风纹 |
| [制作与素材鸣谢](demo-delivery/CREDITS.md) | 音乐、风雨声音和引擎的来源与许可 |
| [Demo 0.1.2 交付记录](demo-delivery/package-0.1.2-2026-10-20.md) | 版本、目录、构建散列、实际检查和已知问题 |
| [GitHub Issues](https://github.com/Dragonzhi/Weaving-Rain/issues) | 报告问题，附上关卡、操作和设备信息 |

当前试玩入口为 [TapTap PC 页面](https://www.taptap.cn/app/981551?os=pc)。`builds/` 是本机构建目录，不随 Git 分发；仓库内的本地 ZIP 路径不能作为公开下载链接。

## 制作与编排关卡

| 文档或资源 | 内容 |
| --- | --- |
| [新建关卡与编辑器指南](level-editor-guide.md) | 选模板、另存、拖动编辑、校验与试玩 |
| [地图编辑与调参](map-authoring.md) | 地图字段、湿空气源、目标需求与暖海配置 |
| [关卡工具配置](tool-availability.md) | 按关开放拨风、风带和漩涡 |
| [九关内容核对](level-content-review.md) | 当前正式地图的内容与关名；难度仍需试玩反馈 |
| [关卡流程安排](level-flow-plan.md) | 教学与正式地图的衔接背景 |
| [`campaign.tres`](../configs/campaign.tres) | 教学资源与正式关卡顺序 |
| [`weather.tres`](../configs/weather.tres) | 天气与风力配置，字段说明见对应脚本 |

先读编辑器指南完成一张地图，再用参数参考细调；不必为每关新建运行场景。

## 开发、视觉与声音

| 文档 | 内容 |
| --- | --- |
| [开发协作说明](../AGENTS.md) | 架构约束、代码入口、验证与文件维护 |
| [完整策划与讨论历史](cloud-weather-game-design-v0.1.md) | 玩法决策和各阶段方案；按日期与当前代码区分历史 |
| [视觉规范](visual-language/DESIGN.md) | 青绿、米白、灰蓝的符号与界面方向 |
| [教学与前期节奏](onboarding-and-early-pacing.md) | 五节点、无进展帮助、暂停说明与前期时限 |
| [试玩可用性修整](usability-followup.md) | F11、跨栏拖动、近距淡化、折叠柄及教学聚焦 |
| [声音来源](audio-sources.md) | 实际使用的音频资产与处理方法 |
| [BGM 接入记录](bgm-implementation.md) | 配乐循环、播放生命周期与混音 |
| [性能与稳定性记录](performance-stability-review.md) | 已执行的采样、未达标项目与排查边界 |
| [GitHub 页面维护](github-presentation.md) | README 配图来源、徽章、简介及公开入口维护 |

规则、视口和回放工具位于 [`tests/`](../tests/)，使用方式以开发协作说明为准。自动检查通过不等于新玩家体验、全部硬件或平台审核通过。

## 宣传与交付资料

公开素材和发布草稿从[交付入口](demo-delivery/README.md)查阅，包括[35 秒宣传片](demo-delivery/visuals/weaving-rain-trailer.mp4)、[TapTap 指定图像](demo-delivery/taptap-2026-10-18/README.md)和[开发者日志草稿](demo-delivery/devlogs/README.md)。素材来源与实际发布状态分别记录，不把草稿当成已发布。
