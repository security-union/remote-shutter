import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/react';
import Privacy from '@/app/privacy/page';

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

describe('Privacy page', () => {
  it('renders the privacy policy heading', () => {
    render(<Privacy />);
    expect(
      screen.getByRole('heading', { level: 1, name: 'Privacy Policy' })
    ).toBeInTheDocument();
  });

  it('states no personal data is collected', () => {
    render(<Privacy />);
    expect(screen.getByText('Data Collection')).toBeInTheDocument();
    expect(screen.getByText(/collect, store, or transmit/)).toBeInTheDocument();
  });
});
