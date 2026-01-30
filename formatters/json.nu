#!/usr/bin/env nu

# ============================================================================
# JSON and Machine-Readable Formatters for Stars Module
# ============================================================================
#
# Provides JSON, CSV, NUON, and Markdown table formatters for machine-readable
# output of starred repository data.
#
# # Usage
# ```nushell
# use json.nu *
# $data | to-json-output --pretty
# $data | to-csv-output --columns [name url stars]
# $data | to-nuon-output
# $data | to-md-output
# ```
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Parse topics from JSON string or list to ensure consistent list format
def parse-topics-internal [topics: any]: nothing -> list<string> {
    if ($topics | is-empty) { return [] }

    let type = $topics | describe | str replace --regex '<.*' ''
    match $type {
        "string" => {
            try { $topics | from json } catch { [] }
        }
        "list" => { $topics }
        _ => { [] }
    }
}

# Extract owner login from owner field (handles JSON string or record)
def get-owner-login-internal [owner: any]: nothing -> string {
    if ($owner | is-empty) { return "unknown" }

    let type = $owner | describe | str replace --regex '<.*' ''
    match $type {
        "string" => {
            try { $owner | from json | get login? | default "unknown" } catch { "unknown" }
        }
        "record" => {
            $owner | get login? | default "unknown"
        }
        _ => { "unknown" }
    }
}

# Format datetime to ISO 8601 string
def format-iso8601 [date_value: any]: nothing -> string {
    if ($date_value | is-empty) { return "" }

    try {
        let type = $date_value | describe | str replace --regex '<.*' ''
        match $type {
            "datetime" => { $date_value | format date "%Y-%m-%dT%H:%M:%SZ" }
            "string" => {
                # Already a string, try to parse and reformat for consistency
                try {
                    $date_value | into datetime | format date "%Y-%m-%dT%H:%M:%SZ"
                } catch {
                    $date_value
                }
            }
            _ => { "" }
        }
    } catch { "" }
}

# Sanitize string for safe output (handle nulls and special chars)
def sanitize-string [value: any]: nothing -> string {
    if ($value | is-empty) { return "" }
    $value | to text
}

# Transform repository to minimal schema
def transform-minimal [repo: record]: nothing -> record {
    {
        name: (sanitize-string ($repo.full_name? | default ($repo.name? | default "")))
        url: (sanitize-string ($repo.html_url? | default ($repo.url? | default "")))
        description: (sanitize-string ($repo.description? | default ""))
        language: (sanitize-string ($repo.language? | default ""))
        stars: ($repo.stargazers_count? | default ($repo.stars? | default 0))
        topics: (parse-topics-internal ($repo.topics? | default []))
    }
}

# Transform repository for CSV export (flatten complex fields)
def transform-for-csv [repo: record]: nothing -> record {
    let topics = parse-topics-internal ($repo.topics? | default []) | str join ";"
    let owner = get-owner-login-internal ($repo.owner? | default "")

    # Handle license field which may be JSON string or record
    let license = if ($repo.license? | is-empty) {
        ""
    } else {
        let license_type = $repo.license | describe | str replace --regex '<.*' ''
        match $license_type {
            "string" => {
                try { $repo.license | from json | get name? | default "" } catch { "" }
            }
            "record" => {
                $repo.license | get name? | default ""
            }
            _ => { "" }
        }
    }

    {
        name: (sanitize-string ($repo.name? | default ""))
        full_name: (sanitize-string ($repo.full_name? | default ""))
        url: (sanitize-string ($repo.html_url? | default ($repo.url? | default "")))
        description: (sanitize-string ($repo.description? | default ""))
        language: (sanitize-string ($repo.language? | default ""))
        stars: ($repo.stargazers_count? | default ($repo.stars? | default 0))
        forks: ($repo.forks_count? | default ($repo.forks? | default 0))
        created_at: (format-iso8601 ($repo.created_at? | default ""))
        updated_at: (format-iso8601 ($repo.updated_at? | default ""))
        pushed_at: (format-iso8601 ($repo.pushed_at? | default ""))
        owner: $owner
        topics: $topics
        license: $license
        archived: ($repo.archived? | default false)
        is_fork: ($repo.fork? | default false)
    }
}

# ============================================================================
# Export Functions
# ============================================================================

# Format data as JSON
#
# Converts table data to JSON format with options for pretty printing
# and minimal schema output.
#
# Parameters:
#   data: table - The data to format
#   --pretty (-p): bool - Pretty print with indentation
#   --minimal (-m): bool - Use minimal schema (fewer fields)
#
# Returns: string - JSON formatted output
#
# Example:
#   $stars | to-json-output --pretty
#   $stars | to-json-output --minimal
export def to-json-output [
    data: table                    # Data to format as JSON
    --pretty (-p)                  # Pretty print with indentation
    --minimal (-m)                 # Minimal schema (fewer fields)
]: nothing -> string {
    # Handle empty table
    if ($data | is-empty) {
        return "[]"
    }

    let transformed = if $minimal {
        $data | each {|repo| transform-minimal $repo }
    } else {
        $data
    }

    if $pretty {
        $transformed | to json --indent 2
    } else {
        $transformed | to json
    }
}

# Format data as CSV
#
# Converts table data to CSV format, transforming complex fields
# (topics, owner, dates) to flat string representations.
#
# Parameters:
#   data: table - The data to format
#   --columns: list<string> - Specific columns to include (empty = all)
#   --no-header: bool - Omit header row
#
# Returns: string - CSV formatted output
#
# Example:
#   $stars | to-csv-output
#   $stars | to-csv-output --columns [name url stars]
#   $stars | to-csv-output --no-header
export def to-csv-output [
    data: table                              # Data to format as CSV
    --columns: list<string> = []             # Specific columns to include
    --no-header                              # Omit header row
]: nothing -> string {
    # Handle empty table
    if ($data | is-empty) {
        return ""
    }

    # Transform data for CSV (flatten complex fields)
    let transformed = $data | each {|repo| transform-for-csv $repo }

    # Select specific columns if requested
    let export_data = if ($columns | length) > 0 {
        # Filter to only valid columns that exist in the data
        let available_columns = $transformed | first | columns
        let valid_columns = $columns | where {|col| $col in $available_columns }

        if ($valid_columns | length) == 0 {
            $transformed
        } else {
            $transformed | select ...$valid_columns
        }
    } else {
        $transformed
    }

    if $no_header {
        # Generate CSV without header by skipping first line
        let full_csv = $export_data | to csv
        let lines = $full_csv | lines
        if ($lines | length) > 1 {
            $lines | skip 1 | str join "\n"
        } else {
            ""
        }
    } else {
        $export_data | to csv
    }
}

# Format data as NUON (Nushell Object Notation)
#
# Converts table data to NUON format, which is Nushell's native
# serialization format that preserves types.
#
# Parameters:
#   data: table - The data to format
#   --pretty (-p): bool - Pretty print with indentation
#
# Returns: string - NUON formatted output
#
# Example:
#   $stars | to-nuon-output
#   $stars | to-nuon-output --pretty
export def to-nuon-output [
    data: table                    # Data to format as NUON
    --pretty (-p)                  # Pretty print with indentation
]: nothing -> string {
    # Handle empty table
    if ($data | is-empty) {
        return "[]"
    }

    if $pretty {
        $data | to nuon --indent 2
    } else {
        $data | to nuon
    }
}

# Format data as Markdown table
#
# Converts table data to a Markdown-formatted table for
# documentation or readable output.
#
# Parameters:
#   data: table - The data to format
#   --columns: list<string> - Specific columns to include (empty = all)
#
# Returns: string - Markdown table formatted output
#
# Example:
#   $stars | to-md-output
#   $stars | to-md-output --columns [name language stars]
export def to-md-output [
    data: table                              # Data to format as Markdown
    --columns: list<string> = []             # Specific columns to include
]: nothing -> string {
    # Handle empty table
    if ($data | is-empty) {
        return ""
    }

    # Transform data for readable output
    let transformed = $data | each {|repo|
        let topics = parse-topics-internal ($repo.topics? | default []) | str join ", "
        let owner = get-owner-login-internal ($repo.owner? | default "")

        {
            name: (sanitize-string ($repo.full_name? | default ($repo.name? | default "")))
            url: (sanitize-string ($repo.html_url? | default ($repo.url? | default "")))
            description: (sanitize-string ($repo.description? | default "") | str substring 0..100)
            language: (sanitize-string ($repo.language? | default ""))
            stars: ($repo.stargazers_count? | default ($repo.stars? | default 0))
            forks: ($repo.forks_count? | default ($repo.forks? | default 0))
            owner: $owner
            topics: $topics
            archived: ($repo.archived? | default false)
        }
    }

    # Select specific columns if requested
    let export_data = if ($columns | length) > 0 {
        let available_columns = $transformed | first | columns
        let valid_columns = $columns | where {|col| $col in $available_columns }

        if ($valid_columns | length) == 0 {
            $transformed
        } else {
            $transformed | select ...$valid_columns
        }
    } else {
        $transformed
    }

    $export_data | to md
}

# ============================================================================
# Convenience Wrappers
# ============================================================================

# Export data to JSON file
#
# Convenience wrapper that formats data as JSON and saves to a file.
#
# Parameters:
#   data: table - The data to export
#   path: path - Output file path
#   --pretty (-p): bool - Pretty print with indentation
#   --minimal (-m): bool - Use minimal schema
#
# Returns: path - The output file path
#
# Example:
#   $stars | export-json ./stars.json --pretty
export def export-json [
    data: table                    # Data to export
    path: path                     # Output file path
    --pretty (-p)                  # Pretty print with indentation
    --minimal (-m)                 # Minimal schema (fewer fields)
]: nothing -> path {
    let output = if $minimal {
        to-json-output $data --minimal --pretty=$pretty
    } else if $pretty {
        to-json-output $data --pretty
    } else {
        to-json-output $data
    }

    $output | save --force $path
    $path
}

# Export data to CSV file
#
# Convenience wrapper that formats data as CSV and saves to a file.
#
# Parameters:
#   data: table - The data to export
#   path: path - Output file path
#   --columns: list<string> - Specific columns to include
#   --no-header: bool - Omit header row
#
# Returns: path - The output file path
#
# Example:
#   $stars | export-csv ./stars.csv
#   $stars | export-csv ./stars.csv --columns [name url stars]
export def export-csv [
    data: table                              # Data to export
    path: path                               # Output file path
    --columns: list<string> = []             # Specific columns to include
    --no-header                              # Omit header row
]: nothing -> path {
    let output = if $no_header {
        to-csv-output $data --columns $columns --no-header
    } else {
        to-csv-output $data --columns $columns
    }

    $output | save --force $path
    $path
}

# Export data to NUON file
#
# Convenience wrapper that formats data as NUON and saves to a file.
#
# Parameters:
#   data: table - The data to export
#   path: path - Output file path
#   --pretty (-p): bool - Pretty print with indentation
#
# Returns: path - The output file path
#
# Example:
#   $stars | export-nuon ./stars.nuon --pretty
export def export-nuon [
    data: table                    # Data to export
    path: path                     # Output file path
    --pretty (-p)                  # Pretty print with indentation
]: nothing -> path {
    let output = if $pretty {
        to-nuon-output $data --pretty
    } else {
        to-nuon-output $data
    }

    $output | save --force $path
    $path
}

# Export data to Markdown file
#
# Convenience wrapper that formats data as Markdown and saves to a file.
#
# Parameters:
#   data: table - The data to export
#   path: path - Output file path
#   --columns: list<string> - Specific columns to include
#
# Returns: path - The output file path
#
# Example:
#   $stars | export-md ./stars.md
#   $stars | export-md ./stars.md --columns [name language stars]
export def export-md [
    data: table                              # Data to export
    path: path                               # Output file path
    --columns: list<string> = []             # Specific columns to include
]: nothing -> path {
    let output = to-md-output $data --columns $columns
    $output | save --force $path
    $path
}
