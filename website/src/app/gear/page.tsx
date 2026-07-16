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

function RigDiagram() {
  return (
    <svg
      className={styles.rig}
      viewBox="0 0 420 300"
      role="img"
      aria-label="Diagram: a phone on a tripod acts as the camera, a second phone in hand is the remote, connected wirelessly."
    >
      {/* signal arcs */}
      <path className={styles.rigArc} d="M 150 96 Q 210 46 270 96" />
      <path
        className={styles.rigArc}
        d="M 158 122 Q 210 84 262 122"
        style={{ animationDelay: '0.25s' }}
      />

      {/* camera phone (portrait) on tripod */}
      <rect className={styles.rigDevice} x="96" y="112" width="52" height="92" rx="9" />
      <rect className={styles.rigScreen} x="104" y="122" width="36" height="64" rx="3" />
      <circle className={styles.rigGold} cx="122" cy="196" r="4" />
      {/* tripod: gold = the part this page sells */}
      <path className={styles.rigGold} d="M 122 204 L 122 224" />
      <path className={styles.rigGold} d="M 122 224 L 88 274" />
      <path className={styles.rigGold} d="M 122 224 L 156 274" />
      <path className={styles.rigGold} d="M 122 224 L 122 278" />

      {/* remote phone (portrait, held) */}
      <rect className={styles.rigDevice} x="272" y="118" width="46" height="82" rx="8" />
      <rect className={styles.rigScreen} x="279" y="127" width="32" height="56" rx="3" />
      <circle className={styles.rigStroke} cx="295" cy="192" r="3.5" />
      <path className={styles.rigStroke} d="M 318 176 q 14 2 14 16 q 0 14 -14 16" />

      {/* labels */}
      <text x="122" y="298" textAnchor="middle" className={styles.rigLabelGold}>
        The gear
      </text>
      <text x="122" y="102" textAnchor="middle" className={styles.rigLabel}>
        Camera
      </text>
      <text x="295" y="102" textAnchor="middle" className={styles.rigLabel}>
        Remote
      </text>
      <text x="210" y="36" textAnchor="middle" className={styles.rigLabel}>
        No internet needed
      </text>
    </svg>
  );
}

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
          <RigDiagram />
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
