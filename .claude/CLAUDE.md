# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The `stars` module is a comprehensive Nushell package for managing GitHub starred repositories. It provides a unified interface for fetching, storing, analyzing, and exporting starred repositories from multiple sources (GitHub, Firefox, Chrome, awesome lists) with SQLite-backed storage and Polars DataFrame support for high-performance analytics.

Version: 3.0.0 (refactored from gh-stars)

## Architecture

### Directory Structure

```
~/.config/nushell/modules/stars/
├── mod.nu                    # Entry point, re-exports, main command
├── core/
│   ├── types.nu              # Type schemas, validation helpers
│   ├── storage.nu            # SQLite persistence layer
│   └── data.nu               # Polars LazyFrame operations
├── commands/
│   ├── config.nu             # stars config [init|show|edit|get|set]
│   ├── sync.nu               # stars sync [github|firefox|chrome|awesome]
│   ├── export.nu             # stars export [csv|json|md|firefox|chrome]
│   └── stats.nu              # stars stats, group, top, recent
├── formatters/
│   ├── table.nu              # Human-readable table with ANSI colors
│   ├── json.nu               # JSON, CSV, NUON, Markdown formatters
│   └── dataframe.nu          # Polars DataFrame conversion
├── adapters/
│   ├── github.nu             # GitHub API adapter
│   ├── firefox.nu            # Firefox bookmarks adapter
│   ├── chrome.nu             # Chrome bookmarks adapter
│   └── awesome.nu            # Awesome list parser
├── filters/
│   └── defaults.nu           # Default filter implementations
├── tests/
│   └── main.test.nu          # Test suite
└── .claude/
    └── CLAUDE.md             # This file
```

### Data Flow

```
Sources (GitHub/Firefox/Chrome/Awesome)
    ↓
Adapters (normalize to schema)
    ↓
Storage (SQLite: ~/.local/share/.stars/stars.db)
    ↓
Data Layer (Polars LazyFrame)
    ↓
Filters (exclude archived, old, languages)
    ↓
Formatters (table/json/csv/md/dataframe)
    ↓
Output
```

### Storage Locations (XDG-compliant)

| Path | Purpose |
|------|---------|
| `$XDG_CONFIG_HOME/stars/config.nu` | User configuration (NUON) |
| `$XDG_DATA_HOME/.stars/stars.db` | SQLite database |
| `$XDG_DATA_HOME/.stars/backups/` | Timestamped backups |
| `$XDG_DATA_HOME/.stars/exports/` | Export output files |

## Command Reference

### Main Commands

```nushell
stars                           # Show all stars (beautiful table)
stars "query"                   # Search stars
stars --json                    # Output as JSON
stars --csv                     # Output as CSV
stars --dataframe               # Output as Polars DataFrame
stars --lazyframe               # Output as Polars LazyFrame
stars version                   # Show version info
```

### Sync Commands

```nushell
stars sync                      # Sync from all configured sources
stars sync github               # Sync from GitHub API
stars sync firefox              # Import from Firefox bookmarks
stars sync chrome               # Import from Chrome bookmarks
stars sync awesome <url>        # Import from awesome list
```

### Config Commands

```nushell
stars config                    # Show current configuration
stars config init [--force]     # Initialize with defaults
stars config edit               # Open in $EDITOR
stars config get <key>          # Get value (dot notation)
stars config set <key> <value>  # Set value
stars config reset              # Reset to defaults
```

### Export Commands

```nushell
stars export csv [-o path]      # Export to CSV
stars export json [-o path]     # Export to JSON
stars export md [-o path]       # Export to Markdown
stars export firefox [-o path]  # Export to Firefox bookmarks HTML
stars export chrome [-o path]   # Export to Chrome bookmarks HTML
```

### Stats Commands

```nushell
stars stats                     # Show statistics
stars group --by language       # Group by field
stars top --by stars --limit 20 # Top repositories
stars recent --days 30          # Recently updated
stars untagged                  # Repos without topics
stars report                    # Generate full report
```

## Default Filters

The module applies these filters by default (configurable):

- Exclude repos not pushed in 365+ days
- Exclude archived repos
- Exclude languages: PHP, C#, Java, Python, Ruby

Use `--no-defaults` to skip these filters.

## Dependencies

- **Nushell 0.100.0+**
- **gh CLI** (authenticated)
- **nu_plugin_polars** (optional, for DataFrame operations)

## Development

### Loading the Module

```nushell
use ~/.config/nushell/modules/stars *
```

### Running Tests

```nushell
nu tests/main.test.nu
nu tests/main.test.nu --test "filter"
```

### Adding New Commands

1. Create function in appropriate submodule
2. Add type signatures and documentation
3. Export from mod.nu
4. Add tests
5. Update this CLAUDE.md

### Error Pattern

```nushell
error make {
    msg: "Human-readable message"
    label: {text: "hint", span: (metadata $var).span}
    help: "Suggestion"
}
```

## gh Extension

The module works as a `gh` CLI extension via `~/.local/bin/gh-stars`:

```bash
gh stars                        # Same as: stars
gh stars sync github            # Same as: stars sync github
gh-stars config                 # Direct invocation
```

## Migration from gh-stars

The module auto-migrates from the legacy `gh-stars` location on first use:
- Old: `$XDG_DATA_HOME/gh-stars/stars.db`
- New: `$XDG_DATA_HOME/.stars/stars.db`
