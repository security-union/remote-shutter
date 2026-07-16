import type { Metadata } from 'next';
import Image from 'next/image';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import AmazonLink from '@/components/AmazonLink';
import { GEAR_SECTIONS } from '@/lib/gear';
import { BASE_PATH, SITE_URL } from '@/lib/constants';
import styles from './page.module.css';

export const metadata: Metadata = {
  title: 'Recommended Gear',
  description:
    'Hand-picked tripods, mounts, and mobile lenses that pair with the Remote Shutter app: hold the camera phone steady, get everyone in the frame.',
  alternates: { canonical: `${SITE_URL}/gear` },
};

// Verbatim per the Associates Operating Agreement §5 — the only permitted
// variants are ones previously allowed under that agreement, and §6 makes a §5
// violation a material breach. Reword nothing here.
const DISCLOSURE = 'As an Amazon Associate I earn from qualifying purchases.';

export default function Gear() {
  return (
    <>
      <Header />
      <main className={styles.main}>
        <section className={styles.hero}>
          <div>
            <p className={styles.eyebrow}>Field kit</p>
            <h1 className={styles.title}>Set the phone down. Get in the shot.</h1>
            <p className={styles.lede}>
              Remote Shutter turns two devices into one camera — but the camera
              half still needs somewhere to stand. This is the gear we reach
              for on real shoots: tripods, mounts, and lenses that hold the
              frame steady while you step into it.
            </p>
            <p className={styles.disclosure}>{DISCLOSURE}</p>
          </div>
          <Image
            className={styles.heroShot}
            src={`${BASE_PATH}/screenshots/2_APP_IPHONE_67_2.png`}
            alt="Remote Shutter framing a group photo from a mounted phone"
            width={1290}
            height={2796}
            priority
          />
        </section>

        <div className={styles.catalog}>
          {GEAR_SECTIONS.map((section) => (
            <section
              key={section.id}
              className={styles.section}
              aria-labelledby={section.id}
            >
              <h2 id={section.id}>{section.title}</h2>
              <p className={styles.sectionSub}>{section.sub}</p>
              {/* Repeated per section, not just in the hero: the FTC asks that a
                  reader see the disclosure and the buy link at the same time, and
                  the hero scrolls away long before the last card. */}
              <p className={styles.disclosure}>{DISCLOSURE}</p>
              <div className={styles.cards}>
                {section.items.map((item) => (
                  <article key={item.name} className={styles.card}>
                    {item.pick && <span className={styles.pick}>Our pick</span>}
                    <div className={styles.photo}>
                      <Image
                        src={`${BASE_PATH}/gear/${item.image}`}
                        alt={item.alt}
                        width={600}
                        height={600}
                      />
                    </div>
                    <h3>{item.name}</h3>
                    <p className={styles.tier}>{item.tier}</p>
                    <p className={styles.why}>{item.why}</p>
                    <AmazonLink query={item.query} className={styles.buy}>
                      View on Amazon ↗
                    </AmazonLink>
                  </article>
                ))}
              </div>
            </section>
          ))}

          <section className={styles.works} aria-labelledby="works-title">
            <p className={styles.eyebrow} id="works-title">
              Works with the app
            </p>
            <div className={styles.worksGrid}>
              <div>
                <h3>Frame from the remote</h3>
                <p>
                  The live preview on your second device shows exactly what the
                  mounted phone sees — walk into the frame and check it from
                  where you stand.
                </p>
              </div>
              <div>
                <h3>Trigger from your wrist</h3>
                <p>
                  Phone on the tripod, hands free: fire the shutter from your
                  Apple Watch without touching either device.
                </p>
              </div>
              <div>
                <h3>Direct from the Mac</h3>
                <p>
                  Mount the phone, then use your Mac&apos;s big screen as the
                  director&apos;s monitor — the desk stands above were picked
                  for exactly this.
                </p>
              </div>
            </div>
          </section>
        </div>

        <p className={styles.footNote}>{DISCLOSURE}</p>
      </main>
      <Footer />
    </>
  );
}
