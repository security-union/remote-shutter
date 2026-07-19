import type { Metadata } from 'next';
import Image from 'next/image';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import AmazonLink from '@/components/AmazonLink';
import { GEAR_SECTIONS, pickFirst, type GearItem } from '@/lib/gear';
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

// The three category picks, framed as one working setup.
const RIG_ROLES: Record<string, string> = {
  tripods: 'The stand',
  mounts: 'The clamp',
  lenses: 'The glass',
};

const RIG_PICKS = GEAR_SECTIONS.flatMap((section) => {
  const pick = section.items.find((item) => item.pick);
  return pick ? [{ role: RIG_ROLES[section.id] ?? section.title, item: pick }] : [];
});

function GearCard({ item }: { item: GearItem }) {
  return (
    <AmazonLink
      query={item.query}
      className={`${styles.card} ${item.pick ? styles.pickCard : ''}`}
    >
      {item.pick && <span className={styles.pick}>Our pick</span>}
      <span className={styles.photo}>
        <Image
          src={`${BASE_PATH}/gear/${item.image}`}
          alt={item.alt}
          width={600}
          height={600}
        />
      </span>
      <h3>{item.name}</h3>
      <span className={styles.tier}>{item.tier}</span>
      <span className={styles.why}>{item.why}</span>
      <span className={styles.buy}>See today&apos;s price&nbsp;↗</span>
    </AmazonLink>
  );
}

export default function Gear() {
  return (
    <>
      <Header />
      <main className={styles.main}>
        <section className={styles.hero}>
          <p className={styles.eyebrow}>Field kit</p>
          <h1 className={styles.title}>Set the phone down. Get in the shot.</h1>
          <p className={styles.lede}>
            The tripods, mounts, and lenses we use on real shoots.
          </p>
          <p className={styles.disclosure}>{DISCLOSURE}</p>
          <Image
            className={styles.heroShot}
            src={`${BASE_PATH}/screenshots/gear-hero-mac.jpg`}
            alt="Remote Shutter on a Mac directing a phone that a GorillaPod holds at a bird feeder"
            width={1920}
            height={1200}
            priority
          />
        </section>

        <nav className={styles.sectionNav} aria-label="Gear categories">
          {GEAR_SECTIONS.map((section) => (
            <a key={section.id} href={`#${section.id}`}>
              {section.title}
            </a>
          ))}
          <a href="#rig">Complete rig</a>
        </nav>

        <div className={styles.catalog}>
          {GEAR_SECTIONS.map((section) => (
            <section
              key={section.id}
              className={styles.section}
              aria-labelledby={section.id}
            >
              <h2 id={section.id}>{section.title}</h2>
              <p className={styles.sectionSub}>{section.sub}</p>
              <ul className={styles.quickGuide}>
                {pickFirst(section.items).map((item) => (
                  <li key={item.name}>
                    <span>{item.bestFor}</span>
                    <AmazonLink query={item.query}>{item.name}&nbsp;↗</AmazonLink>
                  </li>
                ))}
              </ul>
              <div className={styles.cards}>
                {pickFirst(section.items).map((item) => (
                  <GearCard key={item.name} item={item} />
                ))}
              </div>
            </section>
          ))}

          <section id="rig" className={styles.rig} aria-labelledby="rig-title">
            <h2 id="rig-title">The complete rig</h2>
            <p className={styles.sectionSub}>
              Our three picks, one setup — the stand, the clamp, and the glass.
            </p>
            <div className={styles.rigItems}>
              {RIG_PICKS.map(({ role, item }) => (
                <AmazonLink
                  key={item.name}
                  query={item.query}
                  className={styles.rigItem}
                >
                  <span className={styles.rigRole}>{role}</span>
                  <span className={styles.rigPhoto}>
                    <Image
                      src={`${BASE_PATH}/gear/${item.image}`}
                      alt={item.alt}
                      width={300}
                      height={300}
                    />
                  </span>
                  <h3>{item.name}</h3>
                  <span className={styles.rigBuy}>
                    See today&apos;s price&nbsp;↗
                  </span>
                </AmazonLink>
              ))}
            </div>
          </section>

          <section className={styles.works} aria-labelledby="works-title">
            <p className={styles.eyebrow} id="works-title">
              Works with the app
            </p>
            <div className={styles.worksGrid}>
              <div>
                <h3>Frame from the remote</h3>
                <p>The live preview shows what the mounted phone sees.</p>
              </div>
              <div>
                <h3>Trigger from your wrist</h3>
                <p>Fire the shutter from your Apple Watch.</p>
              </div>
              <div>
                <h3>Direct from the Mac</h3>
                <p>The big screen becomes the director&apos;s monitor.</p>
              </div>
            </div>
          </section>
        </div>
      </main>
      <Footer />
    </>
  );
}
