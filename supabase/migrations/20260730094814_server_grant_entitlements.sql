create table if not exists public.server_grant_entitlements (
    device_id uuid primary key references public.transfer_devices(id) on delete cascade,
    entitlement text not null check (entitlement in ('lifetime-free')),
    note text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    revoked_at timestamptz
);

comment on table public.server_grant_entitlements is
    'Server-managed entitlement grants keyed by the app web-transfer device ID.';

comment on column public.server_grant_entitlements.entitlement is
    'Currently supports lifetime-free for manually granted welfare or review users.';

create index if not exists server_grant_entitlements_active_idx
    on public.server_grant_entitlements (device_id, entitlement)
    where revoked_at is null;

alter table public.server_grant_entitlements enable row level security;

revoke all on public.server_grant_entitlements from anon, authenticated;
