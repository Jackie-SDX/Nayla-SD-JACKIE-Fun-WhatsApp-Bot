#!/usr/bin/env bash
# Lean capability discovery/acquisition helper for OpenCode runs.
# It accelerates common tasks; it is not a hard tool allowlist.
set -u

workspace=""
task_file=""
output=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) workspace="$2"; shift 2 ;;
    --task-file) task_file="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) echo "usage: $0 --workspace DIR --task-file FILE --output FILE" >&2; exit 2 ;;
  esac
done

[ -d "$workspace" ] && [ -f "$task_file" ] && [ -n "$output" ] || exit 2
mkdir -p "$(dirname "$output")"

task_text="$(cat "$task_file" 2>/dev/null || true)"
lower_task="$(printf '%s' "$task_text" | tr '[:upper:]' '[:lower:]')"
caps_file="${RUNNER_TEMP:-/tmp}/oc-capabilities.$$.txt"
installs=""
notes=""

cleanup() { rm -f "$caps_file"; }
trap cleanup EXIT

cap() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$caps_file"
}

need() {
  local p="$1"
  case " $installs " in
    *" $p "*) ;;
    *) installs="${installs:+$installs }$p" ;;
  esac
}

cap git git "git" "repository lifecycle"
cap gh gh "gh" "GitHub lifecycle and Actions"
cap jq jq "jq" "structured JSON"
cap rg rg "ripgrep" "repository search"
cap curl curl "curl" "web/API retrieval"
cap tar tar "tar" "archive handling"
cap unzip unzip "unzip" "archive handling"

if [ -e "$workspace/package.json" ] || [ -e "$workspace/pnpm-lock.yaml" ] || [ -e "$workspace/yarn.lock" ]; then
  cap node node "nodejs" "Node project detected"
  cap npm npm "npm" "Node dependency management"
fi

if find "$workspace" -maxdepth 2 \( -name pyproject.toml -o -name requirements.txt -o -name setup.py -o -name setup.cfg \) -print -quit 2>/dev/null | grep -q .; then
  cap python python3 "python3" "Python project detected"
  cap pip pip3 "python3-pip" "Python dependency management"
  cap venv python3 "python3-venv" "isolated Python tooling"
fi

if [ -e "$workspace/Cargo.toml" ]; then
  cap rust cargo "cargo" "Rust project detected"
fi
if [ -e "$workspace/go.mod" ]; then
  cap go go "golang" "Go project detected"
fi
if [ -e "$workspace/CMakeLists.txt" ]; then
  cap cmake cmake "cmake" "CMake project detected"
  cap ninja ninja "ninja-build" "native build accelerator"
  cap compiler cc "build-essential" "native compiler"
  cap clang clang "clang" "alternative native toolchain"
fi
if [ -d "$workspace/.github/workflows" ]; then
  cap yq yq "yq" "workflow YAML manipulation"
  cap shellcheck shellcheck "shellcheck" "controller shell validation"
fi
if printf '%s' "$lower_task" | grep -Eq '(^(|[^a-z])(pdf|pandoc|document|markdown|latex|report|runbook)([^a-zM|$)' || [ -d "$workspace/docs/pandoc-demo" ]; then
  cap pandoc pandoc "pandoc" "document/PDF task"
  cap pdfinfo pdfinfo "poppler-utils" "PDF inspection"
  cap pdftotext pdftotext "poppler-utils" "PDF text verification"
  cap latex pdflatex "texlive-latex-base" "LaTeX PDF engine"
  if ! command -v pdflatex >/dev/null 2>&1; then
    need texlive-latex-recommended
    need texlive-latex-extra
    need texlive-fonts-recommended
    need lmodern
  fi
fi
if printf '%s' "$lower_task" | grep -Eq '([^a-z])(diagram|graphviz|dot generation)([^a-z]|$)'; then
  cap graphviz dot "graphviz" "diagram generation"
fi
if printf '%s' "$lower_task" | grep -Eq '(^|[^a-z])(image|png|jpeg|jpg|svg|ocr)([^a-z]|$)'; then
  cap image-tools convert "imagemagick" "image processing"
fi
if printf '%s' "$lower_task" | grep -Eq '(^|[^a-z])(ffmpeg|audio|video|media)([^a-z]|$)'; then
  cap ffmpeg ffmpeg "ffmpeg" "media processing"
fi

if printf '%s' "$lower_task" | grep -Eq 'security|vulnerability|sast|secret scan|dependency scan'; then
  notes="${notes}
- Security scanners such as Trivy, Semgrep, and Gitleaks are not blindly installed. Acquire the required tool from its official current guidance and verify version/checksum/signature."
fi

if ! command -v mise >/dev/null 2>&1; then
  notes="${notes}
- mise is not assumed globally installed. When an alternate runtime version is required, use the current official mise installation/release guidance and acquire a pinned, verified version."
else
  cap mise mise "" "runtime/tool version manager"
fi

while IFS="$(printf '\t')" read -r label cmd package reason; do
  [ -n "$label" ] || continue
  if ! command -v "$cmd" >/dev/null 2>&1 && [ -n "$package" ]; then
    need "$package"
  fi
done < "$caps_file"

if [ -n "$installs" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    echo "[CAP] acquiring missing capabilities: $installs"
    if ! sudo apt-get update -y >/dev/null 2>&1 || ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $installs >/dev/null 2>&1; then
      notes="${notes}
- Automatic APT acquisition failed for: $installs. Continue with an official user-space/project-local installation path."
    fi
  else
    notes="${notes}
- Insufficient privilege for APT acquisition: $installs. Continue with an official user-space/project-local installation path."
  fi
fi

{
  echo "# OpenCode capability matrix"
  echo
  echo "- Generated: $(date -u +%Y-%m-%dT%: %C:%S:%SZ)"
  echo "- Workspace: $workspace"
  echo "- Runner: $(uname -srm 2>/dev/null || true)"
  echo
  echo "## Required/detected capabilities"
  echo
  while IFS="$(printf '\t')" read -r label cmd package reason; do
    [ -n "$label" ] || continue
    if command -v "$cmd" >/dev/null 2>&1; then
      path="$(command -v "$cmd")"
      version="$("$cmd" --version 2>/dev/null | head -n 1 || true)"
      [ -n "$version" ] || version="$("$cmd" -V 2>/dev/null | head -n 1 || true)"
      echo "- [x] $label â $version â $path â $reason"
    else
      echo "- [ ] $label â missing â $reason"
    fi
  done < "$caps_file"
  echo
  echo "## Useful baseline capabilities"
  echo
  for cmd in python3 node npm cmake ninja clang clang-format clang-tidy do
    if command -v "$cmd" >/dev/null 2>&1; then
      version="$("$cmd" --version 2>/dev/null | head -n 1 || true)"
      echo "- [x] $cmd â $version"
    else
      echo "- [ ] $cmd â not installed"
    fi
  done
  if [ -n "$notes" ]; then
    echo
    echo "## Acquisition notes"
    printf '%s\n' "$notes"
  fi
  echo
  echo "## Policy"
  echo
  echo "This matrix is e vidence for the primary OpenCode session, not a hard allowlist."
  echo "Unknown capabilities may be acquired by the agent when required, using authoritative upstream instructions and verification."
} > "$output"

echo "[CAP] capability matrix: $output"
exit 0
