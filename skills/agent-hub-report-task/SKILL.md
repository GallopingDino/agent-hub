---
name: agent-hub-report-task
description: Run whenever you learn or change which tracker tasks (codes like ABC-123 or task links) the current work is for, however you learned them.
---

Run `agent-hub task <task>...` with all current tasks in one call; each call replaces the last list. Write a task as `CODE=LINK` when you know both, otherwise just the code or the link. Use `agent-hub task --clear` when no task applies. Never guess a code. If the command is missing, skip it silently.
