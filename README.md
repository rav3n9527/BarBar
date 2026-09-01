# 🎵 BarBar

**打字节奏可视化 — 在 Touch Bar 上释放粒子波纹**

每次按键都会触发一波视觉效果 + 音效，连击越多效果越炫。打字越快，Touch Bar 上越热闹。

## 功能特性

- 🎨 **9 种视觉效果** — 粒子爆炸、水波纹、光雨、弹跳球、冲击波、激光脉冲、流星、频谱、火焰
- 🎵 **7 种音效** — 五声音阶、电子合成、音乐盒、打击乐、钢琴、音效1、音效2
- ⌨️ **按键物理定位** — 粒子在 Touch Bar 上从对应按键的真实位置爆开（基于 MacBook 键盘布局校准）
- 💥 **Combo 连击** — 实时显示连击数，连击越高效果越强
- 📊 **菜单栏切换** — 点击 🎵 图标随时切换效果和音效，偏好自动保存
- ⏱️ **智能让出** — 停止输入 3 秒自动让出 Touch Bar，恢复系统控制条
- 💤 **自动休眠** — 空闲自动清理，不占资源

## 系统要求

- macOS 10.15 (Catalina) 或更高
- 带 Touch Bar 的 MacBook Pro（2016–2020 款）
- Xcode Command Line Tools（编译用）

## 编译

```bash
cd BarBar
chmod +x build.sh
./build.sh
```

编译产物在 `build/BarBar.app`。

## 运行

```bash
./run.sh
```

> 推荐用 `run.sh` 直接运行二进制，避免 `open` 对菜单栏 app 的激活限制。
> 按住 `Ctrl+C` 退出。

### 首次运行

macOS 会弹窗要求授予 **辅助功能权限**（Accessibility），因为应用需要全局监听键盘事件：

1. 打开 **系统设置 → 隐私与安全 → 辅助功能**
2. 点击 `+` 添加 `BarBar.app`
3. 重新启动应用

## 项目结构

```
BarBar/
├── BarBar/
│   ├── main.swift               # 入口
│   ├── AppDelegate.swift        # 应用生命周期 & 组件组装
│   ├── Particle.swift           # 粒子数据模型
│   ├── Ripple.swift             # 波纹环数据模型
│   ├── ParticleSystem.swift     # 粒子系统管理器（9 种效果）
│   ├── AudioEngine.swift        # 音频引擎（7 种音效）
│   ├── KeyboardMonitor.swift    # CGEvent 全局键盘监听
│   ├── KeyPosition.swift        # 按键物理位置映射
│   ├── Settings.swift           # 偏好持久化
│   ├── BarBarView.swift        # Touch Bar 渲染视图
│   ├── TouchBarHack.swift       # 私有 API 桥接（Swift 侧）
│   ├── TouchBarBridge.h/.m      # 私有 API 桥接（ObjC 侧）
│   └── Info.plist               # 应用配置
├── build.sh                     # 编译脚本
├── run.sh                       # 运行脚本
└── README.md                    # 本文件
```

## 技术实现

- **全局键盘监听**: `CGEvent.tapCreate` 创建 HID 级别的事件拦截器
- **粒子系统**: 自定义物理模拟（速度、重力、阻力、反弹、生命周期）
- **Touch Bar 接管**: `NSTouchBar` + 私有 DFRFoundation 系统模态 API（独占整个 Touch Bar）
- **音频合成**: `AVAudioEngine` 实时合成（正弦/锯齿/噪声 + 泛音 + 包络）
- **动画驱动**: Timer 60fps 渲染

## 自定义

- **按键定位**: 修改 `KeyPosition.swift` 的 `anchors` 表和 `globalOffset` 微调偏移
- **效果参数**: 修改 `ParticleSystem.swift` 的 `Config`（粒子数、速度、半径等）
- **音阶**: 修改 `AudioEngine.swift` 的 `pianoScale` / `pentatonicScale` 数组
- **让出时间**: 修改 `AppDelegate.swift` 的 `idleDismissDelay`

## License

MIT
