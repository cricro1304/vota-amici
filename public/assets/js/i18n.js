/* ==========================================================================
   Shared i18n helper — Chi è il più...?
   Exposes window.I18n.applyTranslations(lang, dict).
   Each page wires its own setLang that calls this and runs page-specific
   side effects (carousel rebuild, etc.).
   ========================================================================== */

(function () {
  'use strict';

  function applyTranslations(lang, dict) {
    if (!dict) return;

    // 1. Sync the language toggle buttons.
    document.querySelectorAll('.lang-btn').forEach(function (btn) {
      btn.classList.remove('active');
    });
    var activeBtn = document.querySelector(
      '.lang-btn[onclick="setLang(\'' + lang + '\')"]'
    );
    if (activeBtn) activeBtn.classList.add('active');

    // 2. Apply translations to all [data-i18n] elements.
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      if (dict[key]) el.innerHTML = dict[key];
    });

    // 3. Update the document language attribute.
    document.documentElement.lang = lang;
  }

  window.I18n = { applyTranslations: applyTranslations };
})();
