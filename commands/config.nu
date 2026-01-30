#!/usr/bin/env nu

# ============================================================================
# Stars Configuration Module
# ============================================================================
#
# Configuration management for the stars module. Stores settings in NUON format
# at $XDG_CONFIG_HOME/stars/config.nu for user customization.
#
# Config file location: $XDG_CONFIG_HOME/stars/config.nu
#
# Author: Daniel Bodnar
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Get the config file path
def get-config-path []: nothing -> path {
    let config_home = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    $config_home | path join stars config.nu
}

# Ensure config directory exists
def ensure-config-dir []: nothing -> nothing {
    let config_path = get-config-path
    let config_dir = $config_path | path dirname

    if not ($config_dir | path exists) {
        try {
            mkdir $config_dir
        } catch {|e|
            error make {
                msg: $"Failed to create config directory: ($e.msg)"
                label: {text: "directory creation failed", span: (metadata $config_dir).span}
            }
        }
    }
}

# Get default configuration
def get-default-config []: nothing -> record {
    {
        version: "3.0.0"
        storage: {
            db_path: null
            backup_on_sync: true
        }
        defaults: {
            filters: {
                exclude_languages: [PHP, "C#", Java, Python, Ruby]
                exclude_archived: true
                exclude_forks: false
                min_pushed_days: 365
            }
            columns: [owner, name, language, stars, pushed, homepage, topics, description, forks, issues]
            sort_by: "stars"
            sort_reverse: true
        }
        output: {
            default_format: "table"
            table: {
                max_description_length: 80
                clickable_links: true
                colorize_languages: true
            }
        }
        sync: {
            sources: [github]
            github: {
                per_page: 100
                cache_duration: "1h"
            }
        }
    }
}

# Load configuration from file, or return defaults
def load-config []: nothing -> record {
    let config_path = get-config-path

    if not ($config_path | path exists) {
        return (get-default-config)
    }

    try {
        open $config_path
    } catch {|e|
        print --stderr $"Warning: Failed to load config, using defaults: ($e.msg)"
        get-default-config
    }
}

# Save configuration to file
def save-config [config: record]: nothing -> nothing {
    let config_path = get-config-path

    ensure-config-dir

    try {
        $config | to nuon --indent 4 | save --force $config_path
    } catch {|e|
        error make {
            msg: $"Failed to save config: ($e.msg)"
            label: {text: "config write failed", span: (metadata $config_path).span}
        }
    }
}

# Navigate to a nested key using dot notation
# Returns {value: any, found: bool}
def get-nested-value [
    data: record
    key: string
]: nothing -> record<value: any, found: bool> {
    let parts = $key | split row "."

    mut current = $data
    mut found = true

    for part in $parts {
        let type = $current | describe | str replace --regex '<.*' ''

        if $type != "record" {
            $found = false
            break
        }

        if $part not-in ($current | columns) {
            $found = false
            break
        }

        $current = ($current | get $part)
    }

    {value: $current, found: $found}
}

# Set a nested value using dot notation
def set-nested-value [
    data: record
    key: string
    value: any
]: nothing -> record {
    let parts = $key | split row "."

    if ($parts | length) == 1 {
        # Simple case: top-level key
        $data | upsert $key $value
    } else {
        # Nested case: recursively update
        let first = $parts | first
        let rest = $parts | skip 1 | str join "."

        let current_value = if $first in ($data | columns) {
            $data | get $first
        } else {
            {}
        }

        let type = $current_value | describe | str replace --regex '<.*' ''
        let nested = if $type == "record" {
            set-nested-value $current_value $rest $value
        } else {
            # Create nested structure
            set-nested-value {} $rest $value
        }

        $data | upsert $first $nested
    }
}

# ============================================================================
# Exported Commands
# ============================================================================

# Show current configuration
#
# Returns the current configuration as a record. Loads from config file
# if it exists, otherwise returns defaults.
#
# Parameters:
#   --json - Output as JSON instead of record
#
# Example:
#   stars config
#   stars config --json
export def "stars config" [
    --json  # Output as JSON
]: nothing -> record {
    let config = load-config

    if $json {
        $config | to json
    } else {
        $config
    }
}

# Show current configuration (alias)
#
# Alias for `stars config` command.
#
# Parameters:
#   --json - Output as JSON instead of record
#
# Example:
#   stars config show
#   stars config show --json
export def "stars config show" [
    --json  # Output as JSON
]: nothing -> record {
    stars config --json=$json
}

# Initialize configuration with defaults
#
# Creates a new configuration file with default values. If a config file
# already exists, use --force to overwrite it.
#
# Parameters:
#   --force - Overwrite existing config file
#
# Example:
#   stars config init
#   stars config init --force
export def "stars config init" [
    --force  # Overwrite existing config
]: nothing -> nothing {
    let config_path = get-config-path

    if ($config_path | path exists) and (not $force) {
        error make {
            msg: "Configuration file already exists"
            label: {text: "use --force to overwrite", span: (metadata $config_path).span}
            help: $"Config file location: ($config_path)"
        }
    }

    let default_config = get-default-config
    save-config $default_config

    print $"Configuration initialized at: ($config_path)"
}

# Edit configuration in $EDITOR
#
# Opens the configuration file in the editor specified by $EDITOR or $VISUAL
# environment variable. Creates a default config if none exists.
#
# Example:
#   stars config edit
export def "stars config edit" []: nothing -> nothing {
    let config_path = get-config-path

    # Initialize config if it doesn't exist
    if not ($config_path | path exists) {
        stars config init
    }

    let editor = $env.EDITOR? | default ($env.VISUAL? | default "nvim")

    try {
        run-external $editor $config_path
    } catch {|e|
        error make {
            msg: $"Failed to open editor: ($e.msg)"
            label: {text: "editor launch failed", span: (metadata $editor).span}
            help: "Set $EDITOR environment variable to your preferred editor"
        }
    }
}

# Get a specific config value
#
# Retrieves a value from the configuration using dot notation for nested keys.
#
# Parameters:
#   key - Config key using dot notation (e.g., "defaults.columns", "output.table.clickable_links")
#
# Example:
#   stars config get version
#   stars config get defaults.columns
#   stars config get output.table.clickable_links
#   stars config get sync.github.per_page
export def "stars config get" [
    key: string  # Config key (dot notation: defaults.columns)
]: nothing -> any {
    let config = load-config
    let result = get-nested-value $config $key

    if not $result.found {
        error make {
            msg: $"Config key not found: ($key)"
            label: {text: "key does not exist", span: (metadata $key).span}
            help: "Use 'stars config' to see available keys"
        }
    }

    $result.value
}

# Set a specific config value
#
# Sets a value in the configuration using dot notation for nested keys.
# Creates intermediate keys if they don't exist.
#
# Parameters:
#   key - Config key using dot notation (e.g., "defaults.sort_by")
#   value - Value to set (any type)
#
# Example:
#   stars config set defaults.sort_by "pushed"
#   stars config set output.table.max_description_length 120
#   stars config set defaults.filters.exclude_archived false
export def "stars config set" [
    key: string  # Config key (dot notation)
    value: any   # Value to set
]: nothing -> nothing {
    let config = load-config
    let updated_config = set-nested-value $config $key $value

    save-config $updated_config

    print $"Set ($key) = ($value | to nuon)"
}

# Reset configuration to defaults
#
# Resets the entire configuration or a specific key to default values.
#
# Parameters:
#   --key - Specific key to reset (dot notation), resets all if not specified
#
# Example:
#   stars config reset
#   stars config reset --key defaults.filters
export def "stars config reset" [
    --key: string  # Specific key to reset (optional)
]: nothing -> nothing {
    let default_config = get-default-config

    if ($key | is-empty) {
        save-config $default_config
        print "Configuration reset to defaults"
    } else {
        let default_result = get-nested-value $default_config $key

        if not $default_result.found {
            error make {
                msg: $"Unknown config key: ($key)"
                label: {text: "key not in defaults", span: (metadata $key).span}
            }
        }

        let config = load-config
        let updated_config = set-nested-value $config $key $default_result.value

        save-config $updated_config

        print $"Reset ($key) to default value"
    }
}

# Get the config file path
#
# Returns the path to the configuration file.
#
# Example:
#   stars config path
export def "stars config path" []: nothing -> path {
    get-config-path
}

# Validate current configuration
#
# Checks the configuration for common issues and reports any problems found.
#
# Example:
#   stars config validate
export def "stars config validate" []: nothing -> record<valid: bool, errors: list<string>, warnings: list<string>> {
    let config = load-config
    mut errors = []
    mut warnings = []

    # Check version
    if "version" not-in ($config | columns) {
        $errors = ($errors | append "Missing 'version' field")
    }

    # Check storage section
    if "storage" not-in ($config | columns) {
        $errors = ($errors | append "Missing 'storage' section")
    } else {
        if "backup_on_sync" not-in ($config.storage | columns) {
            $warnings = ($warnings | append "Missing 'storage.backup_on_sync' setting")
        }
    }

    # Check defaults section
    if "defaults" not-in ($config | columns) {
        $errors = ($errors | append "Missing 'defaults' section")
    } else {
        if "columns" not-in ($config.defaults | columns) {
            $warnings = ($warnings | append "Missing 'defaults.columns' setting")
        }
        if "filters" not-in ($config.defaults | columns) {
            $warnings = ($warnings | append "Missing 'defaults.filters' section")
        }
    }

    # Check output section
    if "output" not-in ($config | columns) {
        $warnings = ($warnings | append "Missing 'output' section")
    }

    # Check sync section
    if "sync" not-in ($config | columns) {
        $warnings = ($warnings | append "Missing 'sync' section")
    }

    let valid = ($errors | is-empty)

    if $valid and ($warnings | is-empty) {
        print "Configuration is valid"
    } else {
        if not ($errors | is-empty) {
            print "Errors:"
            for err in $errors {
                print $"  - ($err)"
            }
        }
        if not ($warnings | is-empty) {
            print "Warnings:"
            for warn in $warnings {
                print $"  - ($warn)"
            }
        }
    }

    {valid: $valid, errors: $errors, warnings: $warnings}
}
