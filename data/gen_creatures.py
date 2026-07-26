# Regenerates data/creatures.csv from the design spreadsheet.
# Sheet columns: Unit Type, Tier, Gold Cost, Num in Starter Deck, Goodie,
# Baddie, HP, Armour, Init, Range, Power, Action Type, Delay, Traits
import csv, os

ROWS = [
    ("Mook",           1, 0, 0, "-",       "Skeleton",       6, 0,  5, 0,  4, "Strike",              2, ""),
    # The sheet has these two baddie names the wrong way round — it gives the
    # Archer to "Skeleton Guard" and the shield to "Skeleton Archer". Swapped
    # here to match Rosalind's sprites (Skeleton Archer.PNG carries the bow,
    # Skeleton Guard.PNG the shield). Fix the sheet and this can come out.
    ("Shield Guy",     1, 6, 4, "Guard",   "Skeleton Guard", 8, 1,  5, 0,  5, "Shield Strike",       3, "Missile Resist"),
    ("Dog",            1, 3, 2, "Mastiff", "Wolf",           4, 0, 10, 0,  3, "Skirmish Strike",     2, "Fast"),
    ("Archer",         1, 6, 2, "Scout",   "Skeleton Archer",6, 0,  6, 4,  4, "Missile",             2, ""),
    ("Strong Guy",     2, 15, 0, "Knight",  "Wight",         12, 2,  4, 0,  9, "Strike",              3, ""),
    # Sheet says "Zombie Ogre"; the sprite is Ogre Zombie.PNG and sprites are
    # looked up by name, so the data has to use the art's spelling.
    ("Big Guy",        2, 15, 0, "-",       "Ogre Zombie",   16, 0,  3, 0, 10, "Strike",              3, "Slow"),
    ("Duelist",        2, 15, 0, "Noble",   "Ghast",         10, 1,  9, 0,  6, "Riposte",             2, ""),
    ("Healer",         2, 12, 0, "Priest",  "Ghost",          8, 0,  5, 0,  4, "Heal",                2, ""),
    ("Blaster",        2, 21, 0, "Mage",    "-",              7, 0,  7, 4,  6, "Blast",               3, "Ignores Armour"),
    ("Elite Archer",   2, 18, 0, "Alseid",  "-",              8, 0, 11, 4,  6, "Missile and Retreat", 2, ""),
    ("Thorns",         2, 15, 0, "Dryad",   "-",              9, 0,  6, 3,  4, "Line",                2, "Poison"),
    ("Flyer",          2, 15, 0, "Griffon", "-",             10, 0, 13, 0,  6, "Skirmish Strike",     2, "Fast"),
    ("Charger",        2, 18, 0, "Unicorn", "-",             14, 1,  8, 0,  8, "Strike",              3, "Fast"),
    ("Shambler",       1, 0, 0, "-",       "Zombie",        12, 0,  3, 0,  4, "Strike",              2, "Slow"),
    ("Slasher",        1, 0, 0, "-",       "Shadow",         3, 0, 12, 0,  5, "Skirmish Strike",     2, ""),
    ("Angel",          3, 27, 0, "Deva",    "-",             18, 2,  8, 3,  8, "Blast",               3, "Heals allies on Attack"),
    ("Nightstalker",   3, 0, 0, "-",       "Vampire",       16, 1, 12, 0,  8, "Skirmish Strike",     2, "Lifesteal"),
    ("Headless Rider", 3, 0, 0, "-",       "Dullahan",      20, 2, 10, 0, 10, "Strike",              3, "Fast"),
    ("Archlich",       3, 0, 0, "-",       "Lich",          14, 0,  7, 4,  9, "Summon",              3, "Summons Skeletons"),
]
# Two columns here no longer match the sheet, and regenerating from a
# "corrected" sheet would silently undo both:
#  - Delay: shortened from the originals (5->3, 4->3, 3->2, 2->2) so fights
#    start paying off sooner.
#  - Gold Cost: raised ~3x, so a shop visit buys one or two things rather than
#    the whole shelf. See SHOP_PRICES in battle.gd for the matching order prices.

# Sheet action name -> sim action. The sim implements strike, shoot,
# shield_strike, riposte, skirmish, blast, line, heal.
ACTIONS = {
    "Strike": "strike",
    "Shield Strike": "shield_strike",
    "Skirmish Strike": "skirmish",
    "Missile": "shoot",
    "Blast": "blast",
    "Heal": "heal",
    "Riposte": "riposte",
    "Line": "line",
    "Missile and Retreat": "shoot_retreat",
    "Summon": "summon",
}
APPROXIMATED = set()

# Traits go through as snake_case whether or not the sim reads them yet;
# unimplemented ones are inert until something checks for them.
IMPLEMENTED_TRAITS = {"fast", "slow", "ignores_armour", "beast", "poison",
                      "lifesteal", "missile_resist", "heals_allies_on_attack",
                      "summons_skeletons"}

# Creatures with no speech, tagged "beast" so the game knows not to give them
# the soldier voice lines — a dog shouldn't answer an order with "yes, sir".
# Judged on whether it can talk, not whether it's human: the Alseid, Dryad and
# Deva aren't human but are all perfectly articulate.
# TODO: add a "Beast" entry to the sheet's Traits column and delete this set.
BEASTS = {"Mastiff", "Wolf", "Griffon", "Unicorn"}


def trait_slug(t):
    return t.strip().lower().replace(" ", "_")


HEADER = ["name", "health", "armour", "power", "delay", "action", "range",
          "initiative", "abilities", "unit_type", "tier", "side", "cost",
          "starter_count"]

out = []
notes = {"approx_action": [], "unknown_traits": set()}
for (utype, tier, cost, starter, goodie, baddie, hp, armour, init, rng, power,
     action, delay, traits) in ROWS:
    abilities = "|".join(trait_slug(t) for t in traits.split(",") if t.strip())
    for slug in abilities.split("|"):
        if slug and slug not in IMPLEMENTED_TRAITS:
            notes["unknown_traits"].add(slug)
    if action in APPROXIMATED:
        notes["approx_action"].append((utype, action, ACTIONS[action]))
    for name, side in ((goodie, "player"), (baddie, "enemy")):
        if name == "-":
            continue
        # "beast" is per-skin: an archetype can have a talking Goodie and a
        # snarling Baddie, so it can't live on the shared trait list.
        own = abilities
        if name in BEASTS:
            own = "|".join(filter(None, [abilities, "beast"]))
        out.append([name, hp, armour, power, delay, ACTIONS[action], rng,
                    init, own, utype, tier, side, cost, starter])

dest = os.path.join(os.path.dirname(__file__), "creatures.csv")
with open(dest, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(HEADER)
    w.writerows(out)

print("%d creatures (%d player / %d enemy)" % (
    len(out), sum(1 for r in out if r[11] == "player"),
    sum(1 for r in out if r[11] == "enemy")))
print("approximated actions:", notes["approx_action"])
print("traits with no sim support:", sorted(notes["unknown_traits"]))
