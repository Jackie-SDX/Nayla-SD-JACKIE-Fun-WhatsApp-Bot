// Static invariant checks for the host application (index.js).
//
// This file intentionally needs no npm dependencies so it can run in the
// smallest possible CI surface. Each check is a static, deterministic
// assertion over the source text. The file must fail loudly (non-zero exit,
// explicit failure lines) rather than silently degrading.

const fs = require("fs");
const path = require("path");

const APP = path.join(__dirname, "..", "index.js");
const SOURCE = fs.readFileSync(APP, "utf8");

const failures = [];
let checks = 0;

function ok(label) {
  checks += 1;
  process.stdout.write(`ok - ${label}\n`);
}

function fail(label, detail) {
  checks += 1;
  failures.push(`not ok - ${label}`);
  if (detail) failures.push(`       ${detail}`);
}

function assertContains(needle, label) {
  if (SOURCE.includes(needle)) ok(label);
  else fail(label, `missing substring: ${JSON.stringify(needle)}`);
}

function assertAbsent(regex, label) {
  if (regex.test(SOURCE)) fail(label, `unexpected match of ${regex}`);
  else ok(label);
}

function assertCount(regex, expected, label) {
  const matches = SOURCE.match(regex);
  const actual = matches ? matches.length : 0;
  if (actual === expected) ok(label);
  else fail(label, `expected ${expected} match(es), found ${actual} for ${regex}`);
}

function assertOrder(before, after, label) {
  const i = SOURCE.indexOf(before);
  const j = SOURCE.indexOf(after);
  if (i !== -1 && j !== -1 && i < j) ok(label);
  else fail(label, `order broken: before=${i} after=${j}`);
}

assertContains(
  "You are ${BOT_CONFIG.name}, a fun WhatsApp VIBE bot — you are explicitly NOT a moderator.",
  "system prompt declares the bot is explicitly NOT a moderator"
);
assertContains("You NEVER delete messages and NEVER issue formal warnings", "system prompt forbids deleting messages and warnings");
assertContains("I do NOT delete messages or moderate anything", "about text states no deletion or moderation");
assertContains("*.del* — (reply) delete a message", "help text documents manual delete-only command");
assertCount(/\{ delete: /g, 1, "exactly one message-delete publication call exists");
assertContains("{ delete: quotedKey }", "the single delete publication targets a quoted message key");
assertContains("⚠️ I need to be a group admin to delete messages.", "delete command guards on group-admin role");
assertOrder(
  "⚠️ I need to be a group admin to delete messages.",
  "{ delete: quotedKey }",
  "delete publication only reachable behind the admin guard"
);
assertContains("chatJid: { type: String, required: true }", "memory records carry the requiring chat identifier");
assertContains("UserChatFactsSchema.index({ jid: 1, chatJid: 1 }, { unique: true })", "per-chat memory isolation enforces a unique jid+chat key");
assertContains("mongoose.connect(MONGO_URI", "MongoDB persistence is wired");
assertContains("const SessionSchema = new mongoose.Schema({", "Baileys session persistence is wired");
assertContains("TTL-indexed to auto-delete after 30 days", "session records are TTL-indexed for bounded retention");
assertContains("no local creds.json was found", "local creds.json is a fallback, not the primary persistence");
assertAbsent(/useSingleFileAuthState/, "legacy single-file auth state API is absent");
assertAbsent(/localAuth\(/, "legacy localAuth session API is absent");

const summary = `${checks} invariants checked, ${failures.length} failure(s)`;
if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.stderr.write(`${summary} in ${APP}\n`);
  process.exit(1);
}
process.stdout.write(`${summary}\n`);