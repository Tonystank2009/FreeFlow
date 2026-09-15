-- Hosted formatting: spend cap and free trials.
--
-- The cap is denominated in dollars rather than requests. Request counts stop
-- meaning anything the moment the model changes; a spend ceiling stays true.

drop table if exists public.format_usage;

create table if not exists public.format_spend (
    subject    text        not null,   -- licence key, or trial id
    month      text        not null,   -- YYYY-MM
    cost_usd   numeric(10, 6) not null default 0,
    requests   integer     not null default 0,
    updated_at timestamptz not null default now(),
    primary key (subject, month)
);

create table if not exists public.format_trials (
    trial_id   text primary key,
    started_at timestamptz not null default now(),
    last_seen  timestamptz not null default now()
);

alter table public.format_spend  enable row level security;
alter table public.format_trials enable row level security;
-- No policies on either: the edge function reaches these as the service role,
-- and nothing holding the anon key should be able to read spend or trial data.

/// Adds the real cost of one request. Returns the running monthly total.
create or replace function public.add_format_spend(
    subject_in text,
    month_in   text,
    cost_in    numeric
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
    total numeric;
begin
    insert into public.format_spend (subject, month, cost_usd, requests, updated_at)
    values (subject_in, month_in, cost_in, 1, now())
    on conflict (subject, month) do update
        set cost_usd   = format_spend.cost_usd + cost_in,
            requests   = format_spend.requests + 1,
            updated_at = now()
    returning cost_usd into total;
    return total;
end;
$$;

/// Starts a trial the first time an install is seen, and reports how far in it
/// is. Idempotent: calling it again never restarts the clock.
create or replace function public.touch_format_trial(trial_id_in text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
    started timestamptz;
begin
    insert into public.format_trials (trial_id, started_at, last_seen)
    values (trial_id_in, now(), now())
    on conflict (trial_id) do update set last_seen = now()
    returning format_trials.started_at into started;
    return started;
end;
$$;

revoke execute on function public.add_format_spend(text, text, numeric) from anon, authenticated;
revoke execute on function public.touch_format_trial(text) from anon, authenticated;
