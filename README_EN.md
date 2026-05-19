# Cat Bedtime

> When bedtime arrives, your Mac belongs to the cat.  
> 中文名：**猫猫困了**

[中文](README.md)

**Cat Bedtime** is a macOS bedtime lock screen. You choose when the cat visits and when it leaves; at bedtime it takes over your screen so you actually step away.

---

## Why this exists

- “Just one more minute” is easier to resist when a cat needs sleep on your screen
- You need a lock that **sticks** (all displays, relaunches if killed)
- You want **gentle wind-down** (notifications, dimmer screen, lower volume), not a sudden blackout

See [PRODUCT_GOALS.md](PRODUCT_GOALS.md) for product principles.

---

## Download (pick one)

Get the latest build from **[GitHub Releases](https://github.com/znygithub/cat-bedtime/releases)** (macOS 12+).

| I want | File | Best for |
| --- | --- | --- |
| **Graphical app** | `Cat-Bedtime-macOS.dmg` | Drag into Applications, no terminal |
| **CLI** | `cat-bedtime-cli-macos.tar.gz` | Manage schedule with the `zzz` command |

> If Releases has no assets yet, use **Install from source** below.

### App edition

1. Download and open `Cat-Bedtime-macOS.dmg`
2. Drag **Cat Bedtime.app** into **Applications**
3. Launch and complete **cat adoption** on first run
4. If macOS blocks the app: System Settings → Privacy & Security → Open Anyway

### CLI edition

1. Download and extract `cat-bedtime-cli-macos.tar.gz`
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

## Docs

| Doc | Purpose |
| --- | --- |
| [PRODUCT_GOALS.md](PRODUCT_GOALS.md) | Product goals |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture |
| [RELEASE.md](RELEASE.md) | Release signing & notarization |
| [PITFALLS.md](PITFALLS.md) | Known pitfalls |

---

## License

[MIT](LICENSE)
