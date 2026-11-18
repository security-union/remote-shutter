---
title: "Return of the Five Stars"
date: "2026-11-18"
author: "Dario Lencina"
description: "How to measure rating velocity with a public Apple API, use written reviews as a bug tracker, and find the bugs hiding in a review prompt, with Remote Shutter's numbers as proof."
---

![Return of the Five Stars: a parody poster of the author fighting a software bug with a lightsaber while a giant bug looms](/blog/listening-to-customers/return-of-the-five-stars.jpg)

*Nobody's going to rate you five stars for trying.*

**BLUF:** Remote Shutter sat at 3.51★ in the US for 13 years, on 65 ratings. Since July the new US ratings average 4.99★, so basically all fives, and they arrive about five times faster than before. Worldwide, across 37 storefronts, the latest ratings average 4.53★. Let me show you how I measured that, what I changed, and the bugs I found in my own review prompt, so you can check your app for the same ones.

## The lifetime rating says nothing about this week

The example I give people is basic kinematics. The lifetime average on an App Store page is position. It's everything accumulated since launch, so it barely moves, and a good or a bad month disappears inside it.

The average of the new ratings is velocity, and that's the number to steer by. Position moves toward velocity, slowly. My US position went from 3.51★ to 3.69★ in four months, while the 9 ratings that moved it averaged 4.99★.[^1]

Apple doesn't show velocity anywhere, but there's a public endpoint that gives you enough to compute it, with no login.

`GET itunes.apple.com/lookup?id=<app>&country=<cc>`

It returns the lifetime `userRatingCount` and `averageUserRating` for one storefront. Save that per country on a schedule. Count times average is the total number of stars, so subtracting two snapshots gives how many ratings arrived in between and what they averaged. There's no auth, so it works on any app, competitors included.

[[chart:periods]]

The first column is my 13 years of history, 184 ratings at 3.28★ worldwide. Every column after it is what arrived between two snapshots, and hovering a column shows the split. The four windows averaged 4.40, 3.68, 3.17 and 4.53.

Yes, one window is below the lifetime average. It holds 6 ratings, so I don't read much into a single column. The averages come back rounded to two decimals, and that's why I merge windows until each one has at least 6 ratings. Taken together, the ratings since July 11 average 4.06★, and the lifetime number went from 3.28★ to 3.41★.

## People who write reviews are a harsher crowd

Star-only ratings and written reviews come from different people, so split them before reading either one. Before July 2026, people who only tapped stars gave Remote Shutter 3.69★ on 106 ratings. People who wrote something gave it 2.73★ on 78. That's the same app in the same years, almost a full star apart.

[[chart:written-yearly]]

Most years have under 10 written reviews, so one year's average is mostly noise. Over longer stretches it does move. Written reviews averaged about 2.3★ from 2013 to 2019 and about 3.0★ from 2020 to 2026.

[[chart:written-share]]

So I use the two for different jobs. Written reviews tell me what to fix, and the snapshots tell me if the fix is working.

## A Sales key reads every review and posts replies

The App Store Connect API returns every written review an app ever got, with stars, title, body, territory, date and your reply. Follow `links.next` to page through the history. A Sales-role API key is enough to read them and to post replies, so no Admin key has to sit next to a script.

| Call | What it returns | Auth |
|---|---|---|
| `GET itunes.apple.com/lookup?id=<app>&country=<cc>` | lifetime rating count and average for one storefront | none, it's public |
| `GET /v1/apps/<id>/customerReviews?sort=-createdDate&include=response` | every written review plus your reply | Sales-role key |
| `POST /v1/customerReviewResponses` | posts or replaces your reply to a review | same key |
| `GET /v1/salesReports` | sales reports | same key |
| Analytics Reports API | the ongoing analytics reports | Admin once to create the request, then Sales reads it |

Auth is an ES256 JWT with a 20-minute expiry and the audience `appstoreconnect-v1`. If one of your scripts still reads Apple's public customer-reviews RSS feed, check it. That feed died in 2026 and returns empty feeds now.

I keep all 100 reviews since 2013 in SQLite with my reply next to each one, so "which ones are unanswered" is one query. Right now 99 are answered, and the open one is from last week. Then I read the list like a bug tracker.

| What they wrote | What shipped | When |
|---|---|---|
| 🇹🇷 5★ "The countdown clock's sound is audible when the video starts" | `fix timer sound` (#106) | 9 days later |
| 🇮🇹 3★ "it says 2X but actually uses the 5X", and no format choice | lens selection fix + aspect ratio controls (#89 to #91) | 9 days later |
| 🇺🇸 3★ "it would be nice if I could connect more than one camera" | Multicam Director, up to 4 iPhones (#203) | about 6 months later |
| Six reviews asking for zoom or other lenses (🇺🇸🇬🇧🇮🇹, 2021 to 2023) | zoom + lens switching (#13) | 2025 |
| "No tap to focus" (🇬🇧 2022, 🇺🇸 2023) | Tap to focus (#169) | 2026 |
| About ten "can't connect" 1★s, 2020 to 2026 | reconnection rebuilt (#61), then our own QUIC transport, Stormo (#183, #189) | |
| "No setup instructions", three times | tutorial + local network permission screens (#27, #28) | |

Yes, the zoom row is embarrassing. People asked for it from 2021 and it shipped in 2025.

## Replacing a reply notifies the reviewer again

When you replace a developer response, Apple notifies the reviewer again and invites them to update their rating. So a shipped fix is a reason to go back to an old review. When a fix ships I reply again on every review it touches, with the version number that has it.

Some people do come back. In August 2026 a US reviewer updated on their own and wrote "Since my last review on this app, which was less than positive, the newest version fixes every issue I initially had." In November an Italian 5★ said "Every problem solved!"

## A rate button can do nothing when tapped

Check what your "Rate" button calls. If it calls `SKStoreReviewController`, iOS throttles it to about three prompts a year, and the API is allowed to show nothing. That's fine for a prompt nobody requested. On a button it means a tap with no result.

Mine was worse than that. After the tap, the code wrote the UserDefaults key `lastVersionPromptedForReview`, and the button's visibility check read that same key. So the button hid itself whether or not a sheet appeared. The automatic prompt shared those keys too, so it could hide the button before anybody tapped it.

The fix (#164, shipped in 10.0.0 on Aug 13, 2026) made two paths that share no keys. The button opens the write-review deep link, which is never throttled.

`https://apps.apple.com/app/id<id>?action=write-review`

The automatic prompt stays on `SKStoreReviewController`, because guideline 5.6.1 requires the system API for in-app prompts.

## Ask everybody, after the app worked

Before July my rate button lived inside a thank-you block that only purchasers saw, and that's about 4% of users. Paying is not a proxy for happy, and guideline 5.6.3 discourages selecting who gets asked. Everybody else waited for the system prompt, which fired after 10 captures.

Now anyone gets asked after 5 verified captures. Verified means the save to Photos succeeded. A failed save counts nothing, and a shot on a 3-camera rig counts 3. Shutter taps, app launches and purchases don't count at all.

The rest of the rules are small. Ask at most 4 times ever, and once per build. Never ask over the welcome screen. Wait 2 seconds after the shot so the sheet doesn't cover the photo. Keep a row in Settings that is always there.

## A review prompt can die without a crash

Write a test that proves your prompt path gets called, because nothing else tells you when it stops. In September 2026 I deleted the classic remote screen (#236, shipped in 13.1.2 on Sep 25), and that screen had the only call sites of the prompt. There was no crash and no failing test. The counter stopped counting, and new installs were never asked.

The fix (#250) moved the counter to where captures save now, and it shipped in 14.0.1 on Oct 30. That's five weeks of new installs nobody asked, and that's on me.

## Write the machine down

Keep all of this in its own private repo, never in the app repo. Mine has about a dozen small Python scripts, one SQLite database and a `CLAUDE.md` where the machine is written down. It says which key reads what, which endpoints are dead and which rows to net out. My favorite rule in it is "answer questions with SQL before writing any new script".

With that file in place, a run is one sentence. I typed "pull the latest reviews because the trend is changing". Claude pulled the reviews, took a ratings snapshot, found 14 new ratings, regenerated the charts and reported 4.53★. Two things stay with me. I minted the Admin key once, and I decide what ships.

## What I'd do if I were you

1. Snapshot the lookup API for every storefront on a schedule, and subtract.
2. Pull every written review with a Sales key into one table.
3. Answer all of them, and reply again with the version number when the fix ships.
4. Point your rate button at the write-review link, and keep the system prompt for the automatic ask.
5. Count verified results before asking, and test that the counter still gets called.

If you run the snapshots on your own app, what does your velocity look like next to your lifetime number? I would love to see it. Cheers.

[^1]: For the nerds: each column is a finite difference over the snapshot interval, so it's the average velocity over that window, not the instantaneous one. Per-storefront averages come back rounded to two decimals, so a window with only two ratings is mostly rounding. That's why windows merge until they hold six ratings.
