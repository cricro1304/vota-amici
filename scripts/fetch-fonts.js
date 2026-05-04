#!/usr/bin/env node
/* ==========================================================================
   Fetches Latin-subsetted woff2 files for the fonts the landing + packs
   pages actually use, places them in `public/fonts/` so they ship as
   same-origin static assets via the existing `cp -R public/. dist/` step
   in build.sh.

   Why we do this instead of just linking to Google Fonts:
     • Removes the third-party DNS+TCP+TLS handshake to fonts.gstatic.com
       from the critical path. On Slow 4G that handshake costs ~600-1500ms
       of FCP/LCP because gstatic isn't on the same connection as the
       origin (HTTP/2 multiplexing only helps for same-origin resources).
     • HTTP cache partitioning (Chrome Oct 2020 / Safari 16) means
       fonts.gstatic.com fonts no longer benefit from cross-site caching,
       so the "shared CDN" argument for Google Fonts is dead.
     • We only download the weights actually rendered:
         Fredoka  500, 600, 700
         Nunito   400, 600, 700, 800
       (See the grep in the project notes — Fredoka 300/400 were loaded
       by the old URL but never used in any rule.)

   Strategy: hit fonts.googleapis.com/css2 with a Chrome User-Agent (so
   Google serves us a woff2-flavored CSS), pull the URL of the *latin*
   @font-face block out of the response, and download the woff2 directly.
   No npm dependency.

   Run: `node scripts/fetch-fonts.js`. Idempotent — overwrites existing
   files. Re-run whenever Google updates a font (rare).
   ========================================================================== */

'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');

const FONTS = [
  // Order matters only for log readability — heaviest-used weight last so
  // it's the most recent line on screen.
  { family: 'Fredoka', weights: [500, 600, 700] },
  { family: 'Nunito',  weights: [400, 600, 700, 800] },
];

const OUT_DIR = path.resolve(__dirname, '..', 'public', 'fonts');

// Chrome UA so Google Fonts serves us woff2 (the default UA gets older
// formats). Specific version doesn't matter as long as it's a real Chrome.
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

function fetch(url, headers, redirects = 5) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { ...headers } }, (res) => {
      // Follow 30x redirects (Google Fonts rarely uses them but be safe).
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        if (redirects <= 0) return reject(new Error('too many redirects'));
        return fetch(res.headers.location, headers, redirects - 1).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

// Parse `url(https://...woff2)` out of the FIRST @font-face block whose
// unicode-range is the latin set (U+0000-00FF + a few extras). Google
// Fonts ships separate blocks per range — latin-ext, cyrillic, greek,
// vietnamese, latin — and we want only the smallest one, "latin".
function extractLatinWoff2Url(css) {
  // Split on `@font-face` so each block is a single rule. Skip the first
  // chunk (preamble before the first rule).
  const blocks = css.split(/@font-face/).slice(1);
  // Match the "latin" block (unicode-range starting at U+0000-00FF).
  // Note: Google Fonts uses `unicode-range: U+0000-00FF, ...` for latin.
  const latin = blocks.find((b) => /U\+0000-00FF/i.test(b));
  if (!latin) return null;
  const m = latin.match(/url\((https:[^)]+\.woff2)\)/);
  return m ? m[1] : null;
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  console.log(`==> Fetching woff2 files into ${path.relative(process.cwd(), OUT_DIR)}/`);

  let totalBytes = 0;
  for (const { family, weights } of FONTS) {
    for (const weight of weights) {
      const cssUrl =
        `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family)}` +
        `:wght@${weight}&display=swap`;
      const cssBuf = await fetch(cssUrl, { 'User-Agent': UA });
      const woff2Url = extractLatinWoff2Url(cssBuf.toString('utf8'));
      if (!woff2Url) {
        console.error(`  ! ${family} ${weight}: no latin woff2 URL in Google Fonts CSS`);
        process.exitCode = 1;
        continue;
      }
      const woff2Buf = await fetch(woff2Url, { 'User-Agent': UA });
      const fname = `${family.toLowerCase()}-${weight}-latin.woff2`;
      fs.writeFileSync(path.join(OUT_DIR, fname), woff2Buf);
      totalBytes += woff2Buf.length;
      console.log(`  ✓ ${fname}  (${woff2Buf.length.toLocaleString()} bytes)`);
    }
  }
  console.log(`==> Total: ${totalBytes.toLocaleString()} bytes across ${
    FONTS.reduce((n, f) => n + f.weights.length, 0)
  } files`);
}

main().catch((e) => { console.error(e); process.exit(1); });
