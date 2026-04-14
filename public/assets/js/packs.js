/* ==========================================================================
   Packs page logic — Chi è il più...?
   Depends on: i18n.js, packs.translations.js (window.PACKS_TRANSLATIONS).
   All the page does is wire up setLang; the rest of the content is static HTML.
   ========================================================================== */

(function () {
  'use strict';

  var translations = window.PACKS_TRANSLATIONS;

  // Exposed globally so the inline onclick="setLang('it')" handlers work.
  window.setLang = function (lang) {
    window.I18n.applyTranslations(lang, translations[lang]);
  };

  // Boot with the user's stored/preferred language.
  window.setLang(window.I18n.getStoredLang());
})();
