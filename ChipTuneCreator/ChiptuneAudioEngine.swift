import AVFoundation
import Foundation

final class ChiptuneAudioEngine {
    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private var players: [String: AVAudioPlayerNode] = [:]
    private lazy var outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    func configure(channels: [ChipTuneChannel]) {
        for channel in channels where players[channel.id] == nil {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
            players[channel.id] = player
        }
    }

    func play(note: MusicNote, channel: ChipTuneChannel, duration: TimeInterval, velocity: Double = 1.0) {
        configure(channels: [channel])
        startIfNeeded()

        guard let player = players[channel.id],
              let buffer = makeBuffer(
                frequency: note.frequency,
                waveform: channel.waveform,
                volume: channel.volume * velocity,
                duration: duration
              ) else {
            return
        }

        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    func stopAll() {
        for player in players.values {
            player.stop()
        }
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

    private func makeBuffer(
        frequency: Double,
        waveform: ChipWaveform,
        volume: Double,
        duration: TimeInterval
    ) -> AVAudioPCMBuffer? {
        let frameCount = max(1, Int(duration * sampleRate))
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
        let noiseHoldFrames = max(1, Int(sampleRate / max(80.0, frequency * 12.0)))

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let phase = (t * frequency).truncatingRemainder(dividingBy: 1.0)
            let rawSample: Double

            switch waveform {
            case .pulse12, .pulse25, .pulse50:
                rawSample = phase < waveform.dutyCycle ? 1.0 : -1.0
            case .triangle:
                rawSample = 4.0 * abs(phase - 0.5) - 1.0
            case .noise:
                if frame.isMultiple(of: noiseHoldFrames) {
                    let bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1
                    lfsr = (lfsr >> 1) | (bit << 15)
                    noiseValue = (lfsr & 1) == 0 ? -1.0 : 1.0
                }
                rawSample = noiseValue
            }

            let envelope = envelopeValue(frame: frame, frameCount: frameCount)
            let crushed = (rawSample * 12.0).rounded() / 12.0
            data[frame] = Float(crushed * envelope * min(max(volume, 0.0), 1.0))
        }

        return buffer
    }

    private func envelopeValue(frame: Int, frameCount: Int) -> Double {
        let attackFrames = max(1, Int(sampleRate * 0.004))
        let releaseFrames = max(1, min(Int(sampleRate * 0.035), frameCount / 3))

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
}
