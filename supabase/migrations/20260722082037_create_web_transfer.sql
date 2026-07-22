create extension if not exists pgcrypto;

create table if not exists public.transfer_devices (
    id uuid primary key,
    secret_hash text not null,
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    reset_at timestamptz,
    disabled_at timestamptz
);

create table if not exists public.transfer_pairing_codes (
    id uuid primary key default gen_random_uuid(),
    device_id uuid not null references public.transfer_devices(id) on delete cascade,
    code_hash text not null,
    expires_at timestamptz,
    attempt_count integer not null default 0 check (attempt_count >= 0),
    revoked_at timestamptz,
    created_at timestamptz not null default now()
);

comment on column public.transfer_pairing_codes.expires_at is
    'Nullable. Null means the transfer code is long-term valid until the app regenerates or revokes it.';

create unique index if not exists transfer_pairing_codes_code_hash_idx
    on public.transfer_pairing_codes (code_hash)
    where revoked_at is null;

create unique index if not exists transfer_pairing_codes_one_active_per_device_idx
    on public.transfer_pairing_codes (device_id)
    where revoked_at is null;

create table if not exists public.transfer_upload_sessions (
    id uuid primary key default gen_random_uuid(),
    device_id uuid not null references public.transfer_devices(id) on delete cascade,
    pairing_code_id uuid not null references public.transfer_pairing_codes(id) on delete cascade,
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    revoked_at timestamptz
);

create table if not exists public.transfer_uploads (
    id uuid primary key default gen_random_uuid(),
    device_id uuid not null references public.transfer_devices(id) on delete cascade,
    original_filename text not null,
    storage_path text not null unique,
    format text not null check (format in ('txt', 'epub')),
    byte_size bigint not null check (byte_size > 0 and byte_size <= 262144000),
    status text not null check (status in ('pending', 'claimed', 'deleted', 'expired', 'failed')),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    claimed_at timestamptz,
    deleted_at timestamptz,
    failure_reason text
);

create index if not exists transfer_uploads_device_pending_idx
    on public.transfer_uploads (device_id, created_at desc)
    where status = 'pending';

alter table public.transfer_devices enable row level security;
alter table public.transfer_pairing_codes enable row level security;
alter table public.transfer_upload_sessions enable row level security;
alter table public.transfer_uploads enable row level security;

revoke all on public.transfer_devices from anon, authenticated;
revoke all on public.transfer_pairing_codes from anon, authenticated;
revoke all on public.transfer_upload_sessions from anon, authenticated;
revoke all on public.transfer_uploads from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'web-transfer',
    'web-transfer',
    false,
    262144000,
    array[
        'text/plain',
        'application/epub+zip',
        'application/octet-stream'
    ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.expire_web_transfer_uploads()
returns table(expired_upload_id uuid, expired_storage_path text)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    update public.transfer_uploads
    set status = 'expired'
    where status = 'pending'
      and expires_at <= now()
    returning id, storage_path;
end;
$$;

revoke all on function public.expire_web_transfer_uploads() from public;
