class_name Order
extends RefCounted
## A player order for one unit, applied at the start of the next tick.

const ADVANCE := &"advance"
const RETREAT := &"retreat"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const DELAY := &"delay"    # +1 to current windup
const HASTEN := &"hasten"  # -1 to current windup (min 1)

const ALL: Array[StringName] = [ADVANCE, RETREAT, MOVE_UP, MOVE_DOWN, DELAY, HASTEN]

var unit_id: int
var type: StringName


static func make(id: int, order_type: StringName) -> Order:
	var o := Order.new()
	o.unit_id = id
	o.type = order_type
	return o
