# Ipa-maker

Turns an Xcode project into an **unsigned `.ipa`**, built on GitHub's hosted
macOS runners. No Mac, no Xcode install, no code-signing certificate needed.

The workflow at `.github/workflows/build-unsigned-ipa.yml` does the work:
it fetches your Xcode project (either by cloning a repo or by unzipping a
file you push here), runs `xcodebuild archive` with code signing disabled,
packages the resulting `.app` into a `Payload/App.ipa`, and uploads it as a
downloadable workflow artifact.

## Option A: point it at a GitHub repo

1. Go to **Actions → Build Unsigned IPA → Run workflow**.
2. Fill in the inputs:
   - `repo_url` — the Xcode project's repo, e.g. `https://github.com/you/YourApp.git`
   - `ref` — branch/tag/commit to build (optional, defaults to the repo's default branch)
   - `project_subpath` — only needed if the `.xcodeproj`/`.xcworkspace` isn't at the repo root
   - `scheme` — only needed if auto-detection picks the wrong scheme
   - `configuration` — `Release` (default) or `Debug`
   - `xcode_version` — only needed to pin a specific Xcode (e.g. `15.4`)
3. Click **Run workflow**.

For a **private** source repo, add a repo secret named `SOURCE_REPO_TOKEN`
(a GitHub PAT with read access to that repo). It's injected into the clone
URL automatically when set.

## Option B: upload a zip of the project

1. Zip your Xcode project (the folder containing the `.xcodeproj`/`.xcworkspace`,
   or its parent folder).
2. Add the zip to `uploads/` in this repo and push it (or upload it through
   the GitHub web UI's "Add file → Upload files" into `uploads/`).
3. The push automatically triggers the workflow, which picks up the most
   recently added `.zip` in `uploads/`.
4. Alternatively, run the workflow manually and set the `zip_path` input to
   the specific file under `uploads/` you want built (leave `repo_url` empty).

## Getting the IPA

Once the run finishes, open it in the **Actions** tab and download the
`.ipa` from the **Artifacts** section at the bottom of the run summary.

## What the build does

- Auto-detects a `.xcworkspace` (preferred) or `.xcodeproj` under the source.
- Runs `pod install` automatically if a `Podfile` is present.
- Auto-detects the first shared scheme if `scheme` isn't set.
- Archives for a generic iOS device with signing disabled
  (`CODE_SIGNING_ALLOWED=NO`, no team, no identity).
- Repackages the archived `.app` into `Payload/App.ipa` (a plain zip with
  the `Payload/` layout `.ipa` files require).
- Swift Package dependencies are resolved automatically by `xcodebuild`.

## About "unsigned"

The resulting `.ipa` has **no code signature**. It's useful for CI builds,
archiving, static analysis, or as an input to your own signing/resigning
pipeline. It will **not** install as-is on a real device or ad-hoc/App
Store distribution channel — those require a valid signature. It also
won't run in the iOS Simulator directly (simulator builds use a different
SDK); this workflow targets a real-device (`iphoneos`) build so the result
is closest to what a release build would produce.

## Troubleshooting

- **"No .xcworkspace or .xcodeproj found"** — set `project_subpath` to the
  folder containing the project, or check that the zip/repo actually
  contains the Xcode project.
- **"Could not determine a scheme to build"** — the project has no shared
  scheme checked into source control; set the `scheme` input explicitly, or
  in Xcode mark the scheme as **Shared** (Product → Scheme → Manage Schemes)
  and commit the change.
- **Build fails on dependency resolution** — Swift Package Manager needs
  network access, which the hosted runner has; CocoaPods needs a `Podfile`
  at the project root (or under `project_subpath`) to trigger `pod install`.
