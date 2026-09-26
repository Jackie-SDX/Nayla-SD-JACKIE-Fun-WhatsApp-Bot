---
title: SnapDragon Pandoc-to-PDF Capability Test
subtitle: End-to-end GitHub Actions demonstration
author: OpenCode controller
date: 2026-09-26
---

# SnapDragon Pandoc-to-PDF Capability Test

## Purpose

This small document proves that the SnapDragon repository can convert Markdown to
PDF inside GitHub Actions. It intentionally exercises every construct that
typically breaks a naive conversion: a document title, nested headings, multi
paragraph prose, a bullet list, a data table, and a fenced code block.

The conversion runs on `ubuntu-latest`, uses Pandoc installed from the official
binaries, and renders through a LaTeX PDF engine installed in the workflow.

### Why it matters

If this pipeline is green, the repository has a verified path for producing
shareable PDF deliverables (release notes, runbooks, audits) from plain Markdown
sources that are already reviewed in pull requests.

## Checklist

- Title and subtitle rendered from YAML metadata
- Level 2 and level 3 headings preserved in the outline
- Paragraphs with inline emphasis and code spans
- Bullet list with multiple items
- Table with a header row and three data rows
- Fenced code block kept verbatim with monospace font

## Sample Conversion Matrix

| Stage     | Tool              | Source of truth        | Verified by      |
| --------- | ----------------- | ---------------------- | ---------------- |
| Install   | pandoc/actions    | Official pandoc binary | `pandoc --version` |
| Engine    | TeX Live          | Ubuntu package archive | `pdflatex --version` |
| Convert   | Pandoc            | This Markdown file     | Non-empty PDF    |
| Publish   | upload-artifact   | GitHub Actions runtime | Artifact listing |

## Sample Code Block

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p output
pandoc docs/pandoc-demo/snapdragon-pandoc-demo.md \
  --pdf-engine=pdflatex \
  --standalone \
  --output output/snapdragon-pandoc-demo.pdf

test -s output/snapdragon-pandoc-demo.pdf
echo "PDF generated: $(stat -c %s output/snapdragon-pandoc-demo.pdf) bytes"
```

## Closing

Any failure in this pipeline is a real infrastructure failure, not a
documentation gap: the workflow asserts on the presence, minimum size, and PDF
magic bytes of the generated file before uploading it.
