#!/usr/bin/env nu

# ============================================================================
# Stars Module - Polars LazyFrame Data Operations
# ============================================================================
#
# Provides Polars LazyFrame operations for efficient data processing of
# GitHub starred repositories. Uses lazy evaluation for optimal performance
# with large datasets.
#
# # Dependencies
# - Nushell 0.100.0+
# - Polars plugin (nu_plugin_polars)
#
# # Usage
# ```nushell
# use core/data.nu *
# load-lazy | apply-defaults | collect-data
# ```
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

# ============================================================================
# Configuration
# ============================================================================

# Default languages to exclude from analysis
const DEFAULT_EXCLUDED_LANGUAGES = [PHP C# Java Python Ruby]

# Days threshold for considering a repo as "old" (not pushed recently)
const STALE_DAYS_THRESHOLD = 365

# ============================================================================
# Internal Helpers
# ============================================================================

# Check if Polars plugin is available
def polars-available []: nothing -> bool {
    try {
        # Try to create a simple dataframe to verify Polars is working
        [[a]; [1]] | polars into-df | ignore
        true
    } catch {
        false
    }
}

# Get the stars database path from configuration
def get-db-path []: nothing -> path {
    let data_home = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    $data_home | path join gh-stars stars.db
}

# Ensure database exists before operations
def ensure-db-exists []: nothing -> nothing {
    let db_path = get-db-path
    if not ($db_path | path exists) {
        error make {
            msg: "Stars database not found"
            label: { text: "Run 'gh-stars fetch' first to populate the database", span: (metadata $db_path).span }
            help: "The stars database must be initialized before using Polars operations"
        }
    }
}

# ============================================================================
# Core LazyFrame Operations
# ============================================================================

# Load stars as Polars LazyFrame
#
# Loads the starred repositories from SQLite database into a Polars LazyFrame
# for efficient lazy evaluation and query optimization.
#
# Returns: polars_lazyframe - Lazy dataframe containing all starred repos
#
# Example:
#   load-lazy | polars schema
export def load-lazy []: nothing -> any {
    if not (polars-available) {
        error make {
            msg: "Polars plugin not available"
            label: { text: "Install nu_plugin_polars and register it", span: (metadata $in).span }
            help: "Run: plugin add nu_plugin_polars && plugin use polars"
        }
    }

    ensure-db-exists

    let db_path = get-db-path

    try {
        open $db_path
        | query db "SELECT * FROM stars"
        | polars into-lazy
    } catch {|e|
        error make {
            msg: $"Failed to load stars into LazyFrame: ($e.msg)"
            label: { text: "database query or conversion failed", span: (metadata $db_path).span }
        }
    }
}

# Apply default filters to LazyFrame
#
# Applies configurable default filters to exclude archived repos, stale repos,
# and repos in excluded languages.
#
# Parameters:
#   --skip-defaults: Skip all default filters
#   --include-archived: Include archived repositories
#   --include-old: Include repos not pushed in 1+ years
#   --languages: Languages to exclude (default: PHP, C#, Java, Python, Ruby)
#
# Example:
#   load-lazy | apply-defaults
#   load-lazy | apply-defaults --include-archived --languages [PHP Java]
export def apply-defaults [
    --skip-defaults        # Skip all default filters
    --include-archived     # Include archived repositories
    --include-old          # Include repos not pushed in 1+ years
    --languages: list<string> = []  # Languages to exclude (overrides defaults)
]: any -> any {
    let lf = $in

    if $skip_defaults {
        return $lf
    }

    # Determine which languages to exclude
    let excluded_langs = if ($languages | is-empty) {
        $DEFAULT_EXCLUDED_LANGUAGES
    } else {
        $languages
    }

    # Calculate cutoff date for stale repos
    let cutoff_date = (date now) - ($STALE_DAYS_THRESHOLD * 1day)
    let cutoff_str = $cutoff_date | format date "%Y-%m-%dT%H:%M:%SZ"

    # Build filter conditions
    mut filtered = $lf

    # Filter out archived repos unless --include-archived
    # Note: archived is stored as i64 (0/1) not bool in SQLite
    if not $include_archived {
        $filtered = ($filtered | polars filter ((polars col archived) == (polars lit 0)))
    }

    # Filter out stale repos unless --include-old
    if not $include_old {
        $filtered = ($filtered | polars filter ((polars col pushed_at) > (polars lit $cutoff_str)))
    }

    # Filter out excluded languages
    if not ($excluded_langs | is-empty) {
        # Use is-not-in pattern: filter where language is NOT in excluded list
        # Using polars lit with implode to avoid deprecation warning
        $filtered = ($filtered | polars filter (
            (polars col language | polars is-in (polars lit $excluded_langs | polars implode) | polars expr-not)
        ))
    }

    $filtered
}

# Select specific columns from LazyFrame
#
# Parameters:
#   columns: list<string> - Column names to select
#
# Example:
#   load-lazy | select-columns [name full_name stargazers_count language]
export def select-columns [
    columns: list<string>  # Column names to select
]: any -> any {
    let lf = $in

    if ($columns | is-empty) {
        return $lf
    }

    # Build column expressions
    let col_exprs = $columns | each {|col| polars col $col }

    $lf | polars select ...$col_exprs
}

# Sort LazyFrame by field
#
# Parameters:
#   field: string - Field name to sort by
#   --reverse: Sort in descending order
#
# Example:
#   load-lazy | sort-by-field stargazers_count --reverse
export def sort-by-field [
    field: string          # Field name to sort by
    --reverse              # Sort in descending order (default: ascending)
]: any -> any {
    let lf = $in

    if $reverse {
        $lf | polars sort-by $field -r [true]
    } else {
        $lf | polars sort-by $field
    }
}

# Search/filter LazyFrame by query
#
# Performs case-insensitive search across specified fields or all text fields.
#
# Parameters:
#   query: string - Search query (regex pattern supported)
#   --field: string - Specific field to search (default: "all" searches name, description, full_name)
#
# Example:
#   load-lazy | search "rust" --field name
#   load-lazy | search "cli|terminal"
export def search [
    query: string                    # Search query (regex pattern)
    --field (-f): string = "all"     # Field to search: name, description, full_name, owner, topics, all
]: any -> any {
    let lf = $in

    # Build case-insensitive regex pattern
    let pattern = ['(?i)' $query] | str join

    # Build search expression based on field
    let search_expr = match $field {
        "name" => {
            polars col name | polars contains $pattern
        }
        "description" => {
            polars col description | polars contains $pattern
        }
        "full_name" => {
            polars col full_name | polars contains $pattern
        }
        "owner" => {
            polars col owner | polars contains $pattern
        }
        "topics" => {
            polars col topics | polars contains $pattern
        }
        _ => {
            # Search across multiple fields using OR logic via when/otherwise
            # Polars doesn't have direct OR on expressions, so we chain contains checks
            let name_match = polars col name | polars contains $pattern
            let desc_match = polars col description | polars contains $pattern
            let full_name_match = polars col full_name | polars contains $pattern

            # Combine with OR logic using when/otherwise pattern
            polars when $name_match (polars lit true)
            | polars when $desc_match (polars lit true)
            | polars when $full_name_match (polars lit true)
            | polars otherwise (polars lit false)
        }
    }

    $lf | polars filter $search_expr
}

# Group by field with aggregations
#
# Groups the LazyFrame by specified field and computes aggregations.
#
# Parameters:
#   field: string - Field name to group by
#
# Returns: table - Grouped results with count, total_stars, avg_stars
#
# Example:
#   load-lazy | group-by-field language | collect-data
export def group-by-field [
    field: string  # Field name to group by
]: any -> table {
    let lf = $in

    $lf
    | polars group-by $field
    | polars agg {
        count: (polars col full_name | polars count)
        total_stars: (polars col stargazers_count | polars sum)
        avg_stars: (polars col stargazers_count | polars mean)
    }
    | polars sort-by count -r [true]
    | polars collect
    | polars into-nu
}

# Collect LazyFrame to Nushell table
#
# Materializes the lazy dataframe into an eager dataframe and converts
# it to a native Nushell table for further processing.
#
# Example:
#   load-lazy | apply-defaults | collect-data
export def collect-data []: any -> table {
    let lf = $in

    try {
        $lf | polars collect | polars into-nu
    } catch {|e|
        error make {
            msg: $"Failed to collect LazyFrame: ($e.msg)"
            label: { text: "collection or conversion failed", span: (metadata $lf).span }
        }
    }
}

# ============================================================================
# Convenience Functions
# ============================================================================

# Get top N repositories by stars
#
# Parameters:
#   n: int - Number of repositories to return (default: 20)
#
# Example:
#   load-lazy | apply-defaults | top-by-stars 10 | collect-data
export def top-by-stars [
    n: int = 20  # Number of repositories to return
]: any -> any {
    let lf = $in

    $lf
    | polars sort-by stargazers_count -r [true]
    | polars select (polars col full_name) (polars col stargazers_count) (polars col language) (polars col description)
    | polars first $n
}

# Filter by language
#
# Parameters:
#   language: string - Programming language to filter by
#
# Example:
#   load-lazy | filter-by-language Rust | collect-data
export def filter-by-language [
    language: string  # Programming language to filter by
]: any -> any {
    let lf = $in

    $lf | polars filter ((polars col language) == (polars lit $language))
}

# Get recently pushed repositories
#
# Parameters:
#   days: int - Number of days to look back (default: 30)
#
# Example:
#   load-lazy | recently-pushed 7 | collect-data
export def recently-pushed [
    days: int = 30  # Number of days to look back
]: any -> any {
    let lf = $in

    let cutoff_date = (date now) - ($days * 1day)
    let cutoff_str = $cutoff_date | format date "%Y-%m-%dT%H:%M:%SZ"

    $lf
    | polars filter ((polars col pushed_at) > (polars lit $cutoff_str))
    | polars sort-by pushed_at -r [true]
}

# Get language statistics
#
# Returns aggregated statistics grouped by programming language.
#
# Example:
#   load-lazy | apply-defaults | language-stats
export def language-stats []: any -> table {
    let lf = $in

    $lf | group-by-field language
}

# Get owner statistics
#
# Returns aggregated statistics grouped by repository owner.
# Note: Requires owner field to be extracted from JSON in preprocessing.
#
# Example:
#   load-lazy | apply-defaults | owner-stats
export def owner-stats []: any -> table {
    let lf = $in

    $lf | group-by-field owner
}
