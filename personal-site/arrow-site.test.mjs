import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';

const root = fileURLToPath(new URL('./', import.meta.url));
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const sandbox = { window: {} };
vm.runInNewContext(read('js/arrow-i18n.js'), sandbox);
const dict = sandbox.window.SITE_I18N;
assert.deepEqual(Object.keys(dict.en).sort(), Object.keys(dict.zh).sort());
const slugs = ['privacy', 'terms', 'support', 'data-choices'];
for (const slug of slugs) {
  const page = read(`arrow-dash-saga/${slug}.html`);
  assert.ok(page.includes(dict.en[`arrow.${slug}Body`]), `${slug}: English rendered without JavaScript`);
  for (const [lang, fileLang] of [['en', 'en'], ['zh', 'zh-Hans']]) {
    const html = dict[lang][`arrow.${slug}Body`];
    const source = read(`content/arrow-dash-saga/${slug}.${fileLang}.md`);
    for (const token of marked.lexer(source)) {
      if (token.type !== 'paragraph') continue;
      const expected = marked.parser([token]).replace(/href="(privacy|terms|support|data-choices)\.(en|zh-Hans)\.md"/g, 'href="/arrow-dash-saga/$1.html"').trim();
      assert.ok(html.includes(expected), `${slug}/${lang}: preserve paragraph ${token.text.slice(0, 55)}`);
    }
    assert.doesNotMatch(html, /href="[^"]+\.md"/);
    for (const [, id] of html.matchAll(/href="#([^"]+)"/g)) assert.ok(html.includes(`id="${id}"`));
  }
}
for (const file of ['arrow-dash-saga.html', ...slugs.map(s => `arrow-dash-saga/${s}.html`)]) {
  const page = read(file);
  for (const [, key] of page.matchAll(/data-i18n="([^"]+)"/g)) {
    assert.ok(key in dict.en && key in dict.zh, `${file}: missing translation ${key}`);
  }
  for (const [, target] of page.matchAll(/(?:href|src)="(\/[^"#]+)"/g)) {
    assert.ok(fs.existsSync(path.join(root, target.split('#')[0])), `${file}: missing local link ${target}`);
  }
}
assert.doesNotMatch(read('arrow-dash-saga.html'), /apps\.apple\.com|\$2\.99/);
assert.match(read('index.html'), /href="arrow-dash-saga.html"/);
console.log('Arrow pages: complete bilingual policies, translations, TOC and local links verified.');
