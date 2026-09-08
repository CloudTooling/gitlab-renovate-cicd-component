# Tests

[bats](https://bats-core.readthedocs.io/) unit tests for the shell logic that
ships inside the CI/CD component templates.

## Running locally

```sh
# bats + jq must be on PATH (brew install bats-core jq)
bats --print-output-on-failure tests/
```

CI runs the same command in the `Test User Migrator Script` job
(`bats/bats` image + `apk add jq`).

## Layout

| Path | Purpose |
| --- | --- |
| `user-migrator.bats` | Unit tests for the `mig_*` functions in `templates/user-migrator.yml`. |
| `helpers/extract.sh` | Pulls a job's inline `script:` block out of a component YAML (awk only). |
| `helpers/glab` | A `glab` stand-in that records calls and replies from `GLAB_MOCK_DIR/*.json`. |

The template YAML is the single source of truth: `extract.sh` writes the job
script to a temp file and the test sources it with `MIGRATOR_SOURCED=1`, which
skips `main()` so the functions can be exercised in isolation.
