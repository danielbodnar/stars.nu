#!/usr/bin/env nu

# ============================================================================
# Stars Export Commands
# ============================================================================
#
# Export functionality for various output formats including CSV, JSON, NUON,
# Markdown, and browser bookmark formats (Firefox, Chrome).
#
# All exports use XDG-compliant paths and support custom output locations.
#
# Author: Daniel Bodnar
# ============================================================================

use ../core/storage.nu [get-paths, load, ensure-storage]

# ============================================================================
# Internal Helpers
# ============================================================================

# Generate output path with timestamp
def generate-output-path [prefix: string, extension: string]: nothing -> path {
    let paths = get-paths
    ensure-storage
    let timestamp = date now | format date %Y%m%d_%H%M%S
    $paths.export_dir | path join $"($prefix)_($timestamp).($extension)"
}

# Parse topics from JSON string or list
def parse-topics [topics: any]: nothing -> list {
    try {
        let type = $topics | describe | str replace --regex '<.*' ''
        match $type {
            "string" => { $topics | default "[]" | from json }
            "list" => { $topics | default [] }
            _ => { [] }
        }
    } catch { [] }
}

# Get owner login from JSON string or record
def get-owner-login [owner: any]: nothing -> string {
    try {
        let type = $owner | describe | str replace --regex '<.*' ''
        match $type {
            "string" => { $owner | from json | get login? | default "unknown" }
            "record" => { $owner | get login? | default "unknown" }
            _ => { "unknown" }
        }
    } catch { "unknown" }
}

# Transform repository for CSV/tabular export
def transform-repo-for-export [repo: record]: nothing -> record {
    let owner = get-owner-login $repo.owner
    let topics = try { $repo.topics? | default "[]" | from json | str join ";" } catch { "" }
    let license_data = $repo.license? | default ""
    let license = if ($license_data | is-empty) { "" } else {
        try { $license_data | from json | get name? | default "" } catch { "" }
    }

    {
        name: $repo.name
        full_name: $repo.full_name
        url: $repo.html_url
        description: ($repo.description? | default "")
        language: ($repo.language? | default "")
        stars: $repo.stargazers_count
        forks: $repo.forks_count
        created_at: $repo.created_at
        updated_at: $repo.updated_at
        owner: $owner
        topics: $topics
        license: $license
        archived: ($repo.archived? | default false)
        is_fork: ($repo.fork? | default false)
    }
}

# Filter stars based on archive and fork options
def filter-stars [stars: table, include_archived: bool, include_forks: bool]: nothing -> table {
    $stars | where {|repo|
        let is_archived = ($repo.archived? | default 0) == 1
        let is_fork = ($repo.fork? | default 0) == 1
        (not $is_archived or $include_archived) and (not $is_fork or $include_forks)
    }
}

# ============================================================================
# Bookmark HTML Generation Helpers
# ============================================================================

# Generate bookmark HTML for a single repository
def generate-bookmark-item [repo: record]: nothing -> string {
    let topics = parse-topics $repo.topics?
    let language = $repo.language? | default ""
    let all_tags = if ($language | str length) > 0 {
        $topics ++ [($language | str downcase)]
    } else { $topics }
    let tags = $all_tags | str join ","
    let description = $repo.description? | default "" | str replace --all '"' '&quot;'
    let add_date = try { $repo.created_at | into datetime | format date %s } catch { "0" }

    mut bookmark = $"        <DT><A HREF=\"($repo.html_url)\" ADD_DATE=\"($add_date)\""
    if ($tags | str length) > 0 { $bookmark = $"($bookmark) TAGS=\"($tags)\"" }
    $bookmark = $"($bookmark)>($repo.full_name)</A>"
    if ($description | str length) > 0 { $bookmark = $"($bookmark)\n        <DD>($description)" }
    $bookmark
}

# Generate bookmark HTML for a group
def generate-bookmark-group [group_key: string, repos: list]: nothing -> list<string> {
    mut html = [$"    <DT><H3>($group_key)</H3>" "    <DL><p>"]
    for repo in $repos { $html ++= [(generate-bookmark-item $repo)] }
    $html ++ ["    </DL><p>"]
}

# Group repositories for bookmarks export
def group-for-bookmarks [filtered: table, group_by: string]: nothing -> record {
    match $group_by {
        "none" => { {"All Stars": $filtered} }
        "language" => { $filtered | group-by {|repo| $repo.language? | default "Unknown" } }
        "owner" => { $filtered | group-by {|repo| get-owner-login $repo.owner } }
        "year" => { $filtered | group-by {|repo| try { $repo.created_at | into datetime | format date %Y } catch { "unknown" } } }
        "topic" => {
            $filtered | group-by {|repo|
                let topics = parse-topics $repo.topics?
                if ($topics | length) > 0 { $topics | first } else { "Untagged" }
            }
        }
        _ => { {"All Stars": $filtered} }
    }
}

# Generate bookmark HTML content
def generate-bookmark-html [filtered: table, format: string, group_by: string]: nothing -> string {
    let header = if $format == "chrome" {
        "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<!-- This is an automatically generated file. DO NOT EDIT! -->\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Bookmarks</TITLE>\n<H1>Bookmarks</H1>\n<DL><p>"
    } else {
        "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<!-- This is an automatically generated file. DO NOT EDIT! -->\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; script-src 'none'; img-src data: *; object-src 'none'\"></meta>\n<TITLE>Bookmarks</TITLE>\n<H1>Bookmarks Menu</H1>\n<DL><p>"
    }

    let grouped = group-for-bookmarks $filtered $group_by
    mut html = [$header]
    for group in ($grouped | items {|k, v| {key: $k, value: $v} }) {
        $html ++= (generate-bookmark-group $group.key $group.value)
    }
    $html ++= ["</DL>"]

    $html | str join "\n"
}

# ============================================================================
# Export Commands
# ============================================================================

# Export stars to CSV format
#
# Exports starred repositories to a CSV file with configurable columns.
# Auto-generates output path if not specified.
#
# Parameters:
#   --output (-o): Custom output file path
#   --columns (-c): List of columns to include (exports all if not specified)
#
# Example:
#   stars export csv
#   stars export csv --output ~/stars.csv
#   stars export csv --columns [name url language stars]
export def "stars export csv" [
    --output (-o): path           # Output path (auto-generated if not provided)
    --columns (-c): list<string>  # Specific columns to export
]: nothing -> path {
    let stars = load

    let output_path = if ($output | is-empty) {
        generate-output-path "stars" "csv"
    } else { $output | path expand }

    # Ensure parent directory exists
    let parent = $output_path | path dirname
    if not ($parent | path exists) {
        mkdir $parent
    }

    let data = $stars | each {|repo| transform-repo-for-export $repo }
    let export_data = if ($columns | is-empty) or ($columns == null) {
        $data
    } else {
        $data | select ...$columns
    }

    try {
        $export_data | to csv | save --force $output_path
    } catch {|e|
        error make {
            msg: $"Failed to save CSV: ($e.msg)"
            label: {text: "file write failed", span: (metadata $output_path).span}
        }
    }

    print $"Exported ($stars | length) stars to ($output_path)"
    $output_path
}

# Export stars to JSON format
#
# Exports starred repositories to a JSON file. Supports minimal schema
# for reduced file size and pretty printing.
#
# Parameters:
#   --output (-o): Custom output file path
#   --minimal (-m): Export minimal data (name, url, description, language, topics)
#   --pretty (-p): Pretty print JSON with indentation
#
# Example:
#   stars export json
#   stars export json --minimal --pretty
#   stars export json --output ~/stars.json
export def "stars export json" [
    --output (-o): path  # Output path (auto-generated if not provided)
    --minimal (-m)       # Minimal schema
    --pretty (-p)        # Pretty print
]: nothing -> path {
    let stars = load

    let output_path = if ($output | is-empty) {
        generate-output-path "stars" "json"
    } else { $output | path expand }

    # Ensure parent directory exists
    let parent = $output_path | path dirname
    if not ($parent | path exists) {
        mkdir $parent
    }

    let export_data = if $minimal {
        $stars | each {|repo|
            {
                name: $repo.full_name
                url: $repo.html_url
                description: ($repo.description? | default "")
                language: ($repo.language? | default "")
                topics: (parse-topics $repo.topics?)
            }
        }
    } else { $stars }

    let json_output = if $pretty {
        $export_data | to json --indent 2
    } else {
        $export_data | to json
    }

    try {
        $json_output | save --force $output_path
    } catch {|e|
        error make {
            msg: $"Failed to save JSON: ($e.msg)"
            label: {text: "file write failed", span: (metadata $output_path).span}
        }
    }

    print $"Exported ($stars | length) stars to ($output_path)"
    $output_path
}

# Export stars to NUON (Nushell Object Notation)
#
# Exports starred repositories to NUON format, which is Nushell's native
# data serialization format. Useful for later import back into Nushell.
#
# Parameters:
#   --output (-o): Custom output file path
#
# Example:
#   stars export nuon
#   stars export nuon --output ~/stars.nuon
export def "stars export nuon" [
    --output (-o): path  # Output path (auto-generated if not provided)
]: nothing -> path {
    let stars = load

    let output_path = if ($output | is-empty) {
        generate-output-path "stars" "nuon"
    } else { $output | path expand }

    # Ensure parent directory exists
    let parent = $output_path | path dirname
    if not ($parent | path exists) {
        mkdir $parent
    }

    try {
        $stars | to nuon | save --force $output_path
    } catch {|e|
        error make {
            msg: $"Failed to save NUON: ($e.msg)"
            label: {text: "file write failed", span: (metadata $output_path).span}
        }
    }

    print $"Exported ($stars | length) stars to ($output_path)"
    $output_path
}

# Export stars to Markdown table
#
# Exports starred repositories as a Markdown table. Great for documentation
# or sharing in GitHub issues/PRs.
#
# Parameters:
#   --output (-o): Custom output file path
#   --columns (-c): Columns to include (default: name, description, language, stars)
#
# Example:
#   stars export md
#   stars export md --columns [name url language]
#   stars export md --output ~/stars.md
export def "stars export md" [
    --output (-o): path           # Output path (auto-generated if not provided)
    --columns (-c): list<string>  # Specific columns to include
]: nothing -> path {
    let stars = load

    let output_path = if ($output | is-empty) {
        generate-output-path "stars" "md"
    } else { $output | path expand }

    # Ensure parent directory exists
    let parent = $output_path | path dirname
    if not ($parent | path exists) {
        mkdir $parent
    }

    let data = $stars | each {|repo| transform-repo-for-export $repo }

    let cols = if ($columns | is-empty) or ($columns == null) {
        ["name" "description" "language" "stars"]
    } else {
        $columns
    }

    let export_data = $data | select ...$cols

    # Generate markdown table header
    let header = $cols | str join " | "
    let separator = $cols | each { "---" } | str join " | "

    # Generate table rows
    let rows = $export_data | each {|row|
        $cols | each {|col|
            let val = $row | get $col | default ""
            # Escape pipes in values
            $val | into string | str replace --all "|" "\\|"
        } | str join " | "
    }

    let md_content = [
        $"# GitHub Stars Export"
        ""
        $"Generated: (date now | format date '%Y-%m-%d %H:%M:%S')"
        ""
        $"Total: ($stars | length) repositories"
        ""
        $"| ($header) |"
        $"| ($separator) |"
        ...($rows | each {|r| $"| ($r) |"})
    ] | str join "\n"

    try {
        $md_content | save --force $output_path
    } catch {|e|
        error make {
            msg: $"Failed to save Markdown: ($e.msg)"
            label: {text: "file write failed", span: (metadata $output_path).span}
        }
    }

    print $"Exported ($stars | length) stars to ($output_path)"
    $output_path
}

# Export stars to Firefox bookmarks HTML
#
# Exports starred repositories as a Firefox-compatible HTML bookmarks file.
# Supports grouping by language, owner, topic, year, or no grouping.
#
# Parameters:
#   --output (-o): Custom output file path
#   --group-by (-g): Grouping strategy (language, owner, topic, year, none)
#   --include-archived: Include archived repositories
#   --include-forks: Include forked repositories
#
# Example:
#   stars export firefox
#   stars export firefox --group-by owner
#   stars export firefox --include-archived --include-forks
export def "stars export firefox" [
    --output (-o): path                # Output path (auto-generated if not provided)
    --group-by (-g): string = "language"  # Grouping: language, owner, topic, year, none
    --include-archived                 # Include archived repositories
    --include-forks                    # Include forked repositories
]: nothing -> path {
    let stars = load

    let output_path = if ($output | is-empty) {
        generate-output-path "bookmarks_firefox" "html"
    } else { $output | path expand }

    # Ensure parent directory exists
    let parent = $output_path | path dirname
    if not ($parent | path exists) {
        mkdir $parent
    }

    let filtered = filter-stars $stars $include_archived $include_forks
    let html_content = generate-bookmark-html $filtered "firefox" $group_by

    try {
        $html_content | save --force $output_path
    } catch {|e|
        error make {
            msg: $"Failed to save Firefox bookmarks: ($e.msg)"
            label: {text: "file write failed", span: (metadata $output_path).span}
        }
    }

    print $"Exported ($filtered | length) stars to Firefox bookmarks at ($output_path)"
    $output_path
}

# Export stars to Chrome bookmarks HTML
#
# Exports starred repositories as a Chrome-compatible HTML bookmarks file.
# Supports grouping by language, owner, topic, year, or no grouping.
#
# Parameters:
#   --output (-o): Custom output file path
#   --group-by (-g): Grouping strategy (language, owner, topic, year, none)
#   --include-archived: Include archived repositories
#   --include-forks: Include forked repositories
#
# Example:
#   stars export chrome
#   stars export chrome --group-by topic
#   stars export chrome --output ~/chrome_bookmarks.html
export def "stars export chrome" [
    --output (-o): path                # Output path (auto-generated if not provided)
    --group-by (-g): string = "language"  # Grouping: language, owner, topic, year, none
    --include-archived                 # Include archived repositories
    --include-forks                    # Include forked repositories
]: nothing -> path {
    let stars = load

    let output_path = if ($output | is-empty) {
        generate-output-path "bookmarks_chrome" "html"
    } else { $output | path expand }

    # Ensure parent directory exists
    let parent = $output_path | path dirname
    if not ($parent | path exists) {
        mkdir $parent
    }

    let filtered = filter-stars $stars $include_archived $include_forks
    let html_content = generate-bookmark-html $filtered "chrome" $group_by

    try {
        $html_content | save --force $output_path
    } catch {|e|
        error make {
            msg: $"Failed to save Chrome bookmarks: ($e.msg)"
            label: {text: "file write failed", span: (metadata $output_path).span}
        }
    }

    print $"Exported ($filtered | length) stars to Chrome bookmarks at ($output_path)"
    $output_path
}
