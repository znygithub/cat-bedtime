# Cat Bedtime

> When bedtime arrives, your Mac belongs to the cat.  
> 中文名：**猫猫困了**

[中文](README.md)

**Cat Bedtime** is a macOS bedtime lock screen. You choose when the cat visits and when it leaves; at bedtime it takes over your screen so you actually step away.

---

## Why this exists

The hard part at night isn’t knowing you should sleep — it’s **closing the laptop**. One more message, one more tab, and the evening disappears.

Cat Bedtime trades a punitive system lock for something softer: **a cat actually comes to sleep on your screen**. That makes it easier to walk away — and when bedtime hits, the lock really sticks (all displays, relaunches if the overlay is killed).

---

## Design ideas

### Adoption, not “enable lock screen”

First run is **cat adoption**: bedtime, wake-up, visit days, and typing a short pledge to let the cat rest well. It’s a small commitment — easier to keep than flipping a security switch.

### Approach gently, then lock firmly

Before bedtime: yawns, notifications, brightness and volume fading — time to wrap up. At bedtime the cat takes over the screen.

### The lock-screen animation in three acts (`cat-bedtime.mov`)

A transparent cat video plays fullscreen. Each beat has a meaning:

| Scene | Meaning |
| --- | --- |
| **Cat drags the bed in** | Bedtime — the cat is moving in with its bed |
| **Cat pulls the lamp cord** | Lights out — **lock screen is on**; the Mac belongs to the cat now |
| **Cat falls asleep** | The cat needs real rest — **so do you**; step away from the computer |

After the animation, the cat stays on screen until wake-up time, with a countdown and a quiet “shh, the cat is asleep.”

### You can ask for a night off

`zzz tonight off` or **Come later** in the app — but you tell the cat why tonight is special.

---

## Download (pick one)

Installers live on GitHub **Releases**, not in the source file tree:

**👉 [Open downloads](https://github.com/znygithub/cat-bedtime/releases/latest)**

Scroll to **Assets** (macOS 12+):

| I want | File | Direct link | Best for |
| --- | --- | --- | --- |
| **App** (recommended) | `Cat-Bedtime-macOS.dmg` | [Download DMG](https://github.com/znygithub/cat-bedtime/releases/download/v1.0.0/Cat-Bedtime-macOS.dmg) | Normal Mac app with a window |
| **CLI** | `cat-bedtime-cli-macos.tar.gz` | [Download CLI](https://github.com/znygithub/cat-bedtime/releases/download/v1.0.0/cat-bedtime-cli-macos.tar.gz) | Terminal-only; `zzz` command, no Dock icon |

**What is `cat-bedtime-cli-macos.tar.gz`?** A compressed archive (like `.zip`). After extracting you get a `cat-bedtime-cli/` folder with `install.sh` — not a `.app`. Most people should use the **DMG**.

### App edition

1. Download and open [Cat-Bedtime-macOS.dmg](https://github.com/znygithub/cat-bedtime/releases/download/v1.0.0/Cat-Bedtime-macOS.dmg)
2. Drag **Cat Bedtime.app** into **Applications**
3. Launch and complete **cat adoption** on first run
4. If macOS blocks the app: System Settings → Privacy & Security → Open Anyway

### CLI edition

1. Download [cat-bedtime-cli-macos.tar.gz](https://github.com/znygithub/cat-bedtime/releases/download/v1.0.0/cat-bedtime-cli-macos.tar.gz) and extract it
2. Run:

```bash
cd cat-bedtime-cli
bash install.sh
```

3. Terminal opens with `zzz init` — complete adoption there
4. Use `zzz` for tonight’s status

**Requirements:** macOS; CLI needs system `python3`. No Xcode required.

Both editions share `~/.timetosleep/` (legacy directory name). Pick **one** edition; if both were installed, whichever completed adoption **last** owns the launchd job.

---

## Features

- **Adoption setup** — bedtime, wake-up, visit days, wind-down lead time
- **Wind-down** — notifications, brightness and volume fade
- **Lock screen** — fullscreen overlay, media paused; overlay relaunches if killed
- **Wake-up restore** — unlock and restore settings at wake time
- **Night off** — `zzz tonight off` or in-app delay with a reason

---

## Commands (CLI)

```bash
zzz                         # Tonight's status
zzz init                    # Adopt / reconfigure
zzz status                  # Visit stats
zzz config                  # Show schedule
zzz config bedtime 23:30
zzz config wakeup 07:30
zzz tonight off
zzz test 10
zzz uninstall
```

---

## Install from source

```bash
git clone https://github.com/znygithub/cat-bedtime.git
cd cat-bedtime
bash install.sh
# or: bash src/app/build.sh  →  bin/Cat Bedtime.app
```

The cat lock-screen video `assets/cat-bedtime.mov` is bundled in release archives; a bare clone may omit large assets.

---

## Docs (developers)

| Doc | Purpose |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture |
| [RELEASE.md](RELEASE.md) | Release signing & notarization |
| [PITFALLS.md](PITFALLS.md) | Known pitfalls |

---

## License

[MIT](LICENSE)
