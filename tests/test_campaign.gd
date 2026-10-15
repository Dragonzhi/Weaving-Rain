extends SceneTree
const Loader = preload("res://scripts/config_loader.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	var plot_half: float = load("res://configs/weather.tres").plot_half
	var result := Loader.campaign("res://configs/campaign.tres",plot_half)
	check(result.errors.is_empty(),"Published campaign validates: " + str(result.errors))
	var campaign: WRCampaign = result.resource
	check(not campaign.levels.is_empty() and campaign.tutorial.id == "tutorial","Configured formal sequence and independent tutorial load")
	# Single/multiple sequence edge cases use a fixture, not the current authored count.
	campaign = WRCampaign.new()
	campaign.tutorial = load("res://configs/tutorial.tres")
	campaign.levels = [load("res://configs/maps/level01.tres")]
	check(campaign.next_id("level01").is_empty() and campaign.next_id("unknown").is_empty(),"Single and unknown maps never wrap into a test map")
	campaign.levels.append(load("res://configs/maps/storm_coast.tres"))
	check(campaign.next_id("level01") == "storm_coast" and campaign.next_id("storm_coast").is_empty(),"Ordered references determine the next map")
	campaign.levels.reverse()
	check(campaign.next_id("storm_coast") == "level01","Reordering needs no map renames")
	campaign.levels.append(campaign.levels[0])
	check("重复地图id" in "；".join(campaign.validation_errors(plot_half)),"Duplicate ids report the offending array field")
	campaign.levels = [null]
	check("levels[0]" in "；".join(campaign.validation_errors(plot_half)),"Missing map reports the array index")
	campaign.levels.clear()
	check("至少" in "；".join(campaign.validation_errors(plot_half)),"Empty formal lists are rejected")
	campaign.levels.append(load("res://configs/maps/standard.tres"))
	check("star_level" in "；".join(campaign.validation_errors(plot_half)),"Unrated practice maps cannot silently enter formal progression")
	campaign.tutorial = null
	check("tutorial" in "；".join(campaign.validation_errors(plot_half)),"Missing tutorial is reported")
	campaign.tutorial = load("res://configs/tutorial.tres").duplicate(true)
	check("已保存" in "；".join(campaign.validation_errors(plot_half)),"Unsaved embedded teaching cannot produce an empty runtime map path")
	check(not Loader.campaign("res://.godot/no-such-campaign.tres",plot_half).errors.is_empty(),"Missing configuration fails without replacing caller state")
	print("CAMPAIGN: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
