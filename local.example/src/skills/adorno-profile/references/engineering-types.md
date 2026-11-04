# Engineering — types, single source of truth, simplicity

> Template. Your version lives in `local/src/skills/adorno-profile/references/engineering-types.md`
> (git-ignored). The repo's rules (`CLAUDE.md`, `.claude/rules/`) always win on its code.

## Types

- Strict typing; no escape hatches (`any`, unchecked casts, ignore comments) without a stated reason.
- Derive types from a schema or a constant instead of restating them.

## Single source of truth

- One definition per fact (a list, a constant, a schema); everything else derives from it.

## Simplicity

- The smallest change that fully solves the problem; delete dead code and its tests.
- An abstraction earns its place at its third use, not its first.

## Layers

- Pure logic separated from I/O; each layer has one job and a reason to exist.
