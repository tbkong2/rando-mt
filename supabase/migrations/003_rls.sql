-- Caption It: Row Level Security.
-- Requires Authentication -> Providers -> "Anonymous sign-ins" to be enabled,
-- otherwise auth.uid() is null and every policy below denies everything.

-- ---------------------------------------------------------------------------
-- 1. Schema fixes
-- ---------------------------------------------------------------------------

-- lets the phone that creates a room read it back before it has a players row
alter table rooms add column created_by uuid default auth.uid() references auth.users (id);

-- one seat per user per room
alter table players add constraint players_one_seat_per_room unique (room_id, auth_user_id);

-- ---------------------------------------------------------------------------
-- 2. Helper functions
-- security definer skips RLS inside the function, which is what avoids
-- policies on `players` recursing into `players`. search_path is pinned and
-- tables are schema-qualified, as Supabase's security advisor recommends.
-- ---------------------------------------------------------------------------

create function round_rank(r text) returns int
language sql immutable set search_path = '' as $$
  select case r
    when 'lobby' then 0
    when 'round1_submit' then 1
    when 'round2_caption' then 2
    when 'round3_match' then 3
    when 'round4_judge' then 4
    when 'complete' then 5
  end
$$;

create function is_room_member(p_room uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.players
    where room_id = p_room and auth_user_id = auth.uid()
  )
$$;

create function my_player_id(p_room uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.players
  where room_id = p_room and auth_user_id = auth.uid()
$$;

create function is_room_host(p_room uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.players
    where room_id = p_room and auth_user_id = auth.uid() and is_host
  )
$$;

create function room_has_players(p_room uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.players where room_id = p_room)
$$;

create function round_is(p_room uuid, p_round text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select current_round = p_round from public.rooms where id = p_room),
    false
  )
$$;

create function round_at_least(p_room uuid, p_round text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select public.round_rank(current_round) >= public.round_rank(p_round)
     from public.rooms where id = p_room),
    false
  )
$$;

-- used by the no-self-voting rule; pairings are hidden by their own read
-- policy until round 4, so the lookup has to bypass RLS
create function pairing_owner(p_pairing uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select player_id from public.pairings where id = p_pairing
$$;

-- ---------------------------------------------------------------------------
-- 3. Turn RLS on (everything is locked until a policy below allows it)
-- No delete policies exist anywhere: clients can never delete rows.
-- ---------------------------------------------------------------------------

alter table rooms         enable row level security;
alter table players       enable row level security;
alter table photos        enable row level security;
alter table captions      enable row level security;
alter table round3_offers enable row level security;
alter table pairings      enable row level security;
alter table votes         enable row level security;

-- ---------------------------------------------------------------------------
-- 4. Policies
-- ---------------------------------------------------------------------------

-- rooms: members and the creator can read; anyone signed in can create;
-- only the host can change current_round (which also unlocks reveals below)
create policy rooms_read on rooms for select to authenticated
  using (created_by = auth.uid() or is_room_member(id));

create policy rooms_create on rooms for insert to authenticated
  with check (created_by = auth.uid());

create policy rooms_host_update on rooms for update to authenticated
  using (is_room_host(id)) with check (is_room_host(id));

-- players: you can join only as yourself, only in the lobby, starting at 0,
-- and only the first player in a room can be host. No update policy, so
-- scores can only change through the award_vote_points trigger.
create policy players_read on players for select to authenticated
  using (auth_user_id = auth.uid() or is_room_member(room_id));

create policy players_join on players for insert to authenticated
  with check (
    auth_user_id = auth.uid()
    and score = 0
    and round_is(room_id, 'lobby')
    and (not is_host or not room_has_players(room_id))
  );

-- photos: own always; everyone's from round 2 (when captioning starts)
create policy photos_read on photos for select to authenticated
  using (
    is_room_member(room_id)
    and (player_id = my_player_id(room_id) or round_at_least(room_id, 'round2_caption'))
  );

create policy photos_add on photos for insert to authenticated
  with check (player_id = my_player_id(room_id) and round_is(room_id, 'round1_submit'));

-- captions: blind. own always; everyone's from round 3
create policy captions_read on captions for select to authenticated
  using (
    is_room_member(room_id)
    and (player_id = my_player_id(room_id) or round_at_least(room_id, 'round3_match'))
  );

create policy captions_add on captions for insert to authenticated
  with check (player_id = my_player_id(room_id) and round_is(room_id, 'round2_caption'));

-- round3_offers: you only see your own; the host generates everyone's draw
create policy offers_read on round3_offers for select to authenticated
  using (player_id = my_player_id(room_id));

create policy offers_add on round3_offers for insert to authenticated
  with check (is_room_host(room_id) and round_is(room_id, 'round3_match'));

-- pairings: own always; everyone's from round 4 (judging)
create policy pairings_read on pairings for select to authenticated
  using (
    is_room_member(room_id)
    and (player_id = my_player_id(room_id) or round_at_least(room_id, 'round4_judge'))
  );

create policy pairings_add on pairings for insert to authenticated
  with check (player_id = my_player_id(room_id) and round_is(room_id, 'round3_match'));

-- votes: own until the game is complete, then everyone's. No self-voting.
create policy votes_read on votes for select to authenticated
  using (
    is_room_member(room_id)
    and (voter_player_id = my_player_id(room_id) or round_is(room_id, 'complete'))
  );

create policy votes_add on votes for insert to authenticated
  with check (
    voter_player_id = my_player_id(room_id)
    and round_is(room_id, 'round4_judge')
    and pairing_owner(pairing_id) <> voter_player_id
  );

-- ---------------------------------------------------------------------------
-- 5. Max 4 photos per player
-- ---------------------------------------------------------------------------

create function enforce_photo_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.photos where player_id = new.player_id) >= 4 then
    raise exception 'A player can submit at most 4 photos';
  end if;
  return new;
end;
$$;

create trigger photos_limit
  before insert on photos
  for each row
  execute function enforce_photo_limit();
