# Conformance Suite — AMWA Upstream Fixtures

This is an **opt-in** test suite. It downloads SDP fixtures from upstream AMWA
NMOS repositories (pinned to specific commit SHAs) and runs them through the
`parse_sdp` parser. The default `busted spec/` run does **not** include this
suite, so the primary test workflow stays hermetic.

## Running

```sh
busted spec_conformance/
# or inside the container:
docker compose run --rm test busted spec_conformance/
```

The first run downloads fixtures into `spec_conformance/.cache/` (gitignored).
Subsequent runs reuse the cache. Delete `.cache/` to force a re-fetch.

Requires `curl` on the PATH (it is in the project's Docker image).

## What's tested

Every fixture in [`manifest.lua`](manifest.lua) is fetched, optionally rendered
through a small Jinja2 subset (see below), and parsed with the declared
validation tier (`rfc4566`, `st2110`, or `ipmx`). Each successful parse is also
round-tripped through `doc:to_sdp()` and `doc:to_json()`.

A manifest entry may also declare `expect = "fail"` with `expect_spec_ref` —
that signals "the upstream fixture is non-conformant per this clause, and our
parser is expected to reject it for that reason." The test passes when the
parser rejects the fixture and the error's `spec_ref` matches. Use this for
upstream templates whose structural gaps are too deep to repair via vars but
which clearly violate a named SMPTE/AMWA clause.

The strict-by-default failure mode means any upstream-valid fixture we reject
without an explicit `expect = "fail"` is a real signal — either our parser is
wrong, or the fixture violates a clause we should be citing. Open questions
(divergences we have not yet confirmed against the primary spec PDF) live in
[`allowlist.lua`](allowlist.lua) with a `reason` and a `spec_ref`. An empty
allowlist is the goal state; entries should be resolved by either fixing the
parser or moving the fixture to `expect = "fail"` with a citation.

## Sources

| Source | Repo | Pinned SHA | License |
| --- | --- | --- | --- |
| nmos-testing | [AMWA-TV/nmos-testing](https://github.com/AMWA-TV/nmos-testing) | `c0f4f30ee764a12d9f76c39057149122b1e7029c` | Apache-2.0 |
| bcp-006-01   | [AMWA-TV/bcp-006-01](https://github.com/AMWA-TV/bcp-006-01)     | `865faf3ff987f75d1466aa4c3576ce78b331d1f1` | Apache-2.0 |

`AMWA-TV/is-05` was surveyed and contains no SDP fixtures (only JSON transport
parameter examples); it is not pulled.

## The template renderer

The six fixtures under `nmos-testing/test_data/sdp/` are Jinja2 templates, not
literal SDP — they contain `{{ src_ip }}`, `{% if interlace %}`-style
placeholders, etc. [`render.lua`](render.lua) implements the minimal subset
required by these specific files:

| Form | Behavior |
| --- | --- |
| `{{ name }}` | substitute `vars[name]` (errors if missing) |
| `{{ "literal" if name }}` | emit `"literal"` if `vars[name]` truthy, else `""` |
| `{{ "...{}...".format(name) if name }}` | format substitution if truthy, else `""` |

If a future upstream commit adds new template syntax, expand `render.lua` to
match. This is **not** a general Jinja2 implementation.

Each fixture in `manifest.lua` carries the `vars` table used to render it.
Several templates appear multiple times with different parameter sets (e.g.
1080p59.94 progressive vs. 1080i29.97 interlaced) for breadth.

The single fixture from `bcp-006-01` is literal SDP and is parsed as-is.

## Refreshing the upstream SHAs

1. Identify the new commit on the upstream repo's default branch.
2. Update `sha` in [`manifest.lua`](manifest.lua) `sources`.
3. Delete `spec_conformance/.cache/` and re-run.
4. Investigate any new failures: either fix our parser, add an entry to
   `allowlist.lua` with a citation, or update the `vars` block.
5. Note the bump in `CHANGELOG.md`.

## Attribution

The fixtures fetched by this suite are © their respective contributors and
licensed under the Apache License, Version 2.0. See:

- <https://github.com/AMWA-TV/nmos-testing/blob/master/LICENSE>
- <https://github.com/AMWA-TV/bcp-006-01/blob/main/LICENSE>

Fixtures are downloaded into a gitignored cache directory at test time. No
upstream content is checked into this repository.
