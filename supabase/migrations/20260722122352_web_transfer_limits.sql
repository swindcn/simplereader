create table if not exists public.transfer_verification_limits (
    client_key_hash text primary key,
    minute_attempt_count integer not null default 0 check (minute_attempt_count >= 0),
    minute_window_started_at timestamptz not null default now(),
    hour_attempt_count integer not null default 0 check (hour_attempt_count >= 0),
    hour_window_started_at timestamptz not null default now(),
    last_attempt_at timestamptz not null default now(),
    penalty_until timestamptz
);

alter table public.transfer_verification_limits enable row level security;

revoke all on public.transfer_verification_limits from anon, authenticated;

create index if not exists transfer_uploads_device_daily_idx
    on public.transfer_uploads (device_id, created_at desc)
    where status <> 'failed';
