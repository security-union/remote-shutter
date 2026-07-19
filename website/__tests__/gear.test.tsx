import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/react';
import Gear from '@/app/gear/page';
import { GEAR_SECTIONS, AMAZON_TAG_WEB, pickFirst } from '@/lib/gear';

jest.mock('next/link', () => {
  return function MockLink({
    children,
    href,
  }: {
    children: React.ReactNode;
    href: string;
  }) {
    return <a href={href}>{children}</a>;
  };
});

jest.mock('next/image', () => {
  return function MockImage({ priority, ...props }: Record<string, unknown>) {
    void priority;
    // eslint-disable-next-line @next/next/no-img-element, jsx-a11y/alt-text
    return <img {...props} />;
  };
});

const itemCount = GEAR_SECTIONS.reduce((n, s) => n + s.items.length, 0);
const pickCount = GEAR_SECTIONS.filter((s) =>
  s.items.some((i) => i.pick)
).length;

describe('Gear page', () => {
  it('links every product to Amazon with the web tag and sponsored rel', () => {
    render(<Gear />);
    const amazonLinks = screen
      .getAllByRole('link')
      .filter((a) => (a as HTMLAnchorElement).href.includes('amazon.com'));

    // one card + one quick-guide chip per item, one rig card per section pick
    expect(amazonLinks).toHaveLength(itemCount * 2 + pickCount);
    for (const link of amazonLinks) {
      expect(link).toHaveAttribute(
        'href',
        expect.stringContaining(`tag=${AMAZON_TAG_WEB}`)
      );
      expect(link).toHaveAttribute('rel', expect.stringContaining('sponsored'));
    }
  });

  it('shows the verbatim Associates disclosure once, above all links', () => {
    render(<Gear />);
    const disclosures = screen.getAllByText(
      'As an Amazon Associate I earn from qualifying purchases.'
    );
    expect(disclosures).toHaveLength(1);
  });
});

describe('pickFirst', () => {
  it('moves the pick to the front and keeps the rest in author order', () => {
    for (const section of GEAR_SECTIONS) {
      const ordered = pickFirst(section.items);
      const pick = section.items.find((i) => i.pick);
      if (pick) {
        expect(ordered[0]).toBe(pick);
      }
      expect(ordered.filter((i) => !i.pick)).toEqual(
        section.items.filter((i) => !i.pick)
      );
      expect(ordered).toHaveLength(section.items.length);
    }
  });
});
