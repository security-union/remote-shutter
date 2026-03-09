import type { Metadata } from 'next';
import { SITE_URL } from '@/lib/constants';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: 'Remote Shutter - Turn Two iPhones Into a Remote Camera System',
    template: '%s | Remote Shutter',
  },
  description:
    'Remote Shutter turns two Apple devices into a wireless remote-controlled camera system. Use one device as the camera and the other as the monitor and remote control.',
  keywords: [
    'remote shutter',
    'iPhone remote camera',
    'remote camera control',
    'wireless shutter',
    'iOS camera remote',
    'phone camera remote control',
    'dual phone camera',
    'remote photo',
    'remote video recording',
    'peer to peer camera',
    'camera remote app',
    'group photo remote',
  ],
  alternates: {
    canonical: '/',
  },
  openGraph: {
    title: 'Remote Shutter - Wireless Camera Remote for iPhone',
    description:
      'Turn two Apple devices into a remote-controlled camera system. One device is the camera, the other is the remote control.',
    type: 'website',
    locale: 'en_US',
    siteName: 'Remote Shutter',
    url: SITE_URL,
    images: [
      {
        url: '/og-image.jpg',
        width: 1200,
        height: 630,
        alt: 'Remote Shutter - Wireless Camera Remote for iPhone',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Remote Shutter - Wireless Camera Remote for iPhone',
    description:
      'Turn two Apple devices into a remote-controlled camera system.',
    images: ['/og-image.jpg'],
  },
  robots: {
    index: true,
    follow: true,
  },
  other: {
    'apple-mobile-web-app-capable': 'yes',
    'apple-mobile-web-app-status-bar-style': 'black-translucent',
    'theme-color': '#000000',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
