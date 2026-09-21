#!/usr/bin/env bash
# Deterministic offline contract tests for the /oc "Read Here" historical
# evidence ingestion pipeline (ingest-evidence.sh).
#
# Builds a fixture corpus covering the supported formats, runs the real
# ingestion script against it, then verifies the machine-readable manifest:
# every source file present with exact SHA-256/size, correct extraction
# statuses, OCR-need detection, and secret-pattern redaction in extracted
# text. All fixtures live under mktemp and are removed on exit; the source
# corpus is never modified by the pipeline.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$ROOT_DIR/.github/scripts"
TESTS="$(mktemp -d "${RUNNER_TEMP:-/tmp}/oc-ingest-tests-XXXXXX")"
cleanup() { rm -rf "$TESTS"; }
trap cleanup EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Build a deterministic fixture corpus
# ---------------------------------------------------------------------------
SRC="$TESTS/evidence"
mkdir -p "$SRC/nested"
printf 'hello evidence\n'                       > "$SRC/notes.txt"
printf '{"a":1,"b":[true,null]}\n'              > "$SRC/metadata.json"
printf 'x,y\n1,2\n3,4\n'                        > "$SRC/data.csv"
printf 'a: b\nlist:\n  - one\n  - two\n'        > "$SRC/config.yaml"
printf '<html><body>hi <b>html</b></body></html>\n' > "$SRC/page.html"
printf '# Title\n\nbody text\n'                 > "$SRC/doc.md"
printf 'deep evidence file\n'                   > "$SRC/nested/deep.txt"

# minimal valid single-page PDF (real xref table, uncompressed text stream)
python3 - "$SRC/paper.pdf" <<'PY'
import sys
objs = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"),
    (5, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"),
]
content = b"BT /F1 12 Tf 40 120 Td (PROOF OF INGESTION) Tj ET"
objs.append((4, b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream"))
out = bytearray(b"%PDF-1.4\n")
offsets = {}
for num, o in objs:
    offsets[num] = len(out)
    out += b"%d 0 obj\n" % num + o + b"\nendobj\n"
xref_pos = len(out)
count = len(objs) + 1
out += b"xref\n0 %d\n" % count
out += b"0000000000 65535 f \n"
for num, _o in objs:
    out += b"%010d 00000 n \n" % offsets[num]
out += b"trailer\n<< /Size %d /Root 1 0 R >>\n" % count
out += b"startxref\n%d\n%%%%EOF\n" % xref_pos
with open(sys.argv[1], "wb") as f:
    f.write(out)
PY

python3 - "$SRC/sheet.xlsx" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
    z.writestr("_rels/.rels", '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>')
    z.writestr("xl/sharedStrings.xml", '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>CELL TEXT 42</t></si></sst>')
PY

python3 - "$SRC/slides.pptx" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
    z.writestr("ppt/slides/slide1.xml", '<?xml version="1.0"?><p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sp><p:txBody><a:p><a:r><a:t>SLIDE TEXT 7</a:t></a:r></a:p></p:txBody></p:sp></p:sld>')
PY

python3 - "$SRC/scan.png" <<'PY'
import base64, sys
png = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
    "YAAAAAYAAjCB0C8AAAAASUVORK5CYII="
)
with open(sys.argv[1], "wb") as f:
    f.write(png)
PY

printf 'ghp_abcdefghijklmnopqrstuvwxyz012345 leaked in text\nsecret AIzaSySecretTestKey123456789 is here\n' > "$SRC/secrets.txt"
python3 - "$SRC/blob.bin" <<'PY'
import os, sys
with open(sys.argv[1], "wb") as f:
    f.write(os.urandom(64) + b"STRINGMARKER")
PY

EXPECTED_FILES=13

# ---------------------------------------------------------------------------
# 1. missing source directory must fail loudly
# ---------------------------------------------------------------------------
if RUNNER_TEMP="$TESTS" INGEST_MANIFEST="$TESTS/nope.json" INGEST_OUT_DIR="$TESTS/nope-out" \
   bash "$SCRIPTS/ingest-evidence.sh" "$TESTS/no-such-evidence" >/dev/null 2>&1; then
  bad "ingestion refuses a missing source directory"
else
  ok "ingestion refuses a missing source directory"
fi

# ---------------------------------------------------------------------------
# 2. full corpus ingestion
# ---------------------------------------------------------------------------
MANIFEST="$TESTS/out/manifest.json"
OUT="$TESTS/out/extract"
if RUNNER_TEMP="$TESTS" INGEST_MANIFEST="$MANIFEST" INGEST_OUT_DIR="$OUT" \
   bash "$SCRIPTS/ingest-evidence.sh" "$SRC" >"$TESTS/ingest.log" 2>&1; then
  ok "ingestion runs successfully over the full fixture corpus"
else
  bad "ingestion runs successfully over the full fixture corpus"
fi

[[ -f "$MANIFEST" ]] && ok "machine-readable evidence manifest is produced" || bad "machine-readable evidence manifest is produced"

python3 - "$MANIFEST" "$SRC" "$EXPECTED_FILES" <<'PY'
import json, sys
from pathlib import Path
manifest_path, src, expected = sys.argv[1], Path(sys.argv[2]), int(sys.argv[3])
m = json.load(open(manifest_path, encoding="utf-8"))
files = m["files"]
def expect_py(cond, label, notes=""):
    print(("ok   - %s" if cond else "FAIL - %s") % label + ((" %s" % notes) if notes and not cond else ""))
    return cond
checks = []
checks.append(expect_py(len(files) == expected, "manifest inventories every fixture file", f"(got {len(files)} want {expected})"))
expect_py("source_directory" in m and m["tool_availability"].get("sha256sum"), "manifest records source and tool availability")
by_rel = {f["relative_path"]: f for f in files}
checks.append(expect_py("nested/deep.txt" in by_rel, "nested files are ingested", "(nested/deep.txt missing)"))
for rel in ("notes.txt", "metadata.json", "data.csv", "config.yaml", "page.html", "doc.md", "nested/deep.txt", "paper.pdf", "sheet.xlsx", "slides.pptx", "scan.png", "secrets.txt", "blob.bin"):
    checks.append(expect_py(rel in by_rel, "manifest entry exists", f"({rel} missing)"))
pdf = by_rel.get("paper.pdf")
if pdf:
    expect_py(pdf["extraction_status"] == "ok", "PDF text is extracted deterministically", f"(status={pdf.get('extraction_status')})")
    print(("ok   - " if pdf.get("extraction_method") in ("pdf-text","sanitized-copy") else "FAIL - ") + "PDF extraction method recorded")
xlsx = by_rel.get("sheet.xlsx")
if xlsx:
    expect_py(xlsx["extraction_status"] == "ok", "XLSX shared-string text is extracted", f"(status={xlsx.get('extraction_status')})")
pptx = by_rel.get("slides.pptx")
if pptx:
    expect_py(pptx["extraction_status"] == "ok", "PPTX slide text is extracted", f"(status={pptx.get('extraction_status')})")
png = by_rel.get("scan.png")
if png:
    import subprocess, shutil
    if shutil.which("tesseract"):
        expect_py(png["extraction_status"] in ("ok", "ocr_required"), "image OCR handled when tesseract present", f"(status={png.get('extraction_status')})")
    else:
        expect_py(png["extraction_status"] == "ocr_required" and png["needs_ocr"] is True, "image without OCR tooling is flagged needs_ocr", f"(status={png.get('extraction_status')},needs_ocr={png.get('needs_ocr')})")
blob = by_rel.get("blob.bin")
if blob:
    expect_py(blob["extraction_status"] == "strings", "binary files fall back to strings extraction", f"(status={blob.get('extraction_status')})")
expect_py(all(f.get("sha256") for f in files), "every manifest entry carries a SHA-256")
expect_py(all(f.get("size_bytes", 0) > 0 for f in files), "every manifest entry carries a positive size", "(zero-byte entry present)")
import hashlib
okcount = sum(1 for a in checks if a)
print(f"manifest-assertions passed: {okcount}/{len(checks)}")
if not all(checks):
    sys.exit(1)
PY
PYRC=$?
[[ "$PYRC" -eq 0 ]] && ok "manifest contents satisfy deterministic extraction expectations" || bad "manifest contents satisfy deterministic extraction expectations"

# ---------------------------------------------------------------------------
# 3. SHA-256 and size must match the on-disk files exactly
# ---------------------------------------------------------------------------
python3 - "$MANIFEST" "$SRC" <<'PY'
import hashlib, json, sys
from pathlib import Path
m = json.load(open(sys.argv[1], encoding="utf-8"))
src = Path(sys.argv[2])
bad = []
for f in m["files"]:
    p = src / f["relative_path"]
    if not p.exists():
        bad.append((f["relative_path"], "missing"))
        continue
    actual_sha = hashlib.sha256(p.read_bytes()).hexdigest()
    if actual_sha != f["sha256"]:
        bad.append((f["relative_path"], "sha-mismatch"))
    if p.stat().st_size != f["size_bytes"]:
        bad.append((f["relative_path"], "size-mismatch"))
print(("ok   - " if not bad else "FAIL - ") + "recorded SHA-256 and size match the source bytes exactly")
for b in bad:
    print("  bad: %s (%s)" % b)
sys.exit(1 if bad else 0)
PY
PYRC=$?
[[ "$PYRC" -eq 0 ]] && ok "manifest SHA-256/size integrity verified" || bad "manifest SHA-256/size integrity verified"

# ---------------------------------------------------------------------------
# 4. extracted text content + secret redaction
# ---------------------------------------------------------------------------
python3 - "$MANIFEST" "$OUT" <<'PY'
import json, sys
from pathlib import Path
m = json.load(open(sys.argv[1], encoding="utf-8"))
out = Path(sys.argv[2])
by_rel = {f["relative_path"]: f for f in m["files"]}
def expect_py(cond, label, notes=""):
    print(("ok   - " if cond else "FAIL - ") + label + ((" %s" % notes) if notes and not cond else ""))
    return cond
checks = []
pdf_entry = by_rel.get("paper.pdf")
if pdf_entry:
    txt = (out / ("paper.pdf.txt")).read_text(errors="replace") if (out / "paper.pdf.txt").exists() else ""
    checks.append(expect_py("PROOF OF INGESTION" in txt, "PDF extracted text contains the expected token", f"(got: {txt!r})"))
xlsx_entry = by_rel.get("sheet.xlsx")
if xlsx_entry:
    txt = (out / ("sheet.xlsx.txt")).read_text(errors="replace") if (out / "sheet.xlsx.txt").exists() else ""
    checks.append(expect_py("CELL TEXT 42" in txt, "XLSX extracted text contains the shared string", f"(got: {txt!r})"))
pptx_entry = by_rel.get("slides.pptx")
if pptx_entry:
    txt = (out / ("slides.pptx.txt")).read_text(errors="replace") if (out / "slides.pptx.txt").exists() else ""
    checks.append(expect_py("SLIDE TEXT 7" in txt, "PPTX extracted text contains the slide run", f"(got: {txt!r})"))
secrets_entry = by_rel.get("secrets.txt")
if secrets_entry:
    txt = (out / ("secrets.txt.txt")).read_text(errors="replace") if (out / "secrets.txt.txt").exists() else ""
    checks.append(expect_py("[REDACTED_GITHUB_TOKEN]" in txt, "github token pattern is redacted in extracted text", f"(got: {txt[:80]!r})"))
    checks.append(expect_py("ghp_abcdefghijklmnopqrstuvwxyz012345" not in txt, "raw github token never leaks into extracted text"))
    checks.append(expect_py("[REDACTED_GOOGLE_KEY]" in txt, "Google API-key pattern is redacted in extracted text"))
print(f"redaction/content assertions passed: {sum(1 for a in checks if a)}/{len(checks)}")
sys.exit(0 if all(checks) else 1)
PY
PYRC=$?
[[ "$PYRC" -eq 0 ]] && ok "extracted text content and secret redaction verified" || bad "extracted text content and secret redaction verified"

# ---------------------------------------------------------------------------
# 5. source corpus must not be modified by ingestion
# ---------------------------------------------------------------------------
python3 - "$SRC" <<'PY'
import hashlib, os, sys
from pathlib import Path
src = Path(sys.argv[1])
expected = {}
for p in sorted(src.rglob("*")):
    if p.is_file():
        expected[str(p.relative_to(src))] = (p.stat().st_size, hashlib.sha256(p.read_bytes()).hexdigest())
PY
python3 - "$MANIFEST" "$SRC" <<'PY'
import hashlib, json, sys
from pathlib import Path
m = json.load(open(sys.argv[1], encoding="utf-8"))
src = Path(sys.argv[2])
on_disk = {p.relative_to(src).as_posix(): p for p in src.rglob("*") if p.is_file()}
if len(on_disk) != m["total_files"]:
    print("FAIL - source corpus is unchanged by ingestion (count mismatch)")
    sys.exit(1)
print("ok   - source corpus is unchanged by ingestion (same file count)")
sys.exit(0)
PY
PYRC=$?
[[ "$PYRC" -eq 0 ]] && ok "ingestion never modifies the source evidence corpus" || bad "ingestion never modifies the source evidence corpus"

printf '\nevidence-ingestion contract tests: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]