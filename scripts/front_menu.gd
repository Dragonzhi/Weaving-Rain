extends Control
## Native entry pages. The host alone owns gameplay, navigation and persistence.
signal action_requested(action: String, id: String)
signal audio_changed(enabled: bool, volume: float)
signal music_changed(volume: float)
const Visuals = preload("res://scripts/hud_visuals.gd")
const View = preload("res://scripts/weather_view.gd")
const Sim = preload("res://scripts/weather_simulation.gd")
const INK = Color("354e57")
const MUTED = Color("607b80")
@export var preview_map_path := "res://configs/maps/level03.tres"
var page := ""
var campaign: WRCampaign
var best: Dictionary = {}
var selected_id := ""
var cards: Array[Button] = []
var content: VBoxContainer
var heading: Label
var back_button: Button
var primary: Button
var start_button: Button
var tutorial_button: Button
var sound_toggle: CheckButton
var volume: HSlider
var volume_label: Label
var music_volume: HSlider
var music_volume_label: Label
var error_label: Label
var grid: GridContainer
var detail_image: TextureRect
var detail_title: Label
var detail_copy: Label
var detail_meta: Label
var detail_medals: Control
var hero_rect: TextureRect
var hero_viewport: SubViewport
var hero_view: Node3D
var hero_sim: RefCounted
var preview_updates := 0
var help_index := 0
var host: Node
var page_tween: Tween
var title_font := SystemFont.new()

class Medals extends Control:
	var value := 0
	var glyphs = preload("res://scripts/hud_visuals.gd").new()
	func _draw() -> void:
		for n in 3: glyphs.medal(self,Vector2(12+n*27,13),10,n<value)

func _ready() -> void:
	title_font.font_names = PackedStringArray(["SimSun","Songti SC","Microsoft YaHei"])
	title_font.allow_system_fallback = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func setup(owner_node: Node) -> void:
	host = owner_node

func _label(text: String, font_size := 18, center := false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",INK)
	if center: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _button(text: String, parent_node: Node, action: String, id := "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.pressed.connect(func(): action_requested.emit(action,id))
	parent_node.add_child(button)
	return button

func _row(parent_node: Node, gap := 16) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",gap)
	parent_node.add_child(row)
	return row

func _column(parent_node: Node, gap := 12) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",gap)
	parent_node.add_child(col)
	return col

func _spacer(parent_node: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent_node.add_child(spacer)

func _image(parent_node: Node, height: float) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y = height
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent_node.add_child(image)
	return image

func thumbnail(id: String) -> Texture2D:
	# Map ID is validated by the resource loader; no filename or campaign position coupling.
	var path := "res://assets/ui/level_previews/"+id+".png"
	return load(path) if ResourceLoader.exists(path) else null

func show_page(next: String) -> void:
	if page_tween: page_tween.kill()
	page = next
	if hero_viewport: hero_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for child in $Margin.get_children():
		$Margin.remove_child(child)
		child.queue_free()
	cards.clear()
	primary = null
	start_button = null
	sound_toggle = null
	volume = null
	music_volume = null
	hero_rect = null
	campaign = host.campaign
	best = host.progress.best
	content = _column($Margin,16)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := _row(content)
	back_button = _button("← 返回",top,"back")
	back_button.visible = page != "home"
	var brand := _label("风织雨  /  WEAVING RAIN",14)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	top.add_child(_label("一缕风，借一场雨。",14))
	if page == "home": _home()
	else:
		var titles := {"levels":"选择关卡","help":"玩法说明","settings":"设置"}
		heading = _label(titles.get(page,"风织雨"),32)
		heading.add_theme_font_override("font",title_font)
		content.add_child(heading)
		match page:
			"levels": _levels()
			"help": _help()
			"settings": _settings()
	error_label = _label("",14)
	error_label.add_theme_color_override("font_color",Color("b8695f"))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(error_label)
	error_label.visible = false
	var footer := _label("随风聚云，因雨而生。",13,true)
	footer.add_theme_color_override("font_color",MUTED)
	content.add_child(footer)
	show()
	if not host.transition_active():
		content.modulate.a = 0
		page_tween = create_tween()
		page_tween.tween_property(content,"modulate:a",1.0,0.18)
	call_deferred("_focus_current")

func _focus_current() -> void:
	if not is_inside_tree() or not visible: return
	if is_instance_valid(primary) and primary.is_inside_tree(): primary.grab_focus()
	elif is_instance_valid(back_button) and back_button.is_visible_in_tree(): back_button.grab_focus()

func set_error(message: String) -> void:
	if error_label:
		error_label.text = message
		error_label.visible = not message.is_empty()

func _home() -> void:
	var title := _label("风 织 雨",58,true)
	title.add_theme_font_override("font",title_font)
	content.add_child(title)
	var english := _label("W E A V I N G   R A I N",13,true)
	english.add_theme_color_override("font_color",MUTED)
	content.add_child(english)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "PreviewFrame"
	var width := minf(760,size.x*0.62)
	frame.custom_minimum_size = Vector2(width,width*9.0/16.0)
	center.add_child(frame)
	hero_rect = _image(frame,190)
	_ensure_hero()
	if hero_viewport:
		hero_rect.texture = hero_viewport.get_texture()
		hero_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var nav := _row(content,22)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	var continuing: bool = host.session_started and host.sim.outcome == "playing"
	primary = _button("继续本局  ↗" if continuing else "开始旅程  ↗",nav,"start")
	primary.theme_type_variation = "PrimaryButton"
	_button("选择关卡",nav,"levels")
	_button("玩法说明",nav,"help")
	_button("设置",nav,"settings")
	var foot := _row(content)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	_button("退出游戏",foot,"quit").add_theme_font_size_override("font_size",14)

func _ensure_hero() -> void:
	if hero_viewport: return
	var loaded := preload("res://scripts/config_loader.gd").map(preview_map_path,host.weather_settings.plot_half)
	if not loaded.errors.is_empty():
		hero_rect.texture = thumbnail("level03")
		return
	hero_viewport = SubViewport.new()
	hero_viewport.size = Vector2i(960,540)
	hero_viewport.own_world_3d = true
	hero_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(hero_viewport)
	hero_sim = Sim.new(host.weather_settings,true,false,loaded.resource.id,loaded.resource)
	# Display-only model, never stepped, bound to audio or passed to gameplay.
	hero_sim.humidity.fill(0)
	hero_sim.cloud.fill(0)
	hero_sim.rain.fill(0)
	hero_sim.cold.fill(0)
	for i in Sim.COUNT:
		var p: Vector2 = hero_sim.positions[i]
		hero_sim.cloud[i] = 3.2*exp(-pow((p.x-2.6)/2.2,2)-pow((p.y+1.9)/1.0,2))
		hero_sim.wind[i] = Vector2(0.45,0.08)
		hero_sim.low_wind[i] = Vector2(0.45,0.08)
		hero_sim.cloud_wind[i] = Vector2(0.45,0.08)
	hero_sim.refresh_display()
	hero_view = View.new()
	hero_viewport.add_child(hero_view)
	hero_view.setup(hero_sim)
	hero_view.hints_enabled = false

func _levels() -> void:
	var layout := _row(content,28)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.7
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	scroll.add_child(grid)
	var maps: Array = campaign.levels if campaign != null else []
	for i in maps.size():
		var definition: WRMapDefinition = maps[i]
		var card := Button.new()
		card.toggle_mode = true
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(170,205)
		card.tooltip_text = definition.title
		card.pressed.connect(func(): choose_level(definition.id); action_requested.emit("click",""))
		grid.add_child(card)
		cards.append(card)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,10)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(margin)
		var col := _column(margin,5)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var image := _image(col,115)
		image.texture = thumbnail(definition.id)
		var label := _label("%02d · %s" % [i+1,definition.title],15)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(label)
		var medals := Medals.new()
		medals.value = int(best.get(definition.id,0))
		medals.custom_minimum_size = Vector2(82,26)
		medals.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(medals)
	var detail := _column(layout,12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size.x = 295
	detail_image = _image(detail,180)
	detail_title = _label("",28)
	detail_title.add_theme_font_override("font",title_font)
	detail.add_child(detail_title)
	detail_copy = _label("",17)
	detail_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(detail_copy)
	detail_meta = _label("",16)
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(detail_meta)
	detail_medals = Medals.new()
	detail_medals.custom_minimum_size = Vector2(82,28)
	detail.add_child(detail_medals)
	_spacer(detail)
	start_button = _button("开始本关  →",detail,"selected")
	start_button.theme_type_variation = "PrimaryButton"
	tutorial_button = _button("重看入门",detail,"tutorial")
	start_button.disabled = maps.is_empty()
	if not maps.is_empty():
		if campaign.find_map(selected_id) == null: selected_id = maps[0].id
		choose_level(selected_id)
	else: detail_copy.text = "当前关卡列表不可用，请检查配置后重试。"
	_button("重新读取关卡",detail,"reload")

func choose_level(id: String) -> void:
	var definition: WRMapDefinition = campaign.find_map(id) if campaign != null else null
	if definition == null: return
	selected_id = id
	for i in cards.size(): cards[i].set_pressed_no_signal(campaign.levels[i].id == id)
	detail_image.texture = thumbnail(id)
	detail_title.text = definition.title
	detail_copy.text = definition.hint
	var goals: Array[String] = []
	for n in definition.plots.size():
		var needs: WRPlotNeeds = definition.plot_needs[n] if n < definition.plot_needs.size() else null
		goals.append("蓄水区" if needs != null and needs.goal_kind == "reservoir" else ("幼苗田" if needs != null and needs.appearance == "seedling" else "农田"))
	var tools: Array[String] = ["拨风"]
	if definition.available_wind_tools & 2: tools.append("风带")
	if definition.available_wind_tools & 4: tools.append("漩涡")
	detail_meta.text = "目标  ·  "+" / ".join(goals)+"\n工具  ·  "+" / ".join(tools)+"\n最佳  ·  %d/3 枚风纹" % int(best.get(id,0))
	detail_medals.value = int(best.get(id,0))
	detail_medals.queue_redraw()

func _help() -> void:
	var tabs := _row(content)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	var names := ["造云与降雨","田地与蓄水区","风工具"]
	for i in 3:
		var tab := Button.new()
		tab.text = names[i]
		tab.toggle_mode = true
		tab.button_pressed = i == help_index
		tab.pressed.connect(func(): help_index = i; show_page("help"); action_requested.emit("click",""))
		tabs.add_child(tab)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	var layout := _row(panel,30)
	var illustration := _column(layout,14)
	illustration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	illustration.size_flags_stretch_ratio = 0.9
	_spacer(illustration)
	var picture := _image(illustration,220)
	picture.texture = thumbnail("tutorial" if help_index==0 else "level03")
	illustration.add_child(_label("地图示意 · 留意实际云形与落雨位置",15,true))
	if help_index==2:
		var icons := _row(illustration,24)
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		for kind in ["brush","source","vortex"]:
			var icon := _image(icons,36)
			icon.texture = Visuals.tool_icon(kind)
	_spacer(illustration)
	var text := RichTextLabel.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.bbcode_enabled = true
	text.add_theme_font_size_override("normal_font_size",20)
	text.add_theme_color_override("default_color",INK)
	var copy := [
		"[font_size=30]借山成云，随风送雨。[/font_size]\n\n浅色覆盖与细丝是湿空气。把它迎着山坡推过去，抬升后便会成云。\n\n云水集中并维持片刻才会降雨。移走补给后，云中储水仍会继续释放；看地面的淡蓝雨区，判断雨落在哪里。\n\n降雨后的灰蓝薄层是冷空气。把湿空气迎向它的前沿，汇聚时也能抬升成云。\n\n白色风线表示实际气流；天气提示可同时开关流向箭头和地面雨区。",
		"[font_size=30]田要适量，池可蓄满。[/font_size]\n\n农田的雨滴表示已收到的水量。够水后还需要移开危险天气并维持安全，才算保住。蓝色渐黄表示余量减少，变红即已损坏。\n\n蓄水区蓄满就完成，继续降雨可以溢流，不会损坏，也不要求附近停雨。\n\n全目标完成得三枚风纹；完成一处而未全完成得一枚，完成更多但未全完成得两枚，零目标完成则没有风纹。到时按当前已完成目标结算。",
		"[font_size=30]拨、留、聚。[/font_size]\n\n拨风：左键拖动，快划更强；先拖出方向后按住停留，可继续吹。仅点击不造风。\n\n风带：左键拖出起终点，滚轮选弱／中／强，松手留下风带；下方按钮可提前关闭。\n\n漩涡：按下定中心、拖动定半径；左键顺时针，右键逆时针，滚轮选力度。聚集后关闭，再用拨风或风带输送。红色预览表示范围无效。\n\n工具按关卡提供，风源共用数量上限；实际持续时间与范围按当前天气配置。"]
	text.text = copy[help_index]
	layout.add_child(text)

func _settings() -> void:
	_spacer(content)
	var panel := PanelContainer.new()
	content.add_child(panel)
	var center := CenterContainer.new()
	content.remove_child(panel)
	content.add_child(center)
	center.add_child(panel)
	panel.custom_minimum_size.x = minf(650,size.x-120)
	var column := _column(panel,24)
	sound_toggle = CheckButton.new()
	sound_toggle.text = "声音（音乐、风雨与操作）"
	sound_toggle.button_pressed = host.weather_audio.enabled
	column.add_child(sound_toggle)
	var row := _row(column)
	row.add_child(_label("总音量",20))
	volume = HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = host.weather_audio.master_volume*100
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume.custom_minimum_size = Vector2(300,40)
	row.add_child(volume)
	volume_label = _label("%d%%" % volume.value,20)
	volume_label.custom_minimum_size.x = 65
	row.add_child(volume_label)
	sound_toggle.toggled.connect(func(on): audio_changed.emit(on,volume.value/100.0))
	volume.value_changed.connect(func(value): volume_label.text = "%d%%" % value; audio_changed.emit(sound_toggle.button_pressed,value/100.0))
	var music_row := _row(column)
	music_row.add_child(_label("音乐音量",20))
	music_volume = HSlider.new()
	music_volume.min_value = 0
	music_volume.max_value = 100
	music_volume.step = 1
	music_volume.value = host.weather_audio.music_volume*100
	music_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_volume.custom_minimum_size = Vector2(260,40)
	music_row.add_child(music_volume)
	music_volume_label = _label("%d%%" % music_volume.value,20)
	music_volume_label.custom_minimum_size.x = 65
	music_row.add_child(music_volume_label)
	music_volume.value_changed.connect(func(value): music_volume_label.text = "%d%%" % value; music_changed.emit(value/100.0))
	var motion := CheckButton.new()
	motion.text = "减少转场动态（本次运行）"
	motion.button_pressed = host.transition.reduced_motion
	motion.toggled.connect(func(on): host.transition.reduced_motion = on)
	column.add_child(motion)
	column.add_child(_label("调整立即生效；下次启动保留声音偏好。" if not host.weather_audio.preferences_path.is_empty() else "调整立即生效；本次开发试玩不写入声音偏好。",16))
	column.add_child(_label("音乐：Meadow Thoughts · Écrivain（CC0）",16))
	column.add_child(_label("F11：切换全屏／窗口，切回时恢复原窗口。",16))
	_spacer(content)

func _process(delta: float) -> void:
	if not visible or page != "home" or hero_view == null: return
	preview_updates += 1
	hero_view.update_weather(minf(delta,0.05),true)

func close() -> void:
	if page_tween: page_tween.kill()
	if hero_viewport: hero_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	page = ""
	hide()
