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

export default function Home() {
  return (
    <>
      <JsonLd data={websiteSchema} />
      <JsonLd data={appSchema} />
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
            Turn Two iPhones Into a Remote Camera System
          </h1>
          <p className={styles.subtitle}>
            Remote Shutter connects two Apple devices wirelessly — one becomes
            the camera, the other your remote control with a live preview.
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
          <h2 className={styles.sectionTitle}>Features</h2>
          <div className={styles.featureGrid}>
            <div className={styles.feature}>
              <h3>Live Preview</h3>
              <p>
                See exactly what the camera sees on your monitor device in real
                time with low-latency streaming.
              </p>
            </div>
            <div className={styles.feature}>
              <h3>Remote Photo Capture</h3>
              <p>
                Take photos remotely — perfect for group shots, wildlife
                photography, or hard-to-reach angles.
              </p>
            </div>
            <div className={styles.feature}>
              <h3>Remote Video Recording</h3>
              <p>
                Start and stop video recording from your monitor device with
                full control over the process.
              </p>
            </div>
            <div className={styles.feature}>
              <h3>Peer-to-Peer Connection</h3>
              <p>
                No internet required. Devices connect directly via
                peer-to-peer networking — works anywhere.
              </p>
            </div>
            <div className={styles.feature}>
              <h3>Flash &amp; Camera Control</h3>
              <p>
                Toggle flash, switch between front and rear cameras, and change
                lenses — all from the remote.
              </p>
            </div>
            <div className={styles.feature}>
              <h3>No Account Needed</h3>
              <p>
                Just install on two devices and connect. No sign-ups, no cloud,
                no fuss.
              </p>
            </div>
          </div>
        </section>

        <section className={styles.howItWorks} id="how-it-works">
          <h2 className={styles.sectionTitle}>How It Works</h2>
          <div className={styles.steps}>
            <div className={styles.step}>
              <span className={styles.stepNumber}>1</span>
              <h3>Install on Two Devices</h3>
              <p>Download Remote Shutter on both Apple devices.</p>
            </div>
            <div className={styles.step}>
              <span className={styles.stepNumber}>2</span>
              <h3>Connect</h3>
              <p>
                The devices discover each other automatically via peer-to-peer
                networking.
              </p>
            </div>
            <div className={styles.step}>
              <span className={styles.stepNumber}>3</span>
              <h3>Choose Roles</h3>
              <p>
                Pick which device is the camera and which is the monitor/remote
                control.
              </p>
            </div>
            <div className={styles.step}>
              <span className={styles.stepNumber}>4</span>
              <h3>Shoot</h3>
              <p>
                See the live preview and capture photos or videos remotely.
              </p>
            </div>
          </div>
        </section>

        <section className={styles.blog} id="blog">
          <h2 className={styles.sectionTitle}>Blog</h2>
          <p className={styles.blogIntro}>
            Tips, updates, and photography ideas.{' '}
            <Link href="/blog">Read all posts</Link>
          </p>
        </section>
      </main>
      <Footer />
    </>
  );
}
