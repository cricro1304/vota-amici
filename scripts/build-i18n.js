#!/usr/bin/env node
/* ==========================================================================
   Per-language static HTML generator for landing-page.html and packs.html.

   Reads the templates (Italian-seeded HTML with [data-i18n] attributes)
   plus the translation dictionaries, and writes:

       dist/landing-page.html        ← Italian (default at /)
       dist/en/landing-page.html     ← English (served at /en/)
       dist/packs.html               ← Italian
       dist/en/packs.html            ← English

   This replaces the previous client-side i18n approach (i18n.js +
   landing.translations.js + setLang at boot). Net wins:

     • Zero translation JS at runtime → smaller bundle, faster FCP/LCP
     • No post-paint text swap → no CLS from i18n, no INP cost
     • Each language gets its own URL → SEO-friendly, hreflang-correct
     • Lang toggle is a real <a href> navigation, instant

   Design notes:

     • The source-of-truth template is landing-page.html / packs.html at
       the repo root (Italian, with [data-i18n] attributes).
     • Translation dictionaries are still landing.translations.js and
       packs.translations.js — we read them at build time only.
     • The script is invoked from build.sh after the asset copy step,
       overwriting dist/landing-page.html / dist/packs.html with the IT
       version and adding the EN version under dist/en/.
     • Cheerio is installed on demand (npm install --no-save) so the
       repo doesn't need a package.json to clone-and-go. Cheerio handles
       the HTML parsing reliably — regex is fragile around nested
       data-i18n elements (e.g. <span class="mode-chip-locked">🔒
       <span data-i18n="...">...</span></span>).
   ========================================================================== */

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ── Cheerio: install on demand ──────────────────────────────────────────────
let cheerio;
try {
  cheerio = require('cheerio');
} catch (e) {
  console.log('==> cheerio not found, installing...');
  execSync('npm install --no-save --silent cheerio@^1.0.0', { stdio: 'inherit' });
  cheerio = require('cheerio');
}

// ── Paths ───────────────────────────────────────────────────────────────────
const REPO_ROOT = path.resolve(__dirname, '..');
const DIST = path.join(REPO_ROOT, 'dist');

const PAGES = [
  {
    name: 'landing',
    template: path.join(REPO_ROOT, 'landing-page.html'),
    output: 'landing-page.html',
    translationsScript: path.join(REPO_ROOT, 'assets/js/landing.translations.js'),
    translationsGlobal: 'LANDING_TRANSLATIONS',
    // Title strings per language (translations.js doesn't have a title key
    // for landing — keep these in sync with the design here).
    titles: {
      it: 'Chi è il più...? | Il gioco che svela la verità sui tuoi amici',
      en: "Who's the most...? | The game that reveals what your friends really think",
    },
    descriptions: {
      it: 'Il party game che mette alla prova le amicizie. Vota, scopri e ridi con i tuoi amici. Gratis!',
      en: "The party game that puts friendships to the test. Vote, find out, laugh with your friends. Free!",
    },
    ogTitles: {
      it: 'Chi è il più...? | Il gioco che svela la verità',
      en: "Who's the most...? | The game that reveals the truth",
    },
    ogDescriptions: {
      it: 'Il party game che mette alla prova le amicizie. Chi è il più pigro? Il più drammatico? Scoprilo adesso!',
      en: "The party game that tests friendships. Who's the laziest? The most dramatic? Find out now!",
    },
  },
  {
    name: 'packs',
    template: path.join(REPO_ROOT, 'packs.html'),
    output: 'packs.html',
    translationsScript: path.join(REPO_ROOT, 'assets/js/packs.translations.js'),
    translationsGlobal: 'PACKS_TRANSLATIONS',
    titles: {
      it: 'Pacchetti | Chi è il più...?',
      en: "Packs | Who's the most...?",
    },
    descriptions: {
      it: "Tutti i pacchetti di domande: Coppie, Fratelli, Famiglia, Colleghi, Coinquilini, Viaggi, Per conoscersi meglio, Versione Spicy e l'Originale gratuito.",
      en: 'All question packs: Couples, Siblings, Family, Coworkers, Roommates, Travel, Icebreakers, Spicy edition and the free Original.',
    },
  },
];

// Public origin used in hreflang/canonical/og:url. Keep in sync with
// vercel.json's primary domain.
const ORIGIN = 'https://ilpiu.org';

// ── Translation loader ─────────────────────────────────────────────────────
// The translation files are written as `window.GLOBAL = { it: {}, en: {} }`.
// We read the file as text, swap `window` for a sandbox object, and `eval`
// in a tiny scope. Avoids spinning up a vm sandbox for so little code.
function loadTranslations(filePath, globalName) {
  const src = fs.readFileSync(filePath, 'utf8');
  const sandbox = {};
  const fn = new Function('window', src);
  fn(sandbox);
  const dict = sandbox[globalName];
  if (!dict || typeof dict !== 'object') {
    throw new Error(`Translation file ${filePath} did not set window.${globalName}`);
  }
  if (!dict.it || !dict.en) {
    throw new Error(`Translation dict ${globalName} missing it/en keys`);
  }
  return dict;
}

// ── Per-language URL helpers ───────────────────────────────────────────────
// Internal page links in the templates use bare filenames like
// `landing-page.html` and `packs.html`. We rewrite them per-language so
// the IT version points at /landing-page.html and the EN version points
// at /en/landing-page.html.
function pageHref(filename, lang) {
  return lang === 'it' ? '/' + filename : '/en/' + filename;
}

// Path used in og:url and canonical. Matches the public URL the user
// would share — slash for landing root, /packs for packs.
function canonicalUrl(pageName, lang) {
  if (pageName === 'landing') {
    return lang === 'it' ? `${ORIGIN}/` : `${ORIGIN}/en/`;
  }
  if (pageName === 'packs') {
    return lang === 'it' ? `${ORIGIN}/packs` : `${ORIGIN}/en/packs`;
  }
  return ORIGIN;
}

// ── Main per-page render ────────────────────────────────────────────────────
function renderPage(page, lang, dict) {
  const html = fs.readFileSync(page.template, 'utf8');
  const $ = cheerio.load(html, { decodeEntities: false });

  const t = dict[lang];

  // 1. <html lang>
  $('html').attr('lang', lang);

  // 2. Apply [data-i18n] replacements. Each translation value is treated
  //    as HTML (some values contain markup like the slot-machine spans).
  //    We strip the data-i18n attribute from the output to keep the
  //    rendered HTML clean — the runtime no longer needs it.
  $('[data-i18n]').each((_, el) => {
    const $el = $(el);
    const key = $el.attr('data-i18n');
    const val = t[key];
    if (val == null) {
      // Unknown key: leave the seeded text in place but warn.
      console.warn(`  [${page.name}/${lang}] unknown i18n key: ${key}`);
    } else {
      $el.html(val);
    }
    $el.removeAttr('data-i18n');
  });

  // 3. Question carousel chips (landing page only). The template has
  //    Italian chips inline; for EN we replace the chip lists with the
  //    EN chip arrays from the translations dict.
  if (page.name === 'landing') {
    const row1 = t.carousel_row1 || [];
    const row2 = t.carousel_row2 || [];
    const buildChips = (arr) =>
      arr.concat(arr) // duplicate so the marquee can loop seamlessly
        .map((q) => `<span class="question-chip">${q}</span>`)
        .join('');
    $('#qTrack1').html(buildChips(row1)).attr('data-seeded-lang', lang);
    $('#qTrack2').html(buildChips(row2)).attr('data-seeded-lang', lang);
  }

  // 4. Lang toggle: convert the <button onclick="setLang(...)"> markup
  //    to real <a href> links pointing at the alternate-language version
  //    of the current page. Sets aria-current on the active language.
  const otherLang = lang === 'it' ? 'en' : 'it';
  const currentPage = page.output; // e.g. 'landing-page.html'
  const langToggle = `
    <a href="${pageHref(currentPage, 'it')}" class="lang-btn${lang === 'it' ? ' active' : ''}"${lang === 'it' ? ' aria-current="page"' : ''}>IT</a>
    <a href="${pageHref(currentPage, 'en')}" class="lang-btn${lang === 'en' ? ' active' : ''}"${lang === 'en' ? ' aria-current="page"' : ''}>EN</a>
  `.trim();
  $('.lang-toggle').html(langToggle);

  // 5. Internal page links: rewrite bare filename hrefs to language-prefixed
  //    absolute paths. E.g. on the EN landing page, a link to
  //    "packs.html" becomes "/en/packs.html". External links (/play, http(s)://)
  //    are untouched.
  const INTERNAL_PAGES = ['landing-page.html', 'packs.html'];
  $('a[href]').each((_, el) => {
    const $a = $(el);
    const href = $a.attr('href');
    if (!href) return;
    // Skip absolute/external links and in-page anchors
    if (/^(https?:|mailto:|tel:|\/\/|#)/i.test(href)) return;
    // If href is just a filename or starts with a filename, rewrite it
    for (const filename of INTERNAL_PAGES) {
      if (href === filename || href === './' + filename) {
        $a.attr('href', pageHref(filename, lang));
        return;
      }
    }
  });

  // 5b. Asset paths: every relative URL in <link href>, <script src>,
  //     <img src>, etc. needs to be made absolute (`/assets/...`) so
  //     the EN page at /en/landing-page.html doesn't try to load
  //     /en/assets/css/landing.css (which 404s — assets only live at
  //     /assets/...). The IT page works either way; absolute is also
  //     fine there. Rewriting at build time is safer than telling the
  //     template author to remember to use absolute paths everywhere.
  function absolutize(url) {
    if (!url) return url;
    // Skip absolute URLs, protocol-relative URLs, data:, mailto:, etc.
    if (/^(https?:|data:|mailto:|tel:|\/\/|#|\/)/i.test(url)) return url;
    // Strip leading "./" if present, then prepend "/"
    return '/' + url.replace(/^\.\//, '');
  }
  // Cover every common attribute that holds a URL. The `xlink:href`
  // selector contains a colon which css-what (cheerio's selector
  // parser) can't handle, so we escape the colon — `[xlink\\:href]`
  // in the JS string is `[xlink\:href]` in the selector, which css-what
  // treats as a literal colon.
  const URL_ATTRS = [
    ['link', 'href'],
    ['script', 'src'],
    ['img', 'src'],
    ['img', 'srcset'], // technically a list, but we only use single URLs in this codebase
    ['source', 'src'],
    ['source', 'srcset'],
    ['video', 'src'],
    ['video', 'poster'],
    ['audio', 'src'],
    ['iframe', 'src'],
    ['use', 'href'],
    ['use', 'xlink\\:href'],
  ];
  for (const [tag, attr] of URL_ATTRS) {
    $(`${tag}[${attr}]`).each((_, el) => {
      const $el = $(el);
      // attr() expects the literal attr name (no escaping).
      const attrName = attr.replace(/\\/g, '');
      const val = $el.attr(attrName);
      const next = absolutize(val);
      if (next !== val) $el.attr(attrName, next);
    });
  }

  // 6. <title> + meta description + og:title + og:description.
  if (page.titles && page.titles[lang]) {
    $('title').text(page.titles[lang]);
  }
  if (page.descriptions && page.descriptions[lang]) {
    $('meta[name="description"]').attr('content', page.descriptions[lang]);
  }
  if (page.ogTitles && page.ogTitles[lang]) {
    $('meta[property="og:title"]').attr('content', page.ogTitles[lang]);
  }
  if (page.ogDescriptions && page.ogDescriptions[lang]) {
    $('meta[property="og:description"]').attr('content', page.ogDescriptions[lang]);
  }

  // 7. SEO: hreflang alternates + canonical. Inserted into <head> after
  //    the existing preconnect tags. Both languages cross-reference each
  //    other so Google indexes them as a translation pair.
  const itUrl = canonicalUrl(page.name, 'it');
  const enUrl = canonicalUrl(page.name, 'en');
  const seoLinks = `
    <link rel="canonical" href="${lang === 'it' ? itUrl : enUrl}" />
    <link rel="alternate" hreflang="it" href="${itUrl}" />
    <link rel="alternate" hreflang="en" href="${enUrl}" />
    <link rel="alternate" hreflang="x-default" href="${itUrl}" />
    <meta property="og:url" content="${lang === 'it' ? itUrl : enUrl}" />
    <meta property="og:locale" content="${lang === 'it' ? 'it_IT' : 'en_US'}" />
  `;
  // Insert after the last existing <link rel="preconnect"> tag, or before </head> as fallback.
  const $preconnects = $('link[rel="preconnect"]');
  if ($preconnects.length) {
    $preconnects.last().after(seoLinks);
  } else {
    $('head').append(seoLinks);
  }

  // 8. Strip the now-unused i18n script tags. The template no longer
  //    references them after this PR, but defensively remove any that
  //    slipped through (e.g. someone re-added them by mistake).
  $('script[src*="translations.js"]').remove();
  $('script[src*="i18n.js"]').remove();

  // 9. Post-process pass: absolutize URLs inside <noscript> blocks.
  //    Cheerio parses <noscript> contents as raw text per the HTML
  //    spec (contents only become live DOM when scripting is disabled),
  //    so the [link][href] selector above doesn't reach the inner
  //    <link>. Without this fix, the EN page's <noscript> fallback
  //    would 404 on /en/assets/css/landing.css. Regex is fine here —
  //    the noscript blocks contain only well-formed <link> tags.
  let out = $.html();
  out = out.replace(/<noscript>([\s\S]*?)<\/noscript>/g, (_, inner) => {
    const fixed = inner.replace(
      /(\b(?:href|src)=)"([^"]+)"/g,
      (m, attr, url) => attr + '"' + absolutize(url) + '"'
    );
    return '<noscript>' + fixed + '</noscript>';
  });

  // 10. Lightweight HTML+inline-CSS minification. The source HTML is heavy
  //     with explanatory comments (~5KB of HTML comments + ~5KB of CSS
  //     comments inside the inline <style>), plus generous indentation.
  //     None of that ships value to the browser; it just inflates the
  //     critical-path bytes the parser has to walk before discovering
  //     external resources. On Slow 4G + weak-CPU mobile (Lighthouse's
  //     default profile) every KB of HTML adds ~50ms to FCP. Stripping
  //     gets us from ~62KB → ~44KB on the landing page (~28% smaller),
  //     which translates to roughly 700-900ms off mobile FCP/LCP.
  //
  //     Steps (each kept conservative so we don't break anything):
  //       a. Strip /* … */ comments inside <style> blocks (preserve the
  //          rules themselves, just drop the prose).
  //       b. Collapse whitespace inside <style> blocks (newlines/tabs
  //          between selectors and declarations, run-on spaces).
  //       c. Strip HTML comments — but ONLY the prose ones. The two
  //          IE-conditional patterns (`<!--[if IE]>` etc.) and the
  //          translation-key markers like `<!--$KEY$-->` (we don't have
  //          any but be defensive) are preserved by the regex below.
  //       d. Collapse runs of whitespace BETWEEN tags (not inside text
  //          content, where collapsing could change the rendered output).
  //
  //     We do NOT touch <script> or <pre> contents — JS uses ASI and
  //     stripping whitespace there can change semantics, and <pre>
  //     content is meaningful whitespace.
  out = minifyHtml(out);

  return out;
}

// Lightweight HTML minifier. Avoids the full html-minifier dep — the
// transforms below cover ~95% of the size win without any of the
// edge-case footguns (`<select>` whitespace, `<textarea>` content, etc).
function minifyHtml(html) {
  // a + b: minify each <style>...</style> block in place.
  html = html.replace(/<style([^>]*)>([\s\S]*?)<\/style>/gi, (_, attrs, body) => {
    // Strip CSS comments. The /* ... */ form is unambiguous in CSS — no
    // string-literal escaping to worry about for our codebase.
    body = body.replace(/\/\*[\s\S]*?\*\//g, '');
    // Collapse all whitespace runs to a single space.
    body = body.replace(/\s+/g, ' ');
    // Drop spaces around CSS punctuation that doesn't need them.
    body = body.replace(/\s*([{}:;,>+~])\s*/g, '$1');
    // The semicolon before } is optional; drop it for a few extra bytes.
    body = body.replace(/;}/g, '}');
    body = body.trim();
    return '<style' + attrs + '>' + body + '</style>';
  });

  // c: strip prose HTML comments, but preserve IE conditionals and any
  //    comment whose body starts with `[` or `$` (defensive — we don't
  //    use these but other tooling sometimes does).
  html = html.replace(/<!--([\s\S]*?)-->/g, (m, inner) => {
    const t = inner.trim();
    if (t.startsWith('[') || t.startsWith('$')) return m;
    return '';
  });

  // d: collapse whitespace between tags. Preserve a single space if the
  //    original had a newline + indentation between tags, since collapsing
  //    that to nothing changes how inline-block elements render. We use
  //    the simpler rule "collapse multi-space runs to one space" rather
  //    than the more aggressive ">\s+<" → "><" because the latter caused
  //    a few visible spacing regressions in inline contexts.
  html = html.replace(/[ \t]*\n+[ \t]*/g, '\n');
  // Collapse double-newlines to single (was being introduced by stripped
  // comments).
  html = html.replace(/\n{2,}/g, '\n');

  return html;
}

// ── Drive the build ─────────────────────────────────────────────────────────
function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function writePages() {
  ensureDir(DIST);
  ensureDir(path.join(DIST, 'en'));

  for (const page of PAGES) {
    if (!fs.existsSync(page.template)) {
      console.warn(`==> Template missing: ${page.template} — skipping ${page.name}`);
      continue;
    }
    const dict = loadTranslations(page.translationsScript, page.translationsGlobal);

    // IT — the default. Lives at dist/<output> and is served at the root URL.
    const itHtml = renderPage(page, 'it', dict);
    fs.writeFileSync(path.join(DIST, page.output), itHtml);
    console.log(`  wrote dist/${page.output} (it, ${itHtml.length} bytes)`);

    // EN — under /en/.
    const enHtml = renderPage(page, 'en', dict);
    fs.writeFileSync(path.join(DIST, 'en', page.output), enHtml);
    console.log(`  wrote dist/en/${page.output} (en, ${enHtml.length} bytes)`);
  }
}

console.log('==> Generating per-language static HTML...');
writePages();
console.log('==> Done.');
