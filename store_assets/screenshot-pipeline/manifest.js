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
          preview: {
            img: "../ai-scenes/slot0_ots_preview.jpg",
            rect: [22.0, 2.0, 55.9, 70.0],
            pos: "50% 47%",
            scale: 1.3
          },
          statusbar: { heightPct: 2.0, font: 34, pad: 44 }
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
        preview: "../ai-scenes/slot1_preview.jpg",
        previewPosition: "50% 45%",
        previewScale: 1.0,
        top: 800,
        width: 660
      },
      callouts: [
        { text: "PHOTO & VIDEO", anchorScreen: [0.726, 0.628], dx: 220, dy: -80 },
        { text: "TIMER", anchorScreen: [0.244, 0.693], dx: -230, dy: -60 },
        { text: "ZOOM & LENS", anchorScreen: [0.264, 0.752], dx: -230, dy: 110 },
        { text: "FLASH & TORCH", anchorScreen: [0.539, 0.928], dx: 240, dy: 30 }
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
          size: [1210, 2572],
          bezel: 0,
          radius: 190,
          ui: "assets/ui-monitor-iphone.png",
          preview: {
            img: "../ai-scenes/slot3_preview.jpg",
            rect: [17.86, 5.61, 64.36, 52.88],
            pos: "50% 40%",
            scale: 1.1
          },
          statusbar: { heightPct: 5.6, font: 42, pad: 60 }
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

    // ---- iPad variants ----
    "2i": {
      headline: ["See everything.", "Control everything."],
      accentLine: 1,
      mockup: {
        device: "ipad",
        ui: "assets/ui-monitor-ipad.png",
        preview: "../ai-scenes/slot1_preview.jpg",
        previewPosition: "50% 45%",
        previewScale: 1.0,
        top: 700,
        width: 1150
      },
      callouts: [
        { text: "PHOTO & VIDEO", anchorScreen: [0.738, 0.739], dx: 300, dy: -80 },
        { text: "TIMER", anchorScreen: [0.115, 0.786], dx: -260, dy: -60 },
        { text: "ZOOM & LENS", anchorScreen: [0.128, 0.828], dx: -260, dy: 110 },
        { text: "FLASH & TORCH", anchorScreen: [0.52, 0.953], dx: 300, dy: 30 }
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
          preview: {
            img: "../ai-scenes/slot3_preview.jpg",
            rect: [22.0, 2.0, 55.9, 70.0],
            pos: "50% 40%",
            scale: 1.1
          },
          statusbar: { heightPct: 2.0, font: 34, pad: 44 }
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
          preview: {
            img: "../ai-scenes/slot0_ots_preview.jpg",
            rect: [22.0, 2.0, 55.9, 70.0],
            pos: "50% 47%",
            scale: 1.3
          },
          statusbar: { heightPct: 2.0, font: 34, pad: 44 }
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
