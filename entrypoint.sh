#!/bin/sh
set -e

if [ -n "${GITHUB_WORKSPACE}" ] ; then
  cd "${GITHUB_WORKSPACE}/${INPUT_WORKDIR}" || exit
  git config --global --add safe.directory "${GITHUB_WORKSPACE}" || exit 1
fi

export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"

# Display version information for debugging
echo "=== Environment Information ==="
java -version
pmd --version
echo "Reviewdog location: $(which reviewdog || echo 'not found in PATH')"
reviewdog --version || echo "Warning: reviewdog not executable"
echo "PATH: $PATH"
echo "==============================="

# Validate source directory exists
if [ ! -d "${INPUT_SRC_PATH}" ]; then
  echo "Error: Source directory '${INPUT_SRC_PATH}' not found."
  echo "Please verify the 'src_path' input parameter."
  exit 1
fi

# Validate ruleset (if it's a file path)
if [ -f "${INPUT_RULESETS_PATH}" ]; then
  echo "Using custom ruleset: ${INPUT_RULESETS_PATH}"
elif echo "${INPUT_RULESETS_PATH}" | grep -q "^category/"; then
  echo "Using built-in ruleset: ${INPUT_RULESETS_PATH}"
elif echo "${INPUT_RULESETS_PATH}" | grep -q "^rulesets/"; then
  echo "Warning: You are using legacy ruleset path '${INPUT_RULESETS_PATH}'."
  echo "PMD 7.x requires category-based paths like 'category/java/bestpractices.xml'."
  echo "See migration guide: https://docs.pmd-code.org/latest/pmd_userdocs_migrating_to_pmd7.html"
  echo "Attempting to continue with provided path..."
fi

# Setup PMD cache if specified
CACHE_OPT=""
if [ -n "${INPUT_PMD_CACHE}" ]; then
  echo "PMD cache enabled: ${INPUT_PMD_CACHE}"
  # PMD cache requires a file path, not a directory
  # Create parent directory if it doesn't exist
  CACHE_DIR=$(dirname "${INPUT_PMD_CACHE}")
  mkdir -p "${CACHE_DIR}" || {
    echo "Warning: Failed to create cache directory. Continuing without cache."
  }
  if [ -d "${CACHE_DIR}" ]; then
    chmod 777 "${CACHE_DIR}" 2>/dev/null || true
    CACHE_OPT="--cache ${INPUT_PMD_CACHE}"
    echo "✓ PMD cache file will be created at ${INPUT_PMD_CACHE}"
  else
    echo "✗ PMD cache directory creation failed"
  fi
else
  echo "PMD cache is disabled (INPUT_PMD_CACHE is empty)"
fi

# Display safe runtime information for debugging
echo "=== Runtime Information ==="
echo "Workspace: ${GITHUB_WORKSPACE:-not set}"
echo "Workdir: ${INPUT_WORKDIR}"
echo "Source path: ${INPUT_SRC_PATH}"
echo "Ruleset path: ${INPUT_RULESETS_PATH}"
echo "PMD cache: ${INPUT_PMD_CACHE:-disabled}"
echo "==========================="

# Execute PMD with error handling
echo "Running PMD analysis..."
# shellcheck disable=SC2086
pmd check -d "${INPUT_SRC_PATH}" -R "${INPUT_RULESETS_PATH}" ${CACHE_OPT} -f emacs --no-progress \
  | reviewdog -efm="%f:%l: %m" \
      -name="${INPUT_TOOL_NAME}" \
      -reporter="${INPUT_REPORTER:-github-pr-check}" \
      -filter-mode="${INPUT_FILTER_MODE}" \
      -fail-level="${INPUT_FAIL_LEVEL}" \
      -level="${INPUT_LEVEL}" \
      ${INPUT_REVIEWDOG_FLAGS}
