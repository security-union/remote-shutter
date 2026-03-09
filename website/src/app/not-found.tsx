import Link from 'next/link';
import Header from '@/components/Header';
import Footer from '@/components/Footer';

export default function NotFound() {
  return (
    <>
      <Header />
      <main
        style={{
          maxWidth: 720,
          margin: '0 auto',
          padding: '6rem 1.5rem',
          textAlign: 'center',
        }}
      >
        <h1 style={{ fontSize: '3rem', marginBottom: '1rem' }}>404</h1>
        <p style={{ color: 'var(--muted)', marginBottom: '2rem' }}>
          This page could not be found.
        </p>
        <Link
          href="/"
          style={{
            background: 'var(--accent)',
            color: '#000',
            padding: '0.75rem 1.5rem',
            borderRadius: '8px',
            fontWeight: 600,
          }}
        >
          Back to Home
        </Link>
      </main>
      <Footer />
    </>
  );
}
