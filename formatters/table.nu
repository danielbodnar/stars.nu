#!/usr/bin/env nu

# ============================================================================
# Table Formatter Module for Stars
# ============================================================================
#
# Provides human-readable table formatting with ANSI colors and clickable links.
# Respects NO_COLOR environment variable for accessibility.
#
# # Usage
# ```nushell
# use formatters/table.nu *
# gh-stars load | format
# ```
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

# ============================================================================
# Constants
# ============================================================================

# Default columns to display (in order)
const DEFAULT_COLUMNS = [
    owner
    name
    language
    stars
    pushed
    homepage
    topics
    description
    forks
    issues
]

# Language color mappings
const LANGUAGE_COLORS = {
    Rust: red_bold
    TypeScript: blue_bold
    JavaScript: yellow
    Go: cyan_bold
    Nushell: green_bold
    Python: blue
    Ruby: red
    Java: yellow_bold
    "C++": magenta_bold
    C: white_bold
    Shell: green
    Bash: green
    Lua: purple_bold
    Zig: yellow
    Haskell: purple
    Elixir: purple
    Clojure: green
    Scala: red
    Kotlin: purple_bold
    Swift: yellow
    Dart: cyan
    PHP: purple
    Perl: cyan
    R: blue
    Julia: purple
    OCaml: yellow
    F#: cyan_bold
    Elm: cyan
    Vue: green_bold
    Svelte: red
    HTML: red
    CSS: blue
    SCSS: magenta
    Markdown: white
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if colors should be disabled
def colors-disabled []: nothing -> bool {
    ($env.NO_COLOR? | default "" | is-not-empty)
}

# Truncate text with ellipsis
#
# Parameters:
#   text: string - Text to truncate
#   max_len: int - Maximum length (default 80)
#
# Returns: string - Truncated text with ellipsis if needed
#
# Example:
#   truncate "Very long description text" 20
export def truncate [
    text: string      # Text to truncate
    max_len: int = 80 # Maximum length
]: nothing -> string {
    let clean_text = $text | default ""
    if ($clean_text | str length) <= $max_len {
        $clean_text
    } else {
        $"($clean_text | str substring 0..($max_len - 1))..."
    }
}

# Format star count with suffixes (1234 -> 1.2k, 1234567 -> 1.2M)
#
# Parameters:
#   count: int - Star count to format
#
# Returns: string - Formatted star count
#
# Example:
#   format-stars 1234    # Returns "1.2k"
#   format-stars 1234567 # Returns "1.2M"
export def format-stars [
    count: int # Star count to format
]: nothing -> string {
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

# Format date as YYYY-MM-DD
#
# Parameters:
#   date: any - Date value (string, datetime, or null)
#
# Returns: string - Formatted date or empty string
#
# Example:
#   format-date "2024-01-15T10:30:00Z" # Returns "2024-01-15"
export def format-date [
    date: any # Date to format
]: nothing -> string {
    if ($date | is-empty) {
        return ""
    }

    try {
        $date | into datetime | format date "%Y-%m-%d"
    } catch {
        try {
            # Handle if already a string in ISO format
            $date | str substring 0..10
        } catch {
            ""
        }
    }
}

# Create clickable OSC 8 hyperlink
#
# Parameters:
#   url: string - Target URL
#   text: string - Display text
#
# Returns: string - OSC 8 formatted link or plain text if colors disabled
#
# Example:
#   make-link "https://github.com/user/repo" "repo"
export def make-link [
    url: string  # Target URL
    text: string # Display text
]: nothing -> string {
    if (colors-disabled) or ($url | is-empty) {
        return $text
    }

    # OSC 8 escape sequence: ESC ] 8 ; ; URL ESC \ TEXT ESC ] 8 ; ; ESC \
    # Use unicode code point 0x1b for escape character
    let esc = (char -u "1b")
    let bel = (char -u "07")
    # Using BEL (0x07) as terminator which is more widely supported than ST (ESC \)
    let osc8_start = $"($esc)]8;;($url)($bel)"
    let osc8_end = $"($esc)]8;;($bel)"

    $"($osc8_start)($text)($osc8_end)"
}

# Colorize language name based on language type
#
# Parameters:
#   lang: string - Language name
#
# Returns: string - ANSI-colored language name or plain text
#
# Example:
#   colorize-language "Rust" # Returns red bold "Rust"
export def colorize-language [
    lang: string # Language name
]: nothing -> string {
    let language = $lang | default ""

    if (colors-disabled) or ($language | is-empty) {
        return $language
    }

    let color = $LANGUAGE_COLORS | get -o $language | default "default"

    if $color == "default" {
        $language
    } else {
        $"(ansi $color)($language)(ansi reset)"
    }
}

# ============================================================================
# Row Formatting
# ============================================================================

# Parse owner login from JSON string or record
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

# Format a single star record for display
#
# Parameters:
#   row: record - Star repository record
#
# Returns: record - Formatted record for display
#
# Example:
#   format-row $repo
export def format-row [
    row: record # Star repository record
]: nothing -> record {
    let no_links = colors-disabled
    let owner = get-owner-login ($row.owner? | default "")
    let name = $row.name? | default ""
    let html_url = $row.html_url? | default ""
    let homepage = $row.homepage? | default ""
    let language = $row.language? | default ""
    let stars_count = $row.stargazers_count? | default 0
    let forks_count = $row.forks_count? | default 0
    let issues_count = $row.open_issues_count? | default 0
    let pushed_at = $row.pushed_at? | default ""
    let description = $row.description? | default ""
    let topics_raw = $row.topics? | default []

    # Format topics as comma-separated list
    let topics_list = parse-topics $topics_raw
    let topics_str = $topics_list | str join ", "

    # Build formatted record
    {
        owner: $owner
        name: (if $no_links { $name } else { make-link $html_url $name })
        language: (colorize-language $language)
        stars: (format-stars $stars_count)
        pushed: (format-date $pushed_at)
        homepage: (if ($homepage | is-empty) { "" } else if $no_links { $homepage } else { make-link $homepage (truncate $homepage 30) })
        topics: (truncate $topics_str 40)
        description: (truncate $description 60)
        forks: ($forks_count | into string)
        issues: ($issues_count | into string)
    }
}

# ============================================================================
# Table Formatting
# ============================================================================

# Format stars table for human-readable display
#
# Parameters:
#   data: table - Table of star repository records
#   --columns: list<string> - Override default columns (optional)
#   --no-links: bool - Disable clickable links
#   --no-colors: bool - Disable colors (or respects NO_COLOR env)
#
# Returns: table - Formatted table for display
#
# Example:
#   gh-stars load | format
#   gh-stars load | format --columns [name language stars]
#   gh-stars load | format --no-colors
export def format [
    --columns: list<string> = []     # Override default columns
    --no-links                        # Disable clickable links
    --no-colors                       # Disable colors
]: table -> table {
    let data = $in
    # Temporarily set NO_COLOR if --no-colors is passed
    let should_disable_colors = $no_colors or (colors-disabled)

    # Format each row
    let formatted = if $should_disable_colors or $no_links {
        # Use a wrapper that forces no-color mode
        $data | each {|row|
            let owner = get-owner-login ($row.owner? | default "")
            let name = $row.name? | default ""
            let homepage = $row.homepage? | default ""
            let language = $row.language? | default ""
            let stars_count = $row.stargazers_count? | default 0
            let forks_count = $row.forks_count? | default 0
            let issues_count = $row.open_issues_count? | default 0
            let pushed_at = $row.pushed_at? | default ""
            let description = $row.description? | default ""
            let topics_raw = $row.topics? | default []

            let topics_list = parse-topics $topics_raw
            let topics_str = $topics_list | str join ", "

            {
                owner: $owner
                name: $name
                language: (if $should_disable_colors { $language } else { colorize-language $language })
                stars: (format-stars $stars_count)
                pushed: (format-date $pushed_at)
                homepage: (if ($homepage | is-empty) { "" } else { truncate $homepage 30 })
                topics: (truncate $topics_str 40)
                description: (truncate $description 60)
                forks: ($forks_count | into string)
                issues: ($issues_count | into string)
            }
        }
    } else {
        $data | each {|row| format-row $row }
    }

    # Select columns
    let cols = if ($columns | is-empty) { $DEFAULT_COLUMNS } else { $columns }

    # Filter to only existing columns and return
    let available_cols = $cols | where {|c| $c in ($formatted | columns) }
    $formatted | select ...$available_cols
}

# ============================================================================
# Convenience Aliases
# ============================================================================

# Short alias for format command
export alias fmt = format
