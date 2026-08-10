import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { remark } from 'remark';
import html from 'remark-html';

const postsDirectory = path.join(process.cwd(), 'posts');

export interface PostMeta {
  slug: string;
  title: string;
  date: string;
  author: string;
  description: string;
}

export interface PostFaqEntry {
  q: string;
  a: string;
}

export interface Post extends PostMeta {
  contentHtml: string;
  faq: PostFaqEntry[];
}

export function getAllPostSlugs(): string[] {
  if (!fs.existsSync(postsDirectory)) return [];
  return fs
    .readdirSync(postsDirectory)
    .filter((file) => file.endsWith('.md'))
    .map((file) => file.replace(/\.md$/, ''));
}

export function getAllPosts(): PostMeta[] {
  const slugs = getAllPostSlugs();
  return slugs
    .map((slug) => getPostMeta(slug))
    .sort((a, b) => (a.date < b.date ? 1 : -1));
}

export function getPostMeta(slug: string): PostMeta {
  const fullPath = path.join(postsDirectory, `${slug}.md`);
  const fileContents = fs.readFileSync(fullPath, 'utf8');
  const { data } = matter(fileContents);
  return {
    slug,
    title: data.title ?? slug,
    date: data.date ?? '',
    author: data.author ?? 'Dario Lencina',
    description: data.description ?? '',
  };
}

export async function getPost(slug: string): Promise<Post> {
  const fullPath = path.join(postsDirectory, `${slug}.md`);
  const fileContents = fs.readFileSync(fullPath, 'utf8');
  const { data, content } = matter(fileContents);

  const processed = await remark().use(html).process(content);

  const faq: PostFaqEntry[] = Array.isArray(data.faq)
    ? data.faq
        .filter((f: unknown): f is { q: unknown; a: unknown } =>
          typeof f === 'object' && f !== null && 'q' in f && 'a' in f
        )
        .map((f) => ({ q: String(f.q), a: String(f.a) }))
    : [];

  return {
    slug,
    title: data.title ?? slug,
    date: data.date ?? '',
    author: data.author ?? 'Dario Lencina',
    description: data.description ?? '',
    contentHtml: processed.toString(),
    faq,
  };
}
