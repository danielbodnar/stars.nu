#!/usr/bin/env nu

# ============================================================================
# Awesome List Adapter
# ============================================================================
#
# Imports GitHub repository URLs from awesome-* markdown files.
# Parses markdown content to extract GitHub links and normalizes them
# to the standard star schema.
#
# Supports:
# - Local markdown files
# - Remote URLs (fetched via http get)
# - Various GitHub URL formats
#
# Author: Daniel Bodnar
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Fetch content from a URL
#
# Makes an HTTP GET request to fetch markdown content.
# Handles common HTTP errors with helpful messages.
#
# Parameters:
#   url: string - Full URL to fetch
def fetch-from-url [url: string]: nothing -> string {
    let result = try {
        http get $url | complete
    } catch {|e|
        error make {
            msg: $"Failed to fetch URL: ($e.msg)"
            label: {text: "network error", span: (metadata $url).span}
            help: "Check your network connection and verify the URL is accessible"
        }
    }

    if ($result | describe | str replace --regex '<.*' '') == "record" {
        if ($result.exit_code? | default 0) != 0 {
            error make {
                msg: $"HTTP request failed: ($result.stderr? | default 'Unknown error')"
                label: {text: "request failed", span: (metadata $url).span}
                help: "Verify the URL is correct and accessible"
            }
        }
        $result.stdout? | default ""
    } else {
        # http get returned the content directly
        $result | into string
    }
}

# Read content from a local file
#
# Parameters:
#   path: path - Path to local markdown file
def read-from-file [path: path]: nothing -> string {
    if not ($path | path exists) {
        error make {
            msg: $"File not found: ($path)"
            label: {text: "file does not exist", span: (metadata $path).span}
            help: "Check the file path and ensure the file exists"
        }
    }

    try {
        open $path --raw
    } catch {|e|
        error make {
            msg: $"Failed to read file: ($e.msg)"
            label: {text: "read error", span: (metadata $path).span}
            help: "Check file permissions and encoding"
        }
    }
}

# Parse a GitHub URL to extract owner and repo
#
# Handles various GitHub URL formats:
# - https://github.com/owner/repo
# - https://github.com/owner/repo/tree/branch
# - https://github.com/owner/repo/blob/branch/file
# - http://github.com/owner/repo
# - github.com/owner/repo
#
# Parameters:
#   url: string - GitHub URL to parse
#
# Returns: record with owner and repo, or null if invalid
def parse-github-url [url: string]: nothing -> record {
    # Normalize the URL
    let normalized = $url
        | str trim
        | str replace --regex '^http://' 'https://'
        | str replace --regex '^(github\.com)' 'https://$1'

    # Extract owner/repo from the path
    let match = $normalized | parse --regex 'https://github\.com/([^/]+)/([^/\s#?]+)'

    if ($match | is-empty) {
        return null
    }

    let owner = $match | first | get capture0
    let repo = $match | first | get capture1
        | str replace --regex '\.git$' ''  # Remove .git suffix if present

    # Validate owner and repo names (basic GitHub username/repo name rules)
    if ($owner | is-empty) or ($repo | is-empty) {
        return null
    }

    # Skip if it looks like a user profile page (no repo)
    if $repo in ["followers", "following", "stars", "repositories", "projects", "packages", "sponsoring", "sponsors"] {
        return null
    }

    {
        owner: $owner
        repo: $repo
    }
}

# Extract GitHub links from markdown content
#
# Finds all GitHub URLs in markdown, including:
# - Markdown links: [text](url)
# - Bare URLs
# - Reference-style links
#
# Parameters:
#   content: string - Markdown content to parse
#
# Returns: list of records with url, text, and context
def extract-github-links [content: string]: nothing -> list<record> {
    mut links = []

    # Pattern 1: Markdown links [text](url)
    let md_links = $content | parse --regex '\[([^\]]+)\]\((https?://github\.com/[^\s\)]+)\)'
    for link in $md_links {
        $links = ($links | append {
            url: $link.capture1
            text: $link.capture0
            format: "markdown"
        })
    }

    # Pattern 2: Markdown links with github.com (no protocol)
    let md_links_no_proto = $content | parse --regex '\[([^\]]+)\]\((github\.com/[^\s\)]+)\)'
    for link in $md_links_no_proto {
        $links = ($links | append {
            url: $"https://($link.capture1)"
            text: $link.capture0
            format: "markdown"
        })
    }

    # Pattern 3: Bare URLs (not inside markdown link syntax)
    # Match URLs that are not preceded by ]( which would indicate they're already captured
    let bare_links = $content
        | lines
        | each {|line|
            # Skip lines that are markdown links (already captured above)
            if ($line =~ '\]\(https?://github\.com') or ($line =~ '\]\(github\.com') {
                []
            } else {
                $line | parse --regex '(?<![(\[])(https?://github\.com/[^\s\)\]<>"]+)'
            }
        }
        | flatten

    for link in $bare_links {
        let url = $link.capture0 | str trim --char '.' | str trim --char ','
        $links = ($links | append {
            url: $url
            text: ""
            format: "bare"
        })
    }

    # Pattern 4: github.com without protocol (bare)
    let bare_no_proto = $content
        | lines
        | each {|line|
            if ($line =~ '\]\(github\.com') {
                []
            } else {
                $line | parse --regex '(?<![/(\[])(github\.com/[^\s\)\]<>"]+)'
            }
        }
        | flatten

    for link in $bare_no_proto {
        let url = $"https://($link.capture0)" | str trim --char '.' | str trim --char ','
        $links = ($links | append {
            url: $url
            text: ""
            format: "bare"
        })
    }

    # Deduplicate by URL, keeping the first occurrence (which likely has the best text)
    $links | uniq-by url
}

# Normalize an extracted link to our star schema
#
# Takes a link record and transforms it to our standard format.
# Only populates fields that can be derived from the URL/text.
# Other fields are left null for later enrichment via GitHub API.
#
# Parameters:
#   link: record - Extracted link with url, text, format fields
def normalize-link [link: record]: nothing -> record {
    let parsed = parse-github-url $link.url

    if ($parsed == null) {
        return null
    }

    let synced_at = date now | format date "%Y-%m-%dT%H:%M:%SZ"
    let full_name = $"($parsed.owner)/($parsed.repo)"
    let html_url = $"https://github.com/($full_name)"

    # Use the link text as description if available
    let description = if ($link.text | is-empty) or ($link.text == $full_name) or ($link.text == $parsed.repo) {
        null
    } else {
        $link.text
    }

    {
        id: 0  # Placeholder, will be replaced during enrichment or storage
        node_id: ""
        name: $parsed.repo
        full_name: $full_name
        owner: $parsed.owner
        private: false
        html_url: $html_url
        description: $description
        fork: false
        url: $"https://api.github.com/repos/($full_name)"
        created_at: null
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
        source: "awesome"
        synced_at: $synced_at
    }
}

# ============================================================================
# Public API
# ============================================================================

# Parse markdown content and extract GitHub URLs
#
# Processes markdown content to find and extract all GitHub repository URLs.
# Returns a table of normalized star records.
#
# Parameters:
#   content: string - Raw markdown content
#
# Example:
#   open README.md | parse-markdown
export def parse-markdown [content: string]: nothing -> table {
    if ($content | is-empty) {
        error make {
            msg: "Empty content provided"
            label: {text: "no content to parse", span: (metadata $content).span}
            help: "Provide markdown content containing GitHub URLs"
        }
    }

    let links = extract-github-links $content

    if ($links | is-empty) {
        return []
    }

    # Normalize each link to our schema
    let normalized = $links | each {|link|
        normalize-link $link
    } | compact  # Remove null entries (invalid URLs)

    # Deduplicate by full_name (same repo might be linked multiple times)
    $normalized | uniq-by full_name
}

# Import GitHub repos from an awesome list
#
# Fetches content from a URL or local path and extracts all GitHub repository
# links. Returns a table of normalized star records.
#
# Parameters:
#   source: string - URL or local path to awesome list markdown file
#
# Examples:
#   # From URL
#   fetch "https://raw.githubusercontent.com/sindresorhus/awesome/main/readme.md"
#
#   # From local file
#   fetch "./awesome-rust/README.md"
#
#   # From a raw GitHub URL
#   fetch "https://github.com/avelino/awesome-go/raw/main/README.md"
export def fetch [
    source: string  # URL or local path to awesome list markdown
]: nothing -> table {
    if ($source | is-empty) {
        error make {
            msg: "Source is required"
            label: {text: "provide a URL or file path", span: (metadata $source).span}
        }
    }

    # Determine if source is URL or local path
    let is_url = ($source | str starts-with "http://") or ($source | str starts-with "https://")

    let content = if $is_url {
        # Transform GitHub blob URLs to raw URLs for direct access
        let raw_url = $source
            | str replace --regex 'github\.com/([^/]+)/([^/]+)/blob/' 'raw.githubusercontent.com/$1/$2/'

        fetch-from-url $raw_url
    } else {
        read-from-file ($source | path expand)
    }

    let stars = parse-markdown $content

    if ($stars | is-empty) {
        print --stderr $"Warning: No GitHub links found in ($source)"
    }

    $stars
}

# Enrich star records with data from GitHub API
#
# Takes a table of star records (from parse-markdown or fetch) and
# enriches them with full repository data from the GitHub API.
# Requires gh CLI to be installed and authenticated.
#
# Parameters:
#   stars: table - Star records to enrich
#   --batch-size: int - Number of repos to fetch per batch (default: 10)
#   --delay: duration - Delay between batches to avoid rate limiting (default: 500ms)
#
# Example:
#   fetch "awesome-list.md" | enrich
export def enrich [
    stars: table            # Star records to enrich
    --batch-size: int = 10  # Repos per batch
    --delay: duration = 500ms  # Delay between batches
]: nothing -> table {
    if ($stars | is-empty) {
        return []
    }

    # Check if gh CLI is available
    let gh_check = which gh | length
    if $gh_check == 0 {
        error make {
            msg: "gh CLI not found"
            help: "Install gh CLI from https://cli.github.com/ for enrichment"
        }
    }

    let total = $stars | length
    mut enriched = []
    mut current = 0

    # Process in batches
    let batches = $stars | chunks $batch_size

    for batch in $batches {
        for star in $batch {
            $current = $current + 1
            let full_name = $star.full_name

            # Fetch repo data from GitHub API
            let result = try {
                gh api $"repos/($full_name)" | complete
            } catch {
                null
            }

            if ($result != null) and ($result.exit_code == 0) {
                let repo_data = try {
                    $result.stdout | from json
                } catch {
                    null
                }

                if ($repo_data != null) {
                    # Merge GitHub data with our record
                    let synced_at = date now | format date "%Y-%m-%dT%H:%M:%SZ"
                    let license_name = try {
                        $repo_data.license? | get name? | default null
                    } catch { null }
                    let topics = try {
                        $repo_data.topics? | default [] | to json --raw
                    } catch { "[]" }

                    $enriched = ($enriched | append {
                        id: ($repo_data.id? | default 0)
                        node_id: ($repo_data.node_id? | default "")
                        name: ($repo_data.name? | default $star.name)
                        full_name: ($repo_data.full_name? | default $full_name)
                        owner: ($repo_data.owner?.login? | default $star.owner)
                        private: ($repo_data.private? | default false)
                        html_url: ($repo_data.html_url? | default $star.html_url)
                        description: ($repo_data.description? | default $star.description)
                        fork: ($repo_data.fork? | default false)
                        url: ($repo_data.url? | default $star.url)
                        created_at: ($repo_data.created_at? | default null)
                        updated_at: ($repo_data.updated_at? | default null)
                        pushed_at: ($repo_data.pushed_at? | default null)
                        homepage: ($repo_data.homepage? | default null)
                        size: ($repo_data.size? | default 0)
                        stargazers_count: ($repo_data.stargazers_count? | default 0)
                        watchers_count: ($repo_data.watchers_count? | default 0)
                        language: ($repo_data.language? | default null)
                        forks_count: ($repo_data.forks_count? | default 0)
                        archived: ($repo_data.archived? | default false)
                        disabled: ($repo_data.disabled? | default false)
                        open_issues_count: ($repo_data.open_issues_count? | default 0)
                        license: $license_name
                        topics: $topics
                        visibility: ($repo_data.visibility? | default "public")
                        default_branch: ($repo_data.default_branch? | default "main")
                        source: "awesome"
                        synced_at: $synced_at
                    })
                } else {
                    # Keep original record if parse failed
                    $enriched = ($enriched | append $star)
                }
            } else {
                # Keep original record if API call failed (repo might be deleted/private)
                $enriched = ($enriched | append $star)
            }
        }

        # Delay between batches to avoid rate limiting
        if ($current < $total) {
            sleep $delay
        }
    }

    $enriched
}

# Get a summary of extracted repositories
#
# Returns statistics about the extracted repos without enrichment.
#
# Parameters:
#   stars: table - Star records from fetch or parse-markdown
#
# Example:
#   fetch "awesome-list.md" | summary
export def summary [
    stars: table  # Star records to summarize
]: nothing -> record {
    if ($stars | is-empty) {
        return {
            total: 0
            unique_owners: 0
            with_description: 0
            owners: []
        }
    }

    let owners = $stars | get owner | uniq | sort
    let with_desc = $stars | where description != null | length

    {
        total: ($stars | length)
        unique_owners: ($owners | length)
        with_description: $with_desc
        owners: ($owners | first 20)  # Top 20 owners
    }
}

# Validate that all URLs are valid GitHub repositories
#
# Checks each repo against the GitHub API to verify it exists.
# Returns a record with valid and invalid repo lists.
#
# Parameters:
#   stars: table - Star records to validate
#
# Example:
#   fetch "awesome-list.md" | validate
export def validate [
    stars: table  # Star records to validate
]: nothing -> record<valid: table, invalid: table, errors: list<string>> {
    if ($stars | is-empty) {
        return {
            valid: []
            invalid: []
            errors: []
        }
    }

    # Check if gh CLI is available
    let gh_check = which gh | length
    if $gh_check == 0 {
        error make {
            msg: "gh CLI not found"
            help: "Install gh CLI from https://cli.github.com/ for validation"
        }
    }

    mut valid = []
    mut invalid = []
    mut errors = []

    for star in $stars {
        let result = try {
            gh api $"repos/($star.full_name)" --silent | complete
        } catch {
            {exit_code: 1, stderr: "request failed"}
        }

        if $result.exit_code == 0 {
            $valid = ($valid | append $star)
        } else {
            $invalid = ($invalid | append $star)
            $errors = ($errors | append $"($star.full_name): ($result.stderr? | default 'not found')")
        }
    }

    {
        valid: $valid
        invalid: $invalid
        errors: $errors
    }
}
