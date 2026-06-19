import AVFoundation
import Foundation

final class ChiptuneAudioEngine {
    private struct BufferKey: Hashable {
        let waveform: ChipWaveform
        let frequencyBucket: Int
        let frameCount: Int
    }

    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let cacheLimit = 420
    private var players: [String: AVAudioPlayerNode] = [:]
    private var bufferCache: [BufferKey: AVAudioPCMBuffer] = [:]
    private var silentBuffer: AVAudioPCMBuffer?
    private lazy var outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    func configure(channels: [ChipTuneChannel]) {
        for channel in channels where players[channel.id] == nil {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
            players[channel.id] = player
        }

        startIfNeeded()
        primePlayers()
    }

    func preload(note: MusicNote, channel: ChipTuneChannel, duration: TimeInterval) {
        configure(channels: [channel])
        _ = cachedBuffer(
            frequency: note.frequency,
            waveform: channel.waveform,
            duration: duration
        )
    }

    func play(note: MusicNote, channel: ChipTuneChannel, duration: TimeInterval, velocity: Double = 1.0) {
        configure(channels: [channel])

        guard let player = players[channel.id],
              let buffer = cachedBuffer(
                frequency: note.frequency,
                waveform: channel.waveform,
                duration: duration
              ) else {
            return
        }

        player.volume = Float(min(max(channel.volume * velocity, 0.0), 1.0))
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if player.isPlaying == false {
            player.play()
        }
    }

    func stopAll() {
        for player in players.values {
            player.stop()
        }
        primePlayers()
    }

    private func startIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        if engine.isRunning == false {
            engine.prepare()
            try? engine.start()
        }
    }

    private func primePlayers() {
        guard let silence = makeSilentBuffer() else { return }

        for player in players.values where player.isPlaying == false {
            player.volume = 0
            player.scheduleBuffer(silence, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    private func cachedBuffer(
        frequency: Double,
        waveform: ChipWaveform,
        duration: TimeInterval
    ) -> AVAudioPCMBuffer? {
        let frameCount = max(1, Int(duration * sampleRate))
        let bucket = waveform.isPercussion ? Int((frequency / 8.0).rounded()) : Int((frequency * 10.0).rounded())
        let key = BufferKey(waveform: waveform, frequencyBucket: bucket, frameCount: frameCount)

        if let cached = bufferCache[key] {
            return cached
        }

        guard let buffer = makeBuffer(
            frequency: frequency,
            waveform: waveform,
            frameCount: frameCount
        ) else {
            return nil
        }

        if bufferCache.count >= cacheLimit {
            bufferCache.removeAll(keepingCapacity: true)
        }
        bufferCache[key] = buffer
        return buffer
    }

    private func makeBuffer(
        frequency: Double,
        waveform: ChipWaveform,
        frameCount: Int
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData?[0] else {
            return nil
        }

        var lfsr: UInt32 = 0xACE1
        var noiseValue = 0.0
        let noiseHoldFrames = max(1, Int(sampleRate / max(100.0, frequency * 18.0)))

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let phase = (t * frequency).truncatingRemainder(dividingBy: 1.0)
            let rawSample = sampleValue(
                waveform: waveform,
                frequency: frequency,
                phase: phase,
                time: t,
                frame: frame,
                frameCount: frameCount,
                noiseHoldFrames: noiseHoldFrames,
                lfsr: &lfsr,
                noiseValue: &noiseValue
            )
            let envelope = envelopeValue(waveform: waveform, frame: frame, frameCount: frameCount)
            let crushed = (rawSample * waveform.bitDepth).rounded() / waveform.bitDepth
            data[frame] = Float(max(-1.0, min(1.0, crushed * envelope)))
        }

        return buffer
    }

    private func sampleValue(
        waveform: ChipWaveform,
        frequency: Double,
        phase: Double,
        time: Double,
        frame: Int,
        frameCount: Int,
        noiseHoldFrames: Int,
        lfsr: inout UInt32,
        noiseValue: inout Double
    ) -> Double {
        switch waveform {
        case .pulse12, .pulse25, .pulse50, .pulse75:
            return phase < waveform.dutyCycle ? 1.0 : -1.0
        case .triangle:
            return 1.0 - 4.0 * abs(phase - 0.5)
        case .saw:
            return 2.0 * phase - 1.0
        case .sine:
            return sin(2.0 * Double.pi * phase)
        case .pluck:
            let pulse = phase < 0.5 ? 1.0 : -1.0
            let saw = 2.0 * phase - 1.0
            return pulse * 0.58 + saw * 0.42
        case .noise:
            return noiseSample(frame: frame, holdFrames: noiseHoldFrames, lfsr: &lfsr, noiseValue: &noiseValue)
        case .kick:
            let progress = Double(frame) / Double(max(frameCount, 1))
            let startFrequency = max(90.0, min(180.0, frequency / 3.0))
            let endFrequency = 44.0
            let sweptFrequency = startFrequency + (endFrequency - startFrequency) * progress
            let body = sin(2.0 * Double.pi * sweptFrequency * time)
            let click = frame < Int(sampleRate * 0.006)
                ? noiseSample(frame: frame, holdFrames: 1, lfsr: &lfsr, noiseValue: &noiseValue) * 0.32
                : 0.0
            return body * 1.08 + click
        case .snare:
            let noise = noiseSample(frame: frame, holdFrames: 1, lfsr: &lfsr, noiseValue: &noiseValue)
            let tone = sin(2.0 * Double.pi * 185.0 * time)
            return noise * 0.82 + tone * 0.25
        case .hat:
            let noise = noiseSample(frame: frame, holdFrames: 1, lfsr: &lfsr, noiseValue: &noiseValue)
            return noise * (frame.isMultiple(of: 2) ? 1.0 : -1.0)
        case .tom:
            let progress = Double(frame) / Double(max(frameCount, 1))
            let tomFrequency = max(70.0, min(220.0, frequency / 2.0))
            let sweptFrequency = tomFrequency * (1.0 - progress * 0.28)
            return sin(2.0 * Double.pi * sweptFrequency * time)
        }
    }

    private func noiseSample(
        frame: Int,
        holdFrames: Int,
        lfsr: inout UInt32,
        noiseValue: inout Double
    ) -> Double {
        if frame.isMultiple(of: holdFrames) {
            let bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1
            lfsr = (lfsr >> 1) | (bit << 15)
            noiseValue = (lfsr & 1) == 0 ? -1.0 : 1.0
        }
        return noiseValue
    }

    private func envelopeValue(waveform: ChipWaveform, frame: Int, frameCount: Int) -> Double {
        if waveform.isPercussion {
            let progress = Double(frame) / Double(max(frameCount, 1))
            switch waveform {
            case .kick:
                return pow(max(0.0, 1.0 - progress), 2.8)
            case .snare:
                return pow(max(0.0, 1.0 - progress), 3.5)
            case .hat:
                return pow(max(0.0, 1.0 - progress), 6.5)
            case .tom:
                return pow(max(0.0, 1.0 - progress), 2.6)
            default:
                return 1.0
            }
        }

        let attackFrames = max(1, Int(sampleRate * 0.0015))
        let releaseFrames = max(1, min(Int(sampleRate * 0.018), frameCount / 3))

        if frame < attackFrames {
            return Double(frame) / Double(attackFrames)
        }

        let releaseStart = frameCount - releaseFrames
        if frame > releaseStart {
            let remaining = max(0, frameCount - frame)
            return Double(remaining) / Double(releaseFrames)
        }

        return 1.0
    }

    private func makeSilentBuffer() -> AVAudioPCMBuffer? {
        if let silentBuffer {
            return silentBuffer
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: 128
        ) else {
            return nil
        }

        buffer.frameLength = 128
        if let data = buffer.floatChannelData?[0] {
            for frame in 0..<128 {
                data[frame] = 0
            }
        }

        silentBuffer = buffer
        return buffer
    }
}

private extension ChipWaveform {
    var bitDepth: Double {
        switch self {
        case .sine, .kick, .tom:
            return 24.0
        case .snare, .hat, .noise:
            return 10.0
        case .pulse12, .pulse25, .pulse50, .pulse75, .triangle, .saw, .pluck:
            return 14.0
        }
    }
}
