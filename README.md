# stars.nu

A comprehensive Nushell module for managing starred repositories from multiple sources — GitHub, Firefox bookmarks, Chrome bookmarks, and awesome lists — with SQLite-backed storage, Polars analytics, and multiple export formats.

## Features

- Sync stars from GitHub (all pages, rate-limit aware)
- Import bookmarks from Firefox and Chrome
- Parse awesome lists
- SQLite-backed local storage for fast offline queries
- Search by name, description, language, or topic
- Export to CSV, JSON, Firefox bookmarks, and more
- Analytics via Polars (top languages, trending topics, star counts)

## Quick Start

```nushell
# Load the module
use stars *

# Sync stars from GitHub (requires GITHUB_TOKEN)
stars sync

# Browse all starred repos
stars

# Search
stars "rust cli"

# Filter by language
stars --json | from json | where language == "Rust"

# Export
stars export csv
stars export firefox
```

## Module Structure

```
stars.nu/
├── mod.nu          # Main entry point and exports
├── core/
│   ├── types.nu    # Type definitions and schemas
│   ├── storage.nu  # SQLite persistence layer
│   └── data.nu     # Data fetching and normalization
├── commands/
│   ├── sync.nu     # GitHub sync command
│   ├── stats.nu    # Analytics and statistics
│   ├── export.nu   # Export formatters
│   └── config.nu   # Configuration management
├── adapters/       # Source-specific adapters (GitHub, bookmarks, awesome lists)
├── filters/        # Query and filtering utilities
├── formatters/     # Output formatters
└── tests/          # Test suite
```

## Requirements

- Nushell 0.107+
- `GITHUB_TOKEN` environment variable (for syncing)
- SQLite (bundled with Nushell)
