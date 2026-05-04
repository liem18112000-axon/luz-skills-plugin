---
name: earchive-smart-compact
description: User-invoked compaction skill tuned for iterative Java materialise / luz-docs query optimisation work. Preserves load-bearing method bodies (current shape only) + commit SHAs + materialise gate / counter shapes + Mongo state numbers + index list + open Phase items verbatim; summarises debugging traces, cloud-build polling, log dumps, and rejected refactor branches; discards system-reminder skill-list dumps, ToolSearch deferred schemas, playwright YAML pastes, old session summaries, and duplicate file listings. Emits a single compacted markdown view + a token-savings report, persists the view to disk, and prints `/clear` + `Read <path>` instructions so the user can swap the bloated context for the compact one. User-invocation only (`/earchive-smart-compact`).
disable-model-invocation: true
---

# earchive-smart-compact

Effort level: **low** — mechanical 3-layer filter, no deep planning. Walk the conversation top-to-bottom, classify each turn against the rules below, emit a single compacted markdown block + a savings report, persist it to disk, and print the reset instructions. Do **not** modify the live conversation; the user runs `/clear` themselves.

## Why this skill exists

You are a Java developer working iteratively on `src/main/java/ch/klara/luz/docs/materialize/**` to optimise the eArchive API's `search` and `count` queries. Each iteration: ship a small change, measure, decide the next angle. The conversation accumulates lots of supporting noise (system reminders, tool-search outputs, build polling, log dumps, deferred-tool schemas) — but the *load-bearing* state is small: the current shape of the relevant methods, the latest commit SHA, the Mongo numbers, the index list, and the next Phase item. This skill keeps the load-bearing state verbatim, condenses the supporting noise, drops the framing entirely, and gives the user the exact commands to swap the noisy window for the compact view.

Goal: minimise token cost while keeping (or improving) downstream answer quality.

## The 3 layers

### Layer 1 — PRESERVE verbatim
Quote exactly. Current *state*, not history — the same file may have been edited 5 times in the conversation; only the latest shape matters.

1. **Load-bearing method bodies, current shape only** — keep the *latest* version of:
   - `MaterializeQueryBuilder.buildOpenForNoCodesPredicate()` and `buildSecurityClassMatch()`
   - `MaterializeRepository.recomputeTotalOpenCount()` and `getTotalOpenCount()`
   - the `materialize_stats` upsert (`upsertTotalOpenCount` / `findStatsByKey`)
   - `MaterializeFacade.getTotalOpenCount()`
   - any other method whose name is referenced in an open phase item
   Never paste edit-by-edit diffs. The compactor's job is "what does the code look like *now*", not "how did we get here".
2. **Latest commit SHA per file** — one line per file currently under work: `<file>: <sha7>`. Drop intermediate SHAs unless the user is mid-bisect.
3. **The `materialize_stats` doc shape** — `{ statKey, count }` field names. Stat keys (`STATS_KEY_TOTAL_OPEN = "totalOpen"`). Collection name. The reason `statKey` is not `_id` (luz-jsonstore rejects non-hex `_id` filter values).
4. **Mongo state numbers** for the canary tenant (`a5e06d74-137c-4a9e-9adc-9eccdccc2d17`):
   - total documents
   - `_hasUnrestrictedFolder=true` count
   - `_hasUnrestrictedFolder=false` count
   - folderless count
5. **The index list** in `data/create-materialize-indexes.js`. Don't paraphrase index keys.
6. **Open phase items not yet shipped** — current set: Phase 3 (`_isOpenForListing`), Phase 5 (recompute throttle), Phase 7 (split facade), Phase 9 (filtered facets). One line each: `<phase> · <effort> · <one-line rationale>`.
7. **Any *unresolved* ERROR / SEVERE line on luz-docs / luz-jsonstore for the canary tenant** — error class + message verbatim. Resolved errors (a fix has shipped) drop to Layer 2 ("X bug, fixed in <sha7>").

### Layer 2 — SUMMARIZE to key points
Replace with a 1-3 line condensation that names the artifact (file path, error class, tool, sha, count) but drops formatting and step-by-step trace.

1. **Edit history / shipped phases** — one line per ship: `<sha7> · <one-line subject> · <files-touched-count> files`. Drop the diffs themselves (Layer 1 captures the *current* shape of the relevant methods; the path from old → new isn't needed once it's shipped).
2. **Multi-step debugging traces** — examples to compress: iframe-blind a11y tree miss, ObjectId validation rejecting `_id="totalOpen"`, MongoSocketReadException after pool exhaustion. One line: *"Diagnosed <X> by <one-line method>; fix landed as <sha7>."*
3. **Cloud Build + rollout polling output** — collapse to: *"`<sha7>` ✅ build SUCCESS, rollout complete on dev/luz-docs."* Drop the build ID, the per-step `Waiting for 1 pods` chatter, the artifact registry tag re-statements.
4. **`luz-skill-flow-logs` dumps** — keep the anomaly counts (e.g. *"0× MongoSocketReadException, 2× /luz_adyen 5xx unrelated"*); drop the per-entry YAML.
5. **`luz-skill-materialize-stats` outputs** — keep the per-state numbers; drop the YAML formatting and the index list re-print (the index list is preserved separately at Layer 1, point 5).
6. **Phases considered then rejected** — examples: Phase 8 inline (named methods earn their keep at single call sites), Phase 4 cache CAS (luz-cache lacks the API). One line each: *"Phase N rejected: <reason>."*
7. **Long planning prose** — collapse to: *"Plan: Phase A (effort, why) → Phase B (effort, why) → … "*. Don't repeat the trade-off matrix unless it changed.

### Layer 3 — DISCARD
Drop entirely. None of this is consulted by the next iteration.

1. **System-reminder skill-list dumps** — the long `<system-reminder>` block listing every available skill that fires after every turn. Identical content each time.
2. **ToolSearch outputs** — schemas of deferred tools loaded just-in-time. They get loaded, get used once, become irrelevant.
3. **Playwright snapshot YAML pastes** — the accessibility tree dumps. Whatever data we needed is already extracted into the smoke-test report.
4. **Old session-resume summaries** — the long "this session is being continued from a previous conversation" preambles. The active state is in this conversation now, not the summary.
5. **Duplicate file listings** — re-runs of `ls ~/.claude/skills/` showing the same set we already know about.
6. **User-prompt echoes inside system-reminder envelopes** — the bot-emitted re-quote of the user message. The original user turn is enough.
7. **Routine `BUILD SUCCESS` from `mvn -o` checks** — assumed pass-through unless the build *failed*.
8. **Tool-call wrapper boilerplate** — `### Ran Playwright code` blocks, `### Page` URL re-statements when the URL didn't change.

## Output format

When invoked, the skill produces THREE artifacts in this order:

### 1. Compacted view — emit to chat AND persist to disk

A single fenced markdown block titled exactly:

```
# earchive-smart-compact — compacted view
```

Sections, in order:

1. **Active state** — Layer-1 preservation, ordered as above.
2. **Trail** — Layer-2 summaries, chronological, one line per item.
3. **Open work** — the unshipped phase items + any pending verification step.
4. **Compaction report**, exactly this shape:
   ```
   Compaction report
     before: ~<estimated tokens before> tokens (<turns> turns scanned)
     after:  ~<estimated tokens after>  tokens
     ratio:  <NN>% reduction
     preserved:  <N> method bodies / <N> SHAs / <N> mongo facts / <N> index defs
     summarized: <N> debug traces / <N> ship cycles / <N> log dumps
     discarded:  <N> reminders / <N> tool-search / <N> playwright YAML / <N> dup listings
   ```
   Estimate token counts at ~4 chars / token. Round to nearest hundred.

### 2. Persist the view to disk

Write the *exact* fenced block above to:

```
~/.claude/projects/<cwd-slug>/compact/earchive-smart-compact-<unix-ts>.md
```

(`<cwd-slug>` = current working directory with `/`, `\`, and `:` replaced by `-`. Create the `compact/` directory if missing.)

Prepend a one-line provenance header inside the file:
```
<!-- generated: <iso8601> · turns scanned: <N> · ratio: <NN>% -->
```

This step is mandatory. Without it, `/clear` deletes the compact view along with the rest of the conversation.

### 3. Reset instructions — print verbatim, last block of output

```
───────────────────────────────────────────────────────────────────
Compact written: <absolute path to the .md file>
To load only this view as the new context:
    1. /clear            — wipe the current conversation
    2. Read <absolute path>   — load the compact view as the first turn
The next message you send will run against ~<after-tokens> tokens
instead of the current ~<before-tokens> tokens.
───────────────────────────────────────────────────────────────────
```

## How to invoke

```
/earchive-smart-compact
```

No arguments. The skill reads the live conversation and applies the rules above.

## Rules for the compactor

- **Preservation is verbatim, not paraphrase.** If you change a code fence, you've broken the skill's contract. Even whitespace inside method bodies matters.
- **Order matters in Active state.** Method bodies first (most actionable), then SHAs, then stats doc shape, then Mongo numbers, then indexes, then open phases, then errors. Reading order matches reasoning order.
- **Trail is one line per item.** If a debugging story can't fit in one line, you're paraphrasing too little — boil it harder.
- **No editorialising.** Don't rate the work, don't add encouragement. The compactor's only job is structural filtering.
- **Don't invent.** If the conversation doesn't have a number you'd want to report, write `(unknown)`. Never fabricate to fill the template.
- **Don't compact this skill's own output.** If you see a previous `# earchive-smart-compact — compacted view` in scrollback, treat it as already-compacted; carry it forward verbatim, don't re-process.
- **Always emit all three artifacts.** Skipping the persist step makes the compaction useless after `/clear`. Skipping the reset block leaves the user holding a long context and not knowing how to drop it.

## Why the persist-and-clear mechanism matters

A compact view that lives only in scrollback **does not save tokens** — it sits at the *end* of the bloated context. Every subsequent turn still pays for the full preceding noise. The only way to reclaim window space is `/clear` followed by a re-ingest of the compact view.

Three constraints shape the design:

1. **Skills cannot run `/clear` themselves.** It's a user-initiated harness command. The skill therefore prints the *exact* command sequence the user must run, and stops.
2. **The compact view must outlive `/clear`.** That means writing it to disk *before* asking the user to clear. The path lives under `~/.claude/projects/<cwd-slug>/compact/` so multiple compactions can co-exist (timestamped) and grep across the cwd-slug.
3. **The reset instruction names absolute paths.** Pasting `/clear` then typing `Read ~/...` works. Telling the user to "remember the compacted view" doesn't.

## Notes for the orchestrator

- The compaction ratio is the headline product. If the ratio drops below 60%, the conversation didn't have much noise to begin with — print the ratio honestly and stop. Don't pad the output.
- If the user later runs `/earchive-smart-compact` a second time on a longer scrollback, the prior compacted view is the *new* baseline; only new turns since then need processing.
- After running `/clear` + `Read <path>`, the conversation is the compact view + nothing else. Subsequent turns build on a clean foundation; the next iteration of materialise work pays only for the current state, not the path that got there.
