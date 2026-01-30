#!/usr/bin/env nu

# ============================================================================
# Default Filters Module for Stars
# ============================================================================
#
# Provides default filter functions for working with Polars LazyFrames.
# All filters are composable and can be chained together.
#
# # Usage
# ```nushell
# use filters/defaults.nu *
# polars open stars.parquet | exclude-archived | exclude-old --days 365 | polars collect
# ```
#
# # Dependencies
# - nu_plugin_polars
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

# ============================================================================
# Constants
# ============================================================================

# Default excluded languages
const DEFAULT_EXCLUDED_LANGUAGES = [PHP, "C#", Java, Python, Ruby]

# Default staleness threshold in days
const DEFAULT_STALENESS_DAYS = 365

# ============================================================================
# Individual Filter Functions
# ============================================================================

# Exclude repositories not pushed in N days
#
# Filters out repositories where the `pushed` column is older than
# the specified number of days from now.
#
# Parameters:
#   --days (-d): int - Repos not pushed in this many days are excluded (default: 365)
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   polars open stars.parquet | exclude-old --days 180 | polars collect
export def exclude-old [
    --days (-d): int = 365    # Repos not pushed in this many days are excluded
]: any -> any {
    let cutoff = (date now) - ($days * 1day)
    $in | polars filter ((polars col pushed) > (polars lit $cutoff))
}

# Exclude archived repositories
#
# Filters out repositories where the `archived` column is true.
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   polars open stars.parquet | exclude-archived | polars collect
export def exclude-archived []: any -> any {
    $in | polars filter ((polars col archived) == (polars lit false))
}

# Exclude specified programming languages
#
# Filters out repositories with languages in the exclusion list.
# By default excludes: PHP, C#, Java, Python, Ruby
#
# Parameters:
#   --languages (-l): list<string> - Languages to exclude
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   polars open stars.parquet | exclude-languages --languages [PHP Java] | polars collect
export def exclude-languages [
    --languages (-l): list<string> = [PHP, "C#", Java, Python, Ruby]  # Languages to exclude
]: any -> any {
    # Filter out rows where language is in the exclusion list
    # Use polars is-in with negation
    $in | polars filter (
        (polars col language | polars is-in $languages | polars expr-not)
    )
}

# Exclude forked repositories
#
# Filters out repositories where the `fork` column is true.
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   polars open stars.parquet | exclude-forks | polars collect
export def exclude-forks []: any -> any {
    $in | polars filter ((polars col fork) == (polars lit false))
}

# ============================================================================
# Inclusion Filters (inverse of exclusion)
# ============================================================================

# Include only repositories pushed within N days
#
# Keeps only repositories where the `pushed` column is within
# the specified number of days from now.
#
# Parameters:
#   --days (-d): int - Keep repos pushed within this many days (default: 30)
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   polars open stars.parquet | include-recent --days 30 | polars collect
export def include-recent [
    --days (-d): int = 30    # Keep repos pushed within this many days
]: any -> any {
    let cutoff = (date now) - ($days * 1day)
    $in | polars filter ((polars col pushed) > (polars lit $cutoff))
}

# Include only specific languages
#
# Keeps only repositories with languages in the inclusion list.
#
# Parameters:
#   --languages (-l): list<string> - Languages to include
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   polars open stars.parquet | include-languages --languages [Rust TypeScript] | polars collect
export def include-languages [
    --languages (-l): list<string>  # Languages to include
]: any -> any {
    $in | polars filter (polars col language | polars is-in $languages)
}

# ============================================================================
# Combined Filter Function
# ============================================================================

# Apply all default filters
#
# Applies a combination of filters based on the provided flags.
# By default applies all exclusion filters (archived, old, forks, languages).
# Use --include-* flags to skip specific filters.
#
# Parameters:
#   --days (-d): int - Staleness threshold in days (default: 365)
#   --languages (-l): list<string> - Languages to exclude
#   --include-forks: bool - Skip fork exclusion filter
#   --include-archived: bool - Skip archived exclusion filter
#   --include-old: bool - Skip staleness filter
#   --include-all-languages: bool - Skip language exclusion filter
#
# Input: Polars LazyFrame or DataFrame
# Output: Polars LazyFrame or DataFrame
#
# Example:
#   # Apply all default filters
#   polars open stars.parquet | apply-all | polars collect
#
#   # Keep archived repos but exclude old ones
#   polars open stars.parquet | apply-all --include-archived | polars collect
#
#   # Custom staleness and language settings
#   polars open stars.parquet | apply-all --days 180 --languages [PHP] | polars collect
export def apply-all [
    --days (-d): int = 365                                             # Staleness threshold in days
    --languages (-l): list<string> = [PHP, "C#", Java, Python, Ruby]  # Languages to exclude
    --include-forks                                                    # Skip fork exclusion filter
    --include-archived                                                 # Skip archived exclusion filter
    --include-old                                                      # Skip staleness filter
    --include-all-languages                                            # Skip language exclusion filter
]: any -> any {
    mut df = $in

    # Apply archived filter unless --include-archived is set
    if not $include_archived {
        $df = ($df | exclude-archived)
    }

    # Apply staleness filter unless --include-old is set
    if not $include_old {
        $df = ($df | exclude-old --days $days)
    }

    # Apply fork filter unless --include-forks is set
    if not $include_forks {
        $df = ($df | exclude-forks)
    }

    # Apply language filter unless --include-all-languages is set
    if not $include_all_languages {
        $df = ($df | exclude-languages --languages $languages)
    }

    $df
}

# ============================================================================
# Utility Functions
# ============================================================================

# Get filter statistics
#
# Returns a record showing how many rows would be filtered by each filter.
# Useful for understanding the impact of filters before applying them.
#
# Parameters:
#   --days (-d): int - Staleness threshold for old repos (default: 365)
#   --languages (-l): list<string> - Languages considered for exclusion
#
# Input: Polars LazyFrame or DataFrame
# Output: record with filter impact statistics
#
# Example:
#   polars open stars.parquet | filter-stats
export def filter-stats [
    --days (-d): int = 365
    --languages (-l): list<string> = [PHP, "C#", Java, Python, Ruby]
]: any -> record {
    let df = $in
    let total = $df | polars count | polars into-nu | get count | first

    let cutoff = (date now) - ($days * 1day)

    let archived_count = $df
        | polars filter ((polars col archived) == (polars lit true))
        | polars count
        | polars into-nu
        | get count
        | first

    let old_count = $df
        | polars filter ((polars col pushed) <= (polars lit $cutoff))
        | polars count
        | polars into-nu
        | get count
        | first

    let fork_count = $df
        | polars filter ((polars col fork) == (polars lit true))
        | polars count
        | polars into-nu
        | get count
        | first

    let excluded_lang_count = $df
        | polars filter (polars col language | polars is-in $languages)
        | polars count
        | polars into-nu
        | get count
        | first

    let after_all = $df
        | apply-all --days $days --languages $languages
        | polars count
        | polars into-nu
        | get count
        | first

    {
        total_rows: $total
        archived_repos: $archived_count
        old_repos: $old_count
        fork_repos: $fork_count
        excluded_language_repos: $excluded_lang_count
        rows_after_all_filters: $after_all
        staleness_days: $days
        excluded_languages: $languages
    }
}

# Show filter configuration
#
# Returns the current default filter configuration.
#
# Example:
#   filter-config
export def filter-config []: nothing -> record {
    {
        default_staleness_days: $DEFAULT_STALENESS_DAYS
        default_excluded_languages: $DEFAULT_EXCLUDED_LANGUAGES
    }
}
