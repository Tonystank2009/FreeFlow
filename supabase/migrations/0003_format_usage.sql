-- Per-licence daily quota for hosted formatting.
--
-- The point is damage control, not billing: if a licence key leaks, this caps
-- what it can spend. Service role only — nothing reachable with the anon key
-- can read or write it.

create table if not exists public.format_usage (
    license_key text        not null,
    day         date        not null,
    requests    integer     not null default 0,
    updated_at  timestamptz not null default now(),
    primary key (license_key, day)
);

alter table public.format_usage enable row level security;
-- No policies at all: only the service role reaches this.

create or replace function public.bump_format_usage(key_in text, day_in date)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.format_usage (license_key, day, requests, updated_at)
    values (key_in, day_in, 1, now())
    on conflict (license_key, day)
    do update set requests = format_usage.requests + 1, updated_at = now();
$$;

revoke execute on function public.bump_format_usage(text, date) from anon, authenticated;
