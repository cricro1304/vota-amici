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

  /* ── 2. Phone carousel (hero demo) ──────────────────────────────────── */
  // Page language is determined entirely by which HTML file the user
  // requested — IT lives at /landing-page.html, EN lives at
  // /en/landing-page.html, and each is fully translated at build time
  // by scripts/build-i18n.js. There's no client-side i18n machinery
  // anymore; we just read <html lang> to pick the right phone-mockup
  // round set and result-line phrasing below.
  var currentLang = (document.documentElement.lang || 'it').slice(0, 2).toLowerCase();
  if (currentLang !== 'it' && currentLang !== 'en') currentLang = 'it';
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
  // (Removed.) Per-language pages are generated at build time by
  // scripts/build-i18n.js — the IT site lives at /landing-page.html, the
  // EN site at /en/landing-page.html. The lang toggle in the nav is now
  // a real <a href> link to the alternate-language page, so there's no
  // window.setLang to expose, no translations dictionary to load, no
  // post-paint text rewrite. The question-carousel chips are baked into
  // each language's HTML at build time, so makeChips / buildCarousel /
  // restartTrackAnimation are all gone too.


  /* ── 4. Pack tile interactions ──────────────────────────────────────── */
  // Event-delegated click handling on the document, attached
  // immediately at IIFE-execute. This replaces the previous
  // setupPackTileInteractions() that was deferred to requestIdleCallback
  // and attached 14 separate listeners (7 click + 7 mouseenter on each
  // tile). Two problems with the old version:
  //   1. The idle deferral meant on slow phones the listener could be
  //      missing for 250ms+ after first paint — taps in that window
  //      did nothing, then suddenly the sheet appeared (felt "super
  //      slow" to the user).
  //   2. openPackSheet did a double-rAF dance to trigger the transform
  //      transition, adding ~32ms of latency on top of the CSS animation.
  // Delegation fixes (1): one listener at boot covers all tiles, no
  // per-tile attachment needed. Removing display:none from the bottom
  // sheet's CSS (see landing.css) fixes (2): the sheet is always in
  // the DOM positioned offscreen via translateY(100%); adding .open
  // immediately triggers the slide-up transition with no rAF wait.
  var isMobileView = function () { return window.innerWidth <= 600; };

  // Cache sheet elements lazily on first use — these IDs are stable
  // and the DOM nodes exist by the time landing.js (defer) runs.
  var _sheet = null, _sheetBackdrop = null, _sheetTitle = null,
      _sheetDesc = null, _sheetExamples = null;
  function getSheetEls() {
    if (_sheet) return;
    _sheet         = document.getElementById('packSheet');
    _sheetBackdrop = document.getElementById('packBackdrop');
    _sheetTitle    = document.getElementById('packSheetTitle');
    _sheetDesc     = document.getElementById('packSheetDesc');
    _sheetExamples = document.getElementById('packSheetExamples');
    if (_sheetBackdrop) _sheetBackdrop.addEventListener('click', closePackSheet);
  }

  function openPackSheet(tile) {
    getSheetEls();
    if (!_sheet) return;
    var popup = tile.querySelector('.pack-tile-popup');
    if (!popup) return;

    var title = tile.querySelector('h4');
    var emoji = tile.querySelector('.pack-tile-emoji');
    _sheetTitle.textContent = (emoji ? emoji.textContent + ' ' : '') +
                              (title ? title.textContent : '');

    var descEl = popup.querySelector('.pack-tile-desc');
    _sheetDesc.textContent = descEl ? descEl.textContent : '';

    _sheetExamples.innerHTML = '';
    popup.querySelectorAll('.pack-tile-chip').forEach(function (c) {
      var span = document.createElement('span');
      span.className = c.className;
      span.textContent = c.textContent;
      _sheetExamples.appendChild(span);
    });

    // Sheet lives in the DOM at translateY(100%) by default (see
    // landing.css). Adding .open triggers the slide-up transition
    // immediately — no double-rAF needed because the element was
    // already a visible (just offscreen) compositor target.
    _sheetBackdrop.classList.add('open');
    _sheet.classList.add('open');
  }

  function closePackSheet() {
    if (!_sheet) return;
    _sheet.classList.remove('open');
    _sheetBackdrop.classList.remove('open');
    // No setTimeout to set display:none — the sheet stays in the DOM
    // at translateY(100%), invisible and pointer-events:none, ready
    // for the next open. Cheaper than display thrash.
  }

  // Clamp popup position so it doesn't overflow viewport (desktop only).
  function clampPopup(tile) {
    if (isMobileView()) return;
    var popup = tile.querySelector('.pack-tile-popup');
    if (!popup) return;

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

  // Single delegated click listener for both pack tiles AND the
  // "click outside to close" behavior. Attached immediately at boot,
  // so the very first user tap is handled instantly.
  document.addEventListener('click', function (e) {
    var tile = e.target.closest('.pack-tile');
    if (tile) {
      if (isMobileView()) {
        e.stopPropagation();
        openPackSheet(tile);
        return;
      }
      // Desktop: toggle 'touched' for click-to-open popup.
      var wasOpen = tile.classList.contains('touched');
      // Close any other open tile first.
      var open = document.querySelector('.pack-tile.touched');
      if (open && open !== tile) open.classList.remove('touched');
      if (!wasOpen) {
        tile.classList.add('touched');
        clampPopup(tile);
      } else {
        tile.classList.remove('touched');
      }
    } else {
      // Click outside any tile closes the open popup.
      var openTile = document.querySelector('.pack-tile.touched');
      if (openTile) openTile.classList.remove('touched');
    }
  });

  // Desktop hover popups still want the clamp call so they don't
  // overflow the viewport. mouseenter only fires on devices with a
  // hover capability, so this is a no-op on touch-only mobile.
  document.addEventListener('mouseenter', function (e) {
    var tile = e.target && e.target.closest && e.target.closest('.pack-tile');
    if (tile) clampPopup(tile);
  }, true);


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
    setupVerdictReactions();
    startCarousel();
    startVoteCycle();
    armHandGesture();
    // Pack tile interactions used to be set up here too, but are now
    // attached at IIFE-execute time via document-level event delegation
    // (see Section 4 above). That makes the very first tap on a pack
    // tile responsive even on slow phones where the idle callback
    // hadn't fired yet.
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
