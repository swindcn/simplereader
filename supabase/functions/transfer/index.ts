import {
  allowedFormatsFromEnv,
  detectTransferFormat,
  DOWNLOAD_URL_TTL_SECONDS,
  hasExpired,
  json,
  jsonError,
  normalizeFilename,
  optionsResponse,
  parseDeviceAuth,
  serviceClient,
  sha256Hex,
  storagePathForUpload,
  UPLOAD_SESSION_TTL_SECONDS,
  UPLOAD_TTL_HOURS,
  validateUploadSize,
  verificationPenaltySeconds,
  WEB_TRANSFER_DAILY_UPLOAD_LIMIT,
} from "../_shared/transfer.ts";
import { webTransferPageHtml } from "../transfer-web/html.ts";

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
  if (
    method === "GET" &&
    (path === "" || path === "/transfer" || path === "/transfer/web")
  ) return "webPage";
  if (method === "POST" && path === "/transfer/device/register") {
    return "registerDevice";
  }
  if (method === "POST" && path === "/transfer/pairing-code") {
    return "createPairingCode";
  }
  if (method === "POST" && path === "/transfer/web/resolve-code") {
    return "resolveCode";
  }
  if (method === "POST" && path === "/transfer/web/upload") return "webUpload";
  if (method === "GET" && path === "/transfer/inbox") return "inbox";
  if (
    method === "POST" && /^\/transfer\/uploads\/[^/]+\/download-url$/.test(path)
  ) return "downloadUrl";
  if (method === "POST" && /^\/transfer\/uploads\/[^/]+\/claim$/.test(path)) {
    return "claim";
  }
  if (method === "DELETE" && /^\/transfer\/uploads\/[^/]+$/.test(path)) {
    return "deleteUpload";
  }
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

function secondsUntil(isoValue: string): number {
  return Math.max(
    1,
    Math.ceil((new Date(isoValue).getTime() - Date.now()) / 1000),
  );
}

function utcDayStartISO(): string {
  const now = new Date();
  now.setUTCHours(0, 0, 0, 0);
  return now.toISOString();
}

async function requestClientKeyHash(request: Request): Promise<string> {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]
    ?.trim();
  const clientIP = request.headers.get("cf-connecting-ip") ?? forwarded ??
    "unknown";
  const userAgent = request.headers.get("user-agent") ?? "unknown";
  return await sha256Hex(`${clientIP}|${userAgent}`);
}

function generateCode(): string {
  return String(crypto.getRandomValues(new Uint32Array(1))[0] % 100_000_000)
    .padStart(8, "0");
}

async function assertDevice(
  supabase: ReturnType<typeof serviceClient>,
  request: Request,
) {
  const auth = parseDeviceAuth(request);
  const secretHash = await sha256Hex(auth.deviceSecret);
  const { data, error } = await supabase
    .from("transfer_devices")
    .select("id")
    .eq("id", auth.deviceId)
    .eq("secret_hash", secretHash)
    .is("disabled_at", null)
    .maybeSingle();
  if (error || !data) {
    throw jsonError(401, "invalid_device_auth", "设备传书身份无效。");
  }
  await supabase.from("transfer_devices").update({
    last_seen_at: new Date().toISOString(),
  }).eq("id", auth.deviceId);
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
  const body = await request.json().catch(() => ({}));
  const requestedCode = String(body.code ?? "").trim();
  if (/^[0-9]{8}$/.test(requestedCode)) {
    const requestedCodeHash = await sha256Hex(requestedCode);
    const { data: existingRequestedCode, error: requestedReadError } =
      await supabase
        .from("transfer_pairing_codes")
        .select("device_id")
        .eq("code_hash", requestedCodeHash)
        .is("revoked_at", null)
        .maybeSingle();
    if (requestedReadError) {
      return jsonError(500, "pairing_failed", "生成传书码失败。");
    }
    if (existingRequestedCode?.device_id === auth.deviceId) {
      return json({ code: requestedCode, expiresAt: null });
    }
    if (!existingRequestedCode) {
      await supabase.from("transfer_pairing_codes").update({
        revoked_at: new Date().toISOString(),
      }).eq("device_id", auth.deviceId).is("revoked_at", null);
      const { error } = await supabase.from("transfer_pairing_codes").insert({
        device_id: auth.deviceId,
        code_hash: requestedCodeHash,
        expires_at: null,
      });
      if (error) return jsonError(500, "pairing_failed", "生成传书码失败。");
      return json({ code: requestedCode, expiresAt: null });
    }
  }
  await supabase.from("transfer_pairing_codes").update({
    revoked_at: new Date().toISOString(),
  }).eq("device_id", auth.deviceId).is("revoked_at", null);
  const code = generateCode();
  const { error } = await supabase.from("transfer_pairing_codes").insert({
    device_id: auth.deviceId,
    code_hash: await sha256Hex(code),
    expires_at: null,
  });
  if (error) return jsonError(500, "pairing_failed", "生成传书码失败。");
  return json({ code });
}

async function enforceResolveRateLimit(
  supabase: ReturnType<typeof serviceClient>,
  request: Request,
): Promise<void> {
  const clientKeyHash = await requestClientKeyHash(request);
  const now = new Date();
  const { data: existing, error: readError } = await supabase
    .from("transfer_verification_limits")
    .select(
      "client_key_hash, minute_attempt_count, minute_window_started_at, hour_attempt_count, hour_window_started_at, penalty_until",
    )
    .eq("client_key_hash", clientKeyHash)
    .maybeSingle();
  if (readError) {
    console.error("transfer_rate_limit_read_failed", readError);
    throw jsonError(500, "rate_limit_failed", "验证服务暂不可用。");
  }

  if (
    existing?.penalty_until &&
    new Date(existing.penalty_until).getTime() > now.getTime()
  ) {
    const retryAfter = secondsUntil(existing.penalty_until);
    throw jsonError(
      429,
      "verification_locked",
      `验证过于频繁，请 ${retryAfter} 秒后再试。`,
      { "retry-after": String(retryAfter) },
    );
  }

  const minuteWindowStartedAt = existing?.minute_window_started_at
    ? new Date(existing.minute_window_started_at)
    : now;
  const hourWindowStartedAt = existing?.hour_window_started_at
    ? new Date(existing.hour_window_started_at)
    : now;
  const resetsMinute =
    now.getTime() - minuteWindowStartedAt.getTime() > 60 * 1000;
  const resetsHour =
    now.getTime() - hourWindowStartedAt.getTime() > 60 * 60 * 1000;
  const minuteAttemptCount = resetsMinute
    ? 1
    : Number(existing?.minute_attempt_count ?? 0) + 1;
  const hourAttemptCount = resetsHour
    ? 1
    : Number(existing?.hour_attempt_count ?? 0) + 1;
  const penaltySeconds = hourAttemptCount >= 5
    ? verificationPenaltySeconds(5)
    : verificationPenaltySeconds(minuteAttemptCount);
  const penaltyUntil = penaltySeconds > 0
    ? new Date(now.getTime() + penaltySeconds * 1000).toISOString()
    : null;

  const { error: writeError } = await supabase
    .from("transfer_verification_limits")
    .upsert({
      client_key_hash: clientKeyHash,
      minute_attempt_count: minuteAttemptCount,
      minute_window_started_at: resetsMinute
        ? now.toISOString()
        : existing?.minute_window_started_at ?? now.toISOString(),
      hour_attempt_count: hourAttemptCount,
      hour_window_started_at: resetsHour
        ? now.toISOString()
        : existing?.hour_window_started_at ?? now.toISOString(),
      last_attempt_at: now.toISOString(),
      penalty_until: penaltyUntil,
    });
  if (writeError) {
    console.error("transfer_rate_limit_write_failed", writeError);
    throw jsonError(500, "rate_limit_failed", "验证服务暂不可用。");
  }

  if (penaltySeconds > 0) {
    throw jsonError(
      429,
      "verification_locked",
      `验证过于频繁，请 ${penaltySeconds} 秒后再试。`,
      { "retry-after": String(penaltySeconds) },
    );
  }
}

async function countUploadsToday(
  supabase: ReturnType<typeof serviceClient>,
  deviceId: string,
): Promise<number> {
  const { count, error } = await supabase
    .from("transfer_uploads")
    .select("id", { count: "exact", head: true })
    .eq("device_id", deviceId)
    .neq("status", "failed")
    .gte("created_at", utcDayStartISO());
  if (error) {
    console.error("transfer_daily_count_failed", error);
    throw jsonError(500, "daily_limit_failed", "读取今日上传额度失败。");
  }
  return count ?? 0;
}

async function resolveCode(request: Request): Promise<Response> {
  const { code } = await request.json();
  const supabase = serviceClient();
  await enforceResolveRateLimit(supabase, request);
  const codeHash = await sha256Hex(String(code ?? "").trim());
  const { data, error } = await supabase
    .from("transfer_pairing_codes")
    .select("id, device_id, expires_at, attempt_count")
    .eq("code_hash", codeHash)
    .is("revoked_at", null)
    .maybeSingle();
  if (error || !data) {
    return jsonError(404, "code_not_found", "传书码不存在或已失效。");
  }
  if (data.attempt_count >= 5) {
    return jsonError(429, "too_many_attempts", "传书码尝试次数过多。");
  }
  const expiresAt = expiresIn(UPLOAD_SESSION_TTL_SECONDS);
  const { data: session, error: sessionError } = await supabase.from(
    "transfer_upload_sessions",
  ).insert({
    device_id: data.device_id,
    pairing_code_id: data.id,
    expires_at: expiresAt,
  }).select("id, expires_at").single();
  if (sessionError) {
    return jsonError(500, "session_failed", "创建上传会话失败。");
  }
  const uploadedToday = await countUploadsToday(supabase, data.device_id);
  return json({
    uploadSessionId: session.id,
    expiresAt: session.expires_at,
    dailyUploadLimit: WEB_TRANSFER_DAILY_UPLOAD_LIMIT,
    dailyUploadRemaining: Math.max(
      0,
      WEB_TRANSFER_DAILY_UPLOAD_LIMIT - uploadedToday,
    ),
  });
}

async function webUpload(request: Request): Promise<Response> {
  const form = await request.formData();
  const uploadSessionId = String(form.get("uploadSessionId") ?? "");
  const file = form.get("file");
  if (!(file instanceof File)) {
    return jsonError(400, "missing_file", "请选择要上传的文件。");
  }
  validateUploadSize(file.size);
  const filename = normalizeFilename(file.name);
  const format = detectTransferFormat(
    filename,
    file.type,
    allowedFormatsFromEnv(),
  );
  const supabase = serviceClient();
  const { data: session, error: sessionError } = await supabase
    .from("transfer_upload_sessions")
    .select("id, device_id, expires_at")
    .eq("id", uploadSessionId)
    .is("revoked_at", null)
    .maybeSingle();
  if (sessionError || !session || hasExpired(session.expires_at)) {
    return jsonError(401, "upload_session_expired", "上传会话已过期。");
  }
  const uploadedToday = await countUploadsToday(supabase, session.device_id);
  if (uploadedToday >= WEB_TRANSFER_DAILY_UPLOAD_LIMIT) {
    return jsonError(
      429,
      "daily_upload_limit_reached",
      "今天上传数量已达测试上限，请明天再试。",
      { "retry-after": String(24 * 60 * 60) },
    );
  }
  const uploadId = crypto.randomUUID();
  const storagePath = storagePathForUpload(session.device_id, uploadId, format);
  const bytes = new Uint8Array(await file.arrayBuffer());
  const storage = await supabase.storage.from("web-transfer").upload(
    storagePath,
    bytes,
    {
      contentType: file.type || "application/octet-stream",
      upsert: false,
    },
  );
  if (storage.error) {
    console.error("transfer_storage_upload_failed", {
      statusCode: storage.error.statusCode,
      message: storage.error.message,
      filename,
      byteSize: file.size,
      contentType: file.type || "application/octet-stream",
    });
    return jsonError(
      500,
      "upload_failed",
      "文件上传失败，请稍后重试或换用更小的文件。",
    );
  }
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

async function downloadUrl(
  request: Request,
  uploadId: string,
): Promise<Response> {
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
  if (error || !data) {
    return jsonError(404, "upload_not_found", "文件不存在或已过期。");
  }
  const signed = await supabase.storage.from("web-transfer").createSignedUrl(
    data.storage_path,
    DOWNLOAD_URL_TTL_SECONDS,
  );
  if (signed.error) {
    return jsonError(500, "signed_url_failed", "生成下载链接失败。");
  }
  return json({
    downloadUrl: signed.data.signedUrl,
    expiresInSeconds: DOWNLOAD_URL_TTL_SECONDS,
  });
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
  if (error || !data) {
    return jsonError(404, "upload_not_found", "文件不存在或已过期。");
  }
  await supabase.storage.from("web-transfer").remove([data.storage_path]);
  return json({ status: "claimed" });
}

async function deleteUpload(
  request: Request,
  uploadId: string,
): Promise<Response> {
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
  if (error || !data) {
    return jsonError(404, "upload_not_found", "文件不存在或已过期。");
  }
  await supabase.storage.from("web-transfer").remove([data.storage_path]);
  return json({ status: "deleted" });
}

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return optionsResponse();
  const url = new URL(request.url);
  try {
    switch (routeName(url, request.method)) {
      case "registerDevice":
        return await registerDevice(request);
      case "createPairingCode":
        return await createPairingCode(request);
      case "resolveCode":
        return await resolveCode(request);
      case "webUpload":
        return await webUpload(request);
      case "inbox":
        return await inbox(request);
      case "downloadUrl":
        return await downloadUrl(request, uploadIdFromPath(url.pathname));
      case "claim":
        return await claim(request, uploadIdFromPath(url.pathname));
      case "deleteUpload":
        return await deleteUpload(request, uploadIdFromPath(url.pathname));
      case "webPage":
        return new Response(webTransferPageHtml, {
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store",
          },
        });
      case "notFound":
        return jsonError(404, "not_found", "接口不存在。");
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
