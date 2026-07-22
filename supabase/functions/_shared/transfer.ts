// deno-lint-ignore-file no-import-prefix
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.53.0";

export const MAX_UPLOAD_BYTES = 262_144_000;
export const UPLOAD_SESSION_TTL_SECONDS = 30 * 60;
export const UPLOAD_TTL_HOURS = 72;
export const DOWNLOAD_URL_TTL_SECONDS = 300;

export type TransferFormat = "txt" | "epub";

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
      "access-control-allow-headers":
        "content-type,x-transfer-device-id,x-transfer-device-secret",
    },
  });
}

export function jsonError(
  status: number,
  code: string,
  message: string,
): Response {
  return json({ error: { code, message } }, status);
}

export function optionsResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
      "access-control-allow-headers":
        "content-type,x-transfer-device-id,x-transfer-device-secret",
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
  // deno-lint-ignore no-control-regex
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

export function hasExpired(isoValue: string | null | undefined): boolean {
  if (!isoValue) return false;
  return new Date(isoValue).getTime() <= Date.now();
}

export function detectTransferFormat(
  filename: string,
  mimeType: string,
  allowedFormats: Set<string>,
): TransferFormat {
  const extension = filename.split(".").pop()?.toLowerCase() ?? "";
  const normalizedMime = mimeType.toLowerCase();
  const extensionFormat = extension === "txt"
    ? "txt"
    : extension === "epub"
    ? "epub"
    : "";
  const mimeFormat = normalizedMime.includes("epub")
    ? "epub"
    : normalizedMime.startsWith("text/")
    ? "txt"
    : "";
  const format = extensionFormat || mimeFormat;
  if ((format === "txt" || format === "epub") && allowedFormats.has(format)) {
    return format;
  }
  throw jsonError(415, "unsupported_format", "当前网站传书支持 TXT 和 EPUB。");
}

export function allowedFormatsFromEnv(): Set<string> {
  const raw = Deno.env.get("WEB_TRANSFER_ALLOWED_FORMATS") ?? "txt,epub";
  return new Set(
    raw.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean),
  );
}

export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw jsonError(500, "server_not_configured", "传书服务暂不可用。");
  }
  return createClient(url, key, { auth: { persistSession: false } });
}
