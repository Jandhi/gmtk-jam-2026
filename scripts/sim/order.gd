class_name Order
extends RefCounted
## A player order for one unit, applied instantly via Sim.apply_order().

const ADVANCE := &"advance"
const RETREAT := &"retreat"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const DELAY := &"delay"    # +1 to current windup
const HASTEN := &"hasten"  # -1 to current windup (min 1)

const ALL: Array[StringName] = [ADVANCE, RETREAT, MOVE_UP, MOVE_DOWN, DELAY, HASTEN]

## Unit cards ride in the same deck as orders, tagged "unit:<Creature>".
## They aren't Orders — they target an empty cell rather than a unit, and are
## played through Sim.deploy() instead of Sim.apply_order().
const UNIT_PREFIX := "unit:"


static func unit_card(creature_name: String) -> StringName:
	return StringName(UNIT_PREFIX + creature_name)


static func is_unit_card(type: StringName) -> bool:
	return String(type).begins_with(UNIT_PREFIX)


static func card_creature(type: StringName) -> String:
	return String(type).substr(UNIT_PREFIX.length())

var unit_id: int
var type: StringName


static func make(id: int, order_type: StringName) -> Order:
	var o := Order.new()
	o.unit_id = id
	o.type = order_type
	return o
