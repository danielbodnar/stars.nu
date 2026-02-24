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
def generate-id []: nothing -> int {
    # Simple hash: sum of char codes modulo max int
    split chars | each {|c| $c | into binary | first } | math sum
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
