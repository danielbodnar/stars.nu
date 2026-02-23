// @ts-check
import { defineConfig } from 'astro/config'
import starlight from '@astrojs/starlight'

export default defineConfig({
  site: 'https://docs.nu-stars.dev',
  outDir: './dist',
  build: { assets: '_astro' },
  integrations: [
    starlight({
      title: 'stars.nu',
      description: 'Nushell module for managing GitHub starred repositories',
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/danielbodnar/stars.nu' },
      ],
      sidebar: [
        {
          label: 'Getting Started',
          items: [
            { label: 'Installation', slug: 'getting-started/installation' },
            { label: 'Quick Start', slug: 'getting-started/quickstart' },
            { label: 'First Sync', slug: 'getting-started/first-sync' },
          ],
        },
        {
          label: 'Commands',
          items: [
            { label: 'Overview', slug: 'commands/overview' },
            { label: 'stars (main)', slug: 'commands/stars' },
            { label: 'stars sync', slug: 'commands/sync' },
            { label: 'stars config', slug: 'commands/config' },
            { label: 'stars export', slug: 'commands/export' },
            { label: 'stars stats', slug: 'commands/stats' },
          ],
        },
        {
          label: 'Guides',
          items: [
            { label: 'Configuration', slug: 'guides/configuration' },
            { label: 'Incremental Sync', slug: 'guides/incremental-sync' },
            { label: 'Default Filters', slug: 'guides/filters' },
            { label: 'Polars DataFrames', slug: 'guides/polars' },
            { label: 'Export Formats', slug: 'guides/export-formats' },
          ],
        },
        {
          label: 'Architecture',
          items: [
            { label: 'Overview', slug: 'architecture/overview' },
            { label: 'Storage Layer', slug: 'architecture/storage' },
            { label: 'Adapters', slug: 'architecture/adapters' },
            { label: 'Schema & Types', slug: 'architecture/schema' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'SQLite Schema', slug: 'reference/sqlite-schema' },
            { label: 'Configuration Options', slug: 'reference/config-options' },
            { label: 'Migration from gh-stars', slug: 'reference/migration' },
          ],
        },
      ],
    }),
  ],
})