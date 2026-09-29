create or replace function award_vote_points()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  points integer := 4 - new.rank;
  winner_id uuid;
begin
  select player_id into winner_id
  from public.pairings
  where id = new.pairing_id;

  update public.players
  set score = score + points
  where id = winner_id;

  return new;
end;
$$;

drop trigger if exists votes_award_points on public.votes;

create trigger votes_award_points
  after insert on public.votes
  for each row
  execute function award_vote_points();