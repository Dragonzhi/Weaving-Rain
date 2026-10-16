# BGM首轮候选试听

2026-10-16。用户要求A／B／C都准备多个试听；本轮各两段，共六段。采用作者页面标注CC0的现成音乐截取与试配，音乐由下表作者创作，不记录为本项目原创。用户试听后反馈“A1 比较好啊”，将A1《Meadow Thoughts》记为首选；其余候选保留作比较历史。认可范围为本次片段方向，完整曲目、循环接缝及正式混音仍待处理与试听。

每份对比24.6秒：0–12秒纯音乐，12–12.6秒留白，12.6–24.6秒重复相同音乐并叠现有游戏风雨。混合段轻风持续、2秒后远景小雨渐起、7秒后加入密雨；六段使用相同天气，不能当实际天气回放。音乐在淡入淡出前按-26 LUFS目标整理，真实循环接缝和最终混音待选曲后制作。

| 编号／方向 | 原曲与作者 | 截取 | 来源标注 |
| --- | --- | --- | --- |
| A1 空灵自然 · 竖琴 | [Meadow Thoughts](https://opengameart.org/content/meadow-thoughts) — Écrivain | 15–27秒 | CC0 |
| A2 空灵自然 · 环境铺底 | [Contemplation](https://opengameart.org/content/contemplation-0) — Joth | 18–30秒 | CC0 |
| B1 轻快田园 · 明亮节奏 | [Apple Cider](https://opengameart.org/content/apple-cider) — Zane Little Music | 25–37秒 | CC0 |
| B2 轻快田园 · 村落舞步 | [Tavern](https://opengameart.org/content/tavern-0) — yd | 8–20秒 | CC0 |
| C1 温暖抒情 · 钢琴氛围 | [Mystical Piano](https://opengameart.org/content/mystical-piano) — Indieteur | 22–34秒 | CC0 |
| C2 温暖抒情 · 钢琴旋律 | [Gem Popper Piano Tune](https://opengameart.org/content/gem-popper-piano-tune) — Mopz | 10–22秒 | CC0 |

## 播放与重现

在项目根目录执行 `python tools/make_bgm_auditions.py`。使用现有numpy和ffmpeg，原曲与作者网页、PCM中间文件、纯音乐／风雨单独版本以及MP3对比留`.godot/bgm-audition/`，不放入正式assets。`A1-comparison.mp3`至`C2-comparison.mp3`为对比试听；`manifest.json`记录网址、作者、截取点、源文件与输出SHA256和幅度指标。

六份MP3均已核对：24.6秒、44.1kHz立体声，完整解码无错误；PCM最大绝对幅度约0.21–0.28，未发生削波。这里只做文件与信号检查，未宣称已完成主观听感、正式循环或Godot运行混音验收。

没有改正式播放器、音效文件、偏好、地图或天气规则；没有导出包或Git提交。下一步围绕A1制定接入方案：以完整曲目为基础处理循环，切页／重试连续播放，并安排独立音乐音量与风雨混音。以上为后续建议，当前尚未接入。

后续状态：用户授权后已完成A1接入，见[接入说明](bgm-implementation.md)与[实际检查](bgm-review.json)。上文未接入描述仅指首轮候选制作阶段。
