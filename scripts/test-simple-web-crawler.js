const http = require("node:http");
const assert = require("node:assert");
const { spawn } = require("node:child_process");

const {
  crawl,
  MAX_RESPONSE_BYTES,
  MAX_REDIRECTS,
  MAX_TIMEOUT_MS,
  isBlockedAddress,
  normalizeTimeout,
  redactUrl,
} = require("./simple-web-crawler");

// Deterministic fixtures always bind 127.0.0.1, so the crawler's SSRF guard is
// relaxed for loopback only inside the test harness. Non-loopback private and
// metadata destinations stay blocked and are asserted as such below.
const local = (url, timeout, maxBytes) => crawl(url, timeout, maxBytes, { allowLoopback: true });

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
    } else if (req.url.startsWith("/about")) {
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
  <a href="mailto:x@y.z">mail (ignored)</a>
  <a href="#frag">fragment (ignored)</a>
</body>
</html>`);
    } else if (req.url === "/malformed-anchor") {
      res.writeHead(200, { "content-type": "text/html" });
      res.end(`<!doctype html>
<html lang="en">
<head>
  <title>Malformed anchor</title>
</head>
<body>
  <a href="/first">first</a>
  <a href="/unclosed.jpg">never closed (an <a> cannot nest in HTML)
  <a href="/second">second</a>
  <a href="/third">third</a>
</body>
</html>`);
    } else if (/^\/chain\/\d+$/.test(req.url)) {
      const hop = Number(req.url.split("/")[2]);
      res.writeHead(302, { location: `/chain/${hop + 1}` });
      res.end();
    } else if (req.url === "/redirect-metadata") {
      res.writeHead(302, { location: "http://169.254.169.254/latest/meta-data/" });
      res.end();
    } else if (req.url === "/redirect-private") {
      res.writeHead(302, { location: "http://10.0.0.1/internal-admin" });
      res.end();
    } else if (req.url === "/rel-redirect") {
      res.writeHead(302, { location: "/about?from=redirect" });
      res.end();
    } else if (req.url === "/redirect-scheme") {
      res.writeHead(302, { location: "file:///etc/passwd" });
      res.end();
    } else if (req.url === "/no-location") {
      res.writeHead(302, { "content-type": "text/html" });
      res.end("<html><body>redirect without location</body></html>");
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
    const result = await local(fixtureUrl, 3000);
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

    const tricky = await local(`${fixtureUrl}/tricky`, 3000);
    assert.strictEqual(tricky.title, "Price is 5 < 10 now", `title with '<' extracted, got ${JSON.stringify(tricky.title)}`);
    assert.strictEqual(tricky.meta.description, "Don't miss this deal — great stuff", "meta description with apostrophe kept whole");
    const trickyHrefs = tricky.links.map((link) => link.href);
    assert.ok(trickyHrefs.includes("https://example.com/root/real-link"), "link with '>' inside quoted attr kept and resolved against <base>");
    assert.ok(trickyHrefs.includes("https://example.com/real-link2"), "leading-slash href is an absolute-path reference (RFC 3986)");
    assert.ok(!trickyHrefs.some((href) => href.endsWith("/decoy")), "data-href must not be treated as a link");
    assert.ok(!trickyHrefs.some((href) => href.startsWith("mailto:") || href.endsWith("#frag")), "mailto: and fragment links still ignored");
    console.log("PASS tricky-html: attribute with '>', apostrophe meta, data-href, '<' in title");

    const malformed = await local(`${fixtureUrl}/malformed-anchor`, 3000);
    const malformedHrefs = malformed.links.map((link) => link.href);
    assert.deepStrictEqual(
      malformedHrefs,
      [`${fixtureUrl}/first`, `${fixtureUrl}/second`, `${fixtureUrl}/third`],
      "a malformed/unclosed <a> must not swallow or drop the healthy links that follow it",
    );
    assert.strictEqual(
      malformed.links.find((link) => link.href.endsWith("/second")).text,
      "second",
      "anchor text after a malformed <a> survives intact",
    );
    console.log("PASS malformed-anchor resilience: unclosed <a> no longer corrupts later links");

    await expectRejects(
      () => local(hangUrl, 300),
      /timed out after 300ms/,
      "short timeout enforcement",
    );
    console.log("PASS timeout: request to a hanging server aborted within 300ms");

    await expectRejects(
      () => local("http://127.0.0.1:1/", 1000),
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
    const smallResult = await local(smallUrl, 3000, 1024 * 1024);
    assert.strictEqual(smallResult.bytes, chunk.length * 25, "bounded reader counts bytes exactly");
    console.log("PASS size-cap: under-limit body streamed and byte count correct");

    const largeServer = serverSendingLargeBody(chunk, 2000);
    sizeServers.push(largeServer);
    const largeUrl = await listen(largeServer);
    await expectRejects(
      () => local(largeUrl, 3000, 4096),
      /response body exceeds 4096 bytes/,
      "response size cap enforcement",
    );
    console.log("PASS size-cap: over-limit body rejected deterministically");

    const defaultCap = await local(smallUrl, 3000);
    assert.strictEqual(defaultCap.bytes, chunk.length * 25, "default cap path still streams the whole under-limit body");
    assert.ok(Number.isInteger(MAX_RESPONSE_BYTES) && MAX_RESPONSE_BYTES > 0, "MAX_RESPONSE_BYTES export is a positive integer");
    console.log("PASS size-cap: default MAX_RESPONSE_BYTES bound used");

    // --- SSRF: direct destination validation (issue #136) ---
    for (const blocked of [
      "http://169.254.169.254/latest/meta-data/",
      "http://10.0.0.1/internal-admin",
      "http://192.168.1.1/router",
      "http://172.16.0.1/",
      "http://100.64.0.1/",
      "http://127.0.0.1:1/",
      "http://[::1]:1/",
      "http://[fd00::1]/",
      "http://[fe80::1]/",
    ]) {
      await expectRejects(() => crawl(blocked, 1000), /blocked destination/i, `default-deny ${blocked}`);
    }
    console.log("PASS ssrf: loopback/RFC1918/link-local/CGNAT/metadata destinations denied by default");

    await expectRejects(
      () => crawl("http://localhost:1/", 1000),
      /blocked destination/i,
      "hostname resolving to loopback",
    );
    console.log("PASS ssrf: hostname resolving to loopback denied through the DNS path");

    const policyCases = [
      ["127.0.0.1", true], ["10.0.0.1", true], ["169.254.169.254", true],
      ["100.64.0.1", true], ["192.168.1.1", true], ["172.16.0.1", true],
      ["0.0.0.0", true], ["255.255.255.255", true], ["224.0.0.1", true],
      ["198.18.0.1", true], ["203.0.113.9", true],
      ["8.8.8.8", false], ["1.1.1.1", false], ["93.184.216.34", false],
      ["::1", true], ["::", true], ["fd00::1", true], ["fe80::1", true],
      ["ff02::1", true], ["::ffff:127.0.0.1", true], ["::ffff:7f00:1", true],
      ["::ffff:10.0.0.1", true], ["64:ff9b::a00:1", true], ["100::1", true],
      ["2606:4700:10::ac42:93f3", false], ["not-an-ip", true],
    ];
    for (const [address, blocked] of policyCases) {
      assert.strictEqual(isBlockedAddress(address), blocked, `isBlockedAddress(${address}) must be ${blocked}`);
    }
    console.log(`PASS ssrf policy: ${policyCases.length} address classifications incl. IPv4-mapped/NAT64`);

    // --- SSRF: per-hop redirect validation ---
    await expectRejects(
      () => local(`${fixtureUrl}/redirect-metadata`, 2000),
      /blocked destination 169\.254\.169\.254/,
      "redirect onto cloud metadata",
    );
    await expectRejects(
      () => local(`${fixtureUrl}/redirect-private`, 2000),
      /blocked destination 10\.0\.0\.1/,
      "redirect onto RFC1918 host",
    );
    console.log("PASS ssrf: every redirect hop is re-validated (public -> internal pivot blocked)");

    const rel = await local(`${fixtureUrl}/rel-redirect`, 2000);
    assert.strictEqual(rel.title, "About", "relative redirect target was fetched");
    assert.strictEqual(rel.finalUrl, `${fixtureUrl}/about?from=redirect`, "relative Location resolved with port and query preserved");
    console.log("PASS redirect: relative Location followed; finalUrl keeps host, port and query");

    await expectRejects(
      () => local(`${fixtureUrl}/redirect-scheme`, 2000),
      /unsupported redirect protocol: file:/,
      "non-HTTP redirect target",
    );
    console.log("PASS redirect: non-HTTP(S) redirect target rejected");

    await expectRejects(
      () => local(`${fixtureUrl}/no-location`, 2000),
      /HTTP 302/,
      "302 without a Location header",
    );
    console.log("PASS redirect: 302 without Location preserves the existing HTTP 302 error");

    await expectRejects(
      () => local(`${fixtureUrl}/chain/0`, 5000),
      /too many redirects/,
      "unbounded redirect chain",
    );
    console.log(`PASS redirect: chain capped at MAX_REDIRECTS=${MAX_REDIRECTS}`);

    // --- Deadlines: setTimeout 32-bit overflow + invalid budgets ---
    assert.strictEqual(normalizeTimeout(999999999999), MAX_TIMEOUT_MS, "huge deadline clamped to the 32-bit max");
    assert.strictEqual(normalizeTimeout(Infinity), MAX_TIMEOUT_MS, "infinite deadline clamped");
    assert.strictEqual(normalizeTimeout(1500.7), 1500, "fractional deadline floored");
    assert.strictEqual(normalizeTimeout(MAX_TIMEOUT_MS), MAX_TIMEOUT_MS, "max deadline passes through");
    for (const bad of [0, -1, -Infinity, NaN, "abc"]) {
      assert.throws(() => normalizeTimeout(bad), /invalid timeout/, `rejects timeout ${String(bad)}`);
    }
    await expectRejects(() => crawl(fixtureUrl, 0), /invalid timeout/, "zero deadline");
    console.log("PASS deadline: overflow-safe clamp (no 1ms TimeoutOverflowWarning abort) + invalid budgets rejected");

    // --- Diagnostics must never echo credentials ---
    let credentialError = null;
    try {
      await crawl("http://user:S3CR3TPASS@example.invalid/", 1000);
    } catch (error) {
      credentialError = error;
    }
    assert.ok(credentialError, "credential-bearing URL must be rejected");
    assert.match(credentialError.message, /credentials/i, `credential error message: ${credentialError.message}`);
    assert.ok(!credentialError.message.includes("S3CR3TPASS"), "password must never appear in diagnostics");
    assert.strictEqual(redactUrl("https://user:pw@example.com/x"), "https://example.com/x", "redactUrl strips userinfo");
    assert.strictEqual(
      redactUrl("https://example.com/x?y=a@b.com"),
      "https://example.com/x?y=a@b.com",
      "redactUrl leaves query strings intact",
    );
    console.log("PASS diagnostics: credential URLs rejected without leaking the password");

    // --- The deadline timer must be cleared in `finally` ---
    const childScript = `
      const { crawl } = require(${JSON.stringify(require.resolve("./simple-web-crawler"))});
      crawl(process.argv[1], 15000, undefined, { allowLoopback: true })
        .then(() => console.log("CRAWL_DONE"))
        .catch((error) => { console.error(error.message); process.exitCode = 1; });
    `;
    const child = spawn(process.execPath, ["-e", childScript, `${fixtureUrl}/about`], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    const childExit = new Promise((resolve) => {
      const started = Date.now();
      child.on("exit", (code) => resolve({ code, ms: Date.now() - started }));
    });
    const exit = await Promise.race([
      childExit,
      new Promise((resolve) => setTimeout(() => resolve({ code: "STILL_RUNNING", ms: 5000 }), 5000)),
    ]);
    if (exit.code === "STILL_RUNNING") child.kill();
    assert.notStrictEqual(
      exit.code,
      "STILL_RUNNING",
      "child must exit long before its 15s deadline timer fires (timer cleared in finally)",
    );
    assert.strictEqual(exit.code, 0, `crawl child exited with ${exit.code}`);
    console.log(`PASS deadline: crawl child exited in ${exit.ms}ms (no leaked abort timer)`);
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