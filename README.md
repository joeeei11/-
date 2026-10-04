# 个人决策助手

一款 Android 个人决策助手，目前可在无网络时搜索和阅读《HowToLiveBetter》指南。底部提供“咨询、记录、资料、指南”四个入口；前三项尚未开放。

## 当前功能

- 按关键词搜索或按章节浏览 657 条内置指南。
- 阅读每条建议的成本、收益、证据等级、来源及指南版本。
- 指南数据随应用打包；搜索和阅读不需要网络，应用也未申请联网权限。

## 构建与验证

需要 Flutter SDK 和 Android SDK。Windows 上请将工程放在全英文路径下构建；中文路径会使当前工具链的 Android 发布构建失败。

```sh
flutter pub get
flutter test
flutter analyze
flutter build apk --release
```

当前 Android 发布构建使用调试签名，仅供测试安装。

## 内置指南

`assets/guide.json` 从 [HowToLiveBetter](https://github.com/eternity4719/HowToLiveBetter) 的固定提交 `b4048d14960fec19c0367f8c0e6891f2b038c7ef` 中 `book/` 目录生成，包含 657 条指南条目。版本号和来源保留在包内。

使用该提交的源码目录重新生成：

```sh
dart run tool/build_guide.dart <source-repo>/book assets/guide.json
```

指南正文版权归原项目作者所有，按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 使用。原项目：[eternity4719/HowToLiveBetter](https://github.com/eternity4719/HowToLiveBetter)。
