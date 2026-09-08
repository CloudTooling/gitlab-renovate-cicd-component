#!/usr/bin/env bash
# Extract the inline `script:` block of a job from a GitLab CI/CD component
# template and print it to stdout. Depends only on awk (busybox awk is fine),
# so it runs in the same minimal images the tests use.
#
# Usage: extract.sh <template.yml> "<job name>"
set -euo pipefail

file="${1:?template path required}"
job="${2:?job name required}"

awk -v job="${job}:" '
  # Top-level job key (column 0).
  $0 == job { in_job = 1; next }
  # Any other top-level key ends the job.
  in_job && /^[^[:space:]]/ { in_job = 0 }

  in_job && $0 ~ /^  script:/ { in_script = 1; next }
  in_script && $0 ~ /^    - [|>]/ { in_block = 1; next }

  in_block {
    if ($0 == "") { print ""; next }
    if ($0 ~ /^      /) { print substr($0, 7); next }
    # Dedent below the block indentation -> block finished.
    exit
  }
' "${file}"
