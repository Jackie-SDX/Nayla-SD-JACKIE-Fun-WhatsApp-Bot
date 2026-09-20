const http = require("node:http");
const assert = require("node:assert");

const { crawl, MAX_RESPONSE_BYTES } = require("./simple-web-crawler");

const fixture = `<!doctype html>
<html lang="en">
<head>
  <title>Fixture Page</title>
  <meta name="description" content="A tiny fixture page for the crawler test." />
</head>
<body>
  <h1>Hello</h1>
  <a href="/about">About us</a>
  <a href="https://opencode.ai/docs/zen/">Zen docs</a>
  <a href="mailto:test@example.com">mail link (ignored)</a>
  <a href="#section">anchor (ignored)</a>
</body>
</html>`;

function serverForFixture() {
  return http.createServer((req, res) => {
    if (req.url === "/") {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(fixture);
    } else if (req.url === "/about") {
      res.writeHead(200, { "content-type": "text/html" });
      res.end("<html><head><title>About</title></head><body>about</body></html>");
    } else if (req.url === "/tricky") {
      res.writeHead(200, { "content-type": "text/html" });
      res.end(`<!doctype html>
<html lang="en">
<head>
  <title>Price is 5 < 10 now</title>
  <meta name="description" content="Don't miss this deal — great stuff" />
  <base href="https://example.com/root/">
</head>
<body>
  <a data-href="/decoy">fake (ignored)</a>
  <a title="a > b" href="real-link">gt in attr</a>
  <a data-x="c" href="/real-link2">normal</a>
  <a href="/encoded">Encoded &amp; &lt;text&gt;</a>
  <a href="mailto:x@y.z">mail (ignored)</a>
  <a href="#frag">fragment (ignored)</a>
</body>
</html>`);
    } else {
      res.writeHead(404);
      res.end();
    }
  });
}

function serverThatHangs() {
  return http.createServer((req, res) => {
    setTimeout(() => {
      res.writeHead(200);
      res.end("slow");
    }, 5000);
  });
}

function serverSendingLargeBody(chunk, count) {
  return http.createServer((req, res) => {
    res.writeHead(200, { "content-type": "application/octet-stream" });
    for (let i = 0; i < count; i += 1) {
      res.write(chunk);
    }
    res.end();
  });
}

function listen(server) {
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => {
    const { port } = server.address();
    resolve(`http://127.0.0.1:${port}`);
  }));
}

function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

async function expectRejects(fn, pattern, label) {
  let threw = null;
  try {
    await fn();
  } catch (error) {
    threw = error;
  }
  assert.ok(threw, `expected rejection for ${label}`);
  assert.match(threw.message, pattern, `message mismatch for ${label}: ${threw.message}`);
}

async function main() {
  const fixtureServer = serverForFixture();
  const hangServer = serverThatHangs();
  const fixtureUrl = await listen(fixtureServer);
  const hangUrl = await listen(hangServer);
  const sizeServers = [];
  try {
    const result = await crawl(fixtureUrl, 3000);
    assert.strictEqual(result.status, 200);
    assert.strictEqual(result.title, "Fixture Page");
    assert.strictEqual(result.meta.description, "A tiny fixture page for the crawler test.");
    assert.strictEqual(result.meta.lang, "en");
    assert.ok(result.linkCount >= 2, `expected >=2 links, got ${result.linkCount}`);
    const hrefs = result.links.map((link) => link.href);
    assert.ok(hrefs.includes(`${fixtureUrl}/about`), "absolute link resolved");
    assert.ok(hrefs.includes("https://opencode.ai/docs/zen/"), "external link kept");
    assert.ok(!hrefs.some((href) => href.startsWith("mailto:") || href.endsWith("#section")), "ignored links present");
    assert.ok(result.bytes > 0, `expected positive byte count, got ${result.bytes}`);
    console.log(`PASS extraction: title=${JSON.stringify(result.title)} links=${result.linkCount} bytes=${result.bytes} durationMs=${result.durationMs}`);

    const tricky = await crawl(`${fixtureUrl}/tricky`, 3000);
    assert.strictEqual(tricky.title, "Price is 5 < 10 now", `title with '<' extracted, got ${JSON.stringify(tricky.title)}`);
    assert.strictEqual(tricky.meta.description, "Don't miss this deal — great stuff", "meta description with apostrophe kept whole");
    const trickyHrefs = tricky.links.map((link) => link.href);
    assert.ok(trickyHrefs.includes("https://example.com/root/real-link"), "link with '>' inside quoted attr kept and resolved against <base>");
    assert.ok(trickyHrefs.includes("https://example.com/real-link2"), "leading-slash href is an absolute-path reference (RFC 3986)");
    assert.strictEqual(
      tricky.links.find((link) => link.href === "https://example.com/encoded").text,
      "Encoded & <text>",
      "HTML entities in link text are decoded",
    );
    assert.ok(!trickyHrefs.some((href) => href.endsWith("/decoy")), "data-href must not be treated as a link");
    assert.ok(!trickyHrefs.some((href) => href.startsWith("mailto:") || href.endsWith("#frag")), "mailto: and fragment links still ignored");
    console.log("PASS tricky-html: attribute with '>', apostrophe meta, data-href, '<' in title");

    await expectRejects(
      () => crawl(hangUrl, 300),
      /timed out after 300ms/,
      "short timeout enforcement",
    );
    console.log("PASS timeout: request to a hanging server aborted within 300ms");

    await expectRejects(
      () => crawl("http://127.0.0.1:1/", 1000),
      /failed to parse url|fetch failed|ECONNREFUSED/i,
      "connection refused",
    );
    console.log("PASS connection-refused error path");

    await expectRejects(
      () => crawl("not a url", 1000),
      /invalid URL/,
      "invalid URL",
    );
    console.log("PASS invalid-URL error path");

    const chunk = Buffer.alloc(4096, "x");
    const smallServer = serverSendingLargeBody(chunk, 25);
    sizeServers.push(smallServer);
    const smallUrl = await listen(smallServer);
    const smallResult = await crawl(smallUrl, 3000, 1024 * 1024);
    assert.strictEqual(smallResult.bytes, chunk.length * 25, "bounded reader counts bytes exactly");
    console.log("PASS size-cap: under-limit body streamed and byte count correct");

    const largeServer = serverSendingLargeBody(chunk, 2000);
    sizeServers.push(largeServer);
    const largeUrl = await listen(largeServer);
    await expectRejects(
      () => crawl(largeUrl, 3000, 4096),
      /response body exceeds 4096 bytes/,
      "response size cap enforcement",
    );
    console.log("PASS size-cap: over-limit body rejected deterministically");

    const defaultCap = await crawl(smallUrl, 3000);
    assert.strictEqual(defaultCap.bytes, chunk.length * 25, "default cap path still streams the whole under-limit body");
    assert.ok(Number.isInteger(MAX_RESPONSE_BYTES) && MAX_RESPONSE_BYTES > 0, "MAX_RESPONSE_BYTES export is a positive integer");
    console.log("PASS size-cap: default MAX_RESPONSE_BYTES bound used");
  } finally {
    await close(fixtureServer);
    await close(hangServer);
    for (const server of sizeServers) await close(server);
  }
}

main()
  .then(() => {
    console.log("ALL TESTS PASSED");
    process.exitCode = 0;
  })
  .catch((error) => {
    console.error("TEST FAILURE:", error.message);
    process.exitCode = 1;
  });