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

## Special abilities

- **Fast** — move 2 spaces each tick.
- **Slow** — move only every other tick.
- **Ignores Armour** — attacks ignore armour.

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
`range` tiles out; Line pierces through to it). Keeps have **30 HP and 3
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
