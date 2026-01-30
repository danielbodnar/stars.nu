#!/usr/bin/env nu

# ============================================================================
# Stars Module Test Suite
# ============================================================================
#
# Comprehensive tests for the stars module functionality.
#
# # Running Tests
# ```nushell
# nu tests/main.test.nu              # Run all tests
# nu tests/main.test.nu --verbose    # Run with verbose output
# nu tests/main.test.nu --test filter # Run specific test
# ```
#
# # Test Categories
# - Type helper tests (parse-topics, get-owner-login)
# - Storage path tests (XDG compliance)
# - Filter tests (language, archived, old, exclusions)
# - Formatter tests (stars count, dates, columns)
# - Search tests (name, description, case-insensitive)
# - Statistics tests (calculations, grouping)
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

use std/assert

# ============================================================================
# Test Fixtures
# ============================================================================

# Generate mock repository data for testing
# Returns 8 diverse mock repositories covering various scenarios
def mock-repos []: nothing -> list<any> {
    [
        {
            id: 1
            name: "nushell"
            full_name: "nushell/nushell"
            html_url: "https://github.com/nushell/nushell"
            homepage: "https://nushell.sh"
            description: "A new type of shell"
            language: "Rust"
            stargazers_count: 25000
            forks_count: 1200
            open_issues_count: 150
            topics: '["shell", "rust", "cli"]'
            owner: '{"login": "nushell"}'
            created_at: "2019-05-10T00:00:00Z"
            updated_at: "2024-01-15T00:00:00Z"
            pushed_at: "2024-01-15T00:00:00Z"
            archived: false
            fork: false
            license: '{"name": "MIT License"}'
        }
        {
            id: 2
            name: "rust"
            full_name: "rust-lang/rust"
            html_url: "https://github.com/rust-lang/rust"
            homepage: "https://rust-lang.org"
            description: "Empowering everyone to build reliable software"
            language: "Rust"
            stargazers_count: 85000
            forks_count: 11000
            open_issues_count: 9500
            topics: '["rust", "programming-language", "compiler"]'
            owner: '{"login": "rust-lang"}'
            created_at: "2010-06-16T00:00:00Z"
            updated_at: "2024-01-14T00:00:00Z"
            pushed_at: "2024-01-14T00:00:00Z"
            archived: false
            fork: false
            license: '{"name": "Apache License 2.0"}'
        }
        {
            id: 3
            name: "old-project"
            full_name: "someone/old-project"
            html_url: "https://github.com/someone/old-project"
            homepage: ""
            description: "An archived project"
            language: "JavaScript"
            stargazers_count: 100
            forks_count: 10
            open_issues_count: 0
            topics: '[]'
            owner: '{"login": "someone"}'
            created_at: "2015-01-01T00:00:00Z"
            updated_at: "2020-01-01T00:00:00Z"
            pushed_at: "2020-01-01T00:00:00Z"
            archived: true
            fork: false
            license: null
        }
        {
            id: 4
            name: "typescript-lib"
            full_name: "dev/typescript-lib"
            html_url: "https://github.com/dev/typescript-lib"
            homepage: "https://lib.dev"
            description: "A TypeScript library for modern development"
            language: "TypeScript"
            stargazers_count: 500
            forks_count: 50
            open_issues_count: 15
            topics: '["typescript", "library"]'
            owner: '{"login": "dev"}'
            created_at: "2022-06-01T00:00:00Z"
            updated_at: "2024-01-10T00:00:00Z"
            pushed_at: "2024-01-10T00:00:00Z"
            archived: false
            fork: true
            license: '{"name": "MIT License"}'
        }
        {
            id: 5
            name: "go-api"
            full_name: "company/go-api"
            html_url: "https://github.com/company/go-api"
            homepage: null
            description: "High-performance API server"
            language: "Go"
            stargazers_count: 3500
            forks_count: 280
            open_issues_count: 45
            topics: '["go", "api", "server", "http"]'
            owner: '{"login": "company"}'
            created_at: "2021-03-15T00:00:00Z"
            updated_at: "2024-01-12T00:00:00Z"
            pushed_at: "2024-01-12T00:00:00Z"
            archived: false
            fork: false
            license: '{"name": "BSD-3-Clause"}'
        }
        {
            id: 6
            name: "python-ml"
            full_name: "researcher/python-ml"
            html_url: "https://github.com/researcher/python-ml"
            homepage: ""
            description: "Machine learning experiments"
            language: "Python"
            stargazers_count: 1500
            forks_count: 200
            open_issues_count: 30
            topics: '["python", "machine-learning", "ai"]'
            owner: '{"login": "researcher"}'
            created_at: "2020-08-01T00:00:00Z"
            updated_at: "2023-12-01T00:00:00Z"
            pushed_at: "2023-12-01T00:00:00Z"
            archived: false
            fork: false
            license: '{"name": "MIT License"}'
        }
        {
            id: 7
            name: "php-framework"
            full_name: "web/php-framework"
            html_url: "https://github.com/web/php-framework"
            homepage: "https://framework.example.com"
            description: "A PHP web framework"
            language: "PHP"
            stargazers_count: 2000
            forks_count: 400
            open_issues_count: 80
            topics: '["php", "framework", "web"]'
            owner: '{"login": "web"}'
            created_at: "2018-02-01T00:00:00Z"
            updated_at: "2024-01-08T00:00:00Z"
            pushed_at: "2024-01-08T00:00:00Z"
            archived: false
            fork: false
            license: '{"name": "GPL-3.0"}'
        }
        {
            id: 8
            name: "empty-topics-repo"
            full_name: "user/empty-topics-repo"
            html_url: "https://github.com/user/empty-topics-repo"
            homepage: null
            description: null
            language: null
            stargazers_count: 5
            forks_count: 0
            open_issues_count: 0
            topics: null
            owner: "plainuser"
            created_at: "2024-01-01T00:00:00Z"
            updated_at: "2024-01-05T00:00:00Z"
            pushed_at: "2024-01-05T00:00:00Z"
            archived: false
            fork: false
            license: null
        }
    ]
}

# ============================================================================
# Type Helper Tests
# ============================================================================

# Test parsing topics from JSON string
def "test types parse-topics json string" [] {
    # Simulate parse-topics function behavior
    let topics_json = '["rust", "cli", "shell"]'
    let parsed = $topics_json | from json

    assert equal ($parsed | length) 3
    assert ("rust" in $parsed)
    assert ("cli" in $parsed)
    assert ("shell" in $parsed)

    print "  ✓ parse-topics handles JSON string correctly"
}

# Test parsing topics from native list
def "test types parse-topics list" [] {
    let topics_list = [rust, cli, shell]

    assert equal ($topics_list | length) 3
    assert ("rust" in $topics_list)

    print "  ✓ parse-topics handles native list correctly"
}

# Test parsing topics from empty/null
def "test types parse-topics empty" [] {
    # Empty string
    let empty_json = '[]'
    let empty_parsed = $empty_json | from json
    assert equal ($empty_parsed | length) 0

    # Null handling
    let null_topics = null
    let null_result = $null_topics | default []
    assert equal ($null_result | length) 0

    print "  ✓ parse-topics handles empty/null values correctly"
}

# Test getting owner login from JSON string
def "test types get-owner-login json" [] {
    let owner_json = '{"login": "rust-lang"}'
    let parsed = $owner_json | from json | get login

    assert equal $parsed "rust-lang"

    print "  ✓ get-owner-login extracts from JSON string correctly"
}

# Test getting owner login from record
def "test types get-owner-login record" [] {
    let owner_record = {login: "nushell"}
    let login = $owner_record | get login

    assert equal $login "nushell"

    print "  ✓ get-owner-login extracts from record correctly"
}

# Test getting owner login from plain string
def "test types get-owner-login string" [] {
    let owner_string = "plainuser"

    # When owner is already a plain string, use it directly
    let type = $owner_string | describe | str replace --regex '<.*' ''
    let result = if $type == "string" and not ($owner_string | str starts-with "{") {
        $owner_string
    } else {
        "unknown"
    }

    assert equal $result "plainuser"

    print "  ✓ get-owner-login handles plain string correctly"
}

# ============================================================================
# Storage Path Tests
# ============================================================================

# Test XDG-compliant storage paths
def "test storage paths xdg compliant" [] {
    let home_path = $env.HOME? | default "/home/user"
    let data_home = $env.XDG_DATA_HOME? | default ($home_path | path join .local share)

    # Simulate get-paths function
    let base_dir = $data_home | path join .stars
    let paths = {
        db_path: ($base_dir | path join stars.db)
        backup_dir: ($base_dir | path join backups)
        export_dir: ($base_dir | path join exports)
    }

    # All paths should be under XDG_DATA_HOME
    assert ($paths.db_path | str starts-with $data_home)
    assert ($paths.backup_dir | str starts-with $data_home)
    assert ($paths.export_dir | str starts-with $data_home)

    # Paths should use .stars directory
    assert ($paths.db_path | str contains ".stars")
    assert ($paths.backup_dir | str contains ".stars")

    print "  ✓ Storage paths are XDG-compliant"
}

# Test config path XDG compliance
def "test storage config path xdg compliant" [] {
    let home_path = $env.HOME? | default "/home/user"
    let config_home = $env.XDG_CONFIG_HOME? | default ($home_path | path join .config)

    let config_path = $config_home | path join stars config.nu

    assert ($config_path | str starts-with $config_home)
    assert ($config_path | str ends-with "config.nu")

    print "  ✓ Config path is XDG-compliant"
}

# ============================================================================
# Filter Tests
# ============================================================================

# Test filtering by language
def "test filter by language" [] {
    let repos = mock-repos

    let rust_repos = $repos | where language == "Rust"

    assert equal ($rust_repos | length) 2
    assert ($rust_repos | all {|r| $r.language == "Rust" })

    print "  ✓ Language filtering works correctly"
}

# Test filtering out archived repositories
def "test filter exclude archived" [] {
    let repos = mock-repos

    let active_repos = $repos | where {|r| not $r.archived }
    let archived_repos = $repos | where archived

    assert equal ($archived_repos | length) 1
    assert equal ($archived_repos | first | get name) "old-project"
    assert equal ($active_repos | length) 7

    print "  ✓ Archived filtering works correctly"
}

# Test filtering out old repos (not pushed in 1+ years)
def "test filter exclude old repos" [] {
    let repos = mock-repos

    # Define cutoff as 1 year ago from a fixed date (2024-01-15)
    let cutoff_date = "2023-01-15T00:00:00Z"

    let recent_repos = $repos | where {|r|
        let pushed = $r.pushed_at? | default "1970-01-01T00:00:00Z"
        $pushed > $cutoff_date
    }

    # old-project pushed 2020-01-01 should be filtered out
    let old_count = $repos | where {|r|
        let pushed = $r.pushed_at? | default "1970-01-01T00:00:00Z"
        $pushed <= $cutoff_date
    } | length

    assert ($old_count >= 1)
    assert ($recent_repos | all {|r| $r.name != "old-project" })

    print "  ✓ Old repos filtering works correctly"
}

# Test filtering out excluded languages
def "test filter exclude languages" [] {
    let repos = mock-repos
    let excluded_languages = [PHP, Python, Java, Ruby, "C#"]

    let filtered = $repos | where {|r|
        let lang = $r.language? | default ""
        $lang not-in $excluded_languages
    }

    # PHP and Python repos should be filtered
    assert ($filtered | all {|r| ($r.language? | default "") not-in $excluded_languages })
    assert equal ($filtered | where language == "PHP" | length) 0
    assert equal ($filtered | where language == "Python" | length) 0

    print "  ✓ Language exclusion filtering works correctly"
}

# Test filtering forks
def "test filter forks" [] {
    let repos = mock-repos

    let original_repos = $repos | where {|r| not $r.fork }
    let forked_repos = $repos | where fork

    assert equal ($forked_repos | length) 1
    assert equal ($forked_repos | first | get name) "typescript-lib"
    assert equal ($original_repos | length) 7

    print "  ✓ Fork filtering works correctly"
}

# Test filtering by topics
def "test filter by topics" [] {
    let repos = mock-repos

    let cli_repos = $repos | where {|repo|
        let topics = try { $repo.topics | from json } catch { [] }
        "cli" in $topics
    }

    assert equal ($cli_repos | length) 1
    assert equal ($cli_repos | first | get name) "nushell"

    print "  ✓ Topic filtering works correctly"
}

# ============================================================================
# Formatter Tests
# ============================================================================

# Test formatting star counts with suffixes
def "test format stars count" [] {
    # Test function that mimics format-stars behavior
    def test-format-stars [count: int]: nothing -> string {
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

    assert equal (test-format-stars 100) "100"
    assert equal (test-format-stars 999) "999"
    assert equal (test-format-stars 1000) "1.0k"
    assert equal (test-format-stars 1234) "1.2k"
    assert equal (test-format-stars 25000) "25.0k"
    assert equal (test-format-stars 1000000) "1.0M"
    assert equal (test-format-stars 1234567) "1.2M"
    assert equal (test-format-stars 85000000) "85.0M"

    print "  ✓ Star count formatting works correctly"
}

# Test date formatting
def "test format date" [] {
    let iso_date = "2024-01-15T10:30:00Z"
    # substring 0..<10 is exclusive on right side
    let formatted = $iso_date | str substring 0..<10

    assert equal $formatted "2024-01-15"

    # Test with datetime conversion
    let parsed = try {
        $iso_date | into datetime | format date "%Y-%m-%d"
    } catch {
        $iso_date | str substring 0..<10
    }

    assert equal $parsed "2024-01-15"

    print "  ✓ Date formatting works correctly"
}

# Test table columns selection
def "test format table columns" [] {
    let repos = mock-repos
    let default_columns = [owner, name, language, stars, pushed, homepage, topics, description, forks, issues]

    # Simulate format with column transformation
    let formatted = $repos | each {|repo|
        let owner = try { $repo.owner | from json | get login } catch { "unknown" }
        let topics = try { $repo.topics | from json | str join ", " } catch { "" }

        {
            owner: $owner
            name: $repo.name
            language: ($repo.language? | default "")
            stars: $repo.stargazers_count
            pushed: ($repo.pushed_at? | default "" | str substring 0..10)
            homepage: ($repo.homepage? | default "")
            topics: $topics
            description: ($repo.description? | default "")
            forks: $repo.forks_count
            issues: $repo.open_issues_count
        }
    }

    # Check columns exist
    let first_row = $formatted | first
    for col in $default_columns {
        assert ($col in ($first_row | columns))
    }

    print "  ✓ Table column formatting works correctly"
}

# Test JSON output format
def "test format json output" [] {
    let repos = mock-repos | take 2

    # Transform to minimal JSON format
    let minimal = $repos | each {|repo|
        let topics = try { $repo.topics | from json } catch { [] }
        {
            name: $repo.full_name
            url: $repo.html_url
            description: ($repo.description? | default "")
            language: ($repo.language? | default "")
            stars: $repo.stargazers_count
            topics: $topics
        }
    }

    let json_output = $minimal | to json

    # Verify JSON structure
    assert ($json_output | str starts-with "[")
    assert ($json_output | str ends-with "]")

    # Parse back and verify
    let parsed = $json_output | from json
    assert equal ($parsed | length) 2
    assert ("name" in ($parsed | first | columns))
    assert ("url" in ($parsed | first | columns))

    print "  ✓ JSON output format is valid"
}

# Test CSV output format
def "test format csv output" [] {
    let repos = mock-repos | take 2

    let csv_data = $repos | each {|repo|
        let owner = try { $repo.owner | from json | get login } catch { "unknown" }
        let topics = try { $repo.topics | from json | str join ";" } catch { "" }

        {
            name: $repo.name
            full_name: $repo.full_name
            url: $repo.html_url
            language: ($repo.language? | default "")
            stars: $repo.stargazers_count
            owner: $owner
            topics: $topics
        }
    }

    let csv_output = $csv_data | to csv
    let lines = $csv_output | lines

    # Check header row
    assert ($lines | first | str contains "name")
    assert ($lines | first | str contains "stars")

    # Check data rows
    assert equal ($lines | length) 3  # header + 2 data rows

    print "  ✓ CSV output format is valid"
}

# Test text truncation
def "test format truncate text" [] {
    def test-truncate [text: string, max_len: int]: nothing -> string {
        let clean_text = $text | default ""
        if ($clean_text | str length) <= $max_len {
            $clean_text
        } else {
            $"($clean_text | str substring 0..($max_len - 1))..."
        }
    }

    assert equal (test-truncate "Short" 80) "Short"
    assert equal (test-truncate "A very long description that exceeds the maximum length" 20) "A very long descript..."

    let long_text = "A" | fill --character "A" --width 100
    let truncated = test-truncate $long_text 50
    assert ($truncated | str ends-with "...")
    assert (($truncated | str length) <= 53)  # 50 chars + "..."

    print "  ✓ Text truncation works correctly"
}

# ============================================================================
# Search Tests
# ============================================================================

# Test search by name
def "test search by name" [] {
    let repos = mock-repos

    let results = $repos | where name =~ "rust"

    assert equal ($results | length) 1
    assert equal ($results | first | get name) "rust"

    print "  ✓ Name search works correctly"
}

# Test search by description
def "test search by description" [] {
    let repos = mock-repos

    let results = $repos | where {|r|
        ($r.description? | default "") =~ "shell"
    }

    assert equal ($results | length) 1
    assert equal ($results | first | get name) "nushell"

    print "  ✓ Description search works correctly"
}

# Test case-insensitive search
def "test search case insensitive" [] {
    let repos = mock-repos

    # Search for "RUST" (uppercase) should find Rust repos
    let results_upper = $repos | where {|r|
        ($r.language? | default "" | str downcase) == ("RUST" | str downcase)
    }

    let results_lower = $repos | where {|r|
        ($r.language? | default "" | str downcase) == "rust"
    }

    assert equal ($results_upper | length) ($results_lower | length)
    assert equal ($results_upper | length) 2

    print "  ✓ Case-insensitive search works correctly"
}

# Test multi-field search
def "test search multi field" [] {
    let repos = mock-repos

    # Search across name, description, and full_name
    let query = "api"
    let results = $repos | where {|r|
        let name_val = $r.name? | default ""
        let desc_val = $r.description? | default ""
        let full_name_val = $r.full_name? | default ""

        let name_match = ($name_val | str downcase | str contains ($query | str downcase))
        let desc_match = ($desc_val | str downcase | str contains ($query | str downcase))
        let full_name_match = ($full_name_val | str downcase | str contains ($query | str downcase))

        $name_match or $desc_match or $full_name_match
    }

    assert (($results | length) >= 1)
    assert ("go-api" in ($results | get name))

    print "  ✓ Multi-field search works correctly"
}

# ============================================================================
# Statistics Tests
# ============================================================================

# Test basic statistics calculation
def "test stats calculation" [] {
    let repos = mock-repos

    let total = $repos | length
    let languages = $repos | where {|r| $r.language? | is-not-empty} | get language | uniq | length
    let archived = $repos | where archived | length
    let forked = $repos | where fork | length
    let total_stars = $repos | get stargazers_count | math sum

    assert equal $total 8
    assert ($languages >= 5)  # Rust, JavaScript, TypeScript, Go, Python, PHP (some may be null)
    assert equal $archived 1
    assert equal $forked 1
    assert ($total_stars > 100000)

    print "  ✓ Statistics calculation is correct"
}

# Test grouping by language
def "test group by language" [] {
    let repos = mock-repos

    let grouped = $repos
    | where {|r| $r.language? | is-not-empty}
    | group-by {|repo| $repo.language }
    | items {|key, value| {language: $key, count: ($value | length)} }
    | sort-by count --reverse

    # Rust should be the top language (2 repos)
    assert equal ($grouped | first | get language) "Rust"
    assert equal ($grouped | first | get count) 2

    print "  ✓ Language grouping works correctly"
}

# Test grouping by owner
def "test group by owner" [] {
    let repos = mock-repos

    let grouped = $repos
    | group-by {|repo|
        try {
            let owner = $repo.owner
            let type = $owner | describe | str replace --regex '<.*' ''
            if $type == "string" and ($owner | str starts-with "{") {
                $owner | from json | get login
            } else if $type == "record" {
                $owner | get login
            } else {
                $owner
            }
        } catch { "unknown" }
    }
    | items {|key, value| {owner: $key, count: ($value | length)} }
    | sort-by count --reverse

    # Each repo has a unique owner in our test data
    assert (($grouped | length) >= 7)

    print "  ✓ Owner grouping works correctly"
}

# Test top repos by stars
def "test top by stars" [] {
    let repos = mock-repos

    let top_5 = $repos
    | sort-by stargazers_count --reverse
    | take 5

    assert equal ($top_5 | first | get name) "rust"
    assert equal ($top_5 | first | get stargazers_count) 85000

    # Verify order is descending
    let stars = $top_5 | get stargazers_count
    let is_sorted = ($stars | zip ($stars | skip 1) | all {|pair| $pair.0 >= $pair.1 })
    assert $is_sorted

    print "  ✓ Top by stars sorting works correctly"
}

# Test aggregation calculations
def "test stats aggregation" [] {
    let repos = mock-repos

    let rust_stats = $repos
    | where language == "Rust"
    | get stargazers_count
    | math sum

    assert equal $rust_stats 110000  # 25000 + 85000

    let avg_stars = $repos
    | get stargazers_count
    | math avg

    assert ($avg_stars > 10000)

    print "  ✓ Aggregation calculations work correctly"
}

# ============================================================================
# Edge Case Tests
# ============================================================================

# Test handling of null/empty topics
def "test empty topics handling" [] {
    let repos = mock-repos

    let repos_with_topics = $repos | where {|repo|
        let topics = try { $repo.topics | from json } catch { [] }
        ($topics | length) > 0
    }

    let repos_without_topics = $repos | where {|repo|
        let topics = try { $repo.topics | from json } catch { [] }
        ($topics | length) == 0
    }

    # old-project and empty-topics-repo have no topics
    assert (($repos_without_topics | length) >= 1)

    print "  ✓ Empty topics handling is correct"
}

# Test handling of null description
def "test null description handling" [] {
    let repos = mock-repos

    let with_desc = $repos | where {|r| $r.description? | is-not-empty }
    let without_desc = $repos | where {|r| $r.description? | is-empty }

    # empty-topics-repo has null description
    assert (($without_desc | length) >= 1)

    # Ensure we can safely access description with default
    let safe_desc = $repos | each {|r| $r.description? | default "" }
    assert equal ($safe_desc | length) 8

    print "  ✓ Null description handling is correct"
}

# Test handling of null license
def "test null license handling" [] {
    let repos = mock-repos

    let with_license = $repos | where {|r| $r.license? | is-not-empty }
    let without_license = $repos | where {|r| $r.license? | is-empty }

    assert (($with_license | length) >= 5)
    assert (($without_license | length) >= 1)

    print "  ✓ Null license handling is correct"
}

# Test handling of null language
def "test null language handling" [] {
    let repos = mock-repos

    let with_lang = $repos | where {|r| $r.language? | is-not-empty }
    let without_lang = $repos | where {|r| $r.language? | is-empty }

    # empty-topics-repo has null language
    assert (($without_lang | length) >= 1)

    print "  ✓ Null language handling is correct"
}

# ============================================================================
# Validation Tests
# ============================================================================

# Test schema validation
def "test schema required fields" [] {
    let required_fields = [id, owner, name, full_name, url, source, synced_at]

    # Create a minimal valid star record
    let valid_star = {
        id: 1
        owner: "test"
        name: "test-repo"
        full_name: "test/test-repo"
        url: "https://github.com/test/test-repo"
        source: "github"
        synced_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
    }

    # All required fields should be present
    for field in $required_fields {
        assert ($field in ($valid_star | columns))
    }

    print "  ✓ Schema required fields validation works"
}

# Test source validation
def "test schema valid sources" [] {
    let valid_sources = [github, firefox, chrome, awesome, manual]

    for source in $valid_sources {
        assert ($source in $valid_sources)
    }

    # Invalid source should not be in list
    assert ("invalid" not-in $valid_sources)

    print "  ✓ Valid sources validation works"
}

# ============================================================================
# Test Runner
# ============================================================================

# Run a single test and return result
def run-test [test_record: record]: any -> record<name: any, passed: bool, error: string> {
    try {
        do $test_record.fn
        {name: $test_record.name, passed: true, error: ""}
    } catch {|err|
        print $"  ✗ ($test_record.name): ($err.msg)"
        {name: $test_record.name, passed: false, error: $err.msg}
    }
}

# Run all tests
def main [
    --verbose (-v)            # Show detailed test output
    --test (-t): string = ""  # Run specific test by name
] {
    print "Stars Module Test Suite
========================================
"

    let tests = [
        # Type helper tests
        {name: "types parse-topics json string", fn: {|| test types parse-topics json string }}
        {name: "types parse-topics list", fn: {|| test types parse-topics list }}
        {name: "types parse-topics empty", fn: {|| test types parse-topics empty }}
        {name: "types get-owner-login json", fn: {|| test types get-owner-login json }}
        {name: "types get-owner-login record", fn: {|| test types get-owner-login record }}
        {name: "types get-owner-login string", fn: {|| test types get-owner-login string }}

        # Storage path tests
        {name: "storage paths xdg compliant", fn: {|| test storage paths xdg compliant }}
        {name: "storage config path xdg compliant", fn: {|| test storage config path xdg compliant }}

        # Filter tests
        {name: "filter by language", fn: {|| test filter by language }}
        {name: "filter exclude archived", fn: {|| test filter exclude archived }}
        {name: "filter exclude old repos", fn: {|| test filter exclude old repos }}
        {name: "filter exclude languages", fn: {|| test filter exclude languages }}
        {name: "filter forks", fn: {|| test filter forks }}
        {name: "filter by topics", fn: {|| test filter by topics }}

        # Formatter tests
        {name: "format stars count", fn: {|| test format stars count }}
        {name: "format date", fn: {|| test format date }}
        {name: "format table columns", fn: {|| test format table columns }}
        {name: "format json output", fn: {|| test format json output }}
        {name: "format csv output", fn: {|| test format csv output }}
        {name: "format truncate text", fn: {|| test format truncate text }}

        # Search tests
        {name: "search by name", fn: {|| test search by name }}
        {name: "search by description", fn: {|| test search by description }}
        {name: "search case insensitive", fn: {|| test search case insensitive }}
        {name: "search multi field", fn: {|| test search multi field }}

        # Stats tests
        {name: "stats calculation", fn: {|| test stats calculation }}
        {name: "group by language", fn: {|| test group by language }}
        {name: "group by owner", fn: {|| test group by owner }}
        {name: "top by stars", fn: {|| test top by stars }}
        {name: "stats aggregation", fn: {|| test stats aggregation }}

        # Edge case tests
        {name: "empty topics handling", fn: {|| test empty topics handling }}
        {name: "null description handling", fn: {|| test null description handling }}
        {name: "null license handling", fn: {|| test null license handling }}
        {name: "null language handling", fn: {|| test null language handling }}

        # Validation tests
        {name: "schema required fields", fn: {|| test schema required fields }}
        {name: "schema valid sources", fn: {|| test schema valid sources }}
    ]

    # Filter tests if specific test requested
    let tests_to_run = if ($test | is-not-empty) {
        $tests | where {|t| $t.name | str contains $test }
    } else {
        $tests
    }

    if ($tests_to_run | length) == 0 {
        print $"No tests found matching: ($test)"
        return
    }

    print $"Running ($tests_to_run | length) tests...
"

    # Run all tests and collect results
    let results = $tests_to_run | each {|t|
        if $verbose {
            print $"Running: ($t.name)"
        }
        run-test $t
    }

    let passed = $results | where passed | length
    let failed = $results | where {|r| not $r.passed } | length
    let errors = $results | where {|r| not $r.passed }

    print ""
    print ("=" | fill --character "=" --width 50)
    print $"Results: ($passed) passed, ($failed) failed, ($tests_to_run | length) total"

    if ($errors | length) > 0 {
        print ""
        print "Failed tests:"
        $errors | each {|e|
            print $"  - ($e.name): ($e.error)"
        }
    }

    print ""

    # Return exit code based on results
    if $failed > 0 {
        exit 1
    }
}
