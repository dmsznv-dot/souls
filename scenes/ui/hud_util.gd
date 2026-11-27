extends RefCounted
## Small HUD helpers shared by the area controllers.


## A focus (magic) bar styled like the stamina bar, inserted right after it.
static func add_focus_bar(stamina: ProgressBar) -> ProgressBar:
	var bar := stamina.duplicate() as ProgressBar
	bar.name = "Focus"
	bar.unique_name_in_owner = false
	var fill := (stamina.get_theme_stylebox(&"fill") as StyleBoxFlat).duplicate() as StyleBoxFlat
	fill.bg_color = Color(0.48, 0.45, 0.92)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.custom_minimum_size.y = 5
	bar.accessibility_name = "Focus"
	stamina.add_sibling(bar)
	return bar


static func weapon_notice(weapon: SoulsWeapon) -> String:
	return weapon.display_name + ("  ·  " + weapon.hint if not weapon.hint.is_empty() else "")
