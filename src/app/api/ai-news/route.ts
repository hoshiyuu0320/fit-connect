// app/api/ai-news/route.ts
import { NextRequest, NextResponse } from 'next/server';
import Parser from 'rss-parser';

interface NewsItem {
  title: string;
  link: string;
  source: string;
  publishedAt: string;
  snippet: string;
}

const RSS_FEEDS = [
  {
    url: 'https://news.google.com/rss/search?q=AI+driven+development+OR+AI+coding+OR+LLM+programming+OR+AI+software+engineering&hl=ja&gl=JP&ceid=JP:ja',
    name: 'Google News - AI開発',
    filtered: false,
  },
  {
    url: 'https://news.google.com/rss/search?q=generative+AI+developer+tools+OR+GitHub+Copilot+OR+Claude+Code+OR+AI+agent&hl=en&gl=US&ceid=US:en',
    name: 'Google News - AI Dev Tools EN',
    filtered: false,
  },
  {
    url: 'https://zenn.dev/feed?topic=ai',
    name: 'Zenn AI',
    filtered: false,
  },
  {
    url: 'https://b.hatena.ne.jp/hotentry/it.rss',
    name: 'はてなブックマーク IT',
    filtered: true,
  },
];

const AI_KEYWORDS = [
  'AI',
  '人工知能',
  'LLM',
  'GPT',
  'Claude',
  'Copilot',
  '生成AI',
  'ChatGPT',
  '機械学習',
  'GitHub Copilot',
  'AI開発',
  'AIエージェント',
  'Cursor',
  'Gemini',
  'OpenAI',
  'Anthropic',
];

function stripHtmlTags(html: string): string {
  return html.replace(/<[^>]*>/g, '');
}

function isAiRelated(title: string, description: string): boolean {
  const text = `${title} ${description}`.toLowerCase();
  return AI_KEYWORDS.some((keyword) => text.includes(keyword.toLowerCase()));
}

function isWithin24Hours(dateString: string | undefined): boolean {
  if (!dateString) return false;
  const publishedDate = new Date(dateString);
  if (isNaN(publishedDate.getTime())) return false;
  const now = new Date();
  const diff = now.getTime() - publishedDate.getTime();
  return diff <= 24 * 60 * 60 * 1000;
}

export async function GET(_request: NextRequest) {
  const parser = new Parser();
  const allItems: NewsItem[] = [];

  const feedPromises = RSS_FEEDS.map(async (feed) => {
    try {
      const parsedFeed = await parser.parseURL(feed.url);
      const items: NewsItem[] = [];

      for (const item of parsedFeed.items) {
        const title = item.title ?? '';
        const link = item.link ?? '';
        const pubDate = item.pubDate ?? item.isoDate;
        const rawDescription = item.contentSnippet ?? item.content ?? item.summary ?? '';
        const description = stripHtmlTags(rawDescription);

        if (!isWithin24Hours(pubDate)) continue;

        if (feed.filtered && !isAiRelated(title, description)) continue;

        items.push({
          title: stripHtmlTags(title),
          link,
          source: feed.name,
          publishedAt: pubDate ? new Date(pubDate).toISOString() : new Date().toISOString(),
          snippet: description.slice(0, 200),
        });
      }

      return items;
    } catch (error) {
      console.error(`Failed to fetch feed: ${feed.name}`, error);
      return [];
    }
  });

  const results = await Promise.allSettled(feedPromises);

  for (const result of results) {
    if (result.status === 'fulfilled') {
      allItems.push(...result.value);
    }
  }

  allItems.sort(
    (a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime()
  );

  const topItems = allItems.slice(0, 30);

  return NextResponse.json(
    { status: 'ok', items: topItems, count: topItems.length },
    {
      headers: {
        'Cache-Control': 's-maxage=3600, stale-while-revalidate',
      },
    }
  );
}
