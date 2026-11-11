# Arrow Dash Saga Website Implementation Plan

**Goal:** Add an independent bilingual product site and four full legal/support pages to WildGrassX, following the user-approved design.

**Architecture:** Static HTML under personal-site, sharing the existing theme and language preferences. English is rendered in HTML for crawlers and no-JavaScript users. Product-specific translations extend the existing dictionary. Legal Markdown is preserved as source and compiled into static pages with local cross-links. No app or backend changes.

**Tech Stack:** HTML, CSS, vanilla JavaScript, Node.js build script, existing SEO tests, Playwright browser checks.

## Approved Design

Deep green and yellow branding with the supplied promotional poster. Concise gameplay introduction, 400 puzzles, offline core gameplay, and a Coming soon label until a real App Store URL exists. Product-specific privacy, terms, support and data choices remain separate from LucidRead. Add a Selected Work entry and SEO metadata/sitemap entries. Keep English and Chinese legal texts complete; do not publish internal App Store submission notes.

## Tasks

- [x] Copy supplied English legal Markdown and existing corresponding Chinese translations into `personal-site/content/arrow-dash-saga/`; copy the supplied poster into `personal-site/images/`.
- [x] Add `personal-site/scripts/build-arrow-site.mjs` to render five static pages, convert Markdown links and produce the product translation dictionary. Use paths `/arrow-dash-saga` and `/arrow-dash-saga/{privacy,terms,support,data-choices}`.
- [x] Add `personal-site/css/arrow.css` for responsive promotional and readable legal layouts. Extend the shared dictionary through a product bundle loaded before `i18n.js`; add the product card to `index.html`.
- [x] Extend `personal-site/sitemap.xml` and `personal-site/seo.test.mjs`; verify complete source paragraph preservation, internal links and language dictionaries.
- [ ] Run existing site checks and inspect desktop/mobile layouts, language switching, dark mode and nested-page navigation using Playwright. Leave changes local for review; publishing is a separate action.
