'use client';

import { useState, useCallback, useEffect } from 'react';
import Image from 'next/image';
import { BASE_PATH } from '@/lib/constants';
import styles from './ScreenshotCarousel.module.css';

const screenshots = [
  { src: `${BASE_PATH}/screenshots/0_APP_IPHONE_67_0.png`, alt: 'Remote Shutter - Device scanning' },
  { src: `${BASE_PATH}/screenshots/1_APP_IPHONE_67_1.png`, alt: 'Remote Shutter - Role selection' },
  { src: `${BASE_PATH}/screenshots/2_APP_IPHONE_67_2.png`, alt: 'Remote Shutter - Camera view' },
  { src: `${BASE_PATH}/screenshots/3_APP_IPHONE_67_3.png`, alt: 'Remote Shutter - Monitor view' },
];

export default function ScreenshotCarousel() {
  const [current, setCurrent] = useState(0);
  const [lightbox, setLightbox] = useState<number | null>(null);

  const goTo = useCallback((index: number) => {
    setCurrent((index + screenshots.length) % screenshots.length);
  }, []);

  const lightboxGoTo = useCallback((index: number) => {
    setLightbox((index + screenshots.length) % screenshots.length);
  }, []);

  // Auto-advance mobile carousel (pause when lightbox open)
  useEffect(() => {
    if (lightbox !== null) return;
    const timer = setInterval(() => {
      setCurrent((prev) => (prev + 1) % screenshots.length);
    }, 4000);
    return () => clearInterval(timer);
  }, [lightbox]);

  // Close lightbox on Escape, navigate with arrows
  useEffect(() => {
    if (lightbox === null) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setLightbox(null);
      if (e.key === 'ArrowLeft') lightboxGoTo(lightbox - 1);
      if (e.key === 'ArrowRight') lightboxGoTo(lightbox + 1);
    };
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', handler);
    return () => {
      document.body.style.overflow = '';
      window.removeEventListener('keydown', handler);
    };
  }, [lightbox, lightboxGoTo]);

  return (
    <>
      {/* Desktop: all screenshots side by side */}
      <div className={styles.grid}>
        {screenshots.map((shot, i) => (
          <button
            key={shot.src}
            className={styles.gridItem}
            onClick={() => setLightbox(i)}
            aria-label={`View ${shot.alt}`}
          >
            <Image
              src={shot.src}
              alt={shot.alt}
              width={166}
              height={360}
              className={styles.image}
              priority={i === 0}
            />
          </button>
        ))}
      </div>

      {/* Mobile: carousel */}
      <div className={styles.carousel}>
        <button
          className={styles.arrow}
          onClick={() => goTo(current - 1)}
          aria-label="Previous screenshot"
        >
          &#8249;
        </button>

        <div className={styles.track} onClick={() => setLightbox(current)}>
          {screenshots.map((shot, i) => (
            <div
              key={shot.src}
              className={`${styles.slide} ${i === current ? styles.active : ''}`}
            >
              <Image
                src={shot.src}
                alt={shot.alt}
                width={180}
                height={390}
                className={styles.image}
              />
            </div>
          ))}
        </div>

        <button
          className={styles.arrow}
          onClick={() => goTo(current + 1)}
          aria-label="Next screenshot"
        >
          &#8250;
        </button>

        <div className={styles.dots}>
          {screenshots.map((_, i) => (
            <button
              key={i}
              className={`${styles.dot} ${i === current ? styles.activeDot : ''}`}
              onClick={() => goTo(i)}
              aria-label={`Go to screenshot ${i + 1}`}
            />
          ))}
        </div>
      </div>

      {/* Lightbox */}
      {lightbox !== null && (
        <div
          className={styles.lightbox}
          onClick={() => setLightbox(null)}
          role="dialog"
          aria-label="Screenshot viewer"
        >
          <div
            className={styles.lightboxContent}
            onClick={(e) => e.stopPropagation()}
          >
            <button
              className={styles.lightboxClose}
              onClick={() => setLightbox(null)}
              aria-label="Close"
            >
              &times;
            </button>

            <button
              className={styles.lightboxArrow}
              onClick={() => lightboxGoTo(lightbox - 1)}
              aria-label="Previous screenshot"
            >
              &#8249;
            </button>

            <div className={styles.lightboxImage}>
              <Image
                src={screenshots[lightbox].src}
                alt={screenshots[lightbox].alt}
                width={400}
                height={867}
                className={styles.lightboxImg}
                priority
              />
            </div>

            <button
              className={styles.lightboxArrow}
              onClick={() => lightboxGoTo(lightbox + 1)}
              aria-label="Next screenshot"
            >
              &#8250;
            </button>
          </div>

          <div className={styles.lightboxDots}>
            {screenshots.map((_, i) => (
              <button
                key={i}
                className={`${styles.dot} ${i === lightbox ? styles.activeDot : ''}`}
                onClick={(e) => {
                  e.stopPropagation();
                  setLightbox(i);
                }}
                aria-label={`Go to screenshot ${i + 1}`}
              />
            ))}
          </div>
        </div>
      )}
    </>
  );
}
