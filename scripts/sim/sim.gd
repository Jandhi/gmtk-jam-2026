class_name Sim
extends RefCounted
## Deterministic combat simulation. No nodes, no rendering, no scene tree.
## Drive it with tick() and replay the returned SimEvents in the view.
## Player orders are instant free actions applied via apply_order().
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
## Keep durability doubles as the match clock — it's what decides how many
## turns a run lasts. 24x2 puts a competent run at roughly 90 ticks, which is
## one sitting; 30x3 ran past 190 and turned into End Turn homework.
## See scripts/tests/playtest_sim.gd for the sweep these came from.
const KEEP_MAX_HP := 24
const KEEP_LIVES := 2

# --- Ability tuning ---
## `poison`: every hit refreshes this many ticks of rot on the target, each
## dealing POISON_DAMAGE straight to hp. Duration refreshes rather than
## stacking, so the Dryad's job is to keep the line lit, not to burst it down.
const POISON_TICKS := 3
const POISON_DAMAGE := 1
## `missile_resist`: the shield turns most of an arrow aside before armour even
## comes into it. Melee is unaffected — that's the whole trade.
const MISSILE_RESIST_DIVISOR := 2
## `lifesteal`: share of damage dealt that comes back as health, as a divisor.
const LIFESTEAL_DIVISOR := 2
## `heals_allies_on_attack`: share of the attacker's power mended on its most
## wounded ally each time it swings, as a divisor.
const ATTACK_HEAL_DIVISOR := 2
## `summons_skeletons`: a summoner stops conjuring once its side is this many
## strong, so a Lich left alone can't bury the board on its own.
const SUMMON_MAX_ALLIES := 8

const SIDE_PLAYER := 0
const SIDE_ENEMY := 1

## How many of your own back columns a unit card may deploy into. Reinforcements
## arrive behind the line and have to march up like everyone else.
const DEPLOY_COLS := 3

# --- Enemy reinforcement waves ---
# The enemy has no deck and no shop. Instead a director spends a threat budget
# on its roster every few ticks, and both the budget and the cadence ramp with
# the clock: the opening is a duel you can read, the late game is a tide you
# have to out-tempo. Waves only run once `enemy_pool` is filled in (see
# CreatureDB.pool) — leaving it empty gives a still board, which is what most
# of the tests want.

## Grace period: the opening duel gets to resolve before anything walks on.
const WAVE_FIRST_TICK := 5
## Ticks between waves. Drops by one every WAVE_INTERVAL_EVERY ticks, so the
## same budget lands more often as the battle drags on.
const WAVE_INTERVAL_START := 6
const WAVE_INTERVAL_MIN := 3
const WAVE_INTERVAL_EVERY := 25
## Threat a wave may spend: base + this much per tick elapsed. Deliberately
## shallow — the cadence, not the budget, is what makes the late game bite.
const WAVE_THREAT_BASE := 1.5
const WAVE_THREAT_PER_TICK := 0.09
## What one unit of each tier costs that budget. Tuned against the length of a
## real run rather than against each other: at these numbers the first elite is
## affordable around tick 17 and the first super around tick 50, which lands
## the supers inside a game instead of after it (see wave_report.gd).
const WAVE_THREAT_BY_TIER := {1: 1.0, 2: 3.0, 3: 6.0}
## Ceiling on horrors fielded at once. This is the mercy rule: a wave only
## brings the difference, so falling behind slows the tide instead of burying
## you, and clearing the board is what invites the next full wave.
## Has to stay near what the player can actually field (~4-5 units), or the
## cap never binds and the enemy just grinds you down: at 7 a competent player
## won 5% of the time, at 5 it's a real contest.
const WAVE_MAX_ENEMIES := 5
## Ticks before elites / supers may show up at all, on top of affording them.
const WAVE_TIER2_TICK := 12
const WAVE_TIER3_TICK := 40

var units: Array[SimUnit] = []
var rng := RandomNumberGenerator.new()
var tick_count := 0
var winner := -1  # -1 = battle ongoing

## CreatureData the wave director may field, e.g. CreatureDB.pool(db, &"enemy").
var enemy_pool: Array = []
var _next_wave_tick := WAVE_FIRST_TICK

## What a `summon` action conjures, keyed by the summoner's side. Left empty,
## summoners fall back to shooting — the sim never hard-codes a creature name.
var summon_units := {}

## Each side's keep sits on a virtual tile one past its board edge (player
## col -1, enemy col COLS) in every lane. Exhausting its hp costs a life and
## refills the bar; at 0 lives the other side wins. Indexed by side.
var keep_hp: Array[int] = [KEEP_MAX_HP, KEEP_MAX_HP]
var keep_lives: Array[int] = [KEEP_LIVES, KEEP_LIVES]

var _next_id := 1


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


## `armed` starts the unit mid-windup instead of idle, so it shows a countdown
## from the very first frame rather than only after a tick has passed.
func spawn(creature: CreatureData, side: int, lane: int, col: int, armed := false) -> SimUnit:
	var u := SimUnit.new()
	u.id = _next_id
	_next_id += 1
	u.side = side
	u.creature = creature
	u.hp = creature.health
	u.lane = lane
	u.col = col
	if armed:
		u.windup = creature.delay
	units.append(u)
	return u


## Is `col` inside `side`'s own deployment zone — its back DEPLOY_COLS columns?
func in_deploy_zone(side: int, col: int) -> bool:
	return col < DEPLOY_COLS if side == SIDE_PLAYER else col >= COLS - DEPLOY_COLS


## Can a unit card be played onto this cell? Needs to be on the board, empty,
## and inside that side's own back ranks.
func can_deploy(side: int, lane: int, col: int) -> bool:
	if lane < 0 or lane >= LANES or col < 0 or col >= COLS:
		return false
	if not in_deploy_zone(side, col):
		return false
	return unit_at(lane, col) == null


## Bring a unit in off a card, outside the tick (a free action, like orders).
## Returns the events to replay, or an empty array if the cell was illegal.
func deploy(creature: CreatureData, side: int, lane: int, col: int) -> Array:
	if not can_deploy(side, lane, col):
		return []
	var u := spawn(creature, side, lane, col)
	return [SimEvent.make(&"unit_deployed", {
		"unit": u.id, "lane": lane, "col": col, "side": side,
	})]


## Every legal cell for a unit card right now — view helper for the overlay.
func deploy_cells(side: int) -> Array:
	var out := []
	for lane in LANES:
		for col in COLS:
			if can_deploy(side, lane, col):
				out.append(Vector2i(lane, col))
	return out


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
		_apply_order(order, events)
		_check_end(events)
	return events


func tick() -> Array:
	var events: Array = []
	if winner != -1:
		return events
	tick_count += 1
	events.append(SimEvent.make(&"tick_started", {"tick": tick_count}))

	# Reinforcements walk on before the fighting. They spawn idle, so they take
	# no part in this tick's initiative pass and only pick up an action (or
	# start marching) in the end phase, like any other unit that just arrived.
	_run_wave(events)

	for u in alive_units():
		u.acted_this_tick = false
		u.attacked_this_tick = false
		u.shield_active = false
		u.riposte_armed = false

	# Rot burns before anyone swings, so a poisoned unit on its last point can
	# be finished by the poison rather than getting one more action off.
	_tick_poison(events)

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


# --- Enemy reinforcement waves ---


## Walk on whatever this tick's wave can afford. Always re-arms the timer, even
## when nothing arrives, so a stalled wave costs the enemy its slot rather than
## queueing up and dumping everything the moment the board clears.
func _run_wave(events: Array) -> void:
	if enemy_pool.is_empty() or tick_count < _next_wave_tick:
		return
	_next_wave_tick = tick_count + wave_interval()
	var live := 0
	for u in alive_units():
		if u.side == SIDE_ENEMY:
			live += 1
	var room := WAVE_MAX_ENEMIES - live
	if room <= 0:
		return
	var budget := wave_budget()
	for c in _pick_wave(budget, room):
		var cell := _wave_cell()
		if cell.x == -1:
			break  # deploy zone full — the rest of the budget is simply lost
		var u := spawn(c, SIDE_ENEMY, cell.x, cell.y)
		events.append(SimEvent.make(&"unit_deployed", {
			"unit": u.id, "lane": cell.x, "col": cell.y, "side": SIDE_ENEMY, "wave": true,
		}))


## Ticks between waves right now — shortens as the battle drags on.
func wave_interval() -> int:
	return maxi(WAVE_INTERVAL_MIN, WAVE_INTERVAL_START - tick_count / WAVE_INTERVAL_EVERY)


## Threat this tick's wave may spend.
func wave_budget() -> float:
	return WAVE_THREAT_BASE + tick_count * WAVE_THREAT_PER_TICK


## Which tick the next wave is due on — view helper for the countdown.
func next_wave_tick() -> int:
	return _next_wave_tick


## Arm the next wave to land on the coming tick. Dev helper for testing the
## ramp without playing thirty turns to reach it.
func force_wave() -> void:
	_next_wave_tick = tick_count + 1


func _wave_threat(c: CreatureData) -> float:
	return WAVE_THREAT_BY_TIER.get(c.tier, 1.0)


## Elites and supers need the clock as well as the budget, so the first ten
## ticks can't roll a Dullahan off a lucky ramp.
func _wave_tier_cap() -> int:
	if tick_count >= WAVE_TIER3_TICK:
		return 3
	if tick_count >= WAVE_TIER2_TICK:
		return 2
	return 1


## Spend `budget` on at most `room` units. Each pick rolls twice and keeps the
## costlier of the two: waves lean toward the biggest thing they can afford
## without ever being pure elites, so chaff keeps showing up alongside them.
func _pick_wave(budget: float, room: int) -> Array:
	var out := []
	var tier_cap := _wave_tier_cap()
	while out.size() < room:
		var affordable := []
		for c in enemy_pool:
			if c.tier <= tier_cap and _wave_threat(c) <= budget:
				affordable.append(c)
		if affordable.is_empty():
			break
		var a: CreatureData = affordable[rng.randi() % affordable.size()]
		var b: CreatureData = affordable[rng.randi() % affordable.size()]
		var pick: CreatureData = a if _wave_threat(a) >= _wave_threat(b) else b
		out.append(pick)
		budget -= maxf(_wave_threat(pick), 0.5)  # floor guards against a 0-cost tier
	return out


## Where the next horror walks on: the emptiest lane, at the very back of the
## deploy zone, so reinforcements have to march up the board like everyone
## else. Returns (-1, -1) when the zone is full.
func _wave_cell() -> Vector2i:
	var lanes: Array[int] = []
	for lane in LANES:
		lanes.append(lane)
	# Shuffled so equally-empty lanes don't always fall to lane 0. Uses the
	# sim's own rng, so the shuffle stays part of the deterministic replay.
	for i in range(lanes.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp := lanes[i]
		lanes[i] = lanes[j]
		lanes[j] = tmp
	var best := Vector2i(-1, -1)
	var best_key := Vector2i(999, 999)  # (enemies in lane, steps in from the back)
	for lane in lanes:
		var count := 0
		for u in alive_units():
			if u.side == SIDE_ENEMY and u.lane == lane:
				count += 1
		for step in DEPLOY_COLS:
			var col := COLS - 1 - step
			if unit_at(lane, col) != null:
				continue
			var key := Vector2i(count, step)
			if key < best_key:
				best_key = key
				best = Vector2i(lane, col)
			break
	return best


func _apply_order(o, events: Array) -> void:
	var u := get_unit(o.unit_id)
	if u == null or not u.is_alive():
		return
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
		&"shoot_retreat":
			# Skirmishing at range: loose a shot, then give ground so the thing
			# you just shot arrives a tick later than it wanted to.
			_do_shoot(u, events)
			_move_steps(u, -forward(u.side), 1, events)
		&"blast":
			_do_blast(u, events)
		&"line":
			_do_line(u, events)
		&"heal":
			_do_heal(u, events)
		&"summon":
			_do_summon(u, events)
			_do_shoot(u, events)
	# The Deva mends as it fights: every swing puts something back on whoever
	# on its side is worst off.
	if u.creature.has_ability(&"heals_allies_on_attack"):
		var mend_target := _heal_target(u, false)
		if mend_target != null:
			_mend(u, mend_target, u.creature.power / ATTACK_HEAL_DIVISOR, events)


## Burn a tick off every poisoned unit. Poison ignores armour and shields — it
## is already inside them — and can kill, which reports as a normal death so
## bounties and card returns keep working.
func _tick_poison(events: Array) -> void:
	for u in _initiative_order(alive_units()):
		if u.poison_ticks <= 0:
			continue
		u.poison_ticks -= 1
		u.hp = maxi(0, u.hp - POISON_DAMAGE)
		events.append(SimEvent.make(&"poison_ticked", {
			"unit": u.id, "amount": POISON_DAMAGE, "remaining": u.poison_ticks,
		}))
		if not u.is_alive():
			events.append(SimEvent.make(&"unit_died", {"unit": u.id}))


func _do_strike(u: SimUnit, events: Array) -> void:
	var target := _nearest_enemy_in_lane(u, 1)
	if target == null:
		if _keep_dist(u) <= 1:
			_damage_keep(u, events, true)
		else:
			events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"strike"}))
		return
	_deal_damage(u, target, u.creature.power, true, events)


func _do_shoot(u: SimUnit, events: Array) -> void:
	var target := _nearest_enemy_in_lane(u, u.creature.attack_range)
	if target == null:
		if _keep_dist(u) <= u.creature.attack_range:
			_damage_keep(u, events)
		else:
			events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"shoot"}))
		return
	_deal_damage(u, target, u.creature.power, false, events)


func _do_blast(u: SimUnit, events: Array) -> void:
	var target := _nearest_enemy_in_lane(u, u.creature.attack_range)
	if target == null:
		# A blast on the keep is a clean hit — no splash off the virtual tile.
		if _keep_dist(u) <= u.creature.attack_range:
			_damage_keep(u, events)
		else:
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
	var hits_keep := _keep_dist(u) <= u.creature.attack_range
	if targets.is_empty() and not hits_keep:
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"line"}))
		return
	for v in targets:
		if v.is_alive():
			_deal_damage(u, v, u.creature.power, false, events)
	if hits_keep:  # the line pierces through to the keep behind
		_damage_keep(u, events)


## Conjure a servant into a free cell beside the summoner. Silently does
## nothing when there's nowhere to put it, when the side is already at
## SUMMON_MAX_ALLIES, or when no creature is registered for that side — in
## every case the summoner's shot still goes off, so the action never whiffs.
func _do_summon(u: SimUnit, events: Array) -> void:
	if not summon_units.has(u.side):
		return
	var allies := 0
	for v in alive_units():
		if v.side == u.side:
			allies += 1
	if allies >= SUMMON_MAX_ALLIES:
		return
	# Behind first, then beside: a skeleton dropped in front would eat the
	# Lich's own line of fire.
	var back := -forward(u.side)
	# Typed so `d.x`/`d.y` come back as ints — an untyped literal makes them
	# Variant and the offsets below can't infer a type.
	var spots: Array[Vector2i] = [Vector2i(0, back), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -back)]
	for d in spots:
		var lane := u.lane + d.x
		var col := u.col + d.y
		if lane < 0 or lane >= LANES or col < 0 or col >= COLS:
			continue
		if unit_at(lane, col) != null:
			continue
		var summoned := spawn(summon_units[u.side], u.side, lane, col)
		events.append(SimEvent.make(&"unit_deployed", {
			"unit": summoned.id, "lane": lane, "col": col, "side": u.side,
			"summoned_by": u.id,
		}))
		return


func _do_heal(u: SimUnit, events: Array) -> void:
	var target := _heal_target(u)
	if target == null:
		events.append(SimEvent.make(&"action_fizzled", {"unit": u.id, "action": &"heal"}))
		return
	var amount := mini(u.creature.power, target.creature.health - target.hp)
	target.hp += amount
	events.append(SimEvent.make(&"healed", {"healer": u.id, "target": target.id, "amount": amount}))


## Nearest wounded ally, same lane first. `include_self` is what separates a
## Priest (who may patch itself up) from heals-allies-on-attack, which is
## exactly what its name says and would otherwise just top the attacker up.
func _heal_target(u: SimUnit, include_self := true) -> SimUnit:
	var best: SimUnit = null
	var best_key := Vector2i(999, 999)  # (0 = same lane / 1 = other lane, distance)
	for v in alive_units():
		if v.side != u.side or v.hp >= v.creature.health:
			continue
		if v == u and not include_self:
			continue
		var key := Vector2i(0 if v.lane == u.lane else 1, absi(v.col - u.col) + absi(v.lane - u.lane))
		if key < best_key:
			best = v
			best_key = key
	return best


## Distance to the enemy keep's virtual tile (one past the far board edge).
## Enemy units are always nearer, so the keep is only ever a fallback target.
func _keep_dist(u: SimUnit) -> int:
	return (COLS - u.col) if u.side == SIDE_PLAYER else (u.col + 1)


func _damage_keep(u: SimUnit, events: Array, is_melee := false) -> void:
	var side := 1 - u.side
	var amount := u.creature.power
	keep_hp[side] = maxi(0, keep_hp[side] - amount)
	events.append(SimEvent.make(&"keep_damaged", {
		"attacker": u.id, "side": side, "amount": amount, "hp": keep_hp[side],
		"melee": is_melee,
	}))
	if keep_hp[side] == 0:
		keep_lives[side] -= 1
		if keep_lives[side] > 0:
			keep_hp[side] = KEEP_MAX_HP
		events.append(SimEvent.make(&"keep_life_lost", {
			"side": side, "lives": keep_lives[side], "hp": keep_hp[side],
		}))
		# Breaching a keep spends the assault: the attacking army is razed
		# where it stands, handing the defender room for a comeback. Skipped
		# on the last life, where the battle is already over.
		if keep_lives[side] > 0:
			_raze_side(u.side, events)
			# Both sides get the beat to rebuild, whoever broke through: the
			# board has just been cleared of one army, and a wave landing into
			# that vacuum would turn a hard-won breach into a losing position.
			_next_wave_tick = maxi(_next_wave_tick, tick_count + wave_interval())


## Wipe a whole side off the board. Deaths are reported as normal unit_died
## events (tagged "razed" so the view can blow them up rather than fade them),
## which keeps everything hanging off a death — bounties, card returns — working.
func _raze_side(side: int, events: Array) -> void:
	for v in alive_units():
		if v.side == side:
			v.hp = 0
			events.append(SimEvent.make(&"unit_died", {"unit": v.id, "razed": true}))


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


## What `amount` raw damage from `attacker` actually takes off `target` after
## armour and any active shield. Pure — `_deal_damage` and the hover preview
## both go through it so the shown number can't drift from the dealt one.
## A riposte the hit might provoke isn't modelled: this is the hit as thrown.
func predicted_damage(attacker: SimUnit, target: SimUnit, amount: int, is_melee := true) -> int:
	# A missile-resistant shield turns the shot aside first; whatever gets past
	# it still has armour to chew through.
	if not is_melee and target.creature.has_ability(&"missile_resist"):
		amount = amount / MISSILE_RESIST_DIVISOR
	var reduction := 0
	if not attacker.creature.has_ability(&"ignores_armour"):
		reduction += target.creature.armour
	if target.shield_active:
		reduction += SHIELD_REDUCTION
	return maxi(0, amount - reduction)


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
	var dmg := predicted_damage(attacker, target, amount, is_melee)
	target.hp = maxi(0, target.hp - dmg)
	events.append(SimEvent.make(&"damage_dealt", {
		"attacker": attacker.id, "target": target.id, "amount": dmg, "blocked": amount - dmg,
		"melee": is_melee,
	}))
	# A hit that lands is what carries poison and feeds lifesteal — a fully
	# blocked one does neither.
	if dmg > 0:
		if attacker.creature.has_ability(&"poison") and target.is_alive():
			target.poison_ticks = POISON_TICKS
			events.append(SimEvent.make(&"poison_applied", {
				"unit": target.id, "attacker": attacker.id, "ticks": POISON_TICKS,
			}))
		if attacker.creature.has_ability(&"lifesteal") and attacker.is_alive():
			_mend(attacker, attacker, dmg / LIFESTEAL_DIVISOR, events)
	if not target.is_alive():
		events.append(SimEvent.make(&"unit_died", {"unit": target.id}))


## Put health back on a unit, capped at its maximum. Reports as a normal
## `healed` event so the view animates lifesteal and a Priest identically.
func _mend(healer: SimUnit, target: SimUnit, amount: int, events: Array) -> void:
	var gained := mini(amount, target.creature.health - target.hp)
	if gained <= 0:
		return
	target.hp += gained
	events.append(SimEvent.make(&"healed", {
		"healer": healer.id, "target": target.id, "amount": gained,
	}))


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
## How far out a unit will commit to its action instead of marching. Melee
## closes to reach first; everything else engages at its stated range.
##
## Shield Strike and Riposte used to engage at 1 + delay so their defensive
## windup was already up when the enemy arrived. It read as cowardice — they
## halted in open field and raised a guard at nothing while the enemy was
## still tiles off. Walking up to your foe first looks like a soldier.
func _engage_range(u: SimUnit) -> int:
	match u.creature.action:
		&"strike", &"skirmish", &"shield_strike", &"riposte":
			return 1
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


## Where the unit's current/next action lands — view helper for the hover
## preview, read-only. "move"/"hit"/"heal" hold Vector2i(lane, col) cells;
## "move" is every cell the march steps through, in order, so a fast unit
## yields two. "damage" maps unit id -> hp the hit would take off that unit,
## after armour and shields. "keep" is the defending side when the hit lands
## on the keep's virtual tile (-1 otherwise). Marching preview ignores the
## slow-tick parity.
func intent_preview(u: SimUnit) -> Dictionary:
	var out := {"move": [], "hit": [], "heal": [], "damage": {}, "keep": -1}
	if u.windup > 0 or _can_start_action(u):
		var reach := u.creature.attack_range
		match u.creature.action:
			&"strike", &"skirmish", &"shield_strike":
				var t := _nearest_enemy_in_lane(u, 1)
				if t != null:
					_preview_hit(out, u, t, u.creature.power, true)
				elif _keep_dist(u) <= 1:
					out.keep = 1 - u.side
			# A summon's shot previews like any other; where the servant lands
			# depends on the board at the moment it fires, so it isn't shown.
			&"shoot", &"shoot_retreat", &"summon":
				var t := _nearest_enemy_in_lane(u, reach)
				if t != null:
					_preview_hit(out, u, t, u.creature.power)
				elif _keep_dist(u) <= reach:
					out.keep = 1 - u.side
			&"blast":
				var t := _nearest_enemy_in_lane(u, reach)
				if t != null:
					_preview_hit(out, u, t, u.creature.power)
					for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var c := Vector2i(t.lane + d.x, t.col + d.y)
						if c.x >= 0 and c.x < LANES and c.y >= 0 and c.y < COLS:
							out.hit.append(c)
							# Splash catches whoever stands there — allies included.
							var splashed := unit_at(c.x, c.y)
							if splashed != null:
								out.damage[splashed.id] = predicted_damage(u, splashed, u.creature.power / 2, false)
				elif _keep_dist(u) <= reach:
					out.keep = 1 - u.side
			&"line":
				for v in alive_units():
					if v.side != u.side and v.lane == u.lane:
						var dist := (v.col - u.col) * forward(u.side)
						if dist >= 1 and dist <= reach:
							_preview_hit(out, u, v, u.creature.power)
				if _keep_dist(u) <= reach:
					out.keep = 1 - u.side
			&"heal":
				var t := _heal_target(u)
				if t != null:
					out.heal.append(Vector2i(t.lane, t.col))
	elif u.creature.action != &"heal":
		var steps := 2 if u.creature.has_ability(&"fast") else 1
		var col := u.col
		for i in steps:
			var next := col + forward(u.side)
			if next < 0 or next >= COLS or unit_at(u.lane, next) != null:
				break
			col = next
			out.move.append(Vector2i(u.lane, col))
	return out


## Record one previewed hit: the cell to outline plus what it would cost.
## `is_melee` has to match what the real hit will pass, or a missile-resistant
## target's shown number drifts from the one it actually takes.
func _preview_hit(out: Dictionary, attacker: SimUnit, target: SimUnit, amount: int, is_melee := false) -> void:
	out.hit.append(Vector2i(target.lane, target.col))
	out.damage[target.id] = predicted_damage(attacker, target, amount, is_melee)


func _can_start_action(u: SimUnit) -> bool:
	if u.creature.action == &"heal":
		return _heal_target(u) != null
	if _nearest_enemy_in_lane(u, _engage_range(u)) != null:
		return true
	# Units at the wall siege the keep. Melee engages at actual reach (not the
	# early defensive windup — the keep never closes the gap); riposte can't
	# trigger off a keep, so those units just hold.
	if u.creature.action == &"riposte":
		return false
	var reach := 1 if u.creature.action in [&"strike", &"skirmish", &"shield_strike"] else u.creature.attack_range
	return _keep_dist(u) <= reach


func _move_steps(u: SimUnit, dir: int, steps: int, events: Array) -> void:
	for i in steps:
		var next_col := u.col + dir
		if next_col < 0 or next_col >= COLS:
			break
		if unit_at(u.lane, next_col) != null:
			break
		u.col = next_col
		events.append(SimEvent.make(&"unit_moved", {"unit": u.id, "lane": u.lane, "col": u.col}))


## Only a fallen keep ends the battle. Losing every unit isn't a loss — both
## sides field reinforcements from cards, so an empty board is a lull, not a
## result.
func _check_end(events: Array) -> void:
	if keep_lives[SIDE_ENEMY] <= 0:
		winner = SIDE_PLAYER
	elif keep_lives[SIDE_PLAYER] <= 0:
		winner = SIDE_ENEMY
	if winner != -1:
		events.append(SimEvent.make(&"battle_ended", {"winner": winner}))
