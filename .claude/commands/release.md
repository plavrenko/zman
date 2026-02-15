Release workflow for Zman. Run all three phases sequentially — do NOT skip any phase. Stop and fix issues before proceeding.

## Phase 0 — Pre-flight audit

Run these checks automatically. Report results as a checklist. If ANY check fails, stop, report the failures, help fix them, and re-run the audit.

1. **Clean working tree**: Run `git status`. There must be no uncommitted changes and no untracked files (ignoring .gitignore-covered paths). If dirty, tell the user what needs to be committed or cleaned up.

2. **Personal data scan**: Run `git grep -n -E '/Users/[a-zA-Z]' -- ':!.claude/' ':!CLAUDE.md'` to find hardcoded user home paths in tracked files (excluding .claude config and CLAUDE.md). Also check for hardcoded email addresses, API keys, or tokens with `git grep -n -E '(api[_-]?key|token|secret|password)\s*[:=]' --ignore-case -- ':!.claude/'`. Report any matches.

3. **Gitignore coverage**: Verify these patterns exist in .gitignore: `build/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`, `Zman-claude-*.zip`. Read `.gitignore` and check.

4. **No ignored files tracked**: Run `git ls-files -i --exclude-standard`. If any output, those files are tracked but should be ignored.

5. **Version check**: Extract `MARKETING_VERSION` from `Zman-claude.xcodeproj/project.pbxproj` (grep for it, take the first match). Store this as VERSION for the rest of the workflow.

6. **CHANGELOG entry**: Read `CHANGELOG.md`. There must be a section header matching `## [VERSION] - YYYY-MM-DD` (with an actual date, not `[Unreleased]`). The date should be today or recent.

7. **README has Homebrew instructions**: Read `README.md` and verify it contains a Homebrew installation section (search for "brew install").

8. **AGENTS.md has Build & Release**: Read `AGENTS.md` and verify the Build & Release section exists and mentions `make build`, `make release`, and `/release`.

Present all results as a checklist. If all pass, proceed to Phase 1. If any fail, stop and help fix.

## Phase 1 — Build & verify

9. Run `make build`. If the build fails, report the error and stop.

10. Kill any running instance and launch the new build:
    ```
    pkill -x "Zman-claude" 2>/dev/null; sleep 0.5
    open build/Release/Zman-claude.app
    ```

11. Ask the user to verify with a checklist:
    - "App launched and works correctly?"
    - "Version VERSION is correct?"
    - "CHANGELOG entry looks good?"

    Wait for user approval. Do NOT proceed until the user explicitly confirms.

## Phase 2 — Release

12. Run `make release` to create the zip.

13. Check if tag `vVERSION` exists locally or remotely:
    - `git tag -l "vVERSION"` — check local
    - `git ls-remote --tags origin "refs/tags/vVERSION"` — check remote
    - If tag doesn't exist: create and push it: `git tag vVERSION && git push origin vVERSION`
    - If tag exists locally but not remotely: `git push origin vVERSION`

14. Wait for the draft release to appear. Poll up to 60 seconds:
    ```
    for i in $(seq 1 12); do
      gh release view "vVERSION" --repo $(git remote get-url origin | sed 's/.*github.com[:/]//;s/.git$//') 2>/dev/null && break
      sleep 5
    done
    ```

15. Upload the zip:
    ```
    gh release upload "vVERSION" "Zman-claude-VERSION.zip" --repo $(git remote get-url origin | sed 's/.*github.com[:/]//;s/.git$//') --clobber
    ```

16. Ask the user: "Ready to publish release vVERSION? This will make it public and trigger the Homebrew Cask update."

    Wait for explicit confirmation.

17. Publish:
    ```
    gh release edit "vVERSION" --draft=false --repo $(git remote get-url origin | sed 's/.*github.com[:/]//;s/.git$//')
    ```

18. Report success: "Release vVERSION published. The Homebrew Cask will be updated automatically by CI."
