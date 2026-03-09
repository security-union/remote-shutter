import type { Metadata } from 'next';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import styles from './privacy.module.css';

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description:
    'Remote Shutter privacy policy. No personal data collected. Peer-to-peer only.',
  alternates: {
    canonical: '/privacy',
  },
  openGraph: {
    title: 'Privacy Policy | Remote Shutter',
    description:
      'Remote Shutter privacy policy. No personal data collected. Peer-to-peer only.',
    type: 'website',
    siteName: 'Remote Shutter',
    locale: 'en_US',
  },
};

export default function Privacy() {
  return (
    <>
      <Header />
      <main className={styles.main}>
        <h1>Privacy Policy</h1>

        <p>Last updated: March 2026</p>

        <h2>Overview</h2>
        <p>
          Remote Shutter is designed with privacy in mind. The app connects two
          devices directly via peer-to-peer networking. No data is sent to our
          servers because we don&apos;t have any.
        </p>

        <h2>Data Collection</h2>
        <p>
          Remote Shutter does <strong>not</strong> collect, store, or transmit
          any personal data. Photos and videos are saved only to the local
          device&apos;s camera roll.
        </p>

        <h2>Peer-to-Peer Communication</h2>
        <p>
          When two devices connect, they communicate directly over a local
          peer-to-peer connection (Apple MultipeerConnectivity). Camera frames
          and commands are transmitted directly between the paired devices and
          are never routed through external servers.
        </p>

        <h2>Third-Party Services</h2>
        <p>
          The app uses Google AdMob for advertising. AdMob may collect device
          identifiers and usage data in accordance with{' '}
          <a
            href="https://policies.google.com/privacy"
            target="_blank"
            rel="noopener noreferrer"
          >
            Google&apos;s Privacy Policy
          </a>
          . You can opt out of personalized ads through your device settings.
        </p>

        <h2>Contact</h2>
        <p>
          If you have questions about this privacy policy, please open an issue
          on our{' '}
          <a
            href="https://github.com/security-union/remote-shutter"
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub repository
          </a>
          .
        </p>
      </main>
      <Footer />
    </>
  );
}
