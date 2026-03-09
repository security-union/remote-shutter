import Link from 'next/link';
import type { Metadata } from 'next';
import { getAllPosts } from '@/lib/blog';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import styles from './blog.module.css';

export const metadata: Metadata = {
  title: 'Blog',
  description:
    'Tips, updates, and photography ideas from the Remote Shutter team.',
  alternates: {
    canonical: '/blog',
  },
  openGraph: {
    title: 'Blog | Remote Shutter',
    description:
      'Tips, updates, and photography ideas from the Remote Shutter team.',
    type: 'website',
    siteName: 'Remote Shutter',
    locale: 'en_US',
    images: [{ url: '/og-image.jpg', width: 1200, height: 630 }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Blog | Remote Shutter',
    description:
      'Tips, updates, and photography ideas from the Remote Shutter team.',
    images: ['/og-image.jpg'],
  },
};

export default function BlogIndex() {
  const posts = getAllPosts();

  return (
    <>
      <Header />
      <main className={styles.main}>
        <h1 className={styles.title}>Blog</h1>
        {posts.length === 0 ? (
          <p className={styles.empty}>Posts coming soon. Stay tuned!</p>
        ) : (
          <ul className={styles.postList}>
            {posts.map((post) => (
              <li key={post.slug} className={styles.postItem}>
                <Link href={`/blog/${post.slug}`}>
                  <h2>{post.title}</h2>
                  <span className={styles.meta}>
                    <span>By {post.author}</span>
                    <time dateTime={post.date}>{post.date}</time>
                  </span>
                  <p className={styles.description}>{post.description}</p>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </main>
      <Footer />
    </>
  );
}
