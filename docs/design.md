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
3. After all ticks resolve: any unit that hasn't acted and isn't mid-windup
   either starts a new action or moves one space to get into range.

## Player orders (6)

Move in one of four directions, or adjust delay by 1:

- **Advance** / **Retreat** — move toward / away from the enemy side
- **Move Up** / **Move Down** — change lane
- **Delay** — +1 to current action delay
- **Push** — −1 to current action delay

Rules / open ideas:

- Ordering a unit into an ally-occupied space **swaps** the two units.
- Input: either select unit → click order, or drag order onto unit (undecided).
- Order economy: maybe orders have a cooldown, or only refresh if you skip a
  turn (undecided).

## Battle UI (see mockup-battle-ui.png)

- Above each unit: health bar, delay-to-next-action number, icon for the
  *type* of its next action.
- Hover: deep-dive panel with full stats.
- Bottom: the 6 order buttons.

## Gameplay loop

To not overthink it: borrow the loop logic of Dreadful Company.
