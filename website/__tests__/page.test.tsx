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
      screen.getByText('Turn Two iPhones Into a Remote Camera System')
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

  it('renders feature cards', () => {
    render(<Home />);
    expect(screen.getByText('Live Preview')).toBeInTheDocument();
    expect(screen.getByText('Remote Photo Capture')).toBeInTheDocument();
    expect(screen.getByText('Remote Video Recording')).toBeInTheDocument();
    expect(screen.getByText('Peer-to-Peer Connection')).toBeInTheDocument();
  });

  it('renders how-it-works steps', () => {
    render(<Home />);
    expect(screen.getByText('Install on Two Devices')).toBeInTheDocument();
    expect(screen.getByText('Connect')).toBeInTheDocument();
    expect(screen.getByText('Choose Roles')).toBeInTheDocument();
    expect(screen.getByText('Shoot')).toBeInTheDocument();
  });
});
