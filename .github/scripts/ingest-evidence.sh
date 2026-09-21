#!/usr/bin/env bash
# Deterministic historical-evidence ingestion for the /oc control plane.
#
# This is the "Read Here" mode support. Treat a user-supplied directory (by
# convention named "Read Here/") as EVIDENCE/DATA only: it is never consulted
# as executable instructions, and controller security policy always wins.
#
# For every regular file under the source directory the script records a
# machine-readable manifest entry: SHA-256, size, path, type, extraction
# method, extraction status, extracted-text size, OCR-need, and any error.
# Extraction is deterministic and local (python3 stdlib, pdftotext/tesseract
# when present). The source directory is never modified.
#
# Usage:
#   ingest-evidence.sh <source-dir> [--manifest <path>] [--out-dir <dir>]
#
# Env: RUNNER_TEMP (defaults to /tmp), optionally INGEST_MAX_TEXT_CHARS
#
# Exit code: 0 when at least one file was processed; 1 when no source
# directory was found; 2 on usage error.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: ingest-evidence.sh <source-dir> [--manifest <path>] [--out-dir <dir>]
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
source_dir="$1"; shift
manifest="${INGEST_MANIFEST:-}"
out_dir="${INGEST_OUT_DIR:-}"
while (($# > 0)); do
  case "$1" in
    --manifest) manifest="${2:-}"; shift 2 ;;
    --out-dir) out_dir="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -d "$source_dir" ]] || {
  echo "::error title=Evidence source missing::Source directory '$source_dir' does not exist. Nothing was ingested." >&2
  exit 1
}

runner_temp="${RUNNER_TEMP:-/tmp}"
[[ -n "$manifest" ]] || manifest="$runner_temp/evidence/evidence-manifest.json"
[[ -n "$out_dir" ]] || out_dir="$runner_temp/evidence/extract"
mkfile_dir="$(dirname "$manifest")"
mkdir -p "$mkfile_dir" "$out_dir"
manifest="$(realpath "$manifest")"
out_dir="$(realpath "$out_dir")"
source_dir_abs="$(realpath "$source_dir")"

work="$(mktemp -d "$runner_temp/oc-ingest-XXXXXX")"
trap 'rm -rf "$work"' EXIT
inventory="$work/inventory.tsv"
: > "$inventory"

# classify by extension (fallback: file magic), returning a category
category_for() { # category_for <path>
  local p="$1" base ext
  base="$(basename "$p")"
  ext="${base##*.}"
  case "${ext,,}" in
    txt|md|markdown|log|ini|conf|cfg|toml|yaml|yml|json|jsonc|xml|html|htm|csv|tsv|rst|adoc|svg) echo "text" ;;
    js|ts|jsx|tsx|mjs|cjs|py|sh|bash|rb|go|rs|c|h|cpp|hpp|cc|java|kt|scala|php|lua|sql|dockerfile|make|cmake) echo "source" ;;
    pdf) echo "pdf" ;;
    docx|docm) echo "docx" ;;
    xlsx|xlsm) echo "xlsx" ;;
    pptx|pptm) echo "pptx" ;;
    png|jpg|jpeg|gif|webp|bmp|tiff|tif|heic) echo "image" ;;
    *) echo "other" ;;
  esac
}

has_magic_type() { [[ -n "$(file -b "$1" 2>/dev/null || true)" ]]; }

sanitize_text() { # sanitize_text <in-file> <out-file>
  python3 - "$1" "$2" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
text = data.decode("utf-8", errors="replace")
text = re.sub(r"(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})", "[REDACTED_GITHUB_TOKEN]", text)
text = re.sub(r"(AIza[A-Za-z0-9_-]{20,})", "[REDACTED_GOOGLE_KEY]", text)
text = re.sub(r"(sk-or-v1-[A-Za-z0-9_-]{20,})", "[REDACTED_EXTERNAL_API_KEY]", text)
text = re.sub(r"(Bearer\s+)[^\s]+", r"\1[REDACTED]", text)
max_chars = int(os.environ.get("INGEST_MAX_TEXT_CHARS", "2000000"))
if len(text) > max_chars:
    text = text[:max_chars] + "\n[TRUNCATED: input exceeds INGEST_MAX_TEXT_CHARS]\n"
open(dst, "w", encoding="utf-8", errors="replace").write(text)
sys.exit(0)
PY
}

extract_txtlike() { # extract_txtlike <src> <dst-category> <dst>
  local src="$1" cat="$2" dst="$3"
  local tmp
  tmp="$(mktemp "$work/txt.XXXXXX")"
  cp "$src" "$tmp"
  case "$cat" in
    source) : ;; # same copy path
    *) : ;;
  esac
  sanitize_text "$tmp" "$dst"
  rm -f "$tmp"
}

extract_pdf() { # extract_pdf <src> <dst> -> status via stdout (plaintext|ocr_required)
  local src="$1" dst="$2" tmp
  tmp="$(mktemp "$work/pdf.XXXXXX")"
  if command -v pdftotext >/dev/null 2>&1; then
    if pdftotext -layout "$src" "$tmp" >/dev/null 2>&1; then
      if [[ -s "$tmp" ]]; then
        sanitize_text "$tmp" "$dst"
        rm -f "$tmp"
        echo "plaintext"
        return 0
      fi
    fi
  fi
  if python3 - "$src" "$tmp" <<'PY' >/dev/null 2>&1
import re, sys, zlib
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
streams = re.findall(rb"\r?\n?stream\r?\n?(.*?)\r?\n?endstream", data, re.S)
out = []
for s in streams:
    try:
        s = zlib.decompress(s)
    except Exception:
        pass
    for m in re.finditer(rb"\(((?:[^()\\]|\\.)*)\)\s*(?:Tj|TJ)", s):
        out.append(m.group(1))
text = b" ".join(out)
text = text.replace(b"\\(", b"(").replace(b"\\)", b")").replace(b"\\\\", b"\\")
open(dst, "wb").write(text)
if not text.strip():
    sys.exit(3)
PY
  then
    if [[ -s "$tmp" ]]; then
      sanitize_text "$tmp" "$dst"
      rm -f "$tmp"
      echo "plaintext"
      return 0
    fi
  fi
  rm -f "$tmp"
  echo "ocr_required"
}

extract_zip_office() { # extract_zip_office <kind> <src> <dst> -> status
  local kind="$1" src="$2" dst="$3"
  local tmp
  tmp="$(mktemp "$work/office.XXXXXX")"
  if python3 - "$kind" "$src" "$tmp" <<'PY' >/dev/null 2>&1
import re, sys, zipfile, html
kind, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
def strip_tags(x):
    return re.sub(r"<[^>]+>", "", x)
try:
    z = zipfile.ZipFile(src)
except Exception:
    sys.exit(4)
parts = []
if kind == "docx":
    if "word/document.xml" in z.namelist():
        parts.append(strip_tags(z.read("word/document.xml").decode("utf-8", errors="replace")))
elif kind == "xlsx":
    strings = []
    if "xl/sharedStrings.xml" in z.namelist():
        body = z.read("xl/sharedStrings.xml").decode("utf-8", errors="replace")
        for si in re.findall(r"<si>(.*?)</si>", body, re.S):
            strings.append(html.unescape(strip_tags(si)))
    parts.append(" ".join(strings))
elif kind == "pptx":
    names = [n for n in z.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n)]
    for n in sorted(names, key=lambda x: int(re.search(r"(\d+)", x).group(1))):
        parts.append("--- " + n + " ---\n" + strip_tags(z.read(n).decode("utf-8", errors="replace")))
with open(dst, "w", encoding="utf-8", errors="replace") as f:
    f.write("\n\n".join(parts))
PY
  then
    if [[ -s "$tmp" ]]; then
      cp "$tmp" "$dst"
      rm -f "$tmp"
      echo "ok"
      return 0
    fi
  fi
  rm -f "$tmp"
  echo "error"
}

extract_image() { # extract_image <src> <dst> -> status
  local src="$1" dst="$2" tmp
  tmp="$(mktemp "$work/img.XXXXXX")"
  if command -v tesseract >/dev/null 2>&1; then
    if tesseract "$src" "$tmp" >/dev/null 2>&1; then
      if [[ -s "$tmp.txt" ]]; then
        cp "$tmp.txt" "$dst"
        rm -f "$tmp" "$tmp.txt"
        echo "ocr"
        return 0
      fi
    fi
  fi
  rm -f "$tmp"
  echo "ocr_required"
}

extract_binary_strings() { # extract_binary_strings <src> <dst> -> status
  local src="$1" dst="$2" tmp
  tmp="$(mktemp "$work/str.XXXXXX")"
  if command -v strings >/dev/null 2>&1; then
    strings -a "$src" > "$tmp" 2>/dev/null || true
  else
    : > "$tmp"
  fi
  sanitize_text "$tmp" "$dst"
  rm -f "$tmp"
  echo "strings"
}

files=0
while IFS= read -r -d '' f; do
  fabs="$(realpath "$f")"
  rel="${fabs#$source_dir_abs/}"
  rel="${rel#/}"
  # never ingest the manifest or the extract output when they live under source
  if [[ -n "$manifest" && "$manifest" == "$fabs" ]]; then continue; fi
  if [[ -n "$out_dir" && "$out_dir" == "$fabs" ]]; then continue; fi
  if [[ "$fabs" == "$manifest/"* || "$fabs" == "$out_dir/"* ]]; then
    continue
  fi

  size="$(stat -c %s "$f" 2>/dev/null || echo 0)"
  sha="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
  cat_ext="$(category_for "$f")"
  if has_magic_type "$f"; then
    magic="$(file -b "$f" | tr '\t' ' ' | head -c 200)"
  else
    magic=""
  fi
  # image/pdf overrides by magic when extension was unknown
  case "$magic" in
    *"PDF document"*) cat_ext="pdf" ;;
    *"PNG image"*|*"JPEG image"*|*"Web/P image"*|*"GIF image"*|*"bitmap image"*|*"TIFF image"*) cat_ext="image" ;;
    *"Zip archive"*) [[ "$cat_ext" == "other" ]] && cat_ext="zip" ;;
  esac

  rel_out="$out_dir/$rel"
  mkdir -p "$(dirname "$rel_out")"
  text_file="${rel_out}.txt"
  method="none"
  status=""
  needs_ocr="false"
  error=""
  extracted_bytes=0

  case "$cat_ext" in
    text|source)
      method="sanitized-copy"
      if extract_txtlike "$f" "$cat_ext" "$text_file"; then
        status="ok"
      else
        status="error"; error="text extraction failed"
      fi
      ;;
    pdf)
      method="pdf-text"
      res="$(extract_pdf "$f" "$text_file")"
      if [[ "$res" == "plaintext" ]]; then
        status="ok"
      else
        needs_ocr="true"
        status="ocr_required"
      fi
      ;;
    docx) method="zip-xml-docx"; res="$(extract_zip_office docx "$f" "$text_file")"; status="$res"
      [[ "$res" == "error" ]] && error="office extraction failed" ;;
    xlsx) method="zip-xml-xlsx"; res="$(extract_zip_office xlsx "$f" "$text_file")"; status="$res"
      [[ "$res" == "error" ]] && error="office extraction failed" ;;
    pptx) method="zip-xml-pptx"; res="$(extract_zip_office pptx "$f" "$text_file")"; status="$res"
      [[ "$res" == "error" ]] && error="office extraction failed" ;;
    image) method="ocr"
      res="$(extract_image "$f" "$text_file")"
      if [[ "$res" == "ocr" ]]; then status="ok"; else needs_ocr="true"; status="ocr_required"; fi
      ;;
    zip) method="none"; status="binary"; error="generic zip container: not extracted" ;;
    *) method="strings"
      res="$(extract_binary_strings "$f" "$text_file")"; status="$res"
      ;;
  esac

  if [[ -f "$text_file" ]]; then
    extracted_bytes="$(stat -c %s "$text_file" 2>/dev/null || echo 0)"
    if [[ "$status" == "ok" && "$extracted_bytes" -eq 0 ]]; then status="empty"; fi
  else
    extracted_bytes=0
  fi
  if [[ "$status" == "ocr_required" ]]; then needs_ocr="true"; fi

  # TSV row (short error text only)
  err_flat="$(printf '%s' "$error" | tr '\t\n' '  ' | head -c 200)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$rel" "$size" "$sha" "$cat_ext" "$method" "$status" "$needs_ocr" "$extracted_bytes" "$(printf '%s' "$magic" | head -c 200)" "$err_flat" \
    >> "$inventory"
  files=$((files + 1))
done < <(find "$source_dir" -type f -print0)

if [[ "$files" -eq 0 ]]; then
  echo "::warning title=No evidence files::Source directory '$source_dir' contained no regular files to ingest."
  echo "No evidence files were ingested from $source_dir"
  exit 0
fi

python3 - "$inventory" "$manifest" "$source_dir_abs" "$out_dir" <<'PY'
import csv, io, json, os, shutil, sys, datetime
inv, manifest_path, src_abs, out_abs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
rows = []
with open(inv, encoding="utf-8", errors="replace") as f:
    reader = csv.reader(f, delimiter="\t")
    for r in reader:
        if len(r) < 10:
            continue
        rel, size, sha, cat, method, status, ocr, ebytes, magic, err = r
        rows.append({
            "relative_path": rel,
            "size_bytes": int(size or 0),
            "sha256": sha,
            "category": cat,
            "type": magic,
            "extraction_method": method,
            "extraction_status": status,
            "needs_ocr": ocr == "true",
            "extracted_text_bytes": int(ebytes or 0),
            "extracted_text_path": os.path.relpath(os.path.join(out_abs, rel) + ".txt", start="") if ocr or method not in ("none",) else None,
            "error": err or None,
        })
tools = {"python3": shutil.which("python3"), "file": shutil.which("file"), "sha256sum": shutil.which("sha256sum")}
for t in ("pdftotext", "tesseract", "strings"):
    tools[t] = shutil.which(t)
manifest = {
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_directory": src_abs,
    "source_relative_to": os.path.basename(src_abs),
    "extract_directory": out_abs,
    "tool_availability": tools,
    "total_files": len(rows),
    "status_counts": {},
    "files": rows,
}
counts = {}
for r in rows:
    s = r["extraction_status"] or "unknown"
    counts[s] = counts.get(s, 0) + 1
manifest["status_counts"] = counts
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
print(f"MANIFEST={manifest_path}")
print(f"FILES={len(rows)}")
for k, v in sorted(counts.items()):
    print(f"STATUS_{k}={v}")
PY

echo "---- evidence ingestion summary ----"
echo "source: $source_dir_abs"
echo "manifest: $manifest"
python3 - "$manifest" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(f"files processed: {m['total_files']}")
print(f"status counts: {m['status_counts']}")
ocr = [f["relative_path"] for f in m["files"] if f["needs_ocr"]]
if ocr:
    print("needs OCR:")
    for p in ocr:
        print("  - " + p)
else:
    print("needs OCR: none")
PY