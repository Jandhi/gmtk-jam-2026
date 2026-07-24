class_name UnitView
extends Node2D
## Visual representation of one SimUnit: sprite, health bar, windup number,
## action icon. Reads sim state via refresh(); never computes gameplay.

const BAR_W := 52.0

const ACTION_LABELS := {
	&"strike": "STR", &"shoot": "SHT", &"shield_strike": "SHD", &"riposte": "RIP",
	&"skirmish": "SKR", &"blast": "BLA", &"line": "LIN", &"heal": "HEA",
}

var unit_id := 0

var _sprite: Sprite2D
var _hp_fill: ColorRect
var _delay_label: Label
var _action_label: Label
var _max_hp := 1


func setup(unit: SimUnit) -> void:
	unit_id = unit.id
	_max_hp = unit.creature.health

	var team := ColorRect.new()
	team.size = Vector2(40, 4)
	team.position = Vector2(-20, 32)
	team.color = Color(0.35, 0.85, 0.35) if unit.side == Sim.SIDE_PLAYER else Color(0.9, 0.3, 0.3)
	add_child(team)

	_sprite = Sprite2D.new()
	var tex_path := "res://assets/art/Monsters/%s.PNG" % unit.creature.name
	if ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.flip_h = unit.side == Sim.SIDE_ENEMY
	add_child(_sprite)

	var bar_bg := ColorRect.new()
	bar_bg.size = Vector2(BAR_W, 7)
	bar_bg.position = Vector2(-BAR_W / 2, -46)
	bar_bg.color = Color(0.12, 0.12, 0.12)
	add_child(bar_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.size = Vector2(BAR_W - 2, 5)
	_hp_fill.position = Vector2(1, 1)
	_hp_fill.color = Color(0.4, 0.9, 0.35)
	bar_bg.add_child(_hp_fill)

	_delay_label = Label.new()
	_delay_label.position = Vector2(-BAR_W / 2, -66)
	_delay_label.add_theme_font_size_override("font_size", 12)
	add_child(_delay_label)

	_action_label = Label.new()
	_action_label.position = Vector2(2, -66)
	_action_label.add_theme_font_size_override("font_size", 12)
	_action_label.modulate = Color(1, 0.85, 0.4)
	add_child(_action_label)

	refresh(unit)


func refresh(unit: SimUnit) -> void:
	_hp_fill.size.x = maxf(0.0, (BAR_W - 2) * float(unit.hp) / float(_max_hp))
	_delay_label.text = str(unit.windup) if unit.windup > 0 else "-"
	_action_label.text = ACTION_LABELS.get(unit.creature.action, "?")
