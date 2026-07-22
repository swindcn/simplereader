revoke execute on function public.expire_web_transfer_uploads() from anon, authenticated;
grant execute on function public.expire_web_transfer_uploads() to service_role;

create index if not exists transfer_upload_sessions_device_id_idx
    on public.transfer_upload_sessions (device_id);

create index if not exists transfer_upload_sessions_pairing_code_id_idx
    on public.transfer_upload_sessions (pairing_code_id);
