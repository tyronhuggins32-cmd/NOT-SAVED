-- NOT SAVED player profile + cloud save schema. Run in Supabase SQL Editor.
create table if not exists public.player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'Adventurer',
  level integer not null default 1 check (level between 1 and 9999),
  rank text not null default 'Unranked',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.player_game_saves (
  player_id uuid primary key references auth.users(id) on delete cascade,
  save_data jsonb not null default '{"version":1,"characters":[],"cards":[],"inventory":[],"unlockedKingdoms":[],"completedMissions":[],"currency":{"gold":0,"gems":0},"world":{},"settings":{}}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.player_profiles enable row level security;
alter table public.player_game_saves enable row level security;
drop policy if exists "read own profile" on public.player_profiles;
create policy "read own profile" on public.player_profiles for select using (auth.uid() = id);
drop policy if exists "insert own profile" on public.player_profiles;
create policy "insert own profile" on public.player_profiles for insert with check (auth.uid() = id);
drop policy if exists "update own profile" on public.player_profiles;
create policy "update own profile" on public.player_profiles for update using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "read own save" on public.player_game_saves;
create policy "read own save" on public.player_game_saves for select using (auth.uid() = player_id);
drop policy if exists "insert own save" on public.player_game_saves;
create policy "insert own save" on public.player_game_saves for insert with check (auth.uid() = player_id);
drop policy if exists "update own save" on public.player_game_saves;
create policy "update own save" on public.player_game_saves for update using (auth.uid() = player_id) with check (auth.uid() = player_id);
