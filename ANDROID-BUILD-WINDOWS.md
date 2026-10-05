# Windows 上构建 Android APK：故障复盘与操作步骤

## 本次结果

2026-10-05 在 Windows、Flutter 3.24.5、Gradle 8.3 环境下，最终成功运行 `flutter build apk --debug --no-pub`，得到 `build/app/outputs/flutter-apk/app-debug.apk`。这是调试签名安装包，适合测试安装，不是正式发布包。

## 卡住的原因

1. **项目路径含中文，Flutter 编译失败。** 直接在原目录构建时报 `:app:compileFlutterBuildDebug` 失败，核心错误是 `Cannot invoke "java.io.File.exists()" because "parent" is null`。项目 README 已提示当前 Windows 工具链需要全英文构建路径。
2. **盘符映射位置不对，错误仍在。** 将项目目录本身映射成 `R:\` 后，同一错误复现。改为映射项目的父目录，再从 `R:\19-guidance of life` 构建，才越过这一阶段。这里记录的是实测结果，不把 `parent` 异常的内部成因当作已证实结论。
3. **Gradle 的 Java 进程内存不足。** 越过路径问题后，Gradle 守护进程退出；`android/hs_err_pid*.log` 明确写着 `There is insufficient memory for the Java Runtime Environment to continue`。当时配置为 `-Xmx4G -XX:MaxMetaspaceSize=2G`。将 `android/gradle.properties` 调整为 `-Xmx2G -XX:MaxMetaspaceSize=1G` 和 `org.gradle.workers.max=2` 后，构建成功。

## 下次怎么做

在项目根目录打开 PowerShell。先确认 `R:` 没有被占用；若已占用，换一个空闲盘符，并同步替换下面的 `R:`。

```powershell
subst
$projectDir = (Resolve-Path .).Path
$projectName = Split-Path $projectDir -Leaf
$projectParent = Split-Path $projectDir -Parent
subst R: $projectParent
Set-Location ("R:\" + $projectName)
flutter pub get
flutter build apk --debug --no-pub
Get-Item build/app/outputs/flutter-apk/app-debug.apk | Select-Object FullName, Length, LastWriteTime
Get-FileHash build/app/outputs/flutter-apk/app-debug.apk -Algorithm SHA256
Set-Location $projectDir
subst R: /D
```

`subst` 映射的是父目录，因此项目在映射盘符下仍是一个子目录。若构建失败，先看完整错误和最新的 `android/hs_err_pid*.log`，不要直接使用 `build` 目录里原有的 APK。只有构建命令成功，且 APK 的修改时间晚于本次构建开始时间，才能认为它是新包。

## 已验证与未验证

- 本次新调试包的修改时间为 2026-10-05 15:09:13，大小为 193,860,837 字节；SHA-256 为 `CB1137F122D0F80C1743218DEAE389E624E82A0FE7E7CA547EB71E6855AF0DC6`。这些值只用于识别本次构建，下次构建会变化。
- 构建成功不等于真机验收；本次未连接 Android 设备，尚未在手机上检查安装和界面。
