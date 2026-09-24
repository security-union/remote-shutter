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

    // ---- Slot 6: multicam for iPhone — same scene as mac4, portrait ----
    // The scene is natively portrait, so the scene, the three screen quads and
    // the callout anchors are shared with mac4; only the layout and the pill
    // offsets differ. Portrait shows 2543 of the 2752 rows at full width, so
    // nearly the whole rig is in frame and the pills have real space to sit in.
    "6": {
      headline: ["NEW: Four cameras.", "One director."],
      accentLine: 1,
      scene: "../ai-scenes/mac4_climb_ipad_v2.jpg",
      sceneSize: [1536, 2752],
      scenePosition: "50% 35%",
      surfaces: [
        {
          quad: [[518, 1817], [830, 1865], [411, 2094], [730, 2180]],
          size: [2360, 1640],
          bezel: 0,
          radius: 9,
          ui: "assets/raw/monitor-ipad-multicam-climb.png"
        },
        {
          quad: [[197, 877], [367, 850], [190, 976], [366, 954]],
          size: [1704, 786],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-landscape.png"
        },
        {
          quad: [[990, 1989], [1081, 1985], [1004, 2180], [1092, 2178]],
          size: [786, 1704],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-portrait.png"
        }
      ],
      // Pills land in the two genuinely empty regions — the white clerestory
      // wall upper left, and the blue mats across the lower middle and right.
      // Nothing sits over the climber, the man's head, or a screen.
      callouts: [
        { text: "CAMERA 1", anchor: [300, 270], dx: 300, dy: 40 },
        { text: "CAMERA 2", anchor: [278, 995], dx: 120, dy: -330 },
        { text: "CAMERA 4", anchor: [1395, 1120], dx: -150, dy: 430 },
        { text: "CAMERA 3", anchor: [1044, 2215], dx: 180, dy: -300 },
        { text: "REMOTE", anchor: [455, 2130], dx: 60, dy: 330 }
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
    // 6i: the multicam feature for the iPad listing, which had none. Full-bleed
    // scene does not work here — an iPad canvas shows only ~1565 of the scene's
    // 2752 rows and the rig spans ~2135, so the ceiling camera drops out and a
    // "Four cameras" headline would overclaim. The device mockup shows all four
    // feeds instead, which is also the strongest framing on an iPad: the thing
    // you are holding is the thing running the rig. Headline inherits "6"
    // (baseId strips the trailing i), so all 15 locales already have it.
    "6i": {
      // Runs the mac5 headline: this slot IS the grid screen, and the scene
      // slot below already carries "Four cameras. One director."
      headlineKey: "mac5",
      headline: ["4 cameras connected.", "One synced shutter."],
      accentLine: 1,
      mockup: {
        device: "ipad",
        // Held landscape: the four 16:9 feeds fill the cells instead of
        // letterboxing into portrait ones, which left the top of the screen
        // mostly black.
        ar: 1640 / 2360,
        ui: "assets/raw/monitor-ipad-multicam-climb.png",
        naturalSize: [2360, 1640],
        top: 1130,
        width: 1650
      },
      // The device is narrowed to 1430 so the right-hand controls have margin
      // to point into; pills sit above and below the frame rather than beside
      // it, which ran them off the canvas.
      callouts: [
        { text: "FLASH & TORCH", anchorScreen: [0.898, 0.038], dx: -60, dy: -250 },
        // "LIVE PREVIEW" rather than a new string: it is already translated in
        // all 14 locales and slot 2i uses it for the same thing. The headline
        // already carries the "4 cameras" claim.
        { text: "LIVE PREVIEW", anchorScreen: [0.30, 0.52], dx: -250, dy: 270 },
        { text: "SYNCED SHUTTER", anchorScreen: [0.928, 0.432], dx: 40, dy: 430 },
        { text: "PHOTO & VIDEO", anchorScreen: [0.848, 0.962], dx: 210, dy: 250 }
      ]
    },
    // 6is: the rig scene on iPad — the same photo and surfaces as the iPhone
    // slot, in the iPad layout. sceneFit "contain" because an iPad canvas is far
    // squarer: cover-fit shows only ~1565 of the 2752 rows and the rig spans
    // ~2135, so the ceiling camera would drop out and "Four cameras" would
    // overclaim. Contained, every camera stays in frame and the side margins
    // give the callouts clean space to sit in.
    "6is": {
      headlineKey: "6",
      headline: ["NEW: Four cameras.", "One director."],
      accentLine: 1,
      scene: "../ai-scenes/mac4_climb_ipad_v2.jpg",
      sceneSize: [1536, 2752],
      sceneFit: "contain",
      scenePosition: "50% 50%",
      surfaces: [
        {
          quad: [[518, 1817], [830, 1865], [411, 2094], [730, 2180]],
          size: [2360, 1640],
          bezel: 0,
          radius: 9,
          ui: "assets/raw/monitor-ipad-multicam-climb.png"
        },
        {
          quad: [[197, 877], [367, 850], [190, 976], [366, 954]],
          size: [1704, 786],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-landscape.png"
        },
        {
          quad: [[990, 1989], [1081, 1985], [1004, 2180], [1092, 2178]],
          size: [786, 1704],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-portrait.png"
        }
      ],
      callouts: [
        { text: "CAMERA 1", anchor: [300, 270], dx: -330, dy: -70 },
        { text: "CAMERA 2", anchor: [278, 995], dx: -340, dy: 60 },
        { text: "CAMERA 4", anchor: [1395, 1120], dx: 330, dy: -80 },
        { text: "CAMERA 3", anchor: [1044, 2215], dx: 360, dy: -140 },
        { text: "REMOTE", anchor: [455, 2130], dx: -330, dy: 120 }
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

    // mac4: the four-camera bouldering rig. A boulder problem happens once and
    // the climber's hands are on the wall, so the remote shutter is the only way
    // to shoot it — four angles of one instant. The director's screen is the real
    // iPad grid rendered from the app's own SwiftUI (MulticamGridSnapshotTests),
    // not another platform's capture stretched to fit.
    //
    // sceneWidth 0.44 rather than the default 0.56: the four mounts plus the
    // tablet span 2125 rows of the 2752-row scene, and a 56% panel only shows
    // 1714. A narrower panel scales the cover-fit down and shows 2182.
    "mac4": {
      layout: "landscape",
      headline: ["NEW: Four cameras.", "One director."],
      accentLine: 1,
      // The Mac listing shows a Mac directing. Same rig, same instant as the
      // iPhone slot, but the laptop runs the grid rather than a tablet.
      scene: "../ai-scenes/mac4_climb_mac.jpg",
      sceneSize: [1536, 2752],
      // sceneWidth 0.44 rather than the default 0.56: the four mounts plus the
      // laptop span ~2150 rows of the 2752-row scene, and a 56% panel shows
      // only 1714. A narrower panel scales the cover-fit down and shows 2182.
      sceneWidth: 0.44,
      headlineScale: 1.3,
      scenePosition: "50% 8%",
      surfaces: [
        {
          quad: [[546, 1831], [821, 1876], [455, 2078], [728, 2143]],
          size: [1512, 982],
          bezel: 0,
          radius: 9,
          ui: "assets/ui-monitor-mac-multicam-climb.png"
        },
        // Three camera phones run the app's real standby screen. The ceiling
        // phone is left dark: its clamp arm crosses the glass, and a surface
        // has no occlusion mask, so compositing would paint the clamp out.
        {
          quad: [[187, 838], [373, 897], [170, 937], [358, 986]],
          size: [1704, 786],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-landscape.png"
        },
        {
          quad: [[1290, 906], [1387, 910], [1296, 1125], [1396, 1129]],
          size: [786, 1704],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-portrait.png"
        },
        {
          quad: [[985, 1984], [1064, 1981], [1012, 2186], [1100, 2181]],
          size: [786, 1704],
          bezel: 0,
          radius: 6,
          ui: "assets/raw/camera-standby-portrait.png"
        }
      ],
      // Numbers match the grid tiles (1=TL Ceiling, 2=TR Stand, 3=BL Tripod,
      // 4=BR Column). Anchored on each mount, never on glass or a face: his
      // head occupies canvas (1647,1101)-(1858,1259) and the laptop screen
      // (1988,1473)-(2290,1730).
      callouts: [
        { text: "CAMERA 1", anchor: [300, 290], dx: 260, dy: 90 },
        { text: "CAMERA 2", anchor: [275, 1010], dx: 190, dy: 265 },
        { text: "CAMERA 4", anchor: [1420, 1140], dx: -180, dy: -470 },
        { text: "CAMERA 3", anchor: [1045, 2200], dx: 60, dy: -400 },
        { text: "REMOTE", anchor: [450, 2060], dx: 60, dy: -230 }
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
        ui: "assets/ui-monitor-mac-multicam-climb.png",
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
