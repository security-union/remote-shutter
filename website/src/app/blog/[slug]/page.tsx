import type { Metadata } from 'next';
import { getAllPostSlugs, getPost } from '@/lib/blog';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import JsonLd from '@/components/JsonLd';
import styles from './post.module.css';

interface Props {
  params: Promise<{ slug: string }>;
}

export function generateStaticParams() {
  return getAllPostSlugs().map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPost(slug);
  return {
    title: post.title,
    description: post.description,
    alternates: {
      canonical: `/blog/${slug}`,
    },
    openGraph: {
      title: post.title,
      description: post.description,
      type: 'article',
      publishedTime: post.date,
      siteName: 'Remote Shutter',
      locale: 'en_US',
      images: [{ url: '/og-image.jpg', width: 1200, height: 630 }],
    },
    twitter: {
      card: 'summary_large_image',
      title: post.title,
      description: post.description,
      images: ['/og-image.jpg'],
    },
  };
}

export default async function BlogPost({ params }: Props) {
  const { slug } = await params;
  const post = await getPost(slug);

  const articleSchema = {
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: post.title,
    description: post.description,
    datePublished: post.date,
    dateModified: post.date,
    author: {
      '@type': 'Person',
      name: post.author,
    },
    publisher: {
      '@type': 'Organization',
      name: 'Remote Shutter',
      logo: {
        '@type': 'ImageObject',
        url: 'https://security-union.github.io/remote-shutter/app-icon.png',
      },
    },
    mainEntityOfPage: {
      '@type': 'WebPage',
      '@id': `https://security-union.github.io/remote-shutter/blog/${slug}`,
    },
    image: 'https://security-union.github.io/remote-shutter/og-image.jpg',
  };

  const breadcrumbSchema = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      {
        '@type': 'ListItem',
        position: 1,
        name: 'Home',
        item: 'https://security-union.github.io/remote-shutter',
      },
      {
        '@type': 'ListItem',
        position: 2,
        name: 'Blog',
        item: 'https://security-union.github.io/remote-shutter/blog',
      },
      {
        '@type': 'ListItem',
        position: 3,
        name: post.title,
      },
    ],
  };

  return (
    <>
      <JsonLd data={articleSchema} />
      <JsonLd data={breadcrumbSchema} />
      <Header />
      <main className={styles.main}>
        <nav className={styles.breadcrumb} aria-label="Breadcrumb">
          <a href="/remote-shutter">Home</a>
          <span aria-hidden="true">/</span>
          <a href="/remote-shutter/blog">Blog</a>
          <span aria-hidden="true">/</span>
          <span>{post.title}</span>
        </nav>
        <article className={styles.article}>
          <header>
            <h1 className={styles.title}>{post.title}</h1>
            <div className={styles.meta}>
              <span className={styles.author}>By {post.author}</span>
              <time className={styles.date} dateTime={post.date}>
                {post.date}
              </time>
            </div>
          </header>
          <div
            className={styles.content}
            dangerouslySetInnerHTML={{ __html: post.contentHtml }}
          />
        </article>
      </main>
      <Footer />
    </>
  );
}
