# 发布 macOS 网站下载包

公开放到网站下载时，不能使用 `Apple Development` 证书。需要：

1. 已加入 Apple Developer Program
2. 在钥匙串里安装 `Developer ID Application` 证书
3. 保存一次 notarization 凭据

## 准备证书

在 Xcode 里打开 Settings > Accounts > Manage Certificates，添加 `Developer ID Application` 证书

确认本机能看到发布证书：

```bash
security find-identity -v -p codesigning
```

输出里需要出现 `Developer ID Application: ...`

## 保存公证凭据

使用 app-specific password，不要把密码写进命令或聊天记录里；不传 `--password` 时，`notarytool` 会弹出安全输入提示

```bash
xcrun notarytool store-credentials cat-bedtime-notary \
  --apple-id 1339975893@qq.com \
  --team-id LGQX6KS72C
```

如果 Team ID 变化，可以运行时覆盖：

```bash
APPLE_TEAM_ID=YOUR_TEAM_ID scripts/release-macos.sh
```

## App 版发布包

App 版是标准拖拽安装 DMG：打开后只显示 `Cat Bedtime.app` 和 `Applications`。用户把 app 拖进 Applications 即可

```bash
scripts/release-macos.sh
```

成功后上传：

```bash
dist/Cat-Bedtime-macOS.dmg
```

脚本会完成：

- 构建 universal `zzz-overlay` 和 `Cat Bedtime.app`
- 把 App 版运行所需的 `lib/`、`src/cli/`、`assets/` 和 `zzz-overlay` 打进 app bundle
- 使用 `Developer ID Application` 加 hardened runtime 签名
- 生成拖拽安装 DMG
- 提交 Apple notarization
- staple notarization ticket
- 用 `spctl` 做 Gatekeeper 校验

## CLI 版发布包

CLI 版不包含 `Cat Bedtime.app`，只包含 `zzz`、`zzz-overlay`、shell 运行脚本和素材：

```bash
scripts/release-cli-macos.sh
```

成功后上传：

```bash
dist/cat-bedtime-cli-macos.tar.gz
```

CLI 包中的 `install.sh` 会安装到 `~/.timetosleep/` 并创建 `zzz` 命令
