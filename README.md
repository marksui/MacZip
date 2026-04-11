# MyArchive

一个给 macOS 使用的简单压缩/解压 + 密码保护工具。

这个项目分两层：
- **C++ 核心**：自定义归档格式、zlib 压缩、AES-256-GCM 加密、PBKDF2-HMAC-SHA256 密钥派生。
- **SwiftUI 图形界面**：文件选择、密码输入、压缩/解压按钮、状态显示。

## 现在有什么

- `myarchive-cli`：命令行版本，已在当前环境实际编译并做过打包/解包验证。
- `MyArchiveGUI`：macOS SwiftUI 图形界面源码。当前环境不是 macOS，所以 **GUI 没有在这里运行验证**，但源码和打包脚本已经配好。

## 功能范围

- 支持打包单文件或整个目录。
- 支持解包到指定输出目录。
- 使用 `zlib` 压缩。
- 使用 `AES-256-GCM` 加密。
- 使用 `PBKDF2-HMAC-SHA256` 从密码派生密钥。
- 不支持符号链接。
- 第一版没有进度百分比，GUI 只有忙碌指示器。

## 目录结构

- `Sources/ArchiveCore/`：C++ 核心实现
- `Sources/ArchiveBridge/`：给 Swift 调用的 C 桥接层
- `Sources/MyArchiveCLI/`：CLI
- `Sources/MyArchiveGUI/`：SwiftUI GUI
- `scripts/package_app_macos.sh`：在 macOS 上打包 `.app`
- `scripts/smoke_test_cli.sh`：CLI 冒烟测试

## CLI 构建和使用

### Linux / macOS

```bash
swift build -c release --product myarchive-cli
./.build/release/myarchive-cli pack ./some_folder -o ./backup.myarc -p your_password -l normal
./.build/release/myarchive-cli unpack ./backup.myarc -d ./restore_here -p your_password
```

压缩等级：
- `fast`
- `normal`
- `high`

## macOS GUI 构建

### 前置条件

- 安装 Xcode 或 Xcode Command Line Tools
- 如果编译时找不到 OpenSSL，执行：

```bash
brew install openssl@3
```

### 生成可双击的 `.app`

```bash
./scripts/package_app_macos.sh
```

脚本会做这些事：
- 构建 `MyArchiveGUI`
- 生成 `dist/MyArchive.app`
- 复制 Swift 运行时到 app bundle
- 如果检测到 Homebrew 的 `libcrypto`，会一起打进 app bundle
- 做 ad-hoc codesign

## 安全说明

这不是 7-Zip 兼容实现，也不是 7z 文件格式。

它是一个**自定义归档格式**：
1. 先把文件/目录写成内部 bundle
2. 用 zlib 压缩
3. 用 AES-256-GCM 加密
4. 输出 `.myarc` 文件

这意味着：
- 不能直接用 7-Zip 打开 `.myarc`
- 你需要用本项目自带工具解包

## 归档格式概览

文件布局：
- 固定头部（magic / version / KDF 参数 / 长度信息）
- salt
- IV
- ciphertext
- GCM tag

加密时把固定头部作为 AAD 做认证。

## 已验证内容

我已经在当前环境验证过：
- 目录打包/解包
- 单文件打包/解包
- 错误密码会解密失败

GUI 没法在这里启动，因为当前环境不是 macOS。

## 后续可以继续加的东西

- 真正的进度回调
- 拖拽文件到窗口
- 多线程压缩
- 更强的归档元数据
- Finder 快速操作/右键菜单

