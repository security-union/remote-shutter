import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/react';
import Home from '@/app/page';

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

jest.mock('../src/components/ScreenshotCarousel', () => {
  return function MockCarousel() {
    return <div data-testid="screenshot-carousel" />;
  };
});

describe('Home page', () => {
  it('renders the hero title', () => {
    render(<Home />);
    expect(
      screen.getByText('Turn two iPhones into a remote camera.')
    ).toBeInTheDocument();
  });

  it('renders the App Store badge', () => {
    render(<Home />);
    const badge = screen.getByAltText('Download on the App Store');
    expect(badge).toBeInTheDocument();
    expect(badge.closest('a')).toHaveAttribute(
      'href',
      expect.stringContaining('apps.apple.com')
    );
  });

  it('renders feature tiles', () => {
    render(<Home />);
    expect(screen.getByText('Live preview')).toBeInTheDocument();
    expect(screen.getByText('Photos & video')).toBeInTheDocument();
    expect(screen.getByText('Full control')).toBeInTheDocument();
    expect(screen.getByText('No network, no account')).toBeInTheDocument();
  });

  it('renders how-it-works steps', () => {
    render(<Home />);
    expect(screen.getByText('Install on both devices')).toBeInTheDocument();
    expect(screen.getByText('Connect')).toBeInTheDocument();
    expect(screen.getByText('Pick camera & remote')).toBeInTheDocument();
    expect(screen.getByText('Shoot')).toBeInTheDocument();
  });

  it('renders the about section', () => {
    render(<Home />);
    expect(screen.getByText('What is Remote Shutter?')).toBeInTheDocument();
    expect(
      screen.getByText('group photo at the beach').closest('a')
    ).toHaveAttribute('href', '/blog/group-photos-everyone-in-the-shot');
  });

  it('renders the FAQ section', () => {
    render(<Home />);
    expect(
      screen.getByText('Frequently asked questions')
    ).toBeInTheDocument();
    expect(
      screen.getByText('Does Remote Shutter need Wi-Fi or an internet connection?')
    ).toBeInTheDocument();
    expect(
      screen.getByText('Is Remote Shutter free? Is there a subscription?')
    ).toBeInTheDocument();
  });

  it('links to the gear and blog pages', () => {
    render(<Home />);
    expect(screen.getByText('Field kit').closest('a')).toHaveAttribute(
      'href',
      '/gear'
    );
    // "Blog" also appears in the header nav — assert on all of them
    for (const el of screen.getAllByText('Blog')) {
      expect(el.closest('a')).toHaveAttribute('href', '/blog');
    }
  });
});
