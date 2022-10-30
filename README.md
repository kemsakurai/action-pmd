# action-template

<!-- TODO: replace kemsakurai/action-pmd with your repo name -->
[![Test](https://github.com/kemsakurai/action-pmd/workflows/Test/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3ATest)
[![reviewdog](https://github.com/kemsakurai/action-pmd/workflows/reviewdog/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Areviewdog)
[![depup](https://github.com/kemsakurai/action-pmd/workflows/depup/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Adepup)
[![release](https://github.com/kemsakurai/action-pmd/workflows/release/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Arelease)
[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/kemsakurai/action-pmd?logo=github&sort=semver)](https://github.com/kemsakurai/action-pmd/releases)
[![action-bumpr supported](https://img.shields.io/badge/bumpr-supported-ff69b4?logo=github&link=https://github.com/haya14busa/action-bumpr)](https://github.com/haya14busa/action-bumpr)

## Usage

```yaml
name: reviewdog
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
        reporter: 'github-pr-check'
        tool_name: 'testtool'
```
