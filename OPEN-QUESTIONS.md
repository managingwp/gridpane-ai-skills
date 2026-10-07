# Open Questions

Items the maintainer needs to decide or confirm. Per [AGENTS.md](AGENTS.md),
anything that cannot be verified against the GridPane Knowledge Base or
maintainer-supplied server output is recorded here rather than presented as
fact.

## Unverified facts

Facts used in a skill that could not be traced to a source yet. Each entry names
the skill and reference file that mentions it, plus what would confirm it.

- (none yet)

## Scope proposals

Changes to the skill set or safety model that need maintainer sign-off
(AGENTS.md ground rule 5).

- **License.** `LICENSE` currently carries MIT, carried over from README.md
  ("MIT (proposed; confirm before first release)"). Confirm MIT or replace it
  before the first release.
- **OpenLiteSpeed scope.** `gridpane-nginx-config` documents Nginx first. Decide
  whether OpenLiteSpeed customisation is in scope for v0.1 or documented as
  out of scope.

## Needs real-server output

Details that should come from output captured on a real GridPane server before
they are treated as verified.

- `gp` CLI help text (`gp --help`, `gp site --help`, `gp stack --help`) to
  confirm the exact subcommands and flags used in `gridpane-gp-cli`.
- GridPane REST API base URL, auth header format and endpoint list for
  `gridpane-api`.
- Directory listing for the per-site custom Nginx include location and the
  GridPane-managed files that `gp` regenerates.
