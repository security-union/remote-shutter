/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  basePath: '/remote-shutter',
  images: {
    unoptimized: true,
  },
};

module.exports = nextConfig;
