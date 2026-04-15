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
    // Fall back to the browser language hint, then default.
    var nav = (navigator.language || '').slice(0, 2).toLowerCase();
    if (SUPPORTED.indexOf(nav) !== -1) return nav;
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

    // 3. Apply translations to all [data-i18n] elements. Defer the bulk
    //    DOM work to the next frame so the click feedback (button active
    //    state, language attr) paints first — otherwise the synchronous
    //    rewrite of dozens of nodes blocks the click for ~100ms+ on
    //    mid-tier mobiles and the whole interaction feels frozen.
    var run = function () {
      var nodes = document.querySelectorAll('[data-i18n]');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var key = el.getAttribute('data-i18n');
        var val = dict[key];
        if (val == null) continue;
        if (looksLikeHtml(val)) {
          // innerHTML only when the value actually contains markup.
          if (el.innerHTML !== val) el.innerHTML = val;
        } else {
          // textContent is ~10x faster than innerHTML for plain strings
          // and skips the parser entirely. It also clobbers any HTML
          // child structure, which is exactly what we want for these.
          if (el.textContent !== val) el.textContent = val;
        }
      }
    };
    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(run);
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
