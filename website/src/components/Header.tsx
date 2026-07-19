'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import styles from './Header.module.css';

// "/#…" not "#…": these sections only exist on the homepage, and a bare
// hash is a dead link from /gear, /blog, and /privacy.
const NAV_LINKS = [
  { href: '/#features', label: 'Features' },
  { href: '/#how-it-works', label: 'How It Works' },
  { href: '/gear', label: 'Gear' },
  { href: '/blog', label: 'Blog' },
  { href: '/privacy', label: 'Privacy' },
];

export default function Header() {
  const [open, setOpen] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', onKey);
    closeRef.current?.focus();
    return () => {
      document.body.style.overflow = '';
      window.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <header className={styles.header}>
      <nav className={styles.nav}>
        <Link href="/" className={styles.logo}>
          Remote Shutter
        </Link>

        <div className={styles.links}>
          {NAV_LINKS.map(({ href, label }) => (
            <Link key={href} href={href}>
              {label}
            </Link>
          ))}
        </div>

        <button
          type="button"
          className={styles.menuButton}
          onClick={() => setOpen(true)}
          aria-label="Open menu"
          aria-expanded={open}
          aria-controls="mobile-menu"
        >
          <span />
          <span />
          <span />
        </button>
      </nav>

      {open && (
        <div
          className={styles.overlay}
          onClick={() => setOpen(false)}
          aria-hidden="true"
        />
      )}

      <aside
        id="mobile-menu"
        className={`${styles.drawer} ${open ? styles.drawerOpen : ''}`}
        inert={open ? undefined : true}
      >
        <div className={styles.drawerHead}>
          <button
            type="button"
            ref={closeRef}
            className={styles.closeButton}
            onClick={() => setOpen(false)}
            aria-label="Close menu"
          >
            &times;
          </button>
        </div>
        <nav className={styles.drawerLinks} aria-label="Site menu">
          {NAV_LINKS.map(({ href, label }) => (
            <Link key={href} href={href} onClick={() => setOpen(false)}>
              {label}
            </Link>
          ))}
        </nav>
      </aside>
    </header>
  );
}
