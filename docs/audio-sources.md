# 风雨音效来源与制作

2026-10-14。首轮实机反馈及四轮小样后，用户明确认可风／A雨衔接和5条拨风差分，授权接入。随后实机反馈风基本合适，雨起得突然且近处敲击与远景不符；现沿相同雨源增加远景处理与独立渐起／渐退，用户认可当前版本并要求存档。短拨仍为已确认风底裁剪，原吹气感风切和嘈杂B雨已淘汰。候选听感认可不等于完整游戏混音或长时间疲劳感验收。

| 游戏文件 | 来源、作者与许可 | 处理 |
| --- | --- | --- |
| `assets/audio/wind.wav` | [wind1](https://opengameart.org/content/wind1)，Luke.RUSTLTD，CC0；作者用PureData预先合成，**不是自然实录** | 原文件截取第4秒起18秒，去直流、平滑滤掉极低／刺耳频段、音量余量、0.6秒接缝交叉渐变；最终17.4秒单声道 |
| `assets/audio/rain.wav` | [rain rws natural 3-23-2019 151am.wav](https://freesound.org/people/Andron827/sounds/464334/)，Andron827，CC0；户外雨、地面／落木／叶片雨滴录音 | 页面公开HQ MP3试听版本，不是登录下载的原始WAV；离线解码单声道，取第8–30秒，去直流、控制峰值，再用远景EQ及软峰值削弱近处雨滴，处理后RMS约0.0157；最终21.4秒 |
| `assets/audio/rain_detail.wav` | [Rain, Heavy, Falling on Leaves](https://freesound.org/people/CHallSmith/sounds/870824/)，CHallSmith，CC0 | 公开HQ MP3解码保留立体声，第63–77秒，原A雨RMS0.085，再施加远景EQ与软峰值，不补回削去的音量；当前RMS约0.0479，0.6秒平滑接缝后13.4秒。旧文件名／UID保留，随实际雨强接替小雨 |
| `brush.wav`、`brush_2.wav`至`brush_5.wav` | 与wind.wav同源，Luke.RUSTLTD，CC0 | 五条正式文件与第四轮获认可的差分逐字节相同，取wind.wav的4.4／5.2／6.4／7.5／8.7秒附近，单段0.60–0.69秒、RMS0.038。裁剪和起落不同，未添加新噪声。速度音高由原生播放控制 |
| `click.wav`、`source.wav`、`adequate.wav`、`safe.wav`、`full.wav`、`damage.wav`、`success.wav`、`failure.wav` | 本项目离线脚本原创 | 带起落包络的轻木片／水滴音；与首轮已认可版本相同，不接触游戏随机数 |

初轮淘汰来源：[Rain on Window Loop](https://opengameart.org/content/rain-on-window-loop)，alxl，页面明确提供CC0。已下载原文件并加工试听，**没有进入当前游戏素材**，仅保留缓存及历史试听以说明用户反馈。不得把初版窗面录音写成合成源，用户“合成感”描述的是听感。

原文件及候选留`.godot/`，不提交。仅当前16份素材、对应Godot导入标识、制作脚本和来源记录随项目保留。素材为44.1kHz／16位PCM WAV，风／小雨单声道，拨风差分／A密雨立体声；Godot导入保留PCM、不归一化。循环由实际帧数设置，不拿压缩字节长度推算。播音随机使用独立RandomNumberGenerator和不重复抽签袋，不使用天气全局随机数。

## 重现

将[wind1.wav](https://opengameart.org/sites/default/files/wind1.wav)、[小雨公开HQ试听](https://cdn.freesound.org/previews/464/464334_1504845-hq.mp3)和[A密雨公开HQ试听](https://cdn.freesound.org/previews/870/870824_18412227-hq.mp3)放入`.godot/audio-source/`。后两者分别解码为`rain_outdoor.wav`（单声道）、`rain_leaves.wav`（立体声），均44.1kHz PCM16。运行`python tools/make_audio.py`；使用已有numpy，无新增安装。工具会重现16份正式声音及缓存试听和指标；不属于游戏运行依赖。

源文件SHA256：

- wind1.wav：`A2856F794FBF77E05F8241DC4ADEADE7F62FA21C3C9DC49F7725B6C6218060C3`
- 淘汰的rain_on_window_loop.wav：`97B9405025E5ED7ED8A58D24DD7146D06E925519B1F718EFDA94BB85DCD1A61A`
- 当前rain_outdoor.mp3：`EBF3AB59C140A5D44F939F3F871A58ED205377DCCCB02FE6D0147D29535FCADB`
- 解码rain_outdoor.wav：`5D0F38305BE50604F595374AAC4F16CCB4BF1B4EC24297BBED998E11306079F7`
- A密雨rain_leaves.mp3：`5D6743E22B7E9966757A3FA22BB87B83983F0E0BE6F7E499EB59A9639B6980C6`。

远景处理为100Hz平滑高通、约1.2kHz开始的柔和高频衰减和4.2kHz低通，再作声道共用阈值软峰值控制；不加噪声、混响或处理后增益。运行时雨声独立渐起／渐退，不改变素材循环或实际落雨。

首轮历史散列与数字保留在`audio-review.json`；五差分接入历史见`audio-refinement-review.json`，当前两份雨声散列和检查见`rain-distance-review.json`。CC0来源保留作者致谢，原创短音由本项目制作；不修改整个项目许可。
