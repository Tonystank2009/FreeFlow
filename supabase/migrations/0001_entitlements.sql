-- FreeFlow entitlements
--
-- One row per account that has paid. The app reads its own row; only the
-- service role (the dodo-webhook edge function) ever writes one.

create table if not exists public.entitlements (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    status     text        not null default 'active',
    source     text,
    product_id text,
    payment_id text,
    granted_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint entitlements_status_check check (status in ('active', 'refunded', 'revoked'))
);

comment on table public.entitlements is
    'Paid entitlement per account. Written only by the Dodo webhook via the service role.';

alter table public.entitlements enable row level security;

-- A signed-in user may read their own entitlement and nothing else.
drop policy if exists "read own entitlement" on public.entitlements;
create policy "read own entitlement"
    on public.entitlements
    for select
    to authenticated
    using (auth.uid() = user_id);

-- Deliberately no insert/update/delete policy. The service role bypasses RLS,
-- so the webhook can write; nothing reachable with the anon key can.

-- Idempotency: Standard Webhooks redelivers, so record which events we've
-- already applied.
create table if not exists public.processed_webhooks (
    webhook_id   text primary key,
    event_type   text,
    processed_at timestamptz not null default now()
);

alter table public.processed_webhooks enable row level security;
-- No policies at all: service role only.

create index if not exists processed_webhooks_processed_at_idx
    on public.processed_webhooks (processed_at desc);
