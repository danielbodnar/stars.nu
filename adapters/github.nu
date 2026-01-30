#!/usr/bin/env nu

# ============================================================================
# GitHub API Adapter
# ============================================================================
#
# Fetches starred repositories from GitHub API using the `gh` CLI.
# Handles pagination, caching, and normalization to the standard star schema.
#
# Requirements:
# - gh CLI must be installed and authenticated (`gh auth login`)
#
# Author: Daniel Bodnar
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Fetch a single page from GitHub API
#
# Makes an authenticated API request using gh CLI with optional caching.
# Returns the parsed JSON response as a list.
#
# Parameters:
#   url: string - API endpoint path (relative to api.github.com)
#   use_cache: bool - Whether to use gh's built-in cache
#   cache_duration: string - Cache TTL (e.g., "1h", "30m")
def fetch-page [
    url: string
    use_cache: bool
    cache_duration: string
]: nothing -> list {
    let result = if $use_cache {
        gh api $url --cache $cache_duration | complete
    } else {
        gh api $url | complete
    }

    if $result.exit_code != 0 {
        let error_msg = $result.stderr | str trim

        # Provide helpful suggestions based on common errors
        let help_text = if ($error_msg =~ "authentication") or ($error_msg =~ "401") {
            "Run 'gh auth login' to authenticate with GitHub"
        } else if ($error_msg =~ "rate limit") or ($error_msg =~ "403") {
            "GitHub API rate limit exceeded. Wait a few minutes or use --use-cache"
        } else if ($error_msg =~ "not found") or ($error_msg =~ "404") {
            "The requested resource was not found. Check the username or repository"
        } else {
            "Check your network connection and gh CLI configuration"
        }

        error make {
            msg: $"GitHub API error: ($error_msg)"
            label: {text: "API call failed", span: (metadata $url).span}
            help: $help_text
        }
    }

    try {
        $result.stdout | from json
    } catch {
        error make {
            msg: "Failed to parse GitHub API response"
            label: {text: "JSON parse error", span: (metadata $url).span}
            help: "The API returned invalid JSON. This may indicate a network issue or API change"
        }
    }
}

# Process a page of stars and normalize to our schema
#
# Takes raw GitHub API response and transforms each repo to our standard format.
#
# Parameters:
#   page_data: list - Raw list of repository objects from GitHub API
def process-page [
    page_data: list
]: nothing -> list {
    $page_data | each {|repo| normalize-repo $repo }
}

# Extract owner login from owner object or string
#
# Handles both record format (from API) and string format (from stored data).
def get-owner-login [owner: any]: nothing -> string {
    try {
        let type = $owner | describe | str replace --regex '<.*' ''
        match $type {
            "string" => { $owner | from json | get login }
            "record" => { $owner | get login }
            _ => { "unknown" }
        }
    } catch { "unknown" }
}

# Extract license name from license object or return null
def get-license-name [license: any]: nothing -> string {
    try {
        if ($license | is-empty) or ($license == null) {
            return null
        }

        let type = $license | describe | str replace --regex '<.*' ''
        match $type {
            "string" => {
                let parsed = $license | from json
                $parsed | get name? | default null
            }
            "record" => { $license | get name? | default null }
            _ => { null }
        }
    } catch { null }
}

# Parse topics from array or JSON string
def parse-topics [topics: any]: nothing -> string {
    try {
        let type = $topics | describe | str replace --regex '<.*' ''
        let topic_list = match $type {
            "string" => { $topics | default "[]" | from json }
            "list" => { $topics | default [] }
            _ => { [] }
        }
        $topic_list | to json --raw
    } catch { "[]" }
}

# ============================================================================
# Public API
# ============================================================================

# Normalize a single repo from GitHub API response to our schema
#
# Transforms GitHub's API response format to our standard star schema.
# Handles nested objects (owner, license) and converts topics to JSON string.
#
# Parameters:
#   repo: record - Raw repository object from GitHub API
#
# Example:
#   $api_response | each {|r| normalize-repo $r }
export def normalize-repo [
    repo: record
]: nothing -> record {
    let synced_at = date now | format date "%Y-%m-%dT%H:%M:%SZ"

    {
        id: ($repo.id? | default 0)
        node_id: ($repo.node_id? | default "")
        name: ($repo.name? | default "")
        full_name: ($repo.full_name? | default "")
        owner: (get-owner-login ($repo.owner? | default {login: "unknown"}))
        private: ($repo.private? | default false)
        html_url: ($repo.html_url? | default "")
        description: ($repo.description? | default null)
        fork: ($repo.fork? | default false)
        url: ($repo.url? | default "")
        created_at: ($repo.created_at? | default null)
        updated_at: ($repo.updated_at? | default null)
        pushed_at: ($repo.pushed_at? | default null)
        homepage: ($repo.homepage? | default null)
        size: ($repo.size? | default 0)
        stargazers_count: ($repo.stargazers_count? | default 0)
        watchers_count: ($repo.watchers_count? | default 0)
        language: ($repo.language? | default null)
        forks_count: ($repo.forks_count? | default 0)
        archived: ($repo.archived? | default false)
        disabled: ($repo.disabled? | default false)
        open_issues_count: ($repo.open_issues_count? | default 0)
        license: (get-license-name ($repo.license? | default null))
        topics: (parse-topics ($repo.topics? | default []))
        visibility: ($repo.visibility? | default "public")
        default_branch: ($repo.default_branch? | default "main")
        source: "github"
        synced_at: $synced_at
    }
}

# Fetch all starred repositories from GitHub API
#
# Retrieves all starred repositories for the authenticated user (or specified user)
# using pagination. Results are normalized to our standard schema.
#
# Parameters:
#   --user (-u): string - GitHub username (default: authenticated user)
#   --per-page: int - Items per page, max 100 (default: 100)
#   --use-cache - Use gh CLI's built-in cache for faster repeated requests
#   --cache-duration: string - Cache TTL (default: "1h")
#
# Example:
#   # Fetch all stars for authenticated user
#   fetch
#
#   # Fetch with caching for faster subsequent calls
#   fetch --use-cache
#
#   # Fetch stars for a specific user
#   fetch --user danielbodnar
export def fetch [
    --user (-u): string         # GitHub username (default: authenticated user)
    --per-page: int = 100       # Items per page (max 100)
    --use-cache                 # Use gh api cache
    --cache-duration: string = "1h"  # Cache duration (e.g., "1h", "30m")
]: nothing -> table {
    # Validate per-page (GitHub max is 100)
    let page_size = [$per_page 100] | math min

    # Build the base URL
    let base_url = if ($user | is-empty) or ($user == null) {
        "user/starred"
    } else {
        $"users/($user)/starred"
    }

    # Use generate for pagination
    let results = generate {|state|
        let url = $"($base_url)?per_page=($page_size)&page=($state.page)"

        # Fetch and process the page
        let page_data = try {
            fetch-page $url $use_cache $cache_duration
        } catch {|e|
            # On first page error, propagate it
            if $state.page == 1 {
                error make {
                    msg: $e.msg
                    label: {text: "fetch failed", span: (metadata $url).span}
                }
            }
            # On subsequent pages, treat as end of data
            []
        }

        let page_count = $page_data | length

        if $page_count == 0 {
            # No more data, end iteration
            {out: {stars: [], total: $state.total, done: true}}
        } else {
            # Process and normalize the page
            let normalized = process-page $page_data
            let new_total = $state.total + $page_count

            if $page_count < $page_size {
                # Last page (partial)
                {out: {stars: $normalized, total: $new_total, done: true}}
            } else {
                # More pages available
                {
                    out: {stars: $normalized, total: $new_total, done: false}
                    next: {page: ($state.page + 1), total: $new_total}
                }
            }
        }
    } {page: 1, total: 0}

    # Flatten all stars from all pages
    $results | where {($in.stars | length) > 0} | get stars | flatten
}

# Get the authenticated user's GitHub username
#
# Returns the login name of the currently authenticated GitHub user.
# Useful for verifying authentication status.
#
# Example:
#   let username = get-authenticated-user
export def get-authenticated-user []: nothing -> string {
    let result = gh api user | complete

    if $result.exit_code != 0 {
        error make {
            msg: "Not authenticated with GitHub"
            label: {text: "authentication required", span: (metadata $result).span}
            help: "Run 'gh auth login' to authenticate with GitHub"
        }
    }

    try {
        $result.stdout | from json | get login
    } catch {
        error make {
            msg: "Failed to get authenticated user"
            help: "Check your gh CLI configuration with 'gh auth status'"
        }
    }
}

# Check if gh CLI is installed and authenticated
#
# Returns a record with status information about the gh CLI.
#
# Example:
#   let status = check-auth
#   if not $status.authenticated {
#       print $status.message
#   }
export def check-auth []: nothing -> record<installed: bool, authenticated: bool, user: string, message: string> {
    # Check if gh is installed
    let gh_check = which gh | length
    if $gh_check == 0 {
        return {
            installed: false
            authenticated: false
            user: ""
            message: "gh CLI is not installed. Install it from https://cli.github.com/"
        }
    }

    # Check authentication status
    let auth_result = gh auth status | complete

    if $auth_result.exit_code != 0 {
        return {
            installed: true
            authenticated: false
            user: ""
            message: "Not authenticated. Run 'gh auth login' to authenticate"
        }
    }

    # Get authenticated user
    let user = try {
        get-authenticated-user
    } catch {
        ""
    }

    {
        installed: true
        authenticated: true
        user: $user
        message: $"Authenticated as ($user)"
    }
}
