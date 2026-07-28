/* ============================================================
 * LucidRead — Website Transfer (传书) logic
 * ------------------------------------------------------------
 * Front-end implementation wired to the LucidRead Supabase
 * transfer Edge Function.
 * ============================================================ */
(function () {
  "use strict";

  var CONFIG = {
    useBackend: true,
    apiBase: "https://nzksxspznpkquybprqms.supabase.co/functions/v1",
    maxFileBytes: 250 * 1024 * 1024,         // 250 MB
    allowedExt: ["txt", "epub"],
    rateLimit: { max: 3, windowMs: 60 * 1000 }, // 3 verifications / minute
    recentKeyPrefix: "lr_transfer_recent::",
    rateKey: "lr_transfer_verify_ts"
  };

  /* ---------- i18n helpers (reads window.I18N set by i18n.js) ---------- */
  function currentLang() {
    var l = (document.documentElement.lang || "en").toLowerCase();
    return l.indexOf("zh") === 0 ? "zh" : "en";
  }
  function dict() { return (window.I18N && window.I18N[currentLang()]) || {}; }
  function t(key, vars) {
    var s = dict()[key] || key;
    if (vars) { for (var k in vars) { s = s.split("{" + k + "}").join(vars[k]); } }
    return s;
  }

  function apiPath(base, path) {
    return String(base || "").replace(/\/+$/, "") + path;
  }

  function errorFromResponse(response, payload) {
    var message = payload && payload.error && payload.error.message;
    var error = new Error(message || "request_failed");
    error.status = response.status;
    error.retryAfter = response.headers && response.headers.get
      ? response.headers.get("retry-after")
      : null;
    return error;
  }

  function createTransferClient(options) {
    var apiBase = options.apiBase;
    var fetchImpl = options.fetchImpl || fetch;
    return {
      verifyDevice: function (code) {
        return fetchImpl(apiPath(apiBase, "/transfer/web/resolve-code"), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ code: code }),
        }).then(function (response) {
          return response.json().catch(function () { return {}; }).then(function (payload) {
            if (!response.ok) throw errorFromResponse(response, payload);
            payload.ok = true;
            return payload;
          });
        });
      },
      uploadBook: function (uploadSessionId, file) {
        var form = new FormData();
        form.append("uploadSessionId", uploadSessionId);
        form.append("file", file);
        return fetchImpl(apiPath(apiBase, "/transfer/web/upload"), {
          method: "POST",
          body: form,
        }).then(function (response) {
          return response.json().catch(function () { return {}; }).then(function (payload) {
            if (!response.ok) throw errorFromResponse(response, payload);
            payload.ok = true;
            return payload;
          });
        });
      },
    };
  }

  var transferClient = createTransferClient({
    apiBase: CONFIG.apiBase,
    fetchImpl: function () { return fetch.apply(null, arguments); },
  });

  function verifyDeviceApi(code) {
    if (CONFIG.useBackend) return transferClient.verifyDevice(code);
    return Promise.resolve({ ok: true, uploadSessionId: "demo" });
  }

  function uploadBookApi(uploadSessionId, file) {
    if (CONFIG.useBackend) return transferClient.uploadBook(uploadSessionId, file);
    return Promise.resolve({ ok: true, id: "demo_" + Date.now() });
  }

  /* ---------- anti-spam: rate limit verifications ---------- */
  function getAttempts() {
    try { return JSON.parse(localStorage.getItem(CONFIG.rateKey) || "[]"); } catch (e) { return []; }
  }
  function freshAttempts() {
    var now = Date.now();
    return getAttempts().filter(function (ts) { return now - ts < CONFIG.rateLimit.windowMs; });
  }
  function recordAttempt() {
    var a = freshAttempts();
    a.push(Date.now());
    try { localStorage.setItem(CONFIG.rateKey, JSON.stringify(a)); } catch (e) {}
    return a;
  }
  function remainingAttempts() { return Math.max(0, CONFIG.rateLimit.max - freshAttempts().length); }
  function cooldownMs() {
    var a = freshAttempts();
    if (a.length < CONFIG.rateLimit.max) return 0;
    return a[0] + CONFIG.rateLimit.windowMs - Date.now();
  }

  /* ---------- state ---------- */
  var state = { verified: false, code: "", uploadSessionId: "", files: [] };
  var cooldownActive = false, cooldownTimer = null;
  var el = {};

  /* ---------- helpers ---------- */
  function setStatus(node, msg, kind) {
    if (!node) return;
    node.textContent = msg || "";
    node.className = "transfer-status" + (kind ? " " + kind : "");
  }
  function formatSize(bytes) {
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB";
    return bytes + " B";
  }
  function recentKey() { return CONFIG.recentKeyPrefix + (state.code || ""); }
  function loadRecent() {
    try { return JSON.parse(localStorage.getItem(recentKey()) || "[]"); } catch (e) { return []; }
  }
  function addRecent(file, status) {
    var list = loadRecent();
    list.unshift({ name: file.name, size: file.size, time: Date.now(), status: status });
    list = list.slice(0, 20);
    try { localStorage.setItem(recentKey(), JSON.stringify(list)); } catch (e) {}
  }

  /* ---------- rate-limit UI ---------- */
  function updateRateUI() {
    if (!el.rateRemaining) return;
    var left = remainingAttempts();
    el.rateRemaining.textContent = "(" + left + ")";
  }
  function startCooldown(serverMs) {
    cooldownActive = true;
    el.verifyBtn.disabled = true;
    var serverUntil = serverMs ? Date.now() + serverMs : 0;
    function tick() {
      var ms = Math.max(cooldownMs(), serverUntil - Date.now());
      if (ms <= 0) {
        cooldownActive = false;
        el.verifyBtn.disabled = false;
        if (cooldownTimer) { clearInterval(cooldownTimer); cooldownTimer = null; }
        updateRateUI();
        setStatus(el.verifyStatus, "", "");
        return;
      }
      var s = Math.ceil(ms / 1000);
      setStatus(el.verifyStatus, t("transfer.rateLimited", { s: s }), "error");
    }
    tick();
    cooldownTimer = setInterval(tick, 1000);
  }

  /* ---------- verify ---------- */
  function onVerify() {
    if (cooldownActive) return;
    var code = el.codeInput.value.trim();
    if (!/^[0-9]{8}$/.test(code)) {
      setStatus(el.verifyStatus, t("transfer.verifyFail"), "error");
      return;
    }
    if (remainingAttempts() <= 0) { startCooldown(); return; }
    recordAttempt();
    el.verifyBtn.disabled = true;
    setStatus(el.verifyStatus, "…", "info");
    verifyDeviceApi(code).then(function (r) {
      el.verifyBtn.disabled = false;
      updateRateUI();
      if (r && r.ok) {
        state.verified = true;
        state.code = code;
        state.uploadSessionId = r.uploadSessionId || "";
        unlockUpload();
        setStatus(el.verifyStatus, t("transfer.verifyOk"), "ok");
        renderRecent();
      } else {
        setStatus(el.verifyStatus, t("transfer.verifyFail"), "error");
      }
    }).catch(function (error) {
      el.verifyBtn.disabled = false;
      updateRateUI();
      if (error && error.retryAfter) startCooldown(Number(error.retryAfter) * 1000);
      setStatus(el.verifyStatus, (error && error.message) || t("transfer.verifyFail"), "error");
    });
  }

  function unlockUpload() {
    el.stepUpload.classList.remove("transfer-step-locked");
    updateUploadBtn();
  }

  /* ---------- files ---------- */
  function addFiles(fileList) {
    if (!state.verified) {
      setStatus(el.uploadStatus, t("transfer.needVerify"), "error");
      return;
    }
    Array.prototype.forEach.call(fileList, function (f) {
      var ext = (f.name.split(".").pop() || "").toLowerCase();
      if (CONFIG.allowedExt.indexOf(ext) === -1) {
        setStatus(el.uploadStatus, t("transfer.fileBadType", { name: f.name }), "error");
        return;
      }
      if (f.size > CONFIG.maxFileBytes) {
        setStatus(el.uploadStatus, t("transfer.fileTooBig", { name: f.name }), "error");
        return;
      }
      state.files.push(f);
    });
    renderFiles();
    updateUploadBtn();
  }

  function renderFiles() {
    el.fileList.innerHTML = "";
    state.files.forEach(function (f, i) {
      var li = document.createElement("li");
      li.className = "file-item";
      var name = document.createElement("span");
      name.className = "file-name";
      name.textContent = f.name;
      var meta = document.createElement("span");
      meta.className = "file-meta";
      meta.textContent = formatSize(f.size);
      var rm = document.createElement("button");
      rm.type = "button";
      rm.className = "file-remove";
      rm.setAttribute("aria-label", "Remove");
      rm.textContent = "×";
      rm.addEventListener("click", function () {
        state.files.splice(i, 1);
        renderFiles();
        updateUploadBtn();
      });
      li.appendChild(name);
      li.appendChild(meta);
      li.appendChild(rm);
      el.fileList.appendChild(li);
    });
  }

  function updateUploadBtn() {
    el.uploadBtn.disabled = !(state.verified && state.files.length);
  }

  function onUpload() {
    if (!state.verified) { setStatus(el.uploadStatus, t("transfer.needVerify"), "error"); return; }
    if (!state.files.length) return;
    el.uploadBtn.disabled = true;
    var pending = state.files.slice();
    state.files = [];
    renderFiles();
    function next() {
      if (!pending.length) { updateUploadBtn(); return; }
      var f = pending.shift();
      uploadBookApi(state.uploadSessionId, f).then(function (r) {
        addRecent(f, r && r.ok ? "ok" : "fail");
        setStatus(el.uploadStatus, t((r && r.ok) ? "transfer.uploadOk" : "transfer.uploadFail", { name: f.name }), (r && r.ok) ? "ok" : "error");
        renderRecent();
        next();
      }).catch(function (error) {
        addRecent(f, "fail");
        setStatus(el.uploadStatus, (error && error.message) || t("transfer.uploadFail", { name: f.name }), "error");
        renderRecent();
        next();
      });
    }
    next();
  }

  window.LucidReadTransferInternals = {
    CONFIG: CONFIG,
    createTransferClient: createTransferClient,
  };

  /* ---------- recent list ---------- */
  function renderRecent() {
    var list = loadRecent();
    el.recentList.innerHTML = "";
    if (!list.length) { el.recentEmpty.style.display = ""; return; }
    el.recentEmpty.style.display = "none";
    list.forEach(function (it) {
      var li = document.createElement("li");
      li.className = "recent-item " + (it.status === "ok" ? "ok" : "fail");
      var name = document.createElement("span");
      name.className = "recent-name";
      name.textContent = it.name;
      var meta = document.createElement("span");
      meta.className = "recent-meta";
      meta.textContent = formatSize(it.size) + " · " + new Date(it.time).toLocaleString();
      li.appendChild(name);
      li.appendChild(meta);
      el.recentList.appendChild(li);
    });
  }

  /* ---------- i18n placeholders & lang re-apply ---------- */
  function applyTransferI18n() {
    if (el.codeInput) el.codeInput.setAttribute("placeholder", t("transfer.codePlaceholder"));
  }

  /* ---------- init ---------- */
  function init() {
    el.codeInput = document.getElementById("device-code");
    if (!el.codeInput) return; // not on this page
    el.verifyBtn = document.getElementById("verify-btn");
    el.stepUpload = document.getElementById("step-upload");
    el.dropzone = document.getElementById("dropzone");
    el.fileInput = document.getElementById("file-input");
    el.fileList = document.getElementById("file-list");
    el.uploadBtn = document.getElementById("upload-btn");
    el.verifyStatus = document.getElementById("verify-status");
    el.uploadStatus = document.getElementById("upload-status");
    el.recentList = document.getElementById("recent-list");
    el.recentEmpty = document.getElementById("recent-empty");
    el.rateRemaining = document.getElementById("rate-remaining");

    el.verifyBtn.addEventListener("click", onVerify);
    el.codeInput.addEventListener("keydown", function (e) { if (e.key === "Enter") onVerify(); });

    el.dropzone.addEventListener("click", function () {
      if (!state.verified) { setStatus(el.uploadStatus, t("transfer.needVerify"), "error"); return; }
      el.fileInput.click();
    });
    el.dropzone.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); el.dropzone.click(); }
    });
    el.fileInput.addEventListener("change", function () {
      if (el.fileInput.files && el.fileInput.files.length) addFiles(el.fileInput.files);
      el.fileInput.value = "";
    });
    ["dragenter", "dragover"].forEach(function (ev) {
      el.dropzone.addEventListener(ev, function (e) { e.preventDefault(); el.dropzone.classList.add("drag"); });
    });
    ["dragleave", "drop"].forEach(function (ev) {
      el.dropzone.addEventListener(ev, function (e) { e.preventDefault(); el.dropzone.classList.remove("drag"); });
    });
    el.dropzone.addEventListener("drop", function (e) {
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) addFiles(e.dataTransfer.files);
    });

    el.uploadBtn.addEventListener("click", onUpload);

    var lt = document.getElementById("lang-toggle");
    if (lt) lt.addEventListener("click", function () { setTimeout(applyTransferI18n, 0); });

    applyTransferI18n();
    updateRateUI();
    renderRecent();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
