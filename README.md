# action-pmd

[![Test](https://github.com/kemsakurai/action-pmd/workflows/Test/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3ATest)
[![reviewdog](https://github.com/kemsakurai/action-pmd/workflows/reviewdog/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Areviewdog)
[![depup](https://github.com/kemsakurai/action-pmd/workflows/depup/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Adepup)
[![release](https://github.com/kemsakurai/action-pmd/workflows/release/badge.svg)](https://github.com/kemsakurai/action-pmd/actions?query=workflow%3Arelease)
[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/kemsakurai/action-pmd?logo=github&sort=semver)](https://github.com/kemsakurai/action-pmd/releases)
[![action-bumpr supported](https://img.shields.io/badge/bumpr-supported-ff69b4?logo=github&link=https://github.com/haya14busa/action-bumpr)](https://github.com/haya14busa/action-bumpr)

This is a GitHub action to run [PMD](https://github.com/pmd/pmd) check on your Java code and report status via [reviewdog](https://github.com/reviewdog/reviewdog) on pull request.

## 🚨 BREAKING CHANGES (v0.1.0+)

**This version includes major updates and breaking changes:**

- **PMD 7.25.0**: Updated to PMD 7.25.0
- **Java 21**: Now using Eclipse Temurin 21 (upgraded from OpenJDK 17)
- **Reviewdog v0.21.0**: Updated from v0.14.1
- **Default Ruleset Change**: `category/java/bestpractices.xml` (was `rulesets/java/quickstart.xml`)
- **PMD CLI Change**: Uses `pmd check` command (PMD 7.x syntax)

**Migration Required:**
- If you explicitly set `rulesets_path`, update to PMD 7.x compatible paths (see [Migration Guide](#migration-guide-from-pmd-6x-to-7x))
- Legacy ruleset paths like `rulesets/java/basic.xml` are no longer supported
- Review your custom rulesets for deprecated rules

**Version Strategy:**
- v1.x branch: Uses PMD 6.x (previous version)
- v0.1.x: Uses PMD 7.x (current)

## Version Information

| Component | Version |
|-----------|---------|
| Java | Eclipse Temurin 21 (LTS) |
| PMD | 7.25.0 |
| Reviewdog | v0.21.0 |

### PMD 7.25.0 Notes

- PMD 7.25.0 updates ANTLR to 4.13.2.
- If you maintain custom ANTLR-based PMD language modules, regenerate parsers/lexers with ANTLR 4.13.2.
- Java rules were added/updated and violation locations were improved, so CI findings may differ from earlier PMD 7.x versions.

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
  fail_level:
    description: |
      Fail level for reviewdog [none,any,info,warning,error]
      Default is `none`.
    default: 'none'
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
    description: 'Specify the path of the PMD rule set. Default is `category/java/bestpractices.xml`.'
    default: 'category/java/bestpractices.xml'
  pmd_cache:
    description: 'Enable PMD incremental analysis with cache file path (e.g., "/tmp/pmd-cache/pmd.cache"). Must be a file path, not a directory. Leave empty to disable.'
    default: ''
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
      uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    - name: Run PMD
      uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        reporter: 'github-pr-review'
        tool_name: 'pmd_reviewdog'
```

### With PMD Cache (Performance Optimization)

```yaml
name: pmd
on: [pull_request]
jobs:
  pmd_job:
    runs-on: ubuntu-latest
    name: PMD job with cache
    steps:
    - name: Checkout
      uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    - name: Run PMD
      uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        reporter: 'github-pr-review'
        tool_name: 'pmd_reviewdog'
        pmd_cache: '/tmp/pmd-cache/pmd.cache'  # Enable incremental analysis
```

### With Custom Ruleset

```yaml
name: pmd
on: [pull_request]
jobs:
  pmd_job:
    runs-on: ubuntu-latest
    name: PMD job with custom ruleset
    steps:
    - name: Checkout
      uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    - name: Run PMD
      uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        reporter: 'github-pr-check'
        rulesets_path: 'category/java/errorprone.xml'  # Use different built-in ruleset
```

## Migration Guide from PMD 6.x to 7.x

### Official Documentation

For comprehensive migration information, please refer to:
- [PMD 7 Migration Guide](https://docs.pmd-code.org/latest/pmd_userdocs_migrating_to_pmd7.html)
- [PMD 7 Release Notes](https://docs.pmd-code.org/latest/pmd_release_notes_pmd7.html)

### Key Breaking Changes

1. **CLI Command Change**
   - Old: `pmd -d <dir> -R <ruleset>`
   - New: `pmd check -d <dir> -R <ruleset>`

2. **Ruleset Path Format**
   - ❌ Removed: `rulesets/java/basic.xml`, `rulesets/java/quickstart.xml`
   - ✅ Use: `category/java/bestpractices.xml`, `category/java/errorprone.xml`

3. **Deprecated Rules Removed**
   - Many legacy rules have been removed or replaced
   - See [Removed Rules List](https://docs.pmd-code.org/pmd-doc-7.25.0/pmd_release_notes_pmd7.html#removed-rules)

4. **Property Delimiter Change**
   - Old: Pipe `|` separator
   - New: Comma `,` separator

### Migration Steps

1. **Verify Current Ruleset Compatibility**
   ```bash
   # Test your current ruleset with PMD 7.x
  docker build --build-arg PMD_VERSION=7.25.0 -t action-pmd:test .
  docker run --rm --entrypoint sh -v $(pwd):/workspace action-pmd:test -lc 'export PATH="/opt/java/openjdk/bin:/pmd/bin:$PATH" && pmd check -d /workspace/src -R category/java/bestpractices.xml --no-progress'
   ```

2. **Update Workflow Configuration**
   ```yaml
   # Before (v1.x)
   - uses: kemsakurai/action-pmd@v1
     with:
       rulesets_path: 'rulesets/java/quickstart.xml'
   
  # After (commit SHA pin)
  - uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
     with:
       rulesets_path: 'category/java/bestpractices.xml'  # Updated path
   ```

3. **Review Custom Rulesets**
   - Update ruleset references to use `category/` prefix
   - Remove references to deleted rules
   - Test thoroughly before deploying

## Recommended Rulesets

PMD 7.x provides category-based rulesets. Here are recommended options:

| Ruleset | Description | Use Case |
|---------|-------------|----------|
| `category/java/bestpractices.xml` | Best practice rules (default) | General code quality |
| `category/java/errorprone.xml` | Error-prone patterns | Bug prevention |
| `category/java/codestyle.xml` | Code style conventions | Style enforcement |
| `category/java/design.xml` | Design principles | Architecture quality |
| `category/java/performance.xml` | Performance optimizations | Performance-critical code |
| `category/java/security.xml` | Security vulnerabilities | Security-sensitive applications |

### Multiple Rulesets Example

```yaml
- uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
  with:
    rulesets_path: 'category/java/bestpractices.xml,category/java/errorprone.xml'
```

### Custom Ruleset Template

Create a custom `pmd-ruleset.xml` in your repository:

```xml
<?xml version="1.0"?>
<ruleset name="Custom Ruleset"
         xmlns="http://pmd.sourceforge.net/ruleset/2.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://pmd.sourceforge.net/ruleset/2.0.0 https://pmd.sourceforge.io/ruleset_2_0_0.xsd">
    
    <description>Custom PMD ruleset for our project</description>
    
    <!-- Include built-in rulesets -->
    <rule ref="category/java/bestpractices.xml"/>
    <rule ref="category/java/errorprone.xml"/>
    
    <!-- Exclude specific rules -->
    <rule ref="category/java/bestpractices.xml">
        <exclude name="UnusedPrivateMethod"/>
    </rule>
    
    <!-- Customize rule properties -->
    <rule ref="category/java/codestyle.xml/LongVariable">
        <properties>
            <property name="minimum" value="30"/>
        </properties>
    </rule>
</ruleset>
```

Then use it in your workflow:

```yaml
- uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
  with:
    rulesets_path: './pmd-ruleset.xml'
```

## Performance Optimization

### PMD Cache

PMD 7.x supports incremental analysis via the `--cache` option, which can significantly reduce CI execution time for large codebases.

**Enable Cache:**
```yaml
- uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
  with:
    pmd_cache: '/tmp/pmd-cache/pmd.cache'
```

**Benefits:**
- Analyzes only changed files
- Reduces analysis time by 30-70% for subsequent runs
- Automatically managed by PMD

**Best Practices:**
- Use a consistent cache path across workflow runs
- Consider using GitHub Actions cache to persist between runs:

```yaml
- name: Cache PMD results
  uses: actions/cache@v3
  with:
    path: /tmp/pmd-cache
    key: pmd-cache-${{ github.sha }}
    restore-keys: |
      pmd-cache-

- uses: kemsakurai/action-pmd@aafc862a11dd31e0f93c8c4d06e403fd6bbcca8b
  with:
    pmd_cache: '/tmp/pmd-cache/pmd.cache'
```

## Troubleshooting

### Common Errors and Solutions

#### Error: "Ruleset not found"

**Symptom:**
```
Error: Unable to load ruleset: rulesets/java/quickstart.xml
```

**Solution:**
Update to PMD 7.x category-based paths:
```yaml
rulesets_path: 'category/java/bestpractices.xml'
```

#### Error: "Rule not found"

**Symptom:**
```
Error: Rule 'SomeRuleName' not found
```

**Solution:**
The rule may have been removed in PMD 7.x. Check the [removed rules list](https://docs.pmd-code.org/pmd-doc-7.25.0/pmd_release_notes_pmd7.html#removed-rules) and find alternatives.

#### Error: "Permission denied" (Cache)

**Symptom:**
```
Warning: Failed to create cache directory
```

**Solution:**
Ensure the cache path is writable. The action automatically sets permissions, but if using a custom path, verify access:
```yaml
pmd_cache: '/tmp/pmd-cache/pmd.cache'  # /tmp is always writable
```

#### Error: "Java version mismatch"

**Symptom:**
```
Error: PMD requires Java 8 or later
```

**Solution:**
This action includes Java 21. If you're building with a different Java version in previous steps, ensure PMD runs in the action's container context.

### Getting Help

- [PMD Documentation](https://docs.pmd-code.org/)
- [Reviewdog Documentation](https://github.com/reviewdog/reviewdog)
- [Issue Tracker](https://github.com/kemsakurai/action-pmd/issues)

## Custom Docker Build

You can build the Docker image with custom versions of PMD or Reviewdog:

```bash
# Build with specific PMD version
docker build --build-arg PMD_VERSION=7.25.0 -t action-pmd:custom .

# Build with specific Reviewdog version
docker build --build-arg REVIEWDOG_VERSION=v0.20.0 -t action-pmd:custom .

# Build with both custom versions
docker build \
  --build-arg PMD_VERSION=7.25.0 \
  --build-arg REVIEWDOG_VERSION=v0.20.0 \
  -t action-pmd:custom .
```

## License

[MIT](LICENSE)
