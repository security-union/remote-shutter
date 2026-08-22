import Link from 'next/link';
import Image from 'next/image';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import ScreenshotCarousel from '@/components/ScreenshotCarousel';
import JsonLd from '@/components/JsonLd';
import { SITE_URL, BASE_PATH, APP_STORE_URL } from '@/lib/constants';
import styles from './page.module.css';

const websiteSchema = {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  name: 'Remote Shutter',
  url: SITE_URL,
};

const appSchema = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'Remote Shutter',
  operatingSystem: 'iOS',
  applicationCategory: 'PhotographyApplication',
  description:
    'Turn two Apple devices into a wireless remote-controlled camera system. One device is the camera, the other is the remote control with live preview.',
  url: APP_STORE_URL,
  image: `${SITE_URL}/app-icon.png`,
  offers: {
    '@type': 'Offer',
    price: '0',
    priceCurrency: 'USD',
  },
};

const FAQ = [
  {
    q: 'Does Remote Shutter need Wi-Fi or an internet connection?',
    a: 'No. The two devices connect directly to each other over peer-to-peer Wi-Fi — no router, no cellular signal, no account. It works at a beach, on a trail, or in a basement with zero bars. If both devices are on the same Wi-Fi network, that works too.',
  },
  {
    q: 'Which devices can I use?',
    a: 'Any two Apple devices: iPhone, iPad, Apple Watch, or an Apple-silicon Mac. One acts as the camera (iPhone or iPad), the other as the remote with a live preview — a spare iPhone becomes a wireless camera, or an iPad or Mac becomes a big director’s monitor.',
  },
  {
    q: 'Can I record with multiple iPhones at the same time?',
    a: 'Yes — Multicam. One iPhone acts as the director and connects up to four iPhones as cameras. You see every angle live in a grid, and one shutter fires photos or video on all of them at the same instant. The clips collect back to the director, time-aligned, so you can cut between angles in any editor. Two cameras are free; Pro unlocks four.',
  },
  {
    q: 'How far away does the remote work?',
    a: 'About 50 feet (15 m) with line of sight when the devices connect directly. On a shared Wi-Fi network, range is whatever the network covers.',
  },
  {
    q: 'Can I record video remotely, not just photos?',
    a: 'Yes. You can start and stop video recording from the remote device, watching the live preview the whole time.',
  },
  {
    q: 'Is Remote Shutter free? Is there a subscription?',
    a: 'The app is a free download with no account and no subscription. Live preview and remote photo capture work for free; one-time purchases unlock video recording and the full feature set.',
  },
  {
    q: 'Where do my photos and videos go?',
    a: 'They save to the camera device’s photo library and never leave your devices. Nothing is uploaded to any server.',
  },
];

const faqSchema = {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  mainEntity: FAQ.map((f) => ({
    '@type': 'Question',
    name: f.q,
    acceptedAnswer: { '@type': 'Answer', text: f.a },
  })),
};

const howToSchema = {
  '@context': 'https://schema.org',
  '@type': 'HowTo',
  name: 'How to use one iPhone as a remote camera for another',
  description:
    'Turn two Apple devices into a wireless camera system with a live-preview remote.',
  tool: [{ '@type': 'HowToTool', name: 'Two Apple devices with Remote Shutter installed' }],
  step: [
    {
      '@type': 'HowToStep',
      name: 'Install on both devices',
      text: 'Install Remote Shutter on both Apple devices — the camera and the remote.',
    },
    {
      '@type': 'HowToStep',
      name: 'Connect',
      text: 'Open the app on both devices; they discover each other and connect directly, peer to peer.',
    },
    {
      '@type': 'HowToStep',
      name: 'Pick camera & remote',
      text: 'Choose which device is the camera and which is the remote with live preview.',
    },
    {
      '@type': 'HowToStep',
      name: 'Shoot',
      text: 'Frame the shot on the live preview, then capture photos or record video from the remote.',
    },
  ],
};

export default function Home() {
  return (
    <>
      <JsonLd data={websiteSchema} />
      <JsonLd data={appSchema} />
      <JsonLd data={faqSchema} />
      <JsonLd data={howToSchema} />
      <Header />
      <main className={styles.main}>
        <section className={styles.hero}>
          <Image
            src={`${BASE_PATH}/app-icon.png`}
            alt="Remote Shutter app icon"
            width={120}
            height={120}
            className={styles.appIcon}
            priority
          />
          <h1 className={styles.title}>
            Turn two iPhones into a remote camera.
          </h1>
          <p className={styles.subtitle}>
            One is the camera. The other is the remote — with live preview.
          </p>
          <div className={styles.cta}>
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
            >
              <Image
                src={`${BASE_PATH}/apple_app_store_badge.svg`}
                alt="Download on the App Store"
                width={200}
                height={67}
                priority
              />
            </a>
          </div>
        </section>

        <section className={styles.screenshots} id="screenshots">
          <ScreenshotCarousel />
        </section>

        <section className={styles.features} id="features">
          <div className={styles.featureGrid}>
            <div className={styles.feature}>
              <h3>Live preview</h3>
              <p>See what the camera sees</p>
            </div>
            <div className={styles.feature}>
              <h3>Photos &amp; video</h3>
              <p>Capture from the remote</p>
            </div>
            <div className={styles.feature}>
              <h3>Full control</h3>
              <p>Flash, lenses, front or back</p>
            </div>
            <div className={styles.feature}>
              <h3>No network, no account</h3>
              <p>Devices connect directly</p>
            </div>
          </div>
        </section>

        <section className={styles.howItWorks} id="how-it-works">
          <h2 className={styles.sectionTitle}>How it works</h2>
          <ol className={styles.steps}>
            <li>
              <span className={styles.stepNumber}>1</span>
              Install on both devices
            </li>
            <li>
              <span className={styles.stepNumber}>2</span>
              Connect
            </li>
            <li>
              <span className={styles.stepNumber}>3</span>
              Pick camera &amp; remote
            </li>
            <li>
              <span className={styles.stepNumber}>4</span>
              Shoot
            </li>
          </ol>
        </section>

        <section className={styles.about} id="about">
          <h2 className={styles.sectionTitle}>What is Remote Shutter?</h2>
          <p>
            Remote Shutter turns any two Apple devices into a wireless camera
            system. One device — an iPhone or iPad — is the camera. The other —
            an iPhone, iPad, Apple Watch, or Apple-silicon Mac — is the remote,
            with a full live preview of what the camera sees plus controls for
            the shutter, video recording, lenses, flash, and front or back
            camera.
          </p>
          <p>
            The devices connect directly to each other, peer to peer: no Wi-Fi
            network, no cellular signal, no account, and nothing uploaded to any
            server. That makes it work anywhere — a{' '}
            <Link href="/blog/group-photos-everyone-in-the-shot">
              group photo at the beach
            </Link>
            , a{' '}
            <Link href="/blog/use-old-iphone-as-remote-camera">
              spare iPhone watching the backyard
            </Link>
            , or an{' '}
            <Link href="/blog/iphone-as-second-camera-mac-monitor">
              overhead video rig monitored from an iPad or Mac
            </Link>
            . Range is about 50 feet line of sight, or your whole network when
            both devices share Wi-Fi.
          </p>
        </section>

        <section className={styles.faq} id="faq">
          <h2 className={styles.sectionTitle}>Frequently asked questions</h2>
          {FAQ.map((f) => (
            <div key={f.q} className={styles.faqItem}>
              <h3>{f.q}</h3>
              <p>{f.a}</p>
            </div>
          ))}
        </section>

        <section className={styles.more}>
          <Link href="/gear" className={styles.moreCard}>
            <h3>Field kit</h3>
            <p>Tripods, mounts &amp; lenses we shoot with →</p>
          </Link>
          <Link href="/blog" className={styles.moreCard}>
            <h3>Blog</h3>
            <p>Tips &amp; updates →</p>
          </Link>
        </section>
      </main>
      <Footer />
    </>
  );
}
