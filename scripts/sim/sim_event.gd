class_name SimEvent
extends RefCounted
## One thing that happened in the sim. The visual layer replays these;
## it never computes gameplay itself.
##
## Types and their data fields:
##   tick_started      {tick}
##   order_applied     {unit, order}
##   order_rejected    {unit, order}
##   unit_moved        {unit, lane, col}
##   windup_started    {unit, windup, action}
##   windup_changed    {unit, windup}
##   shield_up         {unit}
##   riposte_armed     {unit}
##   riposte_triggered {unit, attacker}
##   action_fired      {unit, action}
##   action_fizzled    {unit, action}
##   shield_counter    {unit}
##   damage_dealt      {attacker, target, amount, blocked}
##   healed            {healer, target, amount}
##   unit_died         {unit}
##   battle_ended      {winner}
##   tick_ended        {tick}

var type: StringName
var data: Dictionary


static func make(event_type: StringName, event_data: Dictionary = {}) -> SimEvent:
	var e := SimEvent.new()
	e.type = event_type
	e.data = event_data
	return e
