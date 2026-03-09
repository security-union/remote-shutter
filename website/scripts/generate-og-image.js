const sharp = require('sharp');
const path = require('path');

const PUBLIC = path.join(__dirname, '..', 'public');
const REPO = path.join(__dirname, '..', '..');

async function generate() {
  const width = 1200;
  const height = 630;

  const iconSize = 90;
  const screenshotHeight = 460;
  const screenshotWidth = Math.round(screenshotHeight * (1290 / 2796)); // ~212
  const gap = 10;

  // Load app icon with rounded corners
  const radius = Math.round(iconSize * 0.22);
  const roundedMask = Buffer.from(
    `<svg width="${iconSize}" height="${iconSize}">
      <rect x="0" y="0" width="${iconSize}" height="${iconSize}" rx="${radius}" ry="${radius}" fill="white"/>
    </svg>`
  );
  // Use the original 1024x1024 icon from the app assets for max quality
  const icon = await sharp(
    path.join(REPO, 'RemoteCam/Assets.xcassets/AppIcon.appiconset/1024.png')
  )
    .resize(iconSize, iconSize)
    .composite([{ input: roundedMask, blend: 'dest-in' }])
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
        .resize(screenshotWidth, screenshotHeight, { fit: 'cover' })
        .png()
        .toBuffer()
    )
  );

  // Screenshots on the right
  const totalScreenshotsWidth =
    screenshots.length * screenshotWidth + (screenshots.length - 1) * gap;
  const screenshotsStartX = width - totalScreenshotsWidth - 40;
  const screenshotsY = Math.round((height - screenshotHeight) / 2);

  // Left panel
  const leftCenterX = Math.round(screenshotsStartX / 2);

  const textSvg = `<svg width="${screenshotsStartX}" height="${height}">
    <text x="${leftCenterX}" y="330" text-anchor="middle"
      font-family="-apple-system, BlinkMacSystemFont, sans-serif"
      font-size="32" font-weight="700" fill="#EDEDED">
      Remote Shutter
    </text>
    <text x="${leftCenterX}" y="368" text-anchor="middle"
      font-family="-apple-system, BlinkMacSystemFont, sans-serif"
      font-size="15" fill="#D8A54C">
      Wireless Camera Remote for iPhone
    </text>
    <text x="${leftCenterX}" y="415" text-anchor="middle"
      font-family="-apple-system, BlinkMacSystemFont, sans-serif"
      font-size="13" fill="#9CA3AF">
      Turn two devices into a
    </text>
    <text x="${leftCenterX}" y="433" text-anchor="middle"
      font-family="-apple-system, BlinkMacSystemFont, sans-serif"
      font-size="13" fill="#9CA3AF">
      remote camera system
    </text>
  </svg>`;

  const composites = [
    { input: icon, left: Math.round(leftCenterX - iconSize / 2), top: 170 },
    { input: Buffer.from(textSvg), left: 0, top: 0 },
  ];

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
    .jpeg({ quality: 95 })
    .toFile(path.join(PUBLIC, 'og-image.jpg'));

  console.log('Generated og-image.jpg');
}

generate().catch(console.error);
