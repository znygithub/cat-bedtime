# 发布流程

## 产物

| 产物 | 脚本 |
| --- | --- |
| `dist/Cat-Bedtime-macOS.dmg` | `scripts/release-macos.sh` |
| `dist/cat-bedtime-cli-macos.tar.gz` | `scripts/release-cli-macos.sh` |

App 构建会先跑 `src/overlay/build.sh` 与 `src/app/build.sh`；bundle 内含 `zzz-overlay`、`src/cli/`、`lib/`、`assets/`、`locales/messages.json`。

## 发布前

1. 更新 `CHANGELOG.md`
2. `for t in tests/test-*.sh; do bash "$t"; done`
3. 确认 overlay 为 universal binary（若目标架构需要）
4. App：onboarding、预览、Toast（`zzz-app --toast-bedtime-warning 5`）、launchd
5. CLI：`install.sh`、`zzz init`、`zzz test 10`
6. 维护者本地 Developer ID 签名 + 公证（见 `scripts/release-macos.sh`）

## GitHub Release

Assets：DMG、CLI tar.gz、版本说明。README 下载链接指向最新 tag。
