# 统一视觉语言实施交接

日期：2026-10-13，更新2026-10-14。状态：雨滴、池水位、悬浮状态与风纹UI已接入；实际检查范围及待验收项见[UI实施记录](../ui-review.json)。本文件保留设计交接，不表示玩家体验已验收。

## 权威方案与依据

- 完整步骤、布局、数值回退、输入、存档与验收：[当前UI实施计划](../ui-implementation-plan.md)。后续实施以该文件为准，不并行维护第二份完整计划。
- 视觉规范：[DESIGN.md](DESIGN.md)。
- 用户决定与推定初值：[design-contract.md](design-contract.md)。
- 已认可参考：[reference-images.md](reference-images.md)。
- 项目约束：AGENTS.md；主要代码：game_hud.gd、weather_simulation.gd、plot_needs.gd、level_rating.gd；基线5d208f8。

## 执行摘要

农田同大固定单位雨滴（暂取20）、末滴余量与显式分组；池独立水位。水量、危险／安全符号及整局风纹分开。浮字单层、短暂、输入穿透。界面用米白、灰蓝、柔金、薄线和中文系统字体，按两尺寸检查字号与锚点。

顺序：共用图形→目标水量和浮字→风纹及结果→标题／工具栏统一→动画／完整检查→截图与本地包。首份实机小样必须证明五种农田状态及池满规则，不只做结果页。

原生Button／OptionButton继续承担操作，风源关闭锁定稳定ID；显示不影响天气、评价和存档，暂停冻结动画。内部star字段和最高纪录版本不改。

## 当前场景交接

用户认可初版UI，随后授权提交基线8f24ca7并在codex/scene-volume分支执行。完整步骤以[场景实施计划](../scene-volume-implementation-plan.md)为准；统一受光与地面材料已接入，实际范围见[实施记录](../scene-volume-review.json)。[整体／云体／田池参考](scene-reference-images.md)仍是概念。

先读cloud.gdshader、cloud_field.gdshaderinc、terrain.gdshader、weather_view.gd及ui-review.json。复用地形固定光向，云约四档、地面两三档，影子冷而浅；先云＋山，再云影／海岸，再田／池。图中地形位置、云瓣和石纹不照搬，不导入固定天气素材。

首份产物须有薄云／厚云／雨云及移动长边GPU对照、云形／拾取不变和短性能数据。不可因加光照减少原采样或拖慢模拟；表面估计细节先小样选定。农田／池轮廓、实际雨区与原生UI输入保留，1920×1080及1280×720审阅；正式长测、原生波动继续开放。

本轮不扩展声音、独立开始／选关页面或投稿。显示参数在configs/scene_style.tres，R／切图重读，F6不改。原V1／V6与新场景试玩反馈仍开放。

地面第二轮交接：用户反馈云层次丰富而地面变化不足，指定[原整体图](scene-references/final-style-target.png)为最终风格目标。[第二轮计划](../ground-volume-implementation-plan.md)覆盖首轮装饰高度限制，执行田台0.36、池沿0.52、向内倒角、浅几何田垄、双叶合并植株与同高度场静态山影。真实山坡、目标轮廓、0.27–0.39水位映射和天气规则保留；地块轮廓与对应标记按显示表面投影。侧面须遵循Godot顺时针正面，不能用关闭剔除掩盖朝向错误。投影是固定光向下的静态近似，不冒充落雨或完整物理光照。
