# SafariF12

在 Safari 中按 F12 切换 Web Inspector（开发者工具），和 Chrome 行为一致。

轻量无 UI 后台运行，仅在 Safari 为前台应用时拦截 F12 并转发为 ⌥⌘I。

## 前置条件

Safari → 设置 → 高级 → 勾选 **"Show features for web developers"**（显示开发功能）

## 编译

```bash
swiftc SafariF12.swift -o SafariF12 -framework Cocoa -framework Carbon
```

## 运行

```bash
./SafariF12
```

首次运行会弹出辅助功能权限请求，前往：

**系统设置 → 隐私与安全性 → 辅助功能** → 允许 SafariF12

## 开机自启

1. 把编译好的 `SafariF12` 放到你喜欢的位置，比如 `~/bin/SafariF12`
2. 创建 `~/Library/LaunchAgents/com.local.safarif12.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.safarif12</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USERNAME/bin/SafariF12</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

把 `YOUR_USERNAME` 替换为你的用户名，然后：

```bash
launchctl load ~/Library/LaunchAgents/com.local.safarif12.plist
```
