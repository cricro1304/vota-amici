# PageSpeed Insights — Report aggiornato (16 apr 2026)

**URL analizzato:** https://ilpiu.org/landing-page.html
**Strategia:** Mobile
**Run ID PSI:** `34v9lno3as` ([link](https://pagespeed.web.dev/analysis/https-ilpiu-org-landing-page-html/34v9lno3as?form_factor=mobile&hl=it))

## Punteggi Lighthouse

| Categoria | Punteggio | vs. run precedente (14 apr, `my79hua7hk`) |
|---|---|---|
| **Prestazioni** | **57** 🔴 | −35 (era 92) |
| Accessibilità | **88** 🟠 | invariato |
| Best practice | **100** 🟢 | invariato |
| SEO | **100** 🟢 | invariato |

La regressione sulle prestazioni è netta: la pagina è passata dalla fascia "buono" a "scarso" in due giorni.

## Core Web Vitals (lab)

| Metrica | Valore | Stato |
|---|---|---|
| First Contentful Paint | **9,2 s** | ❌ fail |
| Largest Contentful Paint | **9,2 s** | ❌ fail |
| Speed Index | **9,2 s** | ❌ fail |
| Total Blocking Time | 0 ms | ✅ pass |
| Cumulative Layout Shift | 0 | ✅ pass |

FCP e LCP arrivano insieme a 9,2 s: il primo paint è completamente bloccato finché non arriva la CSS/JS di testa.

## Opportunità ordinate per impatto

### 1. 🔴 Richieste di blocco del rendering — risparmio stimato **9 260 ms**

Catene bloccanti rilevate nel report:

| URL | Transfer | Durata |
|---|---|---|
| `assets/css/landing.css` | 15,7 KiB | 160 ms |
| `assets/css/shared.css` | 1,9 KiB | — |
| `assets/js/i18n.js` | 2,1 KiB | 120 ms |
| `assets/js/landing.translations.js` | 7,5 KiB | 160 ms |
| `assets/js/landing.js` | 6,6 KiB | 120 ms |
| `fonts.googleapis.com/css2?family=Fredoka…` | 3,5 KiB | 200 ms |

Tutti e sei sono in blocco perché in `landing-page.html` sono inclusi nel classico schema sincrono:

- righe **14, 16, 17** → `<link rel="stylesheet" …>` per Google Fonts, `shared.css`, `landing.css`.
- righe **678-680** → tre `<script src="…">` senza `defer`/`async`.

### 2. 🟠 Minimizza CSS — risparmio ~5 KiB

`assets/css/landing.css` viene servito non minimizzato (65 KB sorgente, 15,7 KB trasferiti: nessun build step di minificazione + probabile gzip ma non brotli-level).

### 3. 🟠 Minimizza JavaScript — risparmio ~3 KiB

`assets/js/landing.js` è servito non minimizzato (20 KB sorgente, 6,1 KB trasferiti, 2,6 KB di risparmio stimato).

### 4. ℹ️ Diagnostiche informative

- **Evita animazioni non composite** — 3 elementi animati non compositi. Nel CSS ci sono keyframe che animano proprietà non composite (es. `@keyframes winnerPulse` → `box-shadow` in `landing.css:515`, `@keyframes dots` → `content` in `landing.css:780`). Vanno ricondotte a `transform` + `opacity`.
- **Evita attività lunghe nel thread principale** — 2 long task rilevati (erano 1 nel run precedente).
- **Adattamento dinamico forzato del contenuto** (forced reflow).
- **Albero delle dipendenze di rete** — segnala la catena `HTML → CSS → font → JS traduzioni → JS principale` come percorso critico.

## Accessibilità (88) — audit falliti

1. **Contrasto colore insufficiente.** I punti sospetti nel codice attuale:
   - `rgba(255, 255, 255, 0.8)` come testo su gradient rosa/ciano (`landing.css:1085`, `.questions-section .section-subtitle`). 80% di opacità sul rosa `#e6366e` scende sotto 4,5:1.
   - `color: var(--pink)` (= `#e6366e`) su sfondo `--bg` (`#fff8ed`) → contrasto ≈ 4,3:1, fallisce AA per testo normale.
   - `color: var(--pink)` su `--pink-light` (`#f9d1dc`) in `.pack-tile` e `.mode-card` → contrasto ≈ 2,8:1, fallisce.
2. **Il documento non ha un landmark `<main>`.** Né `landing-page.html` né `packs.html` dichiarano `<main>…</main>` (verificato con grep).
3. 10 controlli segnalati per revisione manuale (focus visibile, ordine tab, label aria, ecc.).

## Best practice (100) e SEO (100)

Tutti gli audit passano (CSP anti-XSS, HSTS, COOP, XFO, Trusted Types). SEO OK, rimane solo il check manuale "Dati strutturati validi".

---

# Cosa migliorare sul progetto `vota-amici`

Tutti i percorsi sono relativi alla root del progetto.

## Priorità 1 — Sbloccare il render (−9 s potenziali)

**`landing-page.html` righe 12-17 (head)**: cambiare l'ordine e rendere il CSS non critico asincrono.

```html
<!-- Preload del font WOFF2 effettivo, non solo del CSS descriptor -->
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>

<!-- Inline del critical CSS (hero + nav) direttamente in <style> -->
<style>/* ≈ 4 KiB estratti da shared.css + hero di landing.css */</style>

<!-- Resto del CSS caricato in modo non bloccante -->
<link rel="preload" href="assets/css/landing.css" as="style" onload="this.rel='stylesheet'">
<noscript><link rel="stylesheet" href="assets/css/landing.css"></noscript>

<!-- Google Fonts: swap già c'è, ma va spostato giù o usato &display=swap + preload del woff2 -->
<link rel="preload" as="style"
      href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;600;700&family=Nunito:wght@600;700&display=swap"
      onload="this.rel='stylesheet'">
```

**`landing-page.html` righe 678-680**: aggiungere `defer` a tutti e tre gli script (o `type="module"` che è deferito di default) e, se possibile, concatenare `i18n.js` + `landing.translations.js` + `landing.js` in un unico bundle.

```html
<script src="assets/js/i18n.js" defer></script>
<script src="assets/js/landing.translations.js" defer></script>
<script src="assets/js/landing.js" defer></script>
```

`defer` da solo toglie i tre script dal percorso critico e li esegue dopo il parse dell'HTML: già questo dovrebbe fare crollare FCP/LCP sotto i 3 s.

Se il bundle serve subito (es. il selettore di lingua nel nav), valutare un mini-hydration script inline per `setLang()` ed `applyI18n()` e tenere il resto `defer`.

## Priorità 2 — Minificazione (−8 KiB)

Il progetto ha già `build.sh` e `scripts/`. Aggiungere uno step di minificazione:

```sh
# nel build.sh
npx esbuild public/assets/js/landing.js \
  --bundle=false --minify --outfile=dist/assets/js/landing.js
npx esbuild public/assets/css/landing.css --minify --loader:.css=css --outfile=dist/assets/css/landing.css
```

In alternativa, in `vercel.json` attivare `"cleanUrls": true` e affidarsi a `@vercel/static-build` con un piccolo script di minify (lightningcss, csso, terser). Serve zero configurazione runtime.

## Priorità 3 — Animazioni composite (1-2 ore)

In `public/assets/css/landing.css`:

- **`@keyframes winnerPulse` (riga ~515)** — oggi anima `box-shadow`. Sostituire con un pseudo-elemento `::after` che ha il bagliore e animare solo `opacity`/`transform: scale()`. Esempio:

```css
.winner { position: relative; }
.winner::after {
  content: ""; position: absolute; inset: -8px; border-radius: inherit;
  box-shadow: 0 0 40px rgba(245, 197, 24, 0.5);
  opacity: 0; will-change: opacity;
  animation: winnerPulseOpacity 2s ease-in-out infinite;
}
@keyframes winnerPulseOpacity {
  0%, 100% { opacity: 0.5; }
  50%      { opacity: 1; }
}
```

- **`@keyframes dots` (riga ~780)** — anima `content`, non è composita e non è davvero utile. Sostituire con tre span animati in `opacity`.

## Priorità 4 — Accessibilità

1. **Aggiungere `<main>`** in `landing-page.html` e `packs.html`. Fix di una riga: aprire `<main>` dopo il `<nav>` e chiuderlo prima del footer/script.

2. **Contrasto** — in `public/assets/css/shared.css` scurire leggermente `--pink`:

```css
:root {
  --pink:      #d1235b;   /* era #e6366e — ~5,2:1 su bianco, ~4,9:1 su #fff8ed */
  --pink-ink:  #a81448;   /* da usare quando il testo sta su --pink-light */
}
```

Poi nei punti dove oggi hai `color: var(--pink)` su `--pink-light` o `--bg`, passare a `color: var(--pink-ink)`.

3. **`landing.css:1085`** — cambiare `color: rgba(255, 255, 255, 0.8)` in `color: #ffffff` (o almeno `0.95`): su gradient rosa/ciano serve pieno contrasto.

## Priorità 5 — Long task e DOM

Le diagnostiche "2 long task" e "Optimize DOM size" non sono bloccanti, ma conviene:

- Chunkare l'inizializzazione i18n in `landing.js`: la traduzione di centinaia di nodi in un solo ciclo è probabilmente una delle long task. Usare `requestIdleCallback` o un `setTimeout(..., 0)` per applicare le traduzioni in batch dopo il primo paint.
- Ridurre la `.slot-machine` e i `.blob` ridondanti del hero se non necessari sopra il fold.

---

## Riassunto operativo (sprint di ~4 ore)

| # | File | Intervento | Stima impatto |
|---|---|---|---|
| 1 | `landing-page.html` (riga 678-680) | Aggiungere `defer` ai tre `<script>` | **LCP ↓ ~1,5 s** |
| 2 | `landing-page.html` (riga 14-17) | Inline critical CSS + `preload onload` per il resto | **LCP ↓ ~2-3 s** |
| 3 | `build.sh` | Step di minify CSS+JS con esbuild/lightningcss | **−8 KiB / −200 ms TTFB→paint** |
| 4 | `landing-page.html`, `packs.html` | Wrappare il contenuto in `<main>` | **Accessibility +4** |
| 5 | `shared.css` | Scurire `--pink` e aggiungere `--pink-ink` | **Accessibility +6-8** |
| 6 | `landing.css` (riga 515, 780) | Riscrivere `winnerPulse` e `dots` su transform/opacity | diagnostica pulita |
| 7 | `landing.js` | Traduzione i18n in batch con `requestIdleCallback` | long-task rimossi |

Dopo gli step 1-3 mi aspetto che il punteggio Prestazioni torni **≥ 90** e LCP < 2,5 s; step 4-5 portano Accessibilità in area 95+.
