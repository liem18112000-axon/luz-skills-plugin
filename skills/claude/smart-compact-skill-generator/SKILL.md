---
name: smart-compact-skill-generator
description: Generate a custom "smart compact" slash-command tailored to the current conversation. Asks three questions (preserve verbatim / summarize to key points / safe to discard), infers from current conversation context when answers are missing, and writes a new skill at `~/.claude/skills/<name>/SKILL.md` with `disable-model-invocation: true` (user-only invocation) and a default effort hint of "low". Use when the user asks to "make a compact skill", "create a smart compactor", "build a custom /compact", or any equivalent. The generated skill, when invoked, applies the preserve/summarize/discard rules to the conversation and emits a structured summary the user can pin or paste forward.
---

# smart-compact-skill-generator

Generate a one-off, conversation-aware compact skill. The generator asks three questions, fills gaps from context, and writes the new SKILL.md to the user's skills dir.

## Inputs

| # | Question | Required? | Default if user skips |
| -- | -------- | --------- | --------------------- |
| 1 | **Preserve** (must keep verbatim) | optional | infer from context — code blocks the user just wrote, file paths just edited, errors still being investigated |
| 2 | **Summarize** (condense to key points) | optional | infer — multi-step debugging traces, exploratory dialogues, log dumps |
| 3 | **Discard** (safe to remove) | optional | infer — duplicate snippets, system reminders, completed tool outputs, old plans superseded by newer ones |
| 4 | **Name** for the generated skill | optional | infer a relevant kebab-case name from the conversation's dominant topic, prefixed `compact-` (e.g. `compact-luz-materialize`, `compact-eArchive-debugging`) |

If the user provides answers as bullets, free text, or a single sentence, parse and use as-is. If they say "you decide" / "infer it" / nothing at all, generate sensible defaults from the live conversation — name what you saw, not what you assume.

## Behaviour when invoked

1. **Print the resolved tuple** before generating, so the user can correct any inferred value:
   ```
   [smart-compact] resolved:
     name:      compact-<inferred>
     preserve:  <user input or inferred bullet list>
     summarize: <user input or inferred bullet list>
     discard:   <user input or inferred bullet list>
     effort:    low
     disable-model-invocation: true
   proceeding to write ~/.claude/skills/<name>/SKILL.md ...
   ```

2. **Write** `~/.claude/skills/<name>/SKILL.md` with frontmatter:
   ```yaml
   ---
   name: <name>
   description: <one-line summary auto-generated from preserve/summarize/discard>
   disable-model-invocation: true
   ---
   ```
   …and a body section per the template below.

3. **Refuse to overwrite** if `~/.claude/skills/<name>/` already exists. Print the existing path and ask the user to choose another name (or pass `OVERWRITE=yes` to proceed).

4. **Do not modify** the current conversation; the generator's job is to author a NEW skill, not to apply compaction itself. The user will run the new skill later via `/<name>`.

## Default frontmatter values for the generated skill

- `disable-model-invocation: true` — only fires when the user explicitly types `/<name>`. Compaction is intentional, not opportunistic.
- `effort: low` — a hint in the body (not enforced anywhere) telling the future Claude to skim, not deep-think. The compact rules are mechanical filtering, not a research task.

The user can override either field via env var when invoking the generator (`DISABLE_MODEL_INVOCATION=false ENABLE_HIGH_EFFORT=yes /smart-compact-skill-generator …`).

## Generated SKILL.md template

```markdown
---
name: <name>
description: Compact the current conversation by preserving <one-line preserve summary>, summarizing <one-line summarize summary>, and discarding <one-line discard summary>. User-invocation only.
disable-model-invocation: true
---

# <name>

Effort level: **low** — mechanical filter, no deep planning.

## Compaction rules

### Preserve verbatim
<bullet list from input #1>

### Summarize to key points
<bullet list from input #2>

### Discard
<bullet list from input #3>

## How to invoke

Type `/<name>` after a long debugging or exploration session to emit a compacted summary.

## What the skill does

1. Walk the current conversation top-to-bottom.
2. For each message / tool result, classify against the rules above:
   - matches **preserve** → quote verbatim.
   - matches **summarize** → emit a 1-3 line condensation naming the artifact (file path, error class, tool, etc.).
   - matches **discard** → drop entirely.
3. Output the result as a single fenced markdown block titled `# <name> — compacted view`.
4. **Persist the compacted view to disk** so it survives `/clear`:
   - Path: `~/.claude/projects/<cwd-slug>/compact/<name>-<unix-ts>.md` (Linux/macOS) or `%USERPROFILE%\.claude\projects\<cwd-slug>\compact\<name>-<unix-ts>.md` (Windows). `<cwd-slug>` is the current working directory with `/` and `\` and `:` replaced by `-`. Create the `compact/` dir if missing.
   - Write the *exact* fenced block from step 3 plus a one-line provenance header (`<!-- generated: <iso8601> · turns scanned: <N> · ratio: <NN>% -->`).
5. **Print the reset instructions** verbatim, so the user can drop the bloated context and start fresh with only the compact view loaded:
   ```
   ───────────────────────────────────────────────────────────────────
   Compact written: <absolute path>
   To load only this view as the new context:
       1. /clear            — wipe the current conversation
       2. Read <absolute path>   — load the compact view as the first turn
   The next message you send will run against ~<after-tokens> tokens
   instead of the current ~<before-tokens> tokens.
   ───────────────────────────────────────────────────────────────────
   ```
6. Do not modify the live conversation directly; the user runs `/clear` themselves. The skill cannot — and intentionally does not — wipe the window without explicit user action.
```

## How to invoke the generator

Direct: `/smart-compact-skill-generator`

With answers inline (preferred — saves a turn):
```
/smart-compact-skill-generator
preserve: the materialize_stats schema, the Phase-1 buildOpenForNoCodesPredicate diff
summarize: the eArchive smoke-test results, the log analyses
discard: tool-search outputs, system reminders, repeated file listings
name: compact-luz-materialize
```

## Notes for the assistant orchestrating the generator

- Don't ask the user to confirm each inferred value individually — print the full resolved tuple in one block and proceed unless the user objects.
- The "infer from context" step is the value-add of this skill; lean on it. Look at the dominant topic of the last ~20 turns, what files were touched, what tool errors occurred. Don't list everything — pick the 3-5 most load-bearing items per category.
- Keep the generated skill's body under 60 lines. The point is a quick filter, not a treatise.
- After writing the file, print the full path so the user can `/<name>` immediately or open the file to tweak.

## Why the persist-and-clear pattern matters

A compact view that lives only in scrollback **does not save tokens** — it sits at the *end* of the bloated context. Every subsequent turn still pays for the full preceding noise. The only way to reclaim window space is `/clear` followed by a re-ingest of the compact view.

Three constraints shape the design:

1. **Skills cannot run `/clear` themselves.** It's a user-initiated harness command. The generated skill therefore prints the *exact* command sequence the user must run, and stops.
2. **The compact view must outlive `/clear`.** That means writing it to disk *before* asking the user to clear. The path lives under `~/.claude/projects/<cwd-slug>/compact/` so multiple compactions can co-exist (timestamped) and grep-able via the cwd-slug.
3. **The reset instruction names absolute paths.** Pasting `/clear` then typing `Read ~/...` works. Telling the user to "remember the compacted view" doesn't.

This is the difference between a tool that *summarises* and a tool that actually *compresses* the runtime context. The skill must teach this pattern at the call site — users won't infer it from "compacted view" alone.
