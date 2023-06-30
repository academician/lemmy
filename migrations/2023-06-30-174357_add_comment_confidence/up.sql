alter table comment_aggregates add column confidence double precision default 0 not null;

create function calculate_comment_confidence(upvotes bigint, downvotes bigint)
returns double precision
as $$
declare
    n double precision := upvotes + downvotes;
    z double precision := 1.281551565545;
    p double precision;
    l double precision;
    r double precision;
    under double precision;
    confidence double precision;
begin
    if n = 0 then
        return 0;
    end if;

    p := upvotes::double precision / n;
    l := p + 1.0 / (2.0 * n) * z * z;
    r := z * sqrt((p * (1.0 - p) / n + z * z / (4.0 * n * n)));
    under := 1.0 + 1.0 / n * z * z;
    confidence := (l - r) / under;

    return confidence;
end; $$ language plpgsql;

-- Populate the confidence values initially
update comment_aggregates set confidence = calculate_comment_confidence(upvotes, downvotes);

-- comment score
create or replace function comment_aggregates_score()
returns trigger language plpgsql
as $$
begin
  IF (TG_OP = 'INSERT') THEN
    update comment_aggregates ca
    set score = score + NEW.score,
    upvotes = case when NEW.score = 1 then upvotes + 1 else upvotes end,
    downvotes = case when NEW.score = -1 then downvotes + 1 else downvotes end,
    confidence = calculate_comment_confidence(case when NEW.score = 1 then upvotes + 1 else upvotes end, case when NEW.score = -1 then downvotes + 1 else downvotes end)
    where ca.comment_id = NEW.comment_id;

  ELSIF (TG_OP = 'DELETE') THEN
    -- Join to comment because that comment may not exist anymore
    update comment_aggregates ca
    set score = score - OLD.score,
    upvotes = case when OLD.score = 1 then upvotes - 1 else upvotes end,
    downvotes = case when OLD.score = -1 then downvotes - 1 else downvotes end,
    confidence = calculate_comment_confidence(case when OLD.score = 1 then upvotes - 1 else upvotes end, case when OLD.score = -1 then downvotes - 1 else downvotes end)
    from comment c
    where ca.comment_id = c.id
    and ca.comment_id = OLD.comment_id;

  END IF;
  return null;
end $$;