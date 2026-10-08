# Releasing

Releases go to RubyGems from GitHub Actions (`.github/workflows/release.yml`) when a `v*` tag is
pushed. The workflow uses RubyGems [trusted publishing](https://guides.rubygems.org/trusted-publishing/),
so no API key is stored anywhere.

## One-time setup

1. Sign in to rubygems.org with the account that should own the gem, and turn on MFA
   (the gemspec sets `rubygems_mfa_required`).
2. Profile → **Trusted Publishers** → **Create** a *pending* trusted publisher (the gem does not
   exist yet):
   - Gem name: `waffo-pancake`
   - Repository owner: `goodfirstissueorg`
   - Repository name: `waffo-pancake-ruby`
   - Workflow filename: `release.yml`
   - Environment: `rubygems`
3. In this repository, Settings → Environments → **New environment** `rubygems`. Optionally add
   yourself as a required reviewer, so every release waits for a click.

## Each release

1. Update `lib/waffo/pancake/version.rb` and add a `CHANGELOG.md` entry; merge to `main`.
2. Tag the merge commit and push the tag:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. The Release workflow runs the tests, checks that the tag matches `VERSION`, builds the gem
   and pushes it. It appears at https://rubygems.org/gems/waffo-pancake a minute later.

## Publishing by hand instead

```sh
gem build waffo-pancake.gemspec
gem push waffo-pancake-0.1.0.gem   # asks for your MFA code
git tag v0.1.0 && git push origin v0.1.0
```

After the first manual push you can still add a (non-pending) trusted publisher for later
releases in the gem's page → **Trusted publishers**.
