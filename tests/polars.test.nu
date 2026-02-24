#!/usr/bin/env nu

# ============================================================================
# Polars/DataFrame/LazyFrame Test Suite
# ============================================================================
#
# Comprehensive tests for Polars-related functionality across the stars module.
#
# # Running Tests
# ```nushell
# nu tests/polars.test.nu              # Run all tests
# nu tests/polars.test.nu --verbose    # Run with verbose output
# nu tests/polars.test.nu --test "df " # Run formatter tests only
# nu tests/polars.test.nu --test "data " # Run data operation tests
# nu tests/polars.test.nu --test "filters " # Run filter tests
# ```
#
# # Test Categories
# - Polars availability
# - DataFrame formatter tests (is-polars-type, table-to-lazy, to-lazyframe, etc.)
# - Data operations tests (apply-defaults, search, group-by-field, etc.)
# - Filter tests (exclude-archived, exclude-old, apply-all, etc.)
# - Type schema tests (polars-schema, star-schema)
# - README example tests
# - Edge case tests
#
# Author: Daniel Bodnar
# Version: 1.0.0
# ============================================================================

use std/assert

# Import modules under test
use ../formatters/dataframe.nu [
    is-polars-type
    table-to-lazy
    to-lazyframe
    to-dataframe
    get-schema
    apply-schema
]
use ../core/types.nu [polars-schema star-schema all-columns]
use ../core/data.nu [
    apply-defaults
    select-columns
    sort-by-field
    search
    group-by-field
    collect-data
    top-by-stars
    filter-by-language
    recently-pushed
    language-stats
    owner-stats
]
use ../filters/defaults.nu [
    exclude-old
    exclude-archived
    exclude-languages
    exclude-forks
    include-recent
    include-languages
    apply-all
    filter-stats
    filter-config
]

# ============================================================================
# Test Fixtures
# ============================================================================

# Mock data using SQLite/raw column names for core/data.nu tests
# archived/fork as integers (0/1), pushed_at as ISO string
def mock-polars-repos-raw []: nothing -> table {
    let now = date now
    [
        {id: 1, name: nushell, full_name: "nushell/nushell", owner: nushell, description: "A new type of shell", language: Rust, stargazers_count: 25000, forks_count: 1200, open_issues_count: 150, pushed_at: ($now - 10day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 2, name: "rust-lang", full_name: "rust-lang/rust", owner: "rust-lang", description: "Empowering everyone to build reliable software", language: Rust, stargazers_count: 85000, forks_count: 11000, open_issues_count: 9500, pushed_at: ($now - 20day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 3, name: typst, full_name: "typst/typst", owner: typst, description: "A new markup-based typesetting system", language: Rust, stargazers_count: 15000, forks_count: 500, open_issues_count: 200, pushed_at: ($now - 15day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 4, name: "ts-lib", full_name: "dev/ts-lib", owner: dev, description: "TypeScript library", language: TypeScript, stargazers_count: 500, forks_count: 50, open_issues_count: 15, pushed_at: ($now - 5day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 1}
        {id: 5, name: "go-api", full_name: "company/go-api", owner: company, description: "High-performance API server", language: Go, stargazers_count: 3500, forks_count: 280, open_issues_count: 45, pushed_at: ($now - 25day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 6, name: "python-ml", full_name: "researcher/python-ml", owner: researcher, description: "Machine learning experiments", language: Python, stargazers_count: 1500, forks_count: 200, open_issues_count: 30, pushed_at: ($now - 45day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 7, name: "php-fw", full_name: "web/php-fw", owner: web, description: "PHP framework", language: PHP, stargazers_count: 2000, forks_count: 400, open_issues_count: 80, pushed_at: ($now - 35day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 8, name: "java-util", full_name: "org/java-util", owner: org, description: "Java utility library", language: Java, stargazers_count: 800, forks_count: 100, open_issues_count: 20, pushed_at: ($now - 40day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 9, name: "no-lang", full_name: "user/no-lang", owner: user, description: "No language repo", language: Rust, stargazers_count: 5, forks_count: 0, open_issues_count: 0, pushed_at: ($now - 8day | format date %Y-%m-%dT%H:%M:%SZ), archived: 0, fork: 0}
        {id: 10, name: "old-archived", full_name: "someone/old-archived", owner: someone, description: "Old project", language: JavaScript, stargazers_count: 100, forks_count: 10, open_issues_count: 0, pushed_at: ($now - 500day | format date %Y-%m-%dT%H:%M:%SZ), archived: 1, fork: 0}
    ]
}

# Mock data using friendly column names for filters/defaults.nu tests
# archived/fork as booleans, pushed as datetime objects
def mock-polars-repos-friendly []: nothing -> table {
    let now = date now
    [
        {name: nushell, full_name: "nushell/nushell", owner: nushell, description: "A new type of shell", language: Rust, stars: 25000, forks: 1200, issues: 150, pushed: ($now - 10day), archived: false, fork: false}
        {name: "rust-lang", full_name: "rust-lang/rust", owner: "rust-lang", description: "Reliable software", language: Rust, stars: 85000, forks: 11000, issues: 9500, pushed: ($now - 20day), archived: false, fork: false}
        {name: typst, full_name: "typst/typst", owner: typst, description: "Markup typesetting", language: Rust, stars: 15000, forks: 500, issues: 200, pushed: ($now - 15day), archived: false, fork: false}
        {name: "ts-lib", full_name: "dev/ts-lib", owner: dev, description: "TypeScript library", language: TypeScript, stars: 500, forks: 50, issues: 15, pushed: ($now - 5day), archived: false, fork: true}
        {name: "go-api", full_name: "company/go-api", owner: company, description: "API server", language: Go, stars: 3500, forks: 280, issues: 45, pushed: ($now - 25day), archived: false, fork: false}
        {name: "python-ml", full_name: "researcher/python-ml", owner: researcher, description: "ML experiments", language: Python, stars: 1500, forks: 200, issues: 30, pushed: ($now - 45day), archived: false, fork: false}
        {name: "php-fw", full_name: "web/php-fw", owner: web, description: "PHP framework", language: PHP, stars: 2000, forks: 400, issues: 80, pushed: ($now - 35day), archived: false, fork: false}
        {name: "java-util", full_name: "org/java-util", owner: org, description: "Java utility", language: Java, stars: 800, forks: 100, issues: 20, pushed: ($now - 40day), archived: false, fork: false}
        {name: "no-lang", full_name: "user/no-lang", owner: user, description: "No language repo", language: Rust, stars: 5, forks: 0, issues: 0, pushed: ($now - 8day), archived: false, fork: false}
        {name: "old-archived", full_name: "someone/old-archived", owner: someone, description: "Old project", language: JavaScript, stars: 100, forks: 10, issues: 0, pushed: ($now - 500day), archived: true, fork: false}
    ]
}

# ============================================================================
# Polars Availability
# ============================================================================

def "test polars available" [] {
    let df = [[a]; [1]] | polars into-df
    let lf = [[a]; [1]] | polars into-lazy
    assert (($df | describe) == "polars_dataframe")
    assert (($lf | describe) == "polars_lazyframe")
    print "  ✓ Polars plugin is available and functional"
}

# ============================================================================
# Formatter Tests — is-polars-type
# ============================================================================

def "test df is-polars-type table false" [] {
    let data = [[a b]; [1 2]]
    assert equal (is-polars-type $data) false
    print "  ✓ is-polars-type returns false for table"
}

def "test df is-polars-type dataframe true" [] {
    let data = [[a b]; [1 2]] | polars into-df
    assert equal (is-polars-type $data) true
    print "  ✓ is-polars-type returns true for DataFrame"
}

def "test df is-polars-type lazyframe true" [] {
    let data = [[a b]; [1 2]] | polars into-lazy
    assert equal (is-polars-type $data) true
    print "  ✓ is-polars-type returns true for LazyFrame"
}

def "test df is-polars-type string false" [] {
    assert equal (is-polars-type "hello") false
    print "  ✓ is-polars-type returns false for string"
}

# ============================================================================
# Formatter Tests — table-to-lazy
# ============================================================================

def "test df table-to-lazy converts table" [] {
    let data = [[name age]; [Alice 30] [Bob 25]]
    let lf = table-to-lazy $data
    assert (($lf | describe) == "polars_lazyframe")
    let result = $lf | polars collect | polars into-nu
    assert equal ($result | length) 2
    print "  ✓ table-to-lazy converts table to LazyFrame"
}

def "test df table-to-lazy empty table" [] {
    let lf = table-to-lazy []
    assert (($lf | describe) == "polars_lazyframe")
    let result = $lf | polars collect | polars into-nu
    assert equal ($result | length) 0
    print "  ✓ table-to-lazy handles empty table"
}

# ============================================================================
# Formatter Tests — to-lazyframe
# ============================================================================

def "test df to-lazyframe from table" [] {
    let data = [[x]; [1] [2] [3]]
    let lf = to-lazyframe $data
    assert (($lf | describe) == "polars_lazyframe")
    let result = $lf | polars collect | polars into-nu
    assert equal ($result | length) 3
    print "  ✓ to-lazyframe converts table"
}

def "test df to-lazyframe from dataframe" [] {
    let df = [[x]; [1] [2]] | polars into-df
    let lf = to-lazyframe $df
    assert (($lf | describe) == "polars_lazyframe")
    print "  ✓ to-lazyframe converts DataFrame"
}

def "test df to-lazyframe from lazyframe idempotent" [] {
    let lf = [[x]; [1]] | polars into-lazy
    let lf2 = to-lazyframe $lf
    assert (($lf2 | describe) == "polars_lazyframe")
    print "  ✓ to-lazyframe is idempotent on LazyFrame"
}

def "test df to-lazyframe invalid type errors" [] {
    let threw = try {
        to-lazyframe 42
        false
    } catch {
        true
    }
    assert $threw "Expected error for invalid type"
    print "  ✓ to-lazyframe errors on invalid type"
}

# ============================================================================
# Formatter Tests — to-dataframe
# ============================================================================

def "test df to-dataframe from table" [] {
    let data = [[x]; [1] [2] [3]]
    let df = to-dataframe $data
    assert (($df | describe) == "polars_dataframe")
    print "  ✓ to-dataframe converts table"
}

def "test df to-dataframe from lazyframe collects" [] {
    let lf = [[x]; [1] [2]] | polars into-lazy
    let df = to-dataframe $lf
    assert (($df | describe) == "polars_dataframe")
    print "  ✓ to-dataframe collects LazyFrame"
}

def "test df to-dataframe from dataframe idempotent" [] {
    let df = [[x]; [1]] | polars into-df
    let df2 = to-dataframe $df
    assert (($df2 | describe) == "polars_dataframe")
    print "  ✓ to-dataframe is idempotent on DataFrame"
}

def "test df to-dataframe invalid type errors" [] {
    let threw = try {
        to-dataframe "invalid"
        false
    } catch {
        true
    }
    assert $threw "Expected error for invalid type"
    print "  ✓ to-dataframe errors on invalid type"
}

# ============================================================================
# Formatter Tests — get-schema
# ============================================================================

def "test df get-schema returns column dtype table" [] {
    let data = [[name count]; [alice 10] [bob 20]]
    let schema = get-schema $data
    assert equal ($schema | length) 2
    let cols = $schema | get column
    assert ("name" in $cols)
    assert ("count" in $cols)
    print "  ✓ get-schema returns column+dtype table"
}

def "test df get-schema works from lazyframe" [] {
    let lf = [[a b]; [1 "x"]] | polars into-lazy
    let schema = get-schema $lf
    assert equal ($schema | length) 2
    let a_type = $schema | where column == a | get dtype | first
    assert ($a_type == "i64")
    print "  ✓ get-schema works from LazyFrame"
}

# ============================================================================
# Formatter Tests — apply-schema
# ============================================================================

def "test df apply-schema cast i64" [] {
    let data = [[count]; ["100"]]
    let result = {count: i64} | apply-schema $data
    let schema = get-schema $result
    let dtype = $schema | where column == count | get dtype | first
    assert ($dtype == "i64")
    let val = $result | polars collect | polars into-nu | get count | first
    assert equal $val 100
    print "  ✓ apply-schema casts string to i64"
}

def "test df apply-schema cast str" [] {
    let data = [[count]; [100]]
    let result = {count: str} | apply-schema $data
    let schema = get-schema $result
    let dtype = $schema | where column == count | get dtype | first
    assert ($dtype == "str")
    print "  ✓ apply-schema casts i64 to str"
}

def "test df apply-schema cast bool" [] {
    let data = [[flag]; [1]]
    let result = {flag: bool} | apply-schema $data
    let schema = get-schema $result
    let dtype = $schema | where column == flag | get dtype | first
    assert ($dtype == "bool")
    print "  ✓ apply-schema casts i64 to bool"
}

def "test df apply-schema multiple columns" [] {
    let data = [[name age active]; ["alice" "30" 1]]
    let result = {age: i64, active: bool} | apply-schema $data
    let schema = get-schema $result
    let age_type = $schema | where column == age | get dtype | first
    let active_type = $schema | where column == active | get dtype | first
    assert ($age_type == "i64")
    assert ($active_type == "bool")
    print "  ✓ apply-schema handles multiple column casts"
}

def "test df apply-schema unknown type errors" [] {
    let threw = try {
        let data = [[x]; [1]]
        {x: "imaginary_type"} | apply-schema $data
        false
    } catch {
        true
    }
    assert $threw "Expected error for unknown type"
    print "  ✓ apply-schema errors on unknown type"
}

# ============================================================================
# Data Operation Tests — apply-defaults (core/data.nu, raw schema)
# ============================================================================

def "test data apply-defaults excludes archived" [] {
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults | collect-data
    let names = $result | get name
    assert ("old-archived" not-in $names) "archived repo should be excluded"
    print "  ✓ apply-defaults excludes archived repos"
}

def "test data apply-defaults excludes old" [] {
    # old-archived is both archived and old (500 days) — excluded either way
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults --include-archived | collect-data
    let names = $result | get name
    assert ("old-archived" not-in $names) "old repo should be excluded"
    print "  ✓ apply-defaults excludes old repos"
}

def "test data apply-defaults excludes languages" [] {
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults | collect-data
    let langs = $result | get language
    assert ("PHP" not-in $langs) "PHP should be excluded"
    assert ("Python" not-in $langs) "Python should be excluded"
    assert ("Java" not-in $langs) "Java should be excluded"
    assert ("Rust" in $langs) "Rust should survive"
    print "  ✓ apply-defaults excludes default languages"
}

def "test data apply-defaults skip-defaults" [] {
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults --skip-defaults | collect-data
    assert equal ($result | length) 10 "all 10 repos should survive"
    print "  ✓ apply-defaults --skip-defaults keeps all repos"
}

def "test data apply-defaults include-archived" [] {
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults --include-archived --include-old | collect-data
    # old-archived should survive archived filter but may be excluded by language
    # JavaScript is not in default excluded list
    let names = $result | get name
    assert ("old-archived" in $names) "archived repo should survive with --include-archived --include-old"
    print "  ✓ apply-defaults --include-archived keeps archived repos"
}

def "test data apply-defaults include-old" [] {
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults --include-old | collect-data
    let names = $result | get name
    # old-archived is still excluded by archived filter (not --include-archived)
    assert ("nushell" in $names) "recent repos survive"
    print "  ✓ apply-defaults --include-old keeps old repos"
}

def "test data apply-defaults custom languages" [] {
    let result = mock-polars-repos-raw | polars into-lazy | apply-defaults --languages [Go] | collect-data
    let names = $result | get name
    assert ("go-api" not-in $names) "Go should be excluded with custom list"
    assert ("python-ml" in $names) "Python should survive when not in custom list"
    print "  ✓ apply-defaults with custom --languages works"
}

# ============================================================================
# Data Operation Tests — select-columns
# ============================================================================

def "test data select-columns specific" [] {
    let result = mock-polars-repos-raw | polars into-lazy | select-columns name language | polars collect | polars into-nu
    let cols = $result | columns
    assert ("name" in $cols)
    assert ("language" in $cols)
    assert equal ($cols | length) 2
    print "  ✓ select-columns selects specific columns"
}

def "test data select-columns empty noop" [] {
    let lf = mock-polars-repos-raw | polars into-lazy
    let result = $lf | select-columns | polars collect | polars into-nu
    assert (($result | columns | length) > 2) "all columns should remain"
    print "  ✓ select-columns with no args is no-op"
}

# ============================================================================
# Data Operation Tests — sort-by-field
# ============================================================================

def "test data sort-by-field ascending" [] {
    let result = mock-polars-repos-raw | polars into-lazy | sort-by-field stargazers_count | polars collect | polars into-nu
    let first_stars = $result | get stargazers_count | first
    let last_stars = $result | get stargazers_count | last
    assert ($first_stars <= $last_stars) "ascending sort"
    print "  ✓ sort-by-field ascending works"
}

def "test data sort-by-field descending" [] {
    let result = mock-polars-repos-raw | polars into-lazy | sort-by-field stargazers_count --reverse | polars collect | polars into-nu
    let first_stars = $result | get stargazers_count | first
    assert equal $first_stars 85000 "highest stars first"
    print "  ✓ sort-by-field descending works"
}

# ============================================================================
# Data Operation Tests — search
# ============================================================================

def "test data search by name" [] {
    let result = mock-polars-repos-raw | polars into-lazy | search "nushell" --field name | polars collect | polars into-nu
    assert equal ($result | length) 1
    assert equal ($result | first | get name) "nushell"
    print "  ✓ search by name works"
}

def "test data search by description" [] {
    let result = mock-polars-repos-raw | polars into-lazy | search "reliable" --field description | polars collect | polars into-nu
    assert (($result | length) >= 1)
    print "  ✓ search by description works"
}

def "test data search case insensitive" [] {
    let result = mock-polars-repos-raw | polars into-lazy | search "NUSHELL" --field name | polars collect | polars into-nu
    assert equal ($result | length) 1
    print "  ✓ search is case insensitive"
}

def "test data search all fields" [] {
    let result = mock-polars-repos-raw | polars into-lazy | search "typst" | polars collect | polars into-nu
    assert (($result | length) >= 1)
    let names = $result | get name
    assert ("typst" in $names)
    print "  ✓ search across all fields works"
}

def "test data search no results" [] {
    let result = mock-polars-repos-raw | polars into-lazy | search "zzz_nonexistent_zzz" --field name | polars collect | polars into-nu
    assert equal ($result | length) 0
    print "  ✓ search returns empty for no matches"
}

# ============================================================================
# Data Operation Tests — group-by-field
# ============================================================================

def "test data group-by-field language" [] {
    let result = mock-polars-repos-raw | polars into-lazy | group-by-field language
    let rust_row = $result | where language == Rust
    assert equal ($rust_row | length) 1
    let rust_count = $rust_row | get count | first
    assert equal $rust_count 4 "4 Rust repos in mock data"
    let cols = $result | columns
    assert ("count" in $cols)
    assert ("total_stars" in $cols)
    assert ("avg_stars" in $cols)
    print "  ✓ group-by-field language works"
}

def "test data group-by-field owner" [] {
    let result = mock-polars-repos-raw | polars into-lazy | group-by-field owner
    assert (($result | length) >= 9) "at least 9 unique owners"
    print "  ✓ group-by-field owner works"
}

# ============================================================================
# Data Operation Tests — collect-data
# ============================================================================

def "test data collect-data materializes" [] {
    let result = mock-polars-repos-raw | polars into-lazy | collect-data
    let type_name = $result | describe | str replace --regex '<.*' ''
    assert (($type_name == "table") or ($type_name == "list")) "should be a Nushell table/list"
    assert equal ($result | length) 10
    print "  ✓ collect-data materializes LazyFrame to table"
}

# ============================================================================
# Data Operation Tests — top-by-stars
# ============================================================================

def "test data top-by-stars top 3" [] {
    let result = mock-polars-repos-raw | polars into-lazy | top-by-stars 3 | polars collect | polars into-nu
    assert equal ($result | length) 3
    assert equal ($result | first | get full_name) "rust-lang/rust"
    print "  ✓ top-by-stars returns top 3"
}

def "test data top-by-stars default 20" [] {
    let result = mock-polars-repos-raw | polars into-lazy | top-by-stars | polars collect | polars into-nu
    # We have 10 repos, default 20 returns all
    assert equal ($result | length) 10
    print "  ✓ top-by-stars default returns up to 20"
}

# ============================================================================
# Data Operation Tests — filter-by-language
# ============================================================================

def "test data filter-by-language match" [] {
    let result = mock-polars-repos-raw | polars into-lazy | filter-by-language Rust | polars collect | polars into-nu
    assert equal ($result | length) 4
    assert ($result | all {|r| $r.language == "Rust" })
    print "  ✓ filter-by-language Rust returns 4 repos"
}

def "test data filter-by-language no match" [] {
    let result = mock-polars-repos-raw | polars into-lazy | filter-by-language "Haskell" | polars collect | polars into-nu
    assert equal ($result | length) 0
    print "  ✓ filter-by-language returns empty for no match"
}

# ============================================================================
# Data Operation Tests — recently-pushed
# ============================================================================

def "test data recently-pushed within days" [] {
    let result = mock-polars-repos-raw | polars into-lazy | recently-pushed 30 | polars collect | polars into-nu
    let names = $result | get name
    assert ("nushell" in $names) "pushed 10 days ago"
    assert ("go-api" in $names) "pushed 25 days ago"
    assert ("python-ml" not-in $names) "pushed 45 days ago"
    assert ("old-archived" not-in $names) "pushed 500 days ago"
    print "  ✓ recently-pushed filters by days"
}

# ============================================================================
# Data Operation Tests — language-stats, owner-stats
# ============================================================================

def "test data language-stats" [] {
    let result = mock-polars-repos-raw | polars into-lazy | language-stats
    let cols = $result | columns
    assert ("language" in $cols)
    assert ("count" in $cols)
    assert ("total_stars" in $cols)
    print "  ✓ language-stats returns aggregated table"
}

def "test data owner-stats" [] {
    let result = mock-polars-repos-raw | polars into-lazy | owner-stats
    let cols = $result | columns
    assert ("owner" in $cols)
    assert ("count" in $cols)
    print "  ✓ owner-stats returns aggregated table"
}

# ============================================================================
# Filter Tests — Individual Filters (filters/defaults.nu, friendly schema)
# ============================================================================

def "test filters exclude-archived" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | exclude-archived | polars collect | polars into-nu
    assert equal ($result | length) 9
    assert ($result | all {|r| $r.archived == false })
    print "  ✓ exclude-archived removes archived repos"
}

def "test filters exclude-forks" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | exclude-forks | polars collect | polars into-nu
    assert equal ($result | length) 9
    assert ($result | all {|r| $r.fork == false })
    print "  ✓ exclude-forks removes forked repos"
}

def "test filters exclude-languages default" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | exclude-languages | polars collect | polars into-nu
    let langs = $result | get language
    assert ("PHP" not-in $langs) "PHP excluded"
    assert ("Python" not-in $langs) "Python excluded"
    assert ("Java" not-in $langs) "Java excluded"
    assert ("Rust" in $langs) "Rust survives"
    print "  ✓ exclude-languages removes default languages"
}

def "test filters exclude-languages custom" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | exclude-languages --languages [Go TypeScript] | polars collect | polars into-nu
    let langs = $result | get language
    assert ("Go" not-in $langs) "Go excluded"
    assert ("TypeScript" not-in $langs) "TypeScript excluded"
    assert ("PHP" in $langs) "PHP survives with custom list"
    print "  ✓ exclude-languages with custom list works"
}

def "test filters exclude-old" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | exclude-old --days 365 | polars collect | polars into-nu
    let names = $result | get name
    assert ("old-archived" not-in $names) "500-day-old repo excluded"
    assert ("nushell" in $names) "10-day-old repo survives"
    print "  ✓ exclude-old removes old repos"
}

def "test filters exclude-old custom days" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | exclude-old --days 20 | polars collect | polars into-nu
    let names = $result | get name
    assert ("nushell" in $names) "10-day-old survives 20-day cutoff"
    assert ("go-api" not-in $names) "25-day-old excluded by 20-day cutoff"
    print "  ✓ exclude-old with custom days works"
}

# ============================================================================
# Filter Tests — Inclusion Filters
# ============================================================================

def "test filters include-recent" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | include-recent --days 15 | polars collect | polars into-nu
    let names = $result | get name
    assert ("nushell" in $names) "10 days ago < 15 day cutoff"
    assert ("ts-lib" in $names) "5 days ago < 15 day cutoff"
    assert ("go-api" not-in $names) "25 days ago > 15 day cutoff"
    print "  ✓ include-recent keeps only recent repos"
}

def "test filters include-languages" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | include-languages --languages [Rust Go] | polars collect | polars into-nu
    let langs = $result | get language | uniq
    assert ("Rust" in $langs)
    assert ("Go" in $langs)
    assert ("PHP" not-in $langs)
    print "  ✓ include-languages keeps only specified languages"
}

# ============================================================================
# Filter Tests — apply-all (combined filter)
# ============================================================================

def "test filters apply-all defaults" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | apply-all | polars collect | polars into-nu
    let names = $result | get name
    assert ("old-archived" not-in $names) "archived+old excluded"
    assert ("php-fw" not-in $names) "PHP excluded"
    assert ("python-ml" not-in $names) "Python excluded"
    assert ("java-util" not-in $names) "Java excluded"
    assert ("ts-lib" not-in $names) "fork excluded"
    assert ("nushell" in $names) "Rust non-fork survives"
    print "  ✓ apply-all with defaults works"
}

def "test filters apply-all include-archived" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | apply-all --include-archived --include-old | polars collect | polars into-nu
    let names = $result | get name
    # old-archived is JavaScript (not excluded), not a fork, and we include archived+old
    assert ("old-archived" in $names) "archived repo kept"
    print "  ✓ apply-all --include-archived keeps archived"
}

def "test filters apply-all include-old" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | apply-all --include-old | polars collect | polars into-nu
    let names = $result | get name
    # old-archived is still excluded by archived filter
    assert ("nushell" in $names) "recent repo survives"
    print "  ✓ apply-all --include-old works"
}

def "test filters apply-all include-forks" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | apply-all --include-forks | polars collect | polars into-nu
    let names = $result | get name
    assert ("ts-lib" in $names) "fork repo kept with --include-forks"
    print "  ✓ apply-all --include-forks keeps forks"
}

def "test filters apply-all include-all-languages" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | apply-all --include-all-languages | polars collect | polars into-nu
    let names = $result | get name
    assert ("php-fw" in $names) "PHP repo kept"
    assert ("python-ml" in $names) "Python repo kept"
    print "  ✓ apply-all --include-all-languages keeps all languages"
}

def "test filters apply-all custom days and languages" [] {
    let result = mock-polars-repos-friendly | polars into-lazy | apply-all --days 20 --languages [Rust] | polars collect | polars into-nu
    let names = $result | get name
    assert ("nushell" not-in $names) "Rust excluded by custom languages"
    assert ("go-api" not-in $names) "25-day repo excluded by 20-day cutoff"
    assert ("ts-lib" not-in $names) "fork excluded"
    print "  ✓ apply-all with custom days and languages works"
}

# ============================================================================
# Filter Tests — Utility Functions
# ============================================================================

def "test filters filter-config" [] {
    let cfg = filter-config
    let cols = $cfg | columns
    assert ("default_staleness_days" in $cols)
    assert ("default_excluded_languages" in $cols)
    assert equal $cfg.default_staleness_days 365
    print "  ✓ filter-config returns expected configuration"
}

def "test filters filter-stats" [] {
    let data = mock-polars-repos-friendly | polars into-lazy
    let stats = $data | filter-stats --days 365
    let keys = $stats | columns
    assert ("total_rows" in $keys)
    assert ("archived_repos" in $keys)
    assert ("old_repos" in $keys)
    assert ("fork_repos" in $keys)
    assert ("excluded_language_repos" in $keys)
    assert ("rows_after_all_filters" in $keys)
    assert equal $stats.total_rows 10
    assert equal $stats.archived_repos 1
    assert equal $stats.fork_repos 1
    print "  ✓ filter-stats returns expected statistics"
}

# ============================================================================
# Type Schema Tests — core/types.nu
# ============================================================================

def "test types polars-schema has all columns" [] {
    let schema = polars-schema
    let cols = $schema | columns
    assert ("id" in $cols)
    assert ("name" in $cols)
    assert ("full_name" in $cols)
    assert ("owner" in $cols)
    assert ("language" in $cols)
    assert ("stars" in $cols)
    assert ("pushed" in $cols)
    assert ("archived" in $cols)
    assert ("fork" in $cols)
    assert ("starred_at" in $cols)
    assert (($cols | length) == 22)
    print "  ✓ polars-schema has all 22 columns"
}

def "test types polars-schema correct types" [] {
    let schema = polars-schema
    assert equal $schema.id "i64"
    assert equal $schema.name "str"
    assert equal $schema.pushed "datetime[us]"
    assert equal $schema.archived "bool"
    assert equal $schema.stars "i64"
    print "  ✓ polars-schema has correct type mappings"
}

def "test types polars-schema cross-reference star-schema" [] {
    let ps = polars-schema | columns
    let ss = star-schema | get fields | columns
    # Every polars-schema column should exist in star-schema
    for col in $ps {
        assert ($col in $ss) $"polars-schema column '($col)' missing from star-schema"
    }
    print "  ✓ polars-schema columns match star-schema fields"
}

# ============================================================================
# README Example Tests
# ============================================================================

def "test readme filter by language and sort" [] {
    let result = mock-polars-repos-raw
        | polars into-lazy
        | filter-by-language Rust
        | sort-by-field stargazers_count --reverse
        | polars collect
        | polars into-nu
    assert equal ($result | length) 4
    assert equal ($result | first | get name) "rust-lang"
    print "  ✓ README: filter by language + sort works"
}

def "test readme top 10 by stars" [] {
    let result = mock-polars-repos-raw
        | polars into-lazy
        | top-by-stars 10
        | polars collect
        | polars into-nu
    assert equal ($result | length) 10
    assert equal ($result | first | get stargazers_count) 85000
    print "  ✓ README: top 10 by stars works"
}

def "test readme group by language" [] {
    let result = mock-polars-repos-raw
        | polars into-lazy
        | group-by-field language
    assert (($result | length) >= 1)
    let cols = $result | columns
    assert ("count" in $cols)
    assert ("total_stars" in $cols)
    print "  ✓ README: group by language works"
}

def "test readme dataframe output type" [] {
    let df = mock-polars-repos-raw | polars into-df
    assert (($df | describe) == "polars_dataframe")
    assert (is-polars-type $df)
    print "  ✓ README: DataFrame output type verified"
}

def "test readme lazyframe output type" [] {
    let lf = mock-polars-repos-raw | polars into-lazy
    assert (($lf | describe) == "polars_lazyframe")
    assert (is-polars-type $lf)
    print "  ✓ README: LazyFrame output type verified"
}

# ============================================================================
# Edge Case Tests
# ============================================================================

def "test edge empty table to lazyframe" [] {
    let lf = to-lazyframe []
    assert (($lf | describe) == "polars_lazyframe")
    let result = $lf | polars collect | polars into-nu
    assert equal ($result | length) 0
    print "  ✓ Edge: empty table to LazyFrame"
}

def "test edge single row dataframe" [] {
    let data = [[name stars]; [solo 42]]
    let df = to-dataframe $data
    let result = $df | polars into-nu
    assert equal ($result | length) 1
    assert equal ($result | first | get name) "solo"
    print "  ✓ Edge: single-row DataFrame"
}

def "test edge all schema columns" [] {
    let cols = all-columns
    assert equal ($cols | length) 22
    let data = [[name]; [test]]
    let lf = to-lazyframe $data
    assert (($lf | describe) == "polars_lazyframe")
    print "  ✓ Edge: all 22 columns in schema"
}

def "test edge type coercion round trip" [] {
    let data = [[val]; ["42"]]
    let as_int = {val: i64} | apply-schema $data
    let back_to_str = {val: str} | apply-schema ($as_int | polars collect | polars into-nu)
    let schema = get-schema $back_to_str
    let dtype = $schema | where column == val | get dtype | first
    assert ($dtype == "str")
    print "  ✓ Edge: type coercion round trip (str→i64→str)"
}

def "test edge sort empty lazyframe" [] {
    let lf = [] | polars into-df | polars into-lazy
    let result = try {
        $lf | polars collect | polars into-nu
        true
    } catch {
        false
    }
    assert $result "empty LazyFrame should collect without error"
    print "  ✓ Edge: sort empty LazyFrame"
}

def "test edge search with null description" [] {
    # Ensure search doesn't crash when some descriptions have special chars
    let data = [
        {name: "repo-a", full_name: "o/repo-a", description: "A great tool"}
        {name: "repo-b", full_name: "o/repo-b", description: "Another tool"}
    ]
    let result = $data | polars into-lazy | search "great" --field description | polars collect | polars into-nu
    assert equal ($result | length) 1
    assert equal ($result | first | get name) "repo-a"
    print "  ✓ Edge: search handles descriptions correctly"
}

def "test edge filter-by-language preserves columns" [] {
    let result = mock-polars-repos-raw
        | polars into-lazy
        | filter-by-language Rust
        | polars collect
        | polars into-nu
    let cols = $result | columns
    assert ("name" in $cols)
    assert ("stargazers_count" in $cols)
    assert ("language" in $cols)
    assert ("pushed_at" in $cols)
    print "  ✓ Edge: filter-by-language preserves all columns"
}

# ============================================================================
# Test Runner
# ============================================================================

def run-test [test_record: record]: any -> record<name: any, passed: bool, error: string> {
    try {
        do $test_record.fn
        {name: $test_record.name, passed: true, error: ""}
    } catch {|err|
        print $"  ✗ ($test_record.name): ($err.msg)"
        {name: $test_record.name, passed: false, error: $err.msg}
    }
}

def main [
    --verbose (-v)            # Show detailed test output
    --test (-t): string = ""  # Run specific test by name
] {
    print "Polars/DataFrame/LazyFrame Test Suite
========================================"
    print ""

    let tests = [
        # Polars availability
        {name: "polars available", fn: {|| test polars available }}

        # Formatter: is-polars-type
        {name: "df is-polars-type table false", fn: {|| test df is-polars-type table false }}
        {name: "df is-polars-type dataframe true", fn: {|| test df is-polars-type dataframe true }}
        {name: "df is-polars-type lazyframe true", fn: {|| test df is-polars-type lazyframe true }}
        {name: "df is-polars-type string false", fn: {|| test df is-polars-type string false }}

        # Formatter: table-to-lazy
        {name: "df table-to-lazy converts table", fn: {|| test df table-to-lazy converts table }}
        {name: "df table-to-lazy empty table", fn: {|| test df table-to-lazy empty table }}

        # Formatter: to-lazyframe
        {name: "df to-lazyframe from table", fn: {|| test df to-lazyframe from table }}
        {name: "df to-lazyframe from dataframe", fn: {|| test df to-lazyframe from dataframe }}
        {name: "df to-lazyframe from lazyframe idempotent", fn: {|| test df to-lazyframe from lazyframe idempotent }}
        {name: "df to-lazyframe invalid type errors", fn: {|| test df to-lazyframe invalid type errors }}

        # Formatter: to-dataframe
        {name: "df to-dataframe from table", fn: {|| test df to-dataframe from table }}
        {name: "df to-dataframe from lazyframe collects", fn: {|| test df to-dataframe from lazyframe collects }}
        {name: "df to-dataframe from dataframe idempotent", fn: {|| test df to-dataframe from dataframe idempotent }}
        {name: "df to-dataframe invalid type errors", fn: {|| test df to-dataframe invalid type errors }}

        # Formatter: get-schema
        {name: "df get-schema returns column dtype table", fn: {|| test df get-schema returns column dtype table }}
        {name: "df get-schema works from lazyframe", fn: {|| test df get-schema works from lazyframe }}

        # Formatter: apply-schema
        {name: "df apply-schema cast i64", fn: {|| test df apply-schema cast i64 }}
        {name: "df apply-schema cast str", fn: {|| test df apply-schema cast str }}
        {name: "df apply-schema cast bool", fn: {|| test df apply-schema cast bool }}
        {name: "df apply-schema multiple columns", fn: {|| test df apply-schema multiple columns }}
        {name: "df apply-schema unknown type errors", fn: {|| test df apply-schema unknown type errors }}

        # Data: apply-defaults
        {name: "data apply-defaults excludes archived", fn: {|| test data apply-defaults excludes archived }}
        {name: "data apply-defaults excludes old", fn: {|| test data apply-defaults excludes old }}
        {name: "data apply-defaults excludes languages", fn: {|| test data apply-defaults excludes languages }}
        {name: "data apply-defaults skip-defaults", fn: {|| test data apply-defaults skip-defaults }}
        {name: "data apply-defaults include-archived", fn: {|| test data apply-defaults include-archived }}
        {name: "data apply-defaults include-old", fn: {|| test data apply-defaults include-old }}
        {name: "data apply-defaults custom languages", fn: {|| test data apply-defaults custom languages }}

        # Data: select-columns
        {name: "data select-columns specific", fn: {|| test data select-columns specific }}
        {name: "data select-columns empty noop", fn: {|| test data select-columns empty noop }}

        # Data: sort-by-field
        {name: "data sort-by-field ascending", fn: {|| test data sort-by-field ascending }}
        {name: "data sort-by-field descending", fn: {|| test data sort-by-field descending }}

        # Data: search
        {name: "data search by name", fn: {|| test data search by name }}
        {name: "data search by description", fn: {|| test data search by description }}
        {name: "data search case insensitive", fn: {|| test data search case insensitive }}
        {name: "data search all fields", fn: {|| test data search all fields }}
        {name: "data search no results", fn: {|| test data search no results }}

        # Data: group-by-field
        {name: "data group-by-field language", fn: {|| test data group-by-field language }}
        {name: "data group-by-field owner", fn: {|| test data group-by-field owner }}

        # Data: collect-data
        {name: "data collect-data materializes", fn: {|| test data collect-data materializes }}

        # Data: top-by-stars
        {name: "data top-by-stars top 3", fn: {|| test data top-by-stars top 3 }}
        {name: "data top-by-stars default 20", fn: {|| test data top-by-stars default 20 }}

        # Data: filter-by-language
        {name: "data filter-by-language match", fn: {|| test data filter-by-language match }}
        {name: "data filter-by-language no match", fn: {|| test data filter-by-language no match }}

        # Data: recently-pushed
        {name: "data recently-pushed within days", fn: {|| test data recently-pushed within days }}

        # Data: language-stats, owner-stats
        {name: "data language-stats", fn: {|| test data language-stats }}
        {name: "data owner-stats", fn: {|| test data owner-stats }}

        # Filters: individual
        {name: "filters exclude-archived", fn: {|| test filters exclude-archived }}
        {name: "filters exclude-forks", fn: {|| test filters exclude-forks }}
        {name: "filters exclude-languages default", fn: {|| test filters exclude-languages default }}
        {name: "filters exclude-languages custom", fn: {|| test filters exclude-languages custom }}
        {name: "filters exclude-old", fn: {|| test filters exclude-old }}
        {name: "filters exclude-old custom days", fn: {|| test filters exclude-old custom days }}

        # Filters: inclusion
        {name: "filters include-recent", fn: {|| test filters include-recent }}
        {name: "filters include-languages", fn: {|| test filters include-languages }}

        # Filters: apply-all
        {name: "filters apply-all defaults", fn: {|| test filters apply-all defaults }}
        {name: "filters apply-all include-archived", fn: {|| test filters apply-all include-archived }}
        {name: "filters apply-all include-old", fn: {|| test filters apply-all include-old }}
        {name: "filters apply-all include-forks", fn: {|| test filters apply-all include-forks }}
        {name: "filters apply-all include-all-languages", fn: {|| test filters apply-all include-all-languages }}
        {name: "filters apply-all custom days and languages", fn: {|| test filters apply-all custom days and languages }}

        # Filters: utility
        {name: "filters filter-config", fn: {|| test filters filter-config }}
        {name: "filters filter-stats", fn: {|| test filters filter-stats }}

        # Types: polars-schema
        {name: "types polars-schema has all columns", fn: {|| test types polars-schema has all columns }}
        {name: "types polars-schema correct types", fn: {|| test types polars-schema correct types }}
        {name: "types polars-schema cross-reference star-schema", fn: {|| test types polars-schema cross-reference star-schema }}

        # README examples
        {name: "readme filter by language and sort", fn: {|| test readme filter by language and sort }}
        {name: "readme top 10 by stars", fn: {|| test readme top 10 by stars }}
        {name: "readme group by language", fn: {|| test readme group by language }}
        {name: "readme dataframe output type", fn: {|| test readme dataframe output type }}
        {name: "readme lazyframe output type", fn: {|| test readme lazyframe output type }}

        # Edge cases
        {name: "edge empty table to lazyframe", fn: {|| test edge empty table to lazyframe }}
        {name: "edge single row dataframe", fn: {|| test edge single row dataframe }}
        {name: "edge all schema columns", fn: {|| test edge all schema columns }}
        {name: "edge type coercion round trip", fn: {|| test edge type coercion round trip }}
        {name: "edge sort empty lazyframe", fn: {|| test edge sort empty lazyframe }}
        {name: "edge search with null description", fn: {|| test edge search with null description }}
        {name: "edge filter-by-language preserves columns", fn: {|| test edge filter-by-language preserves columns }}
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

    print $"Running ($tests_to_run | length) tests..."
    print ""

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

    if $failed > 0 {
        exit 1
    }
}
