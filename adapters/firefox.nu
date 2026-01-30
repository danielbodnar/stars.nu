#!/usr/bin/env nu

# ============================================================================
# Firefox Bookmarks Adapter
# ============================================================================
#
# Imports GitHub repository bookmarks from Firefox's places.sqlite database
# or exported JSON bookmark files. Normalizes to the standard star schema.
#
# Supported formats:
# - places.sqlite (Firefox profile database)
# - JSON export (Firefox bookmark manager export)
#
# Requirements:
# - Firefox profile with bookmarks (for places.sqlite)
# - Or exported JSON bookmark file
#
# Author: Daniel Bodnar
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Ensure a directory exists, creating it if necessary
def ensure-directory [dir: path]: nothing -> nothing {
    if not ($dir | path exists) {
        try {
            mkdir $dir
        } catch {|e|
            error make {
                msg: $"Failed to create directory: ($e.msg)"
                label: {text: "directory creation failed", span: (metadata $dir).span}
            }
        }
    }
}

# Generate a unique ID from URL hash
def generate-id [url: string]: nothing -> int {
    # Simple hash: sum of char codes modulo max int
    $url | split chars | each {|c| $c | into binary | first } | math sum
}

# ============================================================================
# Profile Detection
# ============================================================================

# Auto-detect Firefox profile and places.sqlite location
#
# Searches for Firefox profile directories on Linux and macOS.
# Returns the path to places.sqlite in the default profile.
#
# Returns: path - Path to places.sqlite
#
# Example:
#   let db = find-places-db
#   print $"Found Firefox database at ($db)"
export def find-places-db []: nothing -> path {
    # Determine Firefox profile directory based on OS
    let firefox_dirs = [
        # Linux
        ($nu.home-dir | path join .mozilla firefox)
        # macOS
        ($nu.home-dir | path join Library "Application Support" Firefox Profiles)
        # Flatpak Firefox on Linux
        ($nu.home-dir | path join .var app org.mozilla.firefox .mozilla firefox)
        # Snap Firefox on Linux
        ($nu.home-dir | path join snap firefox common .mozilla firefox)
    ]

    # Find the first existing Firefox directory
    let firefox_dir = $firefox_dirs | where {|d| $d | path exists } | first

    if ($firefox_dir == null) or ($firefox_dir | is-empty) {
        error make {
            msg: "Firefox profile directory not found"
            help: "Searched locations: ~/.mozilla/firefox, ~/Library/Application Support/Firefox/Profiles, ~/.var/app/org.mozilla.firefox/.mozilla/firefox, ~/snap/firefox/common/.mozilla/firefox"
        }
    }

    # Find profiles.ini or default profile directory
    let profiles_ini = $firefox_dir | path join profiles.ini

    # Look for default profile (*.default* pattern)
    let profile_dirs = try {
        ls $firefox_dir
        | where type == "dir"
        | where name =~ '\.default'
        | get name
    } catch { [] }

    if ($profile_dirs | is-empty) {
        error make {
            msg: "No Firefox default profile found"
            label: {text: "profile directory not found", span: (metadata $firefox_dir).span}
            help: $"Searched in ($firefox_dir) for directories matching *.default*"
        }
    }

    # Use the first default profile found
    let profile_dir = $profile_dirs | first
    let places_db = $profile_dir | path join places.sqlite

    if not ($places_db | path exists) {
        error make {
            msg: "places.sqlite not found in Firefox profile"
            label: {text: "database not found", span: (metadata $profile_dir).span}
            help: $"Expected at: ($places_db)"
        }
    }

    $places_db
}

# ============================================================================
# SQLite Parsing
# ============================================================================

# Parse places.sqlite database for GitHub bookmarks
#
# Queries the Firefox places.sqlite database for bookmarks containing
# github.com URLs. Optionally filters by bookmark folder.
#
# Parameters:
#   db_path: path - Path to places.sqlite file
#   folder?: string - Optional folder name to filter by
#
# Returns: table - Raw bookmark records
def parse-places-db [
    db_path: path
    folder: string = ""
]: nothing -> table {
    # Verify the file exists and is readable
    if not ($db_path | path exists) {
        error make {
            msg: $"Database file not found: ($db_path)"
            label: {text: "file not found", span: (metadata $db_path).span}
        }
    }

    # Firefox keeps places.sqlite locked while running
    # We need to copy it to a temporary location to read it
    let temp_dir = $env.XDG_RUNTIME_DIR? | default "/tmp"
    let temp_db = $temp_dir | path join $"firefox_places_(date now | format date %Y%m%d%H%M%S).sqlite"

    try {
        cp $db_path $temp_db
    } catch {|e|
        error make {
            msg: $"Failed to copy database (Firefox may be running): ($e.msg)"
            label: {text: "copy failed", span: (metadata $db_path).span}
            help: "Try closing Firefox or using a JSON export instead"
        }
    }

    # Build the SQL query
    let folder_filter = if not ($folder | is-empty) {
        $" AND f.title = '($folder)'"
    } else {
        ""
    }

    let sql = $"
        SELECT
            b.title as title,
            p.url as url,
            p.description as description,
            b.dateAdded as date_added,
            f.title as folder
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        LEFT JOIN moz_bookmarks f ON b.parent = f.id
        WHERE p.url LIKE '%github.com/%'
        ($folder_filter)
        ORDER BY b.dateAdded DESC
    "

    let bookmarks = try {
        open $temp_db | query db $sql
    } catch {|e|
        # Clean up temp file before error
        try { rm $temp_db } catch { null }
        error make {
            msg: $"Failed to query database: ($e.msg)"
            label: {text: "query failed", span: (metadata $temp_db).span}
            help: "The database may be corrupted or in an incompatible format"
        }
    }

    # Clean up temp file
    try { rm $temp_db } catch { null }

    $bookmarks
}

# ============================================================================
# JSON Parsing
# ============================================================================

# Recursively extract bookmarks from Firefox JSON export tree
#
# Firefox JSON exports have a nested structure with children arrays.
# This function flattens the tree into a list of bookmark records.
#
# Parameters:
#   node: record - Current node in the bookmark tree
#   current_folder: string - Name of the current folder (for path tracking)
def extract-bookmarks-recursive [
    node: record
    current_folder: string = ""
]: nothing -> list {
    mut bookmarks = []

    # Get the folder name for this level
    let folder_name = if ($current_folder | is-empty) {
        $node.title? | default ""
    } else if ($node.title? | default "" | is-empty) {
        $current_folder
    } else {
        $"($current_folder)/($node.title)"
    }

    # Check if this node is a bookmark (has uri field)
    if ("uri" in ($node | columns)) and ($node.uri? | default "" | str contains "github.com") {
        let bookmark = {
            title: ($node.title? | default "")
            url: ($node.uri? | default "")
            description: ($node.tags? | default [] | str join ", ")
            date_added: ($node.dateAdded? | default 0)
            folder: $folder_name
        }
        $bookmarks = ($bookmarks | append $bookmark)
    }

    # Recursively process children
    if ("children" in ($node | columns)) and ($node.children? | default [] | length) > 0 {
        for child in $node.children {
            let child_bookmarks = extract-bookmarks-recursive $child $folder_name
            $bookmarks = ($bookmarks | append $child_bookmarks)
        }
    }

    $bookmarks
}

# Parse Firefox JSON bookmark export
#
# Parses a JSON file exported from Firefox's bookmark manager.
# Recursively traverses the bookmark tree to find GitHub URLs.
#
# Parameters:
#   json_path: path - Path to exported JSON file
#   folder?: string - Optional folder name to filter by
#
# Returns: table - Raw bookmark records
def parse-bookmark-json [
    json_path: path
    folder: string = ""
]: nothing -> table {
    if not ($json_path | path exists) {
        error make {
            msg: $"JSON file not found: ($json_path)"
            label: {text: "file not found", span: (metadata $json_path).span}
        }
    }

    let json_content = try {
        open $json_path
    } catch {|e|
        error make {
            msg: $"Failed to parse JSON file: ($e.msg)"
            label: {text: "JSON parse error", span: (metadata $json_path).span}
            help: "Ensure the file is a valid Firefox bookmark export"
        }
    }

    # Extract all bookmarks recursively
    let all_bookmarks = extract-bookmarks-recursive $json_content ""

    # Filter by folder if specified
    if not ($folder | is-empty) {
        $all_bookmarks | where {|b| $b.folder =~ $folder }
    } else {
        $all_bookmarks
    }
}

# ============================================================================
# GitHub URL Processing
# ============================================================================

# Extract owner and repo from GitHub URL
#
# Parses various GitHub URL formats to extract the owner and repository name.
# Handles URLs with and without trailing paths.
#
# Parameters:
#   url: string - GitHub URL to parse
#
# Returns: record - {owner: string, repo: string} or null if invalid
def parse-github-url [url: string]: nothing -> record {
    # Match github.com URLs
    let url_clean = $url
        | str replace --regex '^https?://(www\.)?' ''
        | str replace --regex '\?.*$' ''
        | str replace --regex '#.*$' ''
        | str trim --right --char '/'

    # Extract path after github.com
    let path = if ($url_clean | str starts-with "github.com/") {
        $url_clean | str replace "github.com/" ""
    } else {
        return null
    }

    # Split path and extract owner/repo
    let parts = $path | split row '/'

    if ($parts | length) < 2 {
        return null
    }

    let owner = $parts | first
    let repo = $parts | get 1

    # Skip special GitHub paths
    let special_paths = [
        "orgs" "users" "settings" "notifications" "issues" "pulls"
        "marketplace" "explore" "trending" "collections" "events"
        "sponsors" "login" "join" "pricing" "features" "enterprise"
        "search" "topics" "codespaces" "copilot"
    ]

    if $owner in $special_paths {
        return null
    }

    # Skip if repo looks like a path segment (contains special chars for non-repo paths)
    if ($repo | str contains ".") and not ($repo | str ends-with ".git") {
        return null
    }

    {
        owner: $owner
        repo: ($repo | str replace ".git" "")
    }
}

# Filter and normalize URLs to GitHub repos
#
# Takes a table of bookmarks and extracts valid GitHub repository URLs.
# Filters out non-repository URLs (user profiles, org pages, etc.).
#
# Parameters:
#   bookmarks: table - Raw bookmark records with url field
#
# Returns: table - Filtered bookmarks with owner/repo extracted
#
# Example:
#   $raw_bookmarks | extract-github-repos
export def extract-github-repos [
    bookmarks: table
]: nothing -> table {
    $bookmarks
    | each {|bookmark|
        let parsed = parse-github-url $bookmark.url

        if $parsed == null {
            null
        } else {
            $bookmark | merge $parsed
        }
    }
    | where {|b| $b != null }
}

# ============================================================================
# Normalization
# ============================================================================

# Normalize a bookmark to our star schema
#
# Transforms a raw Firefox bookmark into the standard star schema format.
# Sets default values for fields not available in bookmarks.
#
# Parameters:
#   bookmark: record - Raw bookmark with owner/repo extracted
#
# Returns: record - Normalized star record
def normalize-bookmark [
    bookmark: record
]: nothing -> record {
    let synced_at = date now | format date "%Y-%m-%dT%H:%M:%SZ"
    let full_name = $"($bookmark.owner)/($bookmark.repo)"

    # Convert Firefox date_added (microseconds since epoch) to datetime string
    let created_at = try {
        if ($bookmark.date_added? | default 0) > 0 {
            # Firefox stores dates as microseconds since epoch
            let seconds = ($bookmark.date_added / 1000000) | into int
            $seconds | into datetime | format date "%Y-%m-%dT%H:%M:%SZ"
        } else {
            null
        }
    } catch { null }

    {
        id: (generate-id $bookmark.url)
        node_id: ""
        name: $bookmark.repo
        full_name: $full_name
        owner: $bookmark.owner
        private: false
        html_url: $bookmark.url
        description: ($bookmark.title? | default $bookmark.description? | default null)
        fork: false
        url: $bookmark.url
        created_at: $created_at
        updated_at: null
        pushed_at: null
        homepage: null
        size: 0
        stargazers_count: 0
        watchers_count: 0
        language: null
        forks_count: 0
        archived: false
        disabled: false
        open_issues_count: 0
        license: null
        topics: "[]"
        visibility: "public"
        default_branch: "main"
        source: "firefox"
        synced_at: $synced_at
        # Additional metadata from bookmark
        bookmark_folder: ($bookmark.folder? | default "")
    }
}

# ============================================================================
# Public API
# ============================================================================

# Import GitHub bookmarks from Firefox
#
# Fetches GitHub repository bookmarks from Firefox's places.sqlite database
# or from an exported JSON file. Normalizes to the standard star schema.
#
# Parameters:
#   --file (-f): path - Path to places.sqlite or bookmarks JSON export
#   --folder: string - Specific folder to import from
#
# Returns: table - Normalized star records
#
# Example:
#   # Auto-detect Firefox profile
#   fetch
#
#   # Use specific database file
#   fetch --file ~/backup/places.sqlite
#
#   # Import from JSON export
#   fetch --file ~/bookmarks.json
#
#   # Import from specific folder
#   fetch --folder "GitHub/Libraries"
export def fetch [
    --file (-f): path           # Path to places.sqlite or bookmarks JSON export
    --folder: string            # Specific folder to import from
]: nothing -> table {
    # Determine the file to use
    let source_file = if ($file == null) or ($file | is-empty) {
        try {
            find-places-db
        } catch {|e|
            error make {
                msg: $"Could not auto-detect Firefox database: ($e.msg)"
                label: {text: "auto-detection failed", span: (metadata $file).span}
                help: "Specify the file path explicitly with --file"
            }
        }
    } else {
        if not ($file | path exists) {
            error make {
                msg: $"File not found: ($file)"
                label: {text: "file not found", span: (metadata $file).span}
            }
        }
        $file
    }

    # Determine file type and parse accordingly
    let file_ext = $source_file | path parse | get extension | str downcase
    let folder_filter = $folder | default ""

    let raw_bookmarks = match $file_ext {
        "sqlite" | "db" => {
            parse-places-db $source_file $folder_filter
        }
        "json" => {
            parse-bookmark-json $source_file $folder_filter
        }
        _ => {
            # Try to detect by content
            let first_bytes = try {
                open $source_file --raw | first 20 | into string
            } catch { "" }

            if ($first_bytes | str starts-with "SQLite") or ($first_bytes | str contains (char null_byte)) {
                parse-places-db $source_file $folder_filter
            } else if ($first_bytes | str trim | str starts-with "{") {
                parse-bookmark-json $source_file $folder_filter
            } else {
                error make {
                    msg: $"Unknown file format: ($source_file)"
                    label: {text: "unrecognized format", span: (metadata $source_file).span}
                    help: "Supported formats: SQLite (.sqlite, .db) or JSON (.json)"
                }
            }
        }
    }

    # Check if any bookmarks were found
    if ($raw_bookmarks | is-empty) {
        print --stderr "No GitHub bookmarks found"
        return []
    }

    # Extract valid GitHub repos and normalize
    let github_repos = extract-github-repos $raw_bookmarks

    if ($github_repos | is-empty) {
        print --stderr "No valid GitHub repository URLs found in bookmarks"
        return []
    }

    # Normalize to star schema
    let normalized = $github_repos | each {|bookmark| normalize-bookmark $bookmark }

    let count = $normalized | length
    print --stderr $"Imported ($count) GitHub repositories from Firefox bookmarks"

    $normalized
}

# Get list of bookmark folders containing GitHub URLs
#
# Scans Firefox bookmarks and returns a list of folders that contain
# GitHub repository URLs, along with counts.
#
# Parameters:
#   --file (-f): path - Path to places.sqlite or bookmarks JSON export
#
# Returns: table - Folder names with bookmark counts
#
# Example:
#   list-folders | where count > 5
export def list-folders [
    --file (-f): path           # Path to places.sqlite or bookmarks JSON export
]: nothing -> table {
    let source_file = if ($file == null) or ($file | is-empty) {
        find-places-db
    } else {
        $file
    }

    let file_ext = $source_file | path parse | get extension | str downcase

    let raw_bookmarks = match $file_ext {
        "sqlite" | "db" => { parse-places-db $source_file "" }
        "json" => { parse-bookmark-json $source_file "" }
        _ => { parse-places-db $source_file "" }
    }

    let github_repos = extract-github-repos $raw_bookmarks

    $github_repos
    | group-by {|b| $b.folder? | default "(root)" }
    | items {|folder, bookmarks| {folder: $folder, count: ($bookmarks | length)} }
    | sort-by count --reverse
}

# Check Firefox integration status
#
# Verifies that Firefox bookmarks can be accessed and provides
# status information.
#
# Returns: record - Status information
#
# Example:
#   let status = check-status
#   if $status.available {
#       print $"Found ($status.bookmark_count) GitHub bookmarks"
#   }
export def check-status []: nothing -> record<available: bool, places_db: string, bookmark_count: int, folder_count: int, message: string> {
    # Try to find Firefox database
    let places_db = try {
        find-places-db
    } catch {
        return {
            available: false
            places_db: ""
            bookmark_count: 0
            folder_count: 0
            message: "Firefox profile not found"
        }
    }

    # Try to read bookmarks
    let raw_bookmarks = try {
        parse-places-db $places_db ""
    } catch {|e|
        return {
            available: false
            places_db: ($places_db | into string)
            bookmark_count: 0
            folder_count: 0
            message: $"Cannot read database: ($e.msg)"
        }
    }

    let github_repos = extract-github-repos $raw_bookmarks
    let folder_count = $github_repos | get folder | uniq | length

    {
        available: true
        places_db: ($places_db | into string)
        bookmark_count: ($github_repos | length)
        folder_count: $folder_count
        message: $"Found ($github_repos | length) GitHub bookmarks in ($folder_count) folders"
    }
}
