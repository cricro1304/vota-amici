/* ==========================================================================
   Landing page logic — Chi è il più...?
   Depends on: i18n.js, landing.translations.js (window.LANDING_TRANSLATIONS).

   Sections:
     1. Demo data (players + question rounds)
     2. Phone carousel (auto-cycling hero demo screens)
     3. i18n (setLang + question carousel rebuild)
     4. Pack tile interactions (hover popup + mobile bottom sheet)
     5. Scroll-driven tutorial phone coordination
     6. Chat bubble scroll-in animations
   ========================================================================== */

(function () {
  'use strict';

  /* ── 1. Demo data ────────────────────────────────────────────────────── */
  var players = [
    { name: 'Marco',  short: 'Ma', color: 'var(--pink)'   },
    { name: 'Luca',   short: 'Lu', color: 'var(--cyan)'   },
    { name: 'Giulia', short: 'Gi', color: 'var(--teal)'   },
    { name: 'Sara',   short: 'Sa', color: 'var(--purple)' }
  ];

  var questionRounds = {
    it: [
      { emoji: '😴',  question: 'Chi è il più pigro?',        badge: 'Domanda 3 di 15',  reveal: 'Il più pigro è...',        winnerIdx: 1, winnerEmoji: '😴',  votes: 3 },
      { emoji: '🎭',  question: 'Chi è il più drammatico?',   badge: 'Domanda 7 di 15',  reveal: 'Il più drammatico è...',   winnerIdx: 0, winnerEmoji: '🎭',  votes: 2 },
      { emoji: '😄',  question: 'Chi è il più simpatico?',    badge: 'Domanda 1 di 15',  reveal: 'Il più simpatico è...',    winnerIdx: 2, winnerEmoji: '😄',  votes: 3 },
      { emoji: '💪',  question: 'Chi è il più testardo?',     badge: 'Domanda 11 di 15', reveal: 'Il più testardo è...',     winnerIdx: 3, winnerEmoji: '💪',  votes: 4 },
      { emoji: '🗣️', question: 'Chi è il più chiacchierone?', badge: 'Domanda 5 di 15',  reveal: 'Il più chiacchierone è...', winnerIdx: 2, winnerEmoji: '🗣️', votes: 3 },
      { emoji: '🍕',  question: 'Chi è il più goloso?',       badge: 'Domanda 9 di 15',  reveal: 'Il più goloso è...',       winnerIdx: 0, winnerEmoji: '🍕',  votes: 2 }
    ],
    en: [
      { emoji: '😴',  question: 'Who\'s the laziest?',        badge: 'Question 3 of 15',  reveal: 'The laziest is...',        winnerIdx: 1, winnerEmoji: '😴',  votes: 3 },
      { emoji: '🎭',  question: 'Who\'s the most dramatic?',  badge: 'Question 7 of 15',  reveal: 'The most dramatic is...',  winnerIdx: 0, winnerEmoji: '🎭',  votes: 2 },
      { emoji: '😄',  question: 'Who\'s the funniest?',       badge: 'Question 1 of 15',  reveal: 'The funniest is...',       winnerIdx: 2, winnerEmoji: '😄',  votes: 3 },
      { emoji: '💪',  question: 'Who\'s the most stubborn?',  badge: 'Question 11 of 15', reveal: 'The most stubborn is...',  winnerIdx: 3, winnerEmoji: '💪',  votes: 4 },
      { emoji: '🗣️', question: 'Who\'s the biggest talker?', badge: 'Question 5 of 15',  reveal: 'The biggest talker is...', winnerIdx: 2, winnerEmoji: '🗣️', votes: 3 },
      { emoji: '🍕',  question: 'Who\'s the biggest foodie?', badge: 'Question 9 of 15',  reveal: 'The biggest foodie is...', winnerIdx: 0, winnerEmoji: '🍕',  votes: 2 }
    ]
  };

  // Translations are lazy-loaded — see loadTranslations() below.
  // Read window.LANDING_TRANSLATIONS at use-time, not boot-time, so the
  // setLang call works whether the dictionary is already present or
  // arrives later via the dynamically-injected <script>.
  function getTranslations() { return window.LANDING_TRANSLATIONS; }

  var translationsLoading = null; // promise-like: array of pending callbacks
  function loadTranslations(callback) {
    if (getTranslations()) { callback(); return; }
    if (translationsLoading) { translationsLoading.push(callback); return; }
    translationsLoading = [callback];
    var script = document.createElement('script');
    script.src = 'assets/js/landing.translations.js';
    script.async = true;
    script.onload = function () {
      var pending = translationsLoading;
      translationsLoading = null;
      pending.forEach(function (cb) { cb(); });
    };
    script.onerror = function () { translationsLoading = null; };
    document.head.appendChild(script);
  }


  /* ── 2. Phone carousel (hero demo) ──────────────────────────────────── */
  var currentLang = (window.I18n && window.I18n.getStoredLang) ? window.I18n.getStoredLang() : 'it';
  var roundIndex = 0;
  var screens = document.querySelectorAll('.app-screen');
  var currentScreen = 0;

  // Whether the hero carousel should auto-cycle; flipped by scroll observers.
  var heroCarouselRunning = true;

  function applyRound() {
    var rounds = questionRounds[currentLang] || questionRounds.it;
    var r = rounds[roundIndex % rounds.length];
    var winner = players[r.winnerIdx];

    // Screen 1 — question + initial vote highlight
    document.querySelector('.q-badge').textContent = r.badge;
    document.querySelector('.q-emoji').textContent = r.emoji;
    document.querySelector('.q-text').textContent  = r.question;

    var voteButtons = document.querySelectorAll('.vote-btn');
    voteButtons.forEach(function (b) { b.classList.remove('selected'); });
    voteButtons[r.winnerIdx].classList.add('selected');

    // Screen 2 — result; keep colors consistent with the winner
    var scope = '#screen2 ';
    document.querySelector(scope + '.result-label').textContent = r.reveal;

    var innerEl = document.querySelector(scope + '.result-winner-inner');
    innerEl.textContent = winner.short;
    innerEl.style.background = winner.color;

    var ring = document.querySelector(scope + '.result-winner-ring');
    ring.style.background = 'linear-gradient(135deg, ' + winner.color + ', var(--yellow))';

    document.querySelector(scope + '.result-name').textContent = winner.name + '! ' + r.winnerEmoji;
    document.querySelector(scope + '.result-votes').innerHTML =
      '🏆 ' + (currentLang === 'en'
        ? 'with ' + r.votes + ' votes!'
        : 'con '  + r.votes + ' voti!');
  }

  function nextScreen() {
    screens[currentScreen].classList.remove('active');
    currentScreen = (currentScreen + 1) % screens.length;
    screens[currentScreen].classList.add('active');

    // Looping back to screen 1 means a new round.
    if (currentScreen === 0) {
      roundIndex++;
      applyRound();
    }
  }

  // Vote selection cycles through players every 1.2s while on screen 1.
  // Cache .vote-btn lookup once instead of querying every tick — the
  // selector is stable for the lifetime of the page.
  var voteButtons = document.querySelectorAll('.vote-btn');
  var voteIndex = -1;
  var voteInterval = null;
  function startVoteCycle() {
    if (voteInterval) return;
    voteInterval = setInterval(function () {
      if (heroCarouselRunning && screens[0].classList.contains('active')) {
        for (var i = 0; i < voteButtons.length; i++) {
          voteButtons[i].classList.remove('selected');
        }
        voteIndex = (voteIndex + 1) % voteButtons.length;
        voteButtons[voteIndex].classList.add('selected');
        // The winner will be re-selected on the next screen change (see applyRound).
      }
    }, 1200);
  }

  // Carousel timer — only advances when in hero mode.
  var carouselInterval = null;
  function startCarousel() {
    if (carouselInterval) clearInterval(carouselInterval);
    carouselInterval = setInterval(function () {
      if (heroCarouselRunning) nextScreen();
    }, 3000);
  }


  /* ── 3. i18n ────────────────────────────────────────────────────────── */
  // The question carousel is seeded with Italian chips directly in the HTML
  // so the marquee has something to scroll on the very first paint, even if
  // landing.js loads late (flaky connections, cold-start cache miss, etc.).
  // buildCarousel() only swaps content when the lang actually differs from
  // what's currently rendered — repeated calls with the same lang are a
  // no-op. This matters because innerHTML replacement + `width: max-content`
  // forces a full reflow of the track, and the running `translateX(-50%)`
  // animation keyframe is pinned to the old width, so you'd see a visible
  // "jump" or freeze right after every swap.
  function makeChips(arr) {
    return arr.concat(arr) // duplicate so the marquee can loop seamlessly
      .map(function (q) { return '<span class="question-chip">' + q + '</span>'; })
      .join('');
  }

  function restartTrackAnimation(track) {
    // Toggle the animation off/on so the keyframe re-reads the fresh
    // width. Without this, the scroll-left/scroll-right animations stay
    // anchored to the previous content's width and visibly stall on the
    // language toggle. Use a double-rAF instead of `void offsetWidth` —
    // the offsetWidth read is a synchronous forced layout (PSI flagged
    // it as 39ms of forced reflow on initial boot). The rAF version
    // lets the browser do the work between paint frames where it's
    // free, with no main-thread cost during the boot critical path.
    var prev = track.style.animation;
    track.style.animation = 'none';
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        track.style.animation = prev || '';
      });
    });
  }

  function buildCarousel() {
    var translations = getTranslations();
    if (!translations) return;
    var t = translations[currentLang];
    if (!t) return;
    var track1 = document.getElementById('qTrack1');
    var track2 = document.getElementById('qTrack2');
    if (!track1 || !track2) return;

    // Skip rebuilds when the DOM already reflects the target language. This
    // makes the boot-time setLang(currentLang) call a pure no-op when the
    // HTML seed matches the stored lang (the common case for IT users).
    var track1Lang = track1.getAttribute('data-seeded-lang');
    var track2Lang = track2.getAttribute('data-seeded-lang');
    if (track1Lang === currentLang && track2Lang === currentLang) return;

    track1.innerHTML = makeChips(t.carousel_row1);
    track2.innerHTML = makeChips(t.carousel_row2);
    track1.setAttribute('data-seeded-lang', currentLang);
    track2.setAttribute('data-seeded-lang', currentLang);

    // Re-kick both marquee animations so they re-measure against the new
    // content width — otherwise the keyframes are anchored to the previous
    // language's chip set and the track visibly freezes / jumps.
    restartTrackAnimation(track1);
    restartTrackAnimation(track2);
  }

  // Exposed globally so the inline onclick="setLang('it')" handlers work.
  // applyTranslations defers its data-i18n bulk to rAF for snappier toggle
  // feedback. buildCarousel + applyRound stay synchronous because the
  // question-track marquee animation needs its content present on the
  // same frame the .question-track element exists, otherwise the CSS
  // animation runs against an empty element and visibly stalls.
  //
  // Lazy-loads the translations dictionary on first call. For default IT
  // visitors whose stored lang matches the HTML seed, setLang is never
  // called on boot (see boot section below) and the translations file is
  // never fetched — saving ~7KB of transfer + 22KB of JS parse.
  window.setLang = function (lang) {
    loadTranslations(function () {
      var translations = getTranslations();
      if (!translations) return; // network error — fall back to current lang
      currentLang = lang;
      window.I18n.applyTranslations(lang, translations[lang]);
      buildCarousel();
      applyRound();
    });
  };


  /* ── 4. Pack tile interactions ──────────────────────────────────────── */
  // All DOM lookups + listener attachment for this block are wrapped in
  // setupPackTileInteractions() so they only run during the deferred
  // boot phase (initBackgroundWork). Doing this synchronously at IIFE-
  // execute time was contributing ~200ms of input-delay during initial
  // load — the user's tap on the hero CTA had to wait behind 14
  // listeners + several DOM walks even though packs sit far below the
  // fold and can't be interacted with in the first second anyway.
  var isMobileView = function () { return window.innerWidth <= 600; };

  function setupPackTileInteractions() {
    var packSheet         = document.getElementById('packSheet');
    var packBackdrop      = document.getElementById('packBackdrop');
    var packSheetTitle    = document.getElementById('packSheetTitle');
    var packSheetDesc     = document.getElementById('packSheetDesc');
    var packSheetExamples = document.getElementById('packSheetExamples');

    function openPackSheet(tile) {
      var popup = tile.querySelector('.pack-tile-popup');
      if (!popup) return;

      var title = tile.querySelector('h4');
      var emoji = tile.querySelector('.pack-tile-emoji');
      packSheetTitle.textContent = (emoji ? emoji.textContent + ' ' : '') +
                                   (title ? title.textContent : '');

      var descEl = popup.querySelector('.pack-tile-desc');
      packSheetDesc.textContent = descEl ? descEl.textContent : '';

      packSheetExamples.innerHTML = '';
      popup.querySelectorAll('.pack-tile-chip').forEach(function (c) {
        var span = document.createElement('span');
        span.className = c.className;
        span.textContent = c.textContent;
        packSheetExamples.appendChild(span);
      });

      packBackdrop.classList.add('open');
      packSheet.style.display = 'block';
      // Two RAFs to ensure the transition runs from the initial translateY(100%).
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { packSheet.classList.add('open'); });
      });
    }

    function closePackSheet() {
      packSheet.classList.remove('open');
      packBackdrop.classList.remove('open');
      setTimeout(function () { packSheet.style.display = 'none'; }, 350);
    }

    if (packBackdrop) packBackdrop.addEventListener('click', closePackSheet);

    // Clamp popup position so it doesn't overflow viewport (desktop/tablet only).
    function clampPopup(tile) {
      if (isMobileView()) return;
      var popup = tile.querySelector('.pack-tile-popup');
      if (!popup) return;

      // Reset to centered before measuring.
      popup.style.left = '50%';
      popup.style.right = 'auto';
      popup.style.transform = 'translateX(-50%) translateY(0)';

      requestAnimationFrame(function () {
        var rect = popup.getBoundingClientRect();
        var vw = window.innerWidth;
        if (rect.right > vw - 16) {
          var shift = rect.right - vw + 20;
          popup.style.left = 'calc(50% - ' + shift + 'px)';
        } else if (rect.left < 16) {
          var shift2 = 16 - rect.left;
          popup.style.left = 'calc(50% + ' + shift2 + 'px)';
        }
      });
    }

    var packTiles = document.querySelectorAll('.pack-tile');
    packTiles.forEach(function (tile) {
      tile.addEventListener('click', function (e) {
        if (isMobileView()) {
          e.stopPropagation();
          openPackSheet(tile);
          return;
        }
        // Desktop: toggle 'touched' for click-to-open popup.
        var wasOpen = tile.classList.contains('touched');
        packTiles.forEach(function (t) { t.classList.remove('touched'); });
        if (!wasOpen) {
          tile.classList.add('touched');
          clampPopup(tile);
        }
      });

      tile.addEventListener('mouseenter', function () { clampPopup(tile); });
    });

    // Click outside any tile closes all open popups.
    document.addEventListener('click', function (e) {
      if (!e.target.closest('.pack-tile')) {
        packTiles.forEach(function (t) { t.classList.remove('touched'); });
      }
    });
  }


  /* ── 5. Scroll-driven tutorial phone coordination ───────────────────── */
  // The phone column shows either the auto-cycling hero carousel or one
  // specific tutorial mockup, depending on which `.tutorial-step` is
  // currently in the reading position.
  //
  // Implemented with IntersectionObserver instead of a scroll listener.
  // The previous version called getBoundingClientRect() for every step
  // on every rAF after scroll — that forced a layout/reflow per scroll
  // frame, which Safari (both desktop and mobile) handles poorly. The
  // visible symptom was content appearing "late" as the user scrolled
  // past sections, plus delayed click responsiveness because the main
  // thread was busy in layout. IntersectionObserver runs off the main
  // thread and only fires when intersection state changes, so scroll
  // stays at 60fps.

  var tutScreens     = document.querySelectorAll('.tut-app-screen');
  var tutSteps       = document.querySelectorAll('.tutorial-step');
  var tutBlockEl     = document.querySelector('.tut-block');
  var screenCarousel = document.getElementById('screenCarousel');

  var currentMode = 'hero';   // 'hero' or 'tutorial'
  var activeTutScreen = 0;    // 0 = none; 1/2/3 = active tutorial screen

  function enterTutorialMode() {
    if (currentMode === 'tutorial') return;
    currentMode = 'tutorial';
    heroCarouselRunning = false;
    if (screenCarousel) screenCarousel.classList.add('faded');
  }

  function enterHeroMode() {
    if (currentMode === 'hero') return;
    currentMode = 'hero';
    heroCarouselRunning = true;
    if (screenCarousel) screenCarousel.classList.remove('faded');

    tutScreens.forEach(function (s) { s.classList.remove('active'); });
    activeTutScreen = 0;
    tutSteps.forEach(function (s) { s.classList.remove('active'); });
  }

  function setTutScreen(n) {
    if (n === activeTutScreen) return;

    if (activeTutScreen > 0) {
      var prev = document.getElementById('tutScreen' + activeTutScreen);
      if (prev) prev.classList.remove('active');
    }
    var next = document.getElementById('tutScreen' + n);
    if (next) next.classList.add('active');
    activeTutScreen = n;

    tutSteps.forEach(function (s) { s.classList.remove('active'); });
    var activeStep = document.querySelector(
      '.tutorial-step[data-tut-screen="' + n + '"]'
    );
    if (activeStep) activeStep.classList.add('active');
  }

  function setupTutorialObservers() {
    if (!tutSteps.length) return;
    if (typeof window.IntersectionObserver !== 'function') return;

    // Track which steps are currently "in the reading zone" (past 55% of
    // viewport from top). The latest such step wins — same semantics as
    // the old scroll handler, but driven by visibility events instead of
    // per-frame layout reads.
    var stepStates = {}; // screenIndex -> boolean (active in reading zone)

    function recomputeActive() {
      var activeScreen = 0;
      // Iterate steps in DOM order so the latest one wins.
      tutSteps.forEach(function (step) {
        var screen = parseInt(step.getAttribute('data-tut-screen'), 10);
        if (stepStates[screen]) activeScreen = screen;
      });
      if (activeScreen > 0) {
        enterTutorialMode();
        setTutScreen(activeScreen);
      } else {
        enterHeroMode();
      }
    }

    // One observer per step so each can have its own rootMargin (the
    // pack-picker step uses data-tut-start-at to activate earlier).
    // rootMargin's bottom value pulls the trigger line up from the
    // viewport bottom, so the step "enters the reading zone" when its
    // top crosses that line — same as the old 0.55 trigger.
    tutSteps.forEach(function (step) {
      var screen  = parseInt(step.getAttribute('data-tut-screen'), 10);
      var startAt = parseFloat(step.getAttribute('data-tut-start-at'));
      var triggerFrac = isNaN(startAt) ? 0.55 : startAt;
      // bottomMargin shifts the bottom edge of the root upward by
      // (1 - triggerFrac) * 100% — so the step counts as intersecting
      // once its top has crossed `triggerFrac` of the viewport.
      var bottomPct = Math.round((1 - triggerFrac) * 100);
      var rootMargin = '0px 0px -' + bottomPct + '% 0px';

      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          stepStates[screen] = entry.isIntersecting;
        });
        recomputeActive();
      }, { rootMargin: rootMargin, threshold: 0 });
      observer.observe(step);
    });

    // Once we've scrolled fully past the tutorial block, snap back to
    // hero mode. A second observer on the block itself watches for that
    // — cheaper than reading getBoundingClientRect() on every scroll.
    if (tutBlockEl) {
      var blockObserver = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting && entry.boundingClientRect.bottom < 0) {
            // Scrolled past the bottom of the tutorial block.
            Object.keys(stepStates).forEach(function (k) { stepStates[k] = false; });
            recomputeActive();
          }
        });
      }, { threshold: 0 });
      blockObserver.observe(tutBlockEl);
    }
  }


  /* ── 6. Verdict reaction easter egg ─────────────────────────────────── */
  // Each reaction chip on a verdict card is clickable. Tapping it bumps
  // the trailing number ("😂 12" → "😂 13"), plays a small pop, and
  // floats a "+1" upwards. Pure local fun — nothing is persisted. Event
  // delegation on .verdicts-board means it survives i18n re-renders that
  // swap child nodes.
  //
  // Wrapped in a function so the DOM lookup + listener attach happens
  // during deferred boot rather than at IIFE-execute time, for the same
  // input-delay reasons as setupPackTileInteractions above.
  function setupVerdictReactions() {
  var verdictsBoardEl = document.querySelector('.verdicts-board');
  if (verdictsBoardEl) {
    // Match either "<emoji> 12" or plain "12" — we only care about the
    // trailing integer and preserve whatever prefix the chip carries.
    var REACT_NUM_RE = /(\d+)\s*$/;

    var bumpReaction = function (chip) {
      // Read text directly; innerHTML may contain our transient .float span.
      var raw = chip.firstChild && chip.firstChild.nodeType === 3
        ? chip.firstChild.nodeValue
        : chip.textContent;
      var m = raw.match(REACT_NUM_RE);
      if (!m) return;
      var next = parseInt(m[1], 10) + 1;
      var prefix = raw.slice(0, m.index); // emoji + space
      // Replace only the text node so the floating "+1" span (if any) stays.
      if (chip.firstChild && chip.firstChild.nodeType === 3) {
        chip.firstChild.nodeValue = prefix + next;
      } else {
        chip.textContent = prefix + next;
      }

      // Pop animation — re-trigger by removing + re-adding the class.
      // Double-rAF avoids the forced reflow of `void chip.offsetWidth`.
      chip.classList.remove('bump');
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { chip.classList.add('bump'); });
      });

      // Floating "+1" indicator.
      var floater = document.createElement('span');
      floater.className = 'verdict-react-float';
      floater.textContent = '+1';
      chip.appendChild(floater);
      // Clean up after the animation completes (0.9s from CSS).
      setTimeout(function () {
        if (floater.parentNode) floater.parentNode.removeChild(floater);
      }, 950);
    };

    verdictsBoardEl.addEventListener('click', function (e) {
      // Walk up from the event target to find a reaction chip. Chips are
      // <span> elements inside .verdict-reactions. This also catches
      // clicks on the floating "+1" child and attributes them to parent.
      var node = e.target;
      while (node && node !== verdictsBoardEl) {
        if (node.parentNode
            && node.parentNode.classList
            && node.parentNode.classList.contains('verdict-reactions')) {
          bumpReaction(node);
          return;
        }
        node = node.parentNode;
      }
    });
  }
  } // end setupVerdictReactions


  /* ── 6b. Hand-gesture animation ─────────────────────────────────────── */
  // Fires the 🤌 "ma che vuoi" wiggle the first time the title enters the
  // viewport, then re-fires every 60s as long as the hand is still on screen
  // (so it stays a subtle background flourish rather than a constant loop).
  // Re-armed on language change since data-i18n innerHTML rewrite swaps the node.
  var handObserver  = null;
  var handInterval  = null;
  var handVisible   = false;

  function playHandGesture() {
    var hand = document.querySelector('.hand-gesture');
    if (!hand) return;
    hand.classList.remove('play');
    // Double-rAF replaces the previous `void hand.offsetWidth` reflow.
    // The IntersectionObserver fires this on initial visibility, which
    // PSI was attributing as ~39ms of forced reflow during boot.
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { hand.classList.add('play'); });
    });
  }

  function armHandGesture() {
    var hand = document.querySelector('.hand-gesture');
    if (!hand) return;
    hand.classList.remove('play');
    handVisible = false;

    if (handObserver) handObserver.disconnect();
    if (handInterval) { clearInterval(handInterval); handInterval = null; }

    handObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        handVisible = entry.isIntersecting;
        if (handVisible && !handInterval) {
          // First time in view → play immediately, then every 60s.
          playHandGesture();
          handInterval = setInterval(function () {
            if (handVisible) playHandGesture();
          }, 60000);
        }
      });
    }, { threshold: 0.4 });
    handObserver.observe(hand);
  }

  // Re-arm whenever language changes (innerHTML rewrite swaps the node).
  var _origSetLang = window.setLang;
  window.setLang = function (lang) {
    _origSetLang(lang);
    armHandGesture();
  };


  /* ── 7. Boot ────────────────────────────────────────────────────────── */
  // Critical path: keep this section tiny so the hero CTA is interactive
  // on the very first frame. Anything that walks the DOM, sets up
  // observers, or starts an interval gets deferred to either the next
  // frame (rAF) or to idle time.
  //
  // Why this matters: Chrome's INP panel was reporting 500ms+ input
  // delay on the hero-cta during initial load — the user's tap landed
  // while the main thread was still busy with style/layout/paint work
  // for the rest of the page. Even an empty `<a>` click gets queued
  // behind that work. Deferring our JS work until after first paint
  // moves us out of the user's tap window.

  // Defer the auto-cycling timers + tutorial observer setup until after
  // the page has fully settled. setupTutorialObservers() in particular
  // installs an IntersectionObserver per step which, on Safari, can
  // briefly jank the first paint if it runs synchronously.
  function initBackgroundWork() {
    tutSteps.forEach(function (s) { s.classList.remove('active'); });
    setupTutorialObservers();
    setupPackTileInteractions();
    setupVerdictReactions();
    startCarousel();
    startVoteCycle();
    // Hand-gesture observer normally re-arms inside the wrapped
    // setLang. For IT visitors we skip the boot setLang call entirely
    // (see below), so arm it directly here so the 🤌 wiggle still
    // fires when the title scrolls in.
    armHandGesture();
  }

  // i18n boot: only call setLang when the stored/preferred language
  // differs from the HTML seed (Italian). For IT users — the default
  // and the overwhelming majority — the HTML is already correct, the
  // IT lang button is already marked .active, document.lang is already
  // "it", and applyRound's first round matches the hardcoded HTML in
  // the phone mockup. So setLang is a pure no-op and worse, calling it
  // would lazy-fetch landing.translations.js (~7KB transfer + 22KB JS
  // parse) for no reason. Skipping it is the entire point of the
  // lazy-load refactor: PSI flagged the translations file as 66%
  // unused on the boot path, and for IT visitors it's now 100% unused.
  //
  // For non-IT users (browser language English, or someone who
  // previously toggled to EN and it's stored in localStorage), schedule
  // setLang on the next frame so it lands after first paint. The page
  // will paint Italian first, then swap to the user's language a frame
  // later — a tiny visible flicker that's the price of skipping the
  // sync translation load on the IT critical path.
  if (currentLang !== 'it') {
    requestAnimationFrame(function () { window.setLang(currentLang); });
  }

  // Heavier work: wait for idle (or fall back to a small timeout on
  // Safari, which doesn't ship requestIdleCallback). The 250ms timeout
  // cap means even on a CPU-pegged device the tutorial mockups are
  // wired up before the user can realistically scroll into them.
  if (typeof window.requestIdleCallback === 'function') {
    window.requestIdleCallback(initBackgroundWork, { timeout: 250 });
  } else {
    setTimeout(initBackgroundWork, 50);
  }
})();
