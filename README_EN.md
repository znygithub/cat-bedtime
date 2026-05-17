# Cat Bedtime

> When bedtime arrives, your Mac belongs to the cat.

Cat Bedtime is a macOS bedtime lock screen. You decide when the cat comes over and when it leaves. At bedtime, it takes over the screen and sleeps there, which is your cue to step away from the computer.

[中文](README.md)

## What It Does

- **Cat adoption setup**: `zzz init` walks you through the cat's bedtime, wake-up time, active weekdays, and wind-down reminder window.
- **Wind-down reminders**: Sends notifications and gradually lowers brightness and volume before bedtime.
- **Full lock screen**: Covers all displays, pauses media, mutes audio, and relaunches the overlay if it is killed during the sleep window.
- **Wake-up restore**: Exits at wake-up time, restores brightness and volume, and records the visit.
- **Night off**: `zzz tonight off` lets you tell the cat not to come tonight, with a required reason.

## Install

```bash
git clone https://github.com/znygithub/cat-bedtime.git
cd cat-bedtime
bash install.sh
```

Requires macOS and the system `python3`. Normal installation does not require Xcode, `jq`, or third-party packages.

The runtime directory still uses the early project name: `~/.timetosleep/`. This keeps existing installs and launchd jobs compatible.

## Setup

```bash
zzz init
```

After setup, check tonight's status with:

```bash
zzz
```

## Commands

```bash
zzz                         # Tonight's cat status
zzz init                    # Adopt / reconfigure
zzz status                  # Cat visit stats
zzz config                  # Show the cat schedule
zzz config bedtime 23:30    # Change bedtime
zzz config wakeup 07:30     # Change wake-up time
zzz config winddown 30      # Change reminder lead time
zzz tonight off             # Tell the cat not to come tonight
zzz log                     # Visit history
zzz test 10                 # Test the lock screen for 10 seconds
zzz uninstall               # Uninstall
```

## How It Works

- `bin/zzz` is the shell CLI entrypoint.
- `src/init.sh` handles the adoption flow.
- `src/daemon.sh` orchestrates wind-down, lock screen, and wake-up restore.
- `bin/zzz-overlay` is a precompiled Swift fullscreen overlay with multi-display support.
- `launchd` schedules the nightly daemon.
- Config and history live in `~/.timetosleep/config.json` and `~/.timetosleep/stats.json`.

Developers can read [ARCHITECTURE.md](ARCHITECTURE.md) for module details. Historical pitfalls and regression notes are kept in [PITFALLS.md](PITFALLS.md).

## License

MIT
