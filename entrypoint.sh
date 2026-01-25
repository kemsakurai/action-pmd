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
  mkdir -p "${INPUT_PMD_CACHE}" || {
    echo "Warning: Failed to create cache directory. Continuing without cache."
  }
  if [ -d "${INPUT_PMD_CACHE}" ]; then
    chmod 777 "${INPUT_PMD_CACHE}" 2>/dev/null || true
    CACHE_OPT="--cache ${INPUT_PMD_CACHE}"
  fi
fi

printenv
ls

# Execute PMD with error handling
echo "Running PMD analysis..."
exec /bin/sh -c "pmd check -d \"${INPUT_SRC_PATH}\" -R \"${INPUT_RULESETS_PATH}\" ${CACHE_OPT} -f emacs || {
  echo \"Error: PMD execution failed.\"
  echo \"Common issues:\"
  echo \"  - Ruleset not found: Verify 'rulesets_path' parameter\"
  echo \"  - Invalid Java source: Check Java syntax in source files\"
  echo \"  - PMD 7.x compatibility: Use category-based rulesets (e.g., 'category/java/bestpractices.xml')\"
  echo \"See documentation: https://docs.pmd-code.org/latest/\"
  exit 1
}" | reviewdog -efm="%f:%l: %m" \
      -name="${INPUT_TOOL_NAME}" \
      -reporter="${INPUT_REPORTER:-github-pr-check}" \
      -filter-mode="${INPUT_FILTER_MODE}" \
      -fail-on-error="${INPUT_FAIL_ON_ERROR}" \
      -level="${INPUT_LEVEL}" \
      ${INPUT_REVIEWDOG_FLAGS}
