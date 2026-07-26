class_name CardController
extends Control
## Controller for card.tscn. Edit the look in the scene; this wires data in.

## "art" is a full-card 32x44 overlay drawn over the background; "icon" is an
## 8x8 sprite shown in the portrait slot. Art wins when both exist.
const ORDER_DATA := {
	Order.ADVANCE: {"label": "Advance", "art": "res://assets/art/UI/cards/advance.png"},
	Order.RETREAT: {"label": "Retreat", "art": "res://assets/art/UI/cards/retreat.png"},
	Order.MOVE_UP: {"label": "Move Up", "art": "res://assets/art/UI/cards/move up.png"},
	Order.MOVE_DOWN: {"label": "Move Down", "art": "res://assets/art/UI/cards/move down.png"},
	Order.DELAY: {"label": "Delay", "art": "res://assets/art/UI/cards/delay.png"},
	Order.HASTEN: {"label": "Hasten", "art": "res://assets/art/UI/cards/hasten.png"},
}

var order_type: StringName = &""

@onready var background: TextureRect = $Background
@onready var portrait: TextureRect = $Portrait
@onready var art_overlay: TextureRect = $ArtOverlay
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel


func setup(creature: CreatureData, cost: int) -> void:
	name_label.text = creature.name
	cost_label.text = str(cost)
	var tex_path := "res://assets/art/Monsters/%s.PNG" % creature.name
	if ResourceLoader.exists(tex_path):
		portrait.texture = load(tex_path)


## A unit card: portrait + name, and it keeps its "unit:<Creature>" type so
## the hand can tell it apart from an order.
func setup_unit(type: StringName, creature: CreatureData) -> void:
	order_type = type
	name_label.text = creature.name
	cost_label.visible = false
	art_overlay.visible = false
	var tex_path := "res://assets/art/Monsters/%s.PNG" % creature.name
	portrait.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null


func setup_order(type: StringName) -> void:
	order_type = type
	var data: Dictionary = ORDER_DATA.get(type, {})
	name_label.text = data.get("label", String(type))
	cost_label.visible = false
	var art: String = data.get("art", "")
	if not art.is_empty() and ResourceLoader.exists(art):
		art_overlay.texture = load(art)
		art_overlay.visible = true
		portrait.texture = null
		return
	art_overlay.visible = false
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
