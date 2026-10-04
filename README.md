# 个人决策助手

一款面向个人使用的 Android 决策助手。它在设备本地提供《HowToLiveBetter》指南、个人资料管理和自有模型连接配置；“咨询”和“记录”功能仍在开发中。

## 当前功能

- 按关键词搜索或按章节浏览 657 条内置指南。
- 阅读每条建议的成本、收益、证据等级、来源及指南版本。
- 在“指南包信息”查看完整版本、更新日期、项目署名、链接和 CC BY 4.0 许可。
- 用户主动检查官方 GitHub Release；发现兼容的 `guide.json` 后，确认版本才会下载并安装。更新失败不影响离线浏览。
- 指南数据随应用打包；搜索和阅读不需要网络。检查更新或打开外部链接时使用网络。
- 按需保存、修改或删除六类个人资料及答复偏好。资料保存在设备的加密存储中。
- 配置、测试或删除 OpenAI 兼容模型连接。API Key 只保存在系统安全存储中，页面不会回显；可设置每日请求次数和单次答复长度上限。

## 隐私

- 不提供账号、云同步、模型代理、远程分析或广告追踪。
- 本地指南检索不会上传问题或个人资料。
- 模型连接测试只发送固定的 `ping` 请求，不发送个人资料。

## 构建与验证

需要 Flutter SDK 和 Android SDK。Windows 上请将工程放在全英文路径下构建；中文路径会使当前工具链的 Android 发布构建失败。

```sh
flutter pub get
flutter test
flutter analyze
flutter build apk --release
```

当前 Android 发布构建使用调试签名，仅供测试安装。请在全英文路径下构建，或通过 Windows 的盘符映射使用全英文工作路径。

## 内置指南

`assets/guide.json` 从 [HowToLiveBetter](https://github.com/eternity4719/HowToLiveBetter) 的固定提交 `b4048d14960fec19c0367f8c0e6891f2b038c7ef` 中 `book/` 目录生成，包含 657 条指南条目。版本号和来源保留在包内。

使用该提交的源码目录重新生成：

```sh
dart run tool/build_guide.dart <source-repo>/book assets/guide.json
```

指南正文版权归原项目作者所有，按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 使用。原项目：[eternity4719/HowToLiveBetter](https://github.com/eternity4719/HowToLiveBetter)。

更新包须位于官方 Release，资产名为 `guide.json`，包内 `version` 须与 Release 标签一致，并保留项目署名、许可和完整条目字段。2026-10-05 官方可见的 `epub-latest` Release 仅提供 EPUB、HTML、PDF，暂时没有兼容的指南包。
