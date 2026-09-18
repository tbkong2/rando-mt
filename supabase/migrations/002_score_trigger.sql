create or replace function award_vote_points()
returns trigger
language plpgsql
security definer
as $$
declare
  points integer := 4 - new.rank;
  winner_id uuid;
begin
    --who ever submitted the pairing gets the points - not the voter
    select player_id into winner_id
    from pairings
    where id = new.pairing_id;
    -- update the score of the player who submitted the pairing
    update players
    set score = score + points
    where id = winner_id;

    return new;
end;
$$;

--once a vote is cast, award points to the player who submitted the pairing
create trigger votes_award_points
    after insert on votes
    for each row
    execute function award_vote_points();