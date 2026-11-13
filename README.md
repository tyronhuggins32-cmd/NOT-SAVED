# NOT SAVED — Accounts, Cloud Saves & Protected Progression

This repository contains the NOT SAVED account screen, fantasy world hub and Supabase cloud-save integration.

## Enable accounts and protected profiles

1. Open the Supabase project connected in `config.js`.
2. Open **SQL Editor** and run the complete `supabase-schema.sql` script. Re-run it after pulling schema changes; it is written to be safe to apply to the existing tables.
3. In Supabase Authentication, enable Email/Password and set the deployed site's allowed redirect URLs.
4. Publish the site.

The public project URL and publishable/anon key belong in `config.js`. **Never put the Supabase service-role key in browser code.**

## Identity and progression protections

- A player's profile is created automatically from signup metadata by a database trigger.
- The chosen player name is permanent. Database protection rejects attempts to change it.
- Level, XP, rank and rank points are read-only to signed-in browser clients. The profile UI no longer exposes editable fields or a save-profile action.
- Row Level Security allows players to read only their own profile.
- The database function `public.ns_award_progression(player_id, xp, rank_points_delta)` is executable only by the Supabase service role. It calculates level-ups and rank divisions on the database side.
- Rank points determine Unranked, Bronze, Silver, Gold, Platinum, Diamond, Master, Grandmaster and Mythical divisions.
- A trusted game backend must validate a completed quest, battle or ranked match before it calls the progression function. Do not call it from a browser and do not expose the service-role key. The current static client deliberately does not award itself XP or rank points.

The rank function accepts up to 5,000 XP and a rank-point adjustment between -500 and +500 per trusted award. Level 100 is the cap. XP required for each level is `100 + (current_level - 1) * 25`.

## Kingdom map progression

The world hub contains five clickable kingdom environments with level gates:

| Kingdom | Required level |
|---|---:|
| Emerald Kingdom | 1 |
| Frozen Kingdom | 16 |
| Golden Kingdom | 31 |
| Volcanic Kingdom | 51 |
| Mystic Islands | 76 |

The map reads the authenticated profile level. Locked kingdoms show their required level and cannot be entered early.

## Cloud game saves

After successful login, the page exposes `window.NOT_SAVED_SAVE`:

```js
const save = window.NOT_SAVED_SAVE.get();

await window.NOT_SAVED_SAVE.update({
  characters: ownedCharacterIds,
  cards: ownedCardIds,
  inventory: inventoryItems,
  unlockedKingdoms: kingdomIds,
  completedMissions: missionIds,
  currency: { gold: 250, gems: 10 },
  world: { currentKingdom: 'emerald', checkpoint: 'castle-gate' },
  settings: playerSettings
});

await window.NOT_SAVED_SAVE.saveNow();
```

Call save methods after purchases, rewards, battles, card/team changes, mission completion, kingdom unlocks and checkpoint transitions. Saves are debounced for rapid updates; call `saveNow()` when an action must be committed immediately.

## Important deployment note

The repository changes are committed, but the updated SQL must still be run in the connected Supabase project's SQL Editor before the new profile protections take effect. The trusted game backend that validates gameplay events and invokes `ns_award_progression` is a separate server-side integration; the browser cannot securely award progression by itself.
