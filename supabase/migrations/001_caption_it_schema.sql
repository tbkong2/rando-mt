-- Caption It: core tables (step 1 of the schema plan).
-- No RLS policies yet — that's step 4. Tables are created without them for
-- now, so nothing is actually reachable through the anon API key until
-- policies are added (Supabase does not lock a table down just because it
-- has foreign keys; RLS has to be turned on explicitly, later).

create table rooms (
  id uuid primary key default gen_random_uuid(),
  current_round text not null default 'lobby',
  created_at timestamptz not null default now()
);

create table players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms (id) on delete cascade,
  auth_user_id uuid not null references auth.users (id),
  display_name text not null,
  is_host boolean not null default false,
  score integer not null default 0,
  joined_at timestamptz not null default now()
);

create table photos (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms (id) on delete cascade,
  player_id uuid not null references players (id) on delete cascade,
  storage_path text not null,
  created_at timestamptz not null default now()
);

create table captions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms (id) on delete cascade,
  player_id uuid not null references players (id) on delete cascade,
  photo_id uuid not null references photos (id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);

create table round3_offers (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms (id) on delete cascade,
  player_id uuid not null references players (id) on delete cascade,
  photo_ids uuid[] not null check (array_length(photo_ids, 1) = 3),
  caption_ids uuid[] not null check (array_length(caption_ids, 1) = 4),
  created_at timestamptz not null default now()
);

create table pairings (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms (id) on delete cascade,
  player_id uuid not null references players (id) on delete cascade,
  photo_id uuid not null references photos (id) on delete cascade,
  caption_id uuid not null references captions (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (room_id, player_id) -- one pairing submission per player per room
);

create table votes (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms (id) on delete cascade,
  voter_player_id uuid not null references players (id) on delete cascade,
  pairing_id uuid not null references pairings (id) on delete cascade,
  rank smallint not null check (rank in (1, 2, 3)),
  created_at timestamptz not null default now(),
  unique (room_id, voter_player_id, rank),       -- can't reuse a rank
  unique (room_id, voter_player_id, pairing_id)  -- can't vote the same pairing twice
);
