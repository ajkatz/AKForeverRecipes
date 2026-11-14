# Changelog

## Unreleased

- **Who can use a recipe that drops.** A recipe item's tooltip - in the loot window or a roll, your bags, a
  merchant, a chat link - lists your characters on the realm who have the profession: "can learn it
  (Tailoring 120)" in green, "Tailoring 20, needs 25" in orange, "knows it" in grey. Characters without the
  profession, on another realm or of the other faction (for one faction's recipes) are left out.
  `/akr tooltip off` turns it off.

## 0.3.0 - 2026-11-12

- **Your friends' recipes.** Friends who have AKForeverRecipes share theirs with you and you with them - both
  your in-game friends list and Battle.net friends in the game. Mutual only: it goes to people on your friends
  list and is taken only from them. Opened cards list them under **Your friends**, missing recipes a friend
  knows are tagged **Friend**, and the card line adds "Friends: ...". Friends in your guild show under the
  guild. `/akr friends` lists who shares; `/akr share off` covers friends too.
- **Lockpicking.** Rogues get a Lockpicking tab: every lockbox, junkbox, fished chest, footlocker, dungeon chest
  and door, the skill it needs, where it is (and the key that opens a door instead), and whether your rogue can
  open it now or how much more skill it needs. The numbers are Classic's until the game's own tooltip names
  one; a card says which.
- **Skill cap ranks say the level they need** (Journeyman 10, Expert 20, Artisan 35 - Classic's; Forever's are
  not written down): a rank your character is too low for is no longer shown as ready, and the card says
  your level.
- **Fixed: the other faction's Faction Banner showed as missing.** A recipe whose text says it is for one
  faction's members is now that faction's only.

## 0.2.0 - 2026-11-11

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
