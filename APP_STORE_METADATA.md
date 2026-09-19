# App Store Metadata — VerbaDoc v1.0

**App name:** VerbaDoc
**Primary category:** Education
**Secondary category:** Productivity
**Content rating:** 4+ (no objectionable content; AI-generated text filtering offloaded to model provider)

> Note: numbers shown are the **max character length App Store Connect accepts**. Stay under each.
> Apple App Store enforces no truncation on the *display* side; always re-test render before submit.

---

## A. Localizable fields

### App name (max 30)
**VerbaDoc — AI Study Coach**

### Subtitle (max 30)
**Turn notes into flashcards in 30 seconds.**

### Promotional text (max 170 — editable anytime without release)
> Built for the student who needs to study smarter, not longer. VerbaDoc reads your notes,
> textbook pages, or photo of a worksheet and turns them into flashcards, quizzes, open-answer
> questions, and study guides — drafted like an AP teacher, not a fill-in-the-blank bot.
> **What's new in 1.0:** Open-answer grading with rubric explanations, streak-based
> reminders, and the new CapyCoach mascot to keep your streak alive.

### Description (max 4000)

VerbaDoc is the AI study tool for students who want to learn — not just memorize.

**PASTE YOUR NOTES. GET FLASHCARDS, QUIZZES, AND STUDY GUIDES.**

Upload a PDF, snap a photo of a worksheet, paste a chapter, or share a YouTube lecture link.
In under a minute, VerbaDoc returns:

• **Flashcards** that ask the *why*, not the missing word
• **Multiple-choice quizzes** with plausible distractors and explanations
• **Open-answer questions graded by a teacher-rubric AI**
• **Study guides** organized by topic, timeline, and cause-and-effect
• **Spaced repetition** that shows each card the moment you're about to forget it

**BUILT FOR REAL EXAM PREP.**

Whether you're two weeks out from AP US History, prepping for an SAT, or trying to survive
a college genetics midterm, VerbaDoc focuses on the concepts you'd actually be tested on.
The AI is explicitly prompted to never copy your source material and to never produce
cloze-deletion cards — every prompt is rewritten to teach *understanding*, not memorization.

**TRACK YOUR MASTERY.**

Each card, quiz, and open-answer response updates your mastery profile. Watch your weak
topics graduate into strong ones. Build a study streak. Get a gentle reminder when cards
are about to slip.

**WHAT YOU OWN.**

Your decks live in your account, sync between devices, and stay exportable. We do not
train third-party AI models on your notes. Delete your account at any time, and your data
is purged within seven days.

**FREE, THEN PRO.**

VerbaDoc is free for personal use, with an upgrade to **VerbaDoc Pro** that unlocks
unlimited AI generations, multi-device sync, and PDF + photo import. Subscriptions are
billed by Apple through the App Store.

**Designed by a high schooler.** If you've ever thought "the AI tutor should actually
*teach*, not just spout facts" — VerbaDoc is for you.

---

### Keywords (max 100 chars — comma-separated, no spaces after commas)
```
flashcards,quiz,study,AI,exams,SAT,AP,biology,history,chemistry,notes,photos,PDF,review,testprep,spacedrepetition,homework
```

### Support URL
`https://verbadoc.app/support`

### Marketing URL
`https://verbadoc.app`

### Privacy Policy URL
`https://verbadoc.app/legal/privacy`

### Terms of Service URL
`https://verbadoc.app/legal/terms`

---

## B. Privacy nutrition labels

App Store Connect prompts the following. Each row is the truthful answer for
VerbaDoc v1.0 and the rationale behind it.

### Data used to track you
**No.** VerbaDoc does not track users across third-party apps or websites.

### Data linked to you
| Data | Collected | Used for | Purposes (App Store enum) |
|---|---|---|---|
| Contact Info — Email | Yes | Account creation, support | Account Functionality, Customer Support |
| User Content — Photos | Yes (when you import a worksheet photo) | AI generation | App Functionality |
| User Content — Other User Content | Yes (uploaded documents) | AI generation | App Functionality |
| Usage Data — Product Interaction | Yes (anonymous event log) | Product analytics, retention | Analytics, Product Personalization |
| Diagnostics — Crash Data | Yes | Bug fixing | App Functionality |
| Diagnostics — Performance Data | Yes | Performance tuning | App Functionality |

### Data NOT linked to you
**None.** Everything collected is linked to the user account (or, in the analytics case,
to a SHA-256 hash of the user identifier that cannot be reversed).

### Data NOT collected (clarification)
| Data | Not collected? |
|---|---|
| Purchases | NO — collected via App Store receipt + RevenueCat |
| Financial Info — Payment Info | App Store handles; we never see cards |
| Health & Fitness | NO |
| Sensitive Info | NO |
| Location | NO |
| Contacts | NO |
| Browsing History | NO |
| Search History | NO |
| Identifiers — Device ID | NO |
| Identifiers — User ID | **Only inside the hashed analytics log; never stored in cleartext** |

---

## C. Screenshot plan

App Store accepts up to **10 screenshots per device size** (iPhone 6.7" required; iPhone 6.5", 5.5", 12.9" iPad optional). We will ship **5** strong screenshots.

### Required display sizes
- **6.7" iPhone (15 Pro Max, 14 Pro Max)** — 1290 × 2796 px
- **6.5" iPhone (11 Pro Max, XS Max)** — 1242 × 2688 px (optional)
- **5.5" iPhone (8 Plus)** — 1242 × 2208 px (optional)

### Screenshot 1 — *turn notes into AI study tools*
Hero copy: **"paste your notes. get study tools in 30 seconds."**
Visual: UploadTabView with a 1-page paragraph of AP Gov notes pasted in, generation in progress, "8 flashcards + quiz ready" badge.

### Screenshot 2 — *generate flashcards instantly*
Hero copy: **"not fill-in-the-blank. real questions."**
Visual: FlashcardStudyView front of card "Why does federalism distribute power between state and federal governments?" — back reveals rubric-graded answer.

### Screenshot 3 — *study smarter with adaptive learning*
Hero copy: **"spaced repetition shows you the moment you're about to forget."**
Visual: FlashcardStudyView with SRS queue indicator + due-card count badge.

### Screenshot 4 — *track mastery and streaks*
Hero copy: **"weak topics graduate. streaks grow."**
Visual: SettingsView "Weekly Activity" canvas chart + rank-card with XP+streak; mastery bars per topic.

### Screenshot 5 — *AI tutor explains difficult concepts*
Hero copy: **"the AI reads your mistake and explains the why."**
Visual: OpenAnswerView with a 4-sentence student response + the AI tutor's per-key-point credit + 1-line explanation of what's missing.

### Optional: Screenshot 6 — *CapyCoach on a losing streak*
Hero copy: **"missed a day? Capy will nudge you back."**
Visual: NotificationManager-rendered "your streak is at risk" push mockup overlaid on a Home screen with the streak-count tile.

---

## D. App icon

**Single 1024 × 1024 PNG**, no transparency, RGB (not display-P3).

**Brief:** Rounded-square with a chunky-3D pastry-green background (Verba matcha). Centered
yellow notebook character (Capydoc, the Capy mascot) — simple silhouette with two button
eyes, drawn in chunky rounded line art. Below the character, a cream-colored "VD" wordmark
in bunker sans-serif.

**Reference sketch (not final):** the existing `AppIcon-1024.png` in
`VerbaDoc/Assets.xcassets/AppIcon.appiconset/` is approved as the v1.0 master.

### iOS auto-applied corner radius
iOS rounds icons to ~22.4% radius (squircle). Design must accommodate this; do not place
critical visual elements in the corners.

---

## E. Age rating questionnaire (App Store Connect)

| Question | Answer |
|---|---|
| Animated or cartoon violence | None |
| Realistic violence | None |
| Sexual or erotica content | None |
| Profanity or crude humour | None |
| Alcohol, tobacco, drug use | None |
| Simulated gambling | None |
| Horror / fear themes | None |
| Mature / suggestive themes | None |
| Medical / treatment info | None |
| User-generated content | **Yes (uploaded decks) — moderation = AI provider filter** |
| Unrestricted web access | **Yes (SafariViewController) — required for support + legal URLs** |
| Gambling & contests | None |

**Resulting rating: 9+.** Consistent with the "4+" recommendation above.

---

## F. App Review submission checklist

- [ ] All Critical bugs signed off in `QA_CHECKLIST.md`
- [ ] Privacy nutrition labels reviewed by privacy consultant (sign-off in commit history)
- [ ] All 5 screenshots uploaded to App Store Connect (per device size)
- [ ] App icon uploaded, all required derivative sizes pre-rendered
- [ ] Promotional text reviewed for compliance
- [ ] Pricing + free tier verified in RevenueCat
- [ ] Privacy policy + Terms of Service both reachable at the URLs above
- [ ] Export compliance: VerbaDoc uses standard HTTPS — no custom cryptography exemption
- [ ] IDFA: not used (NOT advertising service)
- [ ] Sign-in required? Yes (Apple Sign-In supported, fallback email/password)
- [ ] UGC moderation plan documented inline in description
