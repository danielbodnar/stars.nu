# Plan: Incremental GitHub Sync

**Goal:** Only fetch repos starred/changed since the last sync, rather than fetching and replacing all stars on every sync.

---

## Problem Statement

Current `stars sync` does a full paginated fetch of all starred repos (~N × 100-item API pages) and replaces the entire SQLite database. For users with 1,000+ stars this means:
- Dozens of API calls per sync
- gh CLI cache is the only mitigation (stale by 1h)
- No way to detect just "what changed"

---

## GitHub API Capabilities

The `GET /user/starred` endpoint supports:
- `sort=created` — sorted by when user starred (default), or `sort=updated` for repo activity
- `direction=desc` — newest first (what we want for early-stop)
- `Accept: application/vnd.github.star+json` — returns `{starred_at, repo}` envelope instead of bare repo, giving us the exact timestamp the user starred each repo
- No native `since=` query parameter — we must implement early-stop ourselves

---

## Architecture

### New column: `starred_at`

Add to the `stars` SQLite table. Populated via the `star+json` media type.
This is different from `synced_at` (when we ran sync) — it's when the *user* starred the repo.

### New table: `sync_metadata`

Single-row SQLite table for sync state:

```sql
CREATE TABLE IF NOT EXISTS sync_metadata (
    key   TEXT PRIMARY KEY,
    value TEXT
);
```

Keys:
- `last_synced_at` — ISO-8601 datetime of last successful sync completion
- `last_full_sync_at` — ISO-8601 datetime of last full (--full) sync

### Storage: `core/storage.nu`

Add three functions:

**`upsert`** — replaces the full `store --replace` call for incremental sync:
```nushell
export def upsert [data: table]: nothing -> nothing {
    # Uses SQLite INSERT OR REPLACE semantics via into sqlite
    # or per-row query db "INSERT OR REPLACE INTO stars ..."
}
```

**`get-sync-meta`** / **`set-sync-meta`**:
```nushell
export def get-sync-meta [key: string]: nothing -> string
export def set-sync-meta [key: string, value: string]: nothing -> nothing
```

**`remove-by-ids`** — for full sync unstar detection:
```nushell
export def remove-by-ids [keep_ids: list<int>]: nothing -> int
# Deletes rows whose id is NOT IN keep_ids, returns count deleted
```

**Update `get-paths`** return type to include no new paths (metadata lives in same DB).

### Schema: `core/types.nu`

Add `starred_at` field to `star-schema` and `polars-schema`:

```nushell
starred_at: { type: datetime, nullable: true, description: "When the user starred this repo" }
```

Add it to `all-columns`. Do NOT add to `default-columns` (display noise).

### Adapter: `adapters/github.nu`

**Update `fetch`** — add `--since` param and starred_at extraction:

```nushell
export def fetch [
    --user (-u): string
    --per-page: int = 100
    --use-cache
    --cache-duration: string = "1h"
    --since: datetime     # NEW: stop fetching pages older than this
]: nothing -> table
```

**Update `fetch-page`** — add `Accept` header:
```nushell
gh api $url --header 'Accept: application/vnd.github.star+json' ...
```

Response shape changes from `[repo, ...]` to `[{starred_at, repo}, ...]`. Update `process-page` to extract both fields.

**Early-stop logic** in the `generate` loop:
```nushell
# After processing a page, check if all items are older than --since
let oldest_on_page = $normalized | get starred_at | into datetime | math min
if ($oldest_on_page < $since) {
    # Filter to only items newer than since, then stop
    let new_only = $normalized | where { ($in.starred_at | into datetime) >= $since }
    {out: {stars: $new_only, ...done: true}}
}
```

**Update `normalize-repo`** — accept `starred_at` from envelope:
```nushell
export def normalize-repo [repo: record, starred_at?: string]: nothing -> record {
    ...
    starred_at: ($starred_at | default null)
}
```

### Sync command: `mod.nu`

**`stars sync` / `stars sync github`** — add `--full` flag:

```nushell
export def "stars sync" [
    --backup
    --no-cache
    --full      # NEW: full re-fetch + unstar detection (ignores --since)
]: nothing -> nothing
```

**Incremental flow (default)**:
```
1. Read last_synced_at from sync_metadata table
2. If no last_synced_at → fall back to --full behavior
3. fetch --since $last_synced_at
4. If 0 new stars → print "Already up to date", return
5. upsert new/changed stars into DB
6. set-sync-meta "last_synced_at" (date now | format date ...)
7. Print: "Synced N new/updated stars (M total)"
```

**Full sync flow (`--full`)**:
```
1. fetch (no --since, all pages)
2. store --replace (existing behavior)
3. Optionally: compare fetched IDs against DB, remove unstarred
4. set-sync-meta "last_synced_at" and "last_full_sync_at"
5. Print: "Full sync complete: N stars"
```

**Auto-full escalation** (optional, config-driven):
```nushell
# In config: sync.github.full_sync_interval_days = 7
# If last_full_sync_at > N days ago → escalate to full sync automatically
```

---

## Config Changes (`commands/config.nu`)

Add `full_sync_interval_days` to the sync config block:

```nushell
sync: {
    sources: [github]
    github: {
        per_page: 100
        cache_duration: "1h"
        full_sync_interval_days: 7   # NEW: auto-escalate to full sync weekly
    }
}
```

---

## Implementation Order

1. **`core/storage.nu`** — add `upsert`, `get-sync-meta`, `set-sync-meta`, `remove-by-ids`
2. **`core/types.nu`** — add `starred_at` to schema and `all-columns`
3. **`adapters/github.nu`** — add `Accept` header, `starred_at` extraction, `--since` early-stop
4. **`commands/config.nu`** — add `full_sync_interval_days` default
5. **`mod.nu`** — update `stars sync` and `stars sync github` with `--full` flag and incremental logic
6. **`tests/main.test.nu`** — add tests for incremental fetch, early-stop, upsert, sync metadata

---

## Edge Cases

| Case | Handling |
|------|---------|
| First-ever sync (no `last_synced_at`) | Falls back to full sync automatically |
| User unstarred repos between syncs | Not detected by incremental; caught on next `--full` or auto-escalation |
| Repo metadata changed (stars, description) but not re-starred | Incremental misses it; `--full` catches it |
| `--since` older than gh cache TTL | Cache still served; `--no-cache` flag to force fresh |
| Empty incremental result | Print "Already up to date", exit cleanly |
| Partial page at early-stop boundary | Filter page to items `>= since` before upsert |
| DB doesn't have `starred_at` column (existing installs) | `ALTER TABLE stars ADD COLUMN starred_at TEXT` migration in `ensure-storage` |

---

## Migration

Existing databases lack the `starred_at` column. Add to `ensure-storage`:

```nushell
# Add starred_at column if it doesn't exist (idempotent)
try {
    open $paths.db_path | query db "ALTER TABLE stars ADD COLUMN starred_at TEXT"
} catch { } # Ignore "duplicate column" error

# Create sync_metadata table if it doesn't exist
open $paths.db_path | query db "
    CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT
    )
"
```

---

## Files Changed Summary

| File | Change |
|------|--------|
| `core/storage.nu` | +`upsert`, +`get-sync-meta`, +`set-sync-meta`, +`remove-by-ids`, update `ensure-storage` for migration |
| `core/types.nu` | +`starred_at` field in schemas |
| `adapters/github.nu` | +`Accept` header, +`starred_at` extraction, +`--since` early-stop in `fetch` |
| `commands/config.nu` | +`full_sync_interval_days` default |
| `mod.nu` | Update `stars sync` + `stars sync github` with `--full` and incremental logic |
| `tests/main.test.nu` | New test cases for above |
