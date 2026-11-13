-- NOT SAVED secure player profiles, progression and per-player cloud saves.
-- Run this complete script in the Supabase SQL Editor.

create table if not exists public.player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'Adventurer',
  level integer not null default 1 check (level between 1 and 100),
  rank text not null default 'Unranked',
  xp integer not null default 0 check (xp >= 0),
  total_xp bigint not null default 0 check (total_xp >= 0),
  rank_points integer not null default 0 check (rank_points >= 0),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.player_profiles
  add column if not exists xp integer not null default 0,
  add column if not exists total_xp bigint not null default 0,
  add column if not exists rank_points integer not null default 0;

alter table public.player_profiles
  drop constraint if exists player_profiles_level_check;
alter table public.player_profiles
  add constraint player_profiles_level_check check (level between 1 and 100);

create table if not exists public.player_game_saves (
  player_id uuid primary key references auth.users(id) on delete cascade,
  save_data jsonb not null default '{"version":1,"characters":[],"cards":[],"inventory":[],"unlockedKingdoms":[],"completedMissions":[],"currency":{"gold":0,"gems":0},"world":{},"settings":{}}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.player_profiles enable row level security;
alter table public.player_game_saves enable row level security;

-- A player can read their profile, but cannot insert, update, or delete it.
drop policy if exists "read own profile" on public.player_profiles;
create policy "read own profile" on public.player_profiles
  for select to authenticated using (auth.uid() = id);
drop policy if exists "insert own profile" on public.player_profiles;
drop policy if exists "update own profile" on public.player_profiles;

revoke all on public.player_profiles from anon, authenticated;
grant select on public.player_profiles to authenticated;

-- Cloud saves remain private to their owner.
drop policy if exists "read own save" on public.player_game_saves;
create policy "read own save" on public.player_game_saves
  for select to authenticated using (auth.uid() = player_id);
drop policy if exists "insert own save" on public.player_game_saves;
create policy "insert own save" on public.player_game_saves
  for insert to authenticated with check (auth.uid() = player_id);
drop policy if exists "update own save" on public.player_game_saves;
create policy "update own save" on public.player_game_saves
  for update to authenticated using (auth.uid() = player_id) with check (auth.uid() = player_id);
grant select, insert, update on public.player_game_saves to authenticated;

-- Player names are permanent. Only the trusted service role may update progression fields.
create or replace function public.ns_protect_player_profile()
returns trigger
language plpgsql
as $$
begin
  if new.username is distinct from old.username then
    raise exception 'Player names are permanent and cannot be changed.';
  end if;
  if auth.role() is distinct from 'service_role'
     and (new.level is distinct from old.level
       or new.rank is distinct from old.rank
       or new.xp is distinct from old.xp
       or new.total_xp is distinct from old.total_xp
       or new.rank_points is distinct from old.rank_points) then
    raise exception 'Level, XP and rank are controlled by trusted game services.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists ns_profile_protection on public.player_profiles;
create trigger ns_profile_protection
before update on public.player_profiles
for each row execute function public.ns_protect_player_profile();

-- Create a profile automatically from the signup metadata; the username is set once.
create or replace function public.ns_create_player_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_name text;
begin
  chosen_name := nullif(btrim(coalesce(new.raw_user_meta_data->>'username','')), '');
  if chosen_name is null then chosen_name := split_part(coalesce(new.email,'adventurer@example.invalid'),'@',1); end if;
  chosen_name := left(chosen_name,24);
  if length(chosen_name) < 2 then chosen_name := 'Adventurer'; end if;
  insert into public.player_profiles(id, username, level, rank, xp, total_xp, rank_points)
  values(new.id, chosen_name, 1, 'Unranked', 0, 0, 0)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists ns_auth_user_profile on auth.users;
create trigger ns_auth_user_profile
after insert on auth.users
for each row execute function public.ns_create_player_profile();

-- Backfill accounts created before this trigger was installed.
insert into public.player_profiles(id, username, level, rank, xp, total_xp, rank_points)
select u.id,
       left(coalesce(nullif(btrim(u.raw_user_meta_data->>'username'),''), split_part(coalesce(u.email,'adventurer@example.invalid'),'@',1)),24),
       1, 'Unranked', 0, 0, 0
from auth.users u
on conflict (id) do nothing;

-- Only trusted backend code using the service-role credential can award XP or rank points.
-- Never expose the service-role key in index.html, config.js, or any browser bundle.
create or replace function public.ns_award_progression(
  p_player_id uuid,
  p_xp integer default 0,
  p_rank_points_delta integer default 0
)
returns public.player_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_row public.player_profiles;
  remaining_xp integer;
  needed_xp integer;
  next_level integer;
  points integer;
  next_rank text;
  tier integer;
  division integer;
  tier_names text[] := array['Bronze','Silver','Gold','Platinum','Diamond','Master','Grandmaster','Mythical'];
  divisions text[] := array['III','II','I'];
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Only trusted game services can award progression.';
  end if;
  if p_xp < 0 or p_xp > 5000 or abs(p_rank_points_delta) > 500 then
    raise exception 'Progression reward is outside the allowed range.';
  end if;

  select * into profile_row
  from public.player_profiles
  where id = p_player_id
  for update;

  if not found then raise exception 'Player profile not found.'; end if;

  remaining_xp := profile_row.xp + coalesce(p_xp,0);
  next_level := profile_row.level;
  while next_level < 100 loop
    needed_xp := 100 + (next_level - 1) * 25;
    exit when remaining_xp < needed_xp;
    remaining_xp := remaining_xp - needed_xp;
    next_level := next_level + 1;
  end loop;
  if next_level = 100 then remaining_xp := 0; end if;

  points := greatest(0, profile_row.rank_points + coalesce(p_rank_points_delta,0));
  if points < 100 then
    next_rank := 'Unranked';
  elsif points >= 2200 then
    next_rank := 'Mythical';
  elsif points >= 1900 then
    next_rank := 'Grandmaster';
  else
    tier := least(5, greatest(0, floor((points - 100)::numeric / 300)::integer));
    division := least(2, greatest(0, floor(((points - 100) % 300)::numeric / 100)::integer));
    next_rank := tier_names[tier + 1] || ' ' || divisions[division + 1];
  end if;

  update public.player_profiles
  set level = next_level,
      xp = remaining_xp,
      total_xp = total_xp + coalesce(p_xp,0),
      rank_points = points,
      rank = next_rank,
      updated_at = now()
  where id = p_player_id
  returning * into profile_row;

  return profile_row;
end;
$$;

revoke all on function public.ns_award_progression(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.ns_award_progression(uuid, integer, integer) to service_role;
