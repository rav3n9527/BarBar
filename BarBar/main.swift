import Cocoa

// 入口点——创建应用和代理，然后运行
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
