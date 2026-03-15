# Stage 1 Smoke Test Checklist

This checklist is for manual validation of Stage 1 bootstrap behavior before broad rollout.

## Test Scope

- Validate Stage 1 only.
- Confirm Stage 1 reaches Stage 2 handoff cleanly.
- Do not require private network resources.

## Preconditions

- You can run commands with sudo/admin privileges.
- You have a GitHub account that can access the private Stage 2 repo.
- You can complete gh authentication when prompted.

## macOS Quick Checklist

1. Run the one-liner from the project README.
2. Confirm the script reports the expected Stage 2 target URL.
3. If gh is not authenticated, complete gh login.
4. Confirm chezmoi handoff starts (`chezmoi init --apply`).
5. After completion, run `chezmoi apply` once more and confirm no unexpected errors.
6. Open a new terminal session and verify your shell environment still behaves as expected.

## Linux Quick Checklist

1. Run the one-liner from the project README.
2. Confirm distro detection and package manager path are correct.
3. If gh is not authenticated, complete gh login.
4. Confirm chezmoi handoff starts (`chezmoi init --apply`).
5. Run `chezmoi apply` again to verify rerun safety and idempotency.

## Windows Quick Checklist

1. Run PowerShell as Administrator.
2. Run the one-liner from the project README.
3. Confirm WSL checks/install path behaves as expected.
4. Confirm handoff into WSL bootstrap completes without errors.
5. Confirm Stage 2 handoff is reached inside WSL.

## Existing-System Rerun Check

Use this when Stage 1 and Stage 2 were already run before.

1. Re-run Stage 1 and confirm it does not fail if gh is already authenticated.
2. Confirm Stage 1 reuses existing tools where already installed.
3. Confirm Stage 2 handoff still runs cleanly.
4. Run `chezmoi apply` once more and verify no unexpected drift.

## Pass Criteria

- Stage 1 completes without blocking errors.
- gh authentication is handled correctly (reuse existing auth or prompt when needed).
- Stage 2 handoff command is reached successfully.
- A follow-up `chezmoi apply` does not reveal unexpected failures.

## Notes

- CI mode (`BOOTSTRAP_CI_TEST=1`) is for runner validation and intentionally skips Stage 2 handoff.
- Manual smoke tests should run without CI mode so the full handoff path is exercised.
