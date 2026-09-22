export const AgenticObservability = async () => {
  const safe = (value) => String(value ?? "")
    .replace(/(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-or-v1-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,}|Bearer\s+\S+)/g, "[REDACTED]")
    .replace(/\s+/g, " ")
    .slice(0, 240)

  const toolName = (value) => {
    if (!value) return "unknown"
    if (value === "bash") return "shell"
    if (value === "edit" || value === "write") return "file-edit"
    return String(value)
  }

  const emit = (line) => console.log("[OPENCODE] " + line)

  return {
    event: async ({ event }) => {
      try {
        if (event.type === "session.created") emit("session started")
        else if (event.type === "session.status") emit("status " + safe(event.properties?.status ?? event.status))
        else if (event.type === "session.error") emit("ERROR " + safe(event.properties?.error ?? event.error))
        else if (event.type === "file.edited") emit("edited " + safe(event.properties?.path ?? event.path))
        else if (event.type === "tool.execute.before") emit("tool → " + toolName(event.properties?.tool ?? event.tool))
        else if (event.type === "tool.execute.after") emit("tool ✓ " + toolName(event.properties?.tool ?? event.tool))
        else if (event.type === "todo.updated") emit("plan updated")
        else if (event.type === "session.compacted") emit("session compacted; continuing with preserved context")
        else if (event.type === "session.updated") emit("session updated")
        else if (event.type === "session.idle") emit("session idle")
      } catch (_) {}
    },
  }
}
