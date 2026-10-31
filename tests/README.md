# Tests

[bats](https://bats-core.readthedocs.io/) unit tests for the shell logic that
ships inside the CI/CD component templates.

## Running locally

```sh
# bats + jq must be on PATH (brew install bats-core jq)
bats --print-output-on-failure tests/
```

CI runs the same command in the `Unit-Tests Templates` job
(`bats/bats` image + `apk add jq`).

## Layout

| Path | Purpose |
| --- | --- |
| `user-migrator.bats` | Unit tests for the `mig_*` functions in `templates/user-migrator.yml`. |
| `runner-autoscale.bats` | Runs the child pipeline generation of `Generate Matrix` in `templates/runner-autoscale.yml` with GitLab-style interpolated inputs. |
| `helpers/extract.sh` | Pulls a job's inline `script:` block out of a component YAML (awk only); an optional index selects the n-th block. |
| `helpers/glab` | A `glab` stand-in that records calls and replies from `GLAB_MOCK_DIR/*.json`. |

The template YAML is the single source of truth: `extract.sh` writes the job
script to a temp file and the test sources it with `MIGRATOR_SOURCED=1`, which
skips `main()` so the functions can be exercised in isolation.

The `glab` stand-in is steered with env vars: `GLAB_MOCK_DIR` (fixture bodies:
`group-projects.json`, `issues-<id>.json`, `project.json`), `GLAB_MOCK_CALLS`
(request log the tests assert against), `GLAB_MOCK_USER` (`glab api user`), and
`GLAB_MOCK_CLONE_IID` (iid returned by the issue clone endpoint; set to `null`
to simulate a failed clone).

`runner-autoscale.bats` replaces each `$[[ inputs.<name> ]]` with `$INPUT_<name>`
and runs the script with `bash -eo pipefail`. Fixtures use the format GitLab
interpolates array inputs into strings: arrays of strings are JSON-like
(`["a", "b"]`), but hashes are Ruby hashes (`[{:project=>"a/b"}]`, or
`[{project: "a/b"}]` with Ruby >= 3.4), not JSON.
