# NOT SAVED — Player Profiles & Cloud Saves

This adds real email/password accounts and per-player cloud saves using Supabase Auth + Postgres. Each player's profile and save are protected by Row Level Security and can only be read or changed by that signed-in player.

## Enable cloud accounts

1. Create a Supabase project at https://supabase.com.
2. Run all of `supabase-schema.sql` in the Supabase SQL Editor.
3. Put the project's Project URL and anon/public key into `config.js`.
4. In Supabase Authentication settings, enable Email/Password and configure the allowed site URL / redirect URL for your deployed game.
5. Publish the existing site. Never put the Supabase service_role key in browser code.

Until those steps are completed, the existing start screen remains intact and account creation will display a clear setup message rather than pretending an account was created.

## Game save API

After successful login, the page exposes `window.NOT_SAVED_SAVE`:

```js
// Read current player's save
const save = window.NOT_SAVED_SAVE.get();

// Update and immediately cloud-save game state
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

// Force a save at a checkpoint / reward / purchase boundary
await window.NOT_SAVED_SAVE.saveNow();
```

Call save methods after purchases, rewards, battles, card/team changes, mission completion, kingdom unlocks, and checkpoint transitions. Saves are debounced for rapid updates; call `saveNow()` when an action must be committed immediately.

## Included

- Signup, login, logout and session restoration
- Player name, level, rank and unique auth player ID
- Cloud game-save JSON containing characters, cards, inventory, currency, kingdoms, missions, world state and settings
- Restore player data when returning on another device
- Per-player database access enforced by RLS
