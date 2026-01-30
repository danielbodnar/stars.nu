#!/usr/bin/env nu

# ============================================================================
# Stars Storage Module
# ============================================================================
#
# SQLite persistence layer for the stars module. Handles all database
# operations including loading, saving, backups, and migration from the
# legacy gh-stars module.
#
# Storage locations (XDG-compliant):
# - Database: $XDG_DATA_HOME/.stars/stars.db
# - Backups:  $XDG_DATA_HOME/.stars/backups/
# - Exports:  $XDG_DATA_HOME/.stars/exports/
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

# ============================================================================
# Configuration
# ============================================================================

# Get storage paths (XDG-compliant)
#
# Returns a record containing all storage-related paths for the stars module.
# Uses XDG_DATA_HOME if set, otherwise defaults to ~/.local/share.
#
# Example:
#   get-paths | get db_path
export def get-paths []: nothing -> record<db_path: path, backup_dir: path, export_dir: path> {
    let data_home = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let base_dir = $data_home | path join .stars

    {
        db_path: ($base_dir | path join stars.db)
        backup_dir: ($base_dir | path join backups)
        export_dir: ($base_dir | path join exports)
    }
}

# ============================================================================
# Storage Management
# ============================================================================

# Ensure storage directory exists
#
# Creates the base storage directory and all subdirectories if they don't exist.
# Called automatically by save and backup operations.
#
# Example:
#   ensure-storage
export def ensure-storage []: nothing -> nothing {
    let paths = get-paths
    let base_dir = $paths.db_path | path dirname

    ensure-directory $base_dir
    ensure-directory $paths.backup_dir
    ensure-directory $paths.export_dir
}

# ============================================================================
# Data Operations
# ============================================================================

# Load all stars from SQLite database
#
# Returns a table of all starred repositories sorted by stargazer count.
# Raises an error if the database doesn't exist.
#
# Example:
#   load | where language == "Rust"
export def load []: nothing -> table {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "Database not found"
            label: {text: "Run 'stars fetch' first", span: (metadata $paths).span}
            help: "The stars database needs to be initialized before loading"
        }
    }

    try {
        open $paths.db_path | query db "SELECT * FROM stars ORDER BY stargazers_count DESC"
    } catch {|e|
        error make {
            msg: $"Failed to load stars from database: ($e.msg)"
            label: {text: "database query failed", span: (metadata $paths.db_path).span}
        }
    }
}

# Store stars to SQLite (with optional replace)
#
# Saves a table of star data to the SQLite database. By default, appends to
# existing data. Use --replace to clear the database first.
#
# Note: Named 'store' instead of 'save' to avoid shadowing Nushell's built-in
# 'save' command when this module is imported.
#
# Parameters:
#   data: table - Star data to save (must have standard star columns)
#   --replace - Clear existing data before saving
#
# Example:
#   $stars | store --replace
export def store [
    data: table     # Star data to save
    --replace       # Clear existing data before saving
]: nothing -> nothing {
    let paths = get-paths

    ensure-storage

    if $replace and ($paths.db_path | path exists) {
        try {
            rm $paths.db_path
        } catch {|e|
            error make {
                msg: $"Failed to remove existing database: ($e.msg)"
                label: {text: "file removal failed", span: (metadata $paths.db_path).span}
            }
        }
    }

    if ($data | is-empty) {
        return
    }

    try {
        $data | into sqlite $paths.db_path --table-name stars
    } catch {|e|
        error make {
            msg: $"Failed to save stars to database: ($e.msg)"
            label: {text: "database write failed", span: (metadata $paths.db_path).span}
            help: "Check that the data has valid columns and types"
        }
    }
}

# ============================================================================
# Backup Operations
# ============================================================================

# Create timestamped backup
#
# Creates a copy of the current database with a timestamp in the filename.
# Returns the path to the backup file.
#
# Example:
#   let backup_path = backup
#   print $"Backup created at ($backup_path)"
export def backup []: nothing -> path {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        error make {
            msg: "No database to backup"
            label: {text: "database not found", span: (metadata $paths).span}
            help: "Run 'stars fetch' first to create a database"
        }
    }

    ensure-directory $paths.backup_dir

    let timestamp = date now | format date %Y%m%d_%H%M%S
    let backup_file = $paths.backup_dir | path join $"stars_($timestamp).db"

    try {
        cp $paths.db_path $backup_file
    } catch {|e|
        error make {
            msg: $"Failed to create backup: ($e.msg)"
            label: {text: "backup failed", span: (metadata $backup_file).span}
        }
    }

    $backup_file
}

# ============================================================================
# Migration
# ============================================================================

# Migrate from old gh-stars location
#
# Checks if the old gh-stars database exists and migrates it to the new
# location. Adds source and synced_at columns if they don't exist.
#
# Returns true if migration was performed, false if no migration needed.
#
# Example:
#   if (migrate-from-gh-stars) {
#       print "Migration complete"
#   }
export def migrate-from-gh-stars []: nothing -> bool {
    let paths = get-paths
    let data_home = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let old_db_path = $data_home | path join gh-stars stars.db

    # Skip if old database doesn't exist
    if not ($old_db_path | path exists) {
        return false
    }

    # Skip if new database already exists
    if ($paths.db_path | path exists) {
        print --stderr "New database already exists, skipping migration"
        return false
    }

    ensure-storage

    print --stderr $"Migrating from ($old_db_path) to ($paths.db_path)..."

    # Load data from old database
    let old_data = try {
        open $old_db_path | query db "SELECT * FROM stars"
    } catch {|e|
        error make {
            msg: $"Failed to read old database: ($e.msg)"
            label: {text: "migration read failed", span: (metadata $old_db_path).span}
        }
    }

    if ($old_data | is-empty) {
        print --stderr "Old database is empty, nothing to migrate"
        return false
    }

    # Add source and synced_at columns if they don't exist
    let migrated_data = $old_data | each {|row|
        let row_with_source = if ("source" in ($row | columns)) {
            $row
        } else {
            $row | insert source "github"
        }

        if ("synced_at" in ($row_with_source | columns)) {
            $row_with_source
        } else {
            $row_with_source | insert synced_at (date now | format date "%Y-%m-%dT%H:%M:%SZ")
        }
    }

    # Save to new location
    try {
        $migrated_data | into sqlite $paths.db_path --table-name stars
    } catch {|e|
        error make {
            msg: $"Failed to write migrated data: ($e.msg)"
            label: {text: "migration write failed", span: (metadata $paths.db_path).span}
        }
    }

    let count = $migrated_data | length
    print --stderr $"Successfully migrated ($count) stars to new location"
    print --stderr $"Old database preserved at: ($old_db_path)"

    true
}

# ============================================================================
# Statistics
# ============================================================================

# Get database statistics
#
# Returns a record with database metadata and basic statistics.
#
# Example:
#   get-stats | get total_stars
export def get-stats []: nothing -> record {
    let paths = get-paths

    if not ($paths.db_path | path exists) {
        return {
            exists: false
            total_stars: 0
            unique_languages: 0
            archived_repos: 0
            forked_repos: 0
            db_size_bytes: 0
            last_modified: null
            backup_count: 0
        }
    }

    let counts = try {
        open $paths.db_path | query db "
            SELECT
                COUNT(*) as total_stars,
                COUNT(DISTINCT language) as unique_languages,
                SUM(CASE WHEN archived = 1 THEN 1 ELSE 0 END) as archived_repos,
                SUM(CASE WHEN fork = 1 THEN 1 ELSE 0 END) as forked_repos
            FROM stars
            WHERE language IS NOT NULL AND language != ''
        " | first
    } catch {
        {total_stars: 0, unique_languages: 0, archived_repos: 0, forked_repos: 0}
    }

    let db_info = try {
        ls $paths.db_path | first
    } catch {
        {size: 0, modified: null}
    }

    let backup_count = if ($paths.backup_dir | path exists) {
        try {
            ls $paths.backup_dir | where name =~ '\.db$' | length
        } catch { 0 }
    } else {
        0
    }

    {
        exists: true
        total_stars: $counts.total_stars
        unique_languages: $counts.unique_languages
        archived_repos: $counts.archived_repos
        forked_repos: $counts.forked_repos
        db_size_bytes: $db_info.size
        last_modified: $db_info.modified
        backup_count: $backup_count
    }
}
