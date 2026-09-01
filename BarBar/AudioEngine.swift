import AVFoundation
import Foundation

/// 可从菜单切换的声音模式。
enum SoundMode: Int, CaseIterable {
    case pentatonic = 0
    case synth = 1
    case musicBox = 2
    case percussion = 3
    case piano = 4
    case mechanical = 5
    case sword = 6
    case telegraph = 7
    case blaster = 8

    var displayName: String {
        switch self {
        case .pentatonic: return "五声音阶"
        case .synth:      return "电子合成"
        case .musicBox:   return "音乐盒"
        case .percussion: return "打击乐"
        case .piano:      return "钢琴"
        case .mechanical: return "音效1"
        case .sword:      return "音效2"
        case .telegraph:  return "发电报"
        case .blaster:    return "激光枪"
        }
    }
}

/// 使用五声音阶生成乐音，这样任意按键组合听起来都悦耳。
/// 基于 AVAudioEngine 与合成波形实现。
class AudioEngine {
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var isRunning = false

    /// 当前声音模式
    var mode: SoundMode = .pentatonic

    /// 音效总音量倍率（0.0 ~ 1.0），会应用到所有模式。
    var masterVolume: Float = 0.7

    /// 音调倍率（0.5 ~ 2.0），1.0 = 标准音高。
    /// 会等比缩放所有模式的基频。
    var pitchShift: Float = 1.0

    /// 五声音阶频率（跨两个八度的 C 大调五声音阶）
    /// 这些是"黑键"频率，它们组合在一起总是很和谐
    static let pentatonicScale: [Float] = [
        261.63, // C4
        293.66, // D4
        329.63, // E4
        392.00, // G4
        440.00, // A4
        523.25, // C5
        587.33, // D5
        659.25, // E5
        783.99, // G5
        880.00, // A5
        1046.50, // C6
        1174.66, // D6
    ]

    /// 打击乐模式的根频率（低沉、类似鼓点的闷响）
    static let percussionNotes: [Float] = [
        110.00, 123.47, 146.83, 164.81, 196.00, 220.00,
        246.94, 293.66, 329.63, 392.00, 440.00, 493.88,
    ]

    /// 钢琴模式使用的两个八度 C 大调音阶（多音高）
    static let pianoScale: [Float] = [
        261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88, 523.25,  // C4–C5
        587.33, 659.25, 698.46, 783.99, 880.00, 987.77, 1046.50,        // D5–C6
    ]

    private var noteIndex = 0
    private var sampleRate: Double = 44100
    private var outputFormat: AVAudioFormat!

    /// 活跃的播放器节点，防止被提前释放导致引擎节点泄漏。
    /// 每个音符对应一个节点，播放完毕后移除并 detach。
    private var activePlayers: [AVAudioPlayerNode] = []
    /// 同时允许的最大播放器数量，超出时停掉最旧的，避免极速打字时堆积。
    private let maxConcurrentPlayers = 8

    init() {
        setupAudio()
    }

    private func setupAudio() {
        outputFormat = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate

        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: outputFormat)

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("AudioEngine: failed to start — \(error)")
            isRunning = false
        }
    }

    // MARK: - 音调生成

    /// 根据按键码播放一个短音，使用当前模式。
    func playNote(forKeyCode keyCode: UInt16, volume: Float = 0.3) {
        guard isRunning else { return }

        // 应用总音量倍率
        let outVolume = volume * masterVolume

        switch mode {
        case .pentatonic:
            let freq = Self.pentatonicScale[noteIndex % Self.pentatonicScale.count] * pitchShift
            noteIndex += 1
            playTone(frequency: freq, volume: outVolume,
                     waveform: .sine, duration: 0.25,
                     harmonics: [2.0: 0.3, 3.0: 0.1])

        case .synth:
            let freq = Self.pentatonicScale[noteIndex % Self.pentatonicScale.count] * pitchShift
            noteIndex += 1
            playTone(frequency: freq, volume: outVolume,
                     waveform: .saw, duration: 0.18,
                     harmonics: [:])

        case .musicBox:
            let freq = Self.pentatonicScale[noteIndex % Self.pentatonicScale.count] * 2.0 * pitchShift
            noteIndex += 1
            playTone(frequency: freq, volume: outVolume,
                     waveform: .sine, duration: 0.45,
                     harmonics: [2.0: 0.1])

        case .percussion:
            let freq = Self.percussionNotes[noteIndex % Self.percussionNotes.count] * pitchShift
            noteIndex += 1
            playTone(frequency: freq, volume: outVolume * 1.2,
                     waveform: .noise, duration: 0.15,
                     harmonics: [:])

        case .piano:
            let freq = Self.pianoScale[noteIndex % Self.pianoScale.count] * pitchShift
            noteIndex += 1
            playPiano(frequency: freq, volume: outVolume)

        case .mechanical:
            // 每个按键的声音都略有不同（音高抖动 + 敲击变化）
            playMechanical(volume: outVolume)

        case .sword:
            playSword(volume: outVolume)

        case .telegraph:
            playTelegraph(volume: outVolume)

        case .blaster:
            playBlaster(volume: outVolume)
        }
    }

    // MARK: - 波形合成

    private enum Waveform {
        case sine
        case saw
        case noise
    }

    /// 在新的播放器节点上播放预先填充好的缓冲区。
    /// 播放器节点被强引用保存在 activePlayers 中，播放完毕后移除并 detach，
    /// 防止节点泄漏导致音频混叠。
    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        let player = AVAudioPlayerNode()
        activePlayers.append(player)
        engine.attach(player)
        engine.connect(player, to: mixer, format: outputFormat)

        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.releasePlayer(player)
            }
        }

        player.play()

        // 限制并发播放器数量：极速打字时丢弃最旧的节点，防止堆积
        if activePlayers.count > maxConcurrentPlayers {
            let oldest = activePlayers.removeFirst()
            oldest.stop()
            engine.detach(oldest)
        }
    }

    /// 播放完毕后从活跃列表移除并 detach 节点。
    private func releasePlayer(_ player: AVAudioPlayerNode) {
        activePlayers.removeAll { $0 === player }
        engine.detach(player)
    }

    /// 创建指定长度和音量比例、以零填充的 PCM 缓冲区。
    private func makeBuffer(duration: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        return buffer
    }

    /// 将单个音符合成到缓冲区，并在新的播放器节点上播放。
    private func playTone(frequency: Float, volume: Float,
                          waveform: Waveform, duration: Double,
                          harmonics: [Double: Float]) {
        guard let buffer = makeBuffer(duration: duration) else { return }

        let channels = Int(outputFormat.channelCount)
        let freqD = Double(frequency)
        let attackFrames = Int(sampleRate * 0.005)      // 5ms 起音
        let releaseStart = Int(sampleRate * 0.15)       // 150ms 处开始释放
        let releaseFrames = Int(sampleRate * 0.1)       // 100ms 释放

        for ch in 0 ..< channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            for frame in 0 ..< Int(buffer.frameLength) {
                let t = Double(frame) / sampleRate
                var sample: Double

                switch waveform {
                case .sine:
                    sample = sin(2.0 * .pi * freqD * t)
                    for (mult, amp) in harmonics {
                        sample += Double(amp) * sin(2.0 * .pi * freqD * mult * t)
                    }

                case .saw:
                    // 近似的带限锯齿波：叠加基波的几个谐波
                    sample = 0
                    for n in 1...6 {
                        sample += (1.0 / Double(n)) * sin(2.0 * .pi * freqD * Double(n) * t)
                    }
                    sample *= 0.5

                case .noise:
                    // 带音高包络的类棕色噪声脉冲（鼓腔声）
                    let random = Double.random(in: -1 ... 1)
                    let pitchFalloff = exp(-t * 25.0) // 快速音高下降，产生"砰"的闷响
                    sample = random * pitchFalloff
                    // 叠加一点基波以增强腔体共鸣
                    sample += 0.4 * sin(2.0 * .pi * freqD * t) * exp(-t * 12.0)
                }

                // ADSR 包络（简化版）
                if frame < attackFrames {
                    sample *= Double(frame) / Double(attackFrames)
                } else if frame > releaseStart {
                    let releaseProgress = Double(frame - releaseStart) / Double(releaseFrames)
                    sample *= max(0, 1.0 - releaseProgress)
                }

                data[frame] = Float(sample) * volume * 0.4
            }
        }

        playBuffer(buffer)
    }

    // MARK: - 钢琴

    /// 原声钢琴风格：多个谐波各自有不同的衰减速率
    /// （高次谐波衰减更快），轻柔的琴槌起音，以及缓慢的尾音。
    private func playPiano(frequency: Float, volume: Float) {
        let duration = 0.9
        guard let buffer = makeBuffer(duration: duration) else { return }
        let channels = Int(outputFormat.channelCount)
        let f0 = Double(frequency)

        // 分音结构：[谐波, 相对振幅, 衰减速率]
        let partials: [(mult: Double, amp: Double, decay: Double)] = [
            (1.0, 1.00, 2.2),   // 基波
            (2.0, 0.45, 3.5),   // 二次谐波（亮度）
            (3.0, 0.20, 5.0),
            (4.0, 0.12, 6.5),
            (5.0, 0.07, 8.0),
            (6.0, 0.04, 9.5),
        ]

        for ch in 0 ..< channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            for frame in 0 ..< Int(buffer.frameLength) {
                let t = Double(frame) / sampleRate

                var sample = 0.0
                for p in partials {
                    let f = f0 * p.mult
                    // 轻微的非谐波性以增强真实感
                    let fIn = f * (1.0 + 0.0004 * p.mult * p.mult)
                    sample += p.amp * sin(2.0 * .pi * fIn * t) * exp(-p.decay * t)
                }

                // 琴槌起音：非常快（约 3ms），带轻微打击感的咔哒声
                let attack = min(1.0, t / 0.003)
                // 琴体共鸣：起始处轻微的低频增益
                let body = 1.0 + 0.6 * exp(-t * 18.0)

                sample *= attack * body

                data[frame] = Float(sample * 0.5) * volume * 0.5
            }
        }

        playBuffer(buffer)
    }

    // MARK: - 音效1（原为"机械键盘"）
    /// 明亮的"click"声（经过滤波的噪声脉冲）加上低沉的"thock"共鸣。
    /// 每次按键都会略有随机变化。
    private func playMechanical(volume: Float) {
        let duration = 0.09
        guard let buffer = makeBuffer(duration: duration) else { return }
        let channels = Int(outputFormat.channelCount)

        // 每次按键随机化：click 亮度与 thock 音高略有变化
        // 同时应用音调倍率（pitchShift）
        let clickFreq = Double.random(in: 1200 ... 2600) * Double(pitchShift)
        let thockFreq = Double.random(in: 140 ... 220) * Double(pitchShift)
        let clickDecay = Double.random(in: 45 ... 70)

        for ch in 0 ..< channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            for frame in 0 ..< Int(buffer.frameLength) {
                let t = Double(frame) / sampleRate

                // click：短促的滤波噪声脉冲（通过对连续的随机样本
                // 做差分实现近似高通效果）。
                let n = Double.random(in: -1 ... 1)
                var click = n * exp(-t * clickDecay)
                // 一个音调性的"ping"声增添开关特有的明亮度
                click += 0.35 * sin(2.0 * .pi * clickFreq * t) * exp(-t * 60.0)

                // thock：低沉的主体共鸣
                let thock = 0.7 * sin(2.0 * .pi * thockFreq * t) * exp(-t * 30.0)

                // 极快的起音
                let attack = min(1.0, t / 0.001)

                var sample = (click + thock) * attack
                // 软削波以保持冲击力
                sample = tanh(sample * 1.2) * 0.8

                data[frame] = Float(sample) * volume * 1.1
            }
        }

        playBuffer(buffer)
    }

    // MARK: - 音效2（原为"剑气"）
    /// 嗖嗖的扫频声：上升的啁啾音调混合轻盈的噪声。
    private func playSword(volume: Float) {
        let duration = 0.22
        guard let buffer = makeBuffer(duration: duration) else { return }
        let channels = Int(outputFormat.channelCount)

        // 扫频参数——剑刃从低沉的"whoosh"划过到尖锐的"shing"
        // 同时应用音调倍率（pitchShift）
        let fStart = Double.random(in: 220 ... 340) * Double(pitchShift)
        let fEnd = Double.random(in: 1400 ... 2100) * Double(pitchShift)
        let durationD = Double(duration)

        for ch in 0 ..< channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            var phase = 0.0
            for frame in 0 ..< Int(buffer.frameLength) {
                let t = Double(frame) / sampleRate

                // 频率在持续时间内向上扫动
                let progress = min(1.0, t / durationD)
                let freq = fStart + (fEnd - fStart) * progress
                phase += 2.0 * .pi * freq / sampleRate

                // 剑刃音色
                let blade = sin(phase)
                // 叠加带有气息感的噪声分量（气流呼啸声）
                let air = Double.random(in: -1 ... 1) * 0.5

                // 包络：先渐强再渐弱
                let swell = min(1.0, t / 0.04)
                let fade = max(0.0, 1.0 - progress * progress)
                let env = swell * fade

                var sample = (blade * 0.7 + air) * env
                sample = tanh(sample * 1.3) * 0.9

                data[frame] = Float(sample) * volume * 0.9
            }
        }

        playBuffer(buffer)
    }

    // MARK: - 发电报（摩斯电码）
    /// 清脆的"嘀-哒"摩斯电码声。每次按键随机发出一个点（短音）
    /// 或划（长音），音色是单一纯音加极快的开关包络，模拟电报键。
    private func playTelegraph(volume: Float) {
        // 点 vs 划：随机决定，长音持续约 3 倍
        let isDot = Bool.random()
        let dotDuration = 0.07
        let dashDuration = 0.19
        let duration = isDot ? dotDuration : dashDuration

        guard let buffer = makeBuffer(duration: duration) else { return }
        let channels = Int(outputFormat.channelCount)

        // 电报标准音高约 800Hz，随音调倍率变化
        let baseFreq = 800.0 * Double(pitchShift)
        // 轻微随机抖动，让每个音都略有不同
        let freq = baseFreq * Double.random(in: 0.97 ... 1.03)

        // 电报键按下瞬间的机械咔哒
        let clickAmt = Double.random(in: 0.4 ... 0.7)
        let clickDur = 0.004

        for ch in 0 ..< channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            var phase = 0.0
            for frame in 0 ..< Int(buffer.frameLength) {
                let t = Double(frame) / sampleRate

                phase += 2.0 * .pi * freq / sampleRate
                // 纯音（略带泛音增添"发报机"的金属感）
                let tone = sin(phase) + 0.12 * sin(phase * 2.0)

                // 开关包络：电报键极快的起音和收尾
                let attack = min(1.0, t / 0.002)
                let release = min(1.0, (duration - t) / 0.003)
                let envelope = attack * release

                // 起音瞬间的机械咔哒
                let click = t < clickDur
                    ? Double.random(in: -1 ... 1) * (1.0 - t / clickDur) * clickAmt
                    : 0.0

                var sample = tone * envelope * 0.9 + click * 0.15
                sample = tanh(sample * 1.1) * 0.9

                data[frame] = Float(sample) * volume * 1.0
            }
        }

        playBuffer(buffer)
    }

    // MARK: - 激光枪（星球大战）
    /// 经典的星球大战爆能枪"pew"音：一个从高频快速下滑到低频的
    /// 啁啾脉冲，起音极快、衰减短促，带轻微噪声使声音更有"能量"感。
    private func playBlaster(volume: Float) {
        let duration = 0.13
        guard let buffer = makeBuffer(duration: duration) else { return }
        let channels = Int(outputFormat.channelCount)
        let durationD = Double(duration)

        // 扫频范围：从高频"pew"下滑到低频
        let fStart = Double.random(in: 2200 ... 2800) * Double(pitchShift)
        let fEnd = Double.random(in: 300 ... 450) * Double(pitchShift)
        // 每次发射略有差异
        let snap = Double.random(in: 0.8 ... 1.0)   // 滑落速度

        for ch in 0 ..< channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            var phase = 0.0
            for frame in 0 ..< Int(buffer.frameLength) {
                let t = Double(frame) / sampleRate
                let progress = min(1.0, t / durationD)

                // 指数式下滑：一开始陡降，然后快速到底，就是"pew"的听感
                let freq = fStart + (fEnd - fStart) * pow(progress, snap)

                phase += 2.0 * .pi * freq / sampleRate
                let tone = sin(phase)
                // 轻微噪声增加"能量"感
                let noise = Double.random(in: -1 ... 1) * 0.25 * (1.0 - progress)

                // 包络：极快起音 + 短促衰减
                let attack = min(1.0, t / 0.002)
                let decay = exp(-t * 22.0)
                let env = attack * decay

                var sample = (tone * 0.85 + noise) * env
                sample = tanh(sample * 1.2) * 0.9

                data[frame] = Float(sample) * volume * 1.1
            }
        }

        playBuffer(buffer)
    }

    func stop() {
        // 停止并 detach 所有活跃播放器，避免退出时残留节点
        for player in activePlayers {
            player.stop()
            engine.detach(player)
        }
        activePlayers.removeAll()
        engine.stop()
        isRunning = false
    }
}
