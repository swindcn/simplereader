import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./transfer.js", import.meta.url), "utf8");

function loadTransferModule() {
  const sandbox = {
    console,
    setTimeout,
    clearInterval,
    setInterval,
    localStorage: {
      getItem() { return null; },
      setItem() {},
    },
    document: {
      readyState: "loading",
      documentElement: { lang: "en" },
      addEventListener() {},
      getElementById() { return null; },
    },
    window: {
      I18N: {
        en: {
          "transfer.verifyFail": "Device not found. Check the code.",
        },
      },
    },
    FormData,
  };
  sandbox.window.document = sandbox.document;
  sandbox.window.localStorage = sandbox.localStorage;
  vm.runInNewContext(source, sandbox, { filename: "transfer.js" });
  return sandbox.window.LucidReadTransferInternals;
}

const transfer = loadTransferModule();

assert.ok(transfer, "transfer internals should be exposed for behavior tests");

{
  const calls = [];
  const client = transfer.createTransferClient({
    apiBase: "https://example.supabase.co/functions/v1",
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return {
        ok: true,
        json: async () => ({
          uploadSessionId: "session-1",
          dailyUploadLimit: 999,
          dailyUploadRemaining: 998,
        }),
      };
    },
  });

  const result = await client.verifyDevice("19323438");

  assert.deepEqual(result, {
    ok: true,
    uploadSessionId: "session-1",
    dailyUploadLimit: 999,
    dailyUploadRemaining: 998,
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://example.supabase.co/functions/v1/transfer/web/resolve-code");
  assert.equal(calls[0].init.method, "POST");
  assert.equal(calls[0].init.headers["Content-Type"], "application/json");
  assert.equal(JSON.parse(calls[0].init.body).code, "19323438");
}

{
  const calls = [];
  const client = transfer.createTransferClient({
    apiBase: "https://example.supabase.co/functions/v1",
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return {
        ok: true,
        json: async () => ({ uploadId: "upload-1", filename: "book.epub" }),
      };
    },
  });
  const file = new Blob(["book"], { type: "application/epub+zip" });

  const result = await client.uploadBook("session-1", file);

  assert.equal(result.ok, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://example.supabase.co/functions/v1/transfer/web/upload");
  assert.equal(calls[0].init.method, "POST");
  assert.equal(calls[0].init.body.get("uploadSessionId"), "session-1");
  const uploadedFile = calls[0].init.body.get("file");
  assert.equal(uploadedFile.size, file.size);
  assert.equal(uploadedFile.type, file.type);
}

assert.equal(transfer.uploadProgress(0, 4).value, 0);
assert.equal(transfer.uploadProgress(0, 4).text, "0%");
assert.equal(transfer.uploadProgress(2, 4).value, 50);
assert.equal(transfer.uploadProgress(2, 4).text, "50%");
assert.equal(transfer.uploadProgress(4, 4).value, 100);
assert.equal(transfer.uploadProgress(4, 4).text, "100%");
