const DEFAULT_URL = "https://opencode.ai/docs/cli";
const DEFAULT_TIMEOUT_MS = 10000;
const MAX_LINKS_REPORTED = 20;
const UA = "nayla-simple-web-crawler/1.0 (+https://github.com/Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot)";

function usage() {
  return `usage: node scripts/simple-web-crawler.js [url] [timeoutMs]

Fetches a single URL, extracts page metadata and links, and prints JSON.
Defaults: url=${DEFAULT_URL} timeoutMs=${DEFAULT_TIMEOUT_MS}`;
}

function parseArgs(argv) {
  const args = { url: DEFAULT_URL, timeoutMs: DEFAULT_TIMEOUT_MS };
  for (const arg of argv.slice(2)) {
    if (/^\d+$/.test(arg)) {
      args.timeoutMs = Number(arg);
    } else {
      args.url = arg;
    }
  }
  return args;
}

function resolveBase(html, url) {
  const baseMatch = /<base[^>]*href=["']([^"']+)["']/i.exec(html);
  if (baseMatch) {
    try {
      return new URL(baseMatch[1], url).toString();
    } catch {
      /* fall back to page URL */
    }
  }
  return url;
}

function unquoteEntities(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&apos;/g, "'");
}

function cleanText(value) {
  return unquoteEntities(value).replace(/\s+/g, " ").trim();
}

function extractTitle(html) {
  const m = /<title[^>]*>([^<]*)<\/title>/i.exec(html);
  return m ? cleanText(m[1]) : null;
}

function metaContent(html, name) {
  const patterns = [
    new RegExp(`<meta[^>]+name=["']${name}["'][^>]+content=["']([^"']*)["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+property=["']${name}["'][^>]+content=["']([^"']*)["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+name=["']${name}["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+property=["']${name}["'][^>]*>`, "i"),
  ];
  for (const pattern of patterns) {
    const m = html.match(pattern);
    if (m) return cleanText(m[1]);
  }
  return null;
}

function extractMeta(html) {
  const meta = {};
  const names = ["description", "og:title", "og:description", "og:url", "twitter:card"];
  for (const name of names) {
    const value = metaContent(html, name);
    if (value) meta[name] = value;
  }
  const langMatch = /<html[^>]*\blang=["']([^"']+)["']/i.exec(html);
  if (langMatch) meta.lang = langMatch[1];
  return meta;
}

function extractLinks(html, base) {
  const links = [];
  const seen = new Set();
  const anchorPattern = /<a[^>]*\bhref=["']([^"']+)["'][^>]*>(.*?)<\/a>/gi;
  let match;
  while ((match = anchorPattern.exec(html)) !== null) {
    const rawHref = match[1].trim();
    if (!rawHref || /^(mailto:|tel:|javascript:|data:|#)/i.test(rawHref)) continue;
    let absolute;
    try {
      absolute = new URL(rawHref, base).toString();
    } catch {
      continue;
    }
    if (absolute.startsWith("http:") || absolute.startsWith("https:")) {
      const key = absolute.replace(/\/$/, "");
      if (!seen.has(key)) {
        seen.add(key);
        links.push({ href: absolute, text: cleanText(match[2]).slice(0, 120) });
      }
    }
  }
  return links.slice(0, MAX_LINKS_REPORTED);
}

async function crawl(urlString, timeoutMs) {
  let url;
  try {
    url = new URL(urlString);
  } catch {
    throw new Error(`invalid URL: ${urlString}`);
  }
  if (!/^https?:$/.test(url.protocol)) {
    throw new Error(`unsupported protocol: ${url.protocol}`);
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const startedAt = Date.now();
  let response;
  let body;
  try {
    response = await fetch(url.toString(), {
      headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" },
      redirect: "follow",
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText} for ${url}`);
    }
    body = await response.text();
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error(`timed out after ${timeoutMs}ms fetching ${url}`);
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }

  const base = resolveBase(body, response.url || url.toString());
  const links = extractLinks(body, base);
  const meta = extractMeta(body);
  return {
    fetchedAt: new Date().toISOString(),
    fetchedFrom: url.toString(),
    finalUrl: response.url || url.toString(),
    status: response.status,
    contentType: response.headers.get("content-type") || "",
    bytes: Buffer.byteLength(body),
    durationMs: Date.now() - startedAt,
    title: extractTitle(body),
    meta,
    linkCount: links.length,
    links,
  };
}

async function main() {
  const args = parseArgs(process.argv);
  try {
    const result = await crawl(args.url, args.timeoutMs);
    console.log(JSON.stringify(result, null, 2));
    return 0;
  } catch (error) {
    console.error(JSON.stringify({ error: error.message }, null, 2));
    return 1;
  }
}

if (typeof module !== "undefined" && require.main === module) {
  main().then((code) => {
    process.exitCode = code;
  });
}

module.exports = { crawl, DEFAULT_URL, DEFAULT_TIMEOUT_MS };