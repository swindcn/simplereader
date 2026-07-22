export const webTransferPageHtml = String.raw`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>简声网站传书</title>
  <style>
    :root {
      color-scheme: light;
      --background: #f7f7fb;
      --surface: #ffffff;
      --text: #111827;
      --muted: #6b7280;
      --border: #cfd3dc;
      --primary: #0a84ff;
      --disabled: #9ca3af;
    }

    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
      background: var(--background);
      color: var(--text);
    }

    main {
      max-width: 520px;
      margin: 0 auto;
      padding: 32px 20px;
    }

    h1 {
      font-size: 32px;
      line-height: 1.2;
      margin: 0 0 24px;
    }

    form {
      background: var(--surface);
      border-radius: 8px;
      padding: 20px;
      box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08);
    }

    label {
      display: block;
      font-size: 18px;
      font-weight: 700;
      margin: 18px 0 8px;
    }

    label:first-child {
      margin-top: 0;
    }

    input,
    button {
      width: 100%;
      box-sizing: border-box;
      font-size: 20px;
      min-height: 56px;
      border-radius: 8px;
    }

    input {
      border: 1px solid var(--border);
      padding: 12px;
      background: white;
    }

    button {
      border: 0;
      background: var(--primary);
      color: white;
      font-weight: 700;
      margin-top: 20px;
    }

    button:disabled {
      background: var(--disabled);
    }

    #status {
      margin-top: 20px;
      font-size: 18px;
      line-height: 1.5;
      color: var(--muted);
    }
  </style>
</head>
<body>
  <main>
    <h1>简声网站传书</h1>
    <form id="form">
      <label for="code">传书码</label>
      <input id="code" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="8" required>
      <label for="file">选择书籍文件</label>
      <input id="file" name="file" type="file" accept=".txt,.epub,text/plain,application/epub+zip" required>
      <button id="submit" type="submit">上传到 App</button>
    </form>
    <p id="status" role="status" aria-live="polite"></p>
  </main>
  <script>
    const form = document.getElementById("form");
    const status = document.getElementById("status");
    const submit = document.getElementById("submit");
    const functionBase = location.pathname.replace(/\/web\/?$/, "").replace(/\/$/, "");

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
        const session = await postJson(\`\${functionBase}/web/resolve-code\`, { code });
        const data = new FormData();
        data.append("uploadSessionId", session.uploadSessionId);
        data.append("file", file);
        status.textContent = "正在上传文件";
        const upload = await fetch(\`\${functionBase}/web/upload\`, { method: "POST", body: data });
        const payload = await upload.json();
        if (!upload.ok) throw new Error(payload.error?.message || "上传失败");
        status.textContent = \`上传成功：\${payload.filename}。请回到简声 App 刷新接收。\`;
      } catch (error) {
        status.textContent = error.message;
      } finally {
        submit.disabled = false;
      }
    });
  </script>
</body>
</html>
`;
