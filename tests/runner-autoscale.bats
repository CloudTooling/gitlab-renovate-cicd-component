#!/usr/bin/env bats
#
# Tests for the child pipeline generation in the `Generate Matrix` job of
# templates/runner-autoscale.yml.
#
# The job script is extracted from the component YAML, the `$[[ inputs.* ]]`
# placeholders are replaced the way GitLab interpolates them into a string
# and the script is run against a fixed groups.txt.
#
# GitLab does NOT render array inputs as JSON when they are embedded in a
# string: hashes come out as Ruby hashes, e.g. `[{:project=>"a/b"}]` (or
# `[{project: "a/b"}]` with Ruby >= 3.4). The fixtures below use these forms.

setup_file() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO_ROOT
  export MATRIX_SCRIPT="${BATS_FILE_TMPDIR}/generate-matrix.sh"
  # block 2: the `- |` item after the `- >` curl call
  bash "${REPO_ROOT}/tests/helpers/extract.sh" \
    "${REPO_ROOT}/templates/runner-autoscale.yml" "Generate Matrix" 2 \
    > "${MATRIX_SCRIPT}"
  grep -q 'child-pipeline.yml' "${MATRIX_SCRIPT}"
}

setup() {
  cd "${BATS_TEST_TMPDIR}"
  printf 'group-a\ngroup-b\n' > groups.txt
  export RENOVATE_IMAGE="renovate:test"
  export INPUT_before_script='[]'
  export INPUT_child_include='[]'
  export INPUT_child_extends='[]'
}

# Replace `$[[ inputs.<name> ]]` with $INPUT_<name> and run the script like
# the GitLab runner does (errexit + pipefail).
generate() {
  awk '
    {
      while (match($0, /\$\[\[ inputs\.[a-z_]+ \]\]/)) {
        name = substr($0, RSTART + 11, RLENGTH - 14)
        $0 = substr($0, 1, RSTART - 1) ENVIRON["INPUT_" name] substr($0, RSTART + RLENGTH)
      }
      print
    }
  ' "${MATRIX_SCRIPT}" > rendered.sh
  ! grep -n '\$\[\[' rendered.sh
  run bash -eo pipefail rendered.sh
}

# Print the flow value of a top-level/job key of child-pipeline.yml.
value_of() {
  sed -n "s/^ *$1: //p" child-pipeline.yml
}

assert_success() {
  [ "${status}" -eq 0 ]
  # jq errors inside $(...) do not always fail the script
  [[ "${output}" != *"parse error"* ]]
}

# ---------------------------------------------------------------------------
# defaults
# ---------------------------------------------------------------------------

@test "defaults: no include and no extends are generated" {
  generate
  assert_success
  ! grep -q '^include:' child-pipeline.yml
  ! grep -q 'extends:' child-pipeline.yml
  grep -q '^  before_script: \[\]$' child-pipeline.yml
}

@test "defaults: groups are rendered into the matrix" {
  generate
  assert_success
  grep -q '^      - GROUP: \[group-a, group-b\]$' child-pipeline.yml
  grep -q '^  image: renovate:test$' child-pipeline.yml
}

# ---------------------------------------------------------------------------
# child_include
# ---------------------------------------------------------------------------

expected_include='[{"project":"common/gitlab-ci/helpers","ref":"main","file":".gitlab-ci/include.yml"}]'

@test "child_include: Ruby hash with symbol keys (:key=>)" {
  INPUT_child_include='[{:project=>"common/gitlab-ci/helpers", :ref=>"main", :file=>".gitlab-ci/include.yml"}]'
  generate
  assert_success
  [ "$(value_of include)" = "${expected_include}" ]
}

@test "child_include: Ruby >= 3.4 hash (key: value)" {
  INPUT_child_include='[{project: "common/gitlab-ci/helpers", ref: "main", file: ".gitlab-ci/include.yml"}]'
  generate
  assert_success
  [ "$(value_of include)" = "${expected_include}" ]
}

@test "child_include: Ruby hash with string keys (\"key\"=>)" {
  INPUT_child_include='[{"project"=>"common/gitlab-ci/helpers", "ref"=>"main", "file"=>".gitlab-ci/include.yml"}]'
  generate
  assert_success
  [ "$(value_of include)" = "${expected_include}" ]
}

@test "child_include: JSON input is kept as is" {
  INPUT_child_include="${expected_include}"
  generate
  assert_success
  [ "$(value_of include)" = "${expected_include}" ]
}

@test "child_include: nested file list and multiple entries" {
  INPUT_child_include='[{:project=>"a/b", :file=>["x.yml", "y.yml"]}, {:local=>"ci/proxy.yml"}]'
  generate
  assert_success
  [ "$(value_of include)" = '[{"project":"a/b","file":["x.yml","y.yml"]},{"local":"ci/proxy.yml"}]' ]
}

@test "child_include: values containing colons are not touched" {
  INPUT_child_include='[{:remote=>"https://example.com/ci/include.yml"}]'
  generate
  assert_success
  [ "$(value_of include)" = '[{"remote":"https://example.com/ci/include.yml"}]' ]
}

# ---------------------------------------------------------------------------
# child_extends / before_script
# ---------------------------------------------------------------------------

@test "child_extends: hidden jobs are added to the check job" {
  INPUT_child_extends='[".proxy_setup", ".docker_login"]'
  generate
  assert_success
  [ "$(value_of extends)" = '[".proxy_setup",".docker_login"]' ]
}

@test "before_script: entries become a YAML list of the check job" {
  INPUT_before_script='["echo one", "echo two"]'
  generate
  assert_success
  grep -A2 '^  before_script:$' child-pipeline.yml | grep -q '^    - echo two$'
}

# ---------------------------------------------------------------------------
# generated document
# ---------------------------------------------------------------------------

@test "child pipeline: include is top-level and extends belongs to check" {
  INPUT_child_include='[{:local=>"ci/proxy.yml"}]'
  INPUT_child_extends='[".proxy_setup"]'
  generate
  assert_success
  # include in column 0, extends indented with the check job keys
  grep -q '^include: ' child-pipeline.yml
  grep -q '^  extends: ' child-pipeline.yml
  # include/extends values must be valid JSON (and therefore valid YAML)
  value_of include | jq -e . > /dev/null
  value_of extends | jq -e . > /dev/null
}
