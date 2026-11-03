# Contributing · 参与贡献

欢迎 issue 和 PR。Issues and pull requests are welcome.

## 开发 / Development

Requirements: macOS 13+, Xcode 16+ (Swift 5.9+).

```bash
./build.sh                                   # build/Jot.app (signs ad-hoc if no Developer ID is found)
"build/Jot.app/Contents/MacOS/Jot" --selftest   # editing, formats, writer, clipboard, OCR checks
"build/Jot.app/Contents/MacOS/Jot" --snapshot shot.png "示例文字" --dark   # render the panel offscreen
./install-local.sh                           # replace /Applications/Jot.app and relaunch
```

- Keep captures verbatim: no automatic Markdown decoration of user content.
- Visual style is Vercel-like black and white with Geist; please attach before/after snapshots for UI changes.
- `./release.sh` (maintainer only) builds a universal, notarized DMG.
