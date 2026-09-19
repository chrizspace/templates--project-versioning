# githubflow--pixelbrand

## Branch promotion and versioning

The repository uses this promotion flow:

```text
feature/* -> dev -> release -> prod
```

`dev` is the repository's default branch. The former `main` branch was
retired because it had no commits that were not already represented by the
promotion branches.

Merged pull requests create one semantic version tag on the merged promotion
commit:

| Target branch | Automatic bump | Automatic synchronization |
| --- | --- | --- |
| `dev` | Patch (`v1.0.0` -> `v1.0.1`) | None |
| `release` | Minor by default; labels can select major or hotfix | Merge `release` back into `dev` |
| `prod` | Mirrors the current `release` tag; `release:hotfix` is the only bump | Merge `prod` into `release`, then `release` into `dev` |

For a pull request targeting `release`, the workflow defaults to a minor bump.
Use `release:major` for a major bump or `release:minor` to select minor
explicitly. `release:hotfix` is invalid on a PR targeting `release`; it is
reserved for a hotfix branch created from `prod` and merged back into `prod`.
For a normal PR targeting `prod`, the workflow reuses the semantic version tag
on the current `release` tip, so promoting `v2.0.0` to `prod` keeps `v2.0.0`.
Only `release:hotfix` creates a production tag, incrementing the latest
semantic version reachable from `prod` by one patch. A normal production
promotion fails if no semantic version tag exists on the release tip. The
workflows discover the highest semantic version across all repository tags
where a new promotion bump is required. When no tag exists, versioning starts
at `v0.0.0`.

### Repository setup

1. Make a repository or organization secret named `GH_PAT` available to the
   repository initialization workflow, using a token owned by the repository
   administrator with repository contents write, issues write, and
   administration write access. Repository secrets are not copied when
   creating a repository from a template, so use an organization secret or
   add the secret before manually rerunning initialization. This personal-
   account repository cannot configure user-specific bypass actors, so
   administrator enforcement is disabled on the promotion branches for the
   mergeback jobs.
2. `dev`, `release`, and `prod` require pull requests but no approvals;
   force pushes and branch deletions are disabled. Keep the workflows'
   `GH_PAT` checkout for mergeback jobs so direct synchronization pushes can
   update the protected branches.
3. After creating a repository from this template, open **Actions** ->
   **Initialize Repository Governance** -> **Run workflow**. Leave the
   `repository` input empty to configure the new repository, or enter an
   `OWNER/REPOSITORY` target. The workflow creates or updates the three
   `dev`, `release`, and `prod` branches from the target's default-branch
   commit when they are missing, then creates or updates the three release
   labels and six promotion-branch rulesets from
   `config/repository-governance.json`. Existing branches are not overwritten.
   It deletes all other repository labels and repository-local rulesets, so the
   result contains only the configured governance. Organization-level or
   inherited rulesets are not modified. The workflow is safe to rerun.
4. The same synchronization can be run locally with an authenticated GitHub
   CLI:

   ```bash
   GH_REPO=OWNER/REPOSITORY GH_TOKEN=YOUR_TOKEN \
     bash scripts/sync-repository-governance.sh
   ```

   `GH_REPO` is optional when running inside a checkout of the target
   repository. Do not put the token in shell history or commit it.
5. Open pull requests for each promotion. Once a pull request is merged, the
   matching workflow bumps the version and performs the required mergebacks.

The mergeback pushes do not close pull requests, so they do not trigger another
version bump. This keeps one version tag per promotion and prevents version
drift between `prod`, `release`, and `dev`.
