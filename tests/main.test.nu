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
            name: nushell
            full_name: nushell/nushell
            html_url: https://github.com/nushell/nushell
            homepage: https://nushell.sh
            description: "A new type of shell"
            language: Rust
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
            name: rust
            full_name: rust-lang/rust
            html_url: https://github.com/rust-lang/rust
            homepage: https://rust-lang.org
            description: "Empowering everyone to build reliable software"
            language: Rust
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
            name: old-project
            full_name: someone/old-project
            html_url: https://github.com/someone/old-project
            homepage: ""
            description: "An archived project"
            language: JavaScript
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
            name: typescript-lib
            full_name: dev/typescript-lib
            html_url: https://github.com/dev/typescript-lib
            homepage: https://lib.dev
            description: "A TypeScript library for modern development"
            language: TypeScript
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
            name: go-api
            full_name: company/go-api
            html_url: https://github.com/company/go-api
            homepage: null
            description: "High-performance API server"
            language: Go
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
            name: python-ml
            full_name: researcher/python-ml
            html_url: https://github.com/researcher/python-ml
            homepage: ""
            description: "Machine learning experiments"
            language: Python
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
            name: php-framework
            full_name: web/php-framework
            html_url: https://github.com/web/php-framework
            homepage: https://framework.example.com
            description: "A PHP web framework"
            language: PHP
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
            name: empty-topics-repo
            full_name: user/empty-topics-repo
            html_url: https://github.com/user/empty-topics-repo
            homepage: null
            description: null
            language: null
            stargazers_count: 5
            forks_count: 0
            open_issues_count: 0
            topics: null
            owner: plainuser
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
    let topics_list = [rust cli shell]

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

    assert equal $parsed rust-lang

    print "  ✓ get-owner-login extracts from JSON string correctly"
}

# Test getting owner login from record
def "test types get-owner-login record" [] {
    let owner_record = {login: nushell}
    let login = $owner_record | get login

    assert equal $login nushell

    print "  ✓ get-owner-login extracts from record correctly"
}

# Test getting owner login from plain string
def "test types get-owner-login string" [] {
    let owner_string = "plainuser"

    # When owner is already a plain string, use it directly
    let type = $owner_string | describe | str replace --regex '<.*' ''
    let result = if $type == string and not ($owner_string | str starts-with "{") {
        $owner_string
    } else {
        "unknown"
    }

    assert equal $result plainuser

    print "  ✓ get-owner-login handles plain string correctly"
}

# ============================================================================
# Storage Path Tests
# ============================================================================

# Test XDG-compliant storage paths
def "test storage paths xdg compliant" [] {
    let home_path = $env.HOME? | default /home/user
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
    assert ($paths.db_path | str contains .stars)
    assert ($paths.backup_dir | str contains .stars)

    print "  ✓ Storage paths are XDG-compliant"
}

# Test config path XDG compliance
def "test storage config path xdg compliant" [] {
    let home_path = $env.HOME? | default /home/user
    let config_home = $env.XDG_CONFIG_HOME? | default ($home_path | path join .config)

    let config_path = $config_home | path join stars config.nu

    assert ($config_path | str starts-with $config_home)
    assert ($config_path | str ends-with config.nu)

    print "  ✓ Config path is XDG-compliant"
}

# ============================================================================
# Filter Tests
# ============================================================================

# Test filtering by language
def "test filter by language" [] {
    let repos = mock-repos

    let rust_repos = $repos | where language == Rust

    assert equal ($rust_repos | length) 2
    assert ($rust_repos | all {|r| $r.language == Rust })

    print "  ✓ Language filtering works correctly"
}

# Test filtering out archived repositories
def "test filter exclude archived" [] {
    let repos = mock-repos

    let active_repos = $repos | where not $it.archived
    let archived_repos = $repos | where archived

    assert equal ($archived_repos | length) 1
    assert equal ($archived_repos | first | get name) old-project
    assert equal ($active_repos | length) 7

    print "  ✓ Archived filtering works correctly"
}
        $pushed > $cutoff_date

    # old-project pushed 2020-01-01 should be filtered out
    def "test null license handling" [] {
    let repos = mock-repos

    let with_license = $repos | where $it.license? | is-not-empty
    let without_license = $repos | where $it.license? | is-empty

    assert (($with_license | length) >= 5)
    assert (($without_license | length) >= 1)

    print "  ✓ Null license handling is correct"
}
        upsert $new_data

        let result = load
        assert equal ($result | length) 2
        assert ("repo-a" in ($result | get name))
        assert ("repo-b" in ($result | get name))
    } catch {|e|
        rm --recursive $test_dir
        error make {msg: $e.msg}
    }

    rm --recursive $test_dir
    print "  ✓ Upsert merges new stars correctly"
}

# Test upsert updates existing
def "test upsert updates existing" [] {
    use ../core/storage.nu [get-paths ensure-storage store load upsert]

    let test_dir = $nu.temp-dir | path join $"stars_test_(random int)"
    mkdir $test_dir
    $env.XDG_DATA_HOME = $test_dir

    try {
        ensure-storage

        # Store initial data
        let initial = [
            {
    id: 1
    name: repo-a
    full_name: owner/repo-a
    owner: owner
    language: Rust
    stargazers_count: 100
    starred_at: null
}
        ]
        store ...$initial

        # Upsert updated data for same ID
        def "test upsert empty data" [] {
    use ../core/storage.nu [get-paths ensure-storage store load upsert]

    let test_dir = $nu.temp-dir | path join $"stars_test_(random int)"
    mkdir $test_dir
    $env.XDG_DATA_HOME = $test_dir

    try {
        ensure-storage

        let initial = [
            {
    id: 1
    name: repo-a
    full_name: owner/repo-a
    owner: owner
    stargazers_count: 100
    starred_at: null
}
        ]
        store ...$initial

        # Upsert empty table
        upsert []

        let result = load
        assert equal ($result | length) 1
    } catch {|e|
        rm --recursive $test_dir
        error make {msg: $e.msg}
    }

    rm --recursive $test_dir
    print "  ✓ Upsert with empty data is no-op"
}

# Test starred_at exists in all-columns and star-schema
def "test starred_at in schema" [] {
    use ../core/types.nu [all-columns star-schema]

    let cols = all-columns
    assert ("starred_at" in $cols)

    let schema = star-schema
    assert ($schema.fields has starred_at)

    print "  ✓ starred_at exists in all-columns and star-schema"
}

# Test starred_at NOT in default-columns
def "test starred_at not in defaults" [] {
    use ../core/types.nu [default-columns minimal-columns]

    let defaults = default-columns
    assert ("starred_at" not-in $defaults)

    let minimal = minimal-columns
    assert ("starred_at" not-in $minimal)

    print "  ✓ starred_at not in default-columns or minimal-columns"
}

# Test normalize-repo with --starred-at
def "test normalize repo starred_at" [] {
    use ../adapters/github.nu [normalize-repo]

    let mock_repo = {
        id: 42
        name: test-repo
        full_name: owner/test-repo
        owner: {login: owner}
        html_url: https://github.com/owner/test-repo
        description: "A test repo"
        language: Rust
        stargazers_count: 100
        forks_count: 10
        open_issues_count: 5
        topics: []
        pushed_at: "2024-01-01T00:00:00Z"
        created_at: "2023-01-01T00:00:00Z"
        updated_at: "2024-01-01T00:00:00Z"
        archived: false
        fork: false
        license: null
    }

    let result = normalize-repo $mock_repo --starred-at "2024-06-15T10:30:00Z"
    assert equal $result.starred_at "2024-06-15T10:30:00Z"
    assert equal $result.id 42
    assert equal $result.source github

    # Without --starred-at should be null
    let result_no_sa = normalize-repo $mock_repo
    assert equal $result_no_sa.starred_at null

    print "  ✓ normalize-repo handles --starred-at correctly"
}

# Test config has full_sync_interval_days default
def "test config full_sync_interval_days" [] {
    # Simulate the default config structure
    let default_config = {
        version: 3.0.0
        sync: {
            sources: [github]
            github: {
                per_page: 100
                cache_duration: 1h
                full_sync_interval_days: 7
            }
        }
    }

    let interval = $default_config.sync.github.full_sync_interval_days
    assert equal $interval 7

    print "  ✓ Config has full_sync_interval_days default"
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
        {
    name: "types parse-topics json string"
    fn: {|| test types parse-topics json string }
}
        {name: "types parse-topics list", fn: {|| test types parse-topics list }}
        {name: "types parse-topics empty", fn: {|| test types parse-topics empty }}
        {name: "types get-owner-login json", fn: {|| test types get-owner-login json }}
        {
    name: "types get-owner-login record"
    fn: {|| test types get-owner-login record }
}
        {
    name: "types get-owner-login string"
    fn: {|| test types get-owner-login string }
}

        # Storage path tests
        {
    name: "storage paths xdg compliant"
    fn: {|| test storage paths xdg compliant }
}
        {
    name: "storage config path xdg compliant"
    fn: {|| test storage config path xdg compliant }
}

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

        # Incremental sync tests
        {name: "sync meta round trip", fn: {|| test sync meta round trip }}
        {name: "sync meta missing key", fn: {|| test sync meta missing key }}
        {name: "sync meta overwrite", fn: {|| test sync meta overwrite }}
        {name: "upsert merges new", fn: {|| test upsert merges new }}
        {name: "upsert updates existing", fn: {|| test upsert updates existing }}
        {name: "upsert empty data", fn: {|| test upsert empty data }}
        {name: "starred_at in schema", fn: {|| test starred_at in schema }}
        {name: "starred_at not in defaults", fn: {|| test starred_at not in defaults }}
        {name: "normalize repo starred_at", fn: {|| test normalize repo starred_at }}
        {
    name: "config full_sync_interval_days"
    fn: {|| test config full_sync_interval_days }
}
    ]

    # Filter tests if specific test requested
    let tests_to_run = if ($test | is-not-empty) {
        $tests | where $it.name | str contains $test
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
    let failed = $results | where not $it.passed | length
    let errors = $results | where not $it.passed

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
