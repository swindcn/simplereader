import {
  detectTransferFormat,
  hasExpired,
  jsonError,
  normalizeFilename,
  parseDeviceAuth,
  validateUploadSize,
} from "../_shared/transfer.ts";
import { routeName } from "./index.ts";

Deno.test("detectTransferFormat accepts txt and epub by default", () => {
  const allowed = new Set(["txt", "epub"]);
  if (detectTransferFormat("故事.TXT", "text/plain", allowed) !== "txt") {
    throw new Error("txt rejected");
  }
  if (
    detectTransferFormat("book.epub", "application/epub+zip", allowed) !==
      "epub"
  ) throw new Error("epub rejected");
});

Deno.test("detectTransferFormat rejects mobi", () => {
  const allowed = new Set(["txt", "epub"]);
  try {
    detectTransferFormat(
      "book.mobi",
      "application/x-mobipocket-ebook",
      allowed,
    );
    throw new Error("mobi accepted");
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

Deno.test("hasExpired treats missing expiry as long-term valid", () => {
  if (hasExpired(null)) throw new Error("null expiry should not expire");
  if (hasExpired(undefined)) {
    throw new Error("missing expiry should not expire");
  }
  if (!hasExpired(new Date(Date.now() - 1_000).toISOString())) {
    throw new Error("past expiry accepted");
  }
});

Deno.test("parseDeviceAuth reads required headers", () => {
  const request = new Request("http://localhost", {
    headers: {
      "x-transfer-device-id": "11111111-1111-4111-8111-111111111111",
      "x-transfer-device-secret": "secret-secret-secret-secret-secret",
    },
  });
  const auth = parseDeviceAuth(request);
  if (auth.deviceId !== "11111111-1111-4111-8111-111111111111") {
    throw new Error("bad id");
  }
  if (auth.deviceSecret !== "secret-secret-secret-secret-secret") {
    throw new Error("bad secret");
  }
});

Deno.test("jsonError returns stable payload", async () => {
  const response = jsonError(400, "bad_code", "传书码无效");
  const body = await response.json();
  if (body.error.code !== "bad_code") throw new Error(JSON.stringify(body));
});

Deno.test("routeName maps transfer endpoints", () => {
  if (
    routeName(new URL("http://local/transfer/device/register"), "POST") !==
      "registerDevice"
  ) throw new Error("register");
  if (
    routeName(new URL("http://local/transfer/pairing-code"), "POST") !==
      "createPairingCode"
  ) throw new Error("pairing");
  if (routeName(new URL("http://local/transfer/inbox"), "GET") !== "inbox") {
    throw new Error("inbox");
  }
  if (
    routeName(
      new URL("http://local/transfer/uploads/abc/download-url"),
      "POST",
    ) !== "downloadUrl"
  ) throw new Error("download");
  if (
    routeName(new URL("http://local/transfer/uploads/abc/claim"), "POST") !==
      "claim"
  ) throw new Error("claim");
  if (
    routeName(new URL("http://local/transfer/uploads/abc"), "DELETE") !==
      "deleteUpload"
  ) throw new Error("delete");
  if (
    routeName(new URL("http://local/transfer/web/resolve-code"), "POST") !==
      "resolveCode"
  ) throw new Error("resolve");
  if (
    routeName(new URL("http://local/transfer/web/upload"), "POST") !==
      "webUpload"
  ) throw new Error("upload");
});
