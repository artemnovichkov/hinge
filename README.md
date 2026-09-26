# hinge

<p>
  <a href="https://github.com/artemnovichkov/hinge/releases/latest"><img src="https://img.shields.io/github/v/release/artemnovichkov/hinge" alt="Latest release"></a>
  <a href="https://github.com/artemnovichkov/homebrew-tap"><img src="https://img.shields.io/badge/homebrew-artemnovichkov%2Ftap-orange.svg" alt="Homebrew"></a>
  <img src="https://img.shields.io/badge/macOS-Xcode%2027.1+-blue.svg" alt="Xcode 27.1+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="MIT License"></a>
</p>

Control the hinge angle of a foldable iPhone Simulator (iPhone Duo) from the command line, from scripts, or from AI coding agents like Claude Code and Codex.

https://github.com/user-attachments/assets/758de2a9-10eb-4972-96a0-fd04e433267d

```bash
hinge 120            # set the angle: 0 = closed, 180 = flat
hinge sweep 180 0 2  # fold closed over 2 seconds
hinge get            # 120.0
```

Xcode's Device Hub has a hidden hinge slider (hold Option), but there is no `simctl` or `devicectl` command to set the angle. `hinge` fills that gap.

## Requirements

- macOS with Xcode 27.1 or later and a foldable iOS Simulator runtime
- A booted foldable simulator, such as iPhone Duo

## Installation

**Homebrew:**

```bash
brew install artemnovichkov/tap/hinge
```

**From source:**

```bash
git clone https://github.com/artemnovichkov/hinge.git
ln -s "$PWD/hinge/bin/hinge" /usr/local/bin/hinge
```

The first run compiles a small helper with Xcode's clang and caches it in `~/.cache/hinge`.

## Usage

```
Usage: hinge [-d <device>] <command>

Commands:
  <degrees>                   Set hinge angle, 0 (closed) to 180 (flat)
  set <degrees>               Same as above
  open                        Unfold flat (180°)
  close                       Fold closed (0°)
  half                        Half-open (90°)
  sweep <from> <to> [seconds] Animate between two angles (default 1s)
  get                         Print current hinge angle
  help                        Show this help

Options:
  -d, --device <device>       Simulator UDID, name, or "booted" (default)
  -v, --version               Print version
```

## Agent skill

[`skills/hinge`](skills/hinge) is a self-contained [Agent Skill](https://agentskills.io) that bundles the CLI. It lets an agent fold the simulator while verifying your app.

**[skills.sh](https://skills.sh)** (Claude Code, Codex, Cursor, and other agents):

```bash
npx skills add artemnovichkov/hinge
```

**Claude Code plugin:**

```
/plugin marketplace add artemnovichkov/hinge
/plugin install hinge@hinge
```

**Manually:**

```bash
cp -R hinge/skills/hinge ~/.claude/skills/   # Claude Code
cp -R hinge/skills/hinge ~/.codex/skills/    # Codex
```

Then ask the agent something like *"fold the simulator to 90° and take a screenshot"*.

## How it works

The hinge slider in Device Hub sends a vendor-defined HID event to the simulator through CoreDevice:

| Field | Value |
|---|---|
| Usage page | `0xFF61` |
| Usage | `0x5B` |
| Data | Binary-serialized dictionary: `provider = "com.apple.Virtualization"`, `source = "hinge-slider-control"`, `type = "range"`, `value = <degrees>` |

`hinge` builds a small helper for the iOS Simulator SDK and runs it inside the simulator with `xcrun simctl spawn`. The helper creates the same event and dispatches it through the simulator's `IOHIDEventSystem`. The current angle is read back with `xcrun devicectl device motion hinge-angle`.

## Limitations

- Simulator only. Physical devices are not supported.
- The protocol is private and undocumented. It was verified with Xcode 27.1 and the iOS 27.1 runtime and may break with future releases.
- The Device Hub slider doesn't move when the angle changes from `hinge`.

## Author

Artem Novichkov, https://artemnovichkov.com/

## License

The project is available under the MIT license. See the [LICENSE](./LICENSE) file for more info.
