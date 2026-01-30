#!/usr/bin/env nu

# ============================================================================
# Stars Module - Type Definitions
# ============================================================================
#
# Canonical type schemas and validation helpers for the stars module.
# Defines the unified schema for starred repositories across all sources
# (GitHub, Firefox, Chrome, awesome lists, manual entries).
#
# # Usage
# ```nushell
# use types.nu *
# let schema = star-schema
# let valid = validate-star $record
# ```
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

# ============================================================================
# Type Schemas
# ============================================================================

# Canonical record type for a star/repository entry
#
# This schema represents the unified format for starred repositories
# from any source (GitHub, Firefox bookmarks, Chrome bookmarks, awesome
# lists, or manual entries).
#
# Returns: record with field definitions and metadata
export def star-schema []: nothing -> record {
    {
        fields: {
            id: { type: int, nullable: false, description: "Unique identifier" }
            owner: { type: string, nullable: false, description: "Repository owner (extracted from JSON or direct)" }
            name: { type: string, nullable: false, description: "Repository name" }
            full_name: { type: string, nullable: false, description: "Full name (owner/name)" }
            description: { type: string, nullable: true, description: "Repository description" }
            url: { type: string, nullable: false, description: "HTML URL to repository" }
            homepage: { type: string, nullable: true, description: "Project homepage URL" }
            language: { type: string, nullable: true, description: "Primary programming language" }
            topics: { type: "list<string>", nullable: false, default: [], description: "Repository topics/tags" }
            stars: { type: int, nullable: false, default: 0, description: "Stargazers count" }
            forks: { type: int, nullable: false, default: 0, description: "Forks count" }
            issues: { type: int, nullable: false, default: 0, description: "Open issues count" }
            pushed: { type: datetime, nullable: true, description: "Last push timestamp" }
            created: { type: datetime, nullable: true, description: "Creation timestamp" }
            updated: { type: datetime, nullable: true, description: "Last update timestamp" }
            archived: { type: bool, nullable: false, default: false, description: "Whether repository is archived" }
            fork: { type: bool, nullable: false, default: false, description: "Whether repository is a fork" }
            license: { type: string, nullable: true, description: "License name (e.g., MIT, Apache-2.0)" }
            readme_excerpt: { type: string, nullable: true, description: "Excerpt from README for search" }
            source: { type: string, nullable: false, default: "github", description: "Data source: github|firefox|chrome|awesome|manual" }
            synced_at: { type: datetime, nullable: false, description: "When this record was last synced" }
        }
        required: [id, owner, name, full_name, url, source, synced_at]
        version: "1.0.0"
    }
}

# Schema for Polars LazyFrame with proper dtypes
#
# Defines column types for use with nu_plugin_polars when creating
# or loading DataFrames/LazyFrames.
#
# Returns: record mapping column names to Polars dtype strings
export def polars-schema []: nothing -> record {
    {
        id: "i64"
        owner: "str"
        name: "str"
        full_name: "str"
        description: "str"
        url: "str"
        homepage: "str"
        language: "str"
        topics: "str"  # JSON-encoded list, parsed at query time
        stars: "i64"
        forks: "i64"
        issues: "i64"
        pushed: "datetime[us]"
        created: "datetime[us]"
        updated: "datetime[us]"
        archived: "bool"
        fork: "bool"
        license: "str"
        readme_excerpt: "str"
        source: "str"
        synced_at: "datetime[us]"
    }
}

# ============================================================================
# Display Configuration
# ============================================================================

# Default columns for display output
#
# These columns are shown by default when listing or displaying stars.
# Order matters - columns are displayed left to right.
#
# Returns: list of column names
export def default-columns []: nothing -> list<string> {
    [owner, name, language, stars, pushed, homepage, topics, description, forks, issues]
}

# Minimal columns for compact display
#
# Returns: list of column names for compact output
export def minimal-columns []: nothing -> list<string> {
    [owner, name, language, stars]
}

# All available columns
#
# Returns: list of all column names in schema order
export def all-columns []: nothing -> list<string> {
    [
        id, owner, name, full_name, description, url, homepage, language,
        topics, stars, forks, issues, pushed, created, updated, archived,
        fork, license, readme_excerpt, source, synced_at
    ]
}

# ============================================================================
# Filter Configuration
# ============================================================================

# Default excluded languages
#
# Languages that are excluded by default when filtering.
# These can be overridden via --include-language flag.
#
# Returns: list of language names to exclude
export def excluded-languages []: nothing -> list<string> {
    [PHP, "C#", Java, Python, Ruby]
}

# Valid source identifiers
#
# Returns: list of valid source values
export def valid-sources []: nothing -> list<string> {
    [github, firefox, chrome, awesome, manual]
}

# ============================================================================
# Helper Functions
# ============================================================================

# Parse topics from JSON string or list
#
# Handles topics stored as either a JSON-encoded string (from SQLite)
# or as a native Nushell list. Returns empty list on parse failure.
#
# Parameters:
#   topics: any - Topics as JSON string, list, or null
#
# Returns: list<string> - Parsed topics list
#
# Example:
#   parse-topics '["rust", "cli"]'  # => [rust, cli]
#   parse-topics ["rust", "cli"]    # => [rust, cli]
#   parse-topics null               # => []
export def parse-topics [topics: any]: nothing -> list<string> {
    if ($topics == null) {
        return []
    }

    let type = $topics | describe | str replace --regex '<.*' ''

    try {
        match $type {
            "string" => {
                let trimmed = $topics | str trim
                if ($trimmed | is-empty) or $trimmed == "null" {
                    []
                } else {
                    $trimmed | from json | default []
                }
            }
            "list" => { $topics | default [] }
            _ => { [] }
        }
    } catch {
        []
    }
}

# Get owner login from JSON string or record
#
# Extracts the owner login from GitHub API response format.
# Handles both JSON-encoded string (from SQLite) and native record.
#
# Parameters:
#   owner: any - Owner as JSON string, record, or plain string
#
# Returns: string - Owner login name, or "unknown" if extraction fails
#
# Example:
#   get-owner-login '{"login": "rust-lang"}'  # => rust-lang
#   get-owner-login {login: "rust-lang"}      # => rust-lang
#   get-owner-login "rust-lang"               # => rust-lang
export def get-owner-login [owner: any]: nothing -> string {
    if ($owner == null) {
        return "unknown"
    }

    let type = $owner | describe | str replace --regex '<.*' ''

    try {
        match $type {
            "string" => {
                let trimmed = $owner | str trim
                if ($trimmed | is-empty) or $trimmed == "null" {
                    "unknown"
                } else if ($trimmed | str starts-with "{") {
                    # JSON object
                    $trimmed | from json | get login? | default "unknown"
                } else {
                    # Plain string (already a login name)
                    $trimmed
                }
            }
            "record" => { $owner | get login? | default "unknown" }
            _ => { "unknown" }
        }
    } catch {
        "unknown"
    }
}

# Validate a record against star-schema
#
# Checks that a record has all required fields and valid types.
# Returns a validation result record with status and any errors.
#
# Parameters:
#   record: record - The record to validate
#
# Returns: record with fields:
#   - valid: bool - Whether validation passed
#   - errors: list<string> - List of validation error messages
#   - warnings: list<string> - List of validation warnings
#
# Example:
#   validate-star {id: 1, owner: "rust-lang", name: "rust", ...}
export def validate-star [star: record]: nothing -> record<valid: bool, errors: list<string>, warnings: list<string>> {
    let schema = star-schema
    mut errors = []
    mut warnings = []

    # Check required fields
    for required in $schema.required {
        if not ($required in $star) {
            $errors = ($errors | append $"Missing required field: ($required)")
        }
    }

    # Type validations for present fields
    if "id" in $star {
        let id_type = $star.id | describe
        if not ($id_type =~ "int") {
            $errors = ($errors | append $"Field 'id' must be int, got ($id_type)")
        }
    }

    if "owner" in $star {
        let owner_type = $star.owner | describe | str replace --regex '<.*' ''
        if $owner_type != "string" {
            $errors = ($errors | append $"Field 'owner' must be string, got ($owner_type)")
        }
    }

    if "name" in $star {
        let name_type = $star.name | describe | str replace --regex '<.*' ''
        if $name_type != "string" {
            $errors = ($errors | append $"Field 'name' must be string, got ($name_type)")
        }
    }

    if "full_name" in $star {
        let full_name_type = $star.full_name | describe | str replace --regex '<.*' ''
        if $full_name_type != "string" {
            $errors = ($errors | append $"Field 'full_name' must be string, got ($full_name_type)")
        }
    }

    if "url" in $star {
        let url_type = $star.url | describe | str replace --regex '<.*' ''
        if $url_type != "string" {
            $errors = ($errors | append $"Field 'url' must be string, got ($url_type)")
        } else if not ($star.url | str starts-with "http") {
            $warnings = ($warnings | append "Field 'url' should start with http:// or https://")
        }
    }

    if "source" in $star {
        let valid = valid-sources
        if not ($star.source in $valid) {
            $errors = ($errors | append $"Field 'source' must be one of: ($valid | str join ', ')")
        }
    }

    if "stars" in $star {
        let stars_type = $star.stars | describe
        if not ($stars_type =~ "int") {
            $warnings = ($warnings | append $"Field 'stars' should be int, got ($stars_type)")
        }
    }

    if "forks" in $star {
        let forks_type = $star.forks | describe
        if not ($forks_type =~ "int") {
            $warnings = ($warnings | append $"Field 'forks' should be int, got ($forks_type)")
        }
    }

    if "issues" in $star {
        let issues_type = $star.issues | describe
        if not ($issues_type =~ "int") {
            $warnings = ($warnings | append $"Field 'issues' should be int, got ($issues_type)")
        }
    }

    if "archived" in $star {
        let archived_type = $star.archived | describe
        if $archived_type != "bool" {
            $warnings = ($warnings | append $"Field 'archived' should be bool, got ($archived_type)")
        }
    }

    if "fork" in $star {
        let fork_type = $star.fork | describe
        if $fork_type != "bool" {
            $warnings = ($warnings | append $"Field 'fork' should be bool, got ($fork_type)")
        }
    }

    if "topics" in $star {
        let topics_type = $star.topics | describe | str replace --regex '<.*' ''
        if $topics_type not-in ["list", "string"] {
            $warnings = ($warnings | append $"Field 'topics' should be list or JSON string, got ($topics_type)")
        }
    }

    let is_valid = ($errors | length) == 0

    {
        valid: $is_valid
        errors: $errors
        warnings: $warnings
    }
}

# Normalize a raw GitHub API response to canonical schema
#
# Transforms a raw repository record from the GitHub API into
# the canonical star schema format.
#
# Parameters:
#   raw: record - Raw GitHub API repository response
#
# Returns: record - Normalized star record
#
# Example:
#   $github_repo | normalize-github-star
export def normalize-github-star [raw: record]: nothing -> record {
    let owner = get-owner-login ($raw.owner? | default "unknown")
    let license_name = try {
        $raw.license? | default {} | get name? | default null
    } catch { null }

    {
        id: ($raw.id? | default 0)
        owner: $owner
        name: ($raw.name? | default "")
        full_name: ($raw.full_name? | default $"($owner)/($raw.name? | default '')")
        description: ($raw.description? | default null)
        url: ($raw.html_url? | default "")
        homepage: ($raw.homepage? | default null)
        language: ($raw.language? | default null)
        topics: (parse-topics ($raw.topics? | default []))
        stars: ($raw.stargazers_count? | default 0)
        forks: ($raw.forks_count? | default 0)
        issues: ($raw.open_issues_count? | default 0)
        pushed: ($raw.pushed_at? | default null)
        created: ($raw.created_at? | default null)
        updated: ($raw.updated_at? | default null)
        archived: ($raw.archived? | default false)
        fork: ($raw.fork? | default false)
        license: $license_name
        readme_excerpt: null
        source: "github"
        synced_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
    }
}

# Create an empty star record with defaults
#
# Returns a record with all schema fields set to their default values.
# Useful for creating new entries or testing.
#
# Returns: record - Star record with default values
export def empty-star []: nothing -> record {
    {
        id: 0
        owner: ""
        name: ""
        full_name: ""
        description: null
        url: ""
        homepage: null
        language: null
        topics: []
        stars: 0
        forks: 0
        issues: 0
        pushed: null
        created: null
        updated: null
        archived: false
        fork: false
        license: null
        readme_excerpt: null
        source: "manual"
        synced_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
    }
}
