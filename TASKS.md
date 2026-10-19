# Weaving Rain

status: 进行中
next: 停在五节点教学、局部帮助、暂停说明／R与Esc入口及前四关360／420／420／360秒已实现，源码技术验证已记录；下一步安排2–3名初见玩家试玩教学和前两关，按docs/onboarding-and-early-pacing.md记录卡点与剩余时间，再单项调整。幼苗视口首跑过量、独立复跑通过仍留作V6波动；P1／V1／V6开放。默认Vulkan另待实施，个人声明／日志发布及交付待项保留，本轮Git存档，未新打包／推送／上传。
updated: 2026-10-19

## 待办

## 进行中

- [ ] P1：性能与稳定性收尾（V1／V6）。完成空闲环境下 1920×1080 正式压力采样，定位掉帧与模拟积累，复验修复涉及的流程并记录历史异常排查结果。
  完成标准：既有 meadow／valleys／storm_coast 共 18 项，每项预热 5 秒、采样 60 秒，P95 ≤16.7 ms、P99 ≤20 ms，模拟推进至少达到采样时长的 99%，结束积累 ≤100 ms；相关规则／渲染／流程检查通过。未达标、验证失败或异常未解决时保持未完成，不把短测或单次复跑当作正式验收。

## 已完成

## 交接摘要

### 已确认

- 2026-10-19版本存档：用户追加教学湿空气spread=Vector2(5,5)，并授权Git提交；保留同批地图、主题与编辑器保存改动，以及此前尚未提交的性能修整、图标、Demo交付素材／日志／声明草稿和导出预设。针对当前资源执行tests/test_authored_levels.gd --headless --audit-only，28项0失败、九张正式图及教学引用校验通过；未重跑实机或完整回归，前轮9.3833秒教学路线早于本次水汽修改，不能当作当前布局复验。原幼苗波动、新人反馈及P1／V1／V6继续开放；无新包或远端推送。

- 2026-10-19按用户授权实施教学与前期节奏：水库教学改为五个结果驱动节点，8／20活跃模拟秒无进展帮助与局部拖动示意，保留真实蓄满即完成及提前完成回顾；天气提示仍默认关。原生暂停说明覆盖教学、前四关和首次风带／漩涡，菜单可重看；阅读不推进天气、时限、风源寿命或安全计时，导航／失焦取消手势，R可直接重试、Esc进暂停菜单。文案及延迟在configs/onboarding.tres，前四关仅增加360／420／420／360秒字段，布局／UID／需求／天气规则不改。最终两尺寸各80项教学检查通过，最终菜单59／转场38及真实鼠标教学9.3833秒→首关35.75秒满风纹真实倒数→level02通过（1459事件、0阻挡／失败）。85条目分段覆盖：74项后幼苗视口55.4331过量失败，续跑10项及五路线比较通过；该失败保留，独立复跑幼苗40.4258通过，不能称单次全套通过或关闭波动。最后R／Esc小分支另由两尺寸80项覆盖，不冒称全套重跑。入口docs/onboarding-and-early-pacing.md及review.json。初见玩家理解与时限反馈尚未验收；P1／V1／V6开放，默认后端仍D3D12，无新包／提交／推送／上传。

- 2026-10-18受影响机器Vulkan反馈：用户确认运行Start-Vulkan.cmd后不再画面冻结。已读完整vulkan-27915-8335.log（75195字节／641行），实际Intel Iris Xe、Vulkan 1.4.323、Forward+；ERROR／SCRIPT ERROR／DEVICE_LOST均0，一条加载器注册表清单查找警告，日志含level01／level02加载。确认本次试玩的绕过办法有效，不等于已定位D3D12底层根因或全部硬件／长时稳定性通过。建议下一版默认Vulkan，当前project.godot和已交付EXE仍为D3D12，本轮仅记录、不改代码／配置／导出；教学计划待实施，P1／V1／V6保留。

- 2026-10-18新增试玩反馈与教学计划：用户认为教程说明不足、前期时限短，明确先写计划。已核对当前三阶段水库教学、默认关闭天气提示却引用箭头／雨区、教学100与首关250／次关两池250、九关均继承180秒。拟补五个学习节点、局部手势／无进展帮助、暂停阅读的关前／新工具说明；仅前四关拟360／420／420／360秒，其余保留，全部是待确认试玩初值。完整方案docs/onboarding-and-early-pacing-plan.md；本轮仅文档，不改地图／代码／配置或导出，不视为实现／体验验收。核显反馈已在上方补记，本教学方案不关闭P1／V1／V6。

- 2026-10-18外部试玩冻结反馈：i5-13500H／16GB／Intel Iris Xe的轻薄本高频画面停住、声音及点击反馈继续，启动或第二关均可能出现；Windows／驱动版本及最小化恢复情况未知，未定位根因。当前D3D12，已提供docs/demo-delivery/render-freeze-2026-10-18/中的三份后端／分辨率诊断CMD及3633字节ZIP，不改游戏代码／默认后端或重新导出。本机同一Release在Intel D3D12／Vulkan主界面、Intel／NVIDIA Vulkan第二关短时显示退出0，低分辨率CMD实际调用通过；Vulkan日志有本机OBS／mediasdkhook残留错误，不能称干净。待对方先试Start-Vulkan.cmd并提供日志；不等同此前V6原生异常，不关闭P1。历史游戏ZIP缓存路径本轮未找到，独立目录EXE与原BUILD_INFO散列一致，未擅自重建。

- 2026-10-18日志口吻修订：用户希望改为介绍类型。五篇正文改为介绍式回顾；用户后续明确标题继续使用“开发者日志①～⑤”，副标题恢复原题，先讲当前玩法／体验，再解释实际设计取舍，保留“目前进展／还在打磨的地方／接下来准备做什么”、实机配图及话题；不叙述成当天刚开发完成。文本检查五篇836–945中文字、三节／话题／图片路径通过；发布时间登记未改、未代发，不保证活动计数。只改文档，已交付Demo ZIP及游戏代码不变。入口docs/demo-delivery/devlogs/README.md。

- 2026-10-18用户授权按官方教程封包：新增export_presets.cfg的TapTap Windows Demo独立预设及assets/ui/app_icon.ico，保留原预设和资源标识。生成.godot/WeavingRain-TapTap-Demo-20261018.zip，46294723字节，SHA256 d0f71976bbdc0a2d2ff491ddcd87252d3adc716b9f36059ebabdcd8e783de7a1；启动WeavingRain.exe、参数空、Demo0.1.0，附说明／鸣谢／同版本引擎许可及BUILD_INFO。采用当前未提交工作区，基线7a28040，不是只按该提交构建；未改玩法、未提交／推送／上传。详见docs/demo-delivery/package-2026-10-18.md及package-review.json。

- 2026-10-18平台图标补充：按用户新增格式要求，将既有风托云SVG背景改为直角满底，另存sources/icon-square.svg及upload/icon-square-1024.png（位于docs/demo-delivery/taptap-2026-10-18/）。1024×1024 RGB PNG、82028字节；未替换项目根图标或UID，未加入原五图ZIP。

- 2026-10-18素材声明口径更新：用户转达官方确认AI辅助shader、网格和UI生成画面不计AI美术，宣传插画不并入游戏内统计。已更新docs/demo-delivery/素材使用声明-风织雨-待确认稿.md：游戏内0%，宣传插画原图3/3为100%单列；代码、文案与音效AI工艺继续披露。

- 2026-10-18用户最新确认：官方已回复可以，认可四天五篇、其中一天两篇安排；发布节奏不再阻塞，但不代表日志已发布或所有参赛条件已达成。素材声明按用户下载的官方全文另存填写稿，原模板不改；第三方音频、系统字体／Godot及AI参与工艺均披露，未签署、分享或提交。

- 2026-10-18日志：按真实开发记录准备五篇独立主题正文，分别讲核心循环、程序化天气、风工具演变、田池与热带系统、可读性与声音；约844–946中文字／篇，均配既有正常实机图。入口docs/demo-delivery/devlogs/README.md包含来源和实际发布登记；尚未代为发布。

- 2026-10-18：按用户提供的TapTap要求新增五份上传PNG及仅含五图的素材ZIP，入口 docs/demo-delivery/taptap-2026-10-18/README.md。宣传图1920×1080、透明标题LOGO1375×594、横封面1840×860、竖封面1200×1800、无字壁纸3840×1240。内置image_gen依当前实机造型重新构图，Godot原生排字只保留游戏中英文名；不是直接截图，未改游戏内美术。提示词／原图／检查见该目录prompts.json、sources/和review.json。

- 制作署名为 ZLOONG · 智龙。风托云图标与晴海送雨封面已获用户认可；根目录 icon.svg 已替换，原UID及项目引用保留。入口与图标检查记录：docs/demo-delivery/README.md、visual-review.json。
- 已制作三张1920×1080玩法宣传图（借山成云／留风聚云／海上借雨）和25.021秒H.264／AAC实机短片，位于 docs/demo-delivery/visuals/；审阅入口 docs/demo-delivery/media.html，来源／时间表／散列及限制见 media-review.json。正常level03／07／08真实视口输入合计1068事件，无失败／阻挡，漩涡与风带实际创建；未注水或改天气／相机，主题关保留正常初始云。原始序列、录音和剪辑中间文件留 .godot/demo-media/。
- 本轮素材制作没有改游戏代码、音频配置或导出设置；已有性能优化及其他未提交改动保留。此前记录的main基线为7a28040，本次收工未重新查询Git，也未导出、提交、推送或上传。

### 验证

- 本次暂存149个文件，确认不含.godot缓存；暂存空白检查仅官方声明原模板的原始末尾空行报提示，按保留原模板要求不改，其余暂存文件检查通过。

- 本次提交前Godot4.7.2以--headless --script res://tests/test_authored_levels.gd -- --audit-only --fresh-guide执行，退出0，AUTHORED LEVELS为28项0失败；日志.godot/onboarding-20261019/commit-map-audit.log。仅资源审计，未重跑实机／完整回归。

- 本轮实际执行tests/run_checks.ps1：首轮旧工具说明夹具失败后按新生命周期修正；第二轮前74条目通过，needs-viewport-route幼苗55.4331过量退出1。随后以-StartAt vortex-viewport-route续跑10条目及五份路线比较通过。最终相关检查为菜单59／转场38、真实鼠标教学→首关→level02，以及幼苗独立复跑40.4258通过；最后R／Esc修整另跑两尺寸test_onboarding_pacing.gd各80项0失败。不是单次完整全绿。四张地图文本精确比较确认只有时限字段变化，git diff --check通过。详细命令／日志散列见docs/onboarding-and-early-pacing-review.json；未做新玩家、长性能或新包验证。

- 本次只用Python完整读取受影响机器日志并核对后端、显卡、错误／警告、关卡资源加载与SHA256；没有新运行游戏、完整路线或性能测试。详细提取见docs/demo-delivery/render-freeze-2026-10-18/review.json。

- 本次计划依据：实际读取onboarding.gd／game_hud.gd／main.gd／map_definition.gd及教学、九关、campaign与容量资源；Python逐图确认level01–09无时限覆盖、均继承180秒，并核对教学100与正式池250。计划文件要点检查通过；没有运行游戏、调整资源或执行新回归。

- 本次实际用已交付Release的--rendering-driver与--gpu-index：Intel D3D12／Vulkan主界面和Intel／NVIDIA Vulkan level02共四次退出0并截图；本地Vulkan verbose日志包含OBS JSON／mediasdkhook DLL缺失，首份自动清洁日志门槛因此失败，未掩盖。另实际cmd /c运行低分辨率启动脚本，退出0、日志创建和截图通过。Python小ZIP四文件CRC／逐文件对照通过，独立EXE与原BUILD_INFO散列一致；历史游戏ZIP路径缺失，未称本轮验证其散列。

- 标题后续：仅恢复五篇“开发者日志”标题及原副标题；Python逐文件比较确认正文（首行之后）字节完全不变，发布登记及图片路径保留。无游戏检查／重新打包／发布。

- 本次Python只读检查：五篇均为开发回顾标题、836–945中文字；三节、精确话题各一次与全部本地图片引用存在检查通过，原五条未发布登记未改。未运行游戏／性能检查或平台发帖，没有修改已交付包。

- 本次封包：固定Godot --headless --path PROJECT --export-release "TapTap Windows Demo" OUTPUT.exe由Start-Process -Wait最终退出0、export-final.log无错误／警告。项目外实际Release主界面＋教学／九关共11份启动与最终ZIP解压正常启动通过，核对地图ID／目标数／08和09风暴；--fresh-guide隔离玩家资料。另以同版本编辑器--main-pack挂载最终包，资源检查及既有菜单59项／0失败通过，最终日志无ERROR；不冒称Release外部脚本完整路线。Python ZIP CRC／文件散列及PE六档图标像素一致通过；本轮未逐关通关或长性能复测。

- 图标：固定Godot以Start-Process -Wait运行render-icon.gd，退出0且.godot/taptap-icon-20261018-retry.log确认导出；Python/Pillow完整解码、尺寸／RGB无透明通道、青绿四角及SVG无rx检查通过，已目视。首次直接调用未生成文件，未计成功；平台上传／审核未验证，无游戏规则或性能复测。

- 本次Python只读检查确认声明内0%／100%口径已更新、旧视觉待确认占位移除、文本／程序等未确认字段保留；原官方模板SHA256不变。只改文档，未运行游戏测试。

- 素材声明核对：已读取本地完整模板，重新在线核对四份CC0声源页、Godot许可、微软字体FAQ和CC0说明。Python只读检查确认原模板SHA256不变、填写稿四节齐全、16 WAV＋1 Ogg、音效占比37.5＋6.25＋6.25＋50＝100%，缓存外未发现字体文件。在线飞书未读成功（检索不可达、CLI无身份、浏览器两次超时），最终依据是用户本地文件；无新增游戏测试。

- 已在线读取官方指南https://www.taptap.cn/moment/580820744309575140、论坛https://www.taptap.cn/app/710826/topic与主题公告https://www.taptap.cn/moment/854692229854265392。五稿本地补齐进展／风险／计划摘要及精确话题#聚光灯gamejam开发者日志，逐文件检查该话题各出现一次；未发帖。

- 日志核对：实际阅读策划、当前云shader／模拟字段、天气配置、关序、漩涡和雨声记录；本地Python只读检查确认5份正文、每篇至少600中文字且图片路径均存在。内容是历史主题回顾，不伪造当日开发或旧发布日期；本轮未跑游戏、玩法或性能测试。

- 2026-10-18：Godot图形运行 --script res://docs/demo-delivery/taptap-2026-10-18/render-assets.gd 最终退出0，日志.godot/taptap-assets-20261018-final.log无脚本错误；python docs/demo-delivery/taptap-2026-10-18/verify-assets.py 五图解码、规定尺寸／严格字节上限、LOGO透明边距及ZIP CRC通过，已逐张目视。新素材观感／平台审核未验证；没有重跑玩法或性能。

- 已用固定Godot 4.7.2运行 docs/demo-delivery/capture-gameplay.gd，参数含 --resolution 1920x1080、--fresh-guide --skip-menu --audio-review，以及对应 --shot 和完整 --map=res://configs/maps/levelXX.tres；最终三组退出码均0，实际地图标识、模拟推进与输入记录通过。
- 已执行 python docs/demo-delivery/make-gameplay-media.py --photos，Godot --script res://docs/demo-delivery/render-gameplay-cards.gd（退出0），再执行 python docs/demo-delivery/make-gameplay-media.py（退出0）。三图尺寸及中央330–959行与底图精确对照通过；FFprobe确认1080p／25.021秒，FFmpeg完整解码通过，音频峰值约0.224、无削波。已查看宣传图及抽取的视频首尾／中间帧。
- Godot --headless --editor --import --quit 退出0，日志 .godot/demo-media-import.log 无错误；Python编辑脚本语法及JSON读取通过，git diff --check 无空白错误（有既有CRLF转LF提示）。内置浏览器读到视频readyState=4、1920×1080、完整时长且error=null；审阅页曾在本机17924端口展示。
- 图标原生导入像素及1280正常主界面启动此前已通过，详见visual-review.json；最终独立EXE图标未验证。新三图观感、视频最终混音及九关完整体验未验证；素材阶段未重跑完整玩法或性能。此次收工只重读／回写TASKS.md，未补跑验证。

### 未完成或阻塞

- 教学与前四关时限尚未获得初见玩家验收；需2–3人实玩，不能把上述脚本9.38／35.75模拟秒或UI夹具当新手用时。幼苗视口首次过量失败保留，独立成功不证明波动修复，不调整阈值或关闭V6。本轮只改源码与资源，旧已交付EXE仍是原教学和D3D12；默认Vulkan需另行实施与复验。

- 外部Iris Xe本次Vulkan绕过已获玩家确认及日志支持；D3D12底层根因、Windows／驱动版本、长时稳定性仍未知。未改默认后端、未作完整游戏回归、长性能或新导出，V1／V6不因此关闭。

- 本次封包仍未做TapTap上传／解析／后台自测／审核，未跑九关完整路线、两次真实Release会话间存档回读、跨硬件或长性能测试。首轮导出临时目录写入和SVG EXE图标失败后已重导出；Release外部脚本尝试停滞、已停止精确匹配的自有进程，改用正常Release启动＋编辑器挂载检查。首次挂载检查输出路径错误及沙箱着色器缓存失败均修正／重验；详细失败日志保留，不据此改动天气规则。

- 声明的视觉统计已按用户转达官方回复确认：游戏内AI美术0%，宣传插画100%单列，不合并；这不代表开发未用AI。仍缺本人厂商名／TapTap ID／真实姓名／实际签署日及文本、程序比例，不编造这些字段。未签署／分享／提交；本次新包与许可附带情况已另行核对，见封包记录。

- 2026-10-18最新解释：用户已转达官方认可具体的四天五篇安排，替代此前“仍需确认”的状态。实际日志尚无发布链接；不能将节奏获认可写成全部获奖条件达成。

- 五篇本地草稿不等于TapTap开发期内已发布5篇；真实发布时间、链接和平台内容审核待填，也没有有效试玩人数证据。用户提供的全程参与奖还要求有效投稿／审核、核心循环与至少50人有效试玩，不能将自动回放或资料完成替代这些条件。

- 2026-10-18新增素材待用户认可和平台审核，未上传。首遍浮点尺寸相等断言报错但进程退出0，已取整修复、全五图重导出，务必读最终日志。生成原图为1672×941／1024×1536／2206×713，原生画布采样至上传尺寸，不称原生4K生成。旧含署名／标语的实机封面不用于本轮指定宣传图／封面字段。

- P1完成标准未达，保持未勾选：此前同源码正式18项有13项通过，5项拖动P95失败，第九关附加两项也未达帧门槛；全部20项推进／末积累通过。V6历史原生异常根因仍未确认，不能因本轮未出现而关闭。详见 docs/performance-stability-review.md／json。用户目前优先Demo可玩，不自动继续长测。
- 新图／短片待用户反馈；公开反馈入口、完整教学＋九关体验及跨会话存档仍待处理。本次Demo0.1.0新包已生成、TapTap预设modify_resources=true且EXE图标已验证；原预设仍保留false。旧独立包不能当作当前版本。
- 录制时逐帧读回／JPEG写盘拖慢模拟，视频按实际墙钟剪辑，未加速或插帧，不能作为性能或通关证据。照片保留HUD并排字，视频保留正常操作的悬浮信息；素材不代表已完成这三关。
- 首轮照片提示遮挡后已重拍；一次重拍误传短地图名而回退standard，样本已丢弃，最终脚本加入地图标识／推进校验。重做必须用完整res://地图路径，拼接以capture.json帧列表为准，不通配缓存中残留旧帧。headless不能等待frame_post_draw做取图；录制／排字须用原生图形运行。
- 本地预览服务器是否在切换Agent后仍运行未验证；原始素材是忽略缓存，不加入Git，不扩充docs/previews/。保留现有未提交代码、文档与资源.import／.uid。

### 接着做

教学下一步先打开docs/onboarding-and-early-pacing.md与review.json，安排2–3名初见玩家试玩；记录发现水汽、迎坡造雨、搬云理解、首次接雨／完成耗时和前两关余时。当前代码已实现、前四关时限已生效；按卡点只改一项再观察，不顺便改布局、容量或全局风力。默认Vulkan另线继续。

已回收受影响机器Vulkan日志，且玩家确认不再冻结；接着可将下一版Windows默认后端改为Vulkan，再做相关渲染与流程检查。现有包继续用Start-Vulkan.cmd；不改注册表或系统录屏层。

日志当前先审阅docs/demo-delivery/devlogs/01-core-loop.md的介绍式口吻；本人上传实机图并关联话题发布后，再凭真实链接／日期登记。五篇文件名和图片路径保持原样，旧标题建议以README新清单替代。

包体下一步：打开docs/demo-delivery/package-2026-10-18.md，使用其中当前ZIP和WeavingRain.exe路径上传；等待平台解析通过并做后台自测，按实际页面返回处理问题。不要把本地启动验证写成平台审核通过。

图标直接上传docs/demo-delivery/taptap-2026-10-18/upload/icon-square-1024.png；不要上传SVG、旧透明圆角PNG或透明文字LOGO到应用图标栏。

声明先打开docs/demo-delivery/素材使用声明-风织雨-待确认稿.md，补个人信息、文本／程序比例及本人实际签署；视觉统计已确认，无需重复询问。确认后由本人另建飞书文档、设置可阅读链接并提交。

日志优先动作：打开docs/demo-delivery/devlogs/README.md，用户审阅五篇后按实际情况发布，上传对应实机图并填写真实发布日期／链接。本地Markdown图片路径不会自动成为平台附件；不要倒填发布日期或自动代发。其余素材审阅／封包待项继续保留。

当前先请用户审阅 docs/demo-delivery/taptap-2026-10-18/upload/ 五张PNG（或本目录素材ZIP），核对观感与实际TapTap上传字段；未获新指示不自动上传。之后再衔接原实机素材／文案审阅与统一封包待项。

先打开 docs/demo-delivery/media.html（或查看visuals中的三张-gameplay.png与weaving-rain-demo.mp4），读取 media-review.json，与用户确认新素材和交付文案的观感；先不自动改图、重测或封包。认可后再根据实际授权做必要体验小修、统一导出及独立运行核对。
