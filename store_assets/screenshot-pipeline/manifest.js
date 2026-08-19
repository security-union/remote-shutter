// Screenshot manifest — drives template.html (browser) and render.mjs (node).
// Surface quads are in ORIGINAL scene-image pixel coordinates, order TL,TR,BL,BR.
// Callout label offsets (dx/dy) are in 1290x2796 design px (scaled by k).
window.MANIFEST = {
  slots: {
    // ---- Slot 0: studio hero (photographer, iPad remote, tripod iPhone) ----
    "0": {
      headline: ["One phone is the camera.", "The other is the remote."],
      accentLine: 1,
      scene: "../ai-scenes/slot0_ots_c1.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 30%",
      surfaces: [
        {
          quad: [[612, 894], [1185, 891], [694, 1770], [1265, 1716]],
          size: [1688, 2408],
          bezel: 24,
          radius: 56,
          innerRadius: 32,
          ui: "assets/ui-monitor-ipad.png",
          viewfinder: "../ai-scenes/slot0_ots_preview.jpg",
          statusbar: { heightPct: 3.0, font: 34, pad: 44 }
        },
        {
          quad: [[88, 1113], [262, 1115], [90, 1494], [263, 1496]],
          size: [1210, 2572],
          bezel: 0,
          radius: 185,
          notch: [460, 95],
          chrome: "camera",
          img: "../ai-scenes/slot0_ots_preview.jpg",
          pos: "50% 46%",
          scale: 1.35
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [183, 1085], dx: 60, dy: -170 },
        { text: "REMOTE", anchor: [900, 880], dx: -40, dy: -160 }
      ]
    },

    // ---- Slot 1: family group photo ----
    "1": {
      headline: ["Everyone's in the shot.", "Including you."],
      accentLine: 1,
      scene: "../ai-scenes/slot1_group_c2.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 50%",
      surfaces: [
        {
          // Tripod phone, landscape, showing the live view of the family.
          quad: [[72, 1528], [415, 1525], [72, 1698], [418, 1699]],
          size: [2572, 1210],
          bezel: 0,
          radius: 180,
          chrome: "camera",
          img: "../ai-scenes/slot1_preview.jpg",
          pos: "50% 50%",
          scale: 1.0
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [244, 1510], dx: 220, dy: 130 },
        { text: "REMOTE", anchor: [1020, 1480], dx: 170, dy: -150 }
      ]
    },

    // ---- Slot 2: monitor UI feature callouts (no scene) ----
    "2": {
      headline: ["See everything.", "Control everything."],
      accentLine: 1,
      mockup: {
        ui: "assets/ui-monitor-iphone.png",
        // Near the screen's own aspect, so the frame runs wall to wall — the
        // point of the redesign, and it gives the glass chrome something with
        // contrast to sit on.
        viewfinder: "../ai-scenes/mac3_preview_port.jpg",
        top: 800,
        width: 660
      },
      callouts: [
        { text: "FLASH & TORCH", anchorScreen: [0.727, 0.091], dx: -170, dy: -150 },
        { text: "TIMER", anchorScreen: [0.897, 0.091], dx: 150, dy: -150 },
        { text: "LIVE PREVIEW", anchorScreen: [0.5, 0.42], dx: 300, dy: -60 },
        { text: "ZOOM & LENS", anchorScreen: [0.5, 0.757], dx: -290, dy: 30 },
        { text: "PHOTO & VIDEO", anchorScreen: [0.5, 0.923], dx: 300, dy: 120 }
      ]
    },

    // ---- Slot 3: wildlife (over-the-shoulder: her phone runs the remote) ----
    "3": {
      headline: ["Get close.", "Without getting close."],
      accentLine: 1,
      scene: "../ai-scenes/slot3_ots_c1p.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 35%",
      surfaces: [
        {
          // Her phone: real monitor UI, live preview shows the cardinal.
          quad: [[458, 1119], [750, 1108], [497, 1766], [789, 1746]],
          // The overlay's native pixels — the chrome maps 1:1, no stretch.
          size: [1170, 2532],
          bezel: 0,
          radius: 185,
          ui: "assets/ui-monitor-iphone.png",
          viewfinder: "../ai-scenes/slot3_preview.jpg",
          statusbar: { heightPct: 4.9, font: 42, pad: 60 }
        },
        {
          // Camera phone on the railing tripod (soft focus like the scene).
          quad: [[780, 549], [906, 537], [794, 804], [909, 794]],
          size: [1210, 2572],
          bezel: 0,
          radius: 170,
          img: "../ai-scenes/slot3_preview.jpg",
          pos: "50% 42%",
          scale: 1.0,
          blur: 30
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [848, 540], dx: 80, dy: -130 },
        { text: "REMOTE", anchor: [614, 1113], dx: -160, dy: -150 }
      ]
    },

    // ---- Slot 4: Apple Watch + telescope ----
    "4": {
      headline: ["NEW: Fire the shutter", "from your wrist."],
      accentLine: 1,
      scene: "../ai-scenes/slot4_watch_c1.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 15%",
      surfaces: [
        {
          // Smartwatch screen: Watch live-view chrome over the moon shot.
          quad: [[615, 1060], [915, 1028], [662, 1468], [970, 1420]],
          size: [820, 1004],
          bezel: 0,
          radius: 190,
          chrome: "watch",
          img: "../ai-scenes/slot4_preview.jpg",
          pos: "50% 50%",
          scale: 0.62
        },
        {
          // Phone clamped to the telescope eyepiece: moon viewfinder.
          quad: [[209, 634], [398, 614], [110, 933], [308, 940]],
          size: [1230, 2050],
          bezel: 0,
          radius: 160,
          img: "../ai-scenes/slot4_preview.jpg",
          pos: "50% 50%",
          scale: 0.55
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [300, 600], dx: 90, dy: -150 },
        { text: "REMOTE", anchor: [790, 1030], dx: -160, dy: -170 }
      ]
    },

    // ---- Slot 5: role picker / no-internet (no scene) ----
    "5": {
      headline: ["No internet. No account.", "Just connect."],
      accentLine: 1,
      mockup: {
        ui: "assets/ui-rolepicker-iphone.png",
        statusbar: false,
        top: 800,
        width: 660
      }
    },

    // ---- Slot 6: multicam for iPhone — same content as mac4, portrait ----
    // The scene is natively portrait, so everything (scene, quad, composed
    // screen, callout anchors) is shared with mac4; only the layout differs.
    // Headlines: translations copy the mac4 strings to key "6".
    "6": {
      headline: ["NEW: Four cameras.", "One director."],
      accentLine: 1,
      scene: "../ai-scenes/mac2_multicam_e6.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 30%",
      surfaces: [
        {
          quad: [[-64, 1514], [417, 1397], [131, 2058], [584, 1842]],
          size: [1512, 982],
          bezel: 0,
          radius: 9,
          ui: "assets/ui-monitor-mac-multicam.png"
        }
      ],
      callouts: [
        { text: "CAMERA 3", anchor: [805, 633], dx: -150, dy: -150 },
        { text: "CAMERA 1", anchor: [612, 860], dx: -230, dy: 130 },
        { text: "CAMERA 4", anchor: [1218, 826], dx: 40, dy: -230 },
        { text: "CAMERA 2", anchor: [1369, 1073], dx: -360, dy: 300 },
        { text: "REMOTE", anchor: [300, 1620], dx: 420, dy: 160 }
      ]
    },

    // ---- iPad variants ----
    "2i": {
      headline: ["See everything.", "Control everything."],
      accentLine: 1,
      mockup: {
        device: "ipad",
        ui: "assets/ui-monitor-ipad.png",
        // Same frame the iPhone slot uses: the feature story reads the same on
        // both device families, and it fills the screen top to bottom.
        viewfinder: "../ai-scenes/mac3_preview_port.jpg",
        top: 700,
        width: 1150
      },
      callouts: [
        { text: "FLASH & TORCH", anchorScreen: [0.870, 0.053], dx: -180, dy: -160 },
        { text: "TIMER", anchorScreen: [0.951, 0.053], dx: 170, dy: -160 },
        { text: "LIVE PREVIEW", anchorScreen: [0.5, 0.42], dx: 380, dy: -60 },
        { text: "ZOOM & LENS", anchorScreen: [0.5, 0.834], dx: -360, dy: 30 },
        { text: "PHOTO & VIDEO", anchorScreen: [0.5, 0.956], dx: 330, dy: 90 }
      ]
    },
    "3i": {
      headline: ["Get close.", "Without getting close."],
      accentLine: 1,
      scene: "../ai-scenes/slot3_ipad_c1.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 35%",
      surfaces: [
        {
          // Her iPad: real iPad monitor UI, live preview shows the cardinal.
          quad: [[290, 1118], [870, 1080], [345, 1925], [940, 1870]],
          size: [1640, 2360],
          bezel: 0,
          radius: 70,
          ui: "assets/ui-monitor-ipad.png",
          viewfinder: "../ai-scenes/slot3_preview.jpg",
          statusbar: { heightPct: 3.0, font: 34, pad: 44 }
        },
        {
          // Camera phone on the railing tripod (soft focus like the scene).
          quad: [[780, 549], [906, 537], [794, 804], [909, 794]],
          size: [1210, 2572],
          bezel: 0,
          radius: 170,
          img: "../ai-scenes/slot3_preview.jpg",
          pos: "50% 42%",
          scale: 1.0,
          blur: 30
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [848, 540], dx: 80, dy: -130 },
        { text: "REMOTE", anchor: [580, 1095], dx: -160, dy: -150 }
      ]
    },
    "5i": {
      headline: ["No internet. No account.", "Just connect."],
      accentLine: 1,
      mockup: {
        device: "ipad",
        ui: "assets/ui-rolepicker-ipad.png",
        statusbar: false,
        top: 700,
        width: 1150
      }
    },

    // ---- Mac App Store listing (landscape 16:10 canvas, 2880x1800) ----
    // mac0: studio hero — the Mac runs the camera (pro cinema camera on the
    // desk feeding it), the iPhone in hand is the remote.
    "mac0": {
      layout: "landscape",
      headline: ["Your Mac is the camera.", "Your iPhone is the remote."],
      accentLine: 1,
      scene: "../ai-scenes/mac0_studio_e2.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 50%",
      surfaces: [
        {
          // MacBook screen: real Catalyst camera UI, live view of the watch.
          quad: [[30, 1396], [464, 1319], [102, 1705], [533, 1602]],
          size: [3842, 2102],
          bezel: 0,
          radius: 18,
          // Real capture with the live view baked in (the camera screen is
          // full-bleed with floating chrome — no clean preview rect exists).
          ui: "assets/ui-camera-mac.png"
        },
        {
          // iPhone in her hand: real monitor UI, live preview of the watch —
          // same treatment as slot 3's remote phone.
          quad: [[910, 952], [1114, 928], [979, 1417], [1183, 1392]],
          size: [1170, 2532],
          bezel: 0,
          radius: 185,
          ui: "assets/ui-monitor-iphone.png",
          // The Mac's landscape frame, letterboxed by the viewfinder's own fit —
          // exactly what the phone shows when the camera is a wide sensor.
          viewfinder: "../ai-scenes/mac0_preview.jpg",
          statusbar: { heightPct: 4.9, font: 42, pad: 60 }
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [270, 1360], dx: -40, dy: -160 },
        { text: "PRO CAMERA", anchor: [340, 1830], dx: -80, dy: 170 },
        // Label ABOVE the phone — pulling it left collides with CAMERA in
        // locales with long words (e.g. ru КАМЕРА/ПУЛЬТ).
        { text: "REMOTE", anchor: [1010, 945], dx: 30, dy: -150 }
      ]
    },

    // mac3: the Mac as the director's monitor — iPhone on the windowsill
    // tripod films the feeder; the big screen shows the live view.
    "mac3": {
      layout: "landscape",
      headline: ["Direct the shot", "from the big screen."],
      accentLine: 1,
      scene: "../ai-scenes/mac3_direct_e1.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 30%",
      surfaces: [
        {
          // MacBook screen: real Mac monitor UI, live view of the cardinal.
          quad: [[566, 1314], [1386, 1323], [511, 1841], [1378, 1866]],
          size: [1891, 1052],
          bezel: 0,
          radius: 9,
          ui: "assets/ui-monitor-mac.png",
          viewfinder: "../ai-scenes/mac3_preview.jpg",
          // Below the window's opaque title bar (54px of 1052).
          viewfinderTop: 5.13
        },
        {
          // Camera phone in the GorillaPod clamp: live view with camera chrome.
          quad: [[1120, 566], [1247, 566], [1119, 865], [1250, 863]],
          size: [1210, 2572],
          bezel: 0,
          radius: 170,
          chrome: "camera",
          // Exactly the frame shown on the Mac (same file, phone-screen aspect).
          img: "../ai-scenes/mac3_preview_port.jpg",
          pos: "50% 50%",
          scale: 1.0
        }
      ],
      callouts: [
        { text: "REMOTE", anchor: [950, 1320], dx: 50, dy: -140 },
        { text: "CAMERA", anchor: [1187, 700], dx: -110, dy: 180 }
      ]
    },

    // mac1: remote UI feature callouts — real Mac monitor-window capture
    // (chrome + rounded corners + baked preview in the asset), no scene.
    "mac1": {
      layout: "landscape",
      headline: ["See everything.", "Control everything."],
      accentLine: 1,
      mockup: {
        device: "mac",
        // Its own capture: a near-square window, which fits the landscape
        // canvas better than the wide one the in-scene MacBooks use, and lets
        // the 16:9 frame letterbox — putting every control on black, which is
        // what a callout slot needs.
        ui: "assets/ui-monitor-mac-square.png",
        viewfinder: "../ai-scenes/slot1_preview.jpg",
        viewfinderTop: 5.13,
        naturalSize: [1205, 1052],
        width: 900,
        left: "72%",
        top: 147
      },
      callouts: [
        // Both labels are pulled left and separated vertically: the window's
        // top-right corner sits ~130px from the canvas edge, so a label routed
        // outward clips the moment a locale spells it out (ru ТАЙМЕР, vi ĐÈN
        // FLASH & ĐÈN PIN).
        { text: "FLASH & TORCH", anchorScreen: [0.911, 0.078], dx: -640, dy: -125 },
        { text: "TIMER", anchorScreen: [0.966, 0.078], dx: -110, dy: -125 },
        { text: "ZOOM & LENS", anchorScreen: [0.5, 0.836], dx: -400, dy: 190 },
        { text: "PHOTO & VIDEO", anchorScreen: [0.5, 0.973], dx: 260, dy: 150 }
      ]
    },

    // mac2: hands-full cooking — overhead iPhone on an under-cabinet arm films
    // the charcuterie board; she runs the shot from the Mac on the counter.
    "mac2": {
      layout: "landscape",
      headline: ["Hands full?", "Camera handled."],
      accentLine: 1,
      scene: "../ai-scenes/mac2_cook_c1_crop.jpg",
      sceneSize: [1536, 1770],
      scenePosition: "50% 50%",
      surfaces: [
        {
          // MacBook screen: monitor UI over the overhead board feed.
          quad: [[-53, 1094], [414, 967], [130, 1598], [579, 1391]],
          size: [1891, 1052],
          bezel: 0,
          radius: 9,
          ui: "assets/ui-monitor-mac.png",
          viewfinder: "../ai-scenes/mac2_preview.jpg",
          viewfinderTop: 5.13
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [800, 170], dx: -90, dy: 170 },
        { text: "REMOTE", anchor: [300, 1150], dx: 60, dy: -180 }
      ]
    },

    // mac4: NEW multicam — the four-camera kitchen rig (scene chain
    // mac2_multicam_e1..e6; quads inherited from mac2's base photo, +440y for
    // the uncropped frame). Every camera gets a CAMERA pill; the Mac runs the
    // composed grid (assets/ui-monitor-mac-multicam.png, built by
    // `tools.py grid` — see README).
    "mac4": {
      layout: "landscape",
      headline: ["NEW: Four cameras.", "One director."],
      accentLine: 1,
      scene: "../ai-scenes/mac2_multicam_e6.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 30%",
      surfaces: [
        {
          quad: [[-64, 1514], [417, 1397], [131, 2058], [584, 1842]],
          size: [1512, 982],
          bezel: 0,
          radius: 9,
          ui: "assets/ui-monitor-mac-multicam.png"
        }
      ],
      // Numbers match the grid tiles on the Mac's screen (1=TL … 4=BR), so
      // the pills double as a legend. Spread: arm up-left, stand mid-left,
      // hood up-right (short label fits inboard of the edge), eye-level
      // down-left of its phone, REMOTE over the counter — nothing stacks and
      // nothing can grow over the laptop in long locales.
      callouts: [
        { text: "CAMERA 3", anchor: [805, 633], dx: -150, dy: -150 },  // under-cabinet arm → tile 3
        { text: "CAMERA 1", anchor: [612, 860], dx: -230, dy: 130 },   // stand by the window → tile 1
        { text: "CAMERA 4", anchor: [1218, 826], dx: 40, dy: -230 },   // range-hood clamp → tile 4
        { text: "CAMERA 2", anchor: [1369, 1073], dx: -360, dy: 300 }, // eye-level stand → tile 2
        { text: "REMOTE", anchor: [300, 1620], dx: 420, dy: 160 }      // the Mac
      ]
    },

    // mac5: the multicam monitor itself — four live tiles, chrome from a real
    // window capture (see the grid recipe in the README).
    "mac5": {
      layout: "landscape",
      headline: ["4 cameras connected.", "One synced shutter."],
      accentLine: 1,
      mockup: {
        device: "mac",
        ui: "assets/ui-monitor-mac-multicam.png",
        naturalSize: [1512, 982],
        width: 1020,
        left: "70%",
        top: 400
      },
      callouts: [
        { text: "SYNCED SHUTTER", anchorScreen: [0.499, 0.902], dx: -430, dy: -10 },
        { text: "PHOTO & VIDEO", anchorScreen: [0.5, 0.973], dx: 360, dy: 55 },
        { text: "ZOOM & LENS", anchorScreen: [0.5, 0.826], dx: 340, dy: -50 },
        { text: "FLASH & TORCH", anchorScreen: [0.929, 0.084], dx: -290, dy: -115 }
      ]
    },

    // ---- In-App Event card / horizontal marketing banner (16:9) ----
    "banner": {
      layout: "landscape",
      headline: ["One phone is the camera.", "The other is the remote."],
      accentLine: 1,
      scene: "../ai-scenes/slot0_ots_c1.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 32%",
      surfaces: [
        {
          quad: [[612, 894], [1185, 891], [694, 1770], [1265, 1716]],
          size: [1688, 2408],
          bezel: 24,
          radius: 56,
          innerRadius: 32,
          ui: "assets/ui-monitor-ipad.png",
          viewfinder: "../ai-scenes/slot0_ots_preview.jpg",
          statusbar: { heightPct: 3.0, font: 34, pad: 44 }
        },
        {
          quad: [[88, 1113], [262, 1115], [90, 1494], [263, 1496]],
          size: [1210, 2572],
          bezel: 0,
          radius: 185,
          notch: [460, 95],
          chrome: "camera",
          img: "../ai-scenes/slot0_ots_preview.jpg",
          pos: "50% 46%",
          scale: 1.35
        }
      ],
      callouts: [
        { text: "CAMERA", anchor: [183, 1085], dx: 30, dy: -130 },
        { text: "REMOTE", anchor: [900, 880], dx: 0, dy: -120 }
      ]
    }
  }
};
