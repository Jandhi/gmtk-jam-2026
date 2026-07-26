# Design — grid autobattler with order-based control

Units fight autonomously on a grid (lanes × columns). The player doesn't control
attacks — they issue **orders** that reposition units and manipulate action timing.

## Unit stats

| Stat | Meaning |
|---|---|
| Health | Reduced to 0 → defeated |
| Armour | Flat damage reduction from attacks that don't ignore armour |
| Power | Damage on attacks |
| Delay | How many ticks it takes for this unit to attack |
| Action Type | How this unit attacks |
| Range | The range this unit engages enemies at |
| Initiative | Priority to do its action (ties rolled) |

## Action types

- **Strike** — basic attack, damage = power, target in your lane.
- **Shoot** — basic attack, damage = power, target in your lane up to range away.
- **Shield Strike** — take 5 less damage from all attacks this tick; if not attacked this tick, you strike.
- **Riposte** — negate the first melee strike received this tick and counter-attack.
- **Skirmish** — strike and retreat 2 spaces.
- **Blast** — shoot that also deals half damage to adjacent units.
- **Line** — shoot that damages all units in a line, range long.
- **Heal** — heal, prioritizing nearest damaged unit in your lane, then just the nearest damaged unit.
- **Missile and Retreat** — shoot, then give ground 1 space. Skirmishing at range.
- **Summon** — conjure a servant into a free cell beside you (behind first, so
  it doesn't block your own line of fire), *and* take your shot. Stops
  conjuring once your side is 8 strong.

## Special abilities

- **Fast** — move 2 spaces each tick.
- **Slow** — move only every other tick.
- **Ignores Armour** — attacks ignore armour.
- **Missile Resist** — non-melee damage is halved *before* armour applies.
  Melee is untouched — that's the trade for carrying a shield.
- **Poison** — any hit that lands refreshes 3 ticks of rot on the target,
  1 damage each. Rot burns at the top of a tick, before anyone swings, and
  ignores armour and shields. Refreshes rather than stacks.
- **Lifesteal** — half the damage dealt comes back as health, capped at max.
  A fully blocked hit feeds nothing.
- **Heals Allies on Attack** — every swing mends the nearest wounded *ally*
  (never yourself) for half your power.
- **Summons Skeletons** — pairs with the Summon action; what gets conjured is
  registered by the battle scene, so the sim never hard-codes a creature name.

## Enemy waves

The enemy has no deck and no shop. A wave director inside the sim spends a
**threat budget** on the enemy roster every few ticks. Both the budget and the
cadence ramp with the clock, so the opening is a duel you can read and the late
game is a tide you have to out-tempo.

- Threat per unit: tier 1 = 1, tier 2 = 3, tier 3 = 6.
- Budget = `1.5 + 0.09 × tick`. Interval starts at 6 ticks and drops by one
  every 25 ticks, floor 3.
- Elites are locked until tick 12, supers until tick 40 — on top of having to
  be affordable, which is usually the binding constraint (first elite ≈ t17,
  first super ≈ t50).
- Each pick rolls twice and keeps the costlier, so waves lean toward the
  biggest thing they can afford without ever being pure elites.
- Reinforcements arrive at the **back** of the enemy deploy zone, in the
  emptiest lane, and march up like everyone else.

Two mercy rules keep it from snowballing:

- **A hard ceiling of 5 live enemies.** A wave only brings the difference, so
  falling behind slows the tide instead of burying you, and clearing the board
  is what invites the next full wave. Past the mid-game this is the real
  governor — a bigger budget buys *better* units, not more of them. The number
  is set near what the player can actually field: at 7 the cap never bound and
  a competent player won 5% of the time, at 5 it's a contest.
- **A breach costs both sides a beat.** Whoever breaks through, the next wave
  is pushed back a full interval, so a hard-won breach doesn't immediately hand
  the board back.

`scripts/tests/wave_report.gd` prints the schedule and an unattended-board
outcome for eyeballing the ramp (not part of CI). Left alone, a board loses its
last keep life around tick 71–82.

## Resolving a tick

1. In initiative order (rolling ties), each unit ticks 1 step towards its action.
2. A unit reaching 0 resolves its action. Defensive actions (Riposte, Shield
   Strike) have portions that trigger before anyone else so they defend properly.
3. After all ticks resolve: every unit not mid-windup — including one that
   just fired — either starts a new action or moves one space to get into
   range. Attack cadence is therefore exactly `delay`, and a unit in range
   is always winding up between ticks.

## Keeps

Each side has a keep sitting on a virtual tile one past its board edge (every
lane) — player keep at col −1, enemy keep at col 12. Units that reach the wall
with no enemy in range attack the keep instead (ranged units hit it from
`range` tiles out; Line pierces through to it). Keeps have **24 HP and 2
lives**: exhausting the bar costs a life and refills it; at 0 lives the other
side wins. Keeps have no armour and never attack, so Riposte units hold at
the wall instead of sieging.

## Shop & gold

Every 20 ticks a shop panel drops down from the top of the screen (turn input
pauses while it's open). It offers 3 distinct order cards at per-type prices;
bought cards go to the **discard pile** and cycle in on the next reshuffle.
Gold: +1 per tick, +3 per enemy unit killed.

## Player orders (6)

Move in one of four directions, or adjust delay by 1:

- **Advance** / **Retreat** — move toward / away from the enemy side
- **Move Up** / **Move Down** — change lane
- **Delay** — +1 to current action delay
- **Push** — −1 to current action delay

Rules / open ideas:

- Orders are played as **cards** (draw 1/tick, hand limit 7, opening hand 4)
  and **resolve instantly** as free actions that don't advance the clock —
  including consequences: **hastening a windup to 0 fires the action
  immediately**. Delay/Hasten can target enemy units; movement is own-only.
- Rejected orders (blocked cell, idle unit) don't consume the card.
- Ordering a unit into an ally-occupied space **swaps** the two units.
- Input: either select unit → click order, or drag order onto unit (undecided).
- Order economy: maybe orders have a cooldown, or only refresh if you skip a
  turn (undecided).

## Battle UI (see mockup-battle-ui.png)

- Above each unit: health bar, delay-to-next-action number, icon for the
  *type* of its next action.
- Hover: deep-dive panel with full stats.
- Bottom: the 6 order buttons.

## Economy (idea)

Cards + two currencies: **mana** (in-battle, spent to play/discard) and **gold**
(meta, spent at markets to grow the deck).

Mana:

- Discard a card for 1 mana each — a free action that doesn't advance the clock.
- Gain 1 mana whenever your forces kill an enemy unit — unless that unit is
  **Soulless** (gives none). Units with **Powerful Soul** give 3 mana instead.

Cards:

- Draw one card every tick. You can pass if you don't want to play anything.
- Hand limit: 8.

Farms & the market:

- The lane backgrounds hold **5 farms/goldmines** at fixed columns. If 2 of a
  player's 3 lanes have advanced past a farm, that player claims it.
- Every **20 ticks** a **market phase** triggers: earn gold based on farms
  controlled, spend it on new cards for your deck from a random selection.
- Gold carries over between market phases.
- Very expensive action (maybe itself a card): transmute a ton of mana into
  one gold.

## Gameplay loop

To not overthink it: borrow the loop logic of Dreadful Company.
