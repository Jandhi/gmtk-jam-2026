class_name CardController
extends Control
## Controller for card.tscn. Edit the look in the scene; this wires data in.

const ORDER_DATA := {
	Order.ADVANCE: {"label": "Advance", "icon": "res://assets/art/UI/shoe-icon.png"},
	Order.RETREAT: {"label": "Retreat", "icon": "res://assets/art/UI/left-arrow-icon.png"},
	Order.MOVE_UP: {"label": "Move Up", "icon": ""},
	Order.MOVE_DOWN: {"label": "Move Down", "icon": ""},
	Order.DELAY: {"label": "Delay +1", "icon": ""},
	Order.HASTEN: {"label": "Hasten -1", "icon": ""},
}

var order_type: StringName = &""

@onready var background: TextureRect = $Background
@onready var portrait: TextureRect = $Portrait
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel


func setup(creature: CreatureData, cost: int) -> void:
	name_label.text = creature.name
	cost_label.text = str(cost)
	var tex_path := "res://assets/art/Monsters/%s.PNG" % creature.name
	if ResourceLoader.exists(tex_path):
		portrait.texture = load(tex_path)


func setup_order(type: StringName) -> void:
	order_type = type
	var data: Dictionary = ORDER_DATA.get(type, {})
	name_label.text = data.get("label", String(type))
	cost_label.visible = false
	var icon: String = data.get("icon", "")
	if not icon.is_empty() and ResourceLoader.exists(icon):
		portrait.texture = load(icon)
	else:
		portrait.texture = null


## Re-show the (hidden-by-setup_order) cost label as a shop price tag.
func show_cost(cost: int) -> void:
	cost_label.text = "%dg" % cost
	cost_label.visible = true


func set_selected(selected: bool) -> void:
	pivot_offset = size / 2.0
	modulate = Color(1, 0.95, 0.6) if selected else Color.WHITE
	scale = Vector2(1.08, 1.08) if selected else Vector2.ONE
