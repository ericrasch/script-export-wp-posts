# REFLECTION

Agent learning log. Entries here feed `/reflect`; approved items get promoted
to project standards (e.g. AGENTS.md / CLAUDE.md). Newest entries on top.

---

## 2026-06-11 — PR #3: add `post_modified` column

**Task:** Add `post_modified` as a permanent export column immediately after
`post_date`, threaded through WP-CLI fields, the Perl merge, and Excel output.

**Surprised by:** Reviewing the touched code surfaced a *pre-existing* bug in
the local export path — the posts CSV header was echoed once **and** the first
post type's WP-CLI output was appended with its own header (no `tail -n +2`),
so a duplicate header leaked through the Perl merge as a junk data row. It was
non-obvious because (a) remote mode was unaffected (it always strips the
header), and (b) the `awk 'NF == cols'` validation *passes* the junk row since
it has a valid field count, so nothing downstream flags it.

**Proposed AGENTS.md / CLAUDE.md additions:**
- GOTCHA: When a CSV file gets its header from an explicit `echo "..." >
  "$FILE"`, every subsequent `wp post list ... >> "$FILE"` append MUST pipe
  through `tail -n +2` to drop WP-CLI's own header. Local and remote branches
  must be symmetric on this. The merge only skips ONE header line, and the
  `NF == cols` guard won't catch a header-shaped junk row.
- WORKFLOW: When adding a column, audit BOTH the local and remote export
  branches plus the `EXPECTED_COLUMNS` math, the Perl field-count guard, the
  merge header, and the Excel column offsets — column changes ripple across
  ~6 coordinated sites in this script.

**Prompt improvement:** When a task touches a multi-branch shell pipeline
(local vs remote), diff the branches against each other first — asymmetries
between paths that "should" behave identically are where latent bugs hide.
