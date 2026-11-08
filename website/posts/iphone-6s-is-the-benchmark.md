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

![A scuffed iPhone 6s on a sun-bleached workbench, dust on the cracked screen, flies resting on it](/blog/iphone-6s-flies.jpg)

Remote Shutter pairs two devices. One is the camera. The other is the remote: it shows a live video preview from the camera and has the shutter button. The camera compresses that preview and streams it to the remote over a direct peer-to-peer Wi-Fi link.

The iPhone 6s came out in September 2015. Trump was still on his first campaign. It has two CPU cores, 2 GB of RAM, and iOS 15 at most. It's the slowest phone the app supports, so I use it as the performance benchmark. A new iPhone hides waste, like copying a 4K frame three times, behind a few percent of CPU. The 6s turns the same waste into dropped frames or a crash. This week it crashed in two different ways.

## Crash 1: recording asked for an encoder the phone doesn't have

Starting a recording killed the app. The recorder asked AVFoundation for HEVC (H.265) output settings. The 6s has no HEVC encoder, and AVFoundation doesn't return an error in that case. It raises an Objective-C exception, which Swift can't catch, so our H.264 fallback on the next line never ran.

The fix: ask the camera which codecs it can actually write, then pick HEVC if it's on the list and H.264 if not. Phones with HEVC behave exactly as before.

## Crash 2: the remote ran out of memory

With the 6s as the remote, the preview played for about 19 seconds. Then iOS killed the app with `vm-compressor-space-shortage`, meaning the whole system ran out of memory. The app's footprint stayed flat at 46 MB, so it wasn't a leak. It was allocating and freeing large buffers faster than iOS could reclaim them, because of two bugs.

**Flow control acknowledged frames too early.** The camera may have at most ten frames the remote hasn't acknowledged yet. The remote acked each frame the moment it arrived, before decoding it, so the camera kept sending 30 frames per second. The 6s couldn't decode that fast, and the undecoded frames piled up in a queue with no size limit.

**Every frame was converted to RGB just to draw it.** The decoder outputs YUV 4:2:0, the format cameras and video codecs use natively, about 1.6 MB per frame at preview size. We then converted each frame to an RGB image with Core Image so SwiftUI could display it. That's a GPU pass, a copy back to CPU memory and a new 4.3 MB allocation, 30 times a second: roughly 130 MB/s of throwaway memory.

The fixes:

- **Ack after display.** The remote now acks a frame once it's on screen. The camera can't get more than ten frames ahead of the screen.
- **Display the 4:2:0 frame directly.** The decoded buffer goes straight into an `AVSampleBufferDisplayLayer`, which draws YUV without converting or copying it.
- **Same for VP9.** A 6s acting as the camera sends VP9, since it can't encode HEVC. The VP9 decoder had the same RGB conversion. It now writes straight into the same 4:2:0 buffer format, with no color conversion.

## The camera had the same problems

- **Capture format.** We asked the camera for BGRA (RGB) frames, but the sensor produces 4:2:0. So iOS converted every 4K frame to BGRA, about 2.6x the memory traffic, and both video encoders converted it back. Frames now stay 4:2:0 from sensor to network.
- **Preview scaling.** The preview was scaled down from each 4K recording frame. The camera now provides a second, smaller output for it.
- **Shared hardware encoder.** While recording, the preview encoder waited behind the movie recorder for the hardware encoder and dropped about one preview frame in five. Now it doesn't wait.
- **Network copies.** Messages use FlatBuffers, a format designed to be read directly from the received bytes. We were copying instead: three times per incoming frame on the remote, twice per outgoing frame on the camera. Now it's zero copies in and one out.

Two smaller ones: the multi-camera screen rebuilt its settings menu on every preview frame for no reason, and the keep-screen-awake setting was lost on iOS 15, so the 6s locked mid-shoot.

## Results

On an iPhone 18 Pro recording 4K at 30 fps:

- Preview encoding time per frame: 60 ms to 33 ms.
- Preview on the remote during the recording: 23 fps to 29.8 fps.
- The recorded movie: 30.2 fps, zero dropped frames.

On the 6s, both crashes are gone. It records, and it works as the remote.

None of this was clever. Read data in place instead of copying it, keep the format the hardware produces, and don't send faster than the receiver can process. An old phone breaks the moment you forget one, which is why I keep one in the drawer.
