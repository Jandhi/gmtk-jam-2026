class_name CardController
extends Control
## Controller for card.tscn. Edit the look in the scene; this wires data in.

@onready var background: NinePatchRect = $Background
@onready var portrait: TextureRect = $Portrait
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel


func setup(creature: CreatureData, cost: int) -> void:
	name_label.text = creature.name
	cost_label.text = str(cost)
	var tex_path := "res://assets/art/Monsters/%s.PNG" % creature.name
	if ResourceLoader.exists(tex_path):
		portrait.texture = load(tex_path)
