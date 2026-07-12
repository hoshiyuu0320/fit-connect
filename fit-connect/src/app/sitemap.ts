import type { MetadataRoute } from 'next';
import { siteConfig } from '@/lib/siteConfig';

/** 公開ページのみを掲載する（認証後ページは robots.ts で disallow 済み） */
const PUBLIC_ROUTES: Array<{ path: string; priority: number }> = [
  { path: '', priority: 1.0 },
  { path: '/login', priority: 0.5 },
  { path: '/signup', priority: 0.8 },
  { path: '/terms', priority: 0.3 },
  { path: '/privacy', priority: 0.3 },
  { path: '/tokushoho', priority: 0.3 },
];

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();

  return PUBLIC_ROUTES.map(({ path, priority }) => ({
    url: `${siteConfig.url}${path}`,
    lastModified,
    changeFrequency: path === '' ? 'weekly' : 'monthly',
    priority,
  }));
}
