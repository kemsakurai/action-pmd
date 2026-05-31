---
description: "Use when editing this repository's GitHub Action files, including action.yml, entrypoint.sh, Dockerfile, README.md, and workflow integration for PMD and reviewdog."
applyTo: "{action.yml,Dockerfile,entrypoint.sh,README.md,.github/workflows/**}"
---

# action-pmd Repository Instructions

This repository provides a Docker-based GitHub Action that runs PMD on Java source code and reports findings via reviewdog.

- Keep runtime behavior consistent across `action.yml`, `entrypoint.sh`, and `Dockerfile`.
- Treat this action as PMD 7.x based. Use `pmd check` syntax, not legacy PMD 6.x CLI syntax.
- Prefer built-in PMD rulesets under `category/java/...` when providing defaults or examples.

## Input and Environment Contract

- If you add, rename, or remove an input in `action.yml`, update `entrypoint.sh` to use the corresponding `INPUT_*` variable.
- Keep default values and descriptions synchronized between `action.yml` and `README.md`.
- Preserve current reviewdog flags and names unless the change request explicitly alters behavior.

## Shell Script Rules (`entrypoint.sh`)

- Keep the script POSIX `sh` compatible.
- Keep `set -e` behavior unless the user explicitly requests a different error strategy.
- Validate user inputs before executing PMD when practical (for example, directory existence and ruleset warnings).
- Avoid introducing Bash-only syntax.

## Dockerfile Rules

- Keep the multi-stage design: PMD download/build stage and runtime stage.
- Pin tool versions via `ARG` values and update related docs when versions change.
- Ensure required runtime tools (`git`, `wget`, `reviewdog`, Java runtime, PMD binary) remain available.

## Documentation Rules (`README.md`)

- Update usage examples and migration notes whenever defaults, versions, or CLI behavior change.
- Keep guidance aligned with PMD 7.x and category-based ruleset paths.
- If you change inputs or defaults, update the Inputs section and examples in the same change.

## Change Hygiene

- Prefer small, behavior-focused edits.
- When changing command lines, preserve quoting and safe handling of empty optional flags.
- Do not add unrelated refactors when implementing targeted fixes.