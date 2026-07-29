import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./i18n.js", import.meta.url), "utf8");

function runI18n({ storedLang = null, browserLang = "zh-CN" } = {}) {
  const documentElement = { lang: "" };
  const sandbox = {
    window: {},
    navigator: { language: browserLang },
    localStorage: {
      getItem(key) {
        return key === "lang" ? storedLang : null;
      },
      setItem() {},
    },
    document: {
      documentElement,
      querySelectorAll() { return []; },
      getElementById() { return null; },
      addEventListener() {},
    },
  };
  sandbox.window.navigator = sandbox.navigator;
  sandbox.window.localStorage = sandbox.localStorage;
  sandbox.window.document = sandbox.document;
  vm.runInNewContext(source, sandbox, { filename: "i18n.js" });
  return documentElement.lang;
}

assert.equal(runI18n({ storedLang: null, browserLang: "zh-CN" }), "en");
assert.equal(runI18n({ storedLang: null, browserLang: "en-US" }), "en");
assert.equal(runI18n({ storedLang: "zh", browserLang: "en-US" }), "zh-CN");
assert.equal(runI18n({ storedLang: "en", browserLang: "zh-CN" }), "en");
