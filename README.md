# Sillycard

在 macOS 上管理、预览与编辑符合 Silly Tavern 规范的 PNG 角色卡（元数据内嵌于 PNG `tEXt` 块，解析规则与 SillyTavern 主仓库中的 [`src/character-card-parser.js`](https://github.com/SillyTavern/SillyTavern/blob/release/src/character-card-parser.js) 对齐：`ccv3` 优先于 `chara`，写入时生成 `chara` 并在 JSON 可解析时附加 `ccv3`）。

## 构建与运行

需要 Xcode 15+ 或 Swift 5.9+ 工具链。

### Xcode 工程（推荐，用于签名 / Archive）

在本仓库根目录双击或打开 `Sillycard.xcodeproj`（不再使用已弃用的 `…/SillyTavern/Sillycard/` 嵌套路径）。App 的 **Bundle ID** 为 `xyz.nowtiny.sillycard`；在 **Signing & Capabilities** 中选择你的 **Team** 后即可打包。

若修改了目录结构或 `project.yml`，可在终端执行：`xcodegen generate`（需安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)）。

### SwiftPM（命令行）

```bash
cd "$(git rev-parse --show-toplevel)"   # 本仓库根目录
swift build -c release
open .build/release/Sillycard
```

也可在 Xcode 中 **File → Open** 选择 `Package.swift` 作为备选方式（与 `.xcodeproj` 二选一即可，避免重复编译同一份源码时混淆）。

## 使用说明

1. **打开文件夹**：选择包含 `.png` 角色卡的根目录（会递归扫描子文件夹）。
2. **左侧**：子文件夹分类与标签多选筛选。
3. **中间**：卡片网格；**双击**在独立窗口中打开大 JSON 编辑。
4. **右侧 Inspector**：预览核心字段；显示上次载入元数据时间；**刷新元数据**从磁盘重新解析 PNG。
5. **预览 / 编辑**：Inspector 与单卡窗口均支持模式切换；编辑后可保存或另存为。

## 缓存

同一文件再次选中时优先使用内存缓存（并校验修改时间）；保存后立即用已写入的 JSON 更新缓存，预览无需重新解析 PNG。
