import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const siteDir = new URL("./", import.meta.url);
const sitePath = fileURLToPath(siteDir);
const pages = [
  "index.html",
  "lucidread.html",
  "transfer.html",
  "support.html",
  "accessibility.html",
  "privacy.html",
  "terms.html",
  "cookie.html",
];

for (const page of pages) {
  const html = fs.readFileSync(new URL(page, siteDir), "utf8");
  assert.match(html, /<title[^>]*>[^<]{20,}<\/title>/, `${page} needs a focused title`);
  assert.match(html, /<meta name="description"[^>]+content="[^"]{80,180}"/, `${page} needs a 80-180 char description`);
  assert.match(html, /<meta name="robots" content="index, follow[^"]*"/, `${page} needs indexable robots meta`);
  assert.match(html, /<link rel="canonical" href="https:\/\/wildgrassx\.com\/[^"]*"/, `${page} needs canonical URL`);
  assert.match(html, /<meta name="keywords" content="[^"]{40,}"/, `${page} needs long-tail keywords`);
  assert.match(html, /<meta property="og:title" content="[^"]+"/, `${page} needs og:title`);
  assert.match(html, /<meta property="og:description" content="[^"]+"/, `${page} needs og:description`);
  assert.match(html, /<meta property="og:url" content="https:\/\/wildgrassx\.com\/[^"]*"/, `${page} needs og:url`);
  assert.match(html, /<meta name="twitter:card" content="summary_large_image"/, `${page} needs Twitter card`);
  const jsonLd = html.match(/<script type="application\/ld\+json">([\s\S]+?)<\/script>/);
  assert.ok(jsonLd, `${page} needs JSON-LD`);
  assert.doesNotThrow(() => JSON.parse(jsonLd[1]), `${page} JSON-LD should be valid JSON`);
}

for (const asset of ["robots.txt", "sitemap.xml"]) {
  const assetPath = path.join(sitePath, asset);
  assert.equal(fs.existsSync(assetPath), true, `${asset} should exist`);
}

const sitemap = fs.readFileSync(new URL("sitemap.xml", siteDir), "utf8");
for (const page of pages) {
  const slug = page === "index.html" ? "" : page.replace(/\.html$/, "");
  assert.match(sitemap, new RegExp(`<loc>https://wildgrassx\\.com/${slug}</loc>`), `sitemap should include ${page}`);
}
