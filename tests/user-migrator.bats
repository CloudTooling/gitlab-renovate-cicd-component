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

@test "mig_validate_authors: neither is rejected" {
  run mig_validate_authors "" ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Set one of keep_author / close_author"* ]]
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
# main() end-to-end, against the mock
# ---------------------------------------------------------------------------

run_main() {
  run env \
    MIGRATOR_GITLAB_URL="https://gitlab.example.com" \
    MIGRATOR_TOKEN_VARIABLE="RENOVATE_TOKEN" RENOVATE_TOKEN="s3cret" \
    MIGRATOR_TITLE="Dependency Dashboard" \
    MIGRATOR_SCOPE="group" MIGRATOR_GROUP="grp" MIGRATOR_PROJECTS="" \
    MIGRATOR_KEEP_AUTHOR="${KEEP:-}" MIGRATOR_CLOSE_AUTHOR="${CLOSE:-}" \
    MIGRATOR_INCLUDE_ARCHIVED="false" \
    MIGRATOR_ALLOW_SINGLE="${ALLOW_SINGLE:-false}" \
    MIGRATOR_FORCE_CLOSE_ALL="${FORCE_CLOSE_ALL:-false}" \
    MIGRATOR_EXECUTE="${EXECUTE:-false}" \
    CI_SERVER_HOST="gitlab.example.com" \
    bash "${MIGRATOR_LIB}"
}

@test "main: dry-run reports the orphan but closes nothing" {
  echo '[{"id":1,"path_with_namespace":"grp/a"}]' > "${GLAB_MOCK_DIR}/group-projects.json"
  cat > "${GLAB_MOCK_DIR}/issues-1.json" <<'JSON'
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

@test "main: --execute closes the orphaned dashboard" {
  echo '[{"id":1,"path_with_namespace":"grp/a"}]' > "${GLAB_MOCK_DIR}/group-projects.json"
  cat > "${GLAB_MOCK_DIR}/issues-1.json" <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"},
 {"iid":11,"title":"Dependency Dashboard","author":{"username":"new-bot"},"created_at":"2025-06-01T00:00:00Z"}]
JSON
  KEEP="new-bot" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"closed      !10"* ]]
  grep -q "projects/1/issues/10" "${GLAB_MOCK_CALLS}"
  grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
  ! grep -q "issues/11?state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: a lone correct dashboard is left untouched" {
  echo '[{"id":1,"path_with_namespace":"grp/a"}]' > "${GLAB_MOCK_DIR}/group-projects.json"
  cat > "${GLAB_MOCK_DIR}/issues-1.json" <<'JSON'
[{"iid":11,"title":"Dependency Dashboard","author":{"username":"new-bot"},"created_at":"2025-06-01T00:00:00Z"}]
JSON
  KEEP="new-bot" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Projects touched: 0"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: refuses to close the last dashboard without force_close_all" {
  echo '[{"id":1,"path_with_namespace":"grp/a"}]' > "${GLAB_MOCK_DIR}/group-projects.json"
  cat > "${GLAB_MOCK_DIR}/issues-1.json" <<'JSON'
[{"iid":10,"title":"Dependency Dashboard","author":{"username":"old-bot"},"created_at":"2024-01-02T00:00:00Z"},
 {"iid":13,"title":"Dependency Dashboard","author":{"username":"older-bot"},"created_at":"2023-01-02T00:00:00Z"}]
JSON
  CLOSE="old-bot, older-bot" EXECUTE="true" run_main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would close ALL 2 dashboards"* ]]
  ! grep -q "state_event=close" "${GLAB_MOCK_CALLS}"
}

@test "main: exits non-zero when the author selection is invalid" {
  echo '[]' > "${GLAB_MOCK_DIR}/group-projects.json"
  run_main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Set one of keep_author / close_author"* ]]
}
