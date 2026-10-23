import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';

const root = fileURLToPath(new URL('../', import.meta.url));
const origin = 'https://wildgrassx.com';
const product = 'arrow-dash-saga';
const docs = {
  privacy: ['Privacy Policy', '隐私政策', 'How Arrow Dash Saga handles local game progress, Google AdMob advertising, Apple purchases, support information, and your privacy choices.'],
  terms: ['Terms of Service', '服务条款', 'Read the Arrow Dash Saga terms for gameplay, local progress, advertising rewards, optional Apple purchases, restoration, and support.'],
  support: ['Support & Help', '支持与帮助', 'Get help with Arrow Dash Saga puzzles, hearts, energy, rewarded ads, purchases, refunds, local saves, and privacy questions.'],
  'data-choices': ['Data Choices & Deletion', '数据选择与删除', 'Manage Arrow Dash Saga local progress, advertising privacy options, Apple purchase records, and requests to WildGrassX Studio.'],
};
const strings = {
  en: {
    'arrow.studio': 'WildGrassX Studio', 'arrow.game': 'The game', 'arrow.support': 'Support',
    'arrow.eyebrow': 'A little space to think', 'arrow.tagline': 'One clear move at a time.',
    'arrow.intro': 'Find the open path. Clear the blockers. Watch one small move open up a whole new possibility.',
    'arrow.soon': 'Coming soon on iOS', 'arrow.explore': 'Explore the game',
    'arrow.puzzles': 'Original puzzles', 'arrow.offline': 'Offline core gameplay', 'arrow.account': 'No account required',
    'arrow.playTitle': 'Every arrow needs a way out.',
    'arrow.playDesc': 'Tap an arrow to send it along its path and off the board. When another arrow blocks the way, find a different opening. Clear every arrow to complete the puzzle.',
    'arrow.step1': 'Find an opening', 'arrow.step1desc': 'Look along each path. An unblocked arrow is your first move.',
    'arrow.step2': 'Make room', 'arrow.step2desc': 'Remove blockers in the right order to reveal the next route.',
    'arrow.step3': 'Clear the board', 'arrow.step3desc': 'Work through 400 puzzles, from small boards to tangled challenges.',
    'arrow.detailsTitle': 'Small moves. A satisfying challenge.',
    'arrow.detail1': 'A fresh perspective', 'arrow.detail1desc': 'Free hints, pinch-to-zoom, and Fit controls help you see both the details and the whole board.',
    'arrow.detail2': 'A little planning', 'arrow.detail2desc': 'Each run has limited hearts and a countdown. Starting or retrying uses energy, which replenishes over time.',
    'arrow.detail3': 'Your pace, your volume', 'arrow.detail3desc': 'Adjust the background music or turn sound off. Progress and audio preferences are saved on your device.',
    'arrow.disclosure': 'Contains ads. Optional rewarded ads can provide a revive, extra time, energy, or a level skip. Ads require an internet connection and may not always be available.',
    'arrow.helpTitle': 'A clear path to help, too.', 'arrow.helpDesc': 'Gameplay questions, privacy choices, and the small print, all in one place.',
    'arrow.privacy': 'Privacy Policy', 'arrow.terms': 'Terms of Service', 'arrow.data': 'Data Choices & Deletion',
    'arrow.contact': 'Contact support', 'arrow.contents': 'On this page', 'arrow.back': 'Back to the game',
    'arrow.cardDesc': '400 original arrow puzzles. Find the open paths, plan your next move, and clear the board.',
    'arrow.cardLink': 'Explore Arrow Dash Saga', 'arrow.top': 'Back to top',
    'arrow.metaTitle': 'Arrow Dash Saga — 400 Original Arrow Puzzles for iOS',
    'arrow.metaDesc': 'Discover Arrow Dash Saga: 400 original path-clearing puzzles for iOS, free hints, zoom controls, and offline core gameplay. Coming soon from WildGrassX Studio.',
  },
  zh: {
    'arrow.studio': 'WildGrassX Studio', 'arrow.game': '游戏介绍', 'arrow.support': '支持与帮助',
    'arrow.eyebrow': '给思考留一点空间', 'arrow.tagline': '每一步，都找到新出路。',
    'arrow.intro': '观察路径，移除阻挡。一次小小的移动，就能为下一步打开全新的可能。',
    'arrow.soon': '即将登陆 iOS', 'arrow.explore': '了解游戏',
    'arrow.puzzles': '原创谜题', 'arrow.offline': '核心关卡支持离线', 'arrow.account': '无需注册账号',
    'arrow.playTitle': '每一支箭头，都有出路。',
    'arrow.playDesc': '点击箭头，让它沿路径离开棋盘。前方被挡住时，寻找另一个突破口。安排移除顺序，清空所有箭头，完成挑战。',
    'arrow.step1': '寻找出口', 'arrow.step1desc': '沿着路径观察，没有阻挡的箭头就是第一步。',
    'arrow.step2': '腾出空间', 'arrow.step2desc': '按顺序移除阻挡，为更多箭头打开通路。',
    'arrow.step3': '清空棋盘', 'arrow.step3desc': '从小型棋盘到复杂路径，逐步挑战 400 个原创关卡。',
    'arrow.detailsTitle': '小小的一步，解开的不止一道题。',
    'arrow.detail1': '换个角度看', 'arrow.detail1desc': '免费提示、双指缩放与 Fit 视野适配，让你看清细节，也看清全局。',
    'arrow.detail2': '多一点规划', 'arrow.detail2desc': '每局拥有有限生命与倒计时。开局和重开消耗体力，体力随时间恢复。',
    'arrow.detail3': '用喜欢的声音游玩', 'arrow.detail3desc': '调节背景音乐，或关闭声音。游戏进度与声音偏好保存在本机。',
    'arrow.disclosure': '游戏包含广告。可主动选择激励广告获得复活、加时、体力或跳关奖励。广告需要联网，实际可用情况可能有所不同。',
    'arrow.helpTitle': '需要帮助，也有清晰的入口。', 'arrow.helpDesc': '玩法疑问、隐私选择与服务条款，都可以在这里找到。',
    'arrow.privacy': '隐私政策', 'arrow.terms': '服务条款', 'arrow.data': '数据选择与删除',
    'arrow.contact': '联系客服', 'arrow.contents': '本页目录', 'arrow.back': '返回游戏介绍',
    'arrow.cardDesc': '400 个原创箭头谜题。观察路径，安排移除顺序，一步步清空棋盘。',
    'arrow.cardLink': '了解 Arrow Dash Saga', 'arrow.top': '返回顶部',
    'arrow.metaTitle': 'Arrow Dash Saga — 400 个原创箭头谜题，iOS 益智游戏',
    'arrow.metaDesc': '探索 Arrow Dash Saga：400 个原创箭头解谜关卡、免费提示、缩放与视野适配，核心关卡支持离线游玩。由 WildGrassX Studio 打造，即将登陆 iOS。',
  },
};
const escape = value => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const t = (key, tag = 'span', attrs = '') => `<${tag} data-i18n="arrow.${key}" ${attrs}>${strings.en[`arrow.${key}`]}</${tag}>`;
const route = slug => `/${product}/${slug}.html`;
const legalLinks = () => Object.entries(docs).map(([slug, [label]]) => `<a href="${route(slug)}" data-i18n="arrow.${slug === 'data-choices' ? 'data' : slug}">${label}</a>`).join('');

function shell({ title, description, slug, main, legal = false }) {
  const url = `${origin}/${product}${slug ? '/' + slug : ''}`;
  const schema = { '@context': 'https://schema.org', '@type': legal ? 'WebPage' : 'SoftwareApplication', name: title, url, description, ...(legal ? {} : { applicationCategory: 'GameApplication', operatingSystem: 'iOS' }), publisher: { '@type': 'Organization', name: 'WildGrassX Studio' } };
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" href="data:,">
  <script>try { var theme = localStorage.getItem('theme'); if (theme === 'dark' || (!theme && matchMedia('(prefers-color-scheme: dark)').matches)) document.documentElement.setAttribute('data-theme', 'dark'); } catch (e) {}</script>
  <title data-i18n="arrow.${slug || 'meta'}Title">${escape(title)}</title>
  <meta name="description" data-i18n="arrow.${slug || 'meta'}Desc" content="${escape(description)}">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <meta name="keywords" content="Arrow Dash Saga, arrow puzzle game iOS, offline logic puzzles, path clearing game, 400 original puzzles, WildGrassX Studio">
  <link rel="canonical" href="${url}">
  <meta property="og:title" content="${escape(title)}">
  <meta property="og:description" content="${escape(description)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${url}">
  <meta property="og:site_name" content="WildGrassX Studio">
  <meta property="og:image" content="${origin}/images/arrow-dash-saga.png">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escape(title)}">
  <meta name="twitter:description" content="${escape(description)}">
  <meta name="twitter:image" content="${origin}/images/arrow-dash-saga.png">
  <script type="application/ld+json">${JSON.stringify(schema)}</script>
  <link rel="stylesheet" href="/css/style.css">
  <link rel="stylesheet" href="/css/arrow.css">
</head>
<body class="arrow-site ${legal ? 'arrow-legal' : ''}" id="top">
  <a class="skip-link" href="#main">Skip to content / 跳转到正文</a>
  <header class="site-header">
    <div class="container nav">
      <a class="brand" href="/${product}.html">Arrow Dash Saga<span class="brand-dot" aria-hidden="true">.</span></a>
      <nav class="nav-links" id="nav-links" aria-label="Primary navigation">
        <a href="/index.html" data-i18n="arrow.studio">WildGrassX Studio</a>
        <a href="/${product}.html#game" data-i18n="arrow.game">The game</a>
        <a href="${route('support')}" data-i18n="arrow.support">Support</a>
        <button class="lang-toggle" id="lang-toggle" type="button" aria-label="Switch to Chinese">中文</button>
        <button class="theme-toggle" id="theme-toggle" type="button" aria-label="Toggle light / dark theme"><span class="icon-sun" aria-hidden="true">☀</span><span class="icon-moon" aria-hidden="true">☾</span></button>
      </nav>
      <button class="nav-toggle" id="nav-toggle" type="button" aria-label="Open menu" aria-expanded="false" aria-controls="nav-links"><span></span><span></span><span></span></button>
    </div>
  </header>
  <main id="main">${main}</main>
  <footer class="arrow-footer"><div class="container"><a class="brand" href="/${product}.html">Arrow Dash Saga</a><nav aria-label="Product resources">${legalLinks()}</nav><div class="footer-bottom"><span>© <span id="year">2026</span> WildGrassX Studio</span><a href="#top" data-i18n="arrow.top">Back to top</a></div></div></footer>
  <script src="/js/arrow-i18n.js"></script>
  <script src="/js/i18n.js"></script>
  <script src="/js/main.js"></script>
</body>
</html>
`;
}

const main = `
<section class="arrow-hero" aria-labelledby="game-title">
  <img class="arrow-hero-image" src="/images/arrow-dash-saga.png" alt="" width="851" height="1848" fetchpriority="high">
  <div class="container hero-content">
    ${t('eyebrow', 'p', 'class="arrow-eyebrow"')}
    <h1 id="game-title">Arrow <br>Dash Saga<span aria-hidden="true">.</span></h1>
    ${t('tagline', 'p', 'class="arrow-tagline"')}
    ${t('intro', 'p', 'class="arrow-intro"')}
    <div class="hero-actions">${t('soon', 'span', 'class="coming-soon"')}<a href="#game" class="explore-link" data-i18n="arrow.explore">Explore the game</a></div>
  </div>
</section>
<section class="arrow-facts" aria-label="Game at a glance"><div class="container"><div><strong>400</strong>${t('puzzles')}</div><div>${t('offline')}</div><div>${t('account')}</div></div></section>
<section class="arrow-section container" id="game">
  <div class="section-intro"><span class="section-number" aria-hidden="true">01 /</span>${t('playTitle', 'h2')}${t('playDesc', 'p')}</div>
  <div class="arrow-steps">${[1,2,3].map(i => `<article><span class="step-number" aria-hidden="true">0${i}</span>${t(`step${i}`, 'h3')}${t(`step${i}desc`, 'p')}</article>`).join('')}</div>
</section>
<section class="arrow-details"><div class="container arrow-section"><div class="section-intro"><span class="section-number" aria-hidden="true">02 /</span>${t('detailsTitle', 'h2')}</div><div class="details-list">${[1,2,3].map(i => `<article>${t(`detail${i}`, 'h3')}${t(`detail${i}desc`, 'p')}</article>`).join('')}</div>${t('disclosure', 'p', 'class="ad-disclosure"')}</div></section>
<section class="arrow-section container arrow-help"><span class="section-number" aria-hidden="true">03 /</span>${t('helpTitle', 'h2')}${t('helpDesc', 'p')}<div class="resource-links">${legalLinks()}</div><a class="contact-link" href="mailto:support@wildgrassx.com" data-i18n="arrow.contact">Contact support</a></section>`;

fs.mkdirSync(path.join(root, product), { recursive: true });
fs.writeFileSync(path.join(root, `${product}.html`), shell({ title: strings.en['arrow.metaTitle'], description: strings.en['arrow.metaDesc'], main }));

function legalBody(markdown, language) {
  const tokens = marked.lexer(markdown);
  let section = 0;
  const headings = [];
  const renderer = new marked.Renderer();
  renderer.heading = function(token) {
    const content = this.parser.parseInline(token.tokens);
    if (token.depth === 1) return `<h1>${content}</h1>`;
    const id = `section-${++section}`;
    headings.push(`<li><a href="#${id}">${content}</a></li>`);
    return `<h${token.depth} id="${id}">${content}</h${token.depth}>`;
  };
  renderer.link = function(token) {
    let href = token.href;
    const match = href.match(/^(privacy|terms|support|data-choices)\.(en|zh-Hans)\.md$/);
    if (match) href = route(match[1]);
    if (!/^(https:\/\/|mailto:|\/)/.test(href)) throw new Error(`Unexpected document link: ${href}`);
    return `<a href="${escape(href)}">${this.parser.parseInline(token.tokens)}</a>`;
  };
  const article = marked.parser(tokens, { renderer });
  return `<div class="legal-layout"><aside class="legal-toc"><p>${strings[language]['arrow.contents']}</p><nav aria-label="${strings[language]['arrow.contents']}"><ol>${headings.join('')}</ol></nav></aside><article class="legal-prose">${article}</article></div>`;
}

for (const [slug, [enTitle, zhTitle, description]] of Object.entries(docs)) {
  for (const [language, fileLanguage, title] of [['en','en',enTitle], ['zh','zh-Hans',zhTitle]]) {
    strings[language][`arrow.${slug}Title`] = `Arrow Dash Saga — ${title}`;
    strings[language][`arrow.${slug}Desc`] = language === 'en' ? description : `Arrow Dash Saga ${title}。了解 WildGrassX Studio 提供的游戏服务、本地数据、广告、Apple 购买与支持信息，以及相应的操作方式。`;
    const source = fs.readFileSync(path.join(root, 'content', product, `${slug}.${fileLanguage}.md`), 'utf8');
    strings[language][`arrow.${slug}Body`] = legalBody(source, language);
  }
  const main = `<div class="container legal-container"><a class="back-link" href="/${product}.html" data-i18n="arrow.back">Back to the game</a><div data-i18n="arrow.${slug}Body">${strings.en[`arrow.${slug}Body`]}</div></div>`;
  fs.writeFileSync(path.join(root, product, `${slug}.html`), shell({ title: strings.en[`arrow.${slug}Title`], description, slug, main, legal: true }));
}
fs.writeFileSync(path.join(root, 'js/arrow-i18n.js'), '// Generated by scripts/build-arrow-site.mjs.\nwindow.SITE_I18N = ' + JSON.stringify(strings, null, 2) + ';\n');
console.log('Built Arrow Dash Saga product page, four resource pages, and EN/ZH translations.');
