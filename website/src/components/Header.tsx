import Link from 'next/link';
import styles from './Header.module.css';

export default function Header() {
  return (
    <header className={styles.header}>
      <nav className={styles.nav}>
        <Link href="/" className={styles.logo}>
          Remote Shutter
        </Link>
        <div className={styles.links}>
          <a href="#features">Features</a>
          <a href="#how-it-works">How It Works</a>
          <Link href="/blog">Blog</Link>
          <Link href="/privacy">Privacy</Link>
        </div>
      </nav>
    </header>
  );
}
