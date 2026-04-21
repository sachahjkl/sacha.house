import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import TurndownService from "turndown";

type Config = {
  HYGRAPH_API_ENDPOINT: string;
};

type HygraphPost = {
  slug: string;
  title: string;
  updatedAt: string;
  createdAt: string;
  publishedAt?: string | null;
  author?: { name?: string } | null;
  content: {
    html: string;
    text: string;
  };
};

type HygraphResponse = {
  data?: {
    posts?: HygraphPost[];
  };
  errors?: Array<{ message?: string }>;
};

const BLOG_ROOT = path.join(process.cwd(), "data", "blog");
const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });

function slugify(value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
  return slug || `post-${Date.now()}`;
}

function safeStem(value: string): string {
  return slugify(value.replace(/\.[^.]+$/, "")) || "image";
}

function extFromMime(mimeType: string | null): string {
  switch ((mimeType || "").split(";")[0]) {
    case "image/png":
      return ".png";
    case "image/jpeg":
      return ".jpg";
    case "image/webp":
      return ".webp";
    case "image/gif":
      return ".gif";
    case "image/svg+xml":
      return ".svg";
    default:
      return "";
  }
}

async function loadConfig(): Promise<Config> {
  const raw = await readFile(path.join(process.cwd(), "config.json"), "utf8");
  return JSON.parse(raw) as Config;
}

async function fetchPosts(endpoint: string): Promise<HygraphPost[]> {
  const query = `
    query GET_POSTS_FOR_MIGRATION {
      posts(orderBy: updatedAt_ASC, stage: DRAFT) {
        slug
        title
        updatedAt
        createdAt
        publishedAt
        author {
          name
        }
        content {
          html
          text
        }
      }
    }
  `;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  if (!response.ok) {
    throw new Error(`Hygraph request failed with ${response.status}`);
  }

  const payload = (await response.json()) as HygraphResponse;
  if (payload.errors?.length) {
    throw new Error(payload.errors.map((entry) => entry.message || "Unknown GraphQL error").join("\n"));
  }

  return payload.data?.posts || [];
}

async function downloadAndRewriteImages(slug: string, markdown: string): Promise<string> {
  const assetsDir = path.join(BLOG_ROOT, slug, "assets");
  await mkdir(assetsDir, { recursive: true });

  const matches = [...markdown.matchAll(/!\[([^\]]*)\]\((https?:\/\/[^\s)]+)(?:\s+"[^"]*")?\)/g)];
  const replacements = new Map<string, { original: string; replacement: string }>();

  for (const [index, match] of matches.entries()) {
    const [original, alt, url] = match;
    if (!original || !url || replacements.has(original)) continue;

    const response = await fetch(url);
    if (!response.ok) {
      console.warn(`Skipping image ${url}: ${response.status}`);
      continue;
    }

    const contentType = response.headers.get("content-type");
    const parsedUrl = new URL(url);
    const ext = path.extname(parsedUrl.pathname) || extFromMime(contentType) || ".png";
    const filename = `${safeStem(path.basename(parsedUrl.pathname) || `image-${index + 1}`)}-${index + 1}${ext}`;
    const filePath = path.join(assetsDir, filename);
    const buffer = Buffer.from(await response.arrayBuffer());
    await writeFile(filePath, buffer);

    const localUrl = `/media/blog/${slug}/assets/${filename}`;
    replacements.set(original, {
      original,
      replacement: `![${alt}](${localUrl})`,
    });
  }

  for (const { original, replacement } of replacements.values()) {
    markdown = markdown.split(original).join(replacement);
  }

  return markdown;
}

async function migratePost(post: HygraphPost): Promise<void> {
  const slug = slugify(post.slug || post.title);
  const postDir = path.join(BLOG_ROOT, slug);
  const metaPath = path.join(postDir, "post.json");
  const markdownPath = path.join(postDir, "content.md");

  await mkdir(postDir, { recursive: true });

  let markdown = turndown.turndown(post.content.html || "").trim();
  markdown = await downloadAndRewriteImages(slug, markdown);

  const metadata = {
    id: slug,
    slug,
    title: post.title,
    status: post.publishedAt ? "published" : "draft",
    publishedAt: post.publishedAt || "",
    updatedAt: post.updatedAt,
    createdAt: post.createdAt,
    author: post.author?.name || "",
  };

  await writeFile(metaPath, `${JSON.stringify(metadata, null, 2)}\n`, "utf8");
  await writeFile(markdownPath, `${markdown}\n`, "utf8");

  console.log(`Migrated ${slug}`);
}

async function main() {
  const config = await loadConfig();
  const posts = await fetchPosts(config.HYGRAPH_API_ENDPOINT);
  await mkdir(BLOG_ROOT, { recursive: true });

  for (const post of posts) {
    await migratePost(post);
  }

  console.log(`Done. Migrated ${posts.length} post(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
