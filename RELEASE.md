# 发布清单（维护者）

面向 GitHub Releases / 官网下载。用户安装说明见 [README.md](README.md)。

## 发布前检查

- [ ] `locales/messages.json` 已更新（`python3 scripts/generate-messages.py`）
- [ ] `assets/cat-bedtime.mov` 存在（锁屏动画，发布包会打入）
- [ ] 本地测试：`bash install.sh` → `zzz init` → `zzz test 10`
- [ ] 本地测试：打开 `bin/Cat Bedtime.app` 完成领养并预览锁屏
- [ ] 钥匙串有 `Developer ID Application` 证书

## 构建产物

```bash
# App 版 DMG（签名 + 公证）
scripts/release-macos.sh

# CLI 版 tar.gz
scripts/release-cli-macos.sh
```

输出：

| 文件 | 上传名 |
| --- | --- |
| `dist/Cat-Bedtime-macOS.dmg` | `Cat-Bedtime-macOS.dmg` |
| `dist/cat-bedtime-cli-macos.tar.gz` | `cat-bedtime-cli-macos.tar.gz` |

CLI 包内须包含：`bin/`、`lib/`、`src/cli/`、`locales/messages.json`、`assets/`、`install.sh`。

## 创建 GitHub Release

```bash
gh release create v1.0.0 \
  dist/Cat-Bedtime-macOS.dmg \
  dist/cat-bedtime-cli-macos.tar.gz \
  --title "v1.0.0" \
  --notes "猫猫困了 / Cat Bedtime 首个公开发布。App 版 DMG + CLI 版 tar.gz。"
```

发布后记得到 [Releases](https://github.com/znygithub/cat-bedtime/releases) 页面确认两个附件可下载。

## 证书与公证

公网分发需 **Developer ID Application**（不能用仅开发证书）。

```bash
security find-identity -v -p codesigning
```

保存公证凭据（**勿把密码写进仓库**）：

```bash
xcrun notarytool store-credentials cat-bedtime-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID
```

`scripts/release-macos.sh` 会：构建 universal App + overlay → 签名 → 生成 DMG → `notarytool submit` → `stapler staple` → `spctl` 校验。

跳过公证（仅内测）：

```bash
SKIP_NOTARIZE=1 scripts/release-macos.sh
```

## App 版 DMG 体验

打开 DMG 后仅显示 `Cat Bedtime.app` 与 `Applications` 快捷方式，拖拽安装。

## CLI 版说明

解压后目录名为 `cat-bedtime-cli/`，用户需：

```bash
cd cat-bedtime-cli && bash install.sh
```
