# Changelog

## Unreleased

- **Recipes that need a reputation say so.** 175 recipe items ask for a standing before they can be bought
  or learned (Timbermaw Hold, Thorium Brotherhood, Argent Dawn, Cenarion Circle, Zandalar Tribe, Hydraxian
  Waterlords, and Forever's Nightclaw Druids, Earthen Ring and Kirin Tor). The card carries the standing as a
  tag and on its source line, and a faction's vendor goes by the faction's name there in place of "Vendor":
  the tags read "Cenarion Circle  Revered", the line "Cenarion Circle: Mishta, Silithus - needs Revered".
  The opened card says "Requires Cenarion Circle - Revered", and the search finds them by `rep`, the
  faction or the standing (and still by `vendor`).
  Read from the game client's own item table.
- **... and hold it against each character's own standing.** The standing with those nine factions is read
  at login and whenever it moves, and kept per character. The tag is green when the character has the
  standing and orange when not; a recipe whose skill is there but whose standing is not loses its gold rim.
  A character that lacks the standing is told how much reputation is still to earn, over every standing
  between: on the card's line ("Cenarion Circle: Mishta, Silithus - 8,800 rep to Revered"), in the
  opened card ("8,800 reputation to go", or "you have not met them yet") and on the recipe item's tooltip,
  which no longer says "can learn it" for such a character: "needs Cenarion Circle Revered (8,800 to go)".
  A character not logged in since reads as before, and its card says so.
- **Cooldowns: transmutes, Mooncloth and the Salt Shaker for all your characters, in a row of their own.**
  Under the profession tabs a row says how many are ready and which is due next ("Cooldowns: 1 ready -
  next Transmute (Purr Gola) 5h"); a click opens them all as cards, a second click goes back. The cards list
  every character's Transmute cooldown (shared by all transmutes), Transmute: Iron to Gold and Mithril to
  Truesilver, Mooncloth and Refined Deeprock Salt (for whoever owns a Salt Shaker): "Ready" or "Ready in
  14h 20m", ready ones first. A cooldown is read on the character that has it and kept as the moment it is
  over, so the others count down without being logged in; a character that has not logged in since reads
  "Not read yet". The lengths are the game client's own (23 hours, 47 for Arcanite and Legionite, 3 days 23
  hours for Mooncloth, 2 days 23 hours for the salt).
- **Transmutes with separate cooldowns are shown separately.** Each transmute is asked for by itself: while
  they answer the same they are one Transmute card, and where the game keeps them apart (Arcanite on
  cooldown, Legionite ready) each gets its own card and its own time.
- **A line at login when a long cooldown is ready** on any of your characters: "Ready: Transmute (Purr
  Gola), Mooncloth (Purr Smith)". `/akr cd notice off` silences it; `/akr cd` prints every cooldown.
- A right-click hides a cooldown of a character you do not use; the Hidden list brings it back.
- **An X in the search box** empties it and lists everything again.
- **Recipes only a Master trainer teaches now say so.** 76 recipes read "Any ... trainer", and a city's
  trainer does not have them. The card now names who does, for your side, and a search for the trainer or
  the zone ("felwood", "master tailor") finds them.
  - Tailoring - Red Mageweave Bag, Simple Black Dress, Black Mageweave Headband, Boots and Shoulders,
    Cindercloth Boots, Dreamweave Circlet, Bolt of Runecloth, Runecloth Belt: Daryl Stack in Hillsbrad
    Foothills (Horde), Timothy Worthington in Dustwallow Marsh (Alliance), Meilosh in Felwood (both).
  - Alchemy - Arcane Elixir, Elixir of Greater Intellect, Elixir of Greater Agility, Dreamless Sleep
    Potion, Stonescale Oil, Draught of Detect Undead, Draught of Detect Demon: Rogvar in Swamp of Sorrows
    (Horde), Kylanna Windwhisper in Feralas (Alliance), Master Mycologist Shurome in Felwood (both).
  - Blacksmithing - Heavy Mithril Breastplate, Mithril Coif, Heavy Mithril Boots, Big Black Mace, Dense
    Grinding Stone, Dense Weightstone, Dense Sharpening Stone, Arcanite Skeleton Key, Arcanite Rod: Brikk
    Keencraft in Booty Bay.
  - Leatherworking - Nightscape Pants, Nightscape Boots, Turtle Scale Helm, Turtle Scale Leggings, Cured
    Rugged Hide, Rugged Armor Kit, Rugged Leather: Hahrana Ironhide in Feralas (Horde), Drakk Stonehand in
    The Hinterlands (Alliance).
  - Engineering - Rose Colored Goggles, Green Lens, Hi-Explosive Bomb, Mithril Gyro-Shot, Salt Shaker,
    Dense Blasting Powder, Dense Dynamite: Buzzek Bracketswing in Tanaris and Kaylaena Springwhisper in
    Mount Hyjal (both sides).
  - Enchanting - ten enchants are Annora's alone (Uldaman): Enchanted Leather, Enchanted Thorium Bar,
    Enchant Gloves - Minor Haste, Weapon - Greater Striking, Chest - Stats, Bracer - Greater Strength, 2H
    Weapon - Greater Impact, Boots - Agility, Chest - Superior Intellect, Shield - Greater Spirit. 24 more,
    from Enchant Shield - Lesser Stamina (skill 155) up, are not a city trainer's either: Hgarth in
    Stonetalon Mountains (Horde), Kitta Firewind in Elwynn Forest (Alliance) and Annora teach them.
  - First Aid - Heavy Mageweave, Runecloth and Heavy Runecloth Bandage: a city's trainer does not have
    them and Wowhead names nobody for Forever; the card names the Triage doctors, as in Classic (Doctor
    Gregory Victor in Arathi Highlands, Doctor Gustaf VanHowzen in Dustwallow Marsh), and says it is not
    confirmed for Forever.
  - Mining and Cooking: a city's trainer teaches everything a trainer teaches.
- **21 new recipes no longer say "Probably any trainer".** A trainer's list was read with each of them in
  it (First Aid Kit, the First Aid healing potions, Lodestone, Azerothium Bar, Heavy Thorium Bar, Mana
  Well, the dyes, Sandpaper, Camp Tent, Enchanted Lute, the Faction Banners and more): "Any ... trainer".
  Still a guess: Alchemy's four Discolored Healing Potions and Cooking's Spinefin Halibut - no trainer
  read teaches them.
- **Meilosh in Felwood teaches Tailoring**, the rank Artisan included: the training card lists him.

## 0.4.1 - 2026-11-16

- **Fixed: a rank you had learned was still shown as the next one.** After Dirge's quest the training card
  went on saying "Artisan Cooking raises your skill cap to 300". The skill and its cap were asked of the
  trade skill window's call alone, and on the current build (1.60.1.70938) that call answered 0/0 for every
  profession at login - so the card kept the cap it had read earlier. They are now read from the
  professions book first, then the skill window's list, then that call: right from login, with no
  profession window opened. `/akr diag` says which of the three each profession was read from.
- **What to bring Dirge.** Artisan Cooking (skill cap 300) is a quest, Clamlette Surprise, from Dirge
  Quikcleave in Tanaris. The training card now lists what he wants under the quest's line - 12 Giant Egg,
  10 Zesty Clam Meat, 20 Alterac Swiss - with how many of each you have ("have 3/12", bags and bank) and
  "you have it all" once you do. The closed card says "(open for what to bring)".
- **What a specialization's quest wants.** The same list under each specialization's quest in the opened
  training card: Gnomish Engineering (6 Mithril Tube, 1 Accurate Scope, 2 Advanced Target Dummy), Goblin
  Engineering (20 Big Iron Bomb, 20 Solid Dynamite, 5 Explosive Sheep), Dragonscale, Elemental and Tribal
  Leatherworking, and Blacksmithing's Armorsmith and Weaponsmith - with how many of each you have. The
  numbers are the quests' own words in Questie and on Wowhead's WoW Forever pages. The card no longer calls
  the specializations "not confirmed for Forever": Wowhead's Forever pages have all seven quests.
- **27 more recipes have a source (read again 2026-11-16): about 100 are left without.** Wowhead's WoW
  Forever lists name one now for 27 of the 130 that had none:
  - the seven Blueprints - Sewing Machine (Vectus), Alchemy Laboratory (Ras Frostwhisper), Plague Doctor's
    Laboratory (Doctor Theolen Krastinov), all Scholomance; Loom (Baroness Anastari) and Anarchist's
    Workbench (Ezra Grimm), Stratholme; Master Forge (Golem Lord Argelmach, Blackrock Depths); Arcane Forge
    (Nanaya, The Shaper's Terrace);
  - Leatherworking: Black Dragonscale Helm, Red Dragonscale Leggings, Pristine Scorpid Leggings, Supple
    Scorpid Sabatons, Charged Scorpid Boots, Timbermaw Tunic, Warbear Helm, Tooled Leather Gauntlets and
    Pants, Nightscape Cloak;
  - Blacksmithing: Stormcarver and Bagh Nakh (sold by Meilosh in Felwood - no price read yet), Martyr's
    Legplates; Tailoring: Bottomless Reagent Bag; Enchanting: Enchant 2H Weapon - Strength, Dormant Heart of
    the Mountain; Cooking: Swiftstrike Steak (Frostsaber Pride Watcher, Winterspring);
  - two quest rewards, by the quest's name only: Distilled Firewater (Running Firewater) and Powerful
    Poultice (Transmuted Tincture).
  The evidence is thin - most are one or two drops seen. A drop chance is shown only where the creature was
  looted 20 times or more; twelve of the 27 had their own page read, the rest have the creature's name and
  zone alone. The cards say "Source found in Wowhead".
- **A recipe that is fished up says so.** Draught of Water Walking's recipe is caught fishing in Mount Hyjal
  (one catch in 123 counted): "Fished in Mount Hyjal, 0.81%".
- ForeverChanges' quest, dungeon and Merchant's Favor pages, the client tables of the current build
  (1.60.1.70938) and Questie were read again on 2026-11-16 too: nothing new in them.

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
