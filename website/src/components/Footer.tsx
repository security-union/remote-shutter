import Link from 'next/link';
import { GITHUB_URL } from '@/lib/constants';
import styles from './Footer.module.css';

export default function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.inner}>
        <p>&copy; {new Date().getFullYear()} Remote Shutter by Dario Lencina. All rights reserved.</p>
        <div className={styles.links}>
          <Link href="/privacy">Privacy Policy</Link>
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
        </div>
      </div>
    </footer>
  );
}
