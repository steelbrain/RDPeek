import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // English lives at the root: "/" shows the "en" page, and "/en" goes to "/".
  async rewrites() {
    return [{ source: "/", destination: "/en" }];
  },
  async redirects() {
    return [{ source: "/en", destination: "/", permanent: true }];
  },
};

export default nextConfig;
