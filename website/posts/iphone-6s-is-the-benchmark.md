---
title: "We Made Remote Shutter Fast by Running It on an iPhone 6s"
date: "2026-11-01"
author: "Dario Lencina"
description: "A 2015 phone with 2 GB of RAM found every wasted copy in our video pipeline. Here is what it caught, what we fixed, and why the old phone is now the benchmark."
faq:
  - q: "Does Remote Shutter still run on an iPhone 6s?"
    a: "Yes. The 6s runs iOS 15, which is the app's minimum, and it works as both the camera and the remote. It is the slowest device we test on, on purpose."
  - q: "Why did the app crash on the 6s before?"
    a: "Two reasons. As a camera, it asked for an HEVC recorder the A9 chip does not have, which raised an exception Swift cannot catch. As a remote, it decoded frames faster than it could show them, and iOS killed it for memory about 19 seconds in."
  - q: "Do these fixes help on a new iPhone too?"
    a: "Yes. The same changes took the preview on an iPhone 18 Pro from 23 fps to 30 fps while recording 4K, and cut the preview encoder's time per frame roughly in half."
---

The iPhone 6s came out in September 2015. Trump was still on his first campaign. It has two CPU cores, 2 GB of RAM, and the last iOS it will ever get is 15. I put Remote Shutter on one this week and it crashed in under twenty seconds.

Good. That's the point of having one.

## Fast hardware hides slow code

Here's the thing about optimizing on an iPhone 18 Pro: you can't. Everything is fast. You copy a 4K frame three times, convert it to RGB and back, and the phone shrugs. The profiler shows 4% CPU and you go home.

A 6s doesn't shrug. Every wasted byte shows up as heat, dropped frames, or the kernel killing your process. It's a free profiler with a battery. If the code runs well on the 6s, it runs well on everything Apple has shipped in eleven years, and your new-phone users get the battery life.

So I pulled the crash logs off the old phone over USB and read them. Two different deaths.

## Death one: asking for hardware that isn't there

Start a recording on the 6s and the app aborted on the spot. The recorder asked AVFoundation for HEVC writer settings. The A9 has no HEVC encoder. That call doesn't return an error you can handle, it raises an Objective-C exception, and Swift can't catch those. The fallback on the next line never ran. Same stack trace in a crash report from September that nobody had looked at.

Fix: ask the camera what it can actually write and pick from that list. HEVC if it's there, H.264 if not. Phones with HEVC make the exact same call they did before.

## Death two: the remote decoded itself to death

This one was the real lesson. Run the 6s as the remote, point another phone at something, and the preview streams great. For about nineteen seconds. Then iOS kills the app with `vm-compressor-space-shortage`. Out of memory, system wide.

The app's own footprint was 46 MB and flat, so nothing was leaking. It was churn. Two bugs were multiplying each other.

First, the camera was never told to slow down. The protocol has a credit window: the camera sends a frame, the remote acks it, the camera sends another. Sounds right. Except the remote acked the frame the instant it arrived, before decoding it. So the camera streamed at a full 30 fps no matter how slowly the 6s could keep up, and undecoded frames piled up in a queue with no bound. On a fast phone you never notice because the queue drains. On two A9 cores it doesn't.

Second, every decoded frame became a bitmap. The camera sends 4:2:0 video. The decoder hands back a 4:2:0 pixel buffer, about 1.6 MB at the preview size. Then we ran it through Core Image to make a `CGImage` so SwiftUI could draw it with `Image(uiImage:)`. A `CGImage` is RGB. That's a GPU render, a copy back to the CPU, and a fresh 4.3 MB allocation. Thirty times a second. 130 MB/s of garbage, which SwiftUI then uploaded back to the GPU to draw. Round trip for nothing.

Fixes, in order of how much they mattered:

- **Ack after you show the frame, not when you receive it.** Now the credit goes back once the frame is on screen. The camera paces itself to what the remote can actually display. No frames are dropped, there are just never more than ten in flight end to end.
- **Draw the pixel buffer. Don't convert it.** The decoded 4:2:0 buffer goes straight into an `AVSampleBufferDisplayLayer`, wrapped, not copied. SwiftUI only learns the frame's pixel size, which changes maybe twice a session. A frame now re-renders nothing. Zero RGB anywhere on the remote.
- **VP9 too.** The 6s as a camera has to send VP9, since it can't encode HEVC. That decoder was doing the same RGB dance with vImage. Now it repacks its planes into the same 4:2:0 buffer. A memcpy and an interleave. No color math.

## The camera side got the same treatment

While I was in there, the camera had its own copies to kill. We had been asking the capture session for BGRA frames. The sensor produces 4:2:0. So every 4K frame was converted to BGRA at roughly 2.6× the memory traffic, and then both encoders converted it back. Now everything is 4:2:0 from the sensor to the wire.

The preview also used to be cut from the 4K recording frame on the GPU. Now the camera asks for a second, already-scaled output, so the preview lane never touches a 4K frame. And the preview encoder was waiting on the hardware encoder while the movie writer's frames sat ahead of it, dropping one preview frame in five. It gets its own lane and six frames of slack now.

Smaller ones: the remote copied each inbound datagram three times before the decoder saw a byte. Now it reads the datagram in place. The director rebuilt its whole settings menu on every single frame, 30 times a second, and diffed it to "unchanged". It skips frames now. The screen-awake flag was set once at launch and iOS 15 quietly dropped it, so the 6s locked mid-session. It's reasserted per scene.

## Numbers

On an iPhone 18 Pro recording 4K at 30: the preview encoder's time per frame went from 60 ms to 33 ms, and the remote's preview went from 23 fps to 29.8 fps during the take. The movie writes 30.2 fps with zero dropped frames. Decoding a frame on the remote went from 9 µs to 7 µs, which is nothing, but it was nothing we were paying for.

On the 6s: it records. It streams. The new build is on the phone as I write this, and the memory graph is the test.

None of this was clever. It's the same three rules every time. Don't copy what you can borrow. Don't convert what the hardware already produces in the right format. Don't send faster than the other side can consume. A 2015 phone enforced them for me because nothing newer would.

Keep an old phone in the drawer. It's the cheapest profiler you will ever own.
