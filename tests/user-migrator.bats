#!/usr/bin/env bats
#
# Unit tests for the mig_* helper functions embedded in the
# `Migrate Renovate Dashboards` job of templates/user-migrator.yml.
#
# The job script is extracted from the component YAML and sourced with
# MIGRATOR_SOURCED=1 so that main() does not run on load.

setup_file() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO_ROOT
  export MIGRATOR_LIB="${BATS_FILE_TMPDIR}/user-migrator.sh"
  bash "${REPO_ROOT}/tests/helpers/extract.sh" \
    "${REPO_ROOT}/templates/user-migrator.yml" "Migrate Renovate Dashboards" \
    > "${MIGRATOR_LIB}"
  bash -n "${MIGRATOR_LIB}"
}

setup() {
  MOCKBIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${MOCKBIN}"
  install -m 0755 "${REPO_ROOT}/tests/helpers/glab" "${MOCKBIN}/glab"
  PATH="${MOCKBIN}:${PATH}"

  export GLAB_MOCK_DIR="${BATS_TEST_TMPDIR}/fixtures"
  export GLAB_MOCK_CALLS="${BATS_TEST_TMPDIR}/calls.log"
  export GLAB_MOCK_USER="new-bot"
  mkdir -p "${GLAB_MOCK_DIR}"
  : > "${GLAB_MOCK_CALLS}"

  # shellcheck disable=SC1090
  MIGRATOR_SOURCED=1 source "${MIGRATOR_LIB}"
}

jqc() { jq -c "$@"; }

# ---------------------------------------------------------------------------
# mig_bool
# ---------------------------------------------------------------------------

@test "mig_bool: the literal 'true' maps to true" {
  run mig_bool true
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

@test "mig_bool: everything else maps to false" {
  run mig_bool false
  [ "${output}" = "false" ]
  run mig_bool ""
  [ "${output}" = "false" ]
  run mig_bool TRUE
  [ "${output}" = "false" ]
  run mig_bool
  [ "${output}" = "false" ]
}

# ---------------------------------------------------------------------------
# mig_urlenc
# ---------------------------------------------------------------------------

@test "mig_urlenc: encodes slashes and spaces" {
  run mig_urlenc "my-group/sub group"
  [ "${output}" = "my-group%2Fsub%20group" ]
}

@test "mig_urlenc: encodes the default dashboard title" {
  run mig_urlenc "Dependency Dashboard"
  [ "${output}" = "Dependency%20Dashboard" ]
}

@test "mig_urlenc: empty input yields empty output" {
  run mig_urlenc ""
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

# ---------------------------------------------------------------------------
# mig_validate_authors
# ---------------------------------------------------------------------------

@test "mig_validate_authors: keep_author only is valid" {
  run mig_validate_authors "new-bot" ""
  [ "${status}" -eq 0 ]
}

@test "mig_validate_authors: close_author only is valid" {
  run mig_validate_authors "" "old-bot"
  [ "${status}" -eq 0 ]
}

@test "mig_validate_authors: neither is valid (keep_author is defaulted later)" {
  run mig_validate_authors "" ""
  [ "${status}" -eq 0 ]
}

@test "mig_validate_authors: both is rejected" {
  run mig_validate_authors "new-bot" "old-bot"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"only one"* ]]
}

# ---------------------------------------------------------------------------
# mig_filter_dashboards
# ---------------------------------------------------------------------------

ISSUES='[
  {"iid":1,"title":"Dependency Dashboard"},
  {"iid":2,"title":"  Dependency Dashboard  "},
  {"iid":3,"title":"Dependency Dashboard (draft)"},
  {"iid":4,"title":"Renovate Dashboard"}
]'

@test "mig_filter_dashboards: keeps only exact (trimmed) title matches" {
  out="$(printf '%s' "${ISSUES}" | mig_filter_dashboards "Dependency Dashboard")"
  [ "$(echo "${out}" | jqc 'map(.iid)')" = "[1,2]" ]
}

@test "mig_filter_dashboards: honours a custom title" {
  out="$(printf '%s' "${ISSUES}" | mig_filter_dashboards "Renovate Dashboard")"
  [ "$(echo "${out}" | jqc 'map(.iid)')" = "[4]" ]
}

@test "mig_filter_dashboards: no match yields an empty array" {
  out="$(printf '%s' "${ISSUES}" | mig_filter_dashboards "Nope")"
  [ "$(echo "${out}" | jqc '.')" = "[]" ]
}

# ---------------------------------------------------------------------------
# mig_select_close
# ---------------------------------------------------------------------------

DBS='[
  {"iid":10,"author":{"username":"old-bot"}},
  {"iid":11,"author":{"username":"new-bot"}},
  {"iid":12,"author":{"username":"legacy-bot"}}
]'

@test "mig_select_close: keep-author mode closes every other author" {
  out="$(printf '%s' "${DBS}" | mig_select_close "new-bot" "")"
  [ "$(echo "${out}" | jqc 'map(.iid)|sort')" = "[10,12]" ]
}

@test "mig_select_close: close-author mode closes only the listed authors" {
  out="$(printf '%s' "${DBS}" | mig_select_close "" "old-bot, legacy-bot")"
  [ "$(echo "${out}" | jqc 'map(.iid)|sort')" = "[10,12]" ]
}

@test "mig_select_close: close-author mode ignores unknown authors" {
  out="$(printf '%s' "${DBS}" | mig_select_close "" "ghost-bot")"
  [ "$(echo "${out}" | jqc 'length')" = "0" ]
}

@test "mig_select_close: close_author wins when both are set" {
  out="$(printf '%s' "${DBS}" | mig_select_close "new-bot" "old-bot")"
  [ "$(echo "${out}" | jqc 'map(.iid)')" = "[10]" ]
}

@test "mig_select_close: tolerates an issue without an author" {
  out="$(printf '%s' '[{"iid":1},{"iid":2,"author":{"username":"new-bot"}}]' \
    | mig_select_close "new-bot" "")"
  [ "$(echo "${out}" | jqc 'map(.iid)')" = "[1]" ]
}

# ---------------------------------------------------------------------------
# mig_select_keep
# ---------------------------------------------------------------------------

@test "mig_select_keep: returns dashboards minus the to-close set, by iid" {
  run mig_select_keep '[{"iid":10},{"iid":11},{"iid":12}]' '[{"iid":10},{"iid":12}]'
  [ "${status}" -eq 0 ]
  [ "$(echo "${output}" | jqc 'map(.iid)')" = "[11]" ]
}

@test "mig_select_keep: an empty to-close set keeps everything" {
  run mig_select_keep '[{"iid":1},{"iid":2}]' '[]'
  [ "$(echo "${output}" | jqc 'map(.iid)')" = "[1,2]" ]
}

@test "mig_select_keep: closing all leaves an empty keep set" {
  run mig_select_keep '[{"iid":1}]' '[{"iid":1}]'
  [ "$(echo "${output}" | jqc '.')" = "[]" ]
}

# ---------------------------------------------------------------------------
# mig_collect_projects
# ---------------------------------------------------------------------------

@test "mig_collect_projects: group mode emits '<id>\\t<path>' lines" {
  echo '[{"id":1,"path_with_namespace":"grp/a"},{"id":2,"path_with_namespace":"grp/b"}]' \
    > "${GLAB_MOCK_DIR}/group-projects.json"

  run mig_collect_projects group grp "" false
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "$(printf '1\tgrp/a')" ]
  [ "${lines[1]}" = "$(printf '2\tgrp/b')" ]
  grep -q "include_subgroups=true" "${GLAB_MOCK_CALLS}"
  grep -q "archived=false" "${GLAB_MOCK_CALLS}"
}

@test "mig_collect_projects: group mode forwards archived=true" {
  echo '[]' > "${GLAB_MOCK_DIR}/group-projects.json"
  run mig_collect_projects group grp "" true
  [ "${status}" -eq 0 ]
  grep -q "archived=true" "${GLAB_MOCK_CALLS}"
}

@test "mig_collect_projects: projects mode resolves each entry, trimming spaces" {
  echo '{"id":9,"path_with_namespace":"x/y"}' > "${GLAB_MOCK_DIR}/project.json"
  run mig_collect_projects projects "" "x/y, a/b" false
  [ "${status}" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  grep -q "projects/x%2Fy" "${GLAB_MOCK_CALLS}"
  grep -q "projects/a%2Fb" "${GLAB_MOCK_CALLS}"
}

@test "mig_collect_projects: group mode requires a group" {
  run mig_collect_projects group "" "" false
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"requires 'group'"* ]]
}

@test "mig_collect_projects: projects mode requires a project list" {
  run mig_collect_projects projects "" "" false
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"requires 'projects'"* ]]
}

@test "mig_collect_projects: rejects an unknown scope" {
  run mig_collect_projects bogus "" "" false
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unknown scope"* ]]
}

# ---------------------------------------------------------------------------
# mig_list_dashboards
# ---------------------------------------------------------------------------

@test "mig_list_dashboards: searches by title and filters to exact matches" {
  cat > "${GLAB_MOCK_DIR}/issues-5.json" <<'JSON'
[{"iid":1,"title":"Dependency Dashboard"},
 {"iid":2,"title":"Dependency Dashboard (WIP)"}]
JSON
  run mig_list_dashboards 5 "Dependency Dashboard"
  [ "${status}" -eq 0 ]
  [ "$(echo "${output}" | jqc 'map(.iid)')" = "[1]" ]
  grep -q "state=opened" "${GLAB_MOCK_CALLS}"
  grep -q "in=title" "${GLAB_MOCK_CALLS}"
  grep -q "search=Dependency%20Dashboard" "${GLAB_MOCK_CALLS}"
}

@test "mig_list_dashboards: a project with no issues yields an empty array" {
  run mig_list_dashboards 404 "Dependency Dashboard"
  [ "${status}" -eq 0 ]
  [ "$(echo "${output}" | jqc '.')" = "[]" ]
}

# ---------------------------------------------------------------------------
# mig_close_issue
# ---------------------------------------------------------------------------

@test "mig_close_issue: issues a PUT that closes the issue" {
  run mig_close_issue 7 42
  [ "${status}" -eq 0 ]
  grep -q "projects/7/issues/42" "${GLAB_MOCK_CALLS}"
  grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

# ---------------------------------------------------------------------------
# mig_pick_clone_source
# ---------------------------------------------------------------------------

@test "mig_pick_clone_source: picks the most recently updated dashboard" {
  src="$(printf '%s' '[
    {"iid":10,"author":{"username":"old-bot"},"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-02-01T00:00:00Z"},
    {"iid":13,"author":{"username":"older-bot"},"created_at":"2023-01-01T00:00:00Z","updated_at":"2025-07-09T00:00:00Z"}
  ]' | mig_pick_clone_source)"
  [ "${src}" = "13|older-bot|2025-07-09" ]
}

@test "mig_pick_clone_source: falls back to created_at when updated_at is absent" {
  src="$(printf '%s' '[
    {"iid":10,"author":{"username":"old-bot"},"created_at":"2024-01-01T00:00:00Z"},
    {"iid":11,"author":{"username":"old-bot"},"created_at":"2024-09-01T00:00:00Z"}
  ]' | mig_pick_clone_source)"
  [ "${src}" = "11|old-bot|2024-09-01" ]
}

# ---------------------------------------------------------------------------
# mig_clone_issue
# ---------------------------------------------------------------------------

@test "mig_clone_issue: POSTs to the clone endpoint and returns the new iid" {
  export GLAB_MOCK_CLONE_IID=777
  run mig_clone_issue 3 10 true
  [ "${status}" -eq 0 ]
  [ "${output}" = "777" ]
  grep -q "projects/3/issues/10/clone" "${GLAB_MOCK_CALLS}"
  grep -q "with_notes=true" "${GLAB_MOCK_CALLS}"
  grep -q "to_project_id=3" "${GLAB_MOCK_CALLS}"
  grep -q "POST" "${GLAB_MOCK_CALLS}"
}

@test "mig_clone_issue: forwards with_notes=false" {
  run mig_clone_issue 3 10 false
  [ "${status}" -eq 0 ]
  grep -q "with_notes=false" "${GLAB_MOCK_CALLS}"
}

# ---------------------------------------------------------------------------
# mig_current_user
# ---------------------------------------------------------------------------

@test "mig_current_user: returns the authenticated username" {
  export GLAB_MOCK_USER="renovate-sa"
  run mig_current_user
  [ "${status}" -eq 0 ]
  [ "${output}" = "renovate-sa" ]
}

# ---------------------------------------------------------------------------
# main() end-to-end, against the mock
# ---------------------------------------------------------------------------

run_main() {
  run env \
    MIGRATOR_GITLAB_URL="https://gitlab.example.com" \
    MIGRATOR_TOKEN_VARIABLE="RENOVATE_TOKEN" RENOVATE_TOKEN="s3cret" \
    MIGRATOR_TITLE="Dependency Dashboard" \
    MIGRATOR_SCOPE="group" MIGRATOR_GROUP="grp" MIGRATOR_PROJECTS="" \
    MIGRATOR_KEEP_AUTHOR="${KEEP:-}" MIGRATOR_CLOSE_AUTHOR="${CLOSE:-}" \
    MIGRATOR_CLONE="${CLONE:-false}" \
    MIGRATOR_CLONE_WITH_NOTES="${CLONE_WITH_NOTES:-true}" \
    MIGRATOR_INCLUDE_ARCHIVED="false" \
    MIGRATOR_ALLOW_SINGLE="${ALLOW_SINGLE:-false}" \
    MIGRATOR_FORCE_CLOSE_ALL="${FORCE_CLOSE_ALL:-false}" \
    MIGRATOR_EXECUTE="${EXECUTE:-false}" \
    CI_SERVER_HOST="gitlab.example.com" \
    bash "${MIGRATOR_LIB}"
}

# A single project 'grp/a' (id 1) whose open dashboards are the given JSON.
fixture_project() {
  echo '[{"id":1,"path_with_namespace":"grp/a"}]' > "${GLAB_MOCK_DIR}/group-projects.json"
  cat > "${GLAB_MOCK_DIR}/issues-1.json"
}

@test "main: dry-run reports the orphan but closes nothing" {
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"},
 {"iid":11,"title":"Dependency Dashboard","author":{"username":"new-bot"},"created_at":"2025-06-01T00:00:00Z"}]
JSON
  KEEP="new-bot" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[DRY-RUN]"* ]]
  [[ "${output}" == *"close(dry)  !10"* ]]
  [[ "${output}" == *"keep        !11"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: --execute closes the orphaned dashboard (bot already owns one)" {
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"},
 {"iid":11,"title":"Dependency Dashboard","author":{"username":"new-bot"},"created_at":"2025-06-01T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="true" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"closed      !10"* ]]
  grep -q "projects/1/issues/10" "${GLAB_MOCK_CALLS}"
  grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
  ! grep -q "issues/11?state_event=close" "${GLAB_MOCK_CALLS}"
  ! grep -q "clone" "${GLAB_MOCK_CALLS}"
}

@test "main: a lone correct dashboard is left untouched" {
  fixture_project <<'JSON'
[{"iid":11,"title":"Dependency Dashboard","author":{"username":"new-bot"},"created_at":"2025-06-01T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="true" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Projects touched: 0"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
  ! grep -q "clone" "${GLAB_MOCK_CALLS}"
}

@test "main: clone disabled -> a lone orphan is left untouched" {
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="false" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Projects touched: 0"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: clone disabled -> refuses to close all without force_close_all" {
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"},
 {"iid":13,"title":"Dependency Dashboard","author":{"username":"older-bot"},"created_at":"2023-01-02T00:00:00Z"}]
JSON
  CLOSE="old-bot, older-bot" CLONE="false" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would close ALL 2 dashboards"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: clones a lone orphan to the current bot, then closes it" {
  export GLAB_MOCK_CLONE_IID=900
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z","updated_at":"2025-05-01T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="true" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cloned      !10 -> !900"* ]]
  [[ "${output}" == *"now owned by @new-bot"* ]]
  [[ "${output}" == *"closed      !10"* ]]
  grep -q "projects/1/issues/10/clone" "${GLAB_MOCK_CALLS}"
  grep -q "with_notes=true" "${GLAB_MOCK_CALLS}"
  # clone happens before the close
  clone_line="$(grep -n 'issues/10/clone' "${GLAB_MOCK_CALLS}" | cut -d: -f1)"
  close_line="$(grep -n 'issues/10?state_event=close' "${GLAB_MOCK_CALLS}" | cut -d: -f1)"
  [ "${clone_line}" -lt "${close_line}" ]
}

@test "main: clone dry-run announces the clone but writes nothing" {
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"clone(dry)  !10 -> new dashboard owned by @new-bot"* ]]
  [[ "${output}" == *"to clone: 1"* ]]
  ! grep -qE "clone\?|state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: forwards clone_with_notes=false" {
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="true" CLONE_WITH_NOTES="false" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  grep -q "with_notes=false" "${GLAB_MOCK_CALLS}"
}

@test "main: a failed clone leaves the project untouched and fails the job" {
  export GLAB_MOCK_CLONE_IID=null
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"}]
JSON
  KEEP="new-bot" CLONE="true" EXECUTE="true" run_main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAILED clone !10"* ]]
  [[ "${output}" == *"errors: 1"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: keep_author defaults to the authenticated user" {
  export GLAB_MOCK_USER="renovate-sa"
  fixture_project <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"ex-renovate"},"created_at":"2024-01-02T00:00:00Z"},
 {"iid":11,"title":"Dependency Dashboard","author":{"username":"renovate-sa"},"created_at":"2025-06-01T00:00:00Z"}]
JSON
  CLONE="true" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"keep_author defaulted to the authenticated user '@renovate-sa'"* ]]
  [[ "${output}" == *"closed      !10"* ]]
  [[ "${output}" == *"keep        !11"* ]]
}

@test "main: exits non-zero when both keep_author and close_author are set" {
  echo '[]' > "${GLAB_MOCK_DIR}/group-projects.json"
  KEEP="new-bot" CLOSE="old-bot" run_main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"only one"* ]]
}
