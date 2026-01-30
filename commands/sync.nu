#!/usr/bin/env nu

# ============================================================================
# Stars Sync Module
# ============================================================================
#
# Synchronization commands for fetching stars from various sources:
# - GitHub starred repositories (via gh CLI)
# - Firefox bookmarks (via places.sqlite)
# - Chrome bookmarks (via Bookmarks JSON)
# - Awesome lists (via markdown parsing)
#
# # Usage
# ```nushell
# use sync.nu *
# stars sync github          # Sync from GitHub
# stars sync firefox         # Sync from Firefox bookmarks
# stars sync all             # Sync all configured sources
# ```
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

use ../core/storage.nu
use ../core/types.nu

# ============================================================================
# Internal Helpers
# ============================================================================

# Fetch a single page from GitHub API
def fetch-github-page [
    url: string
    use_cache: bool
]: nothing -> list {
    let result = if $use_cache {
        gh api $url --cache 1h | complete
    } else {
        gh api $url | complete
    }

    if $result.exit_code != 0 {
        error make {
            msg: $"GitHub API error: ($result.stderr)"
            label: {text: "API call failed", span: (metadata $url).span}
        }
    }

    try {
        $result.stdout | from json
    } catch {
        error make {
            msg: "Failed to parse GitHub API response"
            label: {text: "JSON parse error", span: (metadata $url).span}
        }
    }
}

# Process a single page of GitHub stars
def process-github-page [
    page_data: list
    ctx: record<db_path: path, page: int, total: int, page_size: int, verbose: bool>
]: nothing -> record<done: bool, total: int, stars: list, next_page: any> {
    let page_count = $page_data | length

    if $page_count == 0 {
        {done: true, total: $ctx.total, stars: [], next_page: null}
    } else {
        # Normalize each star to canonical schema
        let normalized = $page_data | each {|raw|
            types normalize-github-star $raw
        }

        # Insert into database
        $normalized | into sqlite $ctx.db_path --table-name stars

        let new_total = $ctx.total + $page_count

        if $ctx.verbose {
            print --stderr $"  Page ($ctx.page): ($page_count) stars \(total: ($new_total)\)"
        }

        if $page_count < $ctx.page_size {
            {done: true, total: $new_total, stars: $normalized, next_page: null}
        } else {
            {done: false, total: $new_total, stars: $normalized, next_page: ($ctx.page + 1)}
        }
    }
}

# Core GitHub fetch implementation using generate pattern
def fetch-github-stars-impl [
    ctx: record<page_size: int, use_cache: bool, db_path: path, user: string, verbose: bool>
]: nothing -> table {
    let api_base = if ($ctx.user | is-empty) {
        "user/starred"
    } else {
        $"users/($ctx.user)/starred"
    }

    let results = generate {|state|
        let url = $"($api_base)?per_page=($ctx.page_size)&page=($state.page)"
        let page_data = fetch-github-page $url $ctx.use_cache
        let result = process-github-page $page_data {
            db_path: $ctx.db_path
            page: $state.page
            total: $state.total
            page_size: $ctx.page_size
            verbose: $ctx.verbose
        }

        if $result.done {
            {out: $result}
        } else {
            {
                out: $result
                next: {page: $result.next_page, total: $result.total}
            }
        }
    } {page: 1, total: 0}

    $results | where {($in.stars | length) > 0} | get stars | flatten
}

# Get default Firefox places.sqlite path (returns null if not found)
def get-firefox-places-path [] {
    let home = $nu.home-dir

    # Linux: ~/.mozilla/firefox/<profile>/places.sqlite
    let linux_path = $home | path join .mozilla firefox
    if ($linux_path | path exists) {
        let profiles = try { ls $linux_path | where type == dir } catch { [] }
        let default_profile = $profiles | where name =~ '\.default' | first?
        if $default_profile != null {
            let places = $default_profile.name | path join places.sqlite
            if ($places | path exists) {
                return $places
            }
        }
    }

    # macOS: ~/Library/Application Support/Firefox/Profiles/<profile>/places.sqlite
    let macos_path = $home | path join Library "Application Support" Firefox Profiles
    if ($macos_path | path exists) {
        let profiles = try { ls $macos_path | where type == dir } catch { [] }
        let default_profile = $profiles | where name =~ '\.default' | first?
        if $default_profile != null {
            let places = $default_profile.name | path join places.sqlite
            if ($places | path exists) {
                return $places
            }
        }
    }

    null
}

# Get default Chrome bookmarks path (returns null if not found)
def get-chrome-bookmarks-path [] {
    let home = $nu.home-dir

    # Linux: ~/.config/google-chrome/Default/Bookmarks or ~/.config/chromium/Default/Bookmarks
    let chrome_linux = $home | path join .config google-chrome Default Bookmarks
    if ($chrome_linux | path exists) {
        return $chrome_linux
    }

    let chromium_linux = $home | path join .config chromium Default Bookmarks
    if ($chromium_linux | path exists) {
        return $chromium_linux
    }

    # macOS: ~/Library/Application Support/Google/Chrome/Default/Bookmarks
    let chrome_macos = $home | path join Library "Application Support" Google Chrome Default Bookmarks
    if ($chrome_macos | path exists) {
        return $chrome_macos
    }

    null
}

# ============================================================================
# Public Commands
# ============================================================================

# Sync starred repositories from specified source
#
# Main entry point for synchronization. Dispatches to source-specific
# sync commands based on the source parameter.
#
# Parameters:
#   source: string - Source to sync from (github, firefox, chrome, awesome, all)
#   --refresh (-r) - Force refresh, bypass cache
#   --no-cache - Don't use GitHub API cache
#   --verbose (-v) - Show detailed progress
#
# Example:
#   stars sync                # Sync from GitHub (default)
#   stars sync github -r      # Force refresh from GitHub
#   stars sync all            # Sync all configured sources
export def "stars sync" [
    source: string = "github"  # Source: github, firefox, chrome, awesome, all
    --refresh (-r)             # Force refresh, bypass cache
    --no-cache                 # Don't use GitHub API cache
    --verbose (-v)             # Show detailed progress
]: nothing -> nothing {
    let valid_sources = types valid-sources | append "all"

    if $source not-in $valid_sources {
        error make {
            msg: $"Invalid source: ($source)"
            help: $"Valid sources: ($valid_sources | str join ', ')"
        }
    }

    match $source {
        "github" => {
            if $no_cache or $refresh {
                stars sync github --no-cache --verbose=$verbose
            } else {
                stars sync github --verbose=$verbose
            }
        }
        "firefox" => { stars sync firefox }
        "chrome" => { stars sync chrome }
        "awesome" => {
            error make {
                msg: "Awesome list sync requires a URL or path"
                help: "Use: stars sync awesome <url_or_path>"
            }
        }
        "all" => {
            if $refresh {
                stars sync all --refresh
            } else {
                stars sync all
            }
        }
        _ => {
            error make {
                msg: $"Unknown source: ($source)"
            }
        }
    }
}

# Sync starred repositories from GitHub
#
# Fetches all starred repositories for the authenticated user (or specified
# user) using the GitHub API via the gh CLI. Stores results in SQLite
# with source="github" and updates synced_at timestamp.
#
# Parameters:
#   --user (-u): string - GitHub username (default: authenticated user)
#   --refresh (-r) - Force refresh, removes existing GitHub entries first
#   --no-cache - Bypass gh CLI cache for fresh data
#   --per-page: int - Items per API page (max 100)
#   --verbose (-v) - Show detailed progress
#
# Example:
#   stars sync github              # Sync authenticated user's stars
#   stars sync github -u rust-lang # Sync rust-lang's stars
#   stars sync github --refresh    # Force complete refresh
export def "stars sync github" [
    --user (-u): string        # GitHub username (default: authenticated user)
    --refresh (-r)             # Force refresh, bypass cache
    --no-cache                 # Don't use GitHub API cache
    --per-page: int = 100      # Items per API page (max 100)
    --verbose (-v)             # Show detailed progress
]: nothing -> nothing {
    let paths = storage get-paths
    let page_size = [$per_page 100] | math min
    let use_cache = not ($no_cache or $refresh)
    let target_user = $user | default ""

    storage ensure-storage

    # Check gh CLI authentication
    let auth_check = do { gh auth status } | complete
    if $auth_check.exit_code != 0 {
        error make {
            msg: "GitHub CLI not authenticated"
            help: "Run 'gh auth login' to authenticate"
        }
    }

    if $verbose {
        if ($target_user | is-empty) {
            print --stderr "Syncing stars for authenticated user..."
        } else {
            print --stderr $"Syncing stars for user: ($target_user)..."
        }
        print --stderr $"  Cache: (if $use_cache { 'enabled (1h)' } else { 'disabled' })"
        print --stderr $"  Page size: ($page_size)"
    }

    # Handle refresh: remove existing GitHub entries
    if $refresh and ($paths.db_path | path exists) {
        if $verbose {
            print --stderr "  Removing existing GitHub entries..."
        }
        try {
            open $paths.db_path | query db "DELETE FROM stars WHERE source = 'github'"
        } catch {
            # Table may not exist yet, that's fine
        }
    }

    # Create backup before major sync if database exists
    if ($paths.db_path | path exists) {
        let stats = storage get-stats
        if $stats.total_stars > 100 {
            if $verbose {
                print --stderr "  Creating backup..."
            }
            try {
                storage backup | ignore
            } catch {
                # Non-fatal, continue
            }
        }
    }

    # Fetch all stars from GitHub
    let all_stars = fetch-github-stars-impl {
        page_size: $page_size
        use_cache: $use_cache
        db_path: $paths.db_path
        user: $target_user
        verbose: $verbose
    }

    let star_count = $all_stars | length

    if $verbose {
        print --stderr $"Sync complete: ($star_count) GitHub stars"
    } else {
        print --stderr $"Synced ($star_count) stars from GitHub"
    }
}

# Sync bookmarks from Firefox
#
# Imports bookmarks from Firefox's places.sqlite database. Converts
# bookmark entries to the canonical star schema with source="firefox".
#
# Note: This is a stub implementation. The actual adapter for parsing
# Firefox places.sqlite will be implemented separately.
#
# Parameters:
#   --file (-f): path - Path to places.sqlite (auto-detect if not provided)
#   --folder: string - Specific bookmark folder to import
#   --verbose (-v) - Show detailed progress
#
# Example:
#   stars sync firefox                                    # Auto-detect location
#   stars sync firefox -f ~/.mozilla/firefox/.../places.sqlite
#   stars sync firefox --folder "GitHub Projects"
export def "stars sync firefox" [
    --file (-f): path          # Path to places.sqlite (auto-detect if not provided)
    --folder: string           # Specific bookmark folder to import
    --verbose (-v)             # Show detailed progress
]: nothing -> nothing {
    let places_path = if $file != null {
        $file
    } else {
        let detected = get-firefox-places-path
        if $detected == null {
            error make {
                msg: "Firefox places.sqlite not found"
                help: "Provide the path explicitly with --file"
            }
        }
        $detected
    }

    if not ($places_path | path exists) {
        error make {
            msg: $"Firefox places.sqlite not found at: ($places_path)"
            help: "Check the path or provide a valid --file"
        }
    }

    if $verbose {
        print --stderr $"Reading Firefox bookmarks from: ($places_path)"
        if $folder != null {
            print --stderr $"  Filtering folder: ($folder)"
        }
    }

    # TODO: Implement via adapters/firefox.nu
    # For now, print a stub message
    print --stderr "Firefox sync not yet implemented"
    print --stderr "Adapter will be added in adapters/firefox.nu"

    # Stub: would call something like:
    # use ../adapters/firefox.nu
    # let bookmarks = firefox parse-bookmarks $places_path --folder=$folder
    # let normalized = $bookmarks | each {|b| firefox normalize-bookmark $b }
    # storage save $normalized
}

# Sync bookmarks from Chrome/Chromium
#
# Imports bookmarks from Chrome's Bookmarks JSON file. Converts
# bookmark entries to the canonical star schema with source="chrome".
#
# Note: This is a stub implementation. The actual adapter for parsing
# Chrome bookmarks will be implemented separately.
#
# Parameters:
#   --file (-f): path - Path to Bookmarks JSON (auto-detect if not provided)
#   --folder: string - Specific bookmark folder to import
#   --verbose (-v) - Show detailed progress
#
# Example:
#   stars sync chrome                                    # Auto-detect location
#   stars sync chrome -f ~/.config/google-chrome/.../Bookmarks
#   stars sync chrome --folder "GitHub"
export def "stars sync chrome" [
    --file (-f): path          # Path to Bookmarks JSON (auto-detect if not provided)
    --folder: string           # Specific bookmark folder to import
    --verbose (-v)             # Show detailed progress
]: nothing -> nothing {
    let bookmarks_path = if $file != null {
        $file
    } else {
        let detected = get-chrome-bookmarks-path
        if $detected == null {
            error make {
                msg: "Chrome Bookmarks not found"
                help: "Provide the path explicitly with --file"
            }
        }
        $detected
    }

    if not ($bookmarks_path | path exists) {
        error make {
            msg: $"Chrome Bookmarks not found at: ($bookmarks_path)"
            help: "Check the path or provide a valid --file"
        }
    }

    if $verbose {
        print --stderr $"Reading Chrome bookmarks from: ($bookmarks_path)"
        if $folder != null {
            print --stderr $"  Filtering folder: ($folder)"
        }
    }

    # TODO: Implement via adapters/chrome.nu
    # For now, print a stub message
    print --stderr "Chrome sync not yet implemented"
    print --stderr "Adapter will be added in adapters/chrome.nu"

    # Stub: would call something like:
    # use ../adapters/chrome.nu
    # let bookmarks = chrome parse-bookmarks $bookmarks_path --folder=$folder
    # let normalized = $bookmarks | each {|b| chrome normalize-bookmark $b }
    # storage save $normalized
}

# Sync entries from an awesome list
#
# Parses an awesome list markdown file (local or remote) and extracts
# repository links. Converts entries to canonical star schema with
# source="awesome".
#
# Note: This is a stub implementation. The actual adapter for parsing
# awesome lists will be implemented separately.
#
# Parameters:
#   url_or_path: string - URL or local path to awesome list markdown
#   --verbose (-v) - Show detailed progress
#
# Example:
#   stars sync awesome https://raw.githubusercontent.com/rust-unofficial/awesome-rust/main/README.md
#   stars sync awesome ~/projects/awesome-rust/README.md
export def "stars sync awesome" [
    url_or_path: string        # URL or local path to awesome list markdown
    --verbose (-v)             # Show detailed progress
]: nothing -> nothing {
    let is_url = $url_or_path | str starts-with "http"

    if $verbose {
        if $is_url {
            print --stderr $"Fetching awesome list from: ($url_or_path)"
        } else {
            print --stderr $"Reading awesome list from: ($url_or_path)"
        }
    }

    if not $is_url {
        if not ($url_or_path | path exists) {
            error make {
                msg: $"Awesome list file not found: ($url_or_path)"
            }
        }
    }

    # TODO: Implement via adapters/awesome.nu
    # For now, print a stub message
    print --stderr "Awesome list sync not yet implemented"
    print --stderr "Adapter will be added in adapters/awesome.nu"

    # Stub: would call something like:
    # use ../adapters/awesome.nu
    # let content = if $is_url { http get $url_or_path } else { open $url_or_path }
    # let entries = awesome parse-list $content
    # let normalized = $entries | each {|e| awesome normalize-entry $e }
    # storage save $normalized
}

# Sync from all configured sources
#
# Runs sync for all available sources in sequence:
# 1. GitHub (authenticated user)
# 2. Firefox bookmarks (if places.sqlite found)
# 3. Chrome bookmarks (if Bookmarks found)
#
# Awesome lists are not included as they require explicit URLs.
#
# Parameters:
#   --refresh (-r) - Force refresh all sources
#   --verbose (-v) - Show detailed progress
#
# Example:
#   stars sync all              # Sync all sources
#   stars sync all --refresh    # Force refresh all sources
export def "stars sync all" [
    --refresh (-r)             # Force refresh all sources
    --verbose (-v)             # Show detailed progress
]: nothing -> nothing {
    print --stderr "Syncing all configured sources..."
    print --stderr ""

    # 1. GitHub (always available if gh is authenticated)
    print --stderr "[1/3] GitHub..."
    try {
        if $refresh {
            stars sync github --refresh --verbose=$verbose
        } else {
            stars sync github --verbose=$verbose
        }
    } catch {|e|
        print --stderr $"  Warning: GitHub sync failed: ($e.msg)"
    }
    print --stderr ""

    # 2. Firefox (if places.sqlite exists)
    print --stderr "[2/3] Firefox..."
    let places = get-firefox-places-path
    if $places != null {
        try {
            stars sync firefox --file $places --verbose=$verbose
        } catch {|e|
            print --stderr $"  Warning: Firefox sync failed: ($e.msg)"
        }
    } else {
        print --stderr "  Skipped: Firefox places.sqlite not found"
    }
    print --stderr ""

    # 3. Chrome (if Bookmarks exists)
    print --stderr "[3/3] Chrome..."
    let bookmarks = get-chrome-bookmarks-path
    if $bookmarks != null {
        try {
            stars sync chrome --file $bookmarks --verbose=$verbose
        } catch {|e|
            print --stderr $"  Warning: Chrome sync failed: ($e.msg)"
        }
    } else {
        print --stderr "  Skipped: Chrome Bookmarks not found"
    }
    print --stderr ""

    # Report final stats
    let stats = storage get-stats
    print --stderr $"Sync complete. Total stars: ($stats.total_stars)"
}

# Show sync status for all sources
#
# Displays the current sync status including last sync time,
# entry counts by source, and available sources.
#
# Example:
#   stars sync status
export def "stars sync status" []: nothing -> table {
    let paths = storage get-paths
    let stats = storage get-stats

    if not $stats.exists {
        print --stderr "No database found. Run 'stars sync' to create one."
        return []
    }

    # Get counts by source
    let source_counts = try {
        open $paths.db_path | query db "
            SELECT
                source,
                COUNT(*) as count,
                MAX(synced_at) as last_synced
            FROM stars
            GROUP BY source
            ORDER BY count DESC
        "
    } catch {
        []
    }

    # Check available sources
    let gh_available = (do { gh auth status } | complete).exit_code == 0
    let firefox_path = get-firefox-places-path
    let firefox_available = $firefox_path != null and ($firefox_path | path exists)
    let chrome_path = get-chrome-bookmarks-path
    let chrome_available = $chrome_path != null and ($chrome_path | path exists)

    print --stderr $"Database: ($paths.db_path)"
    print --stderr $"Total stars: ($stats.total_stars)"
    print --stderr $"Last modified: ($stats.last_modified)"
    print --stderr ""
    print --stderr "Available sources:"
    print --stderr $"  GitHub:  (if $gh_available { 'ready' } else { 'not authenticated' })"
    print --stderr $"  Firefox: (if $firefox_available { 'ready' } else { 'not found' })"
    print --stderr $"  Chrome:  (if $chrome_available { 'ready' } else { 'not found' })"
    print --stderr ""

    $source_counts
}
