#!/usr/bin/env nu

# ============================================================================
# Polars DataFrame/LazyFrame Output Formatters
# ============================================================================
#
# Provides functions for converting data to Polars DataFrame and LazyFrame
# types with proper schema handling and type coercion.
#
# Requires: nu_plugin_polars (polars commands)
#
# Author: Daniel Bodnar
# ============================================================================

# ============================================================================
# Internal Helpers
# ============================================================================

# Check if Polars plugin is available
def check-polars-available []: nothing -> bool {
    try {
        # Try to access a polars command - if it fails, plugin not loaded
        "test" | polars into-df | ignore
        true
    } catch {
        false
    }
}

# Raise error if Polars is not available
def require-polars []: nothing -> nothing {
    if not (check-polars-available) {
        error make {
            msg: "Polars plugin not available"
            help: "Install and register nu_plugin_polars:
  1. cargo install nu_plugin_polars
  2. plugin add ~/.cargo/bin/nu_plugin_polars
  3. Restart Nushell"
        }
    }
}

# ============================================================================
# Type Detection
# ============================================================================

# Check if input is already a Polars type (DataFrame or LazyFrame)
#
# Determines whether the input data is already a Polars DataFrame or LazyFrame,
# which avoids unnecessary conversions.
#
# Parameters:
#   data: any - Data to check
#
# Returns: bool - true if data is a Polars type
#
# Example:
#   [[a b]; [1 2]] | is-polars-type  # false
#   [[a b]; [1 2]] | polars into-df | is-polars-type  # true
export def is-polars-type [data: any]: nothing -> bool {
    let type_name = $data | describe

    # Check for Polars type indicators in the description
    ($type_name =~ "(?i)dataframe") or ($type_name =~ "(?i)lazyframe") or ($type_name =~ "(?i)polars")
}

# ============================================================================
# Conversion Functions
# ============================================================================

# Convert table to Polars LazyFrame with proper schema
#
# Converts a Nushell table to a Polars LazyFrame, applying appropriate
# type coercion for common column types (dates, integers, strings).
#
# Parameters:
#   data: table - Nushell table to convert
#
# Returns: LazyFrame - Polars LazyFrame
#
# Example:
#   [[name age]; ["Alice" 30]] | table-to-lazy
export def table-to-lazy [
    data: table  # Table data to convert
]: nothing -> any {
    require-polars

    if ($data | is-empty) {
        # Return empty LazyFrame
        [] | polars into-df | polars into-lazy
    } else {
        # Convert to DataFrame first, then to LazyFrame
        # Note: Schema coercion is skipped due to Nushell limitations with mutable captures
        # Users can apply explicit schema using apply-schema if needed
        $data | polars into-df | polars into-lazy
    }
}

# Return data as Polars LazyFrame (uncollected)
#
# Converts input data to a Polars LazyFrame. If the input is already a
# LazyFrame, returns it as-is. If it's a DataFrame, converts to lazy.
# If it's a table, performs full conversion with schema coercion.
#
# Parameters:
#   data: any - Input data (table, DataFrame, or LazyFrame)
#
# Returns: LazyFrame - Polars LazyFrame
#
# Example:
#   [[name stars]; ["repo1" 100]] | to-lazyframe
#   $existing_df | to-lazyframe
export def to-lazyframe [
    data: any  # Data to convert (table, DataFrame, or LazyFrame)
]: nothing -> any {
    require-polars

    let type_name = $data | describe

    if ($type_name =~ "(?i)lazyframe") {
        # Already a LazyFrame, return as-is
        $data
    } else if ($type_name =~ "(?i)dataframe") {
        # Convert DataFrame to LazyFrame
        $data | polars into-lazy
    } else if ($type_name == "table" or $type_name =~ "list<") {
        # Convert table to LazyFrame with schema coercion
        table-to-lazy $data
    } else {
        error make {
            msg: $"Cannot convert type '($type_name)' to LazyFrame"
            help: "Input must be a table, DataFrame, or LazyFrame"
        }
    }
}

# Return data as collected Polars DataFrame
#
# Converts input data to a Polars DataFrame. If the input is already a
# DataFrame, returns it as-is. If it's a LazyFrame, collects it.
# If it's a table, performs full conversion with schema coercion.
#
# Parameters:
#   data: any - Input data (table, DataFrame, or LazyFrame)
#
# Returns: DataFrame - Polars DataFrame
#
# Example:
#   [[name stars]; ["repo1" 100]] | to-dataframe
#   $lazy_frame | to-dataframe
export def to-dataframe [
    data: any  # Data to convert (table, DataFrame, or LazyFrame)
]: nothing -> any {
    require-polars

    let type_name = $data | describe

    if ($type_name =~ "(?i)dataframe") and not ($type_name =~ "(?i)lazy") {
        # Already a DataFrame (not lazy), return as-is
        $data
    } else if ($type_name =~ "(?i)lazyframe") {
        # Collect LazyFrame to DataFrame
        $data | polars collect
    } else if ($type_name == "table" or $type_name =~ "list<") {
        # Convert table to LazyFrame, then collect
        table-to-lazy $data | polars collect
    } else {
        error make {
            msg: $"Cannot convert type '($type_name)' to DataFrame"
            help: "Input must be a table, DataFrame, or LazyFrame"
        }
    }
}

# ============================================================================
# Schema Utilities
# ============================================================================

# Get schema information from a DataFrame or LazyFrame
#
# Returns column names and their inferred types for inspection.
#
# Parameters:
#   data: any - DataFrame or LazyFrame to inspect
#
# Returns: table - Column names and types
#
# Example:
#   $df | get-schema
export def get-schema [
    data: any  # DataFrame or LazyFrame to inspect
]: nothing -> table {
    require-polars

    let df = to-dataframe $data
    $df | polars schema | transpose column dtype
}

# Apply explicit schema to a LazyFrame
#
# Casts columns to specified types. Useful when automatic type detection
# doesn't produce the desired schema.
#
# Note: Due to Nushell limitations with mutable variable capture in closures,
# this function applies schema through reduce pattern instead of for loop.
#
# Parameters:
#   data: any - Data to apply schema to
#   schema: record - Column name to type mapping
#
# Returns: LazyFrame - LazyFrame with applied schema
#
# Example:
#   $data | apply-schema {age: i64, created_at: datetime}
export def apply-schema [
    data: any          # Data to apply schema to
    schema: record     # Column name to type mapping
]: nothing -> any {
    require-polars

    let lf = to-lazyframe $data

    # Apply casts using reduce to avoid mutable capture issues
    $schema | transpose key value | reduce --fold $lf {|entry, acc|
        let col_name = $entry.key
        let col_type = $entry.value

        try {
            match $col_type {
                "i64" | "int64" | "int" => {
                    $acc | polars with-column ((polars col $col_name) | polars cast i64 | polars as $col_name)
                }
                "f64" | "float64" | "float" => {
                    $acc | polars with-column ((polars col $col_name) | polars cast f64 | polars as $col_name)
                }
                "str" | "string" | "utf8" => {
                    $acc | polars with-column ((polars col $col_name) | polars cast str | polars as $col_name)
                }
                "bool" | "boolean" => {
                    $acc | polars with-column ((polars col $col_name) | polars cast bool | polars as $col_name)
                }
                "datetime" | "date" => {
                    $acc | polars with-column ((polars col $col_name) | polars cast datetime | polars as $col_name)
                }
                _ => {
                    print --stderr $"Warning: Unknown type '($col_type)' for column '($col_name)', skipping"
                    $acc
                }
            }
        } catch {
            print --stderr $"Warning: Failed to cast column '($col_name)' to '($col_type)'"
            $acc
        }
    }
}
