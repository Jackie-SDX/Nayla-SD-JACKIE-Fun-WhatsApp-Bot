const net = require("node:net");
const dns = require("node:dns");

const DEFAULT_URL = "https://opencode.ai/docs/cli";
const DEFAULT_TIMEOUT_MS = 10000;
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;
const MAX_LINKS_REPORTED = 20;
// Node's setTimeout() stores delays in a signed 32-bit int: anything larger
// fires after 1ms (TimeoutOverflowWarning), so a huge requested deadline would
// silently become an immediate abort. This is the largest delay that survives.
const MAX_TIMEOUT_MS = 2147483647;
// Match the redirect chain length Node's fetch already enforced (probe: the
// server observed 21 requests for a redirect loop, i.e. 20 hops followed).
const MAX_REDIRECTS = 20;
const UA = "nayla-simple-web-crawler/1.0 (+https://github.com/Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot)";

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
    const textEnd = closeMatch ? tagEnd + closeMatch.index : html.length;
    // An <a> cannot legally nest, so anchor text that contains another <a>
    // opening means this anchor is malformed/unclosed: the closing tag found
    // above actually belongs to a later anchor. Reusing it would drop that
    // later link and mislabel its text. Skip this anchor and resume scanning
    // at the nested opening instead of corrupting the rest of the page.
    const textWindow = closeMatch ? afterTag.slice(0, closeMatch.index) : afterTag;
    const nestedOpen = /<a(?=[\s>])/i.exec(textWindow);
    if (nestedOpen) {
      index = tagEnd + nestedOpen.index;
      continue;
    }
    if (!closeMatch) break;
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

function redactUrl(value) {
  // Any URL echoed in a message or in the report must never carry userinfo:
  // undici itself leaks it ("Request cannot be constructed from a URL that
  // includes credentials: http://user:pass@host"), so we pre-empt that path.
  try {
    const parsed = value instanceof URL ? value : new URL(String(value));
    parsed.username = "";
    parsed.password = "";
    return parsed.toString();
  } catch {
    return String(value).replace(/\/\/[^/@\s]*@/g, "//");
  }
}

function normalizeTimeout(timeoutMs) {
  const value = Number(timeoutMs);
  if (Number.isNaN(value)) throw new Error(`invalid timeout: ${timeoutMs}`);
  if (value <= 0) throw new Error(`invalid timeout: ${timeoutMs}`);
  if (!Number.isFinite(value)) return MAX_TIMEOUT_MS;
  return Math.min(Math.floor(value), MAX_TIMEOUT_MS);
}

function parseIPv4(address) {
  const parts = address.split(".");
  if (parts.length !== 4) return null;
  const bytes = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    const octet = Number(part);
    if (octet > 255) return null;
    bytes.push(octet);
  }
  return bytes;
}

function isBlockedIPv4(bytes) {
  const [a, b, c] = bytes;
  if (a === 0) return true; // 0.0.0.0/8 this-network
  if (a === 10) return true; // 10.0.0.0/8 private
  if (a === 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
  if (a === 127) return true; // 127.0.0.0/8 loopback
  if (a === 169 && b === 254) return true; // 169.254.0.0/16 link-local + cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12 private
  if (a === 192 && b === 0 && c === 0) return true; // 192.0.0.0/24 IETF assignments
  if (a === 192 && b === 0 && c === 2) return true; // TEST-NET-1
  if (a === 192 && b === 168) return true; // 192.168.0.0/16 private
  if (a === 198 && (b === 18 || b === 19)) return true; // 198.18.0.0/15 benchmarking
  if (a === 198 && b === 51 && c === 100) return true; // TEST-NET-2
  if (a === 203 && b === 0 && c === 113) return true; // TEST-NET-3
  if (a >= 224) return true; // 224.0.0.0/4 multicast, 240.0.0.0/4 reserved, broadcast
  return false;
}

function expandIPv6(address) {
  let text = address;
  const zone = text.indexOf("%");
  if (zone !== -1) text = text.slice(0, zone);
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const toWords = (part) => {
    if (!part) return [];
    const words = [];
    for (const segment of part.split(":")) {
      if (segment.includes(".")) {
        const bytes = parseIPv4(segment);
        if (!bytes) return null;
        words.push((bytes[0] << 8) | bytes[1], (bytes[2] << 8) | bytes[3]);
        continue;
      }
      if (!/^[0-9a-f]{1,4}$/i.test(segment)) return null;
      words.push(parseInt(segment, 16));
    }
    return words;
  };
  const head = toWords(halves[0]);
  if (head === null) return null;
  if (halves.length === 1) return head.length === 8 ? head : null;
  const tail = toWords(halves[1]);
  if (tail === null) return null;
  const missing = 8 - head.length - tail.length;
  if (missing < 0) return null;
  const words = head.concat(new Array(missing).fill(0), tail);
  return words.length === 8 ? words : null;
}

function allZero(words, from, to) {
  for (let i = from; i <= to; i += 1) if (words[i] !== 0) return false;
  return true;
}

function embeddedIPv4(words) {
  // IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::a.b.c.d) carry the IPv4
  // address in the final 32 bits.
  const mapped = allZero(words, 0, 4) && words[5] === 0xffff;
  const nat64 = words[0] === 0x0064 && words[1] === 0xff9b && allZero(words, 2, 5);
  if (mapped || nat64) return [words[6] >> 8, words[6] & 0xff, words[7] >> 8, words[7] & 0xff];
  // 6to4 (2002::/16) embeds the IPv4 address in bits 16..47.
  if (words[0] === 0x2002) return [words[1] >> 8, words[1] & 0xff, words[2] >> 8, words[2] & 0xff];
  return null;
}

function isBlockedIPv6(words) {
  if (allZero(words, 0, 6) && words[7] === 1) return true; // ::1 loopback
  if (allZero(words, 0, 7)) return true; // :: unspecified
  if ((words[0] & 0xfe00) === 0xfc00) return true; // fc00::/7 unique local
  if ((words[0] & 0xffc0) === 0xfe80) return true; // fe80::/10 link-local
  if ((words[0] & 0xff00) === 0xff00) return true; // ff00::/8 multicast
  if (words[0] === 0x0100 && allZero(words, 1, 3)) return true; // 100::/64 discard-only
  // IETF protocol assignments (2001::/23, includes Teredo and other transition
  // mechanisms) and the documentation ranges (2001:db8::/32, 3fff::/20) are
  // special-purpose and not globally reachable, mirroring the IPv4 TEST-NET
  // blocks above.
  if (words[0] === 0x2001 && (words[1] & 0xfe00) === 0) return true;
  if (words[0] === 0x2001 && words[1] === 0x0db8) return true;
  if (words[0] === 0x3fff && (words[1] & 0xf000) === 0) return true;
  const embedded = embeddedIPv4(words);
  // Transition addresses (IPv4-mapped, NAT64, 6to4) inherit the IPv4 policy so
  // an internal IPv4 target cannot be smuggled through an IPv6 literal.
  return embedded === null ? false : isBlockedIPv4(embedded);
}

function isLoopbackAddress(address) {
  const text = String(address).split("%")[0];
  if (net.isIPv4(text)) {
    const bytes = parseIPv4(text);
    return bytes !== null && bytes[0] === 127;
  }
  if (net.isIPv6(text)) {
    const words = expandIPv6(text);
    if (words === null) return false;
    if (allZero(words, 0, 6) && words[7] === 1) return true; // ::1
    // Only the IPv4-mapped form addresses this host's loopback directly. 6to4
    // and NAT64 embed an IPv4 address too, but they route elsewhere, so they
    // must not qualify for the loopback opt-out.
    const mapped = allZero(words, 0, 4) && words[5] === 0xffff;
    return mapped && (words[6] >> 8) === 127;
  }
  return false;
}

function isBlockedAddress(address) {
  // Fail closed: anything we cannot positively classify as a public unicast
  // address is treated as a blocked destination.
  const text = String(address).split("%")[0];
  if (net.isIPv4(text)) {
    const bytes = parseIPv4(text);
    return bytes === null ? true : isBlockedIPv4(bytes);
  }
  if (net.isIPv6(text)) {
    const words = expandIPv6(text);
    return words === null ? true : isBlockedIPv6(words);
  }
  return true;
}

function isRedirectStatus(status) {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function cancelBody(response) {
  // Redirect responses are never read; cancel them so a redirect chain cannot
  // pin sockets or accumulate unread bodies across hops.
  if (!response.body) return Promise.resolve();
  return response.body.cancel().catch(() => {});
}

async function assertDestinationAllowed(target, signal, allowLoopback) {
  // Destination policy for the initial URL and for every redirect hop.
  //
  // Residual risk (documented deliberately): name resolution is validated
  // before the request, but Node's global fetch re-resolves on its own, so a
  // hostile authoritative DNS server could still rebind between the check and
  // the connection (TOCTOU). Closing that gap needs a custom undici dispatcher
  // bound to a pinned address; undici is not a public Node module
  // (ERR_MODULE_NOT_FOUND), so that would mean a new runtime dependency. This
  // pre-check therefore mitigates the common SSRF cases (direct private/metadata
  // targets and hostnames such as localtest.me that resolve internally) without
  // adding supply-chain surface; the residual rebinding window is a known,
  // stated limitation rather than an unnoticed one.
  if (!/^https?:$/.test(target.protocol)) {
    throw new Error(`unsupported protocol: ${target.protocol}`);
  }
  if (target.username || target.password) {
    throw new Error(`URLs with embedded credentials are not supported: ${redactUrl(target)}`);
  }
  const hostname = target.hostname.replace(/^\[|\]$/g, "");
  const addresses = [];
  if (net.isIP(hostname)) {
    addresses.push(hostname);
  } else {
    let resolved;
    try {
      resolved = await dns.promises.lookup(hostname, { all: true });
    } catch (error) {
      throw new Error(`could not resolve host ${hostname}: ${error.code || error.message}`);
    }
    if (!Array.isArray(resolved) || resolved.length === 0) {
      throw new Error(`could not resolve host ${hostname}`);
    }
    addresses.push(...resolved.map((entry) => entry.address));
  }
  for (const address of addresses) {
    if (!isBlockedAddress(address)) continue;
    if (allowLoopback && isLoopbackAddress(address)) continue;
    throw new Error(
      `blocked destination ${address} for ${redactUrl(target)}: non-public address`,
    );
  }
  if (signal.aborted) throw new Error("aborted");
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

// The deadline signal cannot interrupt name resolution (dns.lookup takes no
// AbortSignal), so race the destination check against it: a stalled resolver
// must still honour the caller's deadline instead of hanging forever.
function raceDeadline(promise, signal, makeError) {
  if (signal.aborted) return Promise.reject(makeError());
  return new Promise((resolve, reject) => {
    const onAbort = () => reject(makeError());
    signal.addEventListener("abort", onAbort, { once: true });
    const settle = (fn) => (value) => {
      signal.removeEventListener("abort", onAbort);
      fn(value);
    };
    promise.then(settle(resolve), settle(reject));
  });
}

async function crawl(urlString, timeoutMs, maxBytes = MAX_RESPONSE_BYTES, options = {}) {
  // Narrow opt-out for deterministic local fixtures (every fixture binds
  // 127.0.0.1). It only ever relaxes the loopback rule: RFC1918, link-local
  // and cloud-metadata destinations stay blocked unconditionally.
  const allowLoopback = options.allowLoopback === true;
  let initialUrl;
  try {
    initialUrl = new URL(urlString);
  } catch {
    throw new Error(`invalid URL: ${redactUrl(urlString)}`);
  }
  if (!/^https?:$/.test(initialUrl.protocol)) {
    throw new Error(`unsupported protocol: ${initialUrl.protocol}`);
  }
  const budget = normalizeTimeout(timeoutMs);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), budget);
  const startedAt = Date.now();
  const deadlineError = () => new Error(`timed out after ${budget}ms fetching ${redactUrl(initialUrl)}`);
  let url = initialUrl;
  let response;
  let body;
  let bytes;
  try {
    await raceDeadline(
      assertDestinationAllowed(url, controller.signal, allowLoopback),
      controller.signal,
      deadlineError,
    );
    let hops = 0;
    for (;;) {
      response = await fetch(url.toString(), {
        headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" },
        redirect: "manual",
        signal: controller.signal,
      });
      if (!isRedirectStatus(response.status)) break;
      const location = response.headers.get("location");
      let next = null;
      if (location) {
        try {
          next = new URL(location, url);
        } catch {
          next = null;
        }
      }
      // A redirect with no usable Location is returned as-is so the existing
      // !response.ok path reports "HTTP 302 ..." exactly as before.
      if (!next) {
        await cancelBody(response);
        break;
      }
      await cancelBody(response);
      if (hops >= MAX_REDIRECTS) {
        throw new Error(
          `too many redirects (maximum ${MAX_REDIRECTS}) fetching ${redactUrl(initialUrl)}`,
        );
      }
      if (!/^https?:$/.test(next.protocol)) {
        throw new Error(`unsupported redirect protocol: ${next.protocol}`);
      }
      // Re-validate every hop: a public URL may redirect onto an internal one.
      await raceDeadline(
        assertDestinationAllowed(next, controller.signal, allowLoopback),
        controller.signal,
        deadlineError,
      );
      url = next;
      hops += 1;
    }
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText} for ${redactUrl(initialUrl)}`);
    }
    ({ text: body, bytes } = await readBodyWithLimit(response, maxBytes));
  } catch (error) {
    if (error.name === "AbortError" || controller.signal.aborted) {
      throw deadlineError();
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
    fetchedFrom: redactUrl(initialUrl),
    finalUrl: redactUrl(response.url || url.toString()),
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

module.exports = {
  crawl,
  DEFAULT_URL,
  DEFAULT_TIMEOUT_MS,
  MAX_RESPONSE_BYTES,
  MAX_REDIRECTS,
  MAX_TIMEOUT_MS,
  isBlockedAddress,
  isLoopbackAddress,
  normalizeTimeout,
  redactUrl,
};