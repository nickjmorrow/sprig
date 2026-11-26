# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Native SwiftUI on iPhone (iOS 18+) and Mac (macOS 15+), from one shared core (`ios/SprigCore`). Each app should feel native to its OS; the Mac app is a three-column reader, not a stretched phone app.

## Users

One person: Nicholas. He saves articles, tweets and threads from the iPhone Share menu and follows RSS feeds, then reads them later on the iPhone (on the go) and the Mac (at the desk), about equally.

## Product Purpose

A personal read-it-later app that replaces Readwise Reader. Everything saved gets topics and a reading time automatically, so the app opens straight onto "what can I read in the time I have, on the topic I'm in the mood for." Success: he opens it, picks a time range and a topic, and reads, with no filing or upkeep.

## Positioning

Built for one reader. Topics come from his own short list (assigned by Claude), reading time is computed for every item, and the filter of time range × topic is the front door, not a buried feature.

## Operating Context

- Three places: Inbox (things he saved), Feed (new RSS posts, triaged into Inbox or Archive), Archive (done, with favorites).
- Saving happens from other apps through the Share extension; the app itself is for choosing and reading.
- Reading happens in a clean article reader (rendered HTML, tweet threads as cards), offline on the phone. PDFs open in the reader as the PDF itself and need the network.
- Server on his home Mac (Edgar), reached over Tailscale; devices sync every minute and work offline.
- Mac: keyboard-driven (j/k, e archive, s star, u unread, o open original, ⌘F search).

## Capabilities and Constraints

- Filters: time range (Any, Under 5, 5–15, 15–30, 30+), topic chips, favorites (Archive), full-text search within a tab.
- Actions: archive, keep (Feed → Inbox), move to Inbox, star, mark unread, open original, edit an item's topics.
- Nothing archives itself: a story read to the end stays where it is, marked Read, until he archives it, with the Archive button at the end of the article or the one in the toolbar. Every archive shows an Undo bar for 8 seconds.
- Statuses an item can show: pending (being fetched), ready, failed (couldn't fetch), web only (paywall or too short; opens the page, and its row says Link only). Feed posts that failed or are web only are left out of the Feed.
- Home-screen widget (Up Next) on iPhone.
- Not built: highlights and notes, newsletters, offline images, Readwise-style review.

## Brand Commitments

- Name: Sprig. Plain, short copy in his voice ("Nothing here. Share a link to Sprig.").
- The current Midnight Sun palette (navy and sunflower yellow) is not binding; a redesign may replace it.
- Visual direction (chosen 2026-11-09): the category standard for read-it-later apps, played straight and at full craft. Native system components, semantic colors, light and dark. Benchmarks for finish: Readwise Reader, Matter, Apple News.

## Evidence on Hand

- Real content: his library on Edgar (`~/sprig-hub/sprig.sqlite`): articles, X threads, feed posts from sites like Martin Fowler, Simon Willison, Quanta, Atlas Obscura.
- App icons in `ios/App/Assets.xcassets` and `ios/Mac/Assets.xcassets`.

## Product Principles

1. Choosing what to read takes seconds: time and topic first, everything else second.
2. Reading is the product; chrome gets out of the way once an article is open.
3. Zero upkeep: nothing asks him to file, tag or tidy unless he wants to.
4. Native on each device: iPhone gestures and Mac keyboard and menus, not one compromise layout.
