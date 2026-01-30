#!/usr/bin/env nu

# ============================================================================
# Stars Module - Main Entry Point
# ============================================================================
#
# A comprehensive Nushell module for managing starred repositories from
# multiple sources (GitHub, Firefox bookmarks, Chrome bookmarks, awesome
# lists) with SQLite-backed storage, Polars analytics, and multiple
# export formats.
#
# # Quick Start
#
# ```nushell
# # Load the module
# use stars
#
# # Sync stars from GitHub
# stars sync
#
# # Show all stars with beautiful table output
# stars
#
# # Search for repositories
# stars "rust cli"
#
# # Filter by language
# stars --json | from json | where language == "Rust"
#
# # Export to various formats
# stars export csv
# stars export firefox
# ```
#
# # Available Commands
#
# ## Main Commands
# - `stars` - Display starred repositories (with optional search query)
# - `stars version` - Show version information
# - `stars help` - Show detailed help
#
# ## Configuration
# - `stars config` - Show current configuration
# - `stars config init` - Initialize configuration file
# - `stars config get <key>` - Get a config value
# - `stars config set <key> <value>` - Set a config value
# - `stars config reset` - Reset configuration to defaults
# - `stars config edit` - Edit configuration in $EDITOR
# - `stars config path` - Show config file path
# - `stars config validate` - Validate configuration
#
# ## Sync Commands
# - `stars sync` - Sync stars from all configured sources
# - `stars sync github` - Sync from GitHub API
#
# ## Export Commands
# - `stars export csv` - Export to CSV format
# - `stars export json` - Export to JSON format
# - `stars export nuon` - Export to NUON format
# - `stars export md` - Export to Markdown table
# - `stars export firefox` - Export to Firefox bookmarks HTML
# - `stars export chrome` - Export to Chrome bookmarks HTML
#
# ## Analytics (requires Polars)
# - `stars stats` - Show statistics about starred repos
# - Use `--dataframe` or `--lazyframe` flags for Polars output
#
# # Dependencies
# - Nushell 0.100.0+
# - gh CLI (for GitHub sync) - `gh auth login` for authentication
# - nu_plugin_polars (optional) - for DataFrame/LazyFrame output
#
# Author: Daniel Bodnar
# Version: 3.0.0
# ============================================================================

# ============================================================================
# Module Exports (re-export for external use)
# ============================================================================

# Core types and helpers (exported with glob for direct access)
export use core/types.nu *

# Commands (exported with glob for direct access)
export use commands/config.nu *
export use commands/export.nu *

# ============================================================================
# Internal Imports (for use within this module)
# ============================================================================

# Storage layer - import specific functions for internal use
use core/storage.nu [get-paths, load, store, backup, migrate-from-gh-stars, get-stats, ensure-storage]

# Formatters - import for internal use
use formatters/table.nu [format]
use formatters/json.nu [to-json-output, to-csv-output, to-md-output, to-nuon-output]
use formatters/dataframe.nu [to-dataframe, to-lazyframe]

# Adapters - import for internal use
use adapters/github.nu [fetch]

# ============================================================================
# Constants
# ============================================================================

const MODULE_VERSION = "3.0.0"

# Default excluded languages (can be overridden in config)
const DEFAULT_EXCLUDED_LANGUAGES = [PHP, "C#", Java, Python, Ruby]

# Days threshold for considering a repo as stale
const STALE_DAYS_THRESHOLD = 365

# Default columns for table display
const DEFAULT_DISPLAY_COLUMNS = [
    owner
    name
    language
    stars
    pushed
    homepage
    topics
    description
    forks
    issues
]

# ============================================================================
# Internal Helpers
# ============================================================================

# Check if Polars plugin is available
def polars-available []: nothing -> bool {
    try {
        [[a]; [1]] | polars into-df | ignore
        true
    } catch {
        false
    }
}

# Load configuration with fallback to defaults
def load-config []: nothing -> record {
    try {
        stars config
    } catch {
        {
            version: $MODULE_VERSION
            defaults: {
                filters: {
                    exclude_languages: $DEFAULT_EXCLUDED_LANGUAGES
                    exclude_archived: true
                    exclude_forks: false
                    min_pushed_days: $STALE_DAYS_THRESHOLD
                }
                columns: $DEFAULT_DISPLAY_COLUMNS
                sort_by: "stars"
                sort_reverse: true
            }
        }
    }
}

# Apply default filters to data
def apply-default-filters [
    data: table
    config: record
]: nothing -> table {
    let filters = $config.defaults?.filters? | default {}
    let exclude_archived = $filters.exclude_archived? | default true
    let exclude_forks = $filters.exclude_forks? | default false
    let excluded_langs = $filters.exclude_languages? | default $DEFAULT_EXCLUDED_LANGUAGES
    let min_pushed_days = $filters.min_pushed_days? | default $STALE_DAYS_THRESHOLD

    let cutoff_date = (date now) - ($min_pushed_days * 1day)

    $data | where {|repo|
        # Handle archived/fork as int (0/1) from SQLite or bool
        let is_archived = try {
            let val = $repo.archived? | default 0
            if ($val | describe) == "bool" { $val } else { $val == 1 }
        } catch { false }
        let is_fork = try {
            let val = $repo.fork? | default 0
            if ($val | describe) == "bool" { $val } else { $val == 1 }
        } catch { false }
        let language = try { $repo.language? | default "" } catch { "" }
        let pushed_at = try {
            $repo.pushed_at? | default "" | into datetime
        } catch {
            date now
        }

        # Apply filters
        let pass_archived = (not $exclude_archived) or (not $is_archived)
        let pass_fork = (not $exclude_forks) or (not $is_fork)
        let pass_language = ($language | is-empty) or ($language not-in $excluded_langs)
        let pass_pushed = $pushed_at > $cutoff_date

        $pass_archived and $pass_fork and $pass_language and $pass_pushed
    }
}

# Search data by query string
def search-data [
    data: table
    query: string
]: nothing -> table {
    let query_lower = $query | str downcase

    $data | where {|repo|
        let name = try { $repo.name? | default "" | str downcase } catch { "" }
        let full_name = try { $repo.full_name? | default "" | str downcase } catch { "" }
        let description = try { $repo.description? | default "" | str downcase } catch { "" }
        let topics_str = try {
            let topics = $repo.topics? | default "[]"
            let type = $topics | describe | str replace --regex '<.*' ''
            match $type {
                "string" => { $topics | str downcase }
                "list" => { $topics | str join " " | str downcase }
                _ => { "" }
            }
        } catch { "" }

        (($name =~ $query_lower) or ($full_name =~ $query_lower) or ($description =~ $query_lower) or ($topics_str =~ $query_lower))
    }
}

# Sort data by field
def sort-data [
    data: table
    sort_by: string
    reverse: bool
]: nothing -> table {
    # Map friendly names to actual column names
    let sort_field = match $sort_by {
        "stars" => "stargazers_count"
        "forks" => "forks_count"
        "issues" => "open_issues_count"
        "pushed" => "pushed_at"
        "created" => "created_at"
        "updated" => "updated_at"
        "name" => "name"
        "language" => "language"
        "owner" => "owner"
        _ => $sort_by
    }

    # Use closure-based sorting to handle dynamic field names
    if $reverse {
        $data | sort-by {|row| $row | get $sort_field } --reverse
    } else {
        $data | sort-by {|row| $row | get $sort_field }
    }
}

# Format data for output based on flags
def format-output [
    data: table
    config: record
    columns: list<string>
    raw: bool
    json_flag: bool
    csv_flag: bool
    md_flag: bool
    nuon_flag: bool
    dataframe_flag: bool
    lazyframe_flag: bool
]: nothing -> any {
    # Raw output - return as-is
    if $raw {
        return $data
    }

    # JSON output
    if $json_flag {
        return (to-json-output $data --pretty)
    }

    # CSV output
    if $csv_flag {
        return (to-csv-output $data)
    }

    # Markdown output
    if $md_flag {
        return (to-md-output $data --columns $columns)
    }

    # NUON output
    if $nuon_flag {
        return (to-nuon-output $data --pretty)
    }

    # DataFrame output
    if $dataframe_flag {
        if not (polars-available) {
            error make {
                msg: "Polars plugin not available"
                help: "Install nu_plugin_polars: cargo install nu_plugin_polars && plugin add ~/.cargo/bin/nu_plugin_polars"
            }
        }
        return (to-dataframe $data)
    }

    # LazyFrame output
    if $lazyframe_flag {
        if not (polars-available) {
            error make {
                msg: "Polars plugin not available"
                help: "Install nu_plugin_polars: cargo install nu_plugin_polars && plugin add ~/.cargo/bin/nu_plugin_polars"
            }
        }
        return (to-lazyframe $data)
    }

    # Default: formatted table
    $data | format --columns $columns
}

# Check for migration from gh-stars on first use
def check-migration []: nothing -> bool {
    let paths = get-paths
    let new_db_exists = $paths.db_path | path exists

    if $new_db_exists {
        return false
    }

    # Check if old gh-stars database exists
    try {
        migrate-from-gh-stars
    } catch {
        false
    }
}

# ============================================================================
# Main Command
# ============================================================================

# Display starred repositories with beautiful formatting
#
# The main entry point for the stars module. Shows all starred repositories
# with configurable output formats, filtering, and sorting.
#
# Parameters:
#   query - Optional search query to filter results
#
# Flags:
#   --json - Output as JSON
#   --csv - Output as CSV
#   --md - Output as Markdown table
#   --nuon - Output as NUON (Nushell Object Notation)
#   --dataframe - Output as Polars DataFrame (requires nu_plugin_polars)
#   --lazyframe - Output as Polars LazyFrame (requires nu_plugin_polars)
#   --raw - Raw database output (all columns, no formatting)
#   --no-defaults - Skip default filters (show archived, stale, excluded languages)
#   --columns (-c) - Columns to display (default: owner, name, language, stars, etc.)
#   --limit (-l) - Limit number of results
#   --sort (-s) - Sort by field (stars, forks, pushed, created, name, language)
#   --reverse (-r) - Reverse sort order
#
# Examples:
#   # Show all stars with default formatting
#   stars
#
#   # Search for CLI tools
#   stars "cli tool"
#
#   # Show top 20 Rust repositories by stars
#   stars --limit 20 | where language == "Rust"
#
#   # Export to JSON
#   stars --json | save stars.json
#
#   # Get Polars DataFrame for analysis
#   stars --dataframe | polars filter ((polars col language) == "Rust")
export def main [
    query?: string                       # Optional search query
    --json                               # Output as JSON
    --csv                                # Output as CSV
    --md                                 # Output as Markdown
    --nuon                               # Output as NUON
    --dataframe                          # Output as Polars DataFrame
    --lazyframe                          # Output as Polars LazyFrame
    --raw                                # Raw database output (all columns)
    --no-defaults                        # Skip default filters
    --columns (-c): list<string> = []    # Columns to display
    --limit (-l): int                    # Limit results
    --sort (-s): string = "stars"        # Sort by field
    --reverse (-r)                       # Reverse sort order
]: nothing -> any {
    # Check for migration on first use
    check-migration | ignore

    # Load configuration
    let config = load-config

    # Load data from storage
    let raw_data = try {
        load
    } catch {|e|
        # If database doesn't exist, show helpful message
        print --stderr "No stars database found. Run 'stars sync' to fetch your GitHub stars."
        return []
    }

    if ($raw_data | is-empty) {
        print --stderr "No stars found. Run 'stars sync' to fetch your GitHub stars."
        return []
    }

    # Apply default filters unless --no-defaults
    let filtered_data = if $no_defaults {
        $raw_data
    } else {
        apply-default-filters $raw_data $config
    }

    # Apply search query if provided
    let searched_data = if ($query | is-empty) or ($query == null) {
        $filtered_data
    } else {
        search-data $filtered_data $query
    }

    # Sort data
    let sort_reverse = if $reverse { true } else { $config.defaults?.sort_reverse? | default true }
    let sorted_data = sort-data $searched_data $sort $sort_reverse

    # Apply limit
    let limited_data = if ($limit | is-empty) or ($limit == null) or ($limit <= 0) {
        $sorted_data
    } else {
        $sorted_data | first $limit
    }

    # Determine columns to display
    let display_columns = if ($columns | is-empty) {
        $config.defaults?.columns? | default $DEFAULT_DISPLAY_COLUMNS
    } else {
        $columns
    }

    # Format and return output
    format-output $limited_data $config $display_columns $raw $json $csv $md $nuon $dataframe $lazyframe
}

# ============================================================================
# Version Command
# ============================================================================

# Show version information for the stars module
#
# Displays the current version of the stars module along with Nushell version
# and Polars plugin availability.
#
# Example:
#   stars version
export def "stars version" []: nothing -> record<version: string, nushell: string, polars: string> {
    let polars_version = if (polars-available) {
        try {
            # Try to get Polars version from help output
            help polars | lines | first
        } catch {
            "available (version unknown)"
        }
    } else {
        "not installed"
    }

    {
        version: $MODULE_VERSION
        nushell: (version | get version)
        polars: $polars_version
    }
}

# ============================================================================
# Sync Command
# ============================================================================

# Sync starred repositories from all configured sources
#
# Fetches stars from GitHub (and optionally other sources) and stores them
# in the local SQLite database. Creates a backup before syncing if configured.
#
# Parameters:
#   --backup - Create backup before syncing
#   --no-cache - Bypass gh CLI cache for fresh data
#
# Example:
#   stars sync
#   stars sync --backup
#   stars sync --no-cache
export def "stars sync" [
    --backup        # Create backup before syncing
    --no-cache      # Bypass gh CLI cache
]: nothing -> nothing {
    print "Syncing stars from GitHub..."

    # Create backup if requested or configured
    let config = load-config
    let should_backup = $backup or ($config.storage?.backup_on_sync? | default false)

    if $should_backup {
        try {
            let backup_path = backup
            print $"Backup created: ($backup_path)"
        } catch {|e|
            print --stderr $"Warning: Failed to create backup: ($e.msg)"
        }
    }

    # Fetch from GitHub
    let use_cache = not $no_cache
    let cache_duration = $config.sync?.github?.cache_duration? | default "1h"

    let stars = try {
        if $use_cache {
            fetch --use-cache --cache-duration $cache_duration
        } else {
            fetch
        }
    } catch {|e|
        error make {
            msg: $"Failed to fetch stars from GitHub: ($e.msg)"
            help: "Ensure you're authenticated with 'gh auth login'"
        }
    }

    # Save to storage
    try {
        store $stars --replace
    } catch {|e|
        error make {
            msg: $"Failed to save stars: ($e.msg)"
        }
    }

    let count = $stars | length
    print $"Successfully synced ($count) starred repositories"
}

# Sync starred repositories from GitHub
#
# Fetches stars specifically from GitHub API. Alias for `stars sync` with
# GitHub-specific options.
#
# Parameters:
#   --user (-u) - GitHub username (default: authenticated user)
#   --backup - Create backup before syncing
#   --no-cache - Bypass gh CLI cache
#
# Example:
#   stars sync github
#   stars sync github --user danielbodnar
#   stars sync github --no-cache
export def "stars sync github" [
    --user (-u): string    # GitHub username (default: authenticated user)
    --backup               # Create backup before syncing
    --no-cache             # Bypass gh CLI cache
]: nothing -> nothing {
    print "Syncing stars from GitHub..."

    # Create backup if requested
    if $backup {
        try {
            let backup_path = backup
            print $"Backup created: ($backup_path)"
        } catch {|e|
            print --stderr $"Warning: Failed to create backup: ($e.msg)"
        }
    }

    # Fetch from GitHub
    let stars = try {
        if ($user | is-empty) or ($user == null) {
            if $no_cache {
                fetch
            } else {
                fetch --use-cache
            }
        } else {
            if $no_cache {
                fetch --user $user
            } else {
                fetch --user $user --use-cache
            }
        }
    } catch {|e|
        error make {
            msg: $"Failed to fetch stars from GitHub: ($e.msg)"
            help: "Ensure you're authenticated with 'gh auth login'"
        }
    }

    # Save to storage
    try {
        store $stars --replace
    } catch {|e|
        error make {
            msg: $"Failed to save stars: ($e.msg)"
        }
    }

    let count = $stars | length
    print $"Successfully synced ($count) starred repositories from GitHub"
}

# ============================================================================
# Stats Command
# ============================================================================

# Show statistics about starred repositories
#
# Provides summary statistics including total counts, language distribution,
# top owners, and activity metrics.
#
# Example:
#   stars stats
export def "stars stats" []: nothing -> record {
    let stats = get-stats

    if not $stats.exists {
        error make {
            msg: "No stars database found"
            help: "Run 'stars sync' to fetch your GitHub stars"
        }
    }

    # Get language distribution
    let data = try { load } catch { [] }

    let language_counts = if ($data | is-empty) {
        []
    } else {
        $data
        | where { ($in.language? | default "") != "" }
        | group-by { $in.language? | default "Unknown" }
        | items {|lang, repos| { language: $lang, count: ($repos | length) }}
        | sort-by count --reverse
        | first 10
    }

    # Get owner distribution
    let owner_counts = if ($data | is-empty) {
        []
    } else {
        $data
        | group-by { $in.owner? | default "unknown" }
        | items {|owner, repos| { owner: $owner, count: ($repos | length) }}
        | sort-by count --reverse
        | first 10
    }

    {
        total_stars: $stats.total_stars
        unique_languages: $stats.unique_languages
        archived_repos: $stats.archived_repos
        forked_repos: $stats.forked_repos
        db_size_mb: (($stats.db_size_bytes | into int | into float) / 1048576 | math round --precision 2)
        last_sync: $stats.last_modified
        backup_count: $stats.backup_count
        top_languages: $language_counts
        top_owners: $owner_counts
    }
}

# ============================================================================
# Help Command
# ============================================================================

# Show detailed help for the stars module
#
# Displays comprehensive usage information including all available commands,
# flags, and examples.
#
# Example:
#   stars help
export def "stars help" []: nothing -> nothing {
    print $"
Stars Module v($MODULE_VERSION) - GitHub Stars Management for Nushell

QUICK START
  stars sync         Fetch stars from GitHub \(requires 'gh auth login'\)
  stars              Display all stars with beautiful formatting
  stars \"rust cli\"   Search for repositories matching a query
  stars --json       Output as JSON
  stars export csv   Export to CSV file

MAIN COMMANDS
  stars [query]            Display stars \(with optional search\)
  stars version            Show version information
  stars help               Show this help message

SYNC COMMANDS
  stars sync               Sync from all configured sources
  stars sync github        Sync specifically from GitHub
    --user \(-u\)            GitHub username \(default: authenticated user\)
    --backup               Create backup before syncing
    --no-cache             Bypass gh CLI cache

CONFIGURATION
  stars config             Show current configuration
  stars config init        Initialize configuration file
  stars config get <key>   Get a config value \(dot notation: defaults.columns\)
  stars config set <k> <v> Set a config value
  stars config reset       Reset to defaults
  stars config edit        Edit in \$EDITOR
  stars config path        Show config file path
  stars config validate    Validate configuration

EXPORT COMMANDS
  stars export csv         Export to CSV
  stars export json        Export to JSON
  stars export nuon        Export to NUON \(Nushell format\)
  stars export md          Export to Markdown table
  stars export firefox     Export to Firefox bookmarks HTML
  stars export chrome      Export to Chrome bookmarks HTML

OUTPUT FLAGS \(for 'stars' command\)
  --json                   Output as JSON
  --csv                    Output as CSV
  --md                     Output as Markdown
  --nuon                   Output as NUON
  --dataframe              Output as Polars DataFrame \(requires plugin\)
  --lazyframe              Output as Polars LazyFrame \(requires plugin\)
  --raw                    Raw database output \(all columns\)

FILTER & SORT FLAGS
  --no-defaults            Skip default filters \(show all repos\)
  --columns \(-c\) <list>    Columns to display
  --limit \(-l\) <n>         Limit number of results
  --sort \(-s\) <field>      Sort by: stars, forks, pushed, created, name
  --reverse \(-r\)           Reverse sort order

EXAMPLES
  # Show top 20 most starred Rust repositories
  stars | where language == \"Rust\" | first 20

  # Export stars to JSON with pretty printing
  stars --json | save stars.json

  # Analyze with Polars \(if installed\)
  stars --dataframe | polars group-by language | polars count

  # Search and export matching repos
  stars \"machine learning\" | stars export csv --output ml-repos.csv

DEPENDENCIES
  - Nushell 0.100.0+
  - gh CLI \(authenticated via 'gh auth login'\)
  - nu_plugin_polars \(optional, for DataFrame output\)

STORAGE LOCATIONS
  Database:   \$XDG_DATA_HOME/.stars/stars.db
  Config:     \$XDG_CONFIG_HOME/stars/config.nu
  Backups:    \$XDG_DATA_HOME/.stars/backups/
  Exports:    \$XDG_DATA_HOME/.stars/exports/

For more information, see: https://github.com/danielbodnar/nushell-config
"
}
