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

# ============================================================================
# Public API
# ============================================================================

# Check if Firefox bookmarks (places.sqlite) are available
#
# Returns status information about Firefox bookmarks availability.
#
# Example:
#   let status = check-available
#   if $status.available {
#       print $"Found ($status.bookmark_count) bookmarks"
#   }
export def check-available []: nothing -> record {
    let home = $nu.home-dir
    let mozilla_path = $home | path join .mozilla firefox

    let places_db = if ($mozilla_path | path exists) {
        let profiles = try {
            ls ($mozilla_path | path join "*.default*") | get name | first
        } catch { null }
        if ($profiles != null) {
            $profiles | path join places.sqlite
        } else {
            null
        }
    } else {
        null
    }

    if ($places_db == null) or not ($places_db | path exists) {
        return {
            available: false
            places_db: ""
            bookmark_count: 0
            folder_count: 0
            message: "Firefox places.sqlite not found in standard locations"
        }
    }

    let raw_bookmarks = try {
        open $places_db | query db "SELECT url, title FROM moz_bookmarks JOIN moz_places ON moz_bookmarks.fk = moz_places.id WHERE url LIKE '%github.com%'"
    } catch {
        []
    }

    let github_repos = $raw_bookmarks | extract-github-repos
    let folder_count = $github_repos | get folder | uniq | length

    {
        available: true
        places_db: ($places_db | into string)
        bookmark_count: ($github_repos | length)
        folder_count: $folder_count
        message: $"Found ($github_repos | length) GitHub bookmarks in ($folder_count) folders"
    }
}

# Extract GitHub repository URLs from a list of bookmark records
#
# Filters bookmarks to only those pointing to GitHub repositories.
#
# Example:
#   $bookmarks | extract-github-repos
export def extract-github-repos []: table -> table {
    each {|bookmark|
        let url = $bookmark.url? | default ""
        if not ($url =~ 'github\.com/[^/]+/[^/]+') {
            null
        } else {
            let match = $url | parse --regex 'github\.com/([^/]+)/([^/?#\s]+)'
            if ($match | is-empty) {
                null
            } else {
                let owner = $match | first | get capture0
                let name = $match | first | get capture1 | str replace --regex '\.git$' ''
                {
                    url: $url
                    name: ($bookmark.title? | default $name)
                    owner: $owner
                    repo: $name
                    full_name: $"($owner)/($name)"
                    folder: ($bookmark.folder? | default "")
                }
            }
        }
    } | compact | uniq-by full_name
}
