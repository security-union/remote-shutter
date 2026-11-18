---
title: "Return of the Five Stars"
date: "2026-11-18"
author: "Dario Lencina"
description: "How Remote Shutter's new US ratings went to 4.99 stars: measuring rating velocity, answering every review, and asking only after the app has worked."
---

![Return of the Five Stars: a parody movie poster of the author holding an iPhone up under five gold stars](/blog/listening-to-customers/return-of-the-five-stars.jpg)

*Nobody's going to rate you five stars for trying.*

**BLUF:** In four months the US, our biggest market, went from 3.51★ to 3.69★. The 9 US ratings we got since July average **4.99★**, so basically every one of them is a five, and they are coming in five times faster than in our first 13 years (65 ratings total). Worldwide we went from 3.28★ to 3.41★, and new ratings now average **4.53★**. We got there by listening. We answered every review and shipped what people asked for, and then we asked for a rating at the right moment, after the app worked for you, instead of showing the rate button only to people who paid.

## Position and velocity

The example I give people is basic kinematics. Your lifetime App Store average is your position. It's the integral of every rating since 2013, so it barely moves, and looking at it tells you nothing about this week.

The average of the *new* ratings is your velocity, and that's the number I steer by. Position only catches up if velocity stays above it for long enough, and ours has been above it in every period since July.[^1]

[[chart:periods]]

The first column is 13 years of history, 184 ratings at 3.28★. Every column after that is what came in between two snapshots. Hover any column and you'll see the split.

## We listened

I answer every review. Right now that's 99 out of 100, and the one I haven't answered came in last week. When a complaint is real I put it in the queue, and when the fix ships I go back and reply again.

| What they wrote | What shipped | Time |
|---|---|---|
| 🇹🇷 5★ "The countdown clock's sound is audible when the video starts" | `fix timer sound` (#106) | 9 days |
| 🇮🇹 3★ "it says 2X but actually uses the 5X", and no format choice | lens selection fix + aspect ratio controls (#89–#91) | 9 days |
| 🇺🇸 3★ "it would be nice if I could connect more than one camera" | Multicam Director, up to 4 iPhones (#203) | 6 months |
| Six reviews asking for zoom or the other lenses (🇺🇸🇬🇧🇮🇹, 2021 to 2023) | zoom + lens switching (#13) | years, then one PR |
| 🇬🇧 🇺🇸 "no tap to focus" | Tap to focus (#169) | |
| About ten "can't connect" 1★s, 2020 to 2026 | reconnection rebuilt (#61), then our own QUIC transport, Stormo (#183, #189) | |
| "No setup instructions", three times | tutorial + local network permission screens (#27, #28) | |

Yes, the zoom row is embarrassing. People asked for it in 2021 and I shipped it in 2025. The reviews kept asking for the same thing for four years, and they were right the whole time.

So about that second reply. When you replace your response to a review, Apple emails the reviewer again and invites them to update their rating. That's why I go back to every review a fix touches and tell them which version has it. Somebody who gave you 1★ for a bug that's gone now is somebody you can win back.

And people do come back. In August a reviewer in the US updated their review on their own: *"Since my last review on this app, which was less than positive, the newest version fixes every issue I initially had."* In November an Italian 5★ said just three words: *"Every problem solved!"*

## We asked at the right moment

Until July we were asking the wrong people. The "Rate on App Store" button only showed up if you had bought something, and that's about 4% of users. Paying doesn't mean you're happy, and Apple's guidelines don't want you picking who gets asked anyway. Everybody else only got the system prompt after ten captures. The fix (#164, shipped in 10.0.0 on Aug 13) made everyone eligible and dropped the bar to five.

The rule now is simple. You earn the ask when the app has worked for you. So we count five photos or clips that actually landed in your photo library. Buying something doesn't count, and neither does opening the app ten times.

Let me show you the details, because they matter more than the number five:

- The tally only goes up when the save to Photos succeeds, never when you tap the shutter. A failed save counts nothing. A rig with three cameras counts three.
- The system sheet waits two seconds, so it never covers the shot you just took.
- We ask four times at most, once per build, and never on top of the welcome screen.
- There are two different doors. The unsolicited ask uses Apple's system prompt (`SKStoreReviewController`), which iOS throttles to about three a year and which is allowed to show nothing at all. That's fine when nobody asked, but it's wrong for a button. So the "Rate on App Store" button in Settings opens the App Store's write-review page directly (`?action=write-review` on the app URL), and that one is never throttled.

Then in September I broke it. We deleted the classic remote screen (#236, shipped in 13.1.2), and it turned out that screen held the only calls into the review prompt. Nothing crashed and no test failed. The tally just stopped counting, and every new install stopped getting asked. The velocity chart caught it before anything else did: Aug 23 to Oct 4 is the low point, 3.17★. The fix (#250) moved the tally to where captures actually get saved now, and it shipped in 14.0.1 on Oct 30. These days I check that the prompt actually fires.

## Written reviews are the loudest slice

Before July, people who only tapped stars averaged **3.69★**, and people who wrote a review averaged **2.73★**. Same app, same years, a full star apart.

Mostly the people who write are the ones who got burned. So I read written reviews to find what to fix, and I read the snapshots to see if the fix is working.

[[chart:written-yearly]]

Look at the band. Most years have fewer than ten written reviews, so one year's average is mostly noise. The real change happened around 2020. Before that, written reviews averaged about 2.3★, and since then it's about 3.0★.

[[chart:written-share]]

## The receipts

Apple won't give anyone a list of dated star ratings. What you do get is two feeds, and between them it's enough.

| What we call | What it returns | Auth |
|---|---|---|
| `GET itunes.apple.com/lookup?id=<app>&country=<cc>` | lifetime rating count and average for one storefront | none, it's public |
| `GET /v1/apps/<app>/customerReviews?include=response` | every written review (stars, text, territory, date) plus your reply | App Store Connect API key, Sales role |
| `POST /v1/customerReviewResponses` | posts or replaces your reply to a review | same key |
| `GET /v1/salesReports` | daily downloads and proceeds | same key |
| `/v1/analyticsReportRequests` → reports → instances → segments | impressions, page views, downloads, sessions, crashes per territory | Admin once to create the request, then Sales reads it |

For velocity, every time we run the report we snapshot the lookup API across 37 storefronts into one SQLite file. Count times average gives you the total number of stars. Subtract two snapshots and you get how many ratings came in between and what they averaged. It works on any app, competitors too, because the lookup API doesn't need a login.

For reviews, the App Store Connect API signs every request with a short-lived JWT made from an API key. A Sales-role key is enough to read every review and to post replies. We page through the whole history on every run and store our response next to each review, so "which complaints are still unanswered" is one SQL query.

## Orchestrating it with Claude

All of this lives in its own private growth repo, never in the app repo. It's a dozen small Python scripts, one SQLite file, and a `CLAUDE.md` that writes the whole machine down: which key can read what, which endpoints are dead, which rows to net out. My favorite rule in there is *answer questions with SQL before writing any new script*.

With that file in place, running the whole thing is one sentence. I typed "pull the latest reviews because the trend is changing." Claude pulled the reviews, took a ratings snapshot, found the 14 new ratings, regenerated the charts, and told me the window average had moved to 4.53★. Then "commit and push everything" puts it in git, and `git log -p reports/` becomes the diary of every week.

Some things stay with me on purpose. I minted the Admin key that Analytics needs, once. And I decide what ships.

## What I'd do if I were you

- Snapshot the public lookup API for every storefront on a schedule. Two snapshots and you have velocity.
- Pull every written review with a Sales key, and treat it like a bug tracker.
- Answer all of them, and reply again with the version number when the fix ships.
- Only ask for a rating after the app worked: count real results, not taps, launches or purchases.
- Use the write-review link for buttons and the system prompt for the unsolicited ask, and check that it actually fires.

If you try the snapshot thing on your own app, I'd love to hear what your velocity looks like. Cheers.

[^1]: For the nerds: each column is a finite difference over the snapshot interval, so it's the average velocity over that window, not the instantaneous one. Per-storefront averages come back rounded to two decimals, so a window with only two ratings is mostly rounding. That's why windows merge until they hold six ratings.
