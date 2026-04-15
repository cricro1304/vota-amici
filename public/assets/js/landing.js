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

  var translations = window.LANDING_TRANSLATIONS;


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
  var voteIndex = -1;
  setInterval(function () {
    if (heroCarouselRunning && screens[0].classList.contains('active')) {
      var voteButtons = document.querySelectorAll('.vote-btn');
      voteButtons.forEach(function (b) { b.classList.remove('selected'); });
      voteIndex = (voteIndex + 1) % voteButtons.length;
      voteButtons[voteIndex].classList.add('selected');
      // The winner will be re-selected on the next screen change (see applyRound).
    }
  }, 1200);

  // Carousel timer — only advances when in hero mode.
  var carouselInterval = null;
  function startCarousel() {
    if (carouselInterval) clearInterval(carouselInterval);
    carouselInterval = setInterval(function () {
      if (heroCarouselRunning) nextScreen();
    }, 3000);
  }


  /* ── 3. i18n ────────────────────────────────────────────────────────── */
  function buildCarousel() {
    var t = translations[currentLang];
    var track1 = document.getElementById('qTrack1');
    var track2 = document.getElementById('qTrack2');
    if (!track1 || !track2) return;

    function makeChips(arr) {
      return arr.concat(arr) // duplicate so the marquee can loop seamlessly
        .map(function (q) { return '<span class="question-chip">' + q + '</span>'; })
        .join('');
    }

    track1.innerHTML = makeChips(t.carousel_row1);
    track2.innerHTML = makeChips(t.carousel_row2);
  }

  // Exposed globally so the inline onclick="setLang('it')" handlers work.
  window.setLang = function (lang) {
    currentLang = lang;
    window.I18n.applyTranslations(lang, translations[lang]);
    buildCarousel();
    applyRound();
  };


  /* ── 4. Pack tile interactions ──────────────────────────────────────── */
  var isMobileView = function () { return window.innerWidth <= 600; };

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

  document.querySelectorAll('.pack-tile').forEach(function (tile) {
    tile.addEventListener('click', function (e) {
      if (isMobileView()) {
        e.stopPropagation();
        openPackSheet(tile);
        return;
      }
      // Desktop: toggle 'touched' for click-to-open popup.
      var wasOpen = tile.classList.contains('touched');
      document.querySelectorAll('.pack-tile').forEach(function (t) {
        t.classList.remove('touched');
      });
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
      document.querySelectorAll('.pack-tile').forEach(function (t) {
        t.classList.remove('touched');
      });
    }
  });


  /* ── 5. Scroll-driven tutorial phone coordination ───────────────────── */
  // A single scroll handler decides whether the phone shows the hero
  // auto-cycling carousel or a specific tutorial step screen.

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

  // Uses getBoundingClientRect; trigger line is 65% down the viewport.
  var rafScheduled = false;

  function onScrollUpdate() {
    rafScheduled = false;
    var defaultTrigger = window.innerHeight * 0.65;
    var vh = window.innerHeight;

    // Snapshot step positions. A step may override the default trigger
    // point via `data-tut-start-at` (a fraction of viewport height) — this
    // is how the "🎲 Scegli il pack" step gets to start earlier, since its
    // phone mockup is the user's first impression of the tutorial and it
    // was activating too late / getting skipped past on fast scrolls.
    var stepRects = [];
    tutSteps.forEach(function (step) {
      var rect = step.getBoundingClientRect();
      var startAt = parseFloat(step.getAttribute('data-tut-start-at'));
      var trigger = isNaN(startAt) ? defaultTrigger : vh * startAt;
      stepRects.push({
        top: rect.top,
        bottom: rect.bottom,
        trigger: trigger,
        screen: parseInt(step.getAttribute('data-tut-screen'), 10)
      });
    });

    // Latest step whose top is above its own trigger line wins.
    var activeScreen = 0;
    for (var i = stepRects.length - 1; i >= 0; i--) {
      if (stepRects[i].top <= stepRects[i].trigger) {
        activeScreen = stepRects[i].screen;
        break;
      }
    }

    // Scrolled past the whole tutorial block → reset.
    if (tutBlockEl && tutBlockEl.getBoundingClientRect().bottom < 0) {
      activeScreen = 0;
    }

    if (activeScreen > 0) {
      enterTutorialMode();
      setTutScreen(activeScreen);
    } else {
      enterHeroMode();
    }
  }

  function scheduleScrollUpdate() {
    if (rafScheduled) return;
    rafScheduled = true;
    requestAnimationFrame(onScrollUpdate);
  }


  /* ── 6. Chat bubble scroll-in animations ────────────────────────────── */
  // Each bubble fades/slides in individually as it scrolls into view, so the
  // chat feels like it's being read in real time as the user scrolls down.
  var chatMsgs = document.querySelectorAll('.chat-msg');

  if (chatMsgs.length > 0) {
    chatMsgs.forEach(function (msg) {
      // Reset any previous staggered delay — per-bubble timing is its own arrival.
      msg.style.setProperty('--chat-delay', '0s');
    });

    var chatObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('chat-visible');
        chatObserver.unobserve(entry.target); // play only once per bubble
      });
    }, {
      threshold: 0.35,
      // Trigger slightly before the bubble fully enters so it doesn't pop in
      // at the very edge of the viewport.
      rootMargin: '0px 0px -8% 0px'
    });

    chatMsgs.forEach(function (msg) { chatObserver.observe(msg); });
  }


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
    void hand.offsetWidth; // force reflow so the keyframes restart
    hand.classList.add('play');
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
  // Apply the stored/preferred language on boot so the page renders in the
  // user's last choice rather than the HTML defaults. The wrapped setLang
  // also (re-)arms the hand-gesture observer.
  window.setLang(currentLang);
  startCarousel();

  tutSteps.forEach(function (s) { s.classList.remove('active'); });
  if (tutSteps.length > 0) {
    window.addEventListener('scroll', scheduleScrollUpdate, { passive: true });
    onScrollUpdate();
  }
})();
