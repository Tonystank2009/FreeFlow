-- FreeFlow email capture
--
-- Unverified addresses collected during onboarding. Deliberately NOT an auth
-- table: there is no account, no password and no emailed code. This exists only
-- so there is a way to reach people later.

create table if not exists public.signups (
    id          uuid primary key default gen_random_uuid(),
    email       text        not null,
    source      text        not null default 'onboarding',
    app_version text,
    created_at  timestamptz not null default now()
);

create unique index if not exists signups_email_idx on public.signups (lower(email));

alter table public.signups enable row level security;

-- Anyone running the app may add an address. Nobody may read the list back:
-- without a select policy the anon key cannot enumerate your subscribers, which
-- matters because that key ships inside a GPL binary.
drop policy if exists "anyone can sign up" on public.signups;
create policy "anyone can sign up"
    on public.signups
    for insert
    to public
    with check (true);

grant usage on schema public to anon, authenticated;
grant insert on public.signups to anon, authenticated;
