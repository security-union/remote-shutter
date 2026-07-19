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
