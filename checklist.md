🧼 macOS 清理脚本：完整清单 + 交互界面设计示意

⸻

✅ 一、可清理内容清单（分模块）

🗃️ 1. 用户级缓存与日志

类别 路径
用户缓存 ~/Library/Caches/_
用户日志 ~/Library/Logs/_
Crash 报告 ~/Library/Application Support/CrashReporter/_
SavedState ~/Library/Saved Application State/_
临时项目文件 ~/Library/Application Support/com.apple.sharedfilelist/\*

⸻

🖥 2. 系统级缓存（需 sudo 权限）

类别 路径
系统缓存 /Library/Caches/_
临时目录 /private/var/folders/_
系统日志 /private/var/log/_
Diagnostic 报告 /Library/Logs/DiagnosticReports/_

⸻

🌐 3. 浏览器缓存

浏览器 路径
Safari ~/Library/Caches/com.apple.Safari/_
Chrome ~/Library/Caches/com.google.Chrome/_ 和 Application Cache/_
Firefox ~/Library/Application Support/Firefox/Profiles/_.default*/cache2/*

⸻

👨‍💻 4. 开发工具与 CLI 工具缓存

工具 路径或命令
Xcode DerivedData, Archives, iOS DeviceSupport
CoreSimulator ~/Library/Developer/CoreSimulator/Caches/_
VSCode ~/Library/Application Support/Code/Cache/_
npm / node ~/.npm/_, ~/.node-gyp/_
Homebrew ~/Library/Caches/Homebrew/_，命令：brew cleanup
Python pip ~/Library/Caches/pip/_

⸻

🧩 5. 常见应用缓存（可选）

应用 路径
Adobe ~/Library/Application Support/Adobe/Common/Media Cache Files/_
Zoom ~/Library/Application Support/zoom.us/data/_
Discord ~/Library/Application Support/discord/Cache/_
Spotify ~/Library/Application Support/Spotify/PersistentCache/_

⸻

🗑️ 6. 其他

类别 路径
垃圾桶 ~/.Trash/_, /Volumes/_/.Trashes/_
旧 iPhone 备份 ~/Library/Application Support/MobileSync/Backup/_

⸻

💻 二、交互式终端界面示例图（伪图）

Welcome to CleanMac - Interactive Cleanup Utility 🧼

This tool helps you safely clean cache and junk files from your macOS system.
You will be asked before anything is deleted. Let's begin.

────────────────────────────────────────────────────────────────────

[1] Clean user-level caches (Safari, Chrome, system logs, etc.)?
→ ~/Library/Caches/
Do you want to clean this? [y/n]: y
🧹 Cleaning... ✅ Done.

[2] Clean system caches (requires sudo)?
→ /Library/Caches/
Do you want to clean this? [y/n]: n
🚫 Skipped.

[3] Do you have Xcode installed?
→ Clean DerivedData and Archives? [y/n]: y
🧹 Cleaning Xcode DerivedData... ✅ Done.

[4] Clean Trash?
→ ~/.Trash/
Do you want to empty your Trash now? [y/n]: y
🧹 Emptying... ✅ Done.

[5] Clean npm and node modules cache?
→ ~/.npm/, ~/.node-gyp/
Do you want to clean this? [y/n]: n
🚫 Skipped.

────────────────────────────────────────────────────────────────────

✨ All selected items have been cleaned. Thank you!
