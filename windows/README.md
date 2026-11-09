# 乔木闪记 · Jot Windows 原生版

乔木闪记（Jot）的 Windows 原生移植版本，基于 **.NET 9 + WPF + Windows.Media.Ocr (WinRT 10.0.19041+)** 构建。

## 功能特性

1. **Win+J 随手记（对应 Mac ⌘⇧J）**：
   - 随时呼出居中卡片输入框，支持实时 Markdown 格式工具栏与快捷键（`Ctrl+B`/`Ctrl+I`/`Ctrl+K`/`Ctrl+E`）。
   - 智能列表续写与自动编号、待办切换。
   - `Ctrl+Enter` 快速存入今日日记，`Esc` 关闭并暂存草稿。
2. **Win+K 一键收录（对应 Mac ⌘⇧K）**：
   - 全局低级键盘钩子，精准屏蔽系统投屏并抓取前台选中文字/网页真实 URL 与标题/代码文件名。
   - 临时剪贴板自动恢复机制，不污染用户日常剪贴板历史。
   - 屏幕右下角轻量 Toast 提示，带 3 秒撤销（Undo）。
3. **截图文字本地离线识别（对应 Mac 本机 OCR）**：
   - 采用 Windows 原生 `Windows.Media.Ocr.OcrEngine`（支持中文 zh-Hans-CN 与英文），免额外外挂模型，离线毫秒级识别。
   - 图片以 Obsidian 兼容格式写入日记，折叠块附带识别出的文本供日后检索。
4. **多模式存储**：
   - 自动扫描并连接本地运行的 Obsidian 仓库。
   - 也支持普通 Markdown 文件夹模式，Typora / VS Code 均可直接打开。
   - 默认保存到末尾。在「设置 → 存储与仓库」打开「新内容插入正文开头」，可把新内容放在开头的 YAML 属性和一级标题之后。

## 构建与运行

环境需求：Windows 10 2004+ (Build 19041+) 或 Windows 11，.NET 9.0 SDK。

```bash
# 编译并运行
dotnet build windows/QiaomuJot/QiaomuJot.csproj
dotnet run --project windows/QiaomuJot/QiaomuJot.csproj

# 执行自动化测试套件
dotnet run --project windows/QiaomuJot/QiaomuJot.csproj -- --selftest

# 独立分发发布
dotnet publish windows/QiaomuJot/QiaomuJot.csproj -c Release -o dist/
```
