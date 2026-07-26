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
var abilities: Array[StringName] = []  # fast, slow, ignores_armour (others parse but are inert)

# Roster data from the spreadsheet. Each archetype ("unit_type") ships two
# skins with identical stats — a player-side one and an enemy-side one — so
# the same design reads as a hero or a horror depending on who fields it.
var unit_type: String
var tier: int
var side: StringName  # &"player" / &"enemy" — which pool this skin belongs to
var cost: int
var starter_count: int


func has_ability(ability: StringName) -> bool:
	return ability in abilities
