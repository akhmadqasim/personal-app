# iOS Design System — "Luma-like"

Date: 2026-09-19 · Status: approved direction · Reference: Luma for iOS (≈90 screens
reviewed on Mobbin, light + dark, list/detail/forms/sheets/empty states).

Target: iOS 26, SwiftUI, Liquid Glass for floating bars. Everything below is a
token or a component rule; screens compose these and add nothing ad hoc.

## 1. Character

Quiet, editorial, image-led. Off-white canvas with pure-white rounded cards;
black as the primary action colour; one contextual accent per screen (Luma
uses the category colour — we use the muscle-group colour); status is shown as
small tinted pills, never as full-colour rows. Chrome floats: a translucent
capsule tab bar, circular glass buttons in the top corners, a pill segmented
control in the header. Detail pages tint their background with a blurred
version of the hero image ("ambient"). Dark mode is near-black with
translucent white surfaces — not grey cards on grey.

## 2. Tokens

### Colour (light / dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | `#F5F5F3` | `#0A0A0A` | screen background |
| `surface` | `#FFFFFF` | white 8% over canvas | cards, grouped rows, sheets |
| `surfaceSecondary` | `#EFEFED` | white 12% | segmented track, secondary buttons, inputs |
| `hairline` | `#E8E8E6` | white 10% | row separators, card borders (optional) |
| `textPrimary` | `#111111` | `#F5F5F5` | titles, row labels |
| `textSecondary` | `#6B6B6B` | `#A3A3A3` | meta lines, descriptions |
| `textTertiary` | `#9C9C9C` | `#6F6F6F` | group headers' weekday, placeholders |
| `ink` | `#0A0A0A` | `#FFFFFF` | primary CTA fill (text is the inverse) |
| `success` / `successSoft` | `#1F9D4B` / `#E4F5EA` | `#3DD068` / green 18% | Completed, PR, toasts |
| `info` / `infoSoft` | `#7C3AED` / `#F1E9FD` | `#A78BFA` / purple 18% | In progress, active program |
| `warning` / `warningSoft` | `#B8860B` / `#FBF1D3` | `#E2B93B` / yellow 18% | Skipped, waitlist-like states |
| `danger` / `dangerSoft` | `#E5484D` / `#FDE7E8` | `#F26B70` / red 18% | destructive actions, error toast |
| `link` | `#2F6FED` | `#5B8DEF` | inline links |

Muscle-group accent (used for the exercise illustration tile background, the
Subscribe-style accent button on a group page, and progress chart lines):
chest `#E0574F`, back `#3B7DD8`, shoulders `#E08A2E`, biceps `#9B59B6`,
triceps `#8E44AD`, forearms `#7F8C8D`, core `#16A085`, quads `#2ECC71`,
hamstrings `#27AE60`, glutes `#D35400`, calves `#1ABC9C`, full_body `#34495E`,
cardio `#E91E63`, other `#95A5A6`. Each has a `Soft` variant at 14% alpha.

### Typography (SF Pro, Dynamic Type on)

| Style | Size/weight | Use |
|---|---|---|
| `largeTitle` | 30 bold, tracking −0.4 | tab-root titles ("Today", "Programs") |
| `title` | 24 bold | detail page title (2 lines max) |
| `section` | 20 semibold | "Hosting ›"-style section headers |
| `headline` | 17 semibold | row titles, sheet titles |
| `body` | 17 regular | row labels, form fields |
| `secondary` | 15 regular | meta lines (icon + text), descriptions |
| `caption` | 13 regular | above-title context ("Push A · Week 3"), helper text |
| `pill` | 12 semibold | status pills, counters |
| `numeric` | 28 semibold, monospaced digits | totals, weight × reps in session |

Group headers in lists follow Luma exactly: `headline` date + ` / ` +
`textTertiary` weekday ("Tomorrow / Wednesday").

### Spacing, radius, elevation

- Grid 4 pt. Screen horizontal inset 16. Card padding 16. Row height ≥ 52.
- Radius: card/group 20, thumbnail 12, input 12, pill ∞, sheet 28, tab bar ∞.
- Elevation: cards have no shadow in light mode (colour contrast does the work);
  floating chrome (tab bar, header pills, circular buttons) uses Liquid Glass
  (`.glassEffect()`), with a 0 0 24 pt 8% black shadow as fallback.
- Hairline separators inset to the row's text leading edge.

### Iconography

SF Symbols, `.regular` weight, 20 pt in meta rows, 22 pt in bars, monochrome
`textSecondary`. Outline style only (no filled variants) except the selected
tab icon.

## 3. Components

**Floating tab bar** — capsule, 3 items (Today · Programs · Progress), icon over
11 pt label; selected item is a filled `ink` circle with inverse icon (light
mode) or a white-glass circle (dark mode). 16 pt above the safe area; content
scrolls beneath it. Built with `TabView` + `.tabBarMinimizeBehavior(.onScrollDown)`
on iOS 26; the appearance comes from the system Liquid Glass tab bar with tint
`ink`.

**Header** — tab roots: `largeTitle` left with a small brand glyph (✦) before
it, avatar/gear on the right. Pushed pages: 40 pt circular glass back button
top-left, up to two circular glass action buttons top-right, optional centred
`headline` title. Modals: grab handle, centred title, `X` circle top-right,
confirm `✓` circle top-right when the modal is a form.

**Pill segmented control** — `surfaceSecondary` capsule track, white (light) /
white-16% (dark) selected segment with `headline` label. Lives in the header
row between the back button and a trailing action ("Upcoming | Past" pattern →
our "Upcoming | History").

**List row (event row)** — 72 pt square thumbnail (radius 12) on the left,
optional status pill overlapping its bottom-left corner; on the right: caption
line with a 16 pt circular avatar/icon, `headline` title (2 lines), then 1–2
`secondary` meta lines each led by a 16 pt symbol (clock, mappin → for us:
`dumbbell`, `clock`, `flame`). Trailing: optional green `pill` value. Rows are
separated by 20 pt vertical space, not hairlines, when they have thumbnails.

**Grouped rows (settings/forms)** — `surface` container radius 20; rows 52 pt
with `body` label left and `textSecondary` value right, chevron or stepper
glyph (`chevron.up.chevron.down`) for pickers, green `Toggle` for switches.
Section label above the group in `caption` `textTertiary`. Helper text below
in `caption`.

**Buttons** — primary: `ink` capsule 52 pt, inverse `headline` label, optional
leading symbol; disabled = `surfaceSecondary` with `textTertiary` label.
Secondary: `surfaceSecondary` capsule 44–52 pt. Accent: capsule filled with
the contextual accent, white label (Luma "Subscribe"). Tertiary: text only.
Circular icon button: 40 pt glass circle. Detail-page action row: one primary
white/black capsule + two `surfaceSecondary` capsules, equal widths, 8 pt gap,
icon above 13 pt label.

**Status pill** — capsule, `pill` text, `xSoft` fill with `x` text: Completed
(success), In progress (info), Skipped (warning), PR (success), Draft
(textTertiary on surfaceSecondary).

**Chips** — 36 pt capsule, `surface` fill with hairline border, `secondary`
label, optional trailing count in `textTertiary` ("Clay 1"). Used for filters
(muscle group, equipment).

**Bottom sheet** — radius 28, `surface`, grab handle; header row = 44 pt
circular `surfaceSecondary` icon (symbol in `textPrimary`) left and `X` circle
right; `section` title; `secondary` body; full-width primary CTA; secondary
action below in `surfaceSecondary`. Destructive confirmations use a red
"Slide to confirm" capsule (48 pt, arrow knob) instead of a tap button.

**Toast** — capsule at the top, 44 pt, `success` fill with white check symbol
and `headline` white text ("Session saved"); `danger` fill with warning
symbol for errors. Auto-dismiss 2.5 s.

**Empty state** — centred 72 pt rounded-square `surfaceSecondary` tile with a
`textTertiary` symbol, `headline` `textSecondary` title, `secondary`
`textTertiary` message, optional primary CTA below.

**Inputs** — `surfaceSecondary` fill, radius 12, 52 pt, `body` text,
`textTertiary` placeholder; numeric fields for weight/reps use `numeric`
style, right-aligned, with `.keyboardType(.decimalPad)`. Steppers for reps
(± circular 32 pt) live inside the set row.

**Ambient detail background** — on session/exercise detail pages the hero
illustration is drawn again behind the content at 40 pt blur, 35% opacity,
desaturated 30%, fading to `canvas` by 45% of the screen height; in dark mode
the blur sits over `canvas` at 25% opacity.

## 4. Screen patterns for the gym app

- **Today (tab root)** — header "✦ Today", gear top-right. Card "Next up":
  thumbnail = first exercise illustration, title = program day name, meta =
  "6 exercises · ~50 min", primary CTA "Start session". Below: "History ›"
  section using date-grouped event rows (status pill Completed / Skipped).
- **Session (detail)** — ambient background; title = day name; caption = date
  + elapsed timer; action row: **Finish** (primary) · **Add exercise** · **More**.
  Then one grouped card per exercise: header row (thumbnail 40, name, muscle
  chip), set rows `#1  60 kg × 8  ✓` using `numeric`, tap to edit inline,
  swipe to delete (soft). "Last time: 57.5 × 8" as `caption` under the header.
- **Programs (tab root)** — list of programs as event rows (status pill
  Active); program detail = grouped cards per day; day editor = grouped rows
  with reorder handles (Luma "Hosts" pattern).
- **Exercises (pushed from Programs / search)** — chips row (muscle groups),
  rows with the illustration tile on the accent `Soft` colour; custom
  exercises show the photo instead; detail page uses the ambient background
  and shows a "Photo" secondary action to upload.
- **Progress (tab root)** — per-exercise chart cards (line = accent, area =
  `Soft`), best-set tile, weekly volume; charts follow the `dataviz` rules.
- **Settings (modal)** — grouped rows: API token (secure field), Sync now,
  Last sync, Export, About.

## 5. Motion

- Push/pop: system. Sheets: system spring. Toasts: slide from top, 250 ms.
- Set completion: checkmark scales 0.8→1 with `.bouncy`; row background
  flashes `successSoft` for 400 ms.
- Tab bar minimises on scroll down (iOS 26 behaviour), restores on scroll up.
- Respect Reduce Motion: replace scale/flash with opacity only.

## 6. Accessibility

Dynamic Type up to accessibility sizes (rows grow, thumbnails cap at 88 pt);
all pills carry a text label; contrast ≥ 4.5:1 for text on `Soft` fills
(verified for the pairs above); VoiceOver labels on icon-only circular buttons;
haptics: `.success` on session finish, `.selection` on set complete.
