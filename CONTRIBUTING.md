# Contributing to Etherpad

Thanks for your interest — contributions of all kinds are welcome, and **ideas are genuinely appreciated**. Whether it's a bug fix, a new feature, or just a thought, feel free to open an [Issue](../../issues) or start a [Discussion](../../discussions). Sharing an idea is contributing too.

**Looking for something to build?** Check the [feature roadmap](docs/FEATURE_IDEAS.md) for things we're planning — feel free to pick one up, or suggest your own.

## Don't worry about Apple Developer stuff

You **don't** need a paid Apple Developer account or to deal with notarization/signing to contribute. I already have a paid developer certificate, and releases are **signed and notarized** on our side via GitHub Actions and Xcode Cloud for the Apple ecosystem. Just build, experiment, and have fun — focus on the code and the ideas.

## Getting started

- **Apple (iOS / iPadOS / macOS):** see [`Etherpad-Apple/BUILD.md`](Etherpad-Apple/BUILD.md)
- **Android:** see [`Etherpad-Android/README.md`](Etherpad-Android/README.md)

Tip: new features are easiest to prototype on the **macOS desktop app** first (fastest iteration), then ported to the other platforms.

## Standard workflow

1. **Fork** the repo and create a branch off `main`.
2. Use a descriptive **branch name** with a type prefix:
   - `fix/<short-description>` — bug fixes
   - `feat/<short-description>` — new features
   - `docs/<short-description>` — documentation
   - `chore/<short-description>` — tooling, cleanup, refactors
3. Keep changes focused; write clear, concise **commit messages** (explain the *why*).
4. Make sure the project **builds** before opening a PR.
5. Open a **Pull Request** against `main` with a short summary of what changed and why.
   Link any related issue (e.g. `Closes #123`).

## A few conventions

- Match the existing code style of the platform you're touching (each app is idiomatic
  to its platform — don't share code across them).
- One logical change per PR keeps reviews fast.
- For bigger features, open an issue/discussion first so we can align on the approach.

That's it — appreciate you helping make Etherpad better!
