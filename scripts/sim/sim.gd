class_name Sim
extends RefCounted
## Deterministic combat simulation. No nodes, no rendering, no scene tree.
## Drive it with tick(orders) and replay the returned SimEvents in the view.
##
## Interpretation choices (see docs/design.md):
## - Targets are chosen when an action FIRES, not when windup starts, so
##   repositioning/delay orders can dodge or bait attacks.
## - Shield Strike / Riposte arm at the start of the tick they resolve on.
## - A Riposte that goes unattacked on its tick is wasted — timing it via
##   Delay/Hasten orders is the point.
## - Blast splash hits ALL adjacent units (friendly fire); Line hits enemies
##   only, forward along the lane.
## - Player side is on the left (advancing = +col), enemy on the right.

const LANES := 3
const COLS := 12
const SHIELD_REDUCTION := 5

const SIDE_PLAYER := 0
const SIDE_ENEMY := 1

var units: Array[SimUnit] = []
var rng := RandomNumberGenerator.new()
var tick_count := 0
var winner := -1  # -1 = battle ongoing

var _next_id := 1


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


func spawn(creature: CreatureData, side: int, lane: int, col: int) -> SimUnit:
	var u := SimUnit.new()
	u.id = _next_id
	_next_id += 1
	u.side = side
	u.creature = creature
	u.hp = creature.health
	u.lane = lane
	u.col = col
	units.append(u)
	return u


func get_unit(id: int) -> SimUnit:
	for u in units:
		if u.id == id:
			return u
	return null


func alive_units() -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for u in units:
		if u.is_alive():
			out.append(u)
	return out


func unit_at(lane: int, col: int) -> SimUnit:
	for u in units:
		if u.is_alive() and u.lane == lane and u.col == col:
			return u
	return null


func forward(side: int) -> int:
	return 1 if side == SIDE_PLAYER else -1


## Apply one player order immediately, outside the tick ("free action" — does
## not advance the clock). Returns the events it produced; contains
## order_rejected instead of order_applied if the order was invalid.
func apply_order(order) -> Array:
	var events: Array = []
	if winner == -1:
		_apply_orders([order], events)
		_check_end(events)
	return events


func tick(orders: Array = []) -> Array:
	var events: Array = []
	if winner != -1:
		return events
	tick_count += 1
	events.append(SimEvent.make(&"tick_started", {"tick": tick_count}))

	_apply_orders(orders, events)

	for u in alive_units():
		u.acted_this_tick = false
		u.attacked_this_tick = false
		u.shield_active = false
		u.riposte_armed = false

	# Defensive actions resolving this tick arm before anything else happens.
	for u in alive_units():
		if u.windup == 1:
			if u.creature.action == &"shield_strike":
				u.shield_active = true
				events.append(SimEvent.make(&"shield_up", {"unit": u.id}))
			elif u.creature.action == &"riposte" and not u.riposte_used:
				u.riposte_armed = true
				events.append(SimEvent.make(&"riposte_armed", {"unit": u.id}))

	# Initiative pass: everyone ticks toward their action; zero fires it.
	for u in _initiative_order(alive_units()):
		if not u.is_alive() or u.windup <= 0:
			continue
		u.windup -= 1
		events.append(SimEvent.make(&"windup_changed", {"unit": u.id, "windup": u.windup}))
		if u.windup == 0:
			u.windup = -1
			_fire_action(u, events)

	# Shield strikers that went unattacked get their strike.
	for u in _initiative_order(alive_units()):
		if u.shield_active and not u.attacked_this_tick:
			events.append(SimEvent.make(&"shield_counter", {"unit": u.id}))
			_do_strike(u, events)

	# End phase: every idle unit starts a new action or moves into range —
	# including units that fired this tick, so cadence is exactly `delay`
	# and a unit in range is always winding up between ticks.
	for u in _initiative_order(alive_units()):
		if u.windup > 0:
			continue
		_choose_or_move(u, events)

	_check_end(events)
	events.append(SimEvent.make(&"tick_ended", {"tick": tick_count}))
	return events


func _apply_orders(orders: Array, events: Array) -> void:
	for o in orders:
		var u := get_unit(o.unit_id)
		if u == null or not u.is_alive():
			continue
		var ok := false
		var fires := false
		match o.type:
			Order.DELAY:
				if u.windup > 0:
					u.windup += 1
					ok = true
			Order.HASTEN:
				# Hastening a windup to 0 fires the action immediately.
				if u.windup > 0:
					u.windup -= 1
					ok = true
					if u.windup == 0:
						u.windup = -1
						fires = true
			Order.ADVANCE:
				ok = _order_move(u, u.lane, u.col + forward(u.side), events)
			Order.RETREAT:
				ok = _order_move(u, u.lane, u.col - forward(u.side), events)
			Order.MOVE_UP:
				ok = _order_move(u, u.lane - 1, u.col, events)
			Order.MOVE_DOWN:
				ok = _order_move(u, u.lane + 1, u.col, events)
		var type := &"order_applied" if ok else &"order_rejected"
		events.append(SimEvent.make(type, {"unit": u.id, "order": o.type}))
		if ok and (o.type == Order.DELAY or o.type == Order.HASTEN):
			events.append(SimEvent.make(&"windup_changed", {"unit": u.id, "windup": maxi(u.windup, 0)}))
		if fires:
			_fire_action(u, events)


## Ordered moves swap with allies; enemy-occupied or off-grid cells reject.
func _order_move(u: SimUnit, lane: int, col: int, events: Array) -> bool:
	if lane < 0 or lane >= LANES or col < 0 or col >= COLS:
		return false
	var other := unit_at(lane, col)
	if other != null:
		if other.side != u.side:
			return false
		other.lane = u.lane
		other.col = u.col
		events.append(SimEvent.make(&"unit_moved", {"unit": other.id, "lane": other.lane, "col": other.col}))
	u.lane = lane
	u.col = col
	events.append(SimEvent.make(&"unit_moved", {"unit": u.id, "lane": u.lane, "col": u.col}))
	return true


func _initiative_order(list: Array[SimUnit]) -> Array[SimUnit]:
	var arr := list.duplicate()
	var rolls := {}
	for u in arr:
		rolls[u.id] = rng.randi()
	arr.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		if a.creature.initiative != b.creature.initiative:
			return a.creature.initiative > b.creature.initiative
		return rolls[a.id] < rolls[b.id])
	return arr


func _fire_action(u: SimUnit, events: Array) -> void:
	u.acted_this_tick = true
	events.append(SimEvent.make(&"action_fired", {"unit": u.id, "action": u.creature.action}))
	match u.creature.action:
		&"strike":
			_do_strike(u, events)
		&"shoot":
			_do_shoot(u, events)
		&"shield_strike":
			pass  # shield applied at tick start; strike happens at end if unattacked
		&"riposte":
			pass  # resolves reactively when a melee strike comes in
		&"skirmish":
			_do_strike(u, events)
			_move_steps(u, -forward(u.side), 2, events)
		&"blast":
			_do_blast(u, events)
		&"line":
			_do_line(u, events)
		&"heal":
			_do_heal(u, events)


func _do_strike(u: SimUnit, events: Array) -> void:
	var target := _nearest_enemy_in_lane(u, 1)
	if target == null:
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"strike"}))
		return
	_deal_damage(u, target, u.creature.power, true, events)


func _do_shoot(u: SimUnit, events: Array) -> void:
	var target := _nearest_enemy_in_lane(u, u.creature.attack_range)
	if target == null:
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"shoot"}))
		return
	_deal_damage(u, target, u.creature.power, false, events)


func _do_blast(u: SimUnit, events: Array) -> void:
	var target := _nearest_enemy_in_lane(u, u.creature.attack_range)
	if target == null:
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"blast"}))
		return
	var splash_targets: Array[SimUnit] = []
	for v in alive_units():
		if v != target and absi(v.lane - target.lane) + absi(v.col - target.col) == 1:
			splash_targets.append(v)
	_deal_damage(u, target, u.creature.power, false, events)
	for v in splash_targets:
		if v.is_alive():
			_deal_damage(u, v, u.creature.power / 2, false, events)


func _do_line(u: SimUnit, events: Array) -> void:
	var dir := forward(u.side)
	var targets: Array[SimUnit] = []
	for v in alive_units():
		if v.side == u.side or v.lane != u.lane:
			continue
		var dist := (v.col - u.col) * dir
		if dist >= 1 and dist <= u.creature.attack_range:
			targets.append(v)
	if targets.is_empty():
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"line"}))
		return
	for v in targets:
		if v.is_alive():
			_deal_damage(u, v, u.creature.power, false, events)


func _do_heal(u: SimUnit, events: Array) -> void:
	var target := _heal_target(u)
	if target == null:
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"heal"}))
		return
	var amount := mini(u.creature.power, target.creature.health - target.hp)
	target.hp += amount
	events.append(SimEvent.make(&"healed", {"healer": u.id, "target": target.id, "amount": amount}))


func _heal_target(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var best_key := Vector2i(999, 999)  # (0 = same lane / 1 = other lane, distance)
	for v in alive_units():
		if v.side != u.side or v.hp >= v.creature.health:
			continue
		var key := Vector2i(0 if v.lane == u.lane else 1, absi(v.col - u.col) + absi(v.lane - u.lane))
		if key < best_key:
			best = v
			best_key = key
	return best


func _nearest_enemy_in_lane(u: SimUnit, max_range: int) -> SimUnit:
	var best: SimUnit = null
	var best_dist := 999
	for v in alive_units():
		if v.side == u.side or v.lane != u.lane:
			continue
		var dist := absi(v.col - u.col)
		if dist <= max_range and dist < best_dist:
			best = v
			best_dist = dist
	return best


func _deal_damage(attacker: SimUnit, target: SimUnit, amount: int, is_melee: bool, events: Array, is_counter := false) -> void:
	target.attacked_this_tick = true
	if is_melee and not is_counter and target.riposte_armed and not target.riposte_used:
		target.riposte_used = true
		target.riposte_armed = false
		target.acted_this_tick = true
		target.windup = -1
		events.append(SimEvent.make(&"riposte_triggered", {"unit": target.id, "attacker": attacker.id}))
		_deal_damage(target, attacker, target.creature.power, true, events, true)
		return
	var reduction := 0
	if not attacker.creature.has_ability(&"ignores_armour"):
		reduction += target.creature.armour
	if target.shield_active:
		reduction += SHIELD_REDUCTION
	var dmg := maxi(0, amount - reduction)
	target.hp = maxi(0, target.hp - dmg)
	events.append(SimEvent.make(&"damage_dealt", {
		"attacker": attacker.id, "target": target.id, "amount": dmg, "blocked": amount - dmg,
		"melee": is_melee,
	}))
	if not target.is_alive():
		events.append(SimEvent.make(&"unit_died", {"unit": target.id}))


func _choose_or_move(u: SimUnit, events: Array) -> void:
	if _can_start_action(u):
		u.windup = u.creature.delay
		u.riposte_used = false
		events.append(SimEvent.make(&"windup_started", {
			"unit": u.id, "windup": u.windup, "action": u.creature.action,
		}))
		return
	if u.creature.action == &"heal":
		return  # healers hold position rather than marching at the enemy
	if u.creature.has_ability(&"slow") and tick_count % 2 == 1:
		return
	var steps := 2 if u.creature.has_ability(&"fast") else 1
	_move_steps(u, forward(u.side), steps, events)


## Defensive melee units wind up when an enemy is close enough to arrive as
## they arm (1 + delay), so a well-timed windup meets the attacker head-on.
func _engage_range(u: SimUnit) -> int:
	match u.creature.action:
		&"strike", &"skirmish":
			return 1
		&"shield_strike", &"riposte":
			return 1 + u.creature.delay
		_:
			return u.creature.attack_range


## What an idle unit will do in the end phase — view helper, read-only.
## &"act": starts its action; &"move": marches forward; &"hold": stays put
## (healers out of work, or march blocked by a unit / the board edge).
func idle_intent(u: SimUnit) -> StringName:
	if _can_start_action(u):
		return &"act"
	if u.creature.action == &"heal":
		return &"hold"
	var next_col := u.col + forward(u.side)
	if next_col < 0 or next_col >= COLS or unit_at(u.lane, next_col) != null:
		return &"hold"
	return &"move"


func _can_start_action(u: SimUnit) -> bool:
	if u.creature.action == &"heal":
		return _heal_target(u) != null
	return _nearest_enemy_in_lane(u, _engage_range(u)) != null


func _move_steps(u: SimUnit, dir: int, steps: int, events: Array) -> void:
	for i in steps:
		var next_col := u.col + dir
		if next_col < 0 or next_col >= COLS:
			break
		if unit_at(u.lane, next_col) != null:
			break
		u.col = next_col
		events.append(SimEvent.make(&"unit_moved", {"unit": u.id, "lane": u.lane, "col": u.col}))


func _check_end(events: Array) -> void:
	var player_alive := 0
	var enemy_alive := 0
	for u in alive_units():
		if u.side == SIDE_PLAYER:
			player_alive += 1
		else:
			enemy_alive += 1
	if enemy_alive == 0:
		winner = SIDE_PLAYER if player_alive > 0 else SIDE_ENEMY
	elif player_alive == 0:
		winner = SIDE_ENEMY
	if winner != -1:
		events.append(SimEvent.make(&"battle_ended", {"winner": winner}))
