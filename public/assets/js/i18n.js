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

  function applyTranslations(lang, dict) {
    if (!dict) return;

    // 1. Persist the choice across pages and reloads.
    if (SUPPORTED.indexOf(lang) !== -1) safeSet(lang);

    // 2. Sync the language toggle buttons.
    document.querySelectorAll('.lang-btn').forEach(function (btn) {
      btn.classList.remove('active');
    });
    var activeBtn = document.querySelector(
      '.lang-btn[onclick="setLang(\'' + lang + '\')"]'
    );
    if (activeBtn) activeBtn.classList.add('active');

    // 3. Apply translations to all [data-i18n] elements.
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      if (dict[key]) el.innerHTML = dict[key];
    });

    // 4. Update the document language attribute.
    document.documentElement.lang = lang;
  }

  window.I18n = {
    applyTranslations: applyTranslations,
    getStoredLang:     getStoredLang,
    SUPPORTED:         SUPPORTED
  };
})();
