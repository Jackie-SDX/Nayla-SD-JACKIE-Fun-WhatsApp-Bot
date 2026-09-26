# Human-oriented OpenCode live stream filter.
#
# Input has already been secret-sanitized by run-opencode-attempt.sh.
# Keep the operator-facing stream concise while preserving useful progress
# narration and actionable tool events.

function brace_delta(s,    i,ch,quoted,escaped,delta) {
  quoted=0
  escaped=0
  delta=0
  for (i=1; i<=length(s); i++) {
    ch=substr(s,i,1)
    if (escaped) {
      escaped=0
      continue
    }
    if (ch=="\\" && quoted) {
      escaped=1
      continue
    }
    if (ch=="\"") {
      quoted=!quoted
      continue
    }
    if (!quoted) {
      if (ch=="{") delta++
      else if (ch=="}") delta--
    }
  }
  return delta
}

function bold_green(s) { return "\033[1;32m" s "\033[0m" }
function bold_cyan(s)  { return "\033[1;36m" s "\033[0m" }

function emit(s) {
  print s
  fflush()
}

function status_text(line, prefix, out) {
  out=line
  sub(prefix, "", out)
  sub(/^[[:space:]]+/, "", out)
  sub(/[[:space:]]+$/, "", out)
  return out
}

function extract_file(line, file) {
  file=line
  sub(/^.*file:[[:space:]]*"/, "", file)
  sub(/".*$/, "", file)
  return file
}

BEGIN {
  suppress=0
  suppress_depth=0
  touching=0
  touch_depth=0
  touch_file=""

  tool_event["Read"]="• Reading file…"
  tool_event["Edit"]="• Editing file…"
  tool_event["Write"]="• Editing file…"
  tool_event["Patch"]="• Editing file…"
  tool_event["Shell"]="• Running command…"
  tool_event["Glob"]="• Searching repository…"
  tool_event["Grep"]="• Searching repository…"
  tool_event["WebFetch"]="• Consulting documentation…"
  tool_event["WebSearch"]="• Searching documentation…"
}

{
  line=$0

  if (line ~ /OC-STATUS:[[:space:]]*/) {
    msg=status_text(line, "^.*OC-STATUS:[[:space:]]*")
    if (msg != "") emit(bold_green("▶ " msg))
    next
  }

  if (line ~ /OC-PLAN:[[:space:]]*/) {
    msg=status_text(line, "^.*OC-PLAN:[[:space:]]*")
    if (msg != "") emit(bold_cyan("◆ " msg))
    next
  }

  if (line ~ /OC-DONE:[[:space:]]*/) {
    msg=status_text(line, "^.*OC-DONE:[[:space:]]*")
    if (msg != "") emit(bold_green("✓ " msg))
    next
  }

  if (line ~ /^\[OC\]\[PHASE/) {
    phase=line
    sub(/^\[OC\]\[PHASE[^]]*\][[:space:]]*/, "", phase)
    emit(bold_green("━━ " phase))
    next
  }

  if (line ~ /^\[OC\]\[DECISION SUMMARY\]/) {
    summary=line
    sub(/^\[OC\]\[DECISION SUMMARY\][[:space:]]*/, "", summary)
    if (summary != "") emit(bold_cyan("◆ " summary))
    next
  }

  if (line ~ /^\[OC\]\[heartbeat/ || line ~ /^\[OC\]\[attempt=.*\][[:space:]]heartbeat/) next

  if (line ~ /^\[[^]]+\] INFO \(#[0-9]+\): touching file[[:space:]]*\{/) {
    touching=1
    touch_depth=brace_delta(line)
    touch_file=extract_file(line)
    if (touch_depth <= 0) {
      if (touch_file != "") emit("• Editing \"" touch_file "\"")
      else emit("• Editing file…")
      touching=0
      touch_depth=0
      touch_file=""
    }
    next
  }

  if (touching) {
    if (line ~ /file:[[:space:]]*"/)
      touch_file=extract_file(line)
    touch_depth += brace_delta(line)
    if (touch_depth <= 0) {
      if (touch_file != "") emit("• Editing \"" touch_file "\"")
      else emit("• Editing file…")
      touching=0
      touch_depth=0
      touch_file=""
    }
    next
  }

  if (line ~ /^[[:space:]]*\|[[:space:]]+(Read|Edit|Write|Patch|Shell|Glob|Grep|WebFetch|WebSearch)([[:space:]]|$)/) {
    toolline=line
    sub(/^[[:space:]]*\|[[:space:]]+/,"",toolline)
    split(toolline, fields, /[[:space:]]+/)
    tool=fields[1]
    if (tool in tool_event) emit(tool_event[tool])
    next
  }

  if (line ~ /^\[[^]]+\] INFO \(#[0-9]+\): (process|stream|llm runtime selected|evaluated|tracking|loop|snapshot|telemetry)[[:space:]]*\{/) {
    suppress_depth=brace_delta(line)
    if (suppress_depth > 0) suppress=1
    next
  }

  if (suppress) {
    suppress_depth += brace_delta(line)
    if (suppress_depth <= 0) {
      suppress=0
      suppress_depth=0
    }
    next
  }

  if (line ~ /^\[[^]]+\] (INFO|DEBUG|TRACE) \(#[0-9]+\):/) next
  if (line ~ /^\[OC\]\[attempt=.*\][[:space:]]+(started|finished|live stream complete)/) next
  if (line ~ /^[[:space:]]*(assistant|tool|function|input|output|result):[[:space:]]*$/) next

  emit(line)
}
