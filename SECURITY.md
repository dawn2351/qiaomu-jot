# Security · 安全

乔木闪记 runs locally. It reads the current selection through macOS Accessibility, temporarily uses the clipboard to copy rich selections (and restores it), and writes Markdown files only into the folder you choose. It sends nothing to any server; the only network request is fetching a page title when you paste a bare link (can be turned off in Settings → 记录).

If you find a vulnerability (e.g. content reaching an unexpected location, a password-manager copy being captured, or clipboard data leaking), please **don't open a public issue**. Use GitHub's [private vulnerability reporting](https://github.com/joeseesun/qiaomu-jot/security/advisories/new) or email vista8@gmail.com.

如发现安全问题，请不要公开提 issue，使用上面的私密报告入口或发邮件。
