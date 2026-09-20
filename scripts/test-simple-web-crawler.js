const http = require("node:http");
const assert = require("node:assert");

const { crawl } = require("./simple-web-crawler");

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
  try {
    const fixtureUrl = await listen(fixtureServer);
    const hangUrl = await listen(hangServer);

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
    console.log(`PASS extraction: title=${JSON.stringify(result.title)} links=${result.linkCount} bytes=${result.bytes} durationMs=${result.durationMs}`);

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
  } finally {
    await close(fixtureServer);
    await close(hangServer);
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