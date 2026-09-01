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

    var displayName: String {
        switch self {
        case .pentatonic: return "五声音阶"
        case .synth:      return "电子合成"
        case .musicBox:   return "音乐盒"
        case .percussion: return "打击乐"
        case .piano:      return "钢琴"
        case .mechanical: return "音效1"
        case .sword:      return "音效2"
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

        switch mode {
        case .pentatonic:
            let freq = Self.pentatonicScale[noteIndex % Self.pentatonicScale.count]
            noteIndex += 1
            playTone(frequency: freq, volume: volume,
                     waveform: .sine, duration: 0.25,
                     harmonics: [2.0: 0.3, 3.0: 0.1])

        case .synth:
            let freq = Self.pentatonicScale[noteIndex % Self.pentatonicScale.count]
            noteIndex += 1
            playTone(frequency: freq, volume: volume,
                     waveform: .saw, duration: 0.18,
                     harmonics: [:])

        case .musicBox:
            let freq = Self.pentatonicScale[noteIndex % Self.pentatonicScale.count] * 2.0
            noteIndex += 1
            playTone(frequency: freq, volume: volume,
                     waveform: .sine, duration: 0.45,
                     harmonics: [2.0: 0.1])

        case .percussion:
            let freq = Self.percussionNotes[noteIndex % Self.percussionNotes.count]
            noteIndex += 1
            playTone(frequency: freq, volume: volume * 1.2,
                     waveform: .noise, duration: 0.15,
                     harmonics: [:])

        case .piano:
            let freq = Self.pianoScale[noteIndex % Self.pianoScale.count]
            noteIndex += 1
            playPiano(frequency: freq, volume: volume)

        case .mechanical:
            // 每个按键的声音都略有不同（音高抖动 + 敲击变化）
            playMechanical(volume: volume)

        case .sword:
            playSword(volume: volume)
        }
    }

    // MARK: - 波形合成

    private enum Waveform {
        case sine
        case saw
        case noise
    }

    /// 在新的播放器节点上播放预先填充好的缓冲区。
    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: mixer, format: outputFormat)

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self, weak player] in
            guard let self = self, let player = player else { return }
            DispatchQueue.main.async {
                self.engine.detach(player)
            }
        })

        player.play()
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
        let clickFreq = Double.random(in: 1200 ... 2600)
        let thockFreq = Double.random(in: 140 ... 220)
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
        let fStart = Double.random(in: 220 ... 340)
        let fEnd = Double.random(in: 1400 ... 2100)
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

    func stop() {
        engine.stop()
        isRunning = false
    }
}
