/* ==========================================================================
   Shared i18n helper — Chi è il più...?
   Exposes window.I18n.applyTranslations(lang, dict).
   Each page wires its own setLang that calls this and runs page-specific
   side effects (carousel rebuild, etc.).
   ========================================================================== */

(function () {
  'use strict';

  var STORAGE_KEY = 'cipp_lang';
  var SUPPORTED   = ['it', 'en'];
  var DEFAULT     = 'it';

  // Safe localStorage access (private mode / disabled storage falls back to no-op).
  function safeGet() {
    try { return window.localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }
  function safeSet(val) {
    try { window.localStorage.setItem(STORAGE_KEY, val); } catch (e) { /* ignore */ }
  }

  function getStoredLang() {
    var stored = safeGet();
    if (stored && SUPPORTED.indexOf(stored) !== -1) return stored;
    // No fallback to navigator.language. Doing so meant English-locale
    // browsers triggered an auto-load of landing.translations.js on
    // every first visit — and during the load + apply, the main thread
    // was blocked for ~100-300ms (script parse + 70-node DOM walk),
    // making buttons feel unresponsive. With explicit-only storage,
    // first-visit users see Italian (the HTML seed) regardless of
    // browser locale; the IT/EN toggle in the nav lets EN visitors
    // opt in, and from then on their preference is persisted.
    return DEFAULT;
  }

  // Quick check: does this dictionary value contain HTML markup? If not,
  // we can use textContent (cheap) instead of innerHTML (parser + tree
  // rebuild) — the difference is huge on pages with 70+ data-i18n nodes.
  var HTML_TAG_RE = /<[a-z][\s\S]*?>/i;
  var HTML_ENTITY_RE = /&(?:[a-z0-9]+|#\d+|#x[0-9a-f]+);/i;
  function looksLikeHtml(s) {
    return HTML_TAG_RE.test(s) || HTML_ENTITY_RE.test(s);
  }

  function applyTranslations(lang, dict) {
    if (!dict) return;

    // 1. Persist the choice across pages and reloads.
    if (SUPPORTED.indexOf(lang) !== -1) safeSet(lang);

    // 2. Sync the language toggle buttons (cheap, do it sync so the
    //    button highlight feels instant).
    document.querySelectorAll('.lang-btn').forEach(function (btn) {
      btn.classList.remove('active');
    });
    var activeBtn = document.querySelector(
      '.lang-btn[onclick="setLang(\'' + lang + '\')"]'
    );
    if (activeBtn) activeBtn.classList.add('active');

    // 4. Update the document language attribute (cheap).
    document.documentElement.lang = lang;

    // 3. Apply translations to all [data-i18n] elements in chunks so
    //    user input (taps, scrolls) can be processed between batches.
    //    Previously this was a single synchronous loop over 70+ nodes
    //    that blocked the main thread for 50-200ms on slow mobile —
    //    long enough that any tap during that window felt unresponsive
    //    ("the button isn't clickable while the translation loads").
    //    The chunked version processes nodes in 5ms slices, yielding
    //    via scheduler.postTask (modern Chrome) or setTimeout (Safari,
    //    Firefox) between slices. Each yield gives the browser a
    //    chance to flush queued input and paint, so taps register
    //    immediately even mid-translation.
    var didRun = false;
    var run = function () {
      if (didRun) return;
      didRun = true;
      var nodes = document.querySelectorAll('[data-i18n]');
      var i = 0;
      var SLICE_MS = 5;

      function applyOne(el) {
        var key = el.getAttribute('data-i18n');
        var val = dict[key];
        if (val == null) return;
        if (looksLikeHtml(val)) {
          if (el.innerHTML !== val) el.innerHTML = val;
        } else {
          if (el.textContent !== val) el.textContent = val;
        }
      }

      function yieldThen(fn) {
        // scheduler.postTask with priority "user-blocking" yields
        // immediately to higher-priority tasks (input, paint) but
        // resumes promptly after. setTimeout(0) is the universal
        // fallback — slightly higher latency but still gives input a
        // chance to run.
        if (typeof scheduler !== 'undefined' &&
            typeof scheduler.postTask === 'function') {
          scheduler.postTask(fn, { priority: 'user-blocking' });
        } else {
          setTimeout(fn, 0);
        }
      }

      function processSlice() {
        var deadline = (typeof performance !== 'undefined'
          ? performance.now()
          : Date.now()) + SLICE_MS;
        while (i < nodes.length) {
          applyOne(nodes[i]);
          i++;
          // Time-budget check every iteration. Cheap (~0.1µs) and the
          // 5ms budget keeps each slice well under the input-handler
          // budget so taps don't queue.
          var now = (typeof performance !== 'undefined'
            ? performance.now()
            : Date.now());
          if (now >= deadline) break;
        }
        if (i < nodes.length) yieldThen(processSlice);
      }

      processSlice();
    };
    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(run);
      // Belt + braces: rAF is throttled (or paused) when the tab is in
      // the background, which on some iOS/Android browsers can delay the
      // translation apply by tens of seconds. A setTimeout fallback kicks
      // in after 250ms so stored-lang content still lands — the `didRun`
      // guard makes whichever callback fires second a no-op.
      setTimeout(run, 250);
    } else {
      run();
    }
  }

  window.I18n = {
    applyTranslations: applyTranslations,
    getStoredLang:     getStoredLang,
    SUPPORTED:         SUPPORTED
  };
})();
