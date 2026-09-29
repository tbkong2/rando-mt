-- Caption It: final rules (3 to 8 players). Replaces the game model from
-- 001-003; nothing from the old tables is kept.
--
--   lobby    host starts once 3-8 players have joined
--   upload   every player submits one photo
--   caption  the photo at seat n is captioned by seats n+1 and n+2 (wrapping)
--   vote     photos are shown one at a time in shuffled order, everyone votes
--   results  final ranking; equal totals share a place
--
-- Scoring per photo: 100 per vote. An outright winner's votes count double;
-- in a tie each caption gets 100 per vote.
--
-- Clients never read or write the game tables directly. Every action goes
-- through the functions in section 4, which check who is calling and what
-- round it is. RLS is on everywhere; the only policy lets members read their
-- own room row, which is what Realtime needs to tell phones something changed.

-- ---------------------------------------------------------------------------
-- 1. Remove the old model
-- ---------------------------------------------------------------------------

drop table if exists
  public.votes, public.pairings, public.round3_offers,
  public.captions, public.photos, public.players, public.rooms
  cascade;

drop function if exists
  public.award_vote_points(),
  public.enforce_photo_limit(),
  public.round_rank(text),
  public.is_room_member(uuid),
  public.my_player_id(uuid),
  public.is_room_host(uuid),
  public.room_has_players(uuid),
  public.round_is(uuid, text),
  public.round_at_least(uuid, text),
  public.pairing_owner(uuid);

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  round text not null default 'lobby'
    check (round in ('lobby', 'upload', 'caption', 'vote', 'results')),
  -- during 'vote': which photo (by vote_order) is on screen, and whether
  -- people are still voting on it or its result is being shown
  matchup int,
  phase text check (phase in ('voting', 'reveal')),
  -- bumped on every change so Realtime notifies every phone in the room
  version int not null default 0,
  created_at timestamptz not null default now()
);

create table public.players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  auth_user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 16),
  is_host boolean not null default false,
  -- 0..N-1, shuffled when the game starts; drives the caption rotation
  seat int,
  score int not null default 0,
  joined_at timestamptz not null default now(),
  unique (room_id, auth_user_id),
  unique (room_id, seat)
);

create table public.photos (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  player_id uuid not null unique references public.players (id) on delete cascade,
  storage_path text not null,
  -- position in the shuffled voting order, set when voting starts
  vote_order int,
  created_at timestamptz not null default now(),
  unique (room_id, vote_order)
);

create table public.captions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  photo_id uuid not null references public.photos (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  text text not null check (char_length(text) between 1 and 80),
  -- filled in when the photo's votes are revealed
  votes int not null default 0,
  points int not null default 0,
  created_at timestamptz not null default now(),
  unique (photo_id, player_id)
);

create table public.votes (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  photo_id uuid not null references public.photos (id) on delete cascade,
  caption_id uuid not null references public.captions (id) on delete cascade,
  voter_id uuid not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (photo_id, voter_id)
);

-- ---------------------------------------------------------------------------
-- 3. Internal helpers
-- The private schema is not exposed through the Supabase API, so none of
-- these can be called from a phone. Only is_member and can_upload are granted
-- to signed-in users, because RLS/storage policies run as the caller.
-- ---------------------------------------------------------------------------

create schema if not exists private;

-- Locks the room row until the transaction ends, so two phones acting at the
-- same moment (e.g. the last two votes) are handled one after the other.
create function private.lock_room(p_room uuid) returns public.rooms
language plpgsql set search_path = '' as $$
declare
  r public.rooms;
begin
  select * into r from public.rooms where id = p_room for update;
  if not found then
    raise exception 'Room not found';
  end if;
  return r;
end;
$$;

create function private.me(p_room uuid) returns public.players
language plpgsql stable set search_path = '' as $$
declare
  p public.players;
begin
  select * into p from public.players
  where room_id = p_room and auth_user_id = auth.uid();
  if not found then
    raise exception 'You are not in this room';
  end if;
  return p;
end;
$$;

create function private.clean_name(p_name text) returns text
language plpgsql immutable set search_path = '' as $$
declare
  n text := btrim(coalesce(p_name, ''));
begin
  if char_length(n) not between 1 and 16 then
    raise exception 'Names must be 1 to 16 characters';
  end if;
  return n;
end;
$$;

create function private.player_count(p_room uuid) returns int
language sql stable set search_path = '' as $$
  select count(*)::int from public.players where room_id = p_room
$$;

create function private.bump(p_room uuid) returns void
language sql set search_path = '' as $$
  update public.rooms set version = version + 1 where id = p_room
$$;

-- The rotation: the photo owned by seat s is captioned by seats s+1 and s+2.
create function private.is_captioner(p_photo uuid, p_player uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1
    from public.photos ph
    join public.players owner on owner.id = ph.player_id
    join public.players p on p.id = p_player and p.room_id = ph.room_id
    where ph.id = p_photo
      and p.seat in (
        (owner.seat + 1) % private.player_count(ph.room_id),
        (owner.seat + 2) % private.player_count(ph.room_id)
      )
  )
$$;

-- Tallies one photo's votes and pays out points.
create function private.reveal_matchup(p_photo uuid) returns void
language plpgsql set search_path = '' as $$
begin
  update public.captions c
  set votes = (select count(*) from public.votes v where v.caption_id = c.id)
  where c.photo_id = p_photo;

  with t as (
    select id, votes,
           max(votes) over () as top,
           min(votes) over () as bottom
    from public.captions
    where photo_id = p_photo
  )
  update public.captions c
  set points = case
    when t.top = t.bottom then t.votes * 100  -- tie
    when t.votes = t.top then t.votes * 200   -- winner: votes count double
    else t.votes * 100                        -- loser
  end
  from t
  where c.id = t.id;

  update public.players p
  set score = p.score + c.points
  from public.captions c
  where c.photo_id = p_photo and c.player_id = p.id;
end;
$$;

-- Used by RLS and storage policies (they run as the signed-in user).
create function private.is_member(p_room uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.players
    where room_id = p_room and auth_user_id = auth.uid()
  )
$$;

create function private.can_upload(p_room uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_member(p_room)
     and exists (select 1 from public.rooms where id = p_room and round = 'upload')
$$;

-- Storage paths are "<room id>/<file>"; returns null for anything else.
create function private.storage_room(p_name text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  return split_part(p_name, '/', 1)::uuid;
exception when others then
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Game actions (called from the app with supabase.rpc)
-- security definer lets them write to tables the caller can't touch
-- directly; each one checks the caller and the round itself.
-- ---------------------------------------------------------------------------

create function public.create_room(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_room uuid;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  insert into public.rooms default values returning id into v_room;
  insert into public.players (room_id, auth_user_id, name, is_host)
  values (v_room, auth.uid(), private.clean_name(p_name), true);
  return v_room;
end;
$$;

-- Joining again from the same phone returns the existing seat.
create function public.join_room(p_room uuid, p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  v_player uuid;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  r := private.lock_room(p_room);

  select id into v_player from public.players
  where room_id = p_room and auth_user_id = auth.uid();
  if v_player is not null then
    return v_player;
  end if;

  if r.round <> 'lobby' then
    raise exception 'This game has already started';
  end if;
  if private.player_count(p_room) >= 8 then
    raise exception 'This room is full (8 players max)';
  end if;

  insert into public.players (room_id, auth_user_id, name)
  values (p_room, auth.uid(), private.clean_name(p_name))
  returning id into v_player;

  perform private.bump(p_room);
  return v_player;
end;
$$;

-- Only before the game starts. If the host leaves, the next-oldest player
-- becomes host.
create function public.leave_room(p_room uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  me public.players;
begin
  r := private.lock_room(p_room);
  me := private.me(p_room);
  if r.round <> 'lobby' then
    raise exception 'You can only leave before the game starts';
  end if;

  delete from public.players where id = me.id;
  if me.is_host then
    update public.players set is_host = true
    where id = (
      select id from public.players
      where room_id = p_room
      order by joined_at
      limit 1
    );
  end if;

  perform private.bump(p_room);
end;
$$;

create function public.start_game(p_room uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  me public.players;
  n int;
begin
  r := private.lock_room(p_room);
  me := private.me(p_room);
  if not me.is_host then
    raise exception 'Only the host can start the game';
  end if;
  if r.round <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  n := private.player_count(p_room);
  if n < 3 then
    raise exception 'Caption It needs at least 3 players';
  end if;

  -- shuffled seats, so who captions whose photo changes every game
  update public.players p
  set seat = s.seat
  from (
    select id, (row_number() over (order by random()) - 1)::int as seat
    from public.players
    where room_id = p_room
  ) s
  where p.id = s.id;

  update public.rooms set round = 'upload' where id = p_room;
  perform private.bump(p_room);
end;
$$;

-- p_path must already be uploaded to the "photos" bucket by this user.
-- The round moves on by itself once everyone has submitted.
create function public.submit_photo(p_room uuid, p_path text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  me public.players;
begin
  r := private.lock_room(p_room);
  me := private.me(p_room);
  if r.round <> 'upload' then
    raise exception 'Photos can only be submitted in the upload round';
  end if;
  if exists (select 1 from public.photos where player_id = me.id) then
    raise exception 'You already submitted a photo';
  end if;
  if private.storage_room(p_path) is distinct from p_room
     or not exists (
       select 1 from storage.objects
       where bucket_id = 'photos' and name = p_path and owner_id = auth.uid()::text
     ) then
    raise exception 'Upload the photo before submitting it';
  end if;

  insert into public.photos (room_id, player_id, storage_path)
  values (p_room, me.id, p_path);

  if (select count(*) from public.photos where room_id = p_room)
     = private.player_count(p_room) then
    update public.rooms set round = 'caption' where id = p_room;
  end if;

  perform private.bump(p_room);
end;
$$;

-- Once all 2N captions are in, voting starts with the photos in random order.
create function public.submit_caption(p_photo uuid, p_text text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_room uuid;
  r public.rooms;
  me public.players;
  v_text text := btrim(coalesce(p_text, ''));
begin
  select room_id into v_room from public.photos where id = p_photo;
  if v_room is null then
    raise exception 'Photo not found';
  end if;
  r := private.lock_room(v_room);
  me := private.me(v_room);

  if r.round <> 'caption' then
    raise exception 'Captions can only be written in the caption round';
  end if;
  if not private.is_captioner(p_photo, me.id) then
    raise exception 'That photo is not assigned to you';
  end if;
  if exists (select 1 from public.captions where photo_id = p_photo and player_id = me.id) then
    raise exception 'You already captioned this photo';
  end if;
  if char_length(v_text) not between 1 and 80 then
    raise exception 'Captions must be 1 to 80 characters';
  end if;

  insert into public.captions (room_id, photo_id, player_id, text)
  values (v_room, p_photo, me.id, v_text);

  if (select count(*) from public.captions where room_id = v_room)
     = 2 * private.player_count(v_room) then
    update public.photos ph
    set vote_order = s.o
    from (
      select id, (row_number() over (order by random()) - 1)::int as o
      from public.photos
      where room_id = v_room
    ) s
    where ph.id = s.id;

    update public.rooms
    set round = 'vote', matchup = 0, phase = 'voting'
    where id = v_room;
  end if;

  perform private.bump(v_room);
end;
$$;

-- Anyone can vote, including the photo owner and the two writers (for their
-- own caption too). The result is revealed once every player has voted.
create function public.cast_vote(p_caption uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_room uuid;
  v_photo uuid;
  r public.rooms;
  me public.players;
begin
  select room_id, photo_id into v_room, v_photo
  from public.captions where id = p_caption;
  if v_room is null then
    raise exception 'Caption not found';
  end if;
  r := private.lock_room(v_room);
  me := private.me(v_room);

  if r.round <> 'vote' or r.phase <> 'voting' then
    raise exception 'Voting is closed';
  end if;
  if (select vote_order from public.photos where id = v_photo) <> r.matchup then
    raise exception 'That caption is not in the current matchup';
  end if;
  if exists (select 1 from public.votes where photo_id = v_photo and voter_id = me.id) then
    raise exception 'You already voted';
  end if;

  insert into public.votes (room_id, photo_id, caption_id, voter_id)
  values (v_room, v_photo, p_caption, me.id);

  if (select count(*) from public.votes where photo_id = v_photo)
     = private.player_count(v_room) then
    perform private.reveal_matchup(v_photo);
    update public.rooms set phase = 'reveal' where id = v_room;
  end if;

  perform private.bump(v_room);
end;
$$;

-- Host moves from a revealed result to the next photo, or to the results.
create function public.next_matchup(p_room uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  me public.players;
begin
  r := private.lock_room(p_room);
  me := private.me(p_room);
  if not me.is_host then
    raise exception 'Only the host can move on';
  end if;
  if r.round <> 'vote' or r.phase <> 'reveal' then
    raise exception 'Wait until everyone has voted';
  end if;

  if r.matchup + 1 < (select count(*) from public.photos where room_id = p_room) then
    update public.rooms
    set matchup = r.matchup + 1, phase = 'voting'
    where id = p_room;
  else
    update public.rooms
    set round = 'results', matchup = null, phase = null
    where id = p_room;
  end if;

  perform private.bump(p_room);
end;
$$;

-- Everything the calling player is allowed to see, in one call. Captions stay
-- anonymous (no author, votes or points) until their photo is revealed, and a
-- captioner never sees the other caption on their photo before voting.
create function public.get_game_state(p_room uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  r public.rooms;
  me public.players;
  v_photo public.photos;
  v_players jsonb;
  v_assignments jsonb;
  v_matchup jsonb;
  v_results jsonb;
begin
  select * into r from public.rooms where id = p_room;
  if not found then
    raise exception 'Room not found';
  end if;
  me := private.me(p_room);

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'is_host', p.is_host,
      'score', p.score,
      'is_me', p.id = me.id,
      -- whether this player has finished the current round's task
      'done', case r.round
        when 'upload' then exists (
          select 1 from public.photos where player_id = p.id)
        when 'caption' then (
          select count(*) from public.captions where player_id = p.id) = 2
        when 'vote' then exists (
          select 1 from public.votes v
          join public.photos ph on ph.id = v.photo_id
          where v.voter_id = p.id and ph.room_id = p_room and ph.vote_order = r.matchup)
      end
    ) order by p.joined_at), '[]'::jsonb)
  into v_players
  from public.players p
  where p.room_id = p_room;

  if r.round = 'caption' then
    select coalesce(jsonb_agg(jsonb_build_object(
        'photo_id', ph.id,
        'path', ph.storage_path,
        'my_caption', (
          select c.text from public.captions c
          where c.photo_id = ph.id and c.player_id = me.id)
      ) order by ph.id), '[]'::jsonb)
    into v_assignments
    from public.photos ph
    where ph.room_id = p_room and private.is_captioner(ph.id, me.id);
  end if;

  if r.round = 'vote' then
    select * into v_photo from public.photos
    where room_id = p_room and vote_order = r.matchup;

    v_matchup := jsonb_build_object(
      'photo_id', v_photo.id,
      'path', v_photo.storage_path,
      'number', r.matchup + 1,
      'total', (select count(*) from public.photos where room_id = p_room),
      'phase', r.phase,
      'owner', case when r.phase = 'reveal' then (
        select name from public.players where id = v_photo.player_id) end,
      'my_vote', (
        select caption_id from public.votes
        where photo_id = v_photo.id and voter_id = me.id),
      'votes_in', (
        select count(*) from public.votes where photo_id = v_photo.id),
      'captions', (
        select jsonb_agg(jsonb_build_object(
            'id', c.id,
            'text', c.text,
            'is_mine', c.player_id = me.id,
            'author', case when r.phase = 'reveal' then p.name end,
            'votes', case when r.phase = 'reveal' then c.votes end,
            'points', case when r.phase = 'reveal' then c.points end
          ) order by c.id)
        from public.captions c
        join public.players p on p.id = c.player_id
        where c.photo_id = v_photo.id)
    );
  end if;

  if r.round = 'results' then
    select jsonb_agg(jsonb_build_object(
        'id', id,
        'name', name,
        'score', score,
        'place', place,
        'is_me', id = me.id
      ) order by place, name)
    into v_results
    from (
      select id, name, score, rank() over (order by score desc)::int as place
      from public.players
      where room_id = p_room
    ) ranked;
  end if;

  return jsonb_build_object(
    'room', jsonb_build_object('id', r.id, 'round', r.round, 'version', r.version),
    'me', jsonb_build_object('id', me.id, 'is_host', me.is_host),
    'players', v_players,
    'my_photo', (select storage_path from public.photos where player_id = me.id),
    'assignments', v_assignments,
    'matchup', v_matchup,
    'results', v_results
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Permissions
-- ---------------------------------------------------------------------------

revoke all on schema private from public;
grant usage on schema private to authenticated;
revoke execute on all functions in schema private from public;
grant execute on function private.is_member(uuid) to authenticated;
grant execute on function private.can_upload(uuid) to authenticated;
grant execute on function private.storage_room(text) to authenticated;

-- signed-in players only (anonymous sign-ins count as signed in)
revoke execute on function
  public.create_room(text),
  public.join_room(uuid, text),
  public.leave_room(uuid),
  public.start_game(uuid),
  public.submit_photo(uuid, text),
  public.submit_caption(uuid, text),
  public.cast_vote(uuid),
  public.next_matchup(uuid),
  public.get_game_state(uuid)
from public, anon;
grant execute on function
  public.create_room(text),
  public.join_room(uuid, text),
  public.leave_room(uuid),
  public.start_game(uuid),
  public.submit_photo(uuid, text),
  public.submit_caption(uuid, text),
  public.cast_vote(uuid),
  public.next_matchup(uuid),
  public.get_game_state(uuid)
to authenticated;

alter table public.rooms    enable row level security;
alter table public.players  enable row level security;
alter table public.photos   enable row level security;
alter table public.captions enable row level security;
alter table public.votes    enable row level security;

create policy rooms_member_read on public.rooms
  for select to authenticated
  using (private.is_member(id));

-- ---------------------------------------------------------------------------
-- 6. Photo storage: private bucket, one folder per room
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'photos', 'photos', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do nothing;

create policy caption_it_photos_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and private.can_upload(private.storage_room(name)));

create policy caption_it_photos_read on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and private.is_member(private.storage_room(name)));

-- ---------------------------------------------------------------------------
-- 7. Realtime: phones subscribe to their room row
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table public.rooms;
