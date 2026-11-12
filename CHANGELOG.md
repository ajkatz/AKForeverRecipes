# Changelog

## Unreleased

- **Your guild's recipes.** Everyone in your guild who has AKForeverRecipes shares what their characters know
  - all of them, alts too. A card says who in the guild can make it (their names, or how many when more
  than three), a recipe you are missing that the guild knows is tagged **Guild**, and an opened card lists
  everyone with their skill and whether they are online or when they were last seen. What a guildmate shared
  is remembered while they are offline; somebody who leaves the guild is dropped. `/akr guild` lists who
  shares; `/akr share off` stops sharing and showing.

## 0.1.0 - 2026-11-10

The first release.

- Every recipe of nine professions - Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking,
  Tailoring, Cooking, First Aid, Mining: about 2,170 - with the skill it needs and where it comes from:
  trainer, vendors with zone and price, quests, drops, world drops.
- One card per recipe, like an achievement: icon, name, what it is, the first source, the skill. Tags say
  the kind of source and whether the recipe item is BoP or BoE.
- A click opens a card: the made item's stats a line each, the reagents with how many you have, every
  source. Hovering a card shows the made item's tooltip.
- The first card of every profession is its training: where the next rank is learned for your faction, and
  the specializations of Blacksmithing, Engineering and Leatherworking.
- A tab for every profession, the ones you do not have included.
- Which recipes you have, asked of the client at login and whenever a trade skill window opens; a recipe
  learned while you play is heard at once.
- Every character's recipes are kept account-wide: the window walks through your characters and an opened
  card says who else has the recipe or still misses it.
- Missing / All / Known / Hidden lists; a search over names, places, NPCs, quests, reagents and tags.
- A right-click hides a recipe from a character's lists and counts.
- Recipes only the other faction can get are left out.
- A merchant seen selling a recipe is written down - the way recipes without a known source get one.
- `/akr` (window), `/akr find`, `/akr diag`.

Known gaps: about 220 of Forever's new recipes have no known source yet; the skill a rank asks for and the
specialization quests are Classic's and not confirmed for Forever; Mining's Expert and Artisan trainers are
a guess.
