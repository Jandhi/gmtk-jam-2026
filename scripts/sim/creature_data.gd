class_name CreatureData
extends RefCounted
## Static stats for a creature type, loaded from data/creatures.csv.

var name: String
var health: int
var armour: int
var power: int
var delay: int
var action: StringName  # strike, shoot, shield_strike, riposte, skirmish, blast, line, heal
var attack_range: int
var initiative: int
var abilities: Array[StringName] = []  # fast, slow, ignores_armour


func has_ability(ability: StringName) -> bool:
	return ability in abilities
