class_name SimUnit
extends RefCounted
## A unit instance on the battlefield. Pure state — no nodes, no visuals.

var id: int
var side: int  # Sim.SIDE_PLAYER or Sim.SIDE_ENEMY
var creature: CreatureData
var hp: int
var lane: int
var col: int

## -1 = idle, >0 = ticks remaining until the action fires.
var windup: int = -1

# Per-tick combat flags, reset by the sim each tick.
var acted_this_tick := false
var attacked_this_tick := false
var shield_active := false
var riposte_armed := false
var riposte_used := false


func is_alive() -> bool:
	return hp > 0
