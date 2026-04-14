# PageSpeed Insights Report — ilpiu.org/landing-page.html

**URL analyzed:** https://ilpiu.org/landing-page.html
**Form factor:** Mobile (Emulated Moto G Power, Slow 4G throttling)
**Lighthouse version:** 13.0.1 (HeadlessChromium 146.0.7680.153)
**Captured:** Apr 14, 2026, 11:32 AM GMT+2
**Source:** [PageSpeed Insights run](https://pagespeed.web.dev/analysis/https-ilpiu-org-landing-page-html/my79hua7hk?hl=en&form_factor=mobile)

> Note: the "Discover what your real users are experiencing" panel showed **No Data** — there is no Chrome UX Report (CrUX) field data for this URL yet, so all numbers below are lab metrics from a synthetic Lighthouse run.

## Lighthouse scores

| Category | Score |
|---|---|
| Performance | **92** |
| Accessibility | **88** |
| Best Practices | **100** |
| SEO | **100** |

## Core Web Vitals & lab metrics

| Metric | Value |
|---|---|
| First Contentful Paint (FCP) | 2.6 s |
| Largest Contentful Paint (LCP) | 2.6 s |
| Total Blocking Time (TBT) | 0 ms |
| Cumulative Layout Shift (CLS) | 0.071 |
| Speed Index | 3.2 s |

LCP and FCP are both in the "needs improvement" zone for mobile. CLS is good (< 0.1) but not perfect. TBT is excellent.

## Performance — Insights (with estimated savings)

- **Render-blocking requests** — *Est. savings of 1,710 ms* ← the single biggest opportunity
- Forced reflow
- Network dependency tree
- Layout shift culprits
- Optimize DOM size
- LCP breakdown
- 3rd parties

## Performance — Diagnostics

- **Minify CSS** — Est. savings of 3 KiB
- **Avoid non-composited animations** — 3 animated elements found
- **Avoid long main-thread tasks** — 1 long task found
- 17 audits passed

## Accessibility (88)

Failing items:

- **Contrast** — Background and foreground colors do not have a sufficient contrast ratio.
- **Best Practices** — Document does not have a `<main>` landmark.
- 10 additional items flagged for manual review.
- 10 audits passed; 48 not applicable.

## Best Practices (100)

All trust & safety checks pass:

- CSP effective against XSS
- Strong HSTS policy
- Proper origin isolation with COOP
- Clickjacking mitigated with XFO or CSP
- DOM-based XSS mitigated with Trusted Types
- 13 audits passed; 2 not applicable.

## SEO (100)

- 1 manual-check item: **Structured data is valid** (run an external validator to confirm).
- 8 audits passed; 2 not applicable.

---

## What to fix first (priority order)

1. **Eliminate render-blocking resources** — ~1.7 s of LCP/FCP improvement on its own. Inline critical CSS, defer non-critical CSS (`media="print"` swap or `rel="preload"` + `onload`), and add `defer`/`async` to scripts that aren't needed for the first paint.
2. **Reduce CLS from 0.071 → < 0.05** — set explicit `width`/`height` (or `aspect-ratio`) on images and embeds so reserved space matches what loads. Check the "Layout shift culprits" insight for the offending elements.
3. **Fix the contrast failure** — bump foreground/background contrast to ≥ 4.5:1 for normal text (3:1 for large text). This alone will likely move Accessibility back into the 90s.
4. **Add a `<main>` landmark** — wrap the primary content in `<main>…</main>`. One-line fix.
5. **Minify CSS** — 3 KiB. Trivial via build step or hosting platform option.
6. **Investigate the 1 long main-thread task and 3 non-composited animations** — TBT is currently 0 ms so this isn't urgent, but the animations may be contributing to the CLS or paint cost.
