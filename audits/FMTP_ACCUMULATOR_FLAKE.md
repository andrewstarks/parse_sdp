# Intermittent "no previous value for accumulator capture"

> **Status: resolved in our codebase by avoiding the `%` operator on this
> rule shape (commit reworking `fmtp_params_branch`). Not yet sent
> upstream.** The cause was never definitively isolated to LPeg vs.
> busted vs. our grammar usage; the fix below sidesteps it regardless.
>
> Replacing the `Ct(P("")) * (entry % set_pair)` chain with
> `Ct(entry * (sep * entry)^0) / fmtp_entries_to_params` — i.e. capture
> the entries as a list of 2-element sub-tables and transform that list
> to a flat params table in a function capture — eliminated the
> intermittent failure. 30 fresh `busted spec/` runs went 30/30 green;
> 30 fresh runs of the previously flaky `--filter "trailing semicolon"`
> against the full `grammar_base_spec.lua` also went 30/30. The previous
> rate was ~45%.
>
> The original investigation below is preserved so a future minimal
> repro effort has a starting point. It still wouldn't be a clean
> upstream LPeg report without a busted-free repro.

## Environment

| | |
|---|---|
| LPeg | 1.1.0-2 (luarocks-installed) |
| Lua | 5.3 (busted runs against 5.3 on this machine) |
| busted | 2.2.0-1 |
| dkjson | 2.8-1 (used elsewhere in the project; not loaded by failing tests) |
| OS | macOS Darwin 25.5.0 |
| Repo state | `refactor/grammar-first` branch at 6.B; reproduces back to commit `da46e17` (Phase 5) |

## What the error looks like

```
Error -> spec/grammar_base_spec.lua @ 2324
base SDP grammar — Phase 5 soft-syntactic findings fmtp trailing semicolon (sdp.a.fmtp.trailing-semicolon) emits a finding when fmtp ends with a stray ';'
./parse_sdp/grammar/base.lua:1008: no previous value for accumulator capture

stack traceback:
        ./parse_sdp/grammar/base.lua:1008: in function 'parse_sdp.grammar.base.match'
```

[parse_sdp/grammar/base.lua:1008](../parse_sdp/grammar/base.lua) is the
line that calls `grammar:match(text, 1, ctx)`. The error originates in
LPeg's C code at:

```c
// lpeg-1.1.0/lpcap.c:277-287
static int accumulatorcap (CapState *cs) {
  lua_State *L = cs->L;
  int n;
  if (lua_gettop(L) < cs->firstcap)
    luaL_error(L, "no previous value for accumulator capture");
  pushluaval(cs);  /* push function */
  lua_insert(L, -2);  /* previous value becomes first argument */
  n = pushnestedvalues(cs, 0);  /* push nested captures */
  lua_call(L, n + 1, 1);  /* call function */
  return 0;  /* did not add any extra value */
}
```

`cs->firstcap` is set at [lpcap.c:599](file:///Users/andrewstarks/Downloads/lpeg-1.1.0/lpcap.c#L599):
`cs.firstcap = lua_gettop(L) + 1`. The error fires when the Lua stack
contains fewer items than `firstcap` — i.e. when the `%` accumulator
runs without the previous capture (the table that it folds into)
being on the stack.

## The grammar pattern under suspicion

[parse_sdp/grammar/base.lua:603-620](../parse_sdp/grammar/base.lua):

```lua
fmtp_params_branch =
      Cg(
          Ct(P(""))                                 -- seed empty table
            * V"fmtp_entry"                         -- folds via `%`
            * (V"fmtp_sep" * V"fmtp_entry") ^ 0     -- folds via `%`
            * V"fmtp_trailing_sep_record" ^ -1,     -- optional Cmt + Carg
          "params"
        )
    * #V"line_end_chars",

fmtp_trailing_sep_record =
    Cmt(P(";") * V"fmtp_hws" ^ 0 * Carg(1),
        function(_, pos, ctx)
          if not ctx then return pos end
          local cont = errors.record(ctx, "sdp.a.fmtp.trailing-semicolon", {})
          if not cont then return false end
          return pos
        end),

fmtp_entry   = V"fmtp_kv_pair" + V"fmtp_flag",
fmtp_kv_pair = ( C(V"fmtp_key_chars" ^ 1) * V"fmtp_hws" ^ 0
              * P("=") * V"fmtp_hws" ^ 0
              * C(V"fmtp_val_chars" ^ 0)
              ) % set_pair,
fmtp_flag    = C(V"fmtp_key_chars" ^ 1) % set_flag,
```

The `Ct(P(""))` produces the seed (empty table) that `fmtp_entry`'s
`%` operator folds into. Inputs that trigger the failure are simple
fmtp values such as `profile-level-id=42e016;` (with the trailing `;`
that activates `fmtp_trailing_sep_record`) and
`profile-level-id=42e016;max-mbps=108000` (without).

The base.lua comment block at [base.lua:251-261](../parse_sdp/grammar/base.lua#L251)
already references an LPeg quirk that the *current* shape is supposed
to work around — *"a zero-width Cmt(Carg(1), …) inside the same Cg as
a `%` accumulator chain trips the 'no previous value for accumulator
capture' runtime error"*. The current `fmtp_trailing_sep_record` is
**not** zero-width: it consumes `;` plus optional whitespace before
its Carg(1) match. So the documented workaround is in place; the
flake is something else.

## How it reproduces

The bug is intermittent and reproduces **only** under one specific
harness condition.

```
$ cd /Users/andrewstarks/src/parse_sdp
$ for i in $(seq 1 20); do
    busted spec/grammar_base_spec.lua --filter "trailing semicolon" 2>&1 \
      | tail -1
  done
```

Out of 20 invocations (each a fresh `busted` process), roughly 9–11
fail with the accumulator error on the same 2 `it` blocks; the
remaining 9–11 pass. The flake rate has stayed in the 45–55% range
across multiple sampling rounds.

## What was ruled out

| Hypothesis | How tested | Result |
|---|---|---|
| Standalone-process LPeg bug | 30 fresh `lua` invocations of [/tmp/repro_flake.lua](/tmp/repro_flake.lua) (single match per process) | All 30 pass |
| LPeg state accumulating across many `base.match` calls | 800 calls per process (4 SDP variants × 200 iterations), 30 fresh processes | All 30 pass |
| Coroutine-related (busted wraps `it` bodies in coroutines) | 500 coroutine-wrapped matches per process, 20 fresh processes | All 20 pass |
| LPeg use inside dkjson | Failing tests don't touch dkjson; `dkjson.use_lpeg()` is opt-in and never called by parse_sdp | Ruled out |
| LPeg use inside busted itself | `grep -rl "lpeg" /usr/local/share/lua/5.3/busted` returns nothing | busted does not directly load LPeg |
| Loading the spec file alone | `busted spec/grammar_base_spec.lua --filter-out "."` (loads the file, runs zero tests) — 20 fresh runs | All 20 pass |
| The two failing `it` blocks in an extracted spec file | Copied verbatim into `/tmp/repro_specific.lua` with the same `match_collect` helper; 30 fresh busted runs | All 30 pass |
| A single `describe` block, even a fmtp-heavy one | `busted spec/grammar_base_spec.lua --filter "Phase 4.B fmtp"` (~20 it blocks), 20 fresh runs | All 20 pass |
| A separate fresh spec file with 50 same-input matches under busted | 5 fresh busted runs | All pass |
| A separate fresh spec file with 200 varied warmup matches + final fmtp test | 20 fresh busted runs | All 20 pass |
| Sharing `document_body` pattern across two grammar compilations | Switched to a `make_document_body()` factory; ran the suite | Flake rate unchanged |
| Optional `Cmt(...; Carg) ^ -1` inside the `Cg("params")` Cg | Moved `fmtp_trailing_sep_record^-1` outside the Cg | Flake rate unchanged (≈45%) |
| `^-1` optionality in general | Replaced `params^accumulator * trailing^-1` with two-shape alternation (`with_trailing` / `no_trailing`) so neither branch has an optional | Flake rate unchanged (≈50%) |

## What could NOT be ruled out

- **busted's interaction with our grammar.** The full `grammar_base_spec.lua`
  has 26 `describe` blocks and ~200 `it` blocks. Loading + running this
  file is what triggers the flake. I could not isolate which `describe`s
  or `it`s are required to surface it. Running smaller filters that
  match only a few tests still triggers the bug — but only when the full
  spec file is loaded; the same `it` bodies in a smaller spec file do
  not trigger it.
- **Lua hash seed dependence.** Lua 5.3+ uses a per-process random hash
  seed; `pairs(rules)` iteration order during `lpeg.P({...})` compilation
  varies between processes. *Theory*: certain seeds produce bytecode that
  miscounts `firstcap` for the `%` operator in this specific rules-table
  layout. *Evidence*: the bug is per-process binary (a process either
  always fails or always passes during its lifetime; once `lpeg.P` is
  compiled, behaviour is consistent within the process). *Not verified*:
  I did not find a way to fix Lua's hash seed and confirm the correlation.
- **Whether the bug is in LPeg, busted, our grammar, or the interaction.**
  I have no smoking gun pointing at LPeg specifically. The bug fires in
  LPeg's C code, but the trigger requires the busted harness. If the
  grammar were itself unsound (e.g. relied on undefined LPeg behaviour),
  it could also explain the per-seed split.

## Files involved

- [parse_sdp/grammar/base.lua](../parse_sdp/grammar/base.lua) — the
  grammar containing `fmtp_params_branch`. `M.grammar = lpeg.P(rules)`
  at line 1015.
- [parse_sdp/errors.lua](../parse_sdp/errors.lua) — `errors.record`
  called from the trailing-`;` Cmt. Returns `true` for warn-severity
  findings (default for `sdp.a.fmtp.trailing-semicolon`), so the Cmt
  always returns `pos` and never `false` on the failing inputs.
- [spec/grammar_base_spec.lua](../spec/grammar_base_spec.lua) line
  2324, 2337 — the two intermittently failing `it` blocks.
- [lpcap.c:277-287](file:///Users/andrewstarks/Downloads/lpeg-1.1.0/lpcap.c)
  — LPeg's `accumulatorcap`, where the error fires.

## What a sendable report would still need

- A minimal repro that reproduces **without** busted. None of the
  standalone-Lua attempts have triggered it. Until that exists, the
  evidence is consistent with this being a busted-host or
  grammar-soundness issue rather than an LPeg bug.
- Confirmation of the hash-seed theory — e.g. running with a fixed seed
  and showing the bug becomes deterministically present or absent.
- A reading of `lpcode.c` to see whether the bytecode generation for
  `Cg(Ct(P("")) * (... % fn) * ..., name)` can in fact produce a
  miscounted `firstcap` depending on rule-processing order.
