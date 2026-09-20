const DEFAULT_URL = "https://opencode.ai/docs/cli";
const DEFAULT_TIMEOUT_MS = 10000;
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;
const MAX_LINKS_REPORTED = 20;
const UA = "nayla-simple-web-crawler/1.0 (+https://github.com/Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot)";

function usage() {
  return `usage: node scripts/simple-web-crawler.js [url] [timeoutMs]

Fetches a single URL, extracts page metadata and links, and prints JSON.
Defaults: url=${DEFAULT_URL} timeoutMs=${DEFAULT_TIMEOUT_MS}
Response bodies are capped at ${MAX_RESPONSE_BYTES} bytes.`;
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

function isTagDelimiter(ch) {
  return ch === undefined || /[\s/>]/.test(ch);
}

function findTagBoundary(html, from) {
  // Returns the index just past the closing '>' of the tag, respecting quoted
  // attribute values so that a '>' inside quotes does not end the tag early.
  const len = html.length;
  let i = from + 1;
  let quote = null;
  while (i < len) {
    const ch = html[i];
    if (quote !== null) {
      if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === ">") {
      return i + 1;
    }
    i += 1;
  }
  return len;
}

function attributeValue(tag, name) {
  // Extract a named attribute value from a single tag string. The negative
  // lookbehind stops this from matching attribute names like `data-href` or
  // `ng-href` while still allowing `xlink:href`.
  const pattern = new RegExp(`(?<![\\w-])${name}\\s*=\\s*(["'])(.*?)\\1`, "i");
  const match = tag.match(pattern);
  return match ? match[2] : null;
}

function scanTags(html, name) {
  const tags = [];
  const startPattern = new RegExp(`<${name}(?=[\\s>])`, "gi");
  let match;
  while ((match = startPattern.exec(html)) !== null) {
    const tagEnd = findTagBoundary(html, match.index);
    tags.push(html.slice(match.index, tagEnd));
  }
  return tags;
}

function scanAnchors(html) {
  const anchors = [];
  let index = 0;
  while (index < html.length) {
    const open = html.indexOf("<a", index);
    if (open === -1) break;
    if (!isTagDelimiter(html[open + 2])) {
      index = open + 2;
      continue;
    }
    const tagEnd = findTagBoundary(html, open);
    const afterTag = html.slice(tagEnd);
    const closeMatch = /<\/a[\s>]/i.exec(afterTag);
    if (!closeMatch) break;
    const textEnd = tagEnd + closeMatch.index;
    anchors.push({ tag: html.slice(open, tagEnd), text: html.slice(tagEnd, textEnd) });
    index = textEnd + closeMatch[0].length;
  }
  return anchors;
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
  const openMatch = /<title(?=[\s>])/i.exec(html);
  if (!openMatch) return null;
  const tagEnd = findTagBoundary(html, openMatch.index);
  const closeMatch = /<\/title(?=[\s>])/i.exec(html.slice(tagEnd));
  if (!closeMatch) return null;
  return cleanText(html.slice(tagEnd, tagEnd + closeMatch.index));
}

function metaContent(html, name) {
  for (const tag of scanTags(html, "meta")) {
    const attrName = attributeValue(tag, "name") || attributeValue(tag, "property");
    if (attrName && attrName.toLowerCase() === name.toLowerCase()) {
      const value = attributeValue(tag, "content");
      if (value) return cleanText(value);
    }
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
  for (const tag of scanTags(html, "html")) {
    const lang = attributeValue(tag, "lang");
    if (lang) {
      meta.lang = lang;
      break;
    }
  }
  return meta;
}

function extractLinks(html, base) {
  const links = [];
  const seen = new Set();
  for (const anchor of scanAnchors(html)) {
    const rawHref = attributeValue(anchor.tag, "href");
    if (!rawHref) continue;
    const trimmed = rawHref.trim();
    if (!trimmed || /^(mailto:|tel:|javascript:|data:|#)/i.test(trimmed)) continue;
    let absolute;
    try {
      absolute = new URL(trimmed, base).toString();
    } catch {
      continue;
    }
    if (absolute.startsWith("http:") || absolute.startsWith("https:")) {
      const key = absolute.replace(/\/$/, "");
      if (!seen.has(key)) {
        seen.add(key);
        links.push({ href: absolute, text: cleanText(anchor.text).slice(0, 120) });
      }
    }
    if (links.length >= MAX_LINKS_REPORTED) break;
  }
  return links;
}

function resolveBase(html, url) {
  for (const tag of scanTags(html, "base")) {
    const href = attributeValue(tag, "href");
    if (href) {
      try {
        return new URL(href, url).toString();
      } catch {
        /* fall back to page URL */
      }
    }
  }
  return url;
}

async function readBodyWithLimit(response, maxBytes) {
  // Streams the response so the caller can bound memory usage; Node's global
  // fetch (undici) enforces no response size limit by default.
  if (!response.body) {
    return { text: "", bytes: 0 };
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let total = 0;
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel("response exceeds maximum size").catch(() => {});
      throw new Error(`response body exceeds ${maxBytes} bytes for ${response.url}`);
    }
    text += decoder.decode(value, { stream: true });
  }
  text += decoder.decode();
  return { text, bytes: total };
}

async function crawl(urlString, timeoutMs, maxBytes = MAX_RESPONSE_BYTES) {
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
  let bytes;
  try {
    response = await fetch(url.toString(), {
      headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" },
      redirect: "follow",
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText} for ${url}`);
    }
    ({ text: body, bytes } = await readBodyWithLimit(response, maxBytes));
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
    bytes,
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

module.exports = { crawl, DEFAULT_URL, DEFAULT_TIMEOUT_MS, MAX_RESPONSE_BYTES };