# TapTap 上传素材 · 2026-10-18

按用户提供的素材要求制作，当前为待观感确认的交付版；尚未上传或获得平台审核通过。

**直接取用：[五份PNG素材包](WeavingRain-TapTap-assets.zip)。** 压缩包只有下表五张图，没有说明、参考图或其他文件。也可逐张取用 `upload/` 中的PNG。

| 上传位置 | 文件 | 尺寸 | 文件大小 |
| --- | --- | --- | --- |
| 16:9 宣传图／视频封面 | [promo-1920x1080.png](upload/promo-1920x1080.png) | 1920×1080 | 1.58 MB |
| 游戏LOGO | [logo-transparent.png](upload/logo-transparent.png) | 1375×594，透明背景 | 0.10 MB |
| 横版游戏封面 | [cover-landscape-1840x860.png](upload/cover-landscape-1840x860.png) | 1840×860，460:215 | 1.28 MB |
| 竖版游戏封面 | [cover-portrait-1200x1800.png](upload/cover-portrait-1200x1800.png) | 1200×1800，2:3 | 1.81 MB |
| 游戏库背景壁纸 | [wallpaper-3840x1240.png](upload/wallpaper-3840x1240.png) | 3840×1240 | 2.53 MB |

大小按十进制MB列出；前四份均低于4,000,000字节，壁纸低于10,000,000字节。LOGO满足“宽不低于1280或高不低于720”中的宽度条件，四周仅约10px透明安全边。用户粘贴的横竖标签错位，按尺寸理解为横版460:215、竖版2:3。

![16:9 宣传图](upload/promo-1920x1080.png)

## 平台游戏图标补充

按新增要求提供 [icon-square-1024.png](upload/icon-square-1024.png)：1024×1024、RGB PNG，约82KB。青绿色背景铺满方形画布，无透明通道、无自行裁切圆角；沿用已认可的风托云矢量图案。此文件单独下载，不在上面的五图ZIP中。

矢量源为 `sources/icon-square.svg`；固定Godot执行 `--headless --script res://docs/demo-delivery/taptap-2026-10-18/render-icon.gd` 可重建。`Start-Process -Wait` 确认退出0，PNG完整解码、1024方形／RGB／四色角和SVG无圆角检查通过，已目视；见 `icon-review.json`。首次直接调用未取得输出，未计为成功；平台上传／审核尚未执行。项目根图标和既有UID未改。

## 内容与来源

沿用已选定的晴海送雨方向，以当前 `../visuals/cover-source-level03.png` 和 `tools-source.png` 实机截图为造型／细节上限参考，通过 **内置 image_gen** 生成三种重新构图的插画。没有将实机截图直接加字或拼贴充当新宣传图，也没有增加建筑、人物、树木或游戏中不存在的玩法元素。岛屿、简单山体、分层云、细雨、田池和白风线仍对应当前游戏。

宣传图和两种封面只有“风织雨 / WEAVING RAIN”这组游戏标题，无宣传语、作者署名、应用图标、界面或角标。文字LOGO复用既有高亮宋体方向；它是标题文字标，可叠放到画面上，不是青绿方形应用图标。壁纸完全无字，主体在右侧，左侧约40%保留低细节海面供页面UI覆盖。

原始生成图在 `sources/`，最终提示词与参考角色见 `prompts.json`。生成原生尺寸分别为1672×941、1024×1536、2206×713；`render-assets.gd` 使用Godot原生字体与画布重新排版、采样到所需输出尺寸，并非原生3840px生成图。只交付字体栅格结果，不分发字体文件。没有替换游戏内美术或根目录图标。

## 已执行的检查

- 固定Godot 4.7.2图形运行 `--script res://docs/demo-delivery/taptap-2026-10-18/render-assets.gd`，最终退出0；`.godot/taptap-assets-20261018-final.log`无脚本错误。第一遍共享图片函数的浮点尺寸精确比较曾断言失败，已按整像素取整并重新导出全部五份。
- `python docs/demo-delivery/taptap-2026-10-18/verify-assets.py`：五份PNG完整解码、尺寸／严格字节上限、LOGO透明通道与四周边距检查通过；ZIP只有五张最终图，CRC通过。
- 已逐张查看主宣传图、透明文字标、横竖封面及宽幅壁纸。原图散列、导出检查和限制见 `review.json`。
- 用户最终观感和TapTap上传／审核未验证。两份远程反例URL未能读取，依据用户完整文字要求和附图制作；没有将本地尺寸检查写成平台审核通过。

这轮仅素材交付，没有游戏导出、提交、推送、平台上传或完整玩法／性能复验。旧封面含宣传句与署名，保留为历史；本轮指定上传字段请使用这里的 `upload/` 文件。
