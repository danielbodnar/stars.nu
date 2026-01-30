#!/usr/bin/env nu

# ============================================================================
# Chrome/Chromium Bookmarks Adapter
# ============================================================================
#
# Imports GitHub repository URLs from Chrome or Chromium browser bookmarks.
# Parses the Bookmarks JSON file and extracts GitHub repo URLs, normalizing
# them to the standard star schema.
#
# Supported browsers:
# - Google Chrome
# - Chromium
#
# Bookmarks file locations:
# - Linux: ~/.config/google-chrome/Default/Bookmarks
#          ~/.config/chromium/Default/Bookmarks
# - macOS: ~/Library/Application Support/Google/Chrome/Default/Bookmarks
#          ~/Library/Application Support/Chromium/Default/Bookmarks
#
# Author: Daniel Bodnar
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Extract owner and repo name from a GitHub URL
#
# Parses various GitHub URL formats and extracts the owner/repo pair.
# Handles URLs with trailing paths, query params, and fragments.
#
# Parameters:
#   url: string - GitHub URL to parse
#
# Returns: record with owner and name, or null if not a valid repo URL
def parse-github-url [
    url: string
]: nothing -> record {
    # Skip non-GitHub URLs
    if not ($url =~ "github\\.com") {
        return null
    }

    # Match GitHub repo URLs: https://github.com/{owner}/{repo}[/...]
    # Captures owner and repo, ignoring any trailing path segments
    let pattern = "(?:https?://)?(?:www\\.)?github\\.com/([^/]+)/([^/?#]+)"

    let captures = try {
        $url | parse --regex $pattern | first
    } catch {
        null
    }

    if ($captures == null) or ($captures | is-empty) {
        return null
    }

    let owner = $captures | get capture0
    let name = $captures | get capture1 | str replace --regex '\\.git$' ''

    # Skip special GitHub pages that aren't repos
    let excluded_owners = [
        "settings" "notifications" "pulls" "issues" "explore"
        "trending" "collections" "sponsors" "login" "signup"
        "marketplace" "features" "pricing" "enterprise" "team"
        "security" "customer-stories" "readme" "topics" "search"
    ]

    if $owner in $excluded_owners {
        return null
    }

    # Skip special paths that look like repos but aren't
    let excluded_names = [
        "stars" "followers" "following" "repositories" "projects"
        "packages" "sponsoring" "achievements" "settings"
    ]

    if $name in $excluded_names {
        return null
    }

    {
        owner: $owner
        name: $name
        full_name: $"($owner)/($name)"
    }
}

# Recursively extract bookmarks from Chrome JSON structure
#
# Traverses the bookmark tree structure, extracting URL bookmarks
# and optionally filtering by folder name.
#
# Parameters:
#   node: record - Chrome bookmark node (folder or url)
#   folder_filter: string - Optional folder name to filter by
#   current_path: list<string> - Current folder path (for tracking)
def extract-from-node [
    node: record
    folder_filter?: string
    current_path: list<string> = []
]: nothing -> list {
    let node_type = $node.type? | default ""

    match $node_type {
        "url" => {
            # Check if we're in the right folder (if filter specified)
            let in_folder = if ($folder_filter | is-empty) or ($folder_filter == null) {
                true
            } else {
                $folder_filter in $current_path
            }

            if $in_folder {
                [{
                    name: ($node.name? | default "")
                    url: ($node.url? | default "")
                    date_added: ($node.date_added? | default null)
                    folder_path: ($current_path | str join "/")
                }]
            } else {
                []
            }
        }
        "folder" => {
            let folder_name = $node.name? | default ""
            let new_path = $current_path | append $folder_name
            let children = $node.children? | default []

            $children | each {|child|
                extract-from-node $child $folder_filter $new_path
            } | flatten
        }
        _ => { [] }
    }
}

# Parse Chrome Bookmarks JSON file
#
# Reads and parses the Chrome Bookmarks JSON file, extracting all bookmarks
# from the standard roots (bookmark_bar, other, synced).
#
# Parameters:
#   json_path: path - Path to the Bookmarks JSON file
#   folder: string - Optional folder name to filter by
def parse-bookmarks [
    json_path: path
    folder?: string
]: nothing -> table {
    if not ($json_path | path exists) {
        error make {
            msg: $"Bookmarks file not found: ($json_path)"
            label: {text: "file does not exist", span: (metadata $json_path).span}
            help: "Check the file path or use 'find-bookmarks-file' to locate it"
        }
    }

    let bookmarks_data = try {
        open $json_path
    } catch {|e|
        error make {
            msg: $"Failed to parse Bookmarks JSON: ($e.msg)"
            label: {text: "JSON parse error", span: (metadata $json_path).span}
            help: "The file may be corrupted or not a valid Chrome Bookmarks file"
        }
    }

    # Chrome Bookmarks has a "roots" object with bookmark_bar, other, and synced
    let roots = $bookmarks_data.roots? | default {}

    # Extract from all root folders
    let all_bookmarks = [
        ($roots.bookmark_bar? | default {})
        ($roots.other? | default {})
        ($roots.synced? | default {})
    ] | each {|root|
        if ($root | is-empty) {
            []
        } else {
            extract-from-node $root $folder []
        }
    } | flatten

    $all_bookmarks
}

# Normalize a Chrome bookmark to our star schema
#
# Transforms a Chrome bookmark into the standard star record format.
# Only URL and basic metadata are available from bookmarks.
#
# Parameters:
#   bookmark: record - Chrome bookmark with parsed GitHub info
def normalize-bookmark [
    bookmark: record
]: nothing -> record {
    let synced_at = date now | format date "%Y-%m-%dT%H:%M:%SZ"

    # Parse date_added from Chrome's microseconds-since-epoch format
    # Chrome uses microseconds since Jan 1, 1601 (Windows FILETIME)
    let created = try {
        if ($bookmark.date_added? | is-empty) or ($bookmark.date_added == null) {
            null
        } else {
            # Chrome stores as microseconds since 1601-01-01
            # Convert to Unix epoch by subtracting the difference
            let chrome_epoch_offset = 11644473600000000  # microseconds between 1601 and 1970
            let unix_micros = ($bookmark.date_added | into int) - $chrome_epoch_offset
            let unix_secs = $unix_micros // 1000000

            # Only convert if positive (valid date after 1970)
            if $unix_secs > 0 {
                $unix_secs * 1sec | into datetime | format date "%Y-%m-%dT%H:%M:%SZ"
            } else {
                null
            }
        }
    } catch { null }

    {
        id: 0  # Will be assigned by storage layer
        node_id: ""
        name: ($bookmark.name? | default "")
        full_name: ($bookmark.full_name? | default "")
        owner: ($bookmark.owner? | default "unknown")
        private: false
        html_url: ($bookmark.url? | default "")
        description: null
        fork: false
        url: ($bookmark.url? | default "")
        created_at: $created
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
        source: "chrome"
        synced_at: $synced_at
        folder_path: ($bookmark.folder_path? | default "")
    }
}

# ============================================================================
# Public API
# ============================================================================

# Auto-detect Chrome/Chromium Bookmarks file location
#
# Searches for the Bookmarks file in standard locations for Chrome and
# Chromium on Linux and macOS. Returns the first existing file found.
#
# Example:
#   let bookmarks_path = find-bookmarks-file
#   print $"Found bookmarks at: ($bookmarks_path)"
export def find-bookmarks-file []: nothing -> path {
    let home = $nu.home-dir

    # Define search paths in order of preference
    let search_paths = [
        # Linux - Chrome
        ($home | path join .config google-chrome Default Bookmarks)
        # Linux - Chromium
        ($home | path join .config chromium Default Bookmarks)
        # Linux - Chrome Beta/Dev/Canary
        ($home | path join .config google-chrome-beta Default Bookmarks)
        ($home | path join .config google-chrome-unstable Default Bookmarks)
        # macOS - Chrome
        ($home | path join "Library" "Application Support" "Google" "Chrome" "Default" "Bookmarks")
        # macOS - Chromium
        ($home | path join "Library" "Application Support" "Chromium" "Default" "Bookmarks")
        # macOS - Chrome Beta/Dev/Canary
        ($home | path join "Library" "Application Support" "Google" "Chrome Beta" "Default" "Bookmarks")
        ($home | path join "Library" "Application Support" "Google" "Chrome Canary" "Default" "Bookmarks")
        # Snap Chrome (Linux)
        ($home | path join snap chromium common chromium Default Bookmarks)
        # Flatpak Chrome (Linux)
        ($home | path join .var app com.google.Chrome config google-chrome Default Bookmarks)
    ]

    # Find the first existing file
    let found = $search_paths | where {|p| $p | path exists } | first

    if ($found | is-empty) or ($found == null) {
        error make {
            msg: "Chrome/Chromium Bookmarks file not found"
            label: {text: "no bookmarks file in standard locations", span: (metadata $search_paths).span}
            help: "Use --file to specify the Bookmarks file path manually"
        }
    }

    $found
}

# Extract GitHub repository URLs from bookmarks
#
# Filters a table of bookmarks to only those pointing to GitHub repositories,
# parsing and extracting owner/repo information from each URL.
#
# Parameters:
#   bookmarks: table - Table of bookmark records with url field
#
# Example:
#   $bookmarks | extract-github-repos
export def extract-github-repos [
    bookmarks: table
]: nothing -> table {
    $bookmarks
    | each {|bookmark|
        let parsed = parse-github-url ($bookmark.url? | default "")

        if ($parsed == null) {
            null
        } else {
            $bookmark | merge $parsed
        }
    }
    | where {|b| $b != null }
    | uniq-by full_name
}

# Import GitHub bookmarks from Chrome/Chromium
#
# Reads the Chrome Bookmarks file and extracts all GitHub repository URLs,
# normalizing them to the standard star schema.
#
# Parameters:
#   --file (-f): path - Path to Bookmarks JSON file (auto-detected if not specified)
#   --folder: string - Specific folder to import from (imports all if not specified)
#
# Example:
#   # Auto-detect bookmarks file and import all GitHub repos
#   fetch
#
#   # Import from specific file
#   fetch --file ~/.config/google-chrome/Default/Bookmarks
#
#   # Import only from a specific folder
#   fetch --folder "GitHub"
export def fetch [
    --file (-f): path      # Path to Bookmarks JSON file
    --folder: string       # Specific folder to import from
]: nothing -> table {
    # Find or use provided bookmarks file
    let bookmarks_path = if ($file | is-empty) or ($file == null) {
        find-bookmarks-file
    } else {
        if not ($file | path exists) {
            error make {
                msg: $"Bookmarks file not found: ($file)"
                label: {text: "file does not exist", span: (metadata $file).span}
            }
        }
        $file
    }

    # Parse bookmarks
    let all_bookmarks = parse-bookmarks $bookmarks_path $folder

    if ($all_bookmarks | is-empty) {
        print --stderr "No bookmarks found"
        return []
    }

    # Extract GitHub repos
    let github_bookmarks = extract-github-repos $all_bookmarks

    if ($github_bookmarks | is-empty) {
        print --stderr "No GitHub repository bookmarks found"
        return []
    }

    # Normalize to star schema
    $github_bookmarks | each {|bookmark| normalize-bookmark $bookmark }
}

# Check if Chrome/Chromium bookmarks are available
#
# Returns status information about Chrome bookmarks availability.
#
# Example:
#   let status = check-available
#   if $status.available {
#       print $"Found ($status.bookmark_count) bookmarks"
#   }
export def check-available []: nothing -> record<available: bool, file_path: path, bookmark_count: int, github_count: int, message: string> {
    let file_path = try {
        find-bookmarks-file
    } catch {
        ""
    }

    if ($file_path | is-empty) {
        return {
            available: false
            file_path: ""
            bookmark_count: 0
            github_count: 0
            message: "Chrome/Chromium Bookmarks file not found in standard locations"
        }
    }

    # Try to parse and count bookmarks
    let bookmarks = try {
        parse-bookmarks $file_path
    } catch {|e|
        return {
            available: false
            file_path: $file_path
            bookmark_count: 0
            github_count: 0
            message: $"Failed to parse bookmarks: ($e.msg)"
        }
    }

    let github_bookmarks = try {
        extract-github-repos $bookmarks
    } catch {
        []
    }

    {
        available: true
        file_path: $file_path
        bookmark_count: ($bookmarks | length)
        github_count: ($github_bookmarks | length)
        message: $"Found ($bookmarks | length) bookmarks, ($github_bookmarks | length) GitHub repos"
    }
}

# List all folders in the Chrome bookmarks
#
# Returns a list of all folder names in the bookmarks file, useful for
# determining which folder to filter with --folder.
#
# Parameters:
#   --file (-f): path - Path to Bookmarks JSON file (auto-detected if not specified)
#
# Example:
#   list-folders | where depth == 1
export def list-folders [
    --file (-f): path      # Path to Bookmarks JSON file
]: nothing -> table {
    let bookmarks_path = if ($file | is-empty) or ($file == null) {
        find-bookmarks-file
    } else {
        $file
    }

    let bookmarks_data = try {
        open $bookmarks_path
    } catch {|e|
        error make {
            msg: $"Failed to parse Bookmarks JSON: ($e.msg)"
            label: {text: "JSON parse error", span: (metadata $bookmarks_path).span}
        }
    }

    # Recursive folder extraction
    def extract-folders [node: record, path: list<string> = [], depth: int = 0]: nothing -> list {
        let node_type = $node.type? | default ""

        if $node_type == "folder" {
            let folder_name = $node.name? | default ""
            let full_path = $path | append $folder_name | str join "/"
            let children = $node.children? | default []

            let this_folder = if ($folder_name | is-empty) {
                []
            } else {
                [{
                    name: $folder_name
                    path: $full_path
                    depth: $depth
                    bookmark_count: ($children | where type == "url" | length)
                    subfolder_count: ($children | where type == "folder" | length)
                }]
            }

            let child_folders = $children | each {|child|
                extract-folders $child ($path | append $folder_name) ($depth + 1)
            } | flatten

            $this_folder | append $child_folders
        } else {
            []
        }
    }

    let roots = $bookmarks_data.roots? | default {}

    [
        ($roots.bookmark_bar? | default {})
        ($roots.other? | default {})
        ($roots.synced? | default {})
    ] | each {|root|
        if ($root | is-empty) {
            []
        } else {
            extract-folders $root [] 0
        }
    } | flatten
}
