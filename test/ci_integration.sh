#!/usr/bin/env bash

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Always clean up.
DELETE_AT_EXIT="$(mktemp -d)"
finish() {
  local rv=$?
  echo 'BEGIN: finish() trap handler' >&2
  if [[ "${rv}" -ne 0 ]]; then
    echo 'BEGIN: .kitchen/logs/kitchen.log'
    cat .kitchen/logs/kitchen.log
    echo 'END: .kitchen/logs/kitchen.log'
    echo 'BEGIN: kitchen diagnose --all'
    kitchen diagnose --all
    echo 'END: kitchen diagnose --all'
  fi
  #kitchen destroy "$SUITE"
  [[ -d "${DELETE_AT_EXIT}" ]] && rm -rf "${DELETE_AT_EXIT}"
  echo 'END: finish() trap handler' >&2
  exit "${rv}"
}

# Map the input parameters provided by Concourse CI, or whatever mechanism is
# running the tests to Terraform input variables.  Also setup credentials for
# use with kitchen-terraform, inspec, and gcloud.
setup_environment() {
  local tmpfile
  tmpfile="$(mktemp)"
  echo "${SERVICE_ACCOUNT_JSON}" > "${tmpfile}"

  # gcloud variables
  export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="${tmpfile}"
  # Application default credentials (Terraform google provider and inspec-gcp)
  export GOOGLE_APPLICATION_CREDENTIALS="${tmpfile}"

  # Terraform variables
  export TF_VAR_fixture_project_id="$PROJECT_ID"
  export TF_VAR_billing_account="${BILLING_ACCOUNT_ID}"
  export TF_VAR_org_id="${ORG_ID}"
  export TF_VAR_parent_id="${FOLDER_ID}"
  export TF_VAR_mode="additive"
}

main() {
  export SUITE="${SUITE:-}"

  set -eu
  # Setup trap handler to auto-cleanup
  export TMPDIR="${DELETE_AT_EXIT}"
  trap finish EXIT

  # Setup environment variables
  setup_environment

  set -x

  # Execute the test lifecycle
  if [[ -f "test/fixtures/full/iam.tf" ]]; then
    mv "test/fixtures/full/iam.tf" "test/fixtures/full/iam.tf.mv"
  fi

  kitchen create "$SUITE"
  kitchen converge "$SUITE" || true
  # First converge fails, give delay before the 2-nd attempt,
  # to allow activation of the api being finished
  sleep 30
  kitchen converge "$SUITE"

  # add test fixtures and apply them (for the details see the module's readme page)
  cp "test/fixtures/full/iam.tf.mv" "test/fixtures/full/iam.tf"
  kitchen create "$SUITE"
  kitchen converge "$SUITE"
  kitchen verify "$SUITE"
}

# if script is being executed and not sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

