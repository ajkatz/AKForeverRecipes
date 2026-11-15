# Changelog

## 0.4.0 - 2026-11-15

- **What the trainer asks.** A recipe a trainer teaches shows its price - on the card's line ("Any
  Blacksmithing trainer, 50c") and opened ("Any Blacksmithing trainer teaches it. | 50c"). The prices are
  Wowhead's WoW Forever ones (425 of the 430 trainer recipes); whenever any of your characters opens a
  profession trainer, the price it asks replaces them for the whole account, marked "seen at a trainer".
- **What the next rank costs.** The training card shows the trainer's price for Apprentice, Journeyman, Expert
  and Artisan - on the card ("Trainer: Yelmak, Orgrimmar, 5s") and on every trainer's line when opened.
  A rank that comes from a book or a quest has no trainer's price.
- **Specializations.** Leatherworking's (Dragonscale, Elemental, Tribal) and Blacksmithing's (Armorsmith,
  Weaponsmith, and the Master Swordsmith, Hammersmith and Axesmith) recipes are marked like Engineering's
  were: a tag on the card, "Needs the Dragonscale Leatherworking specialization." in the opened card, the
  recipe item's tooltip, and the search ("tribal", "armorsmith"). A specialization's trainer recipe no longer
  says any trainer teaches it: "Dragonscale Leatherworking trainers, 90s". 126 recipes, from Wowhead's lists.
- **Fixed: Red Whelp Gloves was missing from a Horde character's Leatherworking.** Its only written-down
  source was the Alliance's vendor, so the Horde never saw it - but creatures drop the pattern too. Four
  recipes got the drop Wowhead's item page has: Red Whelp Gloves (Dragonmaw Scout, Wetlands), Herbalist's
  Gloves (Shadethicket Raincaller, Ashenvale), Raptor Hide Belt (Daggerspine Shorestalker, Hillsbrad
  Foothills) and, for the Alliance, Enchant Chest - Lesser Intellect (Wrathtail Sea Witch, Ashenvale).
- **The other faction's recipes that can be traded.** A recipe only the other faction's vendors sell or
  quests reward used to be left out. When its recipe item does not bind it is now in the list, under that
  faction's name: "Alliance vendor: Kendor Kabonka, Stormwind City, 2s", a tag **Alliance** or **Horde**, and
  the search word `alliance` / `horde`. 23 recipes for the Horde (14 of them Cooking's) and 12 for the
  Alliance - they count as missing. Recipes that bind when picked up, and a faction's own, stay left out.
- **The recipes read again (2026-11-15).** The game changed since the tables were read on 2026-11-10:
  Green and Black Silk Pack are 12 slots, Green and Red Woolen Bag 10, Red Mageweave Bag 14 - each for one
  more bolt of cloth. 232 recipes have their current creatures and drop chances, a few their current skill
  numbers, Draught of Water Walking its recipe item. And 92 recipes that had no known source have one now:
  about 130 are left without.
- **Links.** A Shift-click on a card puts a link to what it makes into chat (an enchant: its spell), a
  Shift-right-click the recipe item that teaches it - into the chat line you have open, or a new one.

## 0.3.1 - 2026-11-13

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
