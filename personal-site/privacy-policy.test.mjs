import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync(new URL("./privacy.html", import.meta.url), "utf8");
const i18n = fs.readFileSync(new URL("./js/i18n.js", import.meta.url), "utf8");

const requiredPhrases = [
  'developed by WildGrassX Studio ("we", "us", or "our")',
  "LucidRead is an accessibility-first reading tool requiring no user login.",
  "We highly value your privacy:",
  "No registration, no user accounts.",
  "including your name, email, phone number or IP address",
  "We cannot access your library contents or reading records.",
  "processed exclusively by Apple through StoreKit",
  "This Application does not embed any third-party advertising SDK, tracking library or analytics framework.",
  "We transmit none of your personal content to remote servers.",
  "We reserve the right to revise this Privacy Policy.",
  "For inquiries regarding this policy or accessibility features of LucidRead",
  "support@wildgrassx.com",
];

for (const phrase of requiredPhrases) {
  assert.ok(html.includes(phrase), `privacy.html should include: ${phrase}`);
  assert.ok(i18n.includes(phrase), `i18n.js should include: ${phrase}`);
}

assert.match(html, /<ul class="policy-list">[\s\S]+?No registration, no user accounts\.[\s\S]+?StoreKit[\s\S]+?<\/ul>/);
assert.match(html, /<a href="mailto:support@wildgrassx\.com">support@wildgrassx\.com<\/a>/);
