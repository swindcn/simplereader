# Web Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the V2 minimal website transfer flow so a helper can upload a book on the web with a temporary code and the iOS app can receive it into the local bookshelf.

**Architecture:** Supabase owns the temporary cloud relay: Postgres stores device identities, pairing codes, upload sessions, and inbox rows; private Supabase Storage stores short-lived files; Edge Functions are the only HTTP surface. The iOS app stores a random app-scoped transfer identity in Keychain, generates temporary codes, refreshes inbox items, downloads selected files to a temporary URL, and then reuses `ImportCoordinator.importBook(from:)`.

**Tech Stack:** SwiftUI, Swift concurrency, Keychain Services, URLSession, XCTest, Supabase Postgres, Supabase Storage, Supabase Edge Functions on Deno/TypeScript, Supabase CLI.

**Spec:** `docs/superpowers/specs/2026-07-22-web-transfer-design.md`

**Provider Notes:** Supabase Edge Functions are Deno-compatible TypeScript handlers and can integrate with Postgres and Storage through server-side credentials. Supabase Storage access is controlled by RLS and service keys bypass RLS, so the implementation keeps Storage private and only exposes signed URLs from Edge Functions. Supabase supports scheduled Edge Functions for cleanup. References checked on 2026-07-22:

- https://supabase.com/docs/guides/functions
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/functions/schedule-functions

---

## Scope Guard

This plan implements the web transfer pipeline, not the full MOBI parser. The repository currently rejects MOBI in `BookFormatDetector` with `mobiPendingLegalApproval`, and `ImportPipelineConverter` still throws for `.mobi`. To avoid accepting files the app cannot import, Task 2 makes backend allowed formats configurable and Task 8 ships with TXT/EPUB enabled by default. MOBI is left as a disabled format flag until the existing MOBI parser/legal approval work is completed.

## File Structure

- Create `supabase/config.toml`: local Supabase project configuration and function declarations.
- Create `supabase/migrations/202607220001_create_web_transfer.sql`: tables, indexes, RLS, private Storage bucket, and cleanup RPC.
- Create `supabase/functions/_shared/transfer.ts`: shared request parsing, JSON responses, auth, hashing, validation, and Supabase clients.
- Create `supabase/functions/transfer/index.ts`: routed Edge Function for app and web transfer APIs.
- Create `supabase/functions/transfer-cleanup/index.ts`: scheduled cleanup function.
- Create `supabase/functions/transfer-web/index.html`: minimal upload page served by the transfer function.
- Create `supabase/functions/transfer/transfer_test.ts`: Deno unit tests for validation and routing helpers.
- Create `PureVoice/Features/WebTransfer/TransferIdentity.swift`: app-scoped identity model.
- Create `PureVoice/Features/WebTransfer/TransferIdentityStore.swift`: Keychain persistence.
- Create `PureVoice/Features/WebTransfer/WebTransferModels.swift`: DTOs and user-facing errors.
- Create `PureVoice/Features/WebTransfer/WebTransferClient.swift`: API client protocol and URLSession implementation.
- Create `PureVoice/Features/WebTransfer/WebTransferViewModel.swift`: UI orchestration, download, import, and claim behavior.
- Create `PureVoice/Features/WebTransfer/WebTransferView.swift`: SwiftUI card and inbox list for Import tab.
- Modify `PureVoice/App/AppDependencies.swift`: construct and expose web transfer dependencies.
- Modify `PureVoice/App/RootTabView.swift`: pass web transfer dependencies into `ImportView`.
- Modify `PureVoice/Features/Import/ImportView.swift`: add website transfer section beneath local file import.
- Modify `PureVoice/Core/Models/UserFacingError.swift`: add web transfer error mapping.
- Create `PureVoiceTests/TransferIdentityStoreTests.swift`.
- Create `PureVoiceTests/WebTransferClientTests.swift`.
- Create `PureVoiceTests/WebTransferViewModelTests.swift`.
- Modify `PureVoiceTests/AppDependenciesTests.swift`.
- Modify `PureVoiceTests/DocumentPickerTests.swift` only if local picker copy changes; otherwise leave it unchanged.
- Create or modify `PureVoiceUITests/ImportWebTransferAccessibilityUITests.swift`.

---

### Task 1: Supabase Schema And Storage

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/202607220001_create_web_transfer.sql`

- [ ] **Step 1: Discover local Supabase CLI commands**

Run:

```bash
supabase --help
supabase migration --help
supabase functions --help
```

Expected: CLI help prints successfully. If `supabase` is not installed, install it before continuing and rerun the commands.

- [ ] **Step 2: Write the migration**

Create `supabase/migrations/202607220001_create_web_transfer.sql` with:

```sql
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
    expires_at timestamptz not null,
    attempt_count integer not null default 0 check (attempt_count >= 0),
    revoked_at timestamptz,
    created_at timestamptz not null default now()
);

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
    format text not null check (format in ('txt', 'epub', 'mobi')),
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
        'application/octet-stream',
        'application/x-mobipocket-ebook'
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
```

- [ ] **Step 3: Add Supabase config**

Create `supabase/config.toml` with:

```toml
project_id = "purevoice-local"

[functions.transfer]
verify_jwt = false

[functions.transfer-cleanup]
verify_jwt = false
```

- [ ] **Step 4: Run migration locally**

Run:

```bash
supabase start
supabase db reset
```

Expected: local Supabase starts and the migration applies without SQL errors.

- [ ] **Step 5: Verify schema**

Run:

```bash
supabase db query "select table_name from information_schema.tables where table_schema = 'public' and table_name like 'transfer_%' order by table_name;"
supabase db query "select id, public, file_size_limit from storage.buckets where id = 'web-transfer';"
```

Expected: the four `transfer_*` tables exist and `web-transfer` is private with `262144000` byte limit.

- [ ] **Step 6: Commit**

```bash
git add supabase/config.toml supabase/migrations/202607220001_create_web_transfer.sql
git commit -m "feat: add web transfer schema"
```

---

### Task 2: Shared Edge Function Utilities

**Files:**
- Create: `supabase/functions/_shared/transfer.ts`
- Create: `supabase/functions/transfer/transfer_test.ts`

- [ ] **Step 1: Write failing Deno tests**

Create `supabase/functions/transfer/transfer_test.ts` with:

```ts
import {
  detectTransferFormat,
  jsonError,
  normalizeFilename,
  parseDeviceAuth,
  validateUploadSize,
} from "../_shared/transfer.ts";

Deno.test("detectTransferFormat accepts txt and epub by default", () => {
  const allowed = new Set(["txt", "epub"]);
  if (detectTransferFormat("故事.TXT", "text/plain", allowed) !== "txt") throw new Error("txt rejected");
  if (detectTransferFormat("book.epub", "application/epub+zip", allowed) !== "epub") throw new Error("epub rejected");
});

Deno.test("detectTransferFormat keeps mobi behind a feature flag", () => {
  const allowed = new Set(["txt", "epub"]);
  try {
    detectTransferFormat("book.mobi", "application/x-mobipocket-ebook", allowed);
    throw new Error("mobi accepted without flag");
  } catch (error) {
    if (!(error instanceof Response) || error.status !== 415) throw error;
  }
});

Deno.test("normalizeFilename strips path and control characters", () => {
  const normalized = normalizeFilename("../bad\u0000name.txt");
  if (normalized !== "badname.txt") throw new Error(normalized);
});

Deno.test("validateUploadSize rejects oversized files", () => {
  try {
    validateUploadSize(262144001);
    throw new Error("oversized accepted");
  } catch (error) {
    if (!(error instanceof Response) || error.status !== 413) throw error;
  }
});

Deno.test("parseDeviceAuth reads required headers", () => {
  const request = new Request("http://localhost", {
    headers: {
      "x-transfer-device-id": "11111111-1111-4111-8111-111111111111",
      "x-transfer-device-secret": "secret",
    },
  });
  const auth = parseDeviceAuth(request);
  if (auth.deviceId !== "11111111-1111-4111-8111-111111111111") throw new Error("bad id");
  if (auth.deviceSecret !== "secret") throw new Error("bad secret");
});

Deno.test("jsonError returns stable payload", async () => {
  const response = jsonError(400, "bad_code", "传书码无效");
  const body = await response.json();
  if (body.error.code !== "bad_code") throw new Error(JSON.stringify(body));
});
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
deno test --allow-env --allow-net supabase/functions/transfer/transfer_test.ts
```

Expected: FAIL because `../_shared/transfer.ts` does not exist.

- [ ] **Step 3: Implement shared helpers**

Create `supabase/functions/_shared/transfer.ts` with:

```ts
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.53.0";

export const MAX_UPLOAD_BYTES = 262_144_000;
export const CODE_TTL_SECONDS = 600;
export const UPLOAD_TTL_HOURS = 72;
export const DOWNLOAD_URL_TTL_SECONDS = 300;

export type TransferFormat = "txt" | "epub" | "mobi";

export interface DeviceAuth {
  deviceId: string;
  deviceSecret: string;
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
      "access-control-allow-headers": "content-type,x-transfer-device-id,x-transfer-device-secret",
    },
  });
}

export function jsonError(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export function optionsResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
      "access-control-allow-headers": "content-type,x-transfer-device-id,x-transfer-device-secret",
    },
  });
}

export function parseDeviceAuth(request: Request): DeviceAuth {
  const deviceId = request.headers.get("x-transfer-device-id")?.trim() ?? "";
  const deviceSecret = request.headers.get("x-transfer-device-secret") ?? "";
  if (!/^[0-9a-fA-F-]{36}$/.test(deviceId) || deviceSecret.length < 24) {
    throw jsonError(401, "invalid_device_auth", "设备传书身份无效。");
  }
  return { deviceId: deviceId.toLowerCase(), deviceSecret };
}

export function normalizeFilename(filename: string): string {
  const basename = filename.split(/[\\/]/).pop() ?? "book";
  const cleaned = basename.replace(/[\u0000-\u001f\u007f]/g, "").trim();
  return cleaned.length > 0 ? cleaned.slice(0, 180) : "book";
}

export function validateUploadSize(byteSize: number): void {
  if (!Number.isFinite(byteSize) || byteSize <= 0) {
    throw jsonError(400, "empty_file", "请选择有效的书籍文件。");
  }
  if (byteSize > MAX_UPLOAD_BYTES) {
    throw jsonError(413, "file_too_large", "文件超过 250 MB，无法上传。");
  }
}

export function detectTransferFormat(
  filename: string,
  mimeType: string,
  allowedFormats: Set<string>,
): TransferFormat {
  const extension = filename.split(".").pop()?.toLowerCase() ?? "";
  const normalizedMime = mimeType.toLowerCase();
  const extensionFormat =
    extension === "txt" ? "txt" :
    extension === "epub" ? "epub" :
    extension === "mobi" ? "mobi" :
    "";
  const mimeFormat =
    normalizedMime.includes("epub") ? "epub" :
    normalizedMime.includes("mobipocket") ? "mobi" :
    normalizedMime.startsWith("text/") ? "txt" :
    "";
  const format = extensionFormat || mimeFormat;
  if ((format === "txt" || format === "epub" || format === "mobi") && allowedFormats.has(format)) {
    return format;
  }
  throw jsonError(415, "unsupported_format", "当前网站传书支持 TXT 和 EPUB。");
}

export function allowedFormatsFromEnv(): Set<string> {
  const raw = Deno.env.get("WEB_TRANSFER_ALLOWED_FORMATS") ?? "txt,epub";
  return new Set(raw.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean));
}

export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw jsonError(500, "server_not_configured", "传书服务暂不可用。");
  }
  return createClient(url, key, { auth: { persistSession: false } });
}
```

- [ ] **Step 4: Run tests and confirm pass**

Run:

```bash
deno test --allow-env --allow-net supabase/functions/transfer/transfer_test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/transfer.ts supabase/functions/transfer/transfer_test.ts
git commit -m "feat: add web transfer edge helpers"
```

---

### Task 3: Transfer Edge Function API

**Files:**
- Create: `supabase/functions/transfer/index.ts`
- Modify: `supabase/functions/transfer/transfer_test.ts`

- [ ] **Step 1: Add routing tests**

Append to `supabase/functions/transfer/transfer_test.ts`:

```ts
import { routeName } from "./index.ts";

Deno.test("routeName maps transfer endpoints", () => {
  if (routeName(new URL("http://local/transfer/device/register"), "POST") !== "registerDevice") throw new Error("register");
  if (routeName(new URL("http://local/transfer/pairing-code"), "POST") !== "createPairingCode") throw new Error("pairing");
  if (routeName(new URL("http://local/transfer/inbox"), "GET") !== "inbox") throw new Error("inbox");
  if (routeName(new URL("http://local/transfer/uploads/abc/download-url"), "POST") !== "downloadUrl") throw new Error("download");
  if (routeName(new URL("http://local/transfer/uploads/abc/claim"), "POST") !== "claim") throw new Error("claim");
  if (routeName(new URL("http://local/transfer/uploads/abc"), "DELETE") !== "deleteUpload") throw new Error("delete");
  if (routeName(new URL("http://local/transfer/web/resolve-code"), "POST") !== "resolveCode") throw new Error("resolve");
  if (routeName(new URL("http://local/transfer/web/upload"), "POST") !== "webUpload") throw new Error("upload");
});
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
deno test --allow-env --allow-net supabase/functions/transfer/transfer_test.ts
```

Expected: FAIL because `routeName` is not implemented.

- [ ] **Step 3: Implement Edge Function routes**

Create `supabase/functions/transfer/index.ts` with:

```ts
import {
  allowedFormatsFromEnv,
  CODE_TTL_SECONDS,
  detectTransferFormat,
  DOWNLOAD_URL_TTL_SECONDS,
  json,
  jsonError,
  normalizeFilename,
  optionsResponse,
  parseDeviceAuth,
  serviceClient,
  sha256Hex,
  UPLOAD_TTL_HOURS,
  validateUploadSize,
} from "../_shared/transfer.ts";

export type RouteName =
  | "registerDevice"
  | "createPairingCode"
  | "resolveCode"
  | "webUpload"
  | "inbox"
  | "downloadUrl"
  | "claim"
  | "deleteUpload"
  | "webPage"
  | "notFound";

export function routeName(url: URL, method: string): RouteName {
  const path = url.pathname.replace(/\/+$/, "");
  if (method === "GET" && (path === "" || path === "/transfer" || path === "/transfer/web")) return "webPage";
  if (method === "POST" && path === "/transfer/device/register") return "registerDevice";
  if (method === "POST" && path === "/transfer/pairing-code") return "createPairingCode";
  if (method === "POST" && path === "/transfer/web/resolve-code") return "resolveCode";
  if (method === "POST" && path === "/transfer/web/upload") return "webUpload";
  if (method === "GET" && path === "/transfer/inbox") return "inbox";
  if (method === "POST" && /^\/transfer\/uploads\/[^/]+\/download-url$/.test(path)) return "downloadUrl";
  if (method === "POST" && /^\/transfer\/uploads\/[^/]+\/claim$/.test(path)) return "claim";
  if (method === "DELETE" && /^\/transfer\/uploads\/[^/]+$/.test(path)) return "deleteUpload";
  return "notFound";
}

function uploadIdFromPath(pathname: string): string {
  return pathname.split("/")[3] ?? "";
}

function expiresIn(seconds: number): string {
  return new Date(Date.now() + seconds * 1000).toISOString();
}

function expiresInHours(hours: number): string {
  return new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
}

function generateCode(): string {
  return String(crypto.getRandomValues(new Uint32Array(1))[0] % 100_000_000).padStart(8, "0");
}

async function assertDevice(supabase: ReturnType<typeof serviceClient>, request: Request) {
  const auth = parseDeviceAuth(request);
  const secretHash = await sha256Hex(auth.deviceSecret);
  const { data, error } = await supabase
    .from("transfer_devices")
    .select("id")
    .eq("id", auth.deviceId)
    .eq("secret_hash", secretHash)
    .is("disabled_at", null)
    .maybeSingle();
  if (error || !data) throw jsonError(401, "invalid_device_auth", "设备传书身份无效。");
  await supabase.from("transfer_devices").update({ last_seen_at: new Date().toISOString() }).eq("id", auth.deviceId);
  return auth;
}

async function registerDevice(request: Request): Promise<Response> {
  const body = await request.json();
  const deviceId = String(body.deviceId ?? "").toLowerCase();
  const deviceSecret = String(body.deviceSecret ?? "");
  if (!/^[0-9a-f-]{36}$/.test(deviceId) || deviceSecret.length < 24) {
    return jsonError(400, "invalid_request", "设备传书身份格式无效。");
  }
  const supabase = serviceClient();
  const secretHash = await sha256Hex(deviceSecret);
  const { error } = await supabase.from("transfer_devices").upsert({
    id: deviceId,
    secret_hash: secretHash,
    last_seen_at: new Date().toISOString(),
  });
  if (error) return jsonError(500, "register_failed", "注册传书身份失败。");
  return json({ deviceId, registered: true });
}

async function createPairingCode(request: Request): Promise<Response> {
  const supabase = serviceClient();
  const auth = await assertDevice(supabase, request);
  await supabase.from("transfer_pairing_codes").update({ revoked_at: new Date().toISOString() }).eq("device_id", auth.deviceId).is("revoked_at", null);
  const code = generateCode();
  const { error } = await supabase.from("transfer_pairing_codes").insert({
    device_id: auth.deviceId,
    code_hash: await sha256Hex(code),
    expires_at: expiresIn(CODE_TTL_SECONDS),
  });
  if (error) return jsonError(500, "pairing_failed", "生成传书码失败。");
  return json({ code, expiresAt: expiresIn(CODE_TTL_SECONDS) });
}

async function resolveCode(request: Request): Promise<Response> {
  const { code } = await request.json();
  const supabase = serviceClient();
  const codeHash = await sha256Hex(String(code ?? "").trim());
  const { data, error } = await supabase
    .from("transfer_pairing_codes")
    .select("id, device_id, expires_at, attempt_count")
    .eq("code_hash", codeHash)
    .is("revoked_at", null)
    .maybeSingle();
  if (error || !data || new Date(data.expires_at).getTime() <= Date.now()) {
    return jsonError(404, "code_not_found", "传书码不存在或已过期。");
  }
  if (data.attempt_count >= 5) return jsonError(429, "too_many_attempts", "传书码尝试次数过多。");
  const { data: session, error: sessionError } = await supabase.from("transfer_upload_sessions").insert({
    device_id: data.device_id,
    pairing_code_id: data.id,
    expires_at: data.expires_at,
  }).select("id, expires_at").single();
  if (sessionError) return jsonError(500, "session_failed", "创建上传会话失败。");
  return json({ uploadSessionId: session.id, expiresAt: session.expires_at });
}

async function webUpload(request: Request): Promise<Response> {
  const form = await request.formData();
  const uploadSessionId = String(form.get("uploadSessionId") ?? "");
  const file = form.get("file");
  if (!(file instanceof File)) return jsonError(400, "missing_file", "请选择要上传的文件。");
  validateUploadSize(file.size);
  const filename = normalizeFilename(file.name);
  const format = detectTransferFormat(filename, file.type, allowedFormatsFromEnv());
  const supabase = serviceClient();
  const { data: session, error: sessionError } = await supabase
    .from("transfer_upload_sessions")
    .select("id, device_id, expires_at")
    .eq("id", uploadSessionId)
    .is("revoked_at", null)
    .maybeSingle();
  if (sessionError || !session || new Date(session.expires_at).getTime() <= Date.now()) {
    return jsonError(401, "upload_session_expired", "上传会话已过期。");
  }
  const uploadId = crypto.randomUUID();
  const storagePath = `${session.device_id}/${uploadId}/${filename}`;
  const bytes = new Uint8Array(await file.arrayBuffer());
  const storage = await supabase.storage.from("web-transfer").upload(storagePath, bytes, {
    contentType: file.type || "application/octet-stream",
    upsert: false,
  });
  if (storage.error) return jsonError(500, "upload_failed", "文件上传失败。");
  const expiresAt = expiresInHours(UPLOAD_TTL_HOURS);
  const { error } = await supabase.from("transfer_uploads").insert({
    id: uploadId,
    device_id: session.device_id,
    original_filename: filename,
    storage_path: storagePath,
    format,
    byte_size: file.size,
    status: "pending",
    expires_at: expiresAt,
  });
  if (error) {
    await supabase.storage.from("web-transfer").remove([storagePath]);
    return jsonError(500, "record_failed", "保存上传记录失败。");
  }
  return json({ uploadId, filename, byteSize: file.size, format, expiresAt });
}

async function inbox(request: Request): Promise<Response> {
  const supabase = serviceClient();
  const auth = await assertDevice(supabase, request);
  const { data, error } = await supabase
    .from("transfer_uploads")
    .select("id, original_filename, byte_size, format, created_at, expires_at")
    .eq("device_id", auth.deviceId)
    .eq("status", "pending")
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false });
  if (error) return jsonError(500, "inbox_failed", "读取待接收文件失败。");
  return json({
    items: data.map((item) => ({
      id: item.id,
      filename: item.original_filename,
      byteSize: item.byte_size,
      format: item.format,
      createdAt: item.created_at,
      expiresAt: item.expires_at,
    })),
  });
}

async function downloadUrl(request: Request, uploadId: string): Promise<Response> {
  const supabase = serviceClient();
  const auth = await assertDevice(supabase, request);
  const { data, error } = await supabase
    .from("transfer_uploads")
    .select("storage_path")
    .eq("id", uploadId)
    .eq("device_id", auth.deviceId)
    .eq("status", "pending")
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (error || !data) return jsonError(404, "upload_not_found", "文件不存在或已过期。");
  const signed = await supabase.storage.from("web-transfer").createSignedUrl(data.storage_path, DOWNLOAD_URL_TTL_SECONDS);
  if (signed.error) return jsonError(500, "signed_url_failed", "生成下载链接失败。");
  return json({ downloadUrl: signed.data.signedUrl, expiresInSeconds: DOWNLOAD_URL_TTL_SECONDS });
}

async function claim(request: Request, uploadId: string): Promise<Response> {
  const supabase = serviceClient();
  const auth = await assertDevice(supabase, request);
  const { data, error } = await supabase
    .from("transfer_uploads")
    .update({ status: "claimed", claimed_at: new Date().toISOString() })
    .eq("id", uploadId)
    .eq("device_id", auth.deviceId)
    .eq("status", "pending")
    .select("storage_path")
    .maybeSingle();
  if (error || !data) return jsonError(404, "upload_not_found", "文件不存在或已过期。");
  await supabase.storage.from("web-transfer").remove([data.storage_path]);
  return json({ status: "claimed" });
}

async function deleteUpload(request: Request, uploadId: string): Promise<Response> {
  const supabase = serviceClient();
  const auth = await assertDevice(supabase, request);
  const { data, error } = await supabase
    .from("transfer_uploads")
    .update({ status: "deleted", deleted_at: new Date().toISOString() })
    .eq("id", uploadId)
    .eq("device_id", auth.deviceId)
    .eq("status", "pending")
    .select("storage_path")
    .maybeSingle();
  if (error || !data) return jsonError(404, "upload_not_found", "文件不存在或已过期。");
  await supabase.storage.from("web-transfer").remove([data.storage_path]);
  return json({ status: "deleted" });
}

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return optionsResponse();
  const url = new URL(request.url);
  try {
    switch (routeName(url, request.method)) {
      case "registerDevice": return await registerDevice(request);
      case "createPairingCode": return await createPairingCode(request);
      case "resolveCode": return await resolveCode(request);
      case "webUpload": return await webUpload(request);
      case "inbox": return await inbox(request);
      case "downloadUrl": return await downloadUrl(request, uploadIdFromPath(url.pathname));
      case "claim": return await claim(request, uploadIdFromPath(url.pathname));
      case "deleteUpload": return await deleteUpload(request, uploadIdFromPath(url.pathname));
      case "webPage": return new Response(await Deno.readTextFile("./transfer-web/index.html"), { headers: { "content-type": "text/html; charset=utf-8" } });
      case "notFound": return jsonError(404, "not_found", "接口不存在。");
    }
  } catch (error) {
    if (error instanceof Response) return error;
    console.error("transfer_unhandled", error);
    return jsonError(500, "server_error", "传书服务暂不可用。");
  }
}

if (import.meta.main) {
  Deno.serve(handler);
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
deno test --allow-env --allow-net --allow-read supabase/functions/transfer/transfer_test.ts
```

Expected: PASS.

- [ ] **Step 5: Serve function locally**

Run:

```bash
WEB_TRANSFER_ALLOWED_FORMATS=txt,epub supabase functions serve transfer
```

Expected: function starts. Do not commit local environment files or Supabase secrets.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/transfer/index.ts supabase/functions/transfer/transfer_test.ts
git commit -m "feat: add web transfer api"
```

---

### Task 4: Cleanup Function And Web Upload Page

**Files:**
- Create: `supabase/functions/transfer-cleanup/index.ts`
- Create: `supabase/functions/transfer-web/index.html`

- [ ] **Step 1: Implement cleanup function**

Create `supabase/functions/transfer-cleanup/index.ts` with:

```ts
import { json, jsonError, serviceClient } from "../_shared/transfer.ts";

Deno.serve(async () => {
  const supabase = serviceClient();
  const { data, error } = await supabase.rpc("expire_web_transfer_uploads");
  if (error) {
    console.error("transfer_cleanup_rpc_failed", error);
    return jsonError(500, "cleanup_failed", "清理过期文件失败。");
  }
  const paths = (data ?? []).map((row: { expired_storage_path: string }) => row.expired_storage_path);
  if (paths.length > 0) {
    const removal = await supabase.storage.from("web-transfer").remove(paths);
    if (removal.error) {
      console.error("transfer_cleanup_storage_failed", removal.error);
      return jsonError(500, "cleanup_storage_failed", "清理过期文件失败。");
    }
  }
  return json({ expired: paths.length });
});
```

- [ ] **Step 2: Implement minimal web page**

Create `supabase/functions/transfer-web/index.html` with:

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>简声网站传书</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; background: #f7f7fb; color: #111827; }
    main { max-width: 520px; margin: 0 auto; padding: 32px 20px; }
    h1 { font-size: 32px; margin: 0 0 24px; }
    label { display: block; font-size: 18px; font-weight: 700; margin: 18px 0 8px; }
    input, button { width: 100%; box-sizing: border-box; font-size: 20px; min-height: 56px; border-radius: 8px; }
    input { border: 1px solid #cfd3dc; padding: 12px; background: white; }
    button { border: 0; background: #0a84ff; color: white; font-weight: 700; margin-top: 20px; }
    button:disabled { background: #9ca3af; }
    #status { margin-top: 20px; font-size: 18px; line-height: 1.5; }
  </style>
</head>
<body>
  <main>
    <h1>简声网站传书</h1>
    <form id="form">
      <label for="code">临时传书码</label>
      <input id="code" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="8" required>
      <label for="file">选择书籍文件</label>
      <input id="file" name="file" type="file" accept=".txt,.epub" required>
      <button id="submit" type="submit">上传到 App</button>
    </form>
    <p id="status" role="status" aria-live="polite"></p>
  </main>
  <script>
    const form = document.getElementById("form");
    const status = document.getElementById("status");
    const submit = document.getElementById("submit");

    async function postJson(url, body) {
      const response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error?.message || "请求失败");
      return payload;
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      submit.disabled = true;
      status.textContent = "正在验证传书码";
      try {
        const code = document.getElementById("code").value.trim();
        const file = document.getElementById("file").files[0];
        const session = await postJson("/transfer/web/resolve-code", { code });
        const data = new FormData();
        data.append("uploadSessionId", session.uploadSessionId);
        data.append("file", file);
        status.textContent = "正在上传文件";
        const upload = await fetch("/transfer/web/upload", { method: "POST", body: data });
        const payload = await upload.json();
        if (!upload.ok) throw new Error(payload.error?.message || "上传失败");
        status.textContent = `上传成功：${payload.filename}。请回到简声 App 刷新接收。`;
      } catch (error) {
        status.textContent = error.message;
      } finally {
        submit.disabled = false;
      }
    });
  </script>
</body>
</html>
```

- [ ] **Step 3: Manually verify web page route**

Run the function locally, then open:

```bash
open http://127.0.0.1:54321/functions/v1/transfer
```

Expected: page shows “简声网站传书”, one code field, one file picker, and one upload button.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/transfer-cleanup/index.ts supabase/functions/transfer-web/index.html
git commit -m "feat: add web transfer cleanup and upload page"
```

---

### Task 5: iOS Transfer Identity Store

**Files:**
- Create: `PureVoice/Features/WebTransfer/TransferIdentity.swift`
- Create: `PureVoice/Features/WebTransfer/TransferIdentityStore.swift`
- Create: `PureVoiceTests/TransferIdentityStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PureVoiceTests/TransferIdentityStoreTests.swift` with:

```swift
import XCTest
@testable import PureVoice

final class TransferIdentityStoreTests: XCTestCase {
    func testMemoryStoreCreatesStableIdentityUntilReset() throws {
        let store = InMemoryTransferIdentityStore()

        let first = try store.identity()
        let second = try store.identity()

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.deviceSecret.count, 32)

        try store.reset()
        let reset = try store.identity()

        XCTAssertNotEqual(reset.deviceID, first.deviceID)
        XCTAssertNotEqual(reset.deviceSecret, first.deviceSecret)
    }
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/TransferIdentityStoreTests
```

Expected: FAIL because the types do not exist.

- [ ] **Step 3: Implement identity model and stores**

Create `PureVoice/Features/WebTransfer/TransferIdentity.swift`:

```swift
import Foundation
import Security

struct TransferIdentity: Equatable, Codable, Sendable {
    let deviceID: UUID
    let deviceSecret: String

    static func generate() -> TransferIdentity {
        TransferIdentity(deviceID: UUID(), deviceSecret: Self.randomSecret())
    }

    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
```

Create `PureVoice/Features/WebTransfer/TransferIdentityStore.swift`:

```swift
import Foundation
import Security

enum TransferIdentityStoreError: Error, Equatable {
    case unavailable
}

protocol TransferIdentityStoring: Sendable {
    func identity() throws -> TransferIdentity
    func reset() throws
}

final class InMemoryTransferIdentityStore: TransferIdentityStoring, @unchecked Sendable {
    private var stored: TransferIdentity?

    func identity() throws -> TransferIdentity {
        if let stored { return stored }
        let identity = TransferIdentity.generate()
        stored = identity
        return identity
    }

    func reset() throws {
        stored = nil
    }
}

final class KeychainTransferIdentityStore: TransferIdentityStoring, @unchecked Sendable {
    private let service = "com.taotaoxiaoshuo.purevoice.web-transfer"
    private let account = "transfer-identity"

    func identity() throws -> TransferIdentity {
        if let existing = try read() { return existing }
        let generated = TransferIdentity.generate()
        try save(generated)
        return generated
    }

    func reset() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func read() throws -> TransferIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw TransferIdentityStoreError.unavailable
        }
        return try JSONDecoder().decode(TransferIdentity.self, from: data)
    }

    private func save(_ identity: TransferIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TransferIdentityStoreError.unavailable }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/TransferIdentityStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/WebTransfer/TransferIdentity.swift PureVoice/Features/WebTransfer/TransferIdentityStore.swift PureVoiceTests/TransferIdentityStoreTests.swift
git commit -m "feat: add transfer identity store"
```

---

### Task 6: iOS Web Transfer Client

**Files:**
- Create: `PureVoice/Features/WebTransfer/WebTransferModels.swift`
- Create: `PureVoice/Features/WebTransfer/WebTransferClient.swift`
- Create: `PureVoiceTests/WebTransferClientTests.swift`
- Modify: `PureVoice/Core/Models/UserFacingError.swift`

- [ ] **Step 1: Write failing client tests**

Create `PureVoiceTests/WebTransferClientTests.swift` with:

```swift
import XCTest
@testable import PureVoice

final class WebTransferClientTests: XCTestCase {
    func testRequestUsesDeviceHeaders() async throws {
        let transport = RecordingWebTransferTransport(data: #"{"items":[]}"#.data(using: .utf8)!)
        let client = URLSessionWebTransferClient(
            baseURL: URL(string: "https://example.com/functions/v1/transfer")!,
            transport: transport
        )
        let identity = TransferIdentity(deviceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, deviceSecret: "secret-secret-secret-secret-secret")

        _ = try await client.inbox(identity: identity)

        let request = try XCTUnwrap(await transport.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-transfer-device-id"), identity.deviceID.uuidString.lowercased())
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-transfer-device-secret"), identity.deviceSecret)
    }
}

private actor RecordingWebTransferTransport: WebTransferTransport {
    private(set) var lastRequest: URLRequest?
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/WebTransferClientTests
```

Expected: FAIL because client types do not exist.

- [ ] **Step 3: Implement models**

Create `PureVoice/Features/WebTransfer/WebTransferModels.swift`:

```swift
import Foundation

enum WebTransferError: Error, Equatable, Sendable {
    case server(String)
    case invalidResponse
    case downloadFailed
}

struct TransferPairingCode: Equatable, Decodable, Sendable {
    let code: String
    let expiresAt: Date
}

struct TransferInboxItem: Identifiable, Equatable, Decodable, Sendable {
    let id: UUID
    let filename: String
    let byteSize: Int64
    let format: String
    let createdAt: Date
    let expiresAt: Date
}

struct TransferInboxResponse: Decodable, Sendable {
    let items: [TransferInboxItem]
}

struct TransferDownloadURLResponse: Decodable, Sendable {
    let downloadUrl: URL
    let expiresInSeconds: Int
}

struct TransferRegisterResponse: Decodable, Sendable {
    let deviceId: UUID
    let registered: Bool
}

struct TransferStatusResponse: Decodable, Sendable {
    let status: String
}

struct TransferErrorResponse: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }
    let error: Payload
}
```

- [ ] **Step 4: Implement client**

Create `PureVoice/Features/WebTransfer/WebTransferClient.swift`:

```swift
import Foundation

protocol WebTransferTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: WebTransferTransport {}

protocol WebTransferClient: Sendable {
    func register(identity: TransferIdentity) async throws
    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode
    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem]
    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL
    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws
    func delete(uploadID: UUID, identity: TransferIdentity) async throws
    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL
}

struct URLSessionWebTransferClient: WebTransferClient {
    let baseURL: URL
    let transport: any WebTransferTransport
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init(baseURL: URL, transport: any WebTransferTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func register(identity: TransferIdentity) async throws {
        let body = ["deviceId": identity.deviceID.uuidString.lowercased(), "deviceSecret": identity.deviceSecret]
        _ = try await send(path: "device/register", method: "POST", identity: nil, body: body, response: TransferRegisterResponse.self)
    }

    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode {
        try await send(path: "pairing-code", method: "POST", identity: identity, body: Optional<String>.none, response: TransferPairingCode.self)
    }

    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem] {
        let response = try await send(path: "inbox", method: "GET", identity: identity, body: Optional<String>.none, response: TransferInboxResponse.self)
        return response.items
    }

    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL {
        let response = try await send(path: "uploads/\(uploadID.uuidString.lowercased())/download-url", method: "POST", identity: identity, body: Optional<String>.none, response: TransferDownloadURLResponse.self)
        return response.downloadUrl
    }

    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws {
        let body = ["importedBookId": importedBookID?.uuidString.lowercased() ?? ""]
        _ = try await send(path: "uploads/\(uploadID.uuidString.lowercased())/claim", method: "POST", identity: identity, body: body, response: TransferStatusResponse.self)
    }

    func delete(uploadID: UUID, identity: TransferIdentity) async throws {
        _ = try await send(path: "uploads/\(uploadID.uuidString.lowercased())", method: "DELETE", identity: identity, body: Optional<String>.none, response: TransferStatusResponse.self)
    }

    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await transport.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WebTransferError.downloadFailed }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("web-transfer-\(UUID().uuidString)-\(suggestedFilename)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        identity: TransferIdentity?,
        body: Body?,
        response: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let identity {
            request.setValue(identity.deviceID.uuidString.lowercased(), forHTTPHeaderField: "x-transfer-device-id")
            request.setValue(identity.deviceSecret, forHTTPHeaderField: "x-transfer-device-secret")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        let (data, urlResponse) = try await transport.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw WebTransferError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            if let decoded = try? decoder.decode(TransferErrorResponse.self, from: data) {
                throw WebTransferError.server(decoded.error.message)
            }
            throw WebTransferError.invalidResponse
        }
        return try decoder.decode(Response.self, from: data)
    }
}
```

- [ ] **Step 5: Add user-facing error mapping**

Append to `UserFacingError`:

```swift
init(webTransferError: WebTransferError) {
    switch webTransferError {
    case let .server(message):
        self = .init(title: "网站传书失败", message: message, recoveryAction: "稍后重试")
    case .invalidResponse:
        self = .init(title: "网站传书失败", message: "服务器返回内容无法识别。", recoveryAction: "稍后重试")
    case .downloadFailed:
        self = .init(title: "下载失败", message: "无法下载这本书。", recoveryAction: "检查网络后重试")
    }
}

init(transferIdentityError: TransferIdentityStoreError) {
    self = .init(title: "传书身份不可用", message: "无法读取本机传书身份。", recoveryAction: "重新打开 App 后重试")
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/WebTransferClientTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add PureVoice/Features/WebTransfer/WebTransferModels.swift PureVoice/Features/WebTransfer/WebTransferClient.swift PureVoice/Core/Models/UserFacingError.swift PureVoiceTests/WebTransferClientTests.swift
git commit -m "feat: add web transfer client"
```

---

### Task 7: iOS Web Transfer View Model

**Files:**
- Create: `PureVoice/Features/WebTransfer/WebTransferViewModel.swift`
- Create: `PureVoiceTests/WebTransferViewModelTests.swift`

- [ ] **Step 1: Write failing view model tests**

Create `PureVoiceTests/WebTransferViewModelTests.swift` with:

```swift
import XCTest
@testable import PureVoice

@MainActor
final class WebTransferViewModelTests: XCTestCase {
    func testGenerateCodeRegistersDeviceAndPublishesCode() async throws {
        let client = RecordingWebTransferClient()
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: nil
        )

        await viewModel.generateCode()

        XCTAssertEqual(viewModel.pairingCode?.code, "12345678")
        XCTAssertEqual(await client.registerCount, 1)
        XCTAssertEqual(await client.createCodeCount, 1)
    }

    func testImportSuccessClaimsUpload() async throws {
        let client = RecordingWebTransferClient()
        let importer = RecordingTransferImporter()
        let item = TransferInboxItem(
            id: UUID(),
            filename: "book.txt",
            byteSize: 12,
            format: "txt",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: importer
        )

        await viewModel.importItem(item)

        XCTAssertEqual(await importer.importCount, 1)
        XCTAssertEqual(await client.claimCount, 1)
    }
}

private actor RecordingTransferImporter: TransferImporting {
    private(set) var importCount = 0

    func importBook(from sourceURL: URL) async throws -> UUID? {
        importCount += 1
        return UUID()
    }
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/WebTransferViewModelTests
```

Expected: FAIL because `WebTransferViewModel` and test doubles do not exist.

- [ ] **Step 3: Implement importer adapter and view model**

Create `PureVoice/Features/WebTransfer/WebTransferViewModel.swift`:

```swift
import Foundation

protocol TransferImporting: Sendable {
    func importBook(from sourceURL: URL) async throws -> UUID?
}

struct ImportCoordinatorTransferImporter: TransferImporting {
    let coordinator: ImportCoordinator

    func importBook(from sourceURL: URL) async throws -> UUID? {
        try await coordinator.importBook(from: sourceURL)
        if case let .completed(bookID) = await coordinator.state {
            return bookID
        }
        return nil
    }
}

@MainActor
final class WebTransferViewModel: ObservableObject {
    @Published private(set) var pairingCode: TransferPairingCode?
    @Published private(set) var inbox: [TransferInboxItem] = []
    @Published private(set) var isBusy = false
    @Published var error: UserFacingError?

    private let identityStore: any TransferIdentityStoring
    private let client: any WebTransferClient
    private let importCoordinator: (any TransferImporting)?

    init(
        identityStore: any TransferIdentityStoring,
        client: any WebTransferClient,
        importCoordinator: (any TransferImporting)?
    ) {
        self.identityStore = identityStore
        self.client = client
        self.importCoordinator = importCoordinator
    }

    func generateCode() async {
        await run {
            let identity = try identityStore.identity()
            try await client.register(identity: identity)
            pairingCode = try await client.createPairingCode(identity: identity)
        }
    }

    func refreshInbox() async {
        await run {
            let identity = try identityStore.identity()
            inbox = try await client.inbox(identity: identity)
        }
    }

    func importItem(_ item: TransferInboxItem) async {
        guard let importCoordinator else {
            error = UserFacingError(title: "导入功能不可用", message: "当前无法导入网站传书文件。", recoveryAction: "稍后重试")
            return
        }
        await run {
            let identity = try identityStore.identity()
            let url = try await client.downloadURL(uploadID: item.id, identity: identity)
            let localURL = try await client.downloadFile(from: url, suggestedFilename: item.filename)
            let importedBookID = try await importCoordinator.importBook(from: localURL)
            try await client.claim(uploadID: item.id, identity: identity, importedBookID: importedBookID)
            inbox.removeAll { $0.id == item.id }
        }
    }

    func deleteItem(_ item: TransferInboxItem) async {
        await run {
            let identity = try identityStore.identity()
            try await client.delete(uploadID: item.id, identity: identity)
            inbox.removeAll { $0.id == item.id }
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch let identityError as TransferIdentityStoreError {
            error = UserFacingError(transferIdentityError: identityError)
        } catch let transferError as WebTransferError {
            error = UserFacingError(webTransferError: transferError)
        } catch {
            error = UserFacingError(title: "网站传书失败", message: "操作没有完成。", recoveryAction: "稍后重试")
        }
    }
}
```

- [ ] **Step 4: Add test double client**

Append to `PureVoiceTests/WebTransferViewModelTests.swift`:

```swift
private actor RecordingWebTransferClient: WebTransferClient {
    private(set) var registerCount = 0
    private(set) var createCodeCount = 0
    private(set) var claimCount = 0

    func register(identity: TransferIdentity) async throws {
        registerCount += 1
    }

    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode {
        createCodeCount += 1
        return TransferPairingCode(code: "12345678", expiresAt: Date().addingTimeInterval(600))
    }

    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem] {
        []
    }

    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL {
        URL(string: "https://example.com/book.txt")!
    }

    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws {
        claimCount += 1
    }

    func delete(uploadID: UUID, identity: TransferIdentity) async throws {}

    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/WebTransferViewModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add PureVoice/Features/WebTransfer/WebTransferViewModel.swift PureVoiceTests/WebTransferViewModelTests.swift
git commit -m "feat: add web transfer view model"
```

---

### Task 8: Import Tab UI And Dependency Injection

**Files:**
- Create: `PureVoice/Features/WebTransfer/WebTransferView.swift`
- Modify: `PureVoice/App/AppDependencies.swift`
- Modify: `PureVoice/App/RootTabView.swift`
- Modify: `PureVoice/Features/Import/ImportView.swift`
- Modify: `PureVoiceTests/AppDependenciesTests.swift`
- Create: `PureVoiceUITests/ImportWebTransferAccessibilityUITests.swift`

- [ ] **Step 1: Add dependency tests**

Append to `PureVoiceTests/AppDependenciesTests.swift`:

```swift
func testProductionDependenciesCreateWebTransferViewModel() async throws {
    let persistence = try await PersistenceController(storeDescription: Self.inMemoryStoreDescription())
    let fileStore = try BookFileStore(applicationSupportRoot: temporaryDirectory)

    let dependencies = await AppDependencies.production(
        persistence: persistence,
        fileStore: fileStore
    )

    await MainActor.run {
        XCTAssertNotNil(dependencies.webTransferViewModel)
    }
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/AppDependenciesTests/testProductionDependenciesCreateWebTransferViewModel
```

Expected: FAIL because `webTransferViewModel` is missing.

- [ ] **Step 3: Modify dependencies**

Update `PureVoice/App/AppDependencies.swift`:

```swift
@MainActor
struct AppDependencies {
    let repository: any BookRepository
    let importCoordinator: ImportCoordinator
    let webTransferViewModel: WebTransferViewModel
    let libraryRefresh: LibraryRefreshSignal
    let appStateRestorer: AppStateRestorer
}
```

Inside `AppDependencies.make(...)`, after creating `coordinator`, create:

```swift
let transferBaseURLString = ProcessInfo.processInfo.environment["PUREVOICE_WEB_TRANSFER_BASE_URL"] ?? ""
let transferBaseURL = URL(string: transferBaseURLString)
    ?? URL(string: "http://127.0.0.1:54321/functions/v1/transfer")!
let webTransferViewModel = WebTransferViewModel(
    identityStore: KeychainTransferIdentityStore(),
    client: URLSessionWebTransferClient(baseURL: transferBaseURL),
    importCoordinator: ImportCoordinatorTransferImporter(coordinator: coordinator)
)
```

And include `webTransferViewModel` in the returned `AppDependencies`.

- [ ] **Step 4: Create UI view**

Create `PureVoice/Features/WebTransfer/WebTransferView.swift`:

```swift
import SwiftUI

struct WebTransferView: View {
    @ObservedObject var viewModel: WebTransferViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("网站传书", systemImage: "globe")
                    .font(.headline)
                Spacer()
                Button("刷新") {
                    Task { await viewModel.refreshInbox() }
                }
                .disabled(viewModel.isBusy)
                .accessibilityHint("刷新待接收文件列表")
            }

            if let pairingCode = viewModel.pairingCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pairingCode.code)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("临时传书码 \(pairingCode.code.map(String.init).joined(separator: " "))")
                    Text("10 分钟内有效")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await viewModel.generateCode() }
            } label: {
                Label(viewModel.pairingCode == nil ? "生成传书码" : "重新生成传书码", systemImage: "number")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy)

            ForEach(viewModel.inbox) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.filename)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(item.format.uppercased()) · \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("导入") {
                        Task { await viewModel.importItem(item) }
                    }
                    .disabled(viewModel.isBusy)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.filename)，\(item.format.uppercased())，\(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("网站传书提示", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.message ?? "")
        }
    }
}
```

- [ ] **Step 5: Add view to Import tab**

Change `PureVoice/Features/Import/ImportView.swift` initializer:

```swift
struct ImportView: View {
    @ObservedObject var coordinator: ImportCoordinator
    @ObservedObject var webTransferViewModel: WebTransferViewModel
```

Inside the main `VStack`, after the local import button, insert:

```swift
WebTransferView(viewModel: webTransferViewModel)
```

Update `RootTabView` import tab:

```swift
ImportView(
    coordinator: importCoordinator,
    webTransferViewModel: webTransferViewModel
)
```

Add `webTransferViewModel` as a stored property passed through `RootTabView.init`.

- [ ] **Step 6: Add UI accessibility test**

Create `PureVoiceUITests/ImportWebTransferAccessibilityUITests.swift`:

```swift
import XCTest

final class ImportWebTransferAccessibilityUITests: XCTestCase {
    func testImportTabExposesWebTransferControls() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["导入"].tap()

        XCTAssertTrue(app.staticTexts["网站传书"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["生成传书码"].exists)
        XCTAssertTrue(app.buttons["刷新"].exists)
    }
}
```

- [ ] **Step 7: Run targeted tests**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests/AppDependenciesTests -only-testing:PureVoiceUITests/ImportWebTransferAccessibilityUITests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add PureVoice/App/AppDependencies.swift PureVoice/App/RootTabView.swift PureVoice/Features/Import/ImportView.swift PureVoice/Features/WebTransfer/WebTransferView.swift PureVoiceTests/AppDependenciesTests.swift PureVoiceUITests/ImportWebTransferAccessibilityUITests.swift
git commit -m "feat: add web transfer import ui"
```

---

### Task 9: End-To-End Local Verification

**Files:**
- Modify only files needed to fix failures found during verification.

- [ ] **Step 1: Run backend tests**

Run:

```bash
deno test --allow-env --allow-net --allow-read supabase/functions/transfer/transfer_test.ts
```

Expected: PASS.

- [ ] **Step 2: Run iOS focused tests**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PureVoiceTests/TransferIdentityStoreTests \
  -only-testing:PureVoiceTests/WebTransferClientTests \
  -only-testing:PureVoiceTests/WebTransferViewModelTests \
  -only-testing:PureVoiceTests/AppDependenciesTests
```

Expected: PASS.

- [ ] **Step 3: Run full unit test suite**

Run:

```bash
xcodebuild test -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PureVoiceTests
```

Expected: PASS.

- [ ] **Step 4: Run local Supabase smoke test**

Start local Supabase and function, then run:

```bash
DEVICE_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
DEVICE_SECRET="local-secret-local-secret-local-secret"

curl -s -X POST "http://127.0.0.1:54321/functions/v1/transfer/device/register" \
  -H "content-type: application/json" \
  -d "{\"deviceId\":\"$DEVICE_ID\",\"deviceSecret\":\"$DEVICE_SECRET\"}"

CODE_RESPONSE="$(curl -s -X POST "http://127.0.0.1:54321/functions/v1/transfer/pairing-code" \
  -H "x-transfer-device-id: $DEVICE_ID" \
  -H "x-transfer-device-secret: $DEVICE_SECRET")"

echo "$CODE_RESPONSE"
```

Expected: first response has `"registered":true`; second response has an 8 digit `code`.

- [ ] **Step 5: Run app in simulator**

Run:

```bash
xcodebuild build -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: build succeeds. Launch the app, open 导入, and verify the 网站传书 section renders without covering the tab bar.

- [ ] **Step 6: Commit verification fixes**

If verification required fixes:

```bash
git add PureVoice supabase docs/superpowers/plans/2026-07-22-web-transfer.md
git commit -m "fix: stabilize web transfer verification"
```

If no fixes were needed, skip this commit.

---

## Implementation Notes

- Do not commit `supabase/.env.local` or any Supabase secret.
- Keep the production function URL configurable; do not hardcode a real project URL until deployment credentials are known.
- The default allowed formats are TXT and EPUB because local MOBI import is still gated. When MOBI support lands, change `WEB_TRANSFER_ALLOWED_FORMATS` to `txt,epub,mobi`, update the web file picker accept list, and add a MOBI end-to-end test.
- Keep App-side VoiceOver labels explicit on the transfer code and inbox actions.
- Keep upload cleanup idempotent; repeated cleanup runs must not fail if a Storage object is already gone.
