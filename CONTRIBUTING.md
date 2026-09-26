# Contributing

## Releasing

Run the **Release** workflow with a version number:

```bash
gh workflow run release.yml -f version=0.2.0
```

It bumps the version in the script and plugin manifests, tags the commit, creates a GitHub release, and updates the Homebrew formula in [artemnovichkov/homebrew-tap](https://github.com/artemnovichkov/homebrew-tap).
