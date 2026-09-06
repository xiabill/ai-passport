<p align="right">
  <a href="AGENTS.md">简体中文</a> · <strong>English</strong>
</p>

# Repository Guidelines for AI Agents

This file is the only mandatory entry point for AI-assisted work in this repository. Read task-specific documents from the routing table below; do not load every README by default.

## Project and safety baseline

- Target: ESP32-C3, 8 MB Flash, no PSRAM, ESP-IDF 5.5.3.
- Preserve mini-program BLE install compatibility: the 3 MB application limit,
  `cardid` at `0x356000`, permanent Recovery at `0x700000`, and the five-second
  UP-key bootloader hook are mandatory template contracts.
- Preserve existing user changes. Start with `git status --short --branch`; never overwrite or clean unrelated files.
- Hardware facts follow this priority: product specifications and measured results → `components/bsp/include/bsp_pins.h` → BSP headers and implementation → hardware guide → README/demo code. If a task requires a hardware detail not defined by these sources, ask the user instead of guessing.
- Reusable board logic belongs in `components/bsp`; pages, state machines, animations, and application tasks belong in `main`.
- LVGL is not thread-safe. Code outside the LVGL task must hold `bsp_lvgl_lock()` while accessing LVGL objects.
- Button callbacks must stay non-blocking. Audio, storage, networking, and other slow operations belong in worker tasks.
- A demo must stop every task, timer, callback, and event handler that can access its UI before deleting the screen.
- Keep testable state machines, protocols, timing, and layout calculations independent from ESP-IDF/LVGL and cover them with host tests.
- Never commit credentials, device QR secrets, private keys, personal data, or unsanitized logs.
- Every maintained Markdown document uses Simplified Chinese at its default `.md` path and English in a paired `.en.md` file. Keep both versions aligned and retain reciprocal language links.

## Task-specific context routing

| Task | Read before editing |
| --- | --- |
| Any code change | `docs/development/agent-guide.en.md`, relevant headers and neighboring implementation |
| Environment bootstrap or missing toolchain | `docs/development/environment-setup.en.md` |
| BSP, pins, buses, display, audio, battery | `docs/hardware-design/AI_HARDWARE_DEVELOPMENT_GUIDE.en.md`, `components/bsp/include/bsp_pins.h` |
| Demo or menu | `main/demo.h`, `main/main.c`, the nearest `main/demo_*.c` implementation |
| Build, test, dependencies, partitions | `docs/development/build-and-test.en.md`, `docs/development/ble-recovery-compatibility.en.md`, `sdkconfig.defaults`, `partitions.csv` |
| CI or release | the matching file in `docs/development/CI-*.md` and `.github/workflows/` |
| Project completion | `docs/development/project-completion.en.md` (then the `issue-suggestions` or `experience-pr` skill) |
| Documentation | `docs/contribution/doc-conventions.en.md`, `docs/INDEX.en.md` |
| Commit or PR | `docs/contribution/commit-and-pr.en.md` |

Use `docs/README.en.md` for the product overview and `docs/INDEX.en.md` when a task needs additional documentation. Fork-specific workflow is in `docs/fork-guide.en.md` and is not required for ordinary upstream development.

## Required validation and delivery

Run the smallest relevant check while iterating, then run the complete gate before delivery:

```bash
./tools/validate.sh --static    # repository checks + host tests
./tools/validate.sh --firmware  # ESP-IDF build + merged-image verification
./tools/validate.sh             # complete gate
```

The complete gate requires an activated ESP-IDF 5.5.3 environment. Do not describe a successful build as hardware validation. Final delivery must report these fields separately:

```text
Build: PASS / FAIL / NOT RUN
Host tests: PASS / FAIL / NOT RUN
Device tests: PASS / FAIL / NOT RUN
Unverified: remaining board, instrument, or user checks
```

Create commits and push only when the user requests them or the active workflow explicitly requires them. Record user-visible changes in `docs/CHANGELOG.en.md`; internal refactors, CI maintenance, typo fixes, and generated-file refreshes do not require a changelog entry.

Community guidance is in `.github/CONTRIBUTING.en.md`, `.github/CODE_OF_CONDUCT.en.md`, `.github/SECURITY.en.md`, and `.github/SUPPORT.en.md`.
