# Human-oriented OpenCode live stream filter.
#
# Input has already been secret-sanitized by run-opencode-attempt.sh.
# Keep high-signal operator events visible while suppressing repetitive
# internal logger telemetry that does not help a human follow the work.

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

function emit(s) {
  print s
  fflush()
}

BEGIN {
  suppress=0
  suppress_depth=0
  touching=0
  touch_depth=0
  touch_file=""
  touch_timestamp=""

  label["Read"]="Reading file..."
  label["Edit"]="Making changes / editing file..."
  label["Write"]="Making changes / editing file..."
  label["Patch"]="Making changes / editing file..."
  label["Shell"]="Running shell command"
  label["Glob"]="Searching files..."
  label["Grep"]="Searching files..."
  label["WebFetch"]="Fetching documentation..."
  label["WebSearch"]="Searching documentation/web..."
}

{
  line=$0

  if (line ~ /^\[OC\]\[PHASE/) {
    emit("")
    emit("============================================================")
    emit(line)
    emit("============================================================")
    next
  }
  if (line ~ /^\[GEMINI\]/) { emit("  -> " line); next }
  if (line ~ /^\[COPILOT\]/) { emit("  -> " line); next }
  if (line ~ /^\[OC\]\[DECISION SUMMARY\]/) { emit("  >> " line); next }

  if (suppress) {
    suppress_depth += brace_delta(line)
    if (suppress_depth <= 0) {
      suppress=0
      suppress_depth=0
    }
    next
  }

  if (touching) {
    if (line ~ /file:[[:space:]]*"/) {
      touch_file=line
      sub(/^.*file:[[:space:]]*"/,"",touch_file)
      sub(/".*$/,"",touch_file)
    }
    touch_depth += brace_delta(line)
    if (touch_depth <= 0) {
      if (touch_file!="") {
        emit("Making changes / editing file...")
        emit(touch_timestamp " touching file \"" touch_file "\"")
      } else {
        emit("Making changes / editing file...")
      }
      touching=0
      touch_depth=0
      touch_file=""
      touch_timestamp=""
    }
    next
  }

  if (line ~ /\] INFO \(#[0-9]+\): (process|stream|llm runtime selected|evaluated|tracking|loop|snapshot|telemetry)[[:space:]]*\{/) {
    suppress_depth=brace_delta(line)
    if (suppress_depth > 0) suppress=1
    next
  }

  if (line ~ /^\[[^]]+\] INFO \(#[0-9]+\): touching file[[:space:]]*\{/) {
    touch_timestamp=line
    sub(/ .*$/,"",touch_timestamp)
    touching=1
    touch_depth=brace_delta(line)
    if (line ~ /file:[[:space:]]*"/) {
      touch_file=line
      sub(/^.*file:[[:space:]]*"/,"",touch_file)
      sub(/".*$/,"",touch_file)
    }
    if (touch_depth <= 0) {
      emit("Making changes / editing file...")
      if (touch_file!="") emit(touch_timestamp " touching file \"" touch_file "\"")
      touching=0
      touch_depth=0
      touch_file=""
      touch_timestamp=""
    }
    next
  }

  if (line ~ /^[[:space:]]*\|[[:space:]]+(Read|Edit|Write|Patch|Shell|Glob|Grep|WebFetch|WebSearch)([[:space:]]|$)/) {
    toolline=line
    sub(/^[[:space:]]*\|[[:space:]]+/,"",toolline)
    split(toolline, fields, /[[:space:]]+/)
    tool=fields[1]
    emit(label[tool])
    emit(line)
    next
  }

  emit(line)
}
