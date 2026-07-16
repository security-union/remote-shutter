'use client';

import { useEffect, useState } from 'react';
import { AMAZON_TAG_WEB, AMAZON_TAG_APP } from '@/lib/gear';

/**
 * Buy link that attributes the click to the right Amazon Associates
 * tracking ID: visitors arriving from the app carry ?src=app, everyone
 * else counts as web. Renders the web tag on the server so the static
 * export is correct without JS.
 */
export default function AmazonLink({
  query,
  className,
  children,
}: {
  query: string;
  className?: string;
  children: React.ReactNode;
}) {
  const [tag, setTag] = useState(AMAZON_TAG_WEB);

  useEffect(() => {
    if (new URLSearchParams(window.location.search).get('src') === 'app') {
      setTag(AMAZON_TAG_APP);
    }
  }, []);

  const href = `https://www.amazon.com/s?k=${encodeURIComponent(query)}&tag=${tag}`;

  return (
    <a
      href={href}
      className={className}
      target="_blank"
      rel="noopener noreferrer sponsored"
    >
      {children}
    </a>
  );
}
