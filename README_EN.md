# TimeToSleep

> Nothing is more important than sleep.
>
> Sleeping early is the foundation of good rest, yet most people stay up late because they can't put down their computer. But asking someone to willingly walk away from a screen — that's fighting human nature. So flip the script: when it's time, the computer locks itself.
>
> No willpower required. No "just five more minutes." Time's up, screen goes dark, day's over. That's working *with* human nature, not against it.

A terminal-based commitment device that locks your Mac at bedtime. You sign a contract with yourself — the computer enforces it.

[中文](README.md)

## What it does

- **Wind-down reminders**: Gradually dims screen, lowers volume, sends notifications before bedtime
- **Full lockdown**: Fullscreen overlay covers all displays, pauses media, mutes audio
- **No escape**: Cannot be dismissed until wake-up time — rebooting re-locks immediately
- **Streak tracking**: Records your consecutive early-sleep days, displayed on the lock screen

## Install

```bash
git clone https://github.com/znygithub/TimeToSleep.git
cd TimeToSleep
bash install.sh
```

Requires macOS 11+, no other dependencies.

## Setup

```bash
zzz init
```

Interactive onboarding: set bedtime, wake-up time, active days, and how early to start reminding.

## Commands

```
zzz              # Tonight's status + countdown
zzz status       # Detailed stats
zzz config       # View / change settings
zzz tonight off  # Skip tonight (must give a reason)
zzz log          # History
zzz test         # Test the lock screen (default glow style, 10 seconds)
zzz test cycle 8 # Preview glow / orbit / seal streak animations in sequence
zzz uninstall    # Remove everything
```

## Design principles

- **Lockdown is absolute.** No exit until wake-up time. Rebooting re-locks immediately — there is no backdoor.
- **Uninstall is clean but reflective.** Shows your streak and stats before confirming. No guilt-tripping — just a moment to see what you've built.

## How it works

- `zzz` CLI (shell scripts) for all interaction
- Pre-compiled Swift fullscreen overlay (universal binary for arm64 + x86_64, covers all displays)
- macOS `launchd` for scheduling + boot check (prevents restart bypass)
- `osascript` for media control and notifications
- Config stored in `~/.timetosleep/`

## License

MIT
