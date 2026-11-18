'use client';

import { useState } from 'react';
import data from '@/data/review-trend.json';
import styles from './RatingsTrendChart.module.css';

interface Period {
  label: string;
  n: number;
  avg: number;
  written_n: number;
  written_avg: number | null;
  star_n: number;
  star_avg: number | null;
}

interface Year {
  year: number;
  n: number;
  mean: number;
  lo: number;
  hi: number;
  neg: number;
  mid: number;
  pos: number;
}

interface Review {
  date: string;
  rating: number;
}

const periods = data.periods as Period[];
const years = data.years as Year[];
const reviews = data.reviews as Review[];

const WIDTH = 720;
const LEFT = 40;
const RIGHT = 12;
const TOP = 24;
const PLOT_WIDTH = WIDTH - LEFT - RIGHT;

export default function RatingsTrendChart({ name }: { name: string }) {
  if (name === 'periods') return <PeriodsChart />;
  if (name === 'written-yearly') return <WrittenYearlyChart />;
  if (name === 'written-share') return <WrittenShareChart />;
  return null;
}

function stars(value: number | null): string {
  return value === null ? '–' : `${value.toFixed(2)}★`;
}

function Frame({
  title,
  legend,
  height,
  children,
  tooltip,
}: {
  title: string;
  legend: { label: string; className: string; round?: boolean }[];
  height: number;
  children: React.ReactNode;
  tooltip: { x: number; lines: string[] } | null;
}) {
  return (
    <figure className={styles.figure}>
      <figcaption className={styles.title}>{title}</figcaption>
      <div className={styles.legend}>
        {legend.map((item) => (
          <span key={item.label}>
            <span className={`${styles.swatch} ${item.className} ${item.round ? styles.round : ''}`} />
            {item.label}
          </span>
        ))}
      </div>
      <div className={styles.plot}>
        <svg viewBox={`0 0 ${WIDTH} ${height}`} role="img" aria-label={title}>
          {children}
        </svg>
        {tooltip && (
          <div
            className={styles.tooltip}
            style={{
              left: `${(tooltip.x / WIDTH) * 100}%`,
              transform: `translateX(${tooltip.x < WIDTH * 0.25 ? '-10%' : tooltip.x > WIDTH * 0.75 ? '-90%' : '-50%'})`,
            }}
            role="status"
          >
            {tooltip.lines.map((line, index) => (
              <div key={line} className={index === 0 ? styles.tooltipHead : undefined}>
                {line}
              </div>
            ))}
          </div>
        )}
      </div>
    </figure>
  );
}

function StarGrid({ y }: { y: (value: number) => number }) {
  return (
    <>
      {[1, 2, 3, 4, 5].map((value) => (
        <g key={value}>
          <line className={styles.grid} x1={LEFT} x2={WIDTH - RIGHT} y1={y(value)} y2={y(value)} />
          <text className={styles.tick} x={LEFT - 8} y={y(value)} dy="0.32em" textAnchor="end">
            {value}★
          </text>
        </g>
      ))}
    </>
  );
}

function PeriodsChart() {
  const [active, setActive] = useState<number | null>(null);
  const height = 330;
  const bottom = height - 50;
  const column = PLOT_WIDTH / periods.length;
  const x = (index: number) => LEFT + (index + 0.5) * column;
  const y = (value: number) => TOP + ((5 - value) / 4) * (bottom - TOP);
  const line = periods
    .map((period, index) => (index > 0 ? `${x(index)},${y(period.avg)}` : null))
    .filter(Boolean)
    .join(' ');

  const tooltip =
    active === null
      ? null
      : {
          x: x(active),
          lines: [
            periods[active].label,
            `All ratings: ${stars(periods[active].avg)} (${periods[active].n})`,
            `Written reviews: ${stars(periods[active].written_avg)} (${periods[active].written_n})`,
            periods[active].star_avg === null
              ? `Star-only: too few to split (${periods[active].star_n})`
              : `Star-only: ${stars(periods[active].star_avg)} (${periods[active].star_n})`,
          ],
        };

  return (
    <Frame
      title="All ratings, average stars per period"
      legend={[
        { label: 'all ratings', className: styles.blue, round: true },
        { label: 'written reviews, same period', className: styles.orange, round: true },
      ]}
      height={height}
      tooltip={tooltip}
    >
      <StarGrid y={y} />
      <line
        className={styles.divider}
        x1={LEFT + column}
        x2={LEFT + column}
        y1={TOP}
        y2={bottom}
      />
      {active !== null && (
        <rect className={styles.highlight} x={x(active) - column / 2} y={TOP} width={column} height={bottom - TOP} />
      )}
      <polyline className={styles.line} points={line} />
      {periods.map((period, index) => (
        <g key={period.label}>
          {period.written_avg !== null && (
            <circle className={styles.orangeDot} cx={x(index)} cy={y(period.written_avg)} r={active === index ? 6 : 5} />
          )}
          <circle className={styles.blueDot} cx={x(index)} cy={y(period.avg)} r={active === index ? 7.5 : 6} />
          <text className={styles.value} x={x(index)} y={y(period.avg) - 13} textAnchor="middle">
            {period.avg.toFixed(2)}
          </text>
          <text className={styles.tick} x={x(index)} y={height - 30} textAnchor="middle">
            {period.label}
          </text>
          <text className={styles.tick} x={x(index)} y={height - 14} textAnchor="middle">
            {period.n} ratings
          </text>
          <rect
            className={styles.hit}
            x={x(index) - column / 2}
            y={TOP}
            width={column}
            height={bottom - TOP}
            onMouseEnter={() => setActive(index)}
            onMouseLeave={() => setActive(null)}
            onClick={() => setActive(index)}
          />
        </g>
      ))}
    </Frame>
  );
}

function yearScale(bottom: number) {
  const first = years[0].year;
  const column = PLOT_WIDTH / years.length;
  const x = (year: number) => LEFT + (year - first + 0.5) * column;
  const y = (value: number) => TOP + ((5 - value) / 4) * (bottom - TOP);
  return { first, column, x, y };
}

/** Deterministic spread in [-0.5, 0.5); integer math so server and client render identically. */
function jitter(seed: number): number {
  return ((seed * 7919) % 101) / 101 - 0.5;
}

function WrittenYearlyChart() {
  const [active, setActive] = useState<number | null>(null);
  const height = 320;
  const bottom = height - 32;
  const { column, x, y } = yearScale(bottom);
  const bandTop = years.map((item) => `${x(item.year)},${y(item.hi)}`).join(' ');
  const bandBottom = [...years].reverse().map((item) => `${x(item.year)},${y(item.lo)}`).join(' ');
  const mean = years.map((item) => `${x(item.year)},${y(item.mean)}`).join(' ');
  const activeYear = active === null ? null : years[active];

  const tooltip =
    activeYear === null
      ? null
      : {
          x: x(activeYear.year),
          lines: [
            String(activeYear.year),
            `Average: ${stars(activeYear.mean)}`,
            `95% band: ${activeYear.lo.toFixed(1)}–${activeYear.hi.toFixed(1)}★`,
            `${activeYear.n} written reviews`,
          ],
        };

  return (
    <Frame
      title="Written reviews, average stars per year"
      legend={[
        { label: 'yearly average', className: styles.blue, round: true },
        { label: '95% confidence band', className: styles.band },
        { label: 'one review', className: styles.grey, round: true },
      ]}
      height={height}
      tooltip={tooltip}
    >
      <StarGrid y={y} />
      <polygon className={styles.bandFill} points={`${bandTop} ${bandBottom}`} />
      {reviews.map((review, index) => {
        const year = Number(review.date.slice(0, 4));
        const month = Number(review.date.slice(5, 7));
        const isActive = activeYear !== null && activeYear.year === year;
        return (
          <circle
            key={`${review.date}-${index}`}
            className={isActive ? styles.reviewDotActive : styles.reviewDot}
            cx={x(year) + ((month - 6.5) / 12) * column * 0.8}
            cy={y(review.rating) + jitter(index + 1) * 12}
            r={isActive ? 4 : 3}
          />
        );
      })}
      <polyline className={styles.line} points={mean} />
      {years.map((item, index) => (
        <g key={item.year}>
          <circle className={styles.blueDot} cx={x(item.year)} cy={y(item.mean)} r={active === index ? 6.5 : 4.5} />
          <text className={styles.tick} x={x(item.year)} y={height - 10} textAnchor="middle">
            {`'${String(item.year).slice(2)}`}
          </text>
          <rect
            className={styles.hit}
            x={x(item.year) - column / 2}
            y={TOP}
            width={column}
            height={bottom - TOP}
            onMouseEnter={() => setActive(index)}
            onMouseLeave={() => setActive(null)}
            onClick={() => setActive(index)}
          />
        </g>
      ))}
    </Frame>
  );
}

function WrittenShareChart() {
  const [active, setActive] = useState<number | null>(null);
  const height = 270;
  const middle = (height - 24) / 2 + 4;
  const span = middle - TOP;
  const { column, x } = yearScale(height);
  const barWidth = column * 0.55;
  const activeYear = active === null ? null : years[active];

  const tooltip =
    activeYear === null
      ? null
      : {
          x: x(activeYear.year),
          lines: [
            String(activeYear.year),
            `4–5★: ${activeYear.pos} (${Math.round((activeYear.pos / activeYear.n) * 100)}%)`,
            `3★: ${activeYear.mid}`,
            `1–2★: ${activeYear.neg} (${Math.round((activeYear.neg / activeYear.n) * 100)}%)`,
          ],
        };

  return (
    <Frame
      title="Written reviews, positive vs negative share"
      legend={[
        { label: '4–5★ (up)', className: styles.blue },
        { label: '1–2★ (down)', className: styles.red },
        { label: '3★ in the tooltip', className: styles.none },
      ]}
      height={height}
      tooltip={tooltip}
    >
      {[50, 100].flatMap((percent) =>
        [1, -1].map((sign) => {
          const lineY = middle - sign * span * (percent / 100);
          return (
            <g key={`${percent}-${sign}`}>
              <line className={styles.grid} x1={LEFT} x2={WIDTH - RIGHT} y1={lineY} y2={lineY} />
              <text className={styles.tick} x={LEFT - 8} y={lineY} dy="0.32em" textAnchor="end">
                {percent}%
              </text>
            </g>
          );
        })
      )}
      <line className={styles.axis} x1={LEFT} x2={WIDTH - RIGHT} y1={middle} y2={middle} />
      {years.map((item, index) => {
        const positive = (item.pos / item.n) * span;
        const negative = (item.neg / item.n) * span;
        const dim = active !== null && active !== index;
        return (
          <g key={item.year} opacity={dim ? 0.45 : 1}>
            {positive > 0 && (
              <rect className={styles.posBar} x={x(item.year) - barWidth / 2} y={middle - 1 - positive} width={barWidth} height={positive} rx={3} />
            )}
            {negative > 0 && (
              <rect className={styles.negBar} x={x(item.year) - barWidth / 2} y={middle + 1} width={barWidth} height={negative} rx={3} />
            )}
            <text className={styles.tick} x={x(item.year)} y={height - 4} textAnchor="middle">
              {`'${String(item.year).slice(2)}`}
            </text>
            <rect
              className={styles.hit}
              x={x(item.year) - column / 2}
              y={TOP - 10}
              width={column}
              height={height - 40}
              onMouseEnter={() => setActive(index)}
              onMouseLeave={() => setActive(null)}
              onClick={() => setActive(index)}
            />
          </g>
        );
      })}
    </Frame>
  );
}
