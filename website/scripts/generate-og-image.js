const sharp = require('sharp');
const path = require('path');

const PUBLIC = path.join(__dirname, '..', 'public');

async function generate() {
  const width = 1200;
  const height = 630;
  const iconSize = 200;
  const screenshotHeight = 480;
  const screenshotWidth = Math.round(screenshotHeight * (1290 / 2796));
  const gap = 16;

  // Load and resize app icon with rounded corners
  const icon = await sharp(path.join(PUBLIC, 'app-icon.png'))
    .resize(iconSize, iconSize)
    .png()
    .toBuffer();

  // Load and resize screenshots
  const screenshotFiles = [
    '0_APP_IPHONE_67_0.png',
    '1_APP_IPHONE_67_1.png',
    '2_APP_IPHONE_67_2.png',
    '3_APP_IPHONE_67_3.png',
  ];

  const screenshots = await Promise.all(
    screenshotFiles.map((f) =>
      sharp(path.join(PUBLIC, 'screenshots', f))
        .resize(screenshotWidth, screenshotHeight, { fit: 'contain' })
        .png()
        .toBuffer()
    )
  );

  const totalScreenshotsWidth =
    screenshots.length * screenshotWidth + (screenshots.length - 1) * gap;
  const screenshotsStartX = Math.round((width - totalScreenshotsWidth) / 2);
  const screenshotsY = height - screenshotHeight - 20;

  // Create SVG text overlay
  const textSvg = `<svg width="${width}" height="${height}">
    <text x="${width / 2}" y="100" text-anchor="middle"
      font-family="-apple-system, BlinkMacSystemFont, sans-serif"
      font-size="42" font-weight="700" fill="#EDEDED">
      Remote Shutter
    </text>
    <text x="${width / 2}" y="145" text-anchor="middle"
      font-family="-apple-system, BlinkMacSystemFont, sans-serif"
      font-size="22" fill="#9CA3AF">
      Turn Two iPhones Into a Remote Camera System
    </text>
  </svg>`;

  const composites = [
    // App icon centered at top
    { input: icon, left: Math.round((width - iconSize) / 2) - 240, top: 55 },
    // Text overlay
    { input: Buffer.from(textSvg), left: 0, top: 0 },
  ];

  // Add screenshots side by side
  screenshots.forEach((buf, i) => {
    composites.push({
      input: buf,
      left: screenshotsStartX + i * (screenshotWidth + gap),
      top: screenshotsY,
    });
  });

  await sharp({
    create: {
      width,
      height,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 1 },
    },
  })
    .composite(composites)
    .jpeg({ quality: 85 })
    .toFile(path.join(PUBLIC, 'og-image.jpg'));

  console.log('Generated og-image.jpg');
}

generate().catch(console.error);
