#!/bin/sh
set -e

if [ -n "${GITHUB_WORKSPACE}" ] ; then
  cd "${GITHUB_WORKSPACE}/${INPUT_WORKDIR}" || exit
  git config --global --add safe.directory "${GITHUB_WORKSPACE}" || exit 1
fi

export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"

printenv
ls

# fetch pmd of a requested version
wget -q "https://github.com/pmd/pmd/releases/download/pmd_releases%2F6.51.0/pmd-bin-6.51.0.zip"
unzip pmd-bin-6.51.0.zip
alias pmd="./pmd-bin-6.51.0/bin/run.sh pmd"
exec pmd -d {INPUT_SRC_PATH} -R {INPUT_RULESETS_PATH} -f emacs \
  | reviewdog -efm="%f:%l: %m" \
      -name="PMD" \
      -reporter="${INPUT_REPORTER:-github-pr-check}" \
      -filter-mode="${INPUT_FILTER_MODE}" \
      -fail-on-error="${INPUT_FAIL_ON_ERROR}" \
      -level="${INPUT_LEVEL}" \
      ${INPUT_REVIEWDOG_FLAGS}
