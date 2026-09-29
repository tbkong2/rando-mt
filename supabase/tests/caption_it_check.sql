-- Caption It: checks for migration 004 (final rules). Paste into the Supabase
-- SQL Editor and run. Ends with a PASS/FAIL table, and deletes everything it
-- created (fake users, their rooms and storage rows, helpers) at the end.
--
-- The game functions identify the caller through auth.uid(), which reads the
-- JWT claims, so most checks just set the claims to "become" a player. The
-- permission checks at the bottom also switch to the anon/authenticated
-- roles, because the SQL Editor's own role bypasses RLS.

-- ---------------------------------------------------------------------------
-- Cleanup from an earlier aborted run, then scratch helpers
-- ---------------------------------------------------------------------------
reset role;
delete from public.rooms where id in (
  select room_id from public.players
  where auth_user_id::text like '00000000-0000-0000-0000-0000000000__');
-- Supabase blocks direct deletes on storage tables unless this is set
select set_config('storage.allow_delete_query', 'true', false);
do $$
begin
  delete from storage.objects
    where bucket_id = 'photos' and owner_id like '00000000-0000-0000-0000-0000000000__';
exception when others then
  null;
end;
$$;
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000__';
drop table if exists public.zz_results, public.zz_ids;
drop function if exists public.zz_t(text, boolean), public.zz_err(text),
  public.zz_as(uuid), public.zz_id(text);

create table public.zz_results (n serial, name text, pass boolean);
create table public.zz_ids (k text primary key, v uuid);
grant select on public.zz_ids to anon, authenticated;

create function public.zz_t(p_name text, p_pass boolean) returns void
language sql security definer set search_path = '' as $$
  insert into public.zz_results (name, pass) values (p_name, coalesce(p_pass, false));
$$;

-- null if the statement succeeds, otherwise the error message
create function public.zz_err(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end;
$$;

-- act as a given user for every call after this
create function public.zz_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
end;
$$;

-- security definer: projects with "automatic RLS" put RLS on zz_ids too,
-- which would hide it from the authenticated role in the checks below
create function public.zz_id(p_key text) returns uuid
language sql stable security definer set search_path = '' as $$
  select v from public.zz_ids where k = p_key
$$;

grant execute on function public.zz_t(text, boolean), public.zz_err(text),
  public.zz_as(uuid), public.zz_id(text) to anon, authenticated;

-- users 01-04 play the main game, 05 is an outsider, 06-10 fill a second room
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
       'authenticated', 'authenticated', 'zz-' || i || '@example.test'
from generate_series(1, 10) i;

-- ---------------------------------------------------------------------------
-- Lobby, joining, leaving, room size
-- ---------------------------------------------------------------------------
do $$
declare
  u uuid[] := array(
    select ('00000000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid
    from generate_series(1, 10) i);
  room uuid;
  room2 uuid;
  room3 uuid;
  pid uuid;
  err text;
begin
  perform public.zz_as(u[1]);
  room := public.create_room('Alice');
  perform public.zz_t('host can create a room', room is not null);
  perform public.zz_t('the creator is the host',
    (select is_host from public.players where room_id = room and auth_user_id = u[1]));
  perform public.zz_t('blank names are rejected',
    public.zz_err(format('select public.create_room(%L)', '   ')) like '%1 to 16%');

  perform public.zz_as(u[2]);
  pid := public.join_room(room, 'Bob');
  perform public.zz_t('a second player can join', pid is not null);
  perform public.zz_t('joining again returns the same seat', public.join_room(room, 'Bob') = pid);

  perform public.zz_as(u[1]);
  perform public.zz_t('cannot start with 2 players',
    public.zz_err(format('select public.start_game(%L)', room)) like '%at least 3%');

  perform public.zz_as(u[3]);
  perform public.join_room(room, 'Cara');
  perform public.zz_as(u[4]);
  perform public.join_room(room, 'Dan');

  perform public.zz_as(u[2]);
  perform public.zz_t('a non-host cannot start',
    public.zz_err(format('select public.start_game(%L)', room)) like '%Only the host%');

  perform public.zz_as(u[5]);
  perform public.zz_t('an outsider cannot read the game state',
    public.zz_err(format('select public.get_game_state(%L)', room)) like '%not in this room%');

  perform public.zz_as(u[1]);
  perform public.zz_t('the host can start with 4 players',
    public.zz_err(format('select public.start_game(%L)', room)) is null);
  perform public.zz_t('starting moves to the upload round',
    (select round from public.rooms where id = room) = 'upload');
  perform public.zz_t('seats are shuffled into 0..3',
    (select array_agg(seat order by seat) from public.players where room_id = room)
      = array[0, 1, 2, 3]);

  perform public.zz_as(u[5]);
  perform public.zz_t('nobody can join after the start',
    public.zz_err(format('select public.join_room(%L, %L)', room, 'Eve')) like '%already started%');

  -- a second room: fill it to 8, then a 9th is turned away
  perform public.zz_as(u[5]);
  room2 := public.create_room('Host2');
  for i in 6..10 loop
    perform public.zz_as(u[i]);
    perform public.join_room(room2, 'P' || i);
  end loop;
  perform public.zz_as(u[2]);
  perform public.join_room(room2, 'Bob2');
  perform public.zz_as(u[3]);
  perform public.join_room(room2, 'Cara2');
  perform public.zz_t('a room holds 8 players',
    (select count(*) from public.players where room_id = room2) = 8);
  perform public.zz_as(u[4]);
  perform public.zz_t('a 9th player is turned away',
    public.zz_err(format('select public.join_room(%L, %L)', room2, 'Dan2')) like '%full%');

  perform public.zz_as(u[6]);
  perform public.leave_room(room2);
  perform public.zz_t('a player can leave the lobby',
    (select count(*) from public.players where room_id = room2) = 7);
  perform public.zz_as(u[5]);
  perform public.leave_room(room2);
  perform public.zz_t('when the host leaves, the next-oldest player becomes host',
    (select is_host from public.players where room_id = room2 and auth_user_id = u[7]));

  -- a third room parked in the upload round, for the storage checks below
  perform public.zz_as(u[8]);
  room3 := public.create_room('Host3');
  perform public.zz_as(u[9]);
  perform public.join_room(room3, 'P9');
  perform public.zz_as(u[10]);
  perform public.join_room(room3, 'P10');
  perform public.zz_as(u[8]);
  perform public.start_game(room3);

  insert into public.zz_ids values
    ('room', room), ('room2', room2), ('room3', room3),
    ('u1', u[1]), ('u5', u[5]), ('u8', u[8]), ('u9', u[9]);
end;
$$;

-- ---------------------------------------------------------------------------
-- Upload round
-- ---------------------------------------------------------------------------
do $$
declare
  room uuid := public.zz_id('room');
  u uuid[] := array(select auth_user_id from public.players
                    where room_id = public.zz_id('room') order by joined_at);
  paths text[] := array[]::text[];
  p text;
begin
  -- simulate each player's storage upload
  for i in 1..4 loop
    p := room || '/' || gen_random_uuid() || '.jpg';
    paths := paths || p;
    insert into storage.objects (bucket_id, name, owner_id) values ('photos', p, u[i]::text);
  end loop;

  perform public.zz_as(u[1]);
  perform public.zz_t('submitting a photo that was never uploaded fails',
    public.zz_err(format('select public.submit_photo(%L, %L)', room, room || '/nope.jpg'))
      like '%Upload the photo%');
  perform public.zz_t('submitting another player''s upload fails',
    public.zz_err(format('select public.submit_photo(%L, %L)', room, paths[2]))
      like '%Upload the photo%');
  perform public.zz_t('a player can submit their photo',
    public.zz_err(format('select public.submit_photo(%L, %L)', room, paths[1])) is null);
  perform public.zz_t('a second photo is rejected',
    public.zz_err(format('select public.submit_photo(%L, %L)', room, paths[1]))
      like '%already submitted%');
  perform public.zz_t('the submitter shows as done',
    (select (e ->> 'done')::boolean
     from jsonb_array_elements(public.get_game_state(room) -> 'players') e
     where (e ->> 'is_me')::boolean));

  for i in 2..3 loop
    perform public.zz_as(u[i]);
    perform public.submit_photo(room, paths[i]);
  end loop;
  perform public.zz_t('the round waits for every photo',
    (select round from public.rooms where id = room) = 'upload');

  perform public.zz_as(u[4]);
  perform public.submit_photo(room, paths[4]);
  perform public.zz_t('the last photo moves to the caption round',
    (select round from public.rooms where id = room) = 'caption');
end;
$$;

-- ---------------------------------------------------------------------------
-- Caption round
-- ---------------------------------------------------------------------------
do $$
declare
  room uuid := public.zz_id('room');
  u uuid[] := array(select auth_user_id from public.players
                    where room_id = public.zz_id('room') order by joined_at);
  st jsonb;
  a jsonb;
  own_photo uuid;
  other_photo uuid;
  all_two boolean := true;
  none_own boolean := true;
  shared uuid;
  first_writer uuid;
  second_writer uuid;
begin
  -- every player gets exactly two photos, never their own
  for i in 1..4 loop
    perform public.zz_as(u[i]);
    st := public.get_game_state(room);
    if jsonb_array_length(st -> 'assignments') <> 2 then all_two := false; end if;
    if exists (
      select 1 from jsonb_array_elements(st -> 'assignments') x
      where (x ->> 'photo_id')::uuid = (
        select ph.id from public.photos ph
        join public.players p on p.id = ph.player_id
        where p.auth_user_id = u[i] and ph.room_id = room)
    ) then none_own := false; end if;
  end loop;
  perform public.zz_t('every player is assigned exactly 2 photos', all_two);
  perform public.zz_t('nobody is assigned their own photo', none_own);
  perform public.zz_t('every photo has exactly 2 captioners',
    (select bool_and(n = 2) from (
       select count(*) n from public.photos ph, public.players p
       where ph.room_id = room and p.room_id = room and private.is_captioner(ph.id, p.id)
       group by ph.id) s));

  perform public.zz_as(u[1]);
  select ph.id into own_photo from public.photos ph
    join public.players p on p.id = ph.player_id
    where p.auth_user_id = u[1] and ph.room_id = room;
  perform public.zz_t('captioning your own photo fails',
    public.zz_err(format('select public.submit_caption(%L, %L)', own_photo, 'mine'))
      like '%not assigned%');
  select ph.id into other_photo from public.photos ph
    where ph.room_id = room and ph.id <> own_photo
      and not private.is_captioner(ph.id, (select id from public.players where auth_user_id = u[1] and room_id = room))
    limit 1;
  perform public.zz_t('captioning a photo that isn''t assigned to you fails',
    public.zz_err(format('select public.submit_caption(%L, %L)', other_photo, 'nope'))
      like '%not assigned%');

  -- blind: two writers share a photo; the second can't see the first's caption
  select ph.id into shared from public.photos ph where ph.room_id = room limit 1;
  select p.auth_user_id into first_writer from public.players p
    where p.room_id = room and private.is_captioner(shared, p.id) order by p.seat limit 1;
  select p.auth_user_id into second_writer from public.players p
    where p.room_id = room and private.is_captioner(shared, p.id) order by p.seat desc limit 1;
  perform public.zz_as(first_writer);
  perform public.zz_t('captions over 80 characters are rejected',
    public.zz_err(format('select public.submit_caption(%L, %L)', shared, repeat('x', 81)))
      like '%1 to 80%');
  perform public.submit_caption(shared, 'first writer caption');
  perform public.zz_t('captioning the same photo twice fails',
    public.zz_err(format('select public.submit_caption(%L, %L)', shared, 'again'))
      like '%already captioned%');
  perform public.zz_as(second_writer);
  perform public.zz_t('captions are blind: the other writer can''t see it',
    public.get_game_state(room)::text not like '%first writer caption%');

  -- everyone writes the rest of their captions
  for i in 1..4 loop
    perform public.zz_as(u[i]);
    st := public.get_game_state(room);
    for a in select * from jsonb_array_elements(st -> 'assignments') loop
      if a ->> 'my_caption' is null then
        if (select count(*) from public.captions where room_id = room) = 7 then
          perform public.zz_t('the round waits for every caption',
            (select round from public.rooms where id = room) = 'caption');
        end if;
        perform public.submit_caption((a ->> 'photo_id')::uuid, 'caption by ' || i);
      end if;
    end loop;
  end loop;

  perform public.zz_t('the last caption starts voting on matchup 1',
    (select round = 'vote' and matchup = 0 and phase = 'voting'
     from public.rooms where id = room));
  perform public.zz_t('the photo order is shuffled into 0..3',
    (select array_agg(vote_order order by vote_order) from public.photos where room_id = room)
      = array[0, 1, 2, 3]);
end;
$$;

-- ---------------------------------------------------------------------------
-- Vote round and scoring
-- Planned results for the 4 matchups (4 voters each):
--   3-1 -> 600 / 100    2-2 tie -> 200 / 200    4-0 -> 800 / 0    1-3 -> 100 / 600
-- ---------------------------------------------------------------------------
do $$
declare
  room uuid := public.zz_id('room');
  u uuid[] := array(select auth_user_id from public.players
                    where room_id = public.zz_id('room') order by joined_at);
  plan int[] := array[3, 2, 4, 1];  -- votes for the first caption in each matchup
  expected int[][] := array[[600, 100], [200, 200], [800, 0], [100, 600]];
  c1 uuid;
  c2 uuid;
  st jsonb;
  photo uuid;
  points_ok boolean := true;
begin
  for m in 0..3 loop
    select id into photo from public.photos where room_id = room and vote_order = m;
    select id into c1 from public.captions where photo_id = photo order by id limit 1;
    select id into c2 from public.captions where photo_id = photo order by id desc limit 1;

    if m = 0 then
      perform public.zz_as(u[1]);
      st := public.get_game_state(room);
      perform public.zz_t('captions are anonymous while voting',
        (select bool_and(x -> 'author' = 'null'::jsonb and x -> 'votes' = 'null'::jsonb)
         from jsonb_array_elements(st -> 'matchup' -> 'captions') x));
      perform public.zz_t('the photo owner is hidden while voting',
        st -> 'matchup' -> 'owner' = 'null'::jsonb);
      perform public.zz_t('voting on a later matchup fails',
        public.zz_err(format('select public.cast_vote(%L)',
          (select c.id from public.captions c join public.photos ph on ph.id = c.photo_id
           where ph.room_id = room and ph.vote_order = 1 limit 1))) like '%current matchup%');
      perform public.zz_t('the host can''t skip ahead before everyone votes',
        public.zz_err(format('select public.next_matchup(%L)', room)) like '%everyone has voted%');
    end if;

    for i in 1..4 loop
      perform public.zz_as(u[i]);
      if i <= plan[m + 1] then
        perform public.cast_vote(c1);
      else
        perform public.cast_vote(c2);
      end if;

      if m = 0 and i = 1 then
        perform public.zz_t('a player can''t vote twice',
          public.zz_err(format('select public.cast_vote(%L)', c2)) like '%already voted%');
        perform public.zz_t('your vote is remembered',
          (public.get_game_state(room) -> 'matchup' ->> 'my_vote')::uuid = c1);
      end if;
      if m = 0 and i = 3 then
        perform public.zz_t('the result waits for every vote',
          (select phase from public.rooms where id = room) = 'voting');
      end if;
    end loop;

    if (select points from public.captions where id = c1) <> expected[m + 1][1]
       or (select points from public.captions where id = c2) <> expected[m + 1][2] then
      points_ok := false;
    end if;

    if m = 0 then
      perform public.zz_t('the last vote reveals the result',
        (select phase from public.rooms where id = room) = 'reveal');
      st := public.get_game_state(room);
      perform public.zz_t('the reveal shows authors, votes and points',
        (select bool_and(x ->> 'author' is not null and x ->> 'points' is not null)
         from jsonb_array_elements(st -> 'matchup' -> 'captions') x)
        and st -> 'matchup' ->> 'owner' is not null);
      perform public.zz_t('no votes after the reveal',
        public.zz_err(format('select public.cast_vote(%L)', c1)) like '%closed%');
      perform public.zz_as(u[2]);
      perform public.zz_t('only the host can move on',
        public.zz_err(format('select public.next_matchup(%L)', room)) like '%Only the host%');
    end if;

    perform public.zz_as(u[1]);
    perform public.next_matchup(room);
  end loop;

  perform public.zz_t('points: 3-1 = 600/100, tie 2-2 = 200/200, 4-0 = 800/0, 1-3 = 100/600',
    points_ok);
  perform public.zz_t('every score is the sum of that player''s caption points',
    (select bool_and(p.score = (select coalesce(sum(c.points), 0) from public.captions c
                                where c.player_id = p.id))
     from public.players p where p.room_id = room));
  perform public.zz_t('2,600 points were paid out in total',
    (select sum(score) from public.players where room_id = room) = 2600);
  perform public.zz_t('after the last matchup the game shows results',
    (select round from public.rooms where id = room) = 'results');

  -- shared places: force a tie and read the ranking
  update public.players p set score = s.score
  from (select id, (array[500, 500, 300, 100])[row_number() over (order by joined_at)] score
        from public.players where room_id = room) s
  where p.id = s.id;
  perform public.zz_as(u[1]);
  perform public.zz_t('equal totals share a place (1, 1, 3, 4)',
    (select array_agg((x ->> 'place')::int order by (x ->> 'place')::int)
     from jsonb_array_elements(public.get_game_state(room) -> 'results') x)
      = array[1, 1, 3, 4]);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions: what a phone can do outside the game functions
-- ---------------------------------------------------------------------------
reset role;
select public.zz_as(public.zz_id('u5'));
set role anon;
select public.zz_t('a signed-out phone cannot call the game functions',
  public.zz_err($q$select public.create_room('x')$q$) like '%permission denied%');

reset role;
select public.zz_as(public.zz_id('u1'));
set role authenticated;
select public.zz_t('internal helpers cannot be called',
  public.zz_err($q$select private.reveal_matchup(gen_random_uuid())$q$) like '%permission denied%');
select public.zz_t('game tables cannot be read directly',
  (select count(*) from public.players) = 0
  and (select count(*) from public.photos) = 0
  and (select count(*) from public.captions) = 0
  and (select count(*) from public.votes) = 0);
select public.zz_err($q$update public.players set score = 99999$q$);
select public.zz_err($q$insert into public.votes (room_id, photo_id, caption_id, voter_id)
  select room_id, photo_id, id, player_id from public.captions$q$);
select public.zz_t('a member can read their own room row (for Realtime)',
  (select count(*) from public.rooms where id = public.zz_id('room')) = 1);

reset role;
select public.zz_t('game tables cannot be written directly',
  not exists (select 1 from public.players where score = 99999)
  and (select count(*) from public.votes where room_id = public.zz_id('room')) = 16);

reset role;
select public.zz_as(public.zz_id('u5'));
set role authenticated;
select public.zz_t('an outsider cannot read the room row',
  (select count(*) from public.rooms where id = public.zz_id('room')) = 0);

-- storage: room3 is still in the upload round
reset role;
select public.zz_as(public.zz_id('u9'));
set role authenticated;
select public.zz_t('a member can upload into their room folder during upload',
  public.zz_err(format($q$insert into storage.objects (bucket_id, name, owner_id)
    values ('photos', %L, %L)$q$, public.zz_id('room3') || '/a.jpg', public.zz_id('u9'))) is null);
select public.zz_t('a member can see their room''s photos',
  (select count(*) from storage.objects
   where name like public.zz_id('room3') || '/%') = 1);

reset role;
select public.zz_as(public.zz_id('u1'));
set role authenticated;
select public.zz_t('an outsider cannot upload into another room',
  public.zz_err(format($q$insert into storage.objects (bucket_id, name, owner_id)
    values ('photos', %L, %L)$q$, public.zz_id('room3') || '/b.jpg', public.zz_id('u1')))
    is not null);
select public.zz_t('an outsider cannot see another room''s photos',
  (select count(*) from storage.objects
   where name like public.zz_id('room3') || '/%') = 0);
select public.zz_t('uploads are refused outside the upload round',
  public.zz_err(format($q$insert into storage.objects (bucket_id, name, owner_id)
    values ('photos', %L, %L)$q$, public.zz_id('room') || '/late.jpg', public.zz_id('u1')))
    is not null);

-- ---------------------------------------------------------------------------
-- Clean up, then show results
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '', false);
delete from public.rooms where id in (
  select room_id from public.players
  where auth_user_id::text like '00000000-0000-0000-0000-0000000000__');
select set_config('storage.allow_delete_query', 'true', false);
do $$
begin
  delete from storage.objects
    where bucket_id = 'photos' and owner_id like '00000000-0000-0000-0000-0000000000__';
  perform public.zz_t('cleanup: fake photo rows removed from storage', true);
exception when others then
  perform public.zz_t('cleanup: fake photo rows removed from storage (' || sqlerrm || ')', false);
end;
$$;
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000__';
create temp table zz_final as select n, name, pass from public.zz_results;
drop function public.zz_t(text, boolean), public.zz_err(text),
  public.zz_as(uuid), public.zz_id(text);
drop table public.zz_results, public.zz_ids;

select case when pass then 'PASS' else 'FAIL' end as result, name
from zz_final order by n;
