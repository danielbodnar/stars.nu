# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`stars.nu` is a Nushell module (v3.0.0) for managing GitHub starred repositories. It syncs from GitHub via the `gh` CLI, stores in SQLite, and outputs to table/JSON/CSV/Markdown/Polars DataFrame.

## Development Commands

```nushell
# Run all tests
nu tests/main.test.nu

# Run a specific test category
nu tests/main.test.nu --test "filter"
nu tests/main.test.nu --test "search"
nu tests/main.test.nu --verbose

# Validate a script
nu --ide-check mod.nu
nu-lint mod.nu

# Load module from repo root (for manual testing)
use mod.nu *
```

## Architecture

### Entry Point and Command Structure

`mod.nu` is the single entry point and re-exports everything. It defines these commands **inline**:
- `main` (= `stars [query]`) — load, filter, search, sort, format output
- `stars sync` / `stars sync github` — fetch via `gh` CLI, delegate to `adapters/github.nu`
- `stars stats` — compute language/owner distributions via `core/storage.nu`
- `stars version` / `stars help`

Two submodules are **glob-exported** (their commands become top-level `stars *` subcommands):
- `commands/config.nu` → `stars config [init|show|get|set|reset|edit|path|validate]`
- `commands/export.nu` → `stars export [csv|json|nuon|md|firefox|chrome]`

The other files in `commands/` (`sync.nu`, `stats.nu`) and `adapters/` (`firefox.nu`, `chrome.nu`, `awesome.nu`) and `filters/defaults.nu` and `core/data.nu` exist as **planned submodule implementations** but are not yet imported in `mod.nu`.

### Data Flow

```
gh CLI (GitHub API)
    ↓
adapters/github.nu → fetch []  (paginated, optional cache)
    ↓
core/storage.nu → store $data --replace  (into sqlite)
    ↓
core/storage.nu → load []  (query db SELECT * FROM stars)
    ↓
mod.nu: apply-default-filters / search-data / sort-data
    ↓
formatters/{table,json,dataframe}.nu → output
```

### Storage (XDG-compliant)

| Path | Purpose |
|------|---------|
| `$XDG_DATA_HOME/.stars/stars.db` | SQLite database (`stars` table) |
| `$XDG_DATA_HOME/.stars/backups/` | Timestamped `.db` backups |
| `$XDG_DATA_HOME/.stars/exports/` | Export output files |
| `$XDG_CONFIG_HOME/stars/config.nu` | NUON config file |

### SQLite Schema Gotchas

- `archived` and `fork` columns are stored as **integers** (0/1), not booleans. Always check both: `if ($val | describe) == "bool" { $val } else { $val == 1 }`.
- `topics` is a **JSON-encoded string** in the database, not a native list. Use `| from json` before list operations.
- The database table is named `stars`. Load with: `open $db_path | query db "SELECT * FROM stars"`.

### Error Pattern

All errors use structured `error make` with span hints:

```nushell
error make {
    msg: "Human-readable message"
    label: {text: "hint", span: (metadata $var).span}
    help: "Actionable suggestion"
}
```

### Default Filters (applied unless `--no-defaults`)

- Exclude archived repos
- Exclude repos not pushed in 365+ days
- Exclude languages: PHP, C#, Java, Python, Ruby
- Forks excluded only when `exclude_forks: true` in config

### Dependencies

- **Nushell 0.110.0+** with `std/assert` (for tests)
- **`gh` CLI** authenticated via `gh auth login`
- **`nu_plugin_polars`** — optional, required for `--dataframe` / `--lazyframe` flags

### Migration

On first use, `mod.nu` auto-migrates from the legacy `gh-stars` path:
- Old: `$XDG_DATA_HOME/gh-stars/stars.db`
- New: `$XDG_DATA_HOME/.stars/stars.db`
