class_name WROnboardingSettings
extends Resource
## Fixed teaching copy, not a generic quest graph. R/review/map change reloads;
## F6 remains weather-only. Delays count active simulation seconds only.
@export_range(1.0, 60.0) var reminder_seconds := 8.0
@export_range(2.0, 120.0) var gesture_seconds := 20.0
@export var titles := PackedStringArray(["找到湿空气", "推向山坡", "等待成云降雨", "搬云改变落点", "观察水位与余雨"])
@export var actions := PackedStringArray([
	"浅色覆盖与流动细丝是湿空气，按住左键拖动它。",
	"朝山坡拖一小段，停住别松手，可以继续吹。",
	"继续送入湿空气，让云变厚并保持片刻，等待雨线。",
	"直接按住云朵拖向水库，改变雨落下的位置。",
	"观察水库旁的水位；蓄满就完成，溢流不会损坏。"])
@export var details := PackedStringArray([
	"只点击不会造风；先试着推动一团浅色细丝。",
	"平地主要搬运水汽；迎坡气流才帮助它抬升成云。",
	"云需要持续补给；雨线从云底落下，才是实际降雨。",
	"松手后云仍会移动和下雨；底部天气提示可显示地面雨区。",
	"云的位置影响落点；移开云后，已储存的水仍会继续落下。"])
@export var map_ids := PackedStringArray(["level01", "level02", "level03", "level04"])
@export var map_titles := PackedStringArray(["把雨送远一点", "两池之间怎样分雨", "农田需要适量与收尾", "选择就近的山坡"])
@export var map_notes := PackedStringArray([
	"先把湿空气送上山。成云后，直接按住云朵拖向较远的水库。\n水库蓄满即完成；溢流不损坏，不必等雨停。",
	"这里有两团湿空气和两个水库。\n可以依次蓄满，也可以轮流送雨；由你决定先后和路线。",
	"农田接近适量时就准备移云，余雨不会立即停下。\n水量合适后，还要解除附近危险天气，维持安全才能保住。水库仍可溢流。",
	"两座山都能帮助水汽抬升。\n观察水汽与目标的位置，选择就近造云或转送已有云雨。"])

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(reminder_seconds) or reminder_seconds < 1.0 or reminder_seconds > 60.0: errors.append("reminder_seconds：须为1–60秒")
	if not is_finite(gesture_seconds) or gesture_seconds <= reminder_seconds or gesture_seconds > 120.0: errors.append("gesture_seconds：须大于reminder_seconds且不超过120秒")
	for key in ["titles", "actions", "details"]:
		var entries: PackedStringArray = get(key)
		if entries.size() != 5: errors.append(key+"：须恰好五个教学节点")
		for entry in entries:
			if entry.strip_edges().is_empty() or entry.length() > 70: errors.append(key+"：每项须为1–70字")
	if map_ids.size() != map_titles.size() or map_ids.size() != map_notes.size(): errors.append("map_ids/map_titles/map_notes：数量须一致")
	var seen := {}
	for id in map_ids:
		if id.strip_edges().is_empty() or seen.has(id): errors.append("map_ids：标识须非空且唯一")
		seen[id] = true
	for entry in map_titles:
		if entry.strip_edges().is_empty(): errors.append("map_titles：标题不可为空")
	for entry in map_notes:
		if entry.strip_edges().is_empty(): errors.append("map_notes：说明不可为空")
	return errors
