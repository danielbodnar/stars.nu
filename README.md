# stars.nu

[![Version](https://img.shields.io/badge/version-3.0.0-blue)](./mod.nu)
[![Nushell](https://img.shields.io/badge/nushell-0.110.0%2B-4e9950)](https://nushell.sh)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

A comprehensive Nushell module for managing GitHub starred repositories. Sync from GitHub, import from browser bookmarks and awesome lists, store locally in SQLite, search and filter interactively, and export to multiple formats with optional Polars analytics.

---

## Features

- **Multi-source sync** — GitHub (paginated, rate-limit aware), Firefox bookmarks, Chrome bookmarks, awesome lists
- **Incremental sync** — fetches only new stars since last sync; auto-escalates to full sync every 7 days
- **SQLite-backed storage** — fast offline queries, XDG-compliant paths, automatic backups
- **Rich search** — case-insensitive regex across name, description, language, and topics
- **Smart default filters** — excludes archived repos, stale repos (>365 days), and configurable languages
- **Multiple export formats** — CSV, JSON, NUON, Markdown, Firefox bookmarks HTML, Chrome bookmarks HTML
- **Polars integration** — optional LazyFrame/DataFrame operations for high-performance analytics
- **ANSI table output** — colorized language badges, clickable terminal links, truncated descriptions
- **Auto-migration** — seamlessly migrates from the legacy `gh-stars` path on first use

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| [Nushell](https://nushell.sh) | `0.110.0+` | Required |
| [gh CLI](https://cli.github.com) | any | Required for GitHub sync; must be authenticated |
| [nu_plugin_polars](https://github.com/nushell/nushell/tree/main/crates/nu_plugin_polars) | any | Optional — enables `--dataframe` / `--lazyframe` |

Authenticate the `gh` CLI before syncing:

```nushell
gh auth login
```

---

## Installation

### As a Nushell module (recommended)

```nushell
# Clone to your Nushell module directory
git clone https://github.com/danielbodnar/stars.nu ~/.config/nushell/modules/stars

# Load in your config.nu
use ~/.config/nushell/modules/stars *

# Or load per-session
use ~/.config/nushell/modules/stars/mod.nu *
```

### From the repo root (development)

```nushell
git clone https://github.com/danielbodnar/stars.nu
cd stars.nu
use mod.nu *
```

### As a `gh` extension

```nushell
# Symlink the wrapper script into gh's extension path
ln -s /path/to/stars.nu/mod.nu ~/.local/bin/gh-stars

# Then invoke via gh
gh stars
gh stars sync
```

---

## Quick Start

```nushell
# Initialize configuration
stars config init

# Sync starred repos from GitHub (requires gh auth login)
stars sync

# Browse all stars in a colorized table
stars

# Search by keyword
stars "rust cli"

# Filter to a specific language and show JSON
stars --json | where language == "TypeScript"

# See top repos by star count
stars --sort stars --limit 20

# Export to CSV
stars export csv

# Show language statistics
stars stats
```

---

## Commands

### `stars` — Browse and search

```
stars [query?]
```

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--json` | | flag | | Output as JSON |
| `--csv` | | flag | | Output as CSV |
| `--md` | | flag | | Output as Markdown table |
| `--nuon` | | flag | | Output as NUON (Nushell native format) |
| `--dataframe` | | flag | | Output as Polars DataFrame *(requires nu_plugin_polars)* |
| `--lazyframe` | | flag | | Output as Polars LazyFrame *(requires nu_plugin_polars)* |
| `--raw` | | flag | | Raw database output (all columns, no formatting) |
| `--no-defaults` | | flag | | Skip default filters (archived, stale, excluded languages) |
| `--columns` | `-c` | `list<string>` | config | Columns to display |
| `--limit` | `-l` | `int` | all | Maximum rows to return |
| `--sort` | `-s` | `string` | `stars` | Sort field: `stars`, `forks`, `pushed`, `created`, `name`, `language` |
| `--reverse` | `-r` | flag | | Reverse sort order |

```nushell
# Examples
stars                                     # All stars, default filters
stars "nushell"                           # Search for "nushell"
stars --no-defaults                       # All stars, no filters
stars --sort pushed --limit 10            # 10 most recently pushed
stars --columns [name language stars]     # Custom column set
stars --json | where stars > 1000         # Stars with 1k+ GitHub stars
```

---

### `stars sync` — Fetch from GitHub

```
stars sync
stars sync github
```

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--full` | | flag | | Force full re-fetch (ignore incremental state) |
| `--backup` | | flag | | Create a timestamped backup before syncing |
| `--no-cache` | | flag | | Bypass `gh` CLI response cache |
| `--user` | `-u` | `string` | current user | GitHub username to fetch stars for |

```nushell
stars sync                    # Incremental sync (new stars only)
stars sync --full             # Re-fetch all stars from scratch
stars sync --backup --full    # Full sync with backup first
stars sync github --user octocat  # Fetch another user's stars
```

Sync behavior:
- **Incremental** (default): fetches pages until it encounters a star older than the last sync timestamp. Stops early once caught up.
- **Full escalation**: automatically runs a full sync when `last_full_sync_at` exceeds `sync.github.full_sync_interval_days` (default: 7).
- **Metadata**: tracked in a `sync_metadata` table in the same SQLite database.

---

### `stars config` — Configuration management

```
stars config [subcommand?]
```

| Subcommand | Description |
|---|---|
| *(none)* | Show current configuration |
| `init [--force]` | Initialize with defaults (overwrites if `--force`) |
| `get <key>` | Get a config value using dot notation |
| `set <key> <value>` | Set a config value |
| `reset [--key <key>]` | Reset all config or a specific key to defaults |
| `edit` | Open config file in `$EDITOR` |
| `path` | Print the config file path |
| `validate` | Validate the current configuration |

```nushell
stars config                                   # Show config
stars config init                              # Create default config
stars config get defaults.filters.exclude_archived
stars config set defaults.sort_by "pushed"
stars config set defaults.filters.min_pushed_days 180
stars config edit                              # Open in $EDITOR
stars config path                              # e.g. ~/.config/stars/config.nu
```

---

### `stars export` — Export to files

```
stars export <format>
```

#### `stars export csv`

| Flag | Short | Description |
|---|---|---|
| `--output` | `-o` | Output file path (default: `~/.local/share/.stars/exports/stars.csv`) |
| `--columns` | `-c` | Columns to include |

#### `stars export json`

| Flag | Short | Description |
|---|---|---|
| `--output` | `-o` | Output file path (default: `stars.json`) |
| `--minimal` | `-m` | Minimal schema: name, url, description, language, topics only |
| `--pretty` | `-p` | Pretty-print with indentation |

#### `stars export nuon`

| Flag | Short | Description |
|---|---|---|
| `--output` | `-o` | Output file path |

#### `stars export md`

| Flag | Short | Description |
|---|---|---|
| `--output` | `-o` | Output file path |
| `--columns` | `-c` | Columns to include |

#### `stars export firefox` / `stars export chrome`

| Flag | Short | Description |
|---|---|---|
| `--output` | `-o` | Output HTML file path |
| `--group-by` | `-g` | Grouping strategy: `language`, `owner`, `topic`, `year`, `none` |
| `--include-archived` | | Include archived repos (excluded by default) |
| `--include-forks` | | Include forked repos (excluded by default) |

```nushell
stars export csv -o ~/Desktop/stars.csv
stars export json --pretty --minimal
stars export firefox --group-by language -o ~/bookmarks.html
stars export chrome --group-by owner
stars export md -o ~/stars.md
```

---

### `stars stats` — Summary statistics

```
stars stats
```

Displays a summary including:
- Total stars in the database
- Breakdown by programming language
- Top repository owners
- Most-starred repositories

---

### `stars version` / `stars help`

```nushell
stars version     # Module version, Nushell version, Polars availability
stars help        # Detailed usage help
```

---

## Configuration Reference

**Location:** `$XDG_CONFIG_HOME/stars/config.nu` (typically `~/.config/stars/config.nu`)

**Format:** NUON (Nushell Object Notation)

```nushell
{
    version: "3.0.0"

    storage: {
        db_path: null          # null = use XDG default (~/.local/share/.stars/stars.db)
        backup_on_sync: false  # Auto-backup before every sync
    }

    defaults: {
        filters: {
            exclude_languages: [PHP, "C#", Java, Python, Ruby]  # Languages to hide
            exclude_archived: true                               # Hide archived repos
            exclude_forks: false                                 # Show forked repos
            min_pushed_days: 365                                 # Hide repos not pushed in N days
        }
        columns: [owner, name, language, stars, pushed, homepage, topics, description, forks, issues]
        sort_by: "stars"        # Default sort: stars | forks | pushed | created | name | language
        sort_reverse: true      # Descending by default
    }

    output: {
        default_format: "table"
        table: {
            max_description_length: 240  # Truncate descriptions at N chars
            clickable_links: true        # OSC 8 terminal hyperlinks
            colorize_languages: true     # ANSI color per language
        }
    }

    sync: {
        sources: [github]
        github: {
            per_page: 100                # Results per API page (max 100)
            cache_duration: "1h"         # gh CLI cache TTL
            full_sync_interval_days: 7   # Days between forced full syncs
        }
    }
}
```

### Key config fields

| Key | Type | Description |
|---|---|---|
| `storage.db_path` | `string\|null` | Custom SQLite path; `null` uses XDG default |
| `storage.backup_on_sync` | `bool` | Auto-backup before syncing |
| `defaults.filters.exclude_languages` | `list<string>` | Languages to exclude from output |
| `defaults.filters.exclude_archived` | `bool` | Hide archived repositories |
| `defaults.filters.exclude_forks` | `bool` | Hide forked repositories |
| `defaults.filters.min_pushed_days` | `int` | Hide repos inactive for N+ days |
| `defaults.sort_by` | `string` | Default sort field |
| `defaults.columns` | `list<string>` | Default display columns |
| `sync.github.full_sync_interval_days` | `int` | Days before forcing a full re-fetch |
| `output.table.clickable_links` | `bool` | Terminal OSC 8 hyperlinks |

---

## Data Schema

Every star record — regardless of source — is normalized to this schema:

| Field | Type | SQLite Type | Description |
|---|---|---|---|
| `id` | `int` | `INTEGER` | Auto-incremented primary key |
| `owner` | `string` | `TEXT` | Repository owner login |
| `name` | `string` | `TEXT` | Repository name |
| `full_name` | `string` | `TEXT` | `owner/name` |
| `description` | `string?` | `TEXT` | Repository description |
| `url` | `string` | `TEXT` | GitHub HTML URL |
| `homepage` | `string?` | `TEXT` | Project homepage URL |
| `language` | `string?` | `TEXT` | Primary programming language |
| `topics` | `list<string>` | `TEXT (JSON)` | Repository topics — stored as JSON, returned as list |
| `stars` | `int` | `INTEGER` | GitHub stargazers count |
| `forks` | `int` | `INTEGER` | Fork count |
| `issues` | `int` | `INTEGER` | Open issues count |
| `pushed_at` | `datetime?` | `TEXT` | Last push timestamp (ISO 8601) |
| `created_at` | `datetime?` | `TEXT` | Repository creation timestamp |
| `updated_at` | `datetime?` | `TEXT` | Last update timestamp |
| `archived` | `bool` | `INTEGER (0/1)` | Whether the repo is archived |
| `fork` | `bool` | `INTEGER (0/1)` | Whether this is a fork |
| `license` | `string?` | `TEXT` | License SPDX identifier |
| `source` | `string` | `TEXT` | Data origin: `github`, `firefox`, `chrome`, `awesome`, `manual` |
| `synced_at` | `datetime` | `TEXT` | When this record was last synced |
| `starred_at` | `datetime?` | `TEXT` | When the authenticated user starred it (GitHub only) |

> **SQLite quirks:** `archived` and `fork` are stored as integers (`0`/`1`), not booleans. `topics` is a JSON-encoded string — use `| from json` before list operations when querying the raw database.

---

## Export Formats

| Format | Command | Use case |
|---|---|---|
| **Table** | `stars` | Interactive terminal browsing |
| **JSON** | `stars export json` | Programmatic processing, APIs |
| **CSV** | `stars export csv` | Spreadsheets, data analysis |
| **NUON** | `stars export nuon` | Nushell pipelines |
| **Markdown** | `stars export md` | Documentation, GitHub wikis |
| **Firefox HTML** | `stars export firefox` | Import into Firefox bookmarks |
| **Chrome HTML** | `stars export chrome` | Import into Chrome bookmarks |

Browser bookmark exports can be grouped by `language`, `owner`, `topic`, `year`, or left flat (`none`).

---

## Polars / DataFrame Integration

When `nu_plugin_polars` is installed, `stars` gains high-performance analytical capabilities:

```nushell
# Load as a LazyFrame (deferred execution, efficient)
stars --lazyframe

# Load as a materialized DataFrame
stars --dataframe

# Chain Polars operations directly
stars --lazyframe
    | polars filter ((polars col language) == (polars lit "Rust"))
    | polars sort-by stars --descending
    | polars collect
```

The `core/data.nu` module provides convenience LazyFrame operations:

```nushell
# Top repos by stars
stars --lazyframe | polars sort-by stars --descending | polars head 10 | polars collect

# Language distribution
stars --lazyframe
    | polars group-by language
    | polars agg [(polars col name | polars count | polars as count)]
    | polars sort-by count --descending
    | polars collect
```

> Polars is entirely optional — all core sync, search, filter, and export features work without it.

---

## Storage & XDG Paths

The module follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html):

| Path | Purpose |
|---|---|
| `$XDG_DATA_HOME/.stars/stars.db` | SQLite database (main `stars` table) |
| `$XDG_DATA_HOME/.stars/backups/` | Timestamped `.db` backup files |
| `$XDG_DATA_HOME/.stars/exports/` | Default export output directory |
| `$XDG_CONFIG_HOME/stars/config.nu` | NUON configuration file |

On most Linux systems, `$XDG_DATA_HOME` defaults to `~/.local/share` and `$XDG_CONFIG_HOME` defaults to `~/.config`.

**Auto-migration:** On first run, the module checks for a legacy `gh-stars` database at `$XDG_DATA_HOME/gh-stars/stars.db` and migrates it to the new path automatically.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     mod.nu (entry point)                  │
│   stars • stars sync • stars config • stars export        │
│   stars stats • stars version • stars help                │
└────────────┬─────────────┬────────────┬──────────────────┘
             │             │            │
    ┌────────▼───┐  ┌──────▼───┐  ┌────▼──────────┐
    │ commands/  │  │ adapters/│  │  formatters/  │
    │ config.nu  │  │ github   │  │  table.nu     │
    │ export.nu  │  │ firefox  │  │  json.nu      │
    │ sync.nu    │  │ chrome   │  │  dataframe.nu │
    │ stats.nu   │  │ awesome  │  └───────────────┘
    └────────────┘  └──────────┘
             │             │
    ┌────────▼─────────────▼───────┐
    │           core/              │
    │  storage.nu  (SQLite CRUD)   │
    │  types.nu    (validation)    │
    │  data.nu     (Polars ops)    │
    └──────────────────────────────┘
             │
    ┌────────▼────────────────────┐
    │  ~/.local/share/.stars/     │
    │  stars.db  (SQLite)         │
    └─────────────────────────────┘
```

### Data flow

```
gh CLI (GitHub API)          Firefox / Chrome bookmarks
        │                              │
        ▼                              ▼
adapters/github.nu           adapters/firefox.nu
  fetch --since <ts>          adapters/chrome.nu
        │                              │
        └──────────────┬───────────────┘
                       ▼
              core/storage.nu
                store $data
                       │
                       ▼
              core/storage.nu
                load []  →  SELECT * FROM stars
                       │
                       ▼
         filters/defaults.nu  (exclude_archived, etc.)
                       │
                       ▼
     formatters/table.nu  │  json.nu  │  dataframe.nu
                       │
                       ▼
                   Output
```

---

## Development

### Running tests

```nushell
nu tests/main.test.nu              # Full test suite
nu tests/main.test.nu --test "filter"   # Run a specific test category
nu tests/main.test.nu --verbose    # Verbose output
```

### Validating scripts

```nushell
nu --ide-check mod.nu
nu-lint mod.nu
```

### Module loading (development)

```nushell
# From the repo root
use mod.nu *
```

### Adding a new command

1. Implement the function in the appropriate submodule under `commands/`, `adapters/`, or `formatters/`
2. Add type annotations and `--help` description to the signature
3. Export from `mod.nu` (either inline or via `use ... *`)
4. Write tests in `tests/main.test.nu`
5. Update this README

### Error handling convention

All user-facing errors use structured `error make` with span hints and actionable help text:

```nushell
error make {
    msg: "stars: database not found"
    label: { text: "path checked", span: (metadata $db_path).span }
    help: "Run `stars sync` to initialize the database"
}
```

---

## License

MIT — see [LICENSE](./LICENSE)
