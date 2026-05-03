/* ==========================================================================
   Packs page logic — Chi è il più...?

   Intentionally empty. The previous version's only job was to call
   I18n.applyTranslations() at boot to swap the HTML's seeded Italian
   text for the user's preferred language. Now the page is generated
   per-language at build time (scripts/build-i18n.js) — the EN version
   lives at /en/packs.html, the IT version at /packs.html — so there's
   no runtime translation work to do. The packs page is fully static.

   Kept as an empty stub so existing <script src="assets/js/packs.js">
   tags don't 404 if any cached HTML is still referencing it from
   before this refactor lands. Once cache lifetimes have flushed
   (~1 week after deploy) this file can be deleted along with the
   <script> tag in packs.html.
   ========================================================================== */
