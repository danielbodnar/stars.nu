#!/usr/bin/env nu

# ============================================================================
# Stars Module - Statistics and Analytics Commands
# ============================================================================
#
# Provides statistics, grouping, ranking, and reporting commands for analyzing
# starred repository collections. Uses both SQLite queries and Polars for
# efficient aggregations.
#
# # Usage
# ```nushell
# use commands/stats.nu *
# stars stats
# stars group --by language --limit 10
# stars top --by stars --limit 20
# stars recent --days 30
# stars untagged
# stars report --output ./report.md
# ```
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

use ../core/storage.nu [get-paths, load]
use ../core/types.nu [parse-topics, get-owner-login, excluded-languages]
use ../formatters/table.nu [format-stars]
use ../formatters/json.nu [to-json-output]

# ============================================================================
# Internal Helpers
# ============================================================================

# Format number for human-readable display (1234 -> 1.2k, 1234567 -> 1.2M)
def format-count [count: int]: nothing -> string {
    if $count >= 1000000 {
        let millions = ($count / 1000000.0) | math round --precision 1
        $"($millions)M"
    } else if $count >= 1000 {
        let thousands = ($count / 1000.0) | math round --precision 1
        $"($thousands)k"
    } else {
        $count | into string
    }
}

# Query database for basic counts
def query-star-counts [db_path: path]: nothing -> record {
    try {
        open $db_path | query db "
            SELECT
                COUNT(*) as total_stars,
                COUNT(DISTINCT language) as unique_languages,
                SUM(CASE WHEN archived = 1 THEN 1 ELSE 0 END) as archived_repos,
                SUM(CASE WHEN fork = 1 THEN 1 ELSE 0 END) as forked_repos
            FROM stars
        " | first
    } catch {
        {total_stars: 0, unique_languages: 0, archived_repos: 0, forked_repos: 0}
    }
}

# Query database for untagged repo count
def query-untagged-count [db_path: path]: nothing -> int {
    try {
        open $db_path | query db "
            SELECT COUNT(*) as count FROM stars
            WHERE topics IS NULL OR topics = '' OR topics = '[]' OR topics = 'null'
        " | first | get count
    } catch {
        0
    }
}

# Query database for top languages
def query-top-languages [db_path: path, limit: int = 10]: nothing -> table {
    try {
        open $db_path | query db $"
            SELECT language, COUNT\(*\) as count
            FROM stars
            WHERE language IS NOT NULL AND language != ''
            GROUP BY language
            ORDER BY count DESC
            LIMIT ($limit)
        "
    } catch { [] }
}

# Query database for top owners
def query-top-owners [db_path: path, limit: int = 10]: nothing -> table {
    try {
        open $db_path | query db $"
            SELECT json_extract\(owner, '$.login'\) as owner, COUNT\(*\) as count
            FROM stars
            GROUP BY owner
            ORDER BY count DESC
            LIMIT ($limit)
        "
    } catch { [] }
}

# Query database for stars by year
def query-by-year [db_path: path]: nothing -> table {
    try {
        open $db_path | query db "
            SELECT
                COALESCE(strftime('%Y', created_at), 'unknown') as year,
                COUNT(*) as count
            FROM stars
            GROUP BY year
            ORDER BY year DESC
        "
    } catch { [] }
}

# Group stars by language using pipeline
def group-by-language [data: table, limit: int]: nothing -> table {
    $data
    | group-by {|repo| $repo.language? | default "Unknown" }
    | items {|key, value| {key: $key, count: ($value | length)} }
    | sort-by count --reverse
    | first $limit
}

# Group stars by owner using pipeline
def group-by-owner [data: table, limit: int]: nothing -> table {
    $data
    | group-by {|repo| get-owner-login ($repo.owner? | default "") }
    | items {|key, value| {key: $key, count: ($value | length)} }
    | sort-by count --reverse
    | first $limit
}

# Group stars by year using pipeline
def group-by-year [data: table, limit: int]: nothing -> table {
    $data
    | group-by {|repo|
        try {
            $repo.created_at? | default "" | into datetime | format date "%Y"
        } catch {
            "unknown"
        }
    }
    | items {|key, value| {year: $key, count: ($value | length)} }
    | sort-by year --reverse
    | first $limit
}

# Group stars by topic using pipeline
def group-by-topic [data: table, limit: int]: nothing -> table {
    let all_topics = $data
        | each {|repo| parse-topics ($repo.topics? | default []) }
        | flatten
        | where {|t| $t != null and $t != "" }

    $all_topics
    | uniq --count
    | rename topic count
    | sort-by count --reverse
    | first $limit
}

# Apply default filters (exclude archived, old repos)
def apply-default-filters [data: table]: nothing -> table {
    $data | where {|repo|
        let is_archived = ($repo.archived? | default 0) == 1 or ($repo.archived? | default false) == true
        not $is_archived
    }
}

# ============================================================================
# Statistics Commands
# ============================================================================

# Show statistics about starred repositories
#
# Provides a comprehensive overview of your starred repositories including
# total count, language distribution, archived/forked repos, and top items.
#
# Parameters:
#   --json: Output as JSON format for machine consumption
#
# Returns: record with statistics data
#
# Example:
#   stars stats
#   stars stats --json
export def "stars stats" [
    --json                      # Output as JSON
]: nothing -> record {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
            help: "Initialize the database with 'stars fetch' before running stats"
        }
    }

    let counts = query-star-counts $paths.db_path
    let untagged_count = query-untagged-count $paths.db_path
    let top_languages = query-top-languages $paths.db_path 10
    let top_owners = query-top-owners $paths.db_path 10
    let by_year = query-by-year $paths.db_path
    let db_updated = try { ls $paths.db_path | first | get modified } catch { date now }

    let stats = {
        total_stars: $counts.total_stars
        unique_languages: $counts.unique_languages
        archived_repos: $counts.archived_repos
        forked_repos: $counts.forked_repos
        untagged_repos: $untagged_count
        top_languages: $top_languages
        top_owners: $top_owners
        by_year: $by_year
        cache_updated: $db_updated
    }

    if $json {
        # Return as JSON string for piping
        $stats | to json
    } else {
        $stats
    }
}

# ============================================================================
# Grouping Commands
# ============================================================================

# Group stars by various criteria
#
# Aggregates starred repositories by language, owner, year, or topic.
# Useful for understanding the composition of your star collection.
#
# Parameters:
#   --by (-b): string - Grouping criterion: language, owner, year, topic
#   --limit (-l): int - Maximum number of groups to return
#   --json: Output as JSON format
#
# Returns: table with group key and count columns
#
# Example:
#   stars group --by language
#   stars group --by owner --limit 10
#   stars group --by topic --json
export def "stars group" [
    --by (-b): string = "language"  # Group by: language, owner, year, topic
    --limit (-l): int = 20          # Limit results
    --json                          # Output as JSON
]: nothing -> table {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
        }
    }

    let data = load

    let result = match $by {
        "language" => { group-by-language $data $limit }
        "owner" => { group-by-owner $data $limit }
        "year" => { group-by-year $data $limit }
        "topic" => { group-by-topic $data $limit }
        _ => {
            error make {
                msg: $"Invalid grouping criterion: ($by)"
                label: {text: "Use: language, owner, year, or topic", span: (metadata $by).span}
            }
        }
    }

    if $json {
        $result | to json
    } else {
        # Add human-readable count formatting for display
        $result | each {|row|
            let count_formatted = format-count $row.count
            $row | merge {count_display: $count_formatted}
        }
    }
}

# ============================================================================
# Ranking Commands
# ============================================================================

# Show top repositories
#
# Returns the highest-ranked repositories by stars, forks, or update date.
# Useful for finding your most notable or active starred repos.
#
# Parameters:
#   --by (-b): string - Sort criterion: stars, forks, updated
#   --limit (-l): int - Maximum number of repos to return
#   --json: Output as JSON format
#
# Returns: table with repository details
#
# Example:
#   stars top
#   stars top --by forks --limit 10
#   stars top --by updated --json
export def "stars top" [
    --by (-b): string = "stars"     # Sort by: stars, forks, updated
    --limit (-l): int = 20          # Limit results
    --json                          # Output as JSON
]: nothing -> table {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
        }
    }

    let data = load

    let sorted = match $by {
        "stars" => {
            $data | sort-by {|r| $r.stargazers_count? | default ($r.stars? | default 0)} --reverse
        }
        "forks" => {
            $data | sort-by {|r| $r.forks_count? | default ($r.forks? | default 0)} --reverse
        }
        "updated" => {
            $data | sort-by {|r| $r.updated_at? | default ($r.pushed_at? | default "1970-01-01")} --reverse
        }
        _ => {
            error make {
                msg: $"Invalid sort field: ($by)"
                label: {text: "Use: stars, forks, or updated", span: (metadata $by).span}
            }
        }
    }

    let result = $sorted | first $limit | each {|repo|
        let owner = get-owner-login ($repo.owner? | default "")
        let stars_count = $repo.stargazers_count? | default ($repo.stars? | default 0)
        let forks_count = $repo.forks_count? | default ($repo.forks? | default 0)

        {
            name: ($repo.name? | default "")
            owner: $owner
            full_name: ($repo.full_name? | default $"($owner)/($repo.name? | default '')")
            stars: $stars_count
            stars_display: (format-count $stars_count)
            forks: $forks_count
            forks_display: (format-count $forks_count)
            language: ($repo.language? | default "")
            updated_at: ($repo.updated_at? | default "")
            url: ($repo.html_url? | default ($repo.url? | default ""))
        }
    }

    if $json {
        $result | to json
    } else {
        $result
    }
}

# ============================================================================
# Recent Activity Commands
# ============================================================================

# Show recently updated repositories
#
# Finds starred repositories that have been pushed to within the specified
# time window. Helps identify actively maintained projects.
#
# Parameters:
#   --days (-d): int - Look back this many days
#   --limit (-l): int - Maximum number of repos to return
#   --json: Output as JSON format
#
# Returns: table with repository details and push dates
#
# Example:
#   stars recent
#   stars recent --days 7
#   stars recent --days 90 --limit 50 --json
export def "stars recent" [
    --days (-d): int = 30           # Look back this many days
    --limit (-l): int = 20          # Limit results
    --json                          # Output as JSON
]: nothing -> table {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
        }
    }

    let data = load
    let cutoff_date = (date now) - ($days * 1day)

    let recent_repos = $data
        | where {|repo|
            try {
                let pushed = $repo.pushed_at? | default ($repo.updated_at? | default "")
                if ($pushed | is-empty) {
                    false
                } else {
                    ($pushed | into datetime) > $cutoff_date
                }
            } catch {
                false
            }
        }
        | sort-by {|r| $r.pushed_at? | default ($r.updated_at? | default "1970-01-01")} --reverse
        | first $limit

    let result = $recent_repos | each {|repo|
        let owner = get-owner-login ($repo.owner? | default "")
        let stars_count = $repo.stargazers_count? | default ($repo.stars? | default 0)
        let pushed = $repo.pushed_at? | default ($repo.updated_at? | default "")

        {
            name: ($repo.name? | default "")
            owner: $owner
            full_name: ($repo.full_name? | default $"($owner)/($repo.name? | default '')")
            pushed_at: $pushed
            stars: $stars_count
            stars_display: (format-count $stars_count)
            language: ($repo.language? | default "")
            url: ($repo.html_url? | default ($repo.url? | default ""))
        }
    }

    if $json {
        $result | to json
    } else {
        $result
    }
}

# ============================================================================
# Untagged Commands
# ============================================================================

# Find repositories without topics (untagged)
#
# Identifies starred repositories that have no topics assigned.
# Useful for finding repos that could benefit from better categorization.
#
# Parameters:
#   --limit (-l): int - Maximum number of repos to return
#   --json: Output as JSON format
#
# Returns: table with untagged repository details
#
# Example:
#   stars untagged
#   stars untagged --limit 100
#   stars untagged --json
export def "stars untagged" [
    --limit (-l): int = 50          # Limit results
    --json                          # Output as JSON
]: nothing -> table {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
        }
    }

    let data = load

    let untagged = $data
        | where {|repo|
            let topics = parse-topics ($repo.topics? | default [])
            ($topics | length) == 0
        }
        | sort-by {|r| $r.stargazers_count? | default ($r.stars? | default 0)} --reverse
        | first $limit

    let result = $untagged | each {|repo|
        let owner = get-owner-login ($repo.owner? | default "")
        let stars_count = $repo.stargazers_count? | default ($repo.stars? | default 0)

        {
            name: ($repo.name? | default "")
            owner: $owner
            full_name: ($repo.full_name? | default $"($owner)/($repo.name? | default '')")
            stars: $stars_count
            stars_display: (format-count $stars_count)
            language: ($repo.language? | default "")
            description: ($repo.description? | default "" | str substring 0..80)
            url: ($repo.html_url? | default ($repo.url? | default ""))
        }
    }

    if $json {
        $result | to json
    } else {
        $result
    }
}

# ============================================================================
# Report Commands
# ============================================================================

# Generate a full report
#
# Creates a comprehensive report of your starred repositories including
# statistics, top languages, top owners, recent activity, and untagged repos.
#
# Parameters:
#   --output (-o): path - Save report to file (optional)
#   --format (-f): string - Output format: md (Markdown) or json
#
# Returns: string - The generated report content
#
# Example:
#   stars report
#   stars report --output ./stars-report.md
#   stars report --format json --output ./stars-report.json
export def "stars report" [
    --output (-o): path             # Save to file
    --format (-f): string = "md"    # Format: md, json
]: nothing -> string {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
        }
    }

    # Gather all data
    let stats = stars stats
    let recent = stars recent --days 30 --limit 10
    let untagged = stars untagged --limit 10
    let top_by_stars = stars top --by stars --limit 10
    let by_language = stars group --by language --limit 15
    let by_owner = stars group --by owner --limit 10

    let report = if $format == "json" {
        # JSON format report
        {
            generated_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
            summary: {
                total_stars: $stats.total_stars
                unique_languages: $stats.unique_languages
                archived_repos: $stats.archived_repos
                forked_repos: $stats.forked_repos
                untagged_repos: $stats.untagged_repos
                cache_updated: ($stats.cache_updated | format date "%Y-%m-%dT%H:%M:%SZ")
            }
            top_languages: $stats.top_languages
            top_owners: $stats.top_owners
            by_year: $stats.by_year
            top_repositories: $top_by_stars
            recent_activity: $recent
            untagged_sample: $untagged
        } | to json --indent 2
    } else {
        # Markdown format report
        let cache_date = try {
            $stats.cache_updated | format date "%Y-%m-%d %H:%M:%S"
        } catch {
            "unknown"
        }

        # Format top languages table
        let lang_table = $stats.top_languages
            | each {|row| $"| ($row.language) | ($row.count) |"}
            | str join "\n"

        # Format top owners table
        let owner_table = $stats.top_owners
            | each {|row| $"| ($row.owner) | ($row.count) |"}
            | str join "\n"

        # Format by year table
        let year_table = $stats.by_year
            | each {|row| $"| ($row.year) | ($row.count) |"}
            | str join "\n"

        # Format top repos table
        let top_repos_table = $top_by_stars
            | each {|row| $"| ($row.full_name) | ($row.language) | ($row.stars_display) |"}
            | str join "\n"

        # Format recent activity table
        let recent_table = $recent
            | each {|row|
                let pushed_date = try { $row.pushed_at | str substring 0..10 } catch { "" }
                $"| ($row.full_name) | ($pushed_date) | ($row.language) |"
            }
            | str join "\n"

        # Format untagged table
        let untagged_table = $untagged
            | each {|row| $"| ($row.full_name) | ($row.language) | ($row.stars_display) |"}
            | str join "\n"

        $"# GitHub Stars Report

Generated: (date now | format date '%Y-%m-%d %H:%M:%S')

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total Stars | ($stats.total_stars) |
| Unique Languages | ($stats.unique_languages) |
| Archived Repositories | ($stats.archived_repos) |
| Forked Repositories | ($stats.forked_repos) |
| Untagged Repositories | ($stats.untagged_repos) |
| Cache Updated | ($cache_date) |

## Top Languages

| Language | Count |
|----------|-------|
($lang_table)

## Top Repository Owners

| Owner | Count |
|-------|-------|
($owner_table)

## Stars by Year Created

| Year | Count |
|------|-------|
($year_table)

## Top Repositories by Stars

| Repository | Language | Stars |
|------------|----------|-------|
($top_repos_table)

## Recent Activity \(Last 30 Days\)

| Repository | Pushed | Language |
|------------|--------|----------|
($recent_table)

## Untagged Repositories \(Sample\)

| Repository | Language | Stars |
|------------|----------|-------|
($untagged_table)

---
*Report generated by stars module*
"
    }

    # Save to file if output path provided
    if ($output | is-not-empty) {
        let output_path = $output | path expand
        try {
            $report | save --force $output_path
            print --stderr $"Report saved to: ($output_path)"
        } catch {|e|
            error make {
                msg: $"Failed to save report: ($e.msg)"
                label: {text: "file write failed", span: (metadata $output_path).span}
            }
        }
    }

    $report
}
