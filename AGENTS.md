# AGENTS.md

Promoted, project-specific knowledge for agents working in this repo. Items
here are reviewed and approved via `/reflect` (sourced from `REFLECTION.md`).
Read this at the start of every session.

## GOTCHAS

- **CSV header source-of-truth:** When a CSV file gets its header from an
  explicit `echo "..." > "$FILE"`, every subsequent `wp post list ... >>
  "$FILE"` append MUST pipe through `tail -n +2` to drop WP-CLI's own header.
  Local and remote branches must be symmetric on this. The Perl merge skips
  only ONE header line, and the `awk 'NF == cols'` validation won't catch a
  header-shaped junk row (it has a valid field count). _(PR #3, 2026-06-11)_

## WORKFLOW

- **Adding/removing an export column** ripples across ~6 coordinated sites in
  `export_wp_posts.sh`. Audit all of them: both the local AND remote WP-CLI
  `--fields=` lists, the CSV header `echo`, `EXPECTED_COLUMNS` (static default
  + dynamic `$((... ))`), the Perl field-count guard + field indices, the
  `MERGE_HEADER`, and the Excel column offsets (`DATE_COL`/`STATUS_COL`/etc.).
  _(PR #3, 2026-06-11)_

- **Multi-branch shell pipelines (local vs remote):** Diff the branches
  against each other first. Asymmetries between paths that "should" behave
  identically are where latent bugs hide. _(PR #3, 2026-06-11)_
