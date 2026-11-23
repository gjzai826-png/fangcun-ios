# 方寸

个人房产工作台。界面是中文，数据只留在这台手机上，不登录、不连接云端。

- 显示名：方寸
- 工程 / 产品名：PersonalEstateWorkbench
- Bundle ID：`app.star6979.lettuce4401`
- 版本：0.1.0（10）
- 最低系统：iOS 17.0，仅 iPhone

用 Xcode 打开 `PersonalEstateWorkbench.xcodeproj`，选一台 iPhone 模拟器，直接运行。

## 打出未签名 IPA

仓库里的工作流 **Build unsigned IPA** 只在手动触发时运行，不会在 push 或 pull request 时自动跑。

1. 打开 GitHub 仓库的 Actions。
2. 选择 **Build unsigned IPA**。
3. 点 **Run workflow**。
4. 完成后在 Artifacts 里下载 `PersonalEstateWorkbench-unsigned.ipa`。

这个包没有签名。装到手机前需要你自己用开发者证书签名，例如在 Mac 上执行 `codesign`，或使用你惯用的签名工具。工作流只负责编译和打包。

构建命令是：

```bash
xcodebuild -project PersonalEstateWorkbench.xcodeproj -scheme PersonalEstateWorkbench -sdk iphoneos -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

产物会放进 `Payload/`，再压成 `PersonalEstateWorkbench-unsigned.ipa`。

## 备份

「我的 → 备份、恢复与 CSV」可以导出 `.estatebackup`。这是未加密的包，里面有业务记录和本机照片、视频。恢复前会先做一份安全备份，然后整库替换，不会和现有数据合并。请自己保管文件。

CSV 只是分表导出，不能用来完整恢复。

## 云同步

没有云同步。设置里的「方寸云端同步」是停用说明，不会联网。
