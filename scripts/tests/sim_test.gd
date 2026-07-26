extends SceneTree
## Headless sim tests. Run with:
##   godot --headless --path . --script res://scripts/tests/sim_test.gd
## Exits non-zero on failure (used by CI).

var failures := 0
var db: Dictionary


func _init() -> void:
	db = CreatureDB.load_all()
	_test_db_loads()
	_test_basic_fight_resolves()
	_test_determinism()
	_test_armour_reduces_damage()
	_test_ignores_armour()
	_test_swap_order()
	_test_delay_and_hasten_orders()
	_test_line_hits_multiple()
	_test_heal()
	_test_no_rest_after_firing()
	_test_hasten_fires_instantly()
	_test_riposte_counters()
	_test_keep_siege()
	_test_deploy_zone()
	_test_keep_breach_razes_attackers()
	_test_enemy_waves()
	_test_poison()
	_test_lifesteal()
	_test_missile_resist()
	_test_summon()
	_test_shoot_retreat()
	_test_attack_heal()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)


func run_ticks(sim: Sim, n: int) -> Array:
	var all_events: Array = []
	for i in n:
		all_events.append_array(sim.tick())
		if sim.winner != -1:
			break
	return all_events


func events_of(events: Array, type: StringName) -> Array:
	return events.filter(func(e): return e.type == type)


func _test_db_loads() -> void:
	print("db_loads:")
	check(db.size() >= 12, "at least 12 creatures loaded")
	check(db.has("Skeleton") and db["Skeleton"].power == 4, "skeleton stats parsed")
	check(db["Wolf"].has_ability(&"fast"), "abilities parsed")
	# Each archetype ships a player skin and/or an enemy skin; both pools must
	# be stocked or armies and shop stock have nothing to draw from.
	check(not CreatureDB.pool(db, &"player").is_empty(), "player pool stocked")
	check(not CreatureDB.pool(db, &"enemy").is_empty(), "enemy pool stocked")
	check(db["Wolf"].unit_type == db["Mastiff"].unit_type, "skins share an archetype")
	# Beasts are gated out of the soldier voice lines, so the tag has to stick
	# to the animals and stay off anything that can hold a conversation.
	for name in ["Mastiff", "Griffon", "Unicorn"]:
		check(db[name].has_ability(&"beast"), "%s is tagged beast" % name)
	for name in ["Guard", "Knight", "Alseid", "Dryad", "Deva"]:
		check(not db[name].has_ability(&"beast"), "%s can speak" % name)


func _test_basic_fight_resolves() -> void:
	print("basic_fight_resolves:")
	var sim := Sim.new(42)
	# Mismatched on purpose: two identical units trade kills on the same tick
	# and leave an empty board, with nobody left to march on a keep.
	sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 2)
	sim.spawn(db["Skeleton"], Sim.SIDE_ENEMY, 1, 9)
	var events := run_ticks(sim, 50)
	check(events_of(events, &"unit_died").size() >= 1, "someone died")
	check(events_of(events, &"unit_moved").size() >= 5, "units marched toward each other")
	# Clearing the board is not a win — both sides reinforce from cards, so an
	# empty board is a lull. Only a fallen keep ends it.
	check(sim.winner == -1, "a unit wipe doesn't end the battle")
	var rest := run_ticks(sim, 400)
	check(not events_of(events + rest, &"keep_life_lost").is_empty(), "the survivor breaches a keep")
	# ...and the breach razes it, so with nothing left to reinforce, an
	# unattended battle stalls out rather than resolving.
	check(sim.winner == -1, "but the breach razes it, so nobody wins")


func _test_determinism() -> void:
	print("determinism:")
	var results: Array = []
	for run in 2:
		var sim := Sim.new(1234)
		sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 1)
		sim.spawn(db["Wolf"], Sim.SIDE_PLAYER, 1, 1)
		sim.spawn(db["Ogre Zombie"], Sim.SIDE_ENEMY, 0, 10)
		sim.spawn(db["Skeleton"], Sim.SIDE_ENEMY, 1, 10)
		var events := run_ticks(sim, 100)
		results.append([sim.winner, sim.tick_count, events.size()])
	check(results[0][0] == results[1][0], "same winner")
	check(results[0][1] == results[1][1], "same tick count")
	check(results[0][2] == results[1][2], "same event count")


func _test_armour_reduces_damage() -> void:
	print("armour:")
	var sim := Sim.new(7)
	sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 0, 4)  # power 4
	sim.spawn(db["Knight"], Sim.SIDE_ENEMY, 0, 5)     # armour 2
	var events := run_ticks(sim, 10)
	var skeleton_hits := events_of(events, &"damage_dealt").filter(
		func(e): return e.data.attacker == 1)
	check(not skeleton_hits.is_empty(), "skeleton attacked")
	for e in skeleton_hits:
		check(e.data.amount == 2, "skeleton power 4 cut to 2 by armour 2")
		break


func _test_ignores_armour() -> void:
	print("ignores_armour:")
	var sim := Sim.new(7)
	sim.spawn(db["Mage"], Sim.SIDE_PLAYER, 0, 4)   # power 6, ignores armour
	sim.spawn(db["Knight"], Sim.SIDE_ENEMY, 0, 5)  # armour 2
	var events := run_ticks(sim, 8)
	var hits := events_of(events, &"damage_dealt").filter(
		func(e): return e.data.attacker == 1)
	check(not hits.is_empty(), "mage attacked")
	for e in hits:
		check(e.data.amount == 6, "full 6 damage through armour")
		break


func _test_swap_order() -> void:
	print("swap_order:")
	var sim := Sim.new(1)
	var a := sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 0, 2)
	var b := sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 3)
	sim.apply_order(Order.make(a.id, Order.ADVANCE))
	check(a.col == 3 and b.col == 2, "advancing into ally swaps positions")


func _test_delay_and_hasten_orders() -> void:
	print("delay_hasten:")
	var sim := Sim.new(1)
	# Adjacent: shield strike engages at melee reach now, so a guard two tiles
	# out would spend the first tick marching instead of winding up.
	var g := sim.spawn(db["Guard"], Sim.SIDE_PLAYER, 0, 5)
	sim.spawn(db["Ogre Zombie"], Sim.SIDE_ENEMY, 0, 6)
	sim.tick()  # guard is in reach, so it starts winding up
	check(g.windup == db["Guard"].delay, "guard started windup")
	var before := g.windup
	sim.apply_order(Order.make(g.id, Order.DELAY))
	sim.tick()
	check(g.windup == before, "delay +1 then tick -1 nets no progress")
	sim.apply_order(Order.make(g.id, Order.HASTEN))
	sim.tick()
	check(g.windup == before - 2, "hasten -1 plus tick -1")


func _test_line_hits_multiple() -> void:
	print("line:")
	var sim := Sim.new(9)
	sim.spawn(db["Dryad"], Sim.SIDE_ENEMY, 1, 8)
	sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 7)
	sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 1, 6)
	sim.spawn(db["Zombie"], Sim.SIDE_PLAYER, 1, 5)
	var events := run_ticks(sim, db["Dryad"].delay + 1)
	var fired := events_of(events, &"action_fired").filter(
		func(e): return e.data.action == &"line")
	check(not fired.is_empty(), "dryad fired its line")
	var line_hits := events_of(events, &"damage_dealt").filter(
		func(e): return e.data.attacker == 1)
	check(line_hits.size() >= 3, "line hit 3+ units (hit %d)" % line_hits.size())


func _test_heal() -> void:
	print("heal:")
	var sim := Sim.new(3)
	var priest := sim.spawn(db["Priest"], Sim.SIDE_PLAYER, 0, 1)
	var knight := sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 3)
	sim.spawn(db["Ogre Zombie"], Sim.SIDE_ENEMY, 2, 11)
	knight.hp = 5
	var events := run_ticks(sim, db["Priest"].delay + 1)
	var heals := events_of(events, &"healed")
	check(not heals.is_empty(), "priest healed")
	if not heals.is_empty():
		check(heals[0].data.target == knight.id, "healed the damaged knight")
		check(knight.hp == 5 + db["Priest"].power, "heal amount = power")
	check(priest.col == 1, "priest held position instead of marching")


func _test_no_rest_after_firing() -> void:
	print("no_rest_after_firing:")
	var sim := Sim.new(5)
	var g := sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 0, 4)
	sim.spawn(db["Ogre Zombie"], Sim.SIDE_ENEMY, 0, 5)
	# Tick 1 starts the windup at `delay`; it then counts down one per tick, so
	# after `delay` ticks it sits at 1 and the next tick fires.
	for i in db["Skeleton"].delay:
		sim.tick()
	var events := sim.tick()  # fires, then restarts windup in the same end phase
	check(not events_of(events, &"action_fired").is_empty(), "skeleton fired on schedule")
	check(g.windup == g.creature.delay, "windup restarted same tick (cadence = delay)")


func _test_hasten_fires_instantly() -> void:
	print("hasten_fires_instantly:")
	var sim := Sim.new(5)
	var g := sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 0, 4)
	var o := sim.spawn(db["Ogre Zombie"], Sim.SIDE_ENEMY, 0, 5)
	for i in db["Skeleton"].delay:  # tick 1 starts it, the rest count down
		sim.tick()
	check(g.windup == 1, "skeleton at windup 1")
	var events := sim.apply_order(Order.make(g.id, Order.HASTEN))
	check(not events_of(events, &"action_fired").is_empty(), "hasten to 0 fired the strike")
	var hits := events_of(events, &"damage_dealt")
	check(not hits.is_empty() and hits[0].data.target == o.id, "instant strike hit the ogre")
	check(g.windup == -1, "skeleton idle after instant fire")


func _test_riposte_counters() -> void:
	print("riposte:")
	# The noble winds up as the skeleton approaches; when the skeleton's strike
	# lands on the noble's armed tick, it should be negated + countered.
	var sim := Sim.new(11)
	# Adjacent from the off, so both start winding up on the same tick and the
	# skeleton's strike lands while the noble is armed.
	var noble := sim.spawn(db["Noble"], Sim.SIDE_PLAYER, 0, 4)
	sim.spawn(db["Skeleton"], Sim.SIDE_ENEMY, 0, 5)
	var events := run_ticks(sim, 30)
	var counters := events_of(events, &"riposte_triggered")
	check(not counters.is_empty(), "riposte triggered at least once")
	# Not a win any more (the keep still stands) — what matters is who's left.
	check(sim.alive_units().size() == 1, "noble beats skeleton")
	check(noble.hp > 0, "noble survived")


func _test_keep_siege() -> void:
	print("keep_siege:")
	# A skeleton at the wall sieges the enemy keep; the ghost (other lane, never
	# marches, nothing to heal) keeps the battle from ending by unit wipe.
	var sim := Sim.new(3)
	sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 0, 11)
	var ghost := sim.spawn(db["Ghost"], Sim.SIDE_ENEMY, 2, 11)
	var events := run_ticks(sim, 400)
	var hits := events_of(events, &"keep_damaged")
	check(not hits.is_empty(), "keep took damage")
	if not hits.is_empty():
		check(hits[0].data.side == Sim.SIDE_ENEMY, "enemy keep was hit")
		check(hits[0].data.hp == Sim.KEEP_MAX_HP - db["Skeleton"].power, "keep hp dropped by power")
	var lives := events_of(events, &"keep_life_lost")
	# Breaching costs the attacker its army, so one lone skeleton takes exactly
	# one life and isn't around to take the next.
	check(lives.size() == 1, "a lone attacker takes exactly one life")
	if not lives.is_empty():
		check(lives[0].data.lives == Sim.KEEP_LIVES - 1 and lives[0].data.hp == Sim.KEEP_MAX_HP, "losing a life refills the bar")
	check(sim.winner == -1, "one breach doesn't win the battle")
	check(ghost.is_alive(), "the defender is untouched by the breach")


func _test_keep_breach_razes_attackers() -> void:
	print("keep_breach:")
	var sim := Sim.new(3)
	# Two attackers in different lanes: whichever breaches takes BOTH down.
	var a := sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 0, 11)
	var b := sim.spawn(db["Zombie"], Sim.SIDE_PLAYER, 1, 11)
	var defender := sim.spawn(db["Ghost"], Sim.SIDE_ENEMY, 2, 0)
	var events := run_ticks(sim, 400)
	check(not a.is_alive() and not b.is_alive(), "the whole attacking side is razed, not just the breacher")
	check(defender.is_alive(), "the defending side is left standing")
	check(sim.keep_lives[Sim.SIDE_ENEMY] == Sim.KEEP_LIVES - 1, "exactly one life went down")
	var razed := events_of(events, &"unit_died").filter(func(e): return e.data.get("razed", false))
	check(razed.size() == 2, "both deaths are tagged razed")


func _test_deploy_zone() -> void:
	print("deploy:")
	var sim := Sim.new(1)
	var back := Sim.DEPLOY_COLS - 1        # last column still inside your zone
	check(sim.can_deploy(Sim.SIDE_PLAYER, 1, 0), "own back rank is deployable")
	check(sim.can_deploy(Sim.SIDE_PLAYER, 1, back), "whole zone is deployable")
	check(not sim.can_deploy(Sim.SIDE_PLAYER, 1, back + 1), "one past the zone is not")
	check(not sim.can_deploy(Sim.SIDE_PLAYER, 1, Sim.COLS - 1), "their side is not")
	check(not sim.can_deploy(Sim.SIDE_PLAYER, 1, -1), "off-board is not")
	# The enemy's zone is mirrored to their own back columns.
	check(sim.can_deploy(Sim.SIDE_ENEMY, 1, Sim.COLS - 1), "enemy zone mirrors")
	check(not sim.can_deploy(Sim.SIDE_ENEMY, 1, 0), "enemy can't deploy in your zone")

	var events := sim.deploy(db["Guard"], Sim.SIDE_PLAYER, 1, 0)
	check(events.size() == 1 and events[0].type == &"unit_deployed", "deploy emits unit_deployed")
	var u := sim.unit_at(1, 0)
	check(u != null and u.creature.name == "Guard", "the unit is on the board")
	check(u != null and u.hp == db["Guard"].health, "deployed at full health")
	# That cell is taken now, so a second card can't stack onto it.
	check(not sim.can_deploy(Sim.SIDE_PLAYER, 1, 0), "occupied cell is not deployable")
	check(sim.deploy(db["Scout"], Sim.SIDE_PLAYER, 1, 0).is_empty(), "illegal deploy is a no-op")
	check(sim.deploy_cells(Sim.SIDE_PLAYER).size() == Sim.LANES * Sim.DEPLOY_COLS - 1,
		"deploy_cells drops the occupied one")


func _test_enemy_waves() -> void:
	print("enemy_waves:")
	var sim := Sim.new(7)
	# An empty pool is the default, and it must stay a still board — every other
	# test in this file relies on nothing walking on unasked.
	var quiet := Sim.new(7)
	quiet.spawn(db["Guard"], Sim.SIDE_PLAYER, 1, 0)
	var quiet_events := run_ticks(quiet, 30)
	check(events_of(quiet_events, &"unit_deployed").is_empty(), "no pool means no waves")

	sim = Sim.new(7)
	sim.enemy_pool = CreatureDB.pool(db, &"enemy")
	sim.spawn(db["Guard"], Sim.SIDE_PLAYER, 1, 0)
	var early := run_ticks(sim, Sim.WAVE_FIRST_TICK - 1)
	check(events_of(early, &"unit_deployed").is_empty(), "nothing walks on during the grace period")
	var first := run_ticks(sim, 1)
	check(not events_of(first, &"unit_deployed").is_empty(), "the first wave lands on WAVE_FIRST_TICK")
	for e in events_of(first, &"unit_deployed"):
		check(e.data.side == Sim.SIDE_ENEMY, "waves are enemy-side")
		check(e.data.col >= Sim.COLS - Sim.DEPLOY_COLS, "waves arrive in the enemy deploy zone")
		check(sim.get_unit(e.data.unit).creature.tier == 1, "the opening wave is tier 1 only")

	# The cap is the mercy rule: the board can never hold more than
	# WAVE_MAX_ENEMIES, however long the battle runs.
	var flood := Sim.new(11)
	flood.enemy_pool = CreatureDB.pool(db, &"enemy")
	run_ticks(flood, 80)
	var live := 0
	for u in flood.alive_units():
		if u.side == Sim.SIDE_ENEMY:
			live += 1
	check(live <= Sim.WAVE_MAX_ENEMIES, "live enemies never exceed the cap (%d)" % live)
	check(flood.wave_interval() < Sim.WAVE_INTERVAL_START, "the cadence tightened over 80 ticks")
	check(flood.wave_budget() > Sim.WAVE_THREAT_BASE, "the budget grew over 80 ticks")

	# Waves are part of the seeded replay like everything else.
	var a := Sim.new(23)
	var b := Sim.new(23)
	a.enemy_pool = CreatureDB.pool(db, &"enemy")
	b.enemy_pool = CreatureDB.pool(db, &"enemy")
	var a_names := []
	var b_names := []
	run_ticks(a, 60)
	run_ticks(b, 60)
	for u in a.units:
		a_names.append("%s@%d,%d" % [u.creature.name, u.lane, u.col])
	for u in b.units:
		b_names.append("%s@%d,%d" % [u.creature.name, u.lane, u.col])
	check(a_names == b_names, "waves replay identically from the same seed")


func _test_poison() -> void:
	print("poison:")
	var sim := Sim.new(4)
	var dryad := sim.spawn(db["Dryad"], Sim.SIDE_PLAYER, 1, 4)
	var victim := sim.spawn(db["Zombie"], Sim.SIDE_ENEMY, 1, 6)
	var events := run_ticks(sim, 3)
	check(not events_of(events, &"poison_applied").is_empty(), "the line applies poison")
	check(victim.poison_ticks > 0, "the victim is rotting")
	var before := victim.hp
	var ticked := events_of(run_ticks(sim, 1), &"poison_ticked")
	check(not ticked.is_empty(), "poison burns a tick")
	check(victim.hp < before, "poison takes health off")
	check(dryad.poison_ticks == 0, "poison doesn't splash back onto the source")

	# Armour is no defence against rot.
	var armoured := Sim.new(4)
	var target := armoured.spawn(db["Knight"], Sim.SIDE_ENEMY, 1, 6)
	target.poison_ticks = 2
	var hp := target.hp
	run_ticks(armoured, 1)
	check(target.hp == hp - Sim.POISON_DAMAGE, "poison ignores armour")


func _test_lifesteal() -> void:
	print("lifesteal:")
	var sim := Sim.new(5)
	var vamp := sim.spawn(db["Vampire"], Sim.SIDE_ENEMY, 1, 6)
	sim.spawn(db["Ogre Zombie"], Sim.SIDE_PLAYER, 1, 5)  # a big bag of hp to chew on
	vamp.hp = 4
	var events := run_ticks(sim, 6)
	check(not events_of(events, &"healed").is_empty(), "lifesteal reports as a heal")
	check(vamp.hp > 4, "the vampire got health back")
	check(vamp.hp <= vamp.creature.health, "lifesteal can't overheal")

	# A hit that gets fully blocked feeds nothing.
	var blocked := Sim.new(5)
	var weak := blocked.spawn(db["Vampire"], Sim.SIDE_ENEMY, 1, 6)
	var wall := blocked.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 5)
	weak.hp = 1
	weak.creature = db["Vampire"]
	check(blocked.predicted_damage(weak, wall, 0) == 0, "a zero hit is a zero hit")


func _test_missile_resist() -> void:
	print("missile_resist:")
	var sim := Sim.new(6)
	var scout := sim.spawn(db["Scout"], Sim.SIDE_PLAYER, 1, 4)
	var guard := sim.spawn(db["Skeleton Guard"], Sim.SIDE_ENEMY, 1, 7)
	var knight := sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 4)
	# Scout power 4 -> halved to 2 -> minus the guard's 1 armour = 1.
	check(sim.predicted_damage(scout, guard, scout.creature.power, false) == 1,
		"arrows are halved before armour")
	# Melee ignores the trait entirely: Knight power 9 - 1 armour = 8.
	check(sim.predicted_damage(knight, guard, knight.creature.power, true) == 8,
		"melee is unaffected by missile resist")
	# The hover preview has to agree with what the hit will actually do.
	var preview := sim.intent_preview(scout)
	check(preview.damage.get(guard.id, -1) == 1, "the preview shows the resisted number")


func _test_summon() -> void:
	print("summon:")
	var sim := Sim.new(8)
	sim.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
	var lich := sim.spawn(db["Lich"], Sim.SIDE_ENEMY, 1, 7)
	sim.spawn(db["Guard"], Sim.SIDE_PLAYER, 1, 4)
	var events := run_ticks(sim, 8)
	var summons := events_of(events, &"unit_deployed").filter(
		func(e): return e.data.get("summoned_by", -1) == lich.id)
	check(not summons.is_empty(), "the lich conjures servants")
	check(not events_of(events, &"damage_dealt").is_empty(), "and still gets its shot off")
	for e in summons:
		check(sim.get_unit(e.data.unit).creature.name == "Skeleton", "it summons skeletons")
		check(sim.get_unit(e.data.unit).side == Sim.SIDE_ENEMY, "on its own side")

	# No registered creature means no summon, but the shot still lands.
	var bare := Sim.new(8)
	bare.spawn(db["Lich"], Sim.SIDE_ENEMY, 1, 7)
	bare.spawn(db["Guard"], Sim.SIDE_PLAYER, 1, 4)
	var bare_events := run_ticks(bare, 8)
	check(events_of(bare_events, &"unit_deployed").is_empty(), "no summon creature, no summon")
	check(not events_of(bare_events, &"damage_dealt").is_empty(), "the shot goes off regardless")


func _test_shoot_retreat() -> void:
	print("shoot_retreat:")
	var sim := Sim.new(9)
	var alseid := sim.spawn(db["Alseid"], Sim.SIDE_PLAYER, 1, 5)
	sim.spawn(db["Zombie"], Sim.SIDE_ENEMY, 1, 8)
	var start := alseid.col
	var events := run_ticks(sim, 3)
	check(not events_of(events, &"damage_dealt").is_empty(), "the alseid shoots")
	check(alseid.col < start, "and gives ground after firing")


func _test_attack_heal() -> void:
	print("attack_heal:")
	var sim := Sim.new(10)
	sim.spawn(db["Deva"], Sim.SIDE_PLAYER, 1, 5)
	var hurt := sim.spawn(db["Guard"], Sim.SIDE_PLAYER, 0, 5)
	sim.spawn(db["Zombie"], Sim.SIDE_ENEMY, 1, 7)
	hurt.hp = 1
	var events := run_ticks(sim, 5)
	check(not events_of(events, &"healed").is_empty(), "the deva mends as it fights")
	check(hurt.hp > 1, "the wounded ally is patched up")
