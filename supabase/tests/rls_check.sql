-- Caption It: RLS + trigger check. Paste into the Supabase SQL Editor and run.
-- Ends with a PASS/FAIL table. Uses fixed fake ids and deletes everything it
-- created (rows, helpers, scratch table) at the end.
--
-- The SQL Editor runs as `postgres`, which bypasses RLS, so each block
-- impersonates a player: it sets the JWT claims (which is what auth.uid()
-- reads) and switches to the `authenticated` role.
--
-- Cast:  A = host (11111111...)   B = second player (22222222...)
--        C = outsider, never in the room (33333333...)
-- Room:  aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa

-- ---------------------------------------------------------------------------
-- Cleanup from any earlier aborted run, then scratch helpers
-- ---------------------------------------------------------------------------
reset role;
delete from public.rooms where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
delete from auth.users where id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333');
drop table if exists public.zz_results;
drop function if exists public.zz_t(text, boolean);
drop function if exists public.zz_fails(text);
drop function if exists public.zz_rows(text);

create table public.zz_results (n serial, name text, pass boolean);

-- records one result; security definer so it can write even while impersonating
create function public.zz_t(p_name text, p_pass boolean) returns void
language sql security definer set search_path = '' as $$
  insert into public.zz_results (name, pass) values (p_name, coalesce(p_pass, false));
$$;

-- true if the statement raises an error (RLS violation, trigger, constraint)
create function public.zz_fails(p_sql text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return true;
end;
$$;

-- number of rows the statement touched (RLS silently filters updates/deletes to 0)
create function public.zz_rows(p_sql text) returns int
language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- three throwaway auth users
insert into auth.users (id, aud, role, email) values
  ('11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'zz-a@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'zz-b@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'zz-c@example.test');

-- ---------------------------------------------------------------------------
-- A creates the room and becomes host; B joins
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;

select public.zz_t('A can create a room',
  not public.zz_fails($q$insert into rooms (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$q$));
select public.zz_t('A can join as host (first player)',
  not public.zz_fails($q$insert into players (id, room_id, auth_user_id, display_name, is_host)
    values ('a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '11111111-1111-1111-1111-111111111111', 'A', true)$q$));

reset role;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
set role authenticated;

select public.zz_t('B can join the lobby as a normal player',
  not public.zz_fails($q$insert into players (id, room_id, auth_user_id, display_name, is_host)
    values ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '22222222-2222-2222-2222-222222222222', 'B', false)$q$));

-- ---------------------------------------------------------------------------
-- Outsider C, during the lobby
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', false);
set role authenticated;

select public.zz_t('outsider cannot see the room',
  (select count(*) from rooms where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 0);
select public.zz_t('outsider cannot claim host in a room that already has players',
  public.zz_fails($q$insert into players (room_id, auth_user_id, display_name, is_host)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'C', true)$q$));
select public.zz_t('cannot join with a starting score other than 0',
  public.zz_fails($q$insert into players (room_id, auth_user_id, display_name, score)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'C', 5)$q$));

-- ---------------------------------------------------------------------------
-- Round control
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('non-host cannot change the round',
  public.zz_rows($q$update rooms set current_round = 'round1_submit' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$) = 0);

reset role;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('host can advance to round 1',
  public.zz_rows($q$update rooms set current_round = 'round1_submit' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$) = 1);

-- ---------------------------------------------------------------------------
-- Round 1: photos
-- ---------------------------------------------------------------------------
select public.zz_t('A can add 4 photos',
  not public.zz_fails($q$insert into photos (id, room_id, player_id, storage_path) values
    ('fa000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'a/1.jpg'),
    ('fa000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'a/2.jpg'),
    ('fa000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'a/3.jpg'),
    ('fa000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'a/4.jpg')$q$));
select public.zz_t('a 5th photo is rejected',
  public.zz_fails($q$insert into photos (room_id, player_id, storage_path)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'a/5.jpg')$q$));
select public.zz_t('A cannot add a photo as B',
  public.zz_fails($q$insert into photos (room_id, player_id, storage_path)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'x.jpg')$q$));
select public.zz_t('A sees their own 4 photos',
  (select count(*) from photos) = 4);

reset role;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('B can add a photo',
  not public.zz_fails($q$insert into photos (id, room_id, player_id, storage_path)
    values ('fb000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'b/1.jpg')$q$));
select public.zz_t('B cannot see A''s photos during round 1',
  (select count(*) from photos where player_id = 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1') = 0);

reset role;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('outsider cannot join once the lobby is over',
  public.zz_fails($q$insert into players (room_id, auth_user_id, display_name)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'C')$q$));

-- ---------------------------------------------------------------------------
-- Round 2: blind captions
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('host can advance to round 2',
  public.zz_rows($q$update rooms set current_round = 'round2_caption' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$) = 1);
select public.zz_t('no photos can be added in round 2',
  public.zz_fails($q$insert into photos (room_id, player_id, storage_path)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'late.jpg')$q$));

reset role;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('B can now see A''s photos',
  (select count(*) from photos where player_id = 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1') = 4);
select public.zz_t('B can caption A''s photo',
  not public.zz_fails($q$insert into captions (id, room_id, player_id, photo_id, text)
    values ('c0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'fa000000-0000-0000-0000-000000000001', 'test caption')$q$));
select public.zz_t('B sees their own caption',
  (select count(*) from captions) = 1);

reset role;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('captions are blind: A cannot see B''s caption in round 2',
  (select count(*) from captions) = 0);

reset role;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('outsider cannot see any photos or captions',
  (select count(*) from photos) = 0 and (select count(*) from captions) = 0);

-- ---------------------------------------------------------------------------
-- Round 3: offers and pairings
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('host can advance to round 3',
  public.zz_rows($q$update rooms set current_round = 'round3_match' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$) = 1);
select public.zz_t('captions are revealed in round 3: A sees B''s caption',
  (select count(*) from captions) = 1);
select public.zz_t('host can create an offer for B (3 photos, 4 captions)',
  not public.zz_fails($q$insert into round3_offers (room_id, player_id, photo_ids, caption_ids)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2',
      array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()],
      array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()])$q$));
select public.zz_t('an offer with the wrong number of photos is rejected',
  public.zz_fails($q$insert into round3_offers (room_id, player_id, photo_ids, caption_ids)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
      array[gen_random_uuid()],
      array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()])$q$));
select public.zz_t('host cannot read B''s offer',
  (select count(*) from round3_offers) = 0);
select public.zz_t('A can submit a pairing',
  not public.zz_fails($q$insert into pairings (id, room_id, player_id, photo_id, caption_id)
    values ('d0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'fb000000-0000-0000-0000-000000000001',
            'c0000000-0000-0000-0000-000000000001')$q$));
select public.zz_t('A cannot submit a second pairing',
  public.zz_fails($q$insert into pairings (room_id, player_id, photo_id, caption_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
            'fb000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001')$q$));

reset role;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('B can read their own offer',
  (select count(*) from round3_offers) = 1);
select public.zz_t('B cannot create offers (not host)',
  public.zz_fails($q$insert into round3_offers (room_id, player_id, photo_ids, caption_ids)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2',
      array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()],
      array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()])$q$));
select public.zz_t('B can submit a pairing',
  not public.zz_fails($q$insert into pairings (id, room_id, player_id, photo_id, caption_id)
    values ('d0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'fa000000-0000-0000-0000-000000000001',
            'c0000000-0000-0000-0000-000000000001')$q$));
select public.zz_t('pairings are hidden in round 3: B sees only their own',
  (select count(*) from pairings) = 1);

-- ---------------------------------------------------------------------------
-- Round 4: judging, no self-voting, score trigger
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('host can advance to round 4',
  public.zz_rows($q$update rooms set current_round = 'round4_judge' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$) = 1);
select public.zz_t('pairings are revealed in round 4: A sees both',
  (select count(*) from pairings) = 2);
select public.zz_t('A cannot vote on their own pairing',
  public.zz_fails($q$insert into votes (room_id, voter_player_id, pairing_id, rank)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
            'd0000000-0000-0000-0000-000000000001', 1)$q$));

reset role;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('B can vote 1st for A''s pairing',
  not public.zz_fails($q$insert into votes (room_id, voter_player_id, pairing_id, rank)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2',
            'd0000000-0000-0000-0000-000000000001', 1)$q$));
select public.zz_t('B cannot vote for the same pairing twice',
  public.zz_fails($q$insert into votes (room_id, voter_player_id, pairing_id, rank)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2',
            'd0000000-0000-0000-0000-000000000001', 2)$q$));
select public.zz_t('B cannot edit a score directly',
  public.zz_rows($q$update players set score = 99 where id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'$q$) = 0);

-- trigger result, read as the owner
reset role;
select public.zz_t('trigger: A''s score is 3 after a 1st-place vote',
  (select score from public.players where id = 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1') = 3);
select public.zz_t('trigger: B''s score is still 0',
  (select score from public.players where id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2') = 0);

-- votes stay private until the game is complete
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
set role authenticated;
select public.zz_t('votes are private during round 4: A cannot see B''s vote',
  (select count(*) from votes) = 0);
select public.zz_t('host can finish the game',
  public.zz_rows($q$update rooms set current_round = 'complete' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$) = 1);
select public.zz_t('votes are revealed once complete: A sees B''s vote',
  (select count(*) from votes) = 1);
select public.zz_t('no votes can be added once complete',
  public.zz_fails($q$insert into votes (room_id, voter_player_id, pairing_id, rank)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
            'd0000000-0000-0000-0000-000000000002', 2)$q$));
select public.zz_t('clients cannot delete rows',
  public.zz_rows($q$delete from photos$q$) = 0);

-- ---------------------------------------------------------------------------
-- Clean up, then show results
-- ---------------------------------------------------------------------------
reset role;
delete from public.rooms where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
delete from auth.users where id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333');
create temp table zz_final as select n, name, pass from public.zz_results;
drop function public.zz_t(text, boolean);
drop function public.zz_fails(text);
drop function public.zz_rows(text);
drop table public.zz_results;

select case when pass then 'PASS' else 'FAIL' end as result, name
from zz_final order by n;
