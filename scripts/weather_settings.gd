@tool
class_name WRWeatherSettings
extends Resource
## 原型测试参数，尚非最终平衡。实际配置保存在 res://configs/weather.tres。
## 保存配置后，开发模式按 F6 读取：拨风、云响应立即应用并保留天气；其余参数在 R 重试时生效。
## 数值须为有限非负数；具体限制见各字段与 validation_errors()。建议一次只改一组，比较同一地图的手感。

@export_group("拨风")
## 风刷半径，世界单位，范围 0.1–8；中心推力最强，向边缘平滑减弱。
## 调大可同时推动更宽范围的湿空气、冷空气与云；调小便于局部修形，减少牵动旁边天气。
@export_range(0.1, 8.0, 0.05) var brush_radius: float = 1.5
## 风速上限，世界单位/秒，范围0.1–12；限制人工风，以及叠加背景／自然天气／冷风后的各层实际速度。
## 调大允许更快输送、也更易拉散或推过头；调小限制猛拨速度。未达到上限时，调大不会自动增强风。
@export_range(0.1, 12.0, 0.1) var max_wind: float = 6.0
## 鼠标风的指数衰减率，1/秒；划动期间也会衰减，松手后不会立即归零。
## 调大更快停下、细调更容易；调小惯性更久、输送更远，也需更早收手。0 关闭这项衰减。
@export var wind_decay: float = 1.1
## 相邻格子的风向、风速混合率，1/秒，范围 0–60。
## 调大让周围更快跟随，同时摊平局部强风；调小更保留单笔的局部方向。0 关闭邻域传播。
@export var wind_spread: float = 0.65
## 慢划时的最低力度倍率，须不大于 stroke_max_power。
## 调大让慢划也有明显推力；调小便于轻拨微调。点击不拖动仍不会造风。
@export var stroke_min_power := 0.35
## 快划达到的最高力度倍率，须不小于 stroke_min_power；最终速度仍受 max_wind 限制。
## 调大增加轻拨与猛拨的差异；调小使快划更温和。两者相等时，划动速度不再改变力度倍率。
@export var stroke_max_power := 2.5
## 达到最高力度所需的划动速度，世界单位/秒，须大于 0；在固定水平参考面上测量。
## 调小更容易猛拨；调大需更快划动才达到最高力度。超过此速度不再增加倍率。
@export var stroke_speed_full := 16.0
## 每笔推力的整体倍率，作用于慢划和快划；推力还随划过的距离及风刷位置变化。
## 调大使同样路径更有力、更快接近风速上限；调小整体更柔和。0 使拨动不再增加风。
@export var stroke_gain := 3.0
@export_group("续吹与持续风带")
## 按住续吹及风带的加速度增益，世界单位/秒²，范围 0–10，F6 即时应用。
## 续吹乘最近拖动轻重倍率；风带乘 source_powers 对应档，不受拖动速度影响。
## 调大更快建立输送风，也更容易推过头；调小更柔和。0 停止新增推力，已有风仍自然衰减。
@export_range(0.0, 10.0, 0.1) var hold_gain := 2.0
## 风带总寿命，模拟秒，范围 1–30，默认 30；暂停冻结，重试生效。
## 调大可腾出更多时间处理其他天气，也更容易持续补给过量；调小需更频繁重新布风。
@export_range(1.0, 30.0, 0.5) var source_lifetime := 30.0
## 风带弱／中／强三档的力度倍率，依次为 x/y/z，范围 0–10，按升序配置，F6 即时应用。
## 乘 hold_gain 后按固定步加速度施力；不随拖动速度或风带长度改变。调大对应档更快送风，也更易推过头。
## 调小该档更柔和；0 不新增该档风力。中档独立可调，不影响普通拨风快慢映射。
@export var source_powers := Vector3(0.35, 1.425, 2.5)
## 寿命最后多少秒线性减弱，范围 0.1–总寿命，重试生效。
## 调大更早变弱、停止更平缓；调小更久保持全力。到期仅撤除风源，不清空已有风。
@export_range(0.1, 30.0, 0.1) var source_fade_seconds := 2.0
## 同时存在的临时风源上限，范围 1–4，重试生效；满额后拒绝新建，不替换旧源。
## 调大允许多路补给，也更难照顾过量风险；调小要求更明确地选择输送位置。
@export_range(1, 4, 1) var source_limit := 2
@export_group("云响应")
## 所有云的最低移动响应，范围0–1；例如0.24表示云速至少为同处云层实际风速的24%。
## 调大让厚云、雨云更容易移开，也削弱轻重云的差别；调小允许它们更迟缓。此项不控制雨量。
@export_range(0.0, 1.0, 0.01) var rain_response: float = 0.24
## 云水浓度带来的阻力系数；浓云响应按 1 / (1 + 平滑云水量 × 此值) 减弱。
## 调大使厚云更沉、薄云受影响较小；调小让厚薄云移动更接近。0 仅取消浓度阻力，降雨阻力仍保留。
@export var cloud_drag := 0.22
## 完全激活降雨时的额外移动倍率，范围 0–1；部分激活时按比例过渡。
## 调小使雨云更难推动；调大使其更容易移开，1 取消降雨带来的额外阻力。最终仍受 rain_response 保底。
@export_range(0.0, 1.0, 0.01) var rainy_cloud_response := 0.42
@export_group("初始湿空气")
## 开局湿空气的基础浓度，再乘地图各湿空气源的浓度倍率与空间分布。
## 调大增加开局可用水量、更易造出厚云，也增加过量风险；调小使补给更紧张。只影响开局，不持续补水。
@export var initial_humidity: float = 3.2
@export_group("成云与降雨")
## 湿空气随有效迎坡气流转为云水的效率；实际转化还取决于风向、风速、坡度及当地湿度。
## 调大在同一路线更快造云；调小需要更多补风或更长抬升过程。0 关闭山坡造云，平地拨动仍不能直接造云。
@export var lift_rate: float = 2.2
## 开始累计成雨进度的平滑云水阈值，须大于 0；也参与云体厚度显示和安全范围的厚云判定。
## 调大需更集中才能启动降雨，同等水量显示得较薄；调小薄云也较易成雨。已启动的雨仍按储水释放。
@export var cloud_threshold: float = 1.4
## 局部厚云累计至成雨所需的维持时间，秒，须大于 0；进度随云一起搬运。
## 调大留出更多修形时间，也更难维持到成雨；调小更快启动。此项不直接决定启动后的降雨持续时间。
@export var hold_seconds: float = 2.0
## 云水低于成雨阈值时，已有维持进度的回退倍率。
## 调大使散薄更快失去进度；调小允许短暂失稳后继续积累。0 关闭主动回退，进度仍受剩余云水量限制。
@export var progress_retreat: float = 0.5
## 降雨储水按比例释放的速率，1/秒；每格实际释放还加 rain_base_rate，且不超过剩余储水。
## 调大雨更急、储水耗尽更快，冷空气也更快形成；调小雨较缓、尾雨更长。不会凭空增加总水量。
@export var rain_rate: float = 0.16
## 每个已激活雨格额外释放的基础量，模拟水量/秒；与 rain_rate 的比例释放叠加。
## 调大尤其加快少量储水的尾雨结束；调小让尾雨更久。雨区越宽，基础释放总量越大，仍受各格储水限制。
@export var rain_base_rate := 0.008
## 维持整格降雨状态及结束尾雨所用的雨水阈值；低于此值的微量残雨回收到当地低空湿空气。
## 调大更早结束尾雨、回收更多残水；调小雨可释放得更彻底、收尾也可能更久。回收部分不计入地块雨量。
@export var rain_end_density: float = 0.025
## 实际落入受雨地块的水分，换算为界面地块水量的倍率，须大于 0。
## 调大同一场雨更快达到适量及过量；调小需要更多实际降雨。只改变地块计量，不增加云水或实际雨势。
@export var plot_water_scale: float = 6.0
@export_group("冷空气")
## 是否启用降雨产冷空气、自动低空出流及冷风前沿抬升；还需当前模式支持冷风。
## 关闭后可比较只借山坡的路线；鼠标仍同时影响低空和云层。此开关在重试时生效。
@export var cold_enabled: bool = true
## 每单位实际落雨产生的冷空气强度倍率，直至达到 cold_cap；雨落在目标外也会产生冷空气。
## 调大更快形成强冷区、便于后续接力；调小需更多降雨积累。冷空气强度不计入水分收支。
@export var cold_from_rain: float = 5.0
## 单格可积累的冷空气强度上限。
## 调大允许储备更多冷空气，并可能增强出流梯度；调小更快饱和、可用接力储备更少。抬升效率不会无限随强度增加。
@export var cold_cap: float = 3.0
## 冷空气的指数自然衰减率，1/秒；降雨期间与停雨之后均生效。
## 调大残留更快减弱，需要及时利用或补充；调小接力窗口更长。0 仅取消自然衰减，抬升消耗与边界流失仍存在。
@export var cold_decay: float = 0.045
## 冷空气强度梯度转为向外低空风速的倍率；只推动低空湿空气、冷空气，不自动搬动高处云。
## 调大更强地向四周推开低空空气；调小出流更缓。过强可能把补给推走，速度受 cold_max_speed 和 max_wind 限制。
@export var cold_outflow: float = 1.6
## 自动冷风出流的速度上限，世界单位/秒；与鼠标风合成后还受 max_wind 限制。
## 调大允许强梯度产生更快出流；调小限制向外推力。只限制自动出流，不单独限制鼠标拨风。
@export var cold_max_speed: float = 1.1
## 湿空气迎面挤入有效冷风前沿时，转为云水的效率；还取决于汇聚速度、梯度、冷空气强度及储备。
## 调大有效交界更快造云，也更快消耗冷空气；调小接力较慢。接触边缘或顺着出流移动仍不足以抬升。
@export var cold_lift_rate: float = 3.5
## 每单位由冷风抬升的水分，消耗的冷空气强度；储备不足时也限制当步转化量。
## 调大一次接力更快用弱冷区、需要后续降雨补充；调小同一冷区能抬升更多水汽。0 取消这项消耗。
@export var cold_lift_cost: float = 0.45
## 冷风抬升所需的最低冷空气强度；当前效率从此值至强度 0.8 平滑增加，建议保持低于 0.8。
## 调大使弱冷区更早失去造云能力；调小让较弱残留也能参与。仍需有效梯度与迎面气流，非达到强度就自动造云。
@export var cold_minimum: float = 0.10
@export_group("漩涡")
## 弱／中／强的向内基础加速度，世界单位/秒²；预览时滚轮选档，生成后固定。
## 调大对应档更快聚集，也更易集中降雨；调小收拢更缓。0–10 严格升序，F6 应用。
@export var vortex_inward_acceleration := Vector3(0.7, 1.4, 2.8)
## 切向旋转加速度，世界单位/秒²，0–10，F6 应用；独立于收拢档位。
## 调大绕转更明显，调小更接近向内汇聚；0 仅取消切向施力，手势方向仍保存。
@export var vortex_rotation_acceleration := 1.4
## 拖动可设置的最小／最大世界半径，0.5–8；起点为中心，起终点距离决定范围。
## 调大最大值可聚集更远天气；F6 后下一笔应用，当前预览与已有范围不变，超限不会自动缩小。
@export var vortex_radius_limits := Vector2(0.75, 5.0)
## 核心区占半径比例，0.1–0.5；实际至少一个网格间距。核心内加速度向中心平滑降零。
## 调大聚成更宽的一团，调小更集中、雨量峰值可能更大；F6 应用并重建风源权重。
@export var vortex_core_fraction := 0.20
## 外缘柔化区比例，0.05–0.5；越大越早减弱边缘推力，越小有效收拢覆盖更靠近轮廓。F6 应用。
@export var vortex_edge_fraction := 0.20
@export_group("目标")
## 地块适量水量下限，须小于 flood_water；达到后仍需清除附近危险天气并维持安全。
## 调大需要更多降雨，且在过量上限不变时缩小容错区间；调小更早够水，也需要更早开始移开雨云。
@export var target_water: float = 100.0
## 地块过量水量上限，须大于 target_water；当前测试局在水量超过此值时判过量。
## 调大增加够水后的补救余地；调小更容易浇过头。两者之差决定适量区间宽度。
## 星级关卡标记该地块永久损坏后继续；旧练习局结束并允许重试。
@export var flood_water: float = 150.0
## 已够水且安全范围内无危险天气时，确认完成所需连续时间，秒，须大于 0。
## 调大要求更稳定的收尾；调小更快确认。危险天气重新出现会清零计时，此项不是整局倒计时。
@export var safe_seconds: float = 2.0
## 任意田数的计星测试局全部保住后，自动结算前的展示时间，单位秒；重试生效。
## 调大给玩家更多观察和立即结算的时间，调小更快结束；期间天气继续运行，失星取消并从头倒数。
@export_range(0.1, 30.0, 0.1) var three_star_finish_seconds: float = 3.0
## 正方形受雨地块的半边长，世界单位，须大于 0；边长为此值的两倍，重试后重建覆盖判定。
## 调大扩大接雨面积，同样天气更容易累计水量也更易过量；调小要求更准的落雨位置。地块须完整在平地且互不重叠。
@export var plot_half := 1.25
## 正方形安全缓冲区的半边长，世界单位，须不小于 plot_half；重试后应用。
## 调大需把更远的雨、厚云及可见成雨进度一起处理掉；调小可更早安全完成。界面范围与实际检查共用此值。
@export var safe_half := 2.1
@export_group("边界（开发）")
## 是否允许水汽、云水与冷空气流出模拟范围；正式配置必须开启，关闭仅用于直接构造旧封闭回归。
## 开启后越界部分不会挤回边缘，水分流失单独记账且不自动补回；关闭恢复旧边缘夹紧行为。
@export var open_boundary := true
## 海域缓冲最外侧 2 世界单位内的消散率，1/秒；越靠外消散越强，云水、降雨子集与进度同比例减少。
## 调大使天气更早淡出、流失更多水分；调小允许它飘得更远。0 关闭缓冲消散，但越界仍流失，显示仍有边缘淡出。
@export var edge_decay := 1.8
@export_group("热带主题：补给与对流（R生效）")
## 每个有效海格的水汽补给上限，原始水量/秒，0–2。实际乘当地0–1供能；越大越易持续成云，0停补给。
@export_range(0.0, 2.0, 0.01) var tropical_evaporation := 0.09
## 强天气引起的供能减弱率，供能/秒，0–1；实际乘强度平方及局部影响。越大越早弱化；0不冷却。
@export_range(0.0, 1.0, 0.001) var tropical_cooling := 0.025
## 蒸发／对流支持的最低供能，0–0.9；调大更早停止补给，调小能利用更弱的剩余供能。
@export_range(0.0, 0.9, 0.01) var tropical_energy_min := 0.08
## 初始对流所需的当地水汽，原始浓度，0.01–10；越大越需先收拢。达标仍需有效汇聚。
@export_range(0.01, 10.0, 0.05) var tropical_humidity_min := 0.35
## 实际低空速度散度的负值阈值，1/秒，0.001–10；越大越需集中汇入，同向平移不足以造云。
@export_range(0.001, 10.0, 0.01) var tropical_convergence_min := 0.025
## 有效条件连续维持时间，秒，0.1–10；调大避免短暂汇聚启动，失去条件会回退。
@export_range(0.1, 10.0, 0.1) var tropical_convection_seconds := 0.8
## 海域有效汇聚转水汽为云的效率，0–20；调大更快补云，仍从真实水汽扣账。
@export_range(0.0, 20.0, 0.1) var tropical_lift_rate := 3.5
@export_group("热带主题：组织与环流（R生效）")
## 影响半径，世界单位，1–6；越大覆盖越宽、涉及更多天气，但不凭空增加水。
@export_range(1.0, 6.0, 0.1) var tropical_radius := 4.2
## 满强度切向速度，单位/秒，0–12；调大旋转与云带输送更强，组合仍受max_wind限速。
@export_range(0.0, 12.0, 0.1) var tropical_rotation := 3.4
## 满强度低空向内速度，单位/秒，0–12；调大汇聚与供给更强，可能更快集中雨量。
@export_range(0.0, 12.0, 0.1) var tropical_inflow := 1.8
## 云层向外展开速度，单位/秒，0–4；越大雨带更宽，过大可能散薄。人工风仍作用两层。
@export_range(0.0, 4.0, 0.05) var tropical_cloud_outflow := 0.25
## 支持满组织度所需的实际对流转移速率，水量/秒，0.01–100；调大更难增强。
@export_range(0.01, 100.0, 0.1) var tropical_support_rate := 1.8
## 支持组织的平均切向速度，单位/秒，0.01–12；调大更需明确环流，单纯云多不会增强。
@export_range(0.01, 12.0, 0.05) var tropical_rotation_min := 0.2
## 组织度向支持值增长／衰弱的指数响应，1/秒，0–2。分别调大更快增强／更快减弱，不删除储水。
@export_range(0.0, 2.0, 0.01) var tropical_growth := 0.08
@export_range(0.0, 2.0, 0.01) var tropical_decay := 0.035
@export_group("热带主题：外围引导（R生效）")
## 外围环境平均风转为中心移动的倍率，0–2；调大更易引导，不读取自身环流。
@export_range(0.0, 2.0, 0.05) var tropical_steering_gain := 0.65
## 中心移动速度上限，单位/秒，0–2；调小更稳定，调大需更早安排雨带经过目标。
@export_range(0.0, 2.0, 0.05) var tropical_motion_cap := 0.35
## 中心对引导风的指数响应，1/秒，0–4；调大更快转向，调小惯性更久。0保持当前移动速度。
@export_range(0.0, 4.0, 0.05) var tropical_steering_response := 0.35

const LIVE_FIELDS := ["hold_gain", "source_powers", "brush_radius", "max_wind", "wind_decay", "wind_spread", "rain_response",
	"stroke_min_power", "stroke_max_power", "stroke_speed_full", "stroke_gain", "cloud_drag", "rainy_cloud_response",
	"vortex_inward_acceleration", "vortex_rotation_acceleration", "vortex_radius_limits", "vortex_core_fraction", "vortex_edge_fraction"]

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for property in get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var value = get(property.name)
		if typeof(value) == TYPE_FLOAT and (not is_finite(value) or value < 0): errors.append(str(property.name) + "：须为有限非负数")
	for field in ["brush_radius", "max_wind", "stroke_speed_full", "cloud_threshold", "hold_seconds", "plot_water_scale", "safe_seconds", "three_star_finish_seconds", "plot_half"]:
		if get(field) <= 0: errors.append(field + "：须大于零")
	var tropical_ranges := {"tropical_evaporation": Vector2(0, 2), "tropical_cooling": Vector2(0, 1), "tropical_energy_min": Vector2(0, 0.9), "tropical_humidity_min": Vector2(0.01, 10), "tropical_convergence_min": Vector2(0.001, 10), "tropical_convection_seconds": Vector2(0.1, 10), "tropical_lift_rate": Vector2(0, 20), "tropical_radius": Vector2(1, 6), "tropical_rotation": Vector2(0, 12), "tropical_inflow": Vector2(0, 12), "tropical_cloud_outflow": Vector2(0, 4), "tropical_support_rate": Vector2(0.01, 100), "tropical_rotation_min": Vector2(0.01, 12), "tropical_growth": Vector2(0, 2), "tropical_decay": Vector2(0, 2), "tropical_steering_gain": Vector2(0, 2), "tropical_motion_cap": Vector2(0, 2), "tropical_steering_response": Vector2(0, 4)}
	for field in tropical_ranges:
		var limits: Vector2 = tropical_ranges[field]
		if get(field) < limits.x or get(field) > limits.y: errors.append(field + "：超出有效范围")
	if brush_radius > 8.0: errors.append("brush_radius：最大 8 世界单位")
	if max_wind > 12.0: errors.append("max_wind：最大 12 世界单位/秒")
	if three_star_finish_seconds < 0.1 or three_star_finish_seconds > 30.0: errors.append("three_star_finish_seconds：须在 0.1–30 秒")
	if wind_spread > 60.0: errors.append("wind_spread：最大 60，避免固定步过度传播")
	if hold_gain > 10.0: errors.append("hold_gain：须在 0–10")
	if source_lifetime < 1.0 or source_lifetime > 30.0: errors.append("source_lifetime：须在 1–30 秒")
	if source_fade_seconds < 0.1 or source_fade_seconds > source_lifetime: errors.append("source_fade_seconds：须在 0.1 秒至风源寿命之间")
	if source_limit < 1 or source_limit > 4: errors.append("source_limit：须在 1–4")
	if not source_powers.is_finite() or source_powers.x < 0.0 or source_powers.z > 10.0 or source_powers.x > source_powers.y or source_powers.y > source_powers.z:
		errors.append("source_powers：弱／中／强须为有限、递增的 0–10 倍率")
	if stroke_max_power < stroke_min_power: errors.append("stroke_max_power：须不小于 stroke_min_power")
	if rain_response > 1.0 or rainy_cloud_response > 1.0: errors.append("rain_response / rainy_cloud_response：须在 0–1")
	if safe_half < plot_half: errors.append("safe_half：须不小于 plot_half")
	if flood_water <= target_water: errors.append("flood_water：须大于 target_water")
	if not open_boundary: errors.append("open_boundary：正式配置须开启；旧封闭回归请直接构造开发模拟")
	if not vortex_inward_acceleration.is_finite() or vortex_inward_acceleration.x < 0 or vortex_inward_acceleration.z > 10 or vortex_inward_acceleration.x >= vortex_inward_acceleration.y or vortex_inward_acceleration.y >= vortex_inward_acceleration.z:
		errors.append("vortex_inward_acceleration：三档须为有限、严格递增的0–10加速度")
	if vortex_rotation_acceleration > 10: errors.append("vortex_rotation_acceleration：须在0–10")
	if not vortex_radius_limits.is_finite() or vortex_radius_limits.x < 0.5 or vortex_radius_limits.y > 8 or vortex_radius_limits.x > vortex_radius_limits.y:
		errors.append("vortex_radius_limits：须为0.5–8的递增半径")
	for rule in [["vortex_core_fraction", 0.1, 0.5], ["vortex_edge_fraction", 0.05, 0.5]]:
		if get(rule[0]) < rule[1] or get(rule[0]) > rule[2]: errors.append("%s：须在%.2f–%.2f" % rule)
	return errors

func apply_live(source: WRWeatherSettings) -> void:
	for field in LIVE_FIELDS: set(field, source.get(field))
