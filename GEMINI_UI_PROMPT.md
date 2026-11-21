# Prompt for Gemini — BiLingo UI/UX redesign

Copy everything below the line into Gemini.

---

You are a senior mobile product designer (Material 3, Flutter-friendly). Redesign the UI/UX of my Android app **BiLingo** and give me high-fidelity screen designs plus a design spec I can hand to a Flutter developer.

## 1. About the app
**BiLingo** — tagline *"Learn something new, every unlock."* A learning app that shows the user a new word (English, German, Hindi) as a notification every time they unlock their phone, plus topic practice for exams. Target users: students and exam aspirants in India (Kerala PSC, UPSC, NEET, JEE) and language learners aged 16–35. Tone: friendly, motivating, calm — never childish, never noisy.

**Topics:** English (Vocabulary & grammar), German (Wörter & Sätze), Hindi (शब्द और वाक्य), PSC (Kerala PSC practice), UPSC (Civil services prep), NEET (Medical entrance), JEE (Engineering entrance). Topics are currently all "coming soon" except the word-of-the-unlock feature for en/de/hi.

**Existing data I can show (real):** user first name, selected topics, words learned per language, total words seen, current streak (days), level (1 level per 20 words learned), quiz accuracy %, dark/light theme.
**Data I will add (design for it):** daily activity history (questions answered / correct per day), XP, daily goal, last-studied topic.

## 2. Current look (keep the DNA, raise the quality)
- Brand blue `#2F80FF`, Material 3, soft sky-blue vertical gradient background in light (`#C9E0FF → #E8F1FF → #F8FBFF`) and deep navy in dark (`#16254A → #0B1220`).
- Translucent "glass" rounded cards (22px radius), floating pill bottom nav (Home, Profile), a glowing animated **orb** as the brand mascot/logo.
- Splash: letters rain from the top, the screen vibrates briefly, then orb + "BiLingo" pop in.
- Current Home is weak: big orb, greeting, then a plain list of 7 topic cards. Profile has avatar, level/streak pills, stats row, settings tiles.

## 3. What I want you to design
Design these screens, **light AND dark mode**, 360×800 Android portrait:

1. **Home (main focus)** — suggested structure, improve it if you have better ideas:
   - Compact header: greeting ("Good evening, Anu"), small orb avatar, 🔥 streak chip and Level badge.
   - **Daily goal + Level card:** circular progress ring for today's goal (e.g. 6/10 words), XP bar to next level, current level title (Beginner → Learner → Explorer → Scholar → Master).
   - **Week strip calendar:** Mon–Sun dots (done / missed / today), tapping opens the full month view. Show where the streak flame lives.
   - **Progress chart:** last 7 days bar chart (words/questions per day) with an accuracy line; 7D / 30D toggle. Give an empty state for a brand-new user.
   - **"Continue learning"** hero card for the last topic.
   - **Topics:** redesign the topic list (grid or horizontal carousel + list?), with per-topic progress, a star for the user's chosen topics, and a clear "coming soon" treatment.
2. **Full month calendar / activity heatmap** (bottom sheet or screen) with streak stats (current, longest, total days active).
3. **Level-up and streak animations** — describe as storyboard frames: streak flame pulse + sparkle when today's goal is hit; "Level 3 — Explorer!" celebration overlay; XP bar fill. Keep it consistent with the splash/orb style.
4. **Profile** polish: header, stats, achievements/badges section, settings groups.
5. **Topic detail screen** (what you see after tapping a topic): progress, start practice button, recent words, difficulty levels.
6. **Quiz question screen + result screen** (multiple choice, instant feedback, XP gained, streak impact).
7. **Word detail screen** (opened from the unlock notification): the word, language tag, pronunciation/speaker button, meaning, example sentence, "Next word" and "I know this" actions.
8. **Onboarding** (name → pick topics → enable unlock words permission) — 3 short, delightful steps.
9. **Bottom navigation:** propose whether 2 tabs (Home, Profile) is enough or add Practice / Progress. Justify.

## 4. Design requirements
- Material 3, accessible: contrast ≥ 4.5:1, touch targets ≥ 48dp, text readable at 1.3× font scale, Hindi (Devanagari) and German text must fit.
- One-handed use: primary actions in the lower half of the screen.
- Consistent 8dp spacing grid; list your type scale, radii, elevations and shadows.
- Charts must be simple and glanceable — no clutter, no more than 2 series, direct labels where possible. Colour must never be the only signal.
- Motion: describe duration and easing for every animation (150–400ms for UI, up to 1.2s for celebrations). Respect "reduce motion".
- Gamification should motivate, not shame: missed days are neutral grey, never red; offer a "streak freeze" idea if useful.
- Must be buildable in Flutter with standard widgets + `fl_chart`/`CustomPainter` — avoid effects that need heavy native code.

## 5. Deliverables (in this order)
1. A short **UX rationale** (what was wrong, what you changed and why, top 5 decisions).
2. **Information architecture / navigation map.**
3. **Design tokens:** colours (light + dark, with hex), type scale, spacing, radii, shadows, icon style.
4. **Screen-by-screen design** for every screen above: layout description top to bottom, component states (empty, loading, success, error), and an image/mockup for each.
5. **Component library:** goal ring, streak chip, week strip, chart card, topic card, XP bar, badge, buttons, bottom nav.
6. **Animation specs** (trigger, duration, easing, what moves).
7. **Flutter handoff notes:** suggested widget breakdown per screen.

If anything is ambiguous, state your assumption and continue rather than asking me questions.
