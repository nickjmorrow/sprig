---
name: Sprig
description: A personal read-it-later app for iPhone and Mac, played as the native category standard with one sage-teal tint taken from the app icon.
colors:
  leaf: "#1f6f62"
  leaf-dark: "#6aa89a"
  on-leaf: "#ffffff"
  on-leaf-dark: "#0f2321"
  leaf-line: "rgba(31, 111, 98, 0.35)"
  leaf-line-dark: "rgba(106, 168, 154, 0.4)"
  leaf-select: "rgba(31, 111, 98, 0.2)"
  leaf-select-dark: "rgba(106, 168, 154, 0.28)"
  paper: "#ffffff"
  paper-dark: "#000000"
  well: "#f2f2f7"
  well-dark: "#1c1c1e"
  ink: "#111113"
  ink-dark: "#f5f5f7"
  body-ink: "#26262b"
  body-ink-dark: "#dcdce0"
  dim: "#6c6c72"
  dim-dark: "#98989f"
  hairline: "rgba(60, 60, 67, 0.18)"
  hairline-dark: "rgba(84, 84, 88, 0.6)"
typography:
  list-title:
    fontFamily: "SF Pro (system), Dynamic Type .largeTitle"
    fontSize: "34px"
    fontWeight: 700
  row-headline:
    fontFamily: "SF Pro (system), Dynamic Type .headline"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.29
  row-meta:
    fontFamily: "SF Pro (system), Dynamic Type .subheadline"
    fontSize: "15px"
    fontWeight: 400
  row-site:
    fontFamily: "SF Pro (system), Dynamic Type .footnote"
    fontSize: "13px"
    fontWeight: 500
  chip-label:
    fontFamily: "SF Pro (system), Dynamic Type .subheadline"
    fontSize: "15px"
    fontWeight: 400
  article-title:
    fontFamily: "ui-serif, New York, Georgia, serif"
    fontSize: "calc(17px * 1.6)"
    fontWeight: 700
    lineHeight: 1.16
    letterSpacing: "-0.015em"
  article-body:
    fontFamily: "ui-serif, New York, Georgia, serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.62
    fontFeature: "\"onum\", \"pnum\""
  article-byline:
    fontFamily: "-apple-system, system-ui, sans-serif"
    fontSize: "0.76em"
    fontWeight: 600
    lineHeight: 1.4
  article-mono:
    fontFamily: "ui-monospace, Menlo, monospace"
    fontSize: "0.84em"
    lineHeight: 1.5
rounded:
  code: "5px"
  tile: "5px"
  field: "8px"
  media: "10px"
  card: "16px"
  capsule: "9999px"
spacing:
  hair: "5px"
  chip-gap: "8px"
  stack: "10px"
  gutter: "16px"
  reader-x: "22px"
  reader-tail: "56px"
components:
  topic-chip:
    backgroundColor: "{colors.well}"
    textColor: "{colors.ink}"
    typography: "{typography.chip-label}"
    rounded: "{rounded.capsule}"
    padding: "6px 12px"
    height: "32px"
  topic-chip-selected:
    backgroundColor: "{colors.leaf}"
    textColor: "{colors.on-leaf}"
    rounded: "{rounded.capsule}"
    padding: "6px 12px"
    height: "32px"
  source-tile:
    textColor: "{colors.paper}"
    rounded: "{rounded.tile}"
    size: "18px"
  story-row:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.row-headline}"
    padding: "8px 16px"
  mac-search-field:
    backgroundColor: "{colors.well}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "7px 10px"
  reader-column:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.body-ink}"
    typography: "{typography.article-body}"
    padding: "18px 22px 56px"
    width: "68ch"
  tweet-card:
    backgroundColor: "{colors.well}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "14px 16px"
  progress-line:
    backgroundColor: "{colors.leaf}"
    height: "2px"
---

# Design System: Sprig

## Overview

**Creative North Star: "The Quiet Shelf"**

Sprig is the read-it-later category standard (Readwise Reader, Matter, Apple News) played straight. Every surface is built from the platform's own parts: plain and inset `List`s, the system segmented control, `.searchable`, system toolbars and tab bar, `NavigationSplitView` on Mac, `ContentUnavailableView` for empty states and SF Symbols for every icon. Color comes from system semantic colors, so light, dark and Increase Contrast work without custom handling. The one owned hue is the icon's sage-teal.

Choosing and reading are two separate voices. The lists are dense, scannable SF Pro: a small colored source tile, the site, a headline of up to two lines, then reading time and topic. The reader drops the chrome and opens a calm New York serif column at about 68 characters, with a 2px tint progress line at the top and the actions in a bottom bar (iPhone) or the window toolbar (Mac).

**Key Characteristics:**
- System components and semantic colors throughout, light and dark.
- One sage-teal tint (the icon's sage, and a deep teal for light mode) for interactive state, reading time, progress and links.
- SF Pro with Dynamic Type for UI; New York serif for article text.
- Flat surfaces; depth comes only from system bars and materials.
- Per-site letter tiles give each source a stable color.

## Colors

System neutrals plus one sage-teal. Native views use the SwiftUI/AppKit semantic colors (`Theme.swift`); the hex values here are the reader stylesheet's mirror of them (`reader.css`) and the canonical values for the tint.

### Primary
- **Leaf** (light `leaf`, dark `leaf-dark`): the app tint (`.tint(Theme.accent)` at each app root), the selected topic chip, reading time ("12 min", "4 min left") in rows, the reader progress line, article links, the "Keep" swipe action, the minutes in the reader meta line. The light value holds 4.5:1 on white; the dark value is lifted for black.
- **On Leaf** (`on-leaf` / `on-leaf-dark`): text on a Leaf fill (the selected chip).
- **Leaf Line / Leaf Select**: link underline and text selection in the reader; search-match highlight in rows uses Leaf at 20% opacity.

### Neutral
- **Paper** (`paper` / `paper-dark`): `systemBackground` (iPhone), `textBackgroundColor` (Mac); list and reader background.
- **Well** (`well` / `well-dark`): `secondarySystemBackground`; tweet cards and code blocks in the reader. Unselected chips and the Mac search field use the system fill (`tertiarySystemFill` / `quaternaryLabelColor`), which renders in the same family.
- **Ink** (`ink` / `ink-dark`): `Color.primary`; headlines and titles.
- **Body Ink** (`body-ink` / `body-ink-dark`): article paragraphs, a step softer than Ink.
- **Dim** (`dim` / `dim-dark`): `Color.secondary`; site names, row meta, finished-story headlines, blockquotes, captions.
- **Hairline** (`hairline` / `hairline-dark`): `separator`; table rules, `hr`, blockquote rule, quoted-tweet border. List separators are the system's own.

### Other system colors in use
- Star gold for stars (row star, star swipe, starred toolbar button): `Theme.star`, #B07A00 light / #FFD60A dark, so the outline clears 3:1 on white. System indigo (archive) and blue (move to Inbox) for swipe actions. System red for the Mac sync error.
- Source tiles: a hue hashed from the site name at saturation 0.6, brightness 0.55 (dark enough for the white letter); X accounts get a plain "X" on a tile in the label color with the background color for the letter, so it shows in light and dark. These are identity colors, confined to the tile, which scales with Dynamic Type from 18pt.

### Named Rules
**The One Leaf Rule.** The icon's sage-teal is the only owned hue. It marks what is interactive or selected and how long a story takes. Everything else is a system neutral or a system color with a fixed meaning (gold star, indigo archive).

**The Semantic First Rule.** Native views take system semantic colors, never hard-coded hex; only the tint is defined in code, as a light/dark pair.

## Typography

**UI Font:** SF Pro via Dynamic Type text styles (largeTitle, headline, subheadline, footnote)
**Reading Font:** New York (`ui-serif`, falling back to Georgia)
**Mono Font:** `ui-monospace` (Menlo)

**Character:** SF Pro is for choosing, New York for reading. The serif appears in native UI only for a story's title on the link-only page (`.title`, serif, bold).

### Hierarchy
- **List title** (`.largeTitle`, bold): Inbox / Feed / Archive on iPhone, collapsing to inline on scroll. Mac uses the window title.
- **Row headline** (`.headline`, up to 3 lines): story title; turns Dim once a story is 98% read.
- **Row meta** (`.subheadline`): reading time · topic; the time comes first so it never truncates, semibold Leaf with monospaced digits (primary text on a selected Mac row).
- **Row site** (`.footnote`, medium, Dim): the source name beside its tile.
- **Article title** (serif bold, 1.6× the body size, 1.16 line height, -0.015em, balanced wrap).
- **Article body** (serif 17 / 19 / 21px by the text-size control, 1.62 line height, oldstyle proportional numerals, hanging punctuation, `text-wrap: pretty`). Headings h2 1.3em, h3 1.12em, h4 1em, line height 1.25.
- **Article byline** (system sans 600, 0.76em, Dim): site · topic · minutes directly below the title, the minutes in Leaf. Nothing sits above the title. Tables and captions also switch to the system sans.

### Named Rules
**The Two Voices Rule.** Interface text is SF Pro at a Dynamic Type style; article text is New York. Don't put the serif in lists or controls, or sans in article paragraphs.

**The Text Styles Rule.** UI sizes come from text styles, not point sizes, so Dynamic Type scales them. The Mac search field (13pt) is the only fixed size. The article's 17/19/21 steps are scaled by the system text size (`UIFontMetrics` body) on iPhone.

## Layout

- **iPhone:** a tab bar (Inbox, Feed, Archive), each a `NavigationStack` with a plain `List`. The filter bar is the list's section header: the segmented time control (Any, Under 5, 5–15, 15–30, 30+), then a horizontally scrolling chip row, both on a 16px gutter with 10px between them. Rows have 8px vertical padding and a 5px internal stack. Settings is a gear in the Inbox toolbar.
- **Mac:** a three-column `NavigationSplitView`: sidebar (170–260, ideal 190) with unread counts and a sync line at its foot; story list (300–520, ideal 360, inset style) with the search field and filter bar pinned above it on the `.bar` material; reader as the detail column.
- **Reader:** inline nav bar, tab bar hidden, body max 68ch centered with 18px / 22px / 56px padding (Mac adds 36px at the top). Link-only pages use a 24px (iPhone) or 32px, 640pt-max (Mac) leading-aligned column.
- **Empty states:** `ContentUnavailableView` with a location symbol (tray, radio waves, archive box) or filter/search symbol, and short plain copy.

## Elevation & Depth

Flat. Sprig defines no shadows. Depth comes from the system: the tab bar, toolbars and the Mac filter header's `.bar` material, and tonal fills (Well, system fills) for chips, fields, cards and code. The reader's only overlay is the 2px progress line.

**The Borrowed Depth Rule.** Layering comes from system bars and materials; Sprig adds no custom shadows or hand-built glass.

## Shapes

Continuous corners throughout. Capsules for topic chips; small rounded squares (27% of side, about 5px at 18px) for source tiles; 8px for the Mac search field; 10px for article images and code blocks; 5px for inline code; 16px for tweet cards. Lines are 1px hairlines; the blockquote is marked by a 1px Hairline rule and italic Dim text.

## Components

### Topic Chips
- **Style:** capsule, subheadline, 12×6px padding, min height 32, 8px apart, system fill with Ink text.
- **Selected:** Leaf fill, On Leaf text, semibold, with the selected accessibility trait. "All topics" leads; Archive adds a "Favorites" chip with a star symbol first.
- **Shared:** the topics sheet reuses the same chip.

### Time Control
The system segmented `Picker`, labels hidden, selection haptic. Never restyled.

### Story Row
Source tile (18pt, scaled) + site, optional gold star at trailing edge; headline; optional search excerpt with matches in semibold Ink on Leaf at 20%; meta line. Statuses replace the time: mini spinner + "Fetching", triangle + "Couldn't fetch", checkmark + "Read". iPhone rows have no disclosure chevron and carry leading/trailing swipe actions; Mac rows use list selection and a context menu.

### Search
iPhone: system `.searchable` under the large title. Mac: a plain text field in an 8px rounded system-fill well with a magnifying glass and clear button, above the filter bar; ⌘F focuses it, Escape clears.

### Reader Chrome
- **iPhone bottom bar:** Text Size menu with Smaller / Larger (or Open in X for tweets), Star (gold when on, light haptic), Archive, More menu (Mark as Unread, Open Original, Share, Edit Topics, Try Again).
- **Mac controls:** the window has no title bar or toolbar. A material pill at the article's top right holds Text Size (a menu: Smaller / Bigger), Star, Archive and More (Open Original, Copy Link, Share, Mark as Unread, Edit Topics, Try Again).
- **Progress line:** 2px Leaf across the top, animating linearly over 0.2s.
- **Link-only page:** site, serif title, Dim message, a large `.borderedProminent` "Read on the Web" (or "Open in X").

### Tweet Cards
In the reader, saved tweets render as Well cards (16px radius, 14×16px padding) in system sans one pixel below the body size; quoted tweets are transparent with a Hairline border.

### Inheriting surfaces
Settings, the topics sheet, feed and topic editors and the Share extension use the same `Theme` tokens and system components; they were re-colored, not redesigned. The Up Next widget is outside this system: it uses its own engraved-plate home-screen theme in the app icon's colors (teal tile, sage frame, brass rules, a vermilion progress pip, bone serif text).

## Do's and Don'ts

### Do:
- **Do** build with system components first (List, segmented Picker, searchable, toolbars, ContentUnavailableView, SF Symbols).
- **Do** use Leaf for selection, interaction, reading time, progress and links, and nothing decorative.
- **Do** keep article text in New York at 1.62 line height inside a 68ch column, sized 17 / 19 / 21px.
- **Do** show a story's reading time on every row, as minutes left once started.
- **Do** keep each site's tile color stable by hashing its name.

### Don't:
- **Don't** hard-code neutral hex in Swift; use the semantic colors in `Theme`.
- **Don't** add custom shadows, hand-built glass bars or web-shaped controls.
- **Don't** introduce a second owned brand hue; system colors keep their fixed meanings.
- **Don't** set fixed point sizes for UI text where a Dynamic Type style fits.
