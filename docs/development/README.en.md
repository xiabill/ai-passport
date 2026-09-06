<p align="right">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

# Development Guidelines

This directory contains AI Passport engineering rules and reusable workflows. Rules should identify their trigger, required action, prohibited action, validation, and exceptions. Hardware facts belong in `docs/hardware-design/`; automatable requirements must also be enforced by tooling or CI.

## Documents

- [agent-guide.en.md](agent-guide.en.md): AI-assisted development workflow.
- [vibe-typeless.en.md](vibe-typeless.en.md): Vibe Typeless companion firmware and Mac bridge.
- [environment-setup.en.md](environment-setup.en.md): clean-machine bootstrap for AI agents, including international and mainland China download routes.
- [build-and-test.en.md](build-and-test.en.md): ESP-IDF build and validation.
- [ble-recovery-compatibility.en.md](ble-recovery-compatibility.en.md): mandatory
  mini-program BLE install artifact, partition, and bootloader contract.
- [coding-conventions.en.md](coding-conventions.en.md): source-code and resource conventions.
- [CI-validation.en.md](CI-validation.en.md): pull-request and main-branch checks.
- [CI-build-and-release.en.md](CI-build-and-release.en.md): tagged firmware builds and releases.
- [CI-sync-main.en.md](CI-sync-main.en.md): upstream synchronization for forks.
- [publish-to-community.en.md](publish-to-community.en.md): publishing firmware to the AI Passport community market.
- [project-completion.en.md](project-completion.en.md): project completion flow — a menu of optional closing actions.
- [file-issues.en.md](file-issues.en.md): filing a suggestion as an upstream GitHub issue.
- [experience-notes.en.md](experience-notes.en.md): index of development experience entries under `docs/experiences/`.
