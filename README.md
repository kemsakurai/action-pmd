# action-pmd

[![Test](https://github.com/kemsakurai/action-pmd/workflows/Test/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3ATest)
[![reviewdog](https://github.com/kemsakurai/action-pmd/workflows/reviewdog/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Areviewdog)
[![depup](https://github.com/kemsakurai/action-pmd/workflows/depup/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Adepup)
[![release](https://github.com/kemsakurai/action-pmd/workflows/release/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Arelease)
[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/kemsakurai/action-pmd?logo=github&sort=semver)](https://github.com/kemsakurai/action-pmd/releases)
[![action-bumpr supported](https://img.shields.io/badge/bumpr-supported-ff69b4?logo=github&link=https://github.com/haya14busa/action-bumpr)](https://github.com/haya14busa/action-bumpr)

This is a GitHub action to run [PMD](https://github.com/pmd/pmd) check on your Java code and report status via [reviewdog](https://github.com/reviewdog/reviewdog) on pull request.

## Example

An example of how the reported pmd violations will look like on pull request is shown below ([link to PR](https://github.com/kemsakurai/mixcloud-java-api/pull/5)):

![PR comment with violation](https://user-images.githubusercontent.com/10411936/199019548-266be1ad-4927-4d4c-94ce-c3e4feeb9f98.png)

## Inputs    
```yaml
inputs:
  github_token:
    description: 'GITHUB_TOKEN'
    default: '${{ github.token }}'
  workdir:
    description: 'Working directory relative to the root directory.'
    default: '.'
  ### Flags for reviewdog ###
  level:
    description: 'Report level for reviewdog [info,warning,error]'
    default: 'error'
  reporter:
    description: 'Reporter of reviewdog command [github-pr-check,github-pr-review].'
    default: 'github-pr-check'
  filter_mode:
    description: |
      Filtering mode for the reviewdog command [added,diff_context,file,nofilter].
      Default is added.
    default: 'added'
  fail_on_error:
    description: |
      Exit code for reviewdog when errors are found [true,false]
      Default is `false`.
    default: 'false'
  tool_name:
    description: 'Tool name to use for reviewdog reporter'
    default: 'pmd'
  reviewdog_flags:
    description: 'Additional reviewdog flags'
    default: ''
  ### Flags for PMD ###
  src_path:
    description: 'Specify the directory where the sources to be analyzed are stored. Default is `src/main/java`.'
    default: 'src/main/java'
  rulesets_path:
    description: 'Specify the path of the PMD rule set. Default is `rulesets/java/quickstart.xml`.'
    default: 'rulesets/java/quickstart.xml'
```

## Usage

```yaml
name: pmd
on: [pull_request]
jobs:
  pmd_job:
    runs-on: ubuntu-latest
    name: PMD job
    steps:
    - name: Checkout
      uses: actions/checkout@v2
    - name: Run PMD
      uses: kemsakurai/action-pmd@master
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        reporter: 'github-pr-review'
        tool_name: 'pmd_reviewdog'
```
