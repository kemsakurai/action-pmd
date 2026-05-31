#!/bin/sh
# Run PMD and report findings through reviewdog in GitHub Actions.

set -e

info() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

err() {
  printf 'Error: %s\n' "$*" >&2
}

validate_required_inputs() {
  if [ -z "${INPUT_SRC_PATH:-}" ]; then
    err "'src_path' input is empty."
    return 1
  fi

  if [ -z "${INPUT_RULESETS_PATH:-}" ]; then
    err "'rulesets_path' input is empty."
    return 1
  fi

  if [ -z "${INPUT_LEVEL:-}" ]; then
    err "'level' input is empty."
    return 1
  fi

  if [ -z "${INPUT_FILTER_MODE:-}" ]; then
    err "'filter_mode' input is empty."
    return 1
  fi

  if [ -z "${INPUT_FAIL_LEVEL:-}" ]; then
    err "'fail_level' input is empty."
    return 1
  fi
}

setup_workspace() {
  if [ -n "${GITHUB_WORKSPACE:-}" ]; then
    if ! cd "${GITHUB_WORKSPACE}/${INPUT_WORKDIR}"; then
      err "Unable to cd to workdir '${GITHUB_WORKSPACE}/${INPUT_WORKDIR}'."
      return 1
    fi

    if ! git config --global --add safe.directory "${GITHUB_WORKSPACE}"; then
      err "Failed to mark '${GITHUB_WORKSPACE}' as a safe git directory."
      return 1
    fi
  fi
}

print_environment_info() {
  info '=== Environment Information ==='
  java -version
  pmd --version

  if command -v reviewdog >/dev/null 2>&1; then
    info "Reviewdog location: $(command -v reviewdog)"
    reviewdog --version
  else
    warn 'reviewdog not found in PATH'
  fi

  info "PATH: ${PATH}"
  info '==============================='
}

validate_paths() {
  if [ ! -d "${INPUT_SRC_PATH}" ]; then
    err "Source directory '${INPUT_SRC_PATH}' not found."
    err "Please verify the 'src_path' input parameter."
    return 1
  fi

  if [ -f "${INPUT_RULESETS_PATH}" ]; then
    info "Using custom ruleset: ${INPUT_RULESETS_PATH}"
    return 0
  fi

  case "${INPUT_RULESETS_PATH}" in
    category/*)
      info "Using built-in ruleset: ${INPUT_RULESETS_PATH}"
      ;;
    rulesets/*)
      warn "You are using legacy ruleset path '${INPUT_RULESETS_PATH}'."
      warn "PMD 7.x requires paths like 'category/java/bestpractices.xml'."
      warn 'See migration guide: https://docs.pmd-code.org/latest/pmd_userdocs_migrating_to_pmd7.html'
      warn 'Attempting to continue with provided path.'
      ;;
    *)
      warn "Ruleset path '${INPUT_RULESETS_PATH}' is neither an existing file nor category/rulesets prefix."
      ;;
  esac
}

setup_cache() {
  CACHE_OPT=''

  if [ -z "${INPUT_PMD_CACHE:-}" ]; then
    info 'PMD cache is disabled (INPUT_PMD_CACHE is empty)'
    return 0
  fi

  info "PMD cache enabled: ${INPUT_PMD_CACHE}"
  CACHE_DIR="$(dirname "${INPUT_PMD_CACHE}")"

  if ! mkdir -p "${CACHE_DIR}"; then
    warn 'Failed to create cache directory. Continuing without cache.'
    return 0
  fi

  if [ -d "${CACHE_DIR}" ]; then
    chmod 777 "${CACHE_DIR}" 2>/dev/null || true
    CACHE_OPT="--cache ${INPUT_PMD_CACHE}"
    info "PMD cache file will be created at ${INPUT_PMD_CACHE}"
  else
    warn 'PMD cache directory creation failed. Continuing without cache.'
  fi
}

print_runtime_info() {
  info '=== Runtime Information ==='
  info "Workspace: ${GITHUB_WORKSPACE:-not set}"
  info "Workdir: ${INPUT_WORKDIR}"
  info "Source path: ${INPUT_SRC_PATH}"
  info "Ruleset path: ${INPUT_RULESETS_PATH}"
  info "PMD cache: ${INPUT_PMD_CACHE:-disabled}"
  info '==========================='
}

run_analysis() {
  info 'Running PMD analysis...'

  # INPUT_REVIEWDOG_FLAGS is intentionally word-split to support multiple flags.
  # shellcheck disable=SC2086
  pmd check -d "${INPUT_SRC_PATH}" -R "${INPUT_RULESETS_PATH}" ${CACHE_OPT} -f emacs --no-progress \
    | reviewdog -efm='%f:%l: %m' \
        -name="${INPUT_TOOL_NAME}" \
        -reporter="${INPUT_REPORTER:-github-pr-check}" \
        -filter-mode="${INPUT_FILTER_MODE}" \
        -fail-level="${INPUT_FAIL_LEVEL}" \
        -level="${INPUT_LEVEL}" \
        ${INPUT_REVIEWDOG_FLAGS}
}

main() {
  export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN:-}"

  validate_required_inputs
  setup_workspace
  print_environment_info
  validate_paths
  setup_cache
  print_runtime_info
  run_analysis
}

main "$@"
