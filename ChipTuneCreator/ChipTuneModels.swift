import Foundation

struct MusicNote: Codable, Hashable, Identifiable {
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    let semitone: Int
    let octave: Int

    var id: String { displayName }

    var midiNumber: Int {
        (octave + 1) * 12 + semitone
    }

    var frequency: Double {
        440.0 * pow(2.0, Double(midiNumber - 69) / 12.0)
    }

    var displayName: String {
        "\(Self.sharpNames[semitone])-\(octave)"
    }

    init(semitone: Int, octave: Int) {
        self.semitone = min(max(semitone, 0), 11)
        self.octave = min(max(octave, 0), 8)
    }

    init(midiNumber: Int) {
        let clamped = min(max(midiNumber, 12), 119)
        semitone = clamped % 12
        octave = clamped / 12 - 1
    }

    init?(trackerName: String) {
        let cleaned = trackerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")

        guard let octaveCharacter = cleaned.last,
              let octave = Int(String(octaveCharacter)) else {
            return nil
        }

        let notePart = String(cleaned.dropLast()).replacingOccurrences(of: "-", with: "")
        let normalized: String
        switch notePart {
        case "DB":
            normalized = "C#"
        case "EB":
            normalized = "D#"
        case "GB":
            normalized = "F#"
        case "AB":
            normalized = "G#"
        case "BB":
            normalized = "A#"
        default:
            normalized = notePart
        }

        guard let semitone = Self.sharpNames.firstIndex(of: normalized) else {
            return nil
        }

        self.init(semitone: semitone, octave: octave)
    }

    static func trackerPalette() -> [MusicNote] {
        (24...96).map { MusicNote(midiNumber: $0) }
    }

    static func defaultRows() -> [MusicNote] {
        let top = MusicNote(semitone: 0, octave: 6).midiNumber
        return (0..<37).map { MusicNote(midiNumber: top - $0) }
    }
}

enum ChipWaveform: String, Codable, CaseIterable, Hashable, Identifiable {
    case pulse12
    case pulse25
    case pulse50
    case pulse75
    case triangle
    case saw
    case sine
    case pluck
    case noise
    case kick
    case snare
    case hat
    case tom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pulse12:
            return "12.5%"
        case .pulse25:
            return "25%"
        case .pulse50:
            return "50%"
        case .pulse75:
            return "75%"
        case .triangle:
            return "Tri"
        case .saw:
            return "Saw"
        case .sine:
            return "Sine"
        case .pluck:
            return "Pluck"
        case .noise:
            return "Noise"
        case .kick:
            return "Kick"
        case .snare:
            return "Snare"
        case .hat:
            return "Hat"
        case .tom:
            return "Tom"
        }
    }

    var dutyCycle: Double {
        switch self {
        case .pulse12:
            return 0.125
        case .pulse25:
            return 0.25
        case .pulse50:
            return 0.5
        case .pulse75:
            return 0.75
        case .triangle, .saw, .sine, .pluck, .noise, .kick, .snare, .hat, .tom:
            return 0.5
        }
    }

    var isPercussion: Bool {
        switch self {
        case .kick, .snare, .hat, .tom:
            return true
        case .pulse12, .pulse25, .pulse50, .pulse75, .triangle, .saw, .sine, .pluck, .noise:
            return false
        }
    }
}

struct ChipTuneChannel: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var waveform: ChipWaveform
    var volume: Double

    static let defaults = [
        ChipTuneChannel(id: "pulse1", title: "Pulse 1", waveform: .pulse50, volume: 0.46),
        ChipTuneChannel(id: "pulse2", title: "Pulse 2", waveform: .pulse25, volume: 0.38),
        ChipTuneChannel(id: "triangle", title: "Triangle", waveform: .triangle, volume: 0.42),
        ChipTuneChannel(id: "saw", title: "Saw Lead", waveform: .saw, volume: 0.32),
        ChipTuneChannel(id: "noise", title: "Noise", waveform: .noise, volume: 0.24),
        ChipTuneChannel(id: "kick", title: "Kick", waveform: .kick, volume: 0.62),
        ChipTuneChannel(id: "snare", title: "Snare", waveform: .snare, volume: 0.42),
        ChipTuneChannel(id: "hat", title: "Hat", waveform: .hat, volume: 0.28)
    ]
}

struct SequencerNote: Codable, Identifiable, Equatable {
    var id: UUID
    var row: Int
    var startStep: Int
    var length: Int
    var velocity: Double

    init(id: UUID = UUID(), row: Int, startStep: Int, length: Int = 1, velocity: Double = 1.0) {
        self.id = id
        self.row = row
        self.startStep = startStep
        self.length = max(1, length)
        self.velocity = min(max(velocity, 0.05), 1.0)
    }

    func covers(step: Int) -> Bool {
        step >= startStep && step < startStep + length
    }
}

enum ChipTuneEditMode: String, CaseIterable, Identifiable {
    case draw
    case erase

    var id: String { rawValue }
}

struct ChipTuneProject: Codable, Equatable {
    var tempo: Double
    var steps: Int
    var rowNotes: [MusicNote]
    var channels: [ChipTuneChannel]
    var patterns: [String: [SequencerNote]]

    static func starter() -> ChipTuneProject {
        let rows = MusicNote.defaultRows()
        var patterns = Dictionary(uniqueKeysWithValues: ChipTuneChannel.defaults.map { ($0.id, [SequencerNote]()) })

        func row(_ name: String) -> Int {
            guard let note = MusicNote(trackerName: name),
                  let index = rows.firstIndex(of: note) else {
                return 0
            }
            return index
        }

        patterns["pulse1"] = [
            SequencerNote(row: row("C-5"), startStep: 0, length: 1),
            SequencerNote(row: row("C#5"), startStep: 2, length: 1, velocity: 0.82),
            SequencerNote(row: row("C-5"), startStep: 3, length: 1, velocity: 0.92),
            SequencerNote(row: row("G-4"), startStep: 4, length: 2),
            SequencerNote(row: row("A#4"), startStep: 7, length: 1, velocity: 0.74),
            SequencerNote(row: row("C-5"), startStep: 8, length: 1),
            SequencerNote(row: row("D#5"), startStep: 10, length: 1, velocity: 0.78),
            SequencerNote(row: row("C#5"), startStep: 11, length: 1, velocity: 0.88),
            SequencerNote(row: row("C-5"), startStep: 12, length: 1),
            SequencerNote(row: row("G-4"), startStep: 14, length: 2),
            SequencerNote(row: row("F#4"), startStep: 16, length: 1),
            SequencerNote(row: row("G-4"), startStep: 18, length: 1, velocity: 0.86),
            SequencerNote(row: row("A#4"), startStep: 19, length: 1, velocity: 0.8),
            SequencerNote(row: row("C-5"), startStep: 20, length: 2),
            SequencerNote(row: row("C#5"), startStep: 23, length: 1, velocity: 0.74),
            SequencerNote(row: row("D#5"), startStep: 24, length: 1),
            SequencerNote(row: row("C#5"), startStep: 26, length: 1, velocity: 0.86),
            SequencerNote(row: row("C-5"), startStep: 27, length: 1),
            SequencerNote(row: row("A#4"), startStep: 28, length: 1, velocity: 0.9),
            SequencerNote(row: row("G-4"), startStep: 30, length: 2)
        ]

        patterns["pulse2"] = [
            SequencerNote(row: row("C-4"), startStep: 0, length: 2, velocity: 0.78),
            SequencerNote(row: row("C#4"), startStep: 2, length: 1, velocity: 0.58),
            SequencerNote(row: row("C-4"), startStep: 4, length: 2, velocity: 0.78),
            SequencerNote(row: row("A#3"), startStep: 7, length: 1, velocity: 0.64),
            SequencerNote(row: row("C-4"), startStep: 8, length: 2, velocity: 0.78),
            SequencerNote(row: row("D#4"), startStep: 10, length: 1, velocity: 0.58),
            SequencerNote(row: row("C#4"), startStep: 12, length: 2, velocity: 0.72),
            SequencerNote(row: row("G-3"), startStep: 14, length: 2, velocity: 0.68),
            SequencerNote(row: row("F#3"), startStep: 16, length: 2, velocity: 0.74),
            SequencerNote(row: row("G-3"), startStep: 18, length: 1, velocity: 0.58),
            SequencerNote(row: row("A#3"), startStep: 19, length: 1, velocity: 0.62),
            SequencerNote(row: row("C-4"), startStep: 20, length: 2, velocity: 0.82),
            SequencerNote(row: row("C#4"), startStep: 23, length: 1, velocity: 0.58),
            SequencerNote(row: row("D#4"), startStep: 24, length: 2, velocity: 0.76),
            SequencerNote(row: row("C#4"), startStep: 26, length: 1, velocity: 0.66),
            SequencerNote(row: row("A#3"), startStep: 28, length: 1, velocity: 0.72),
            SequencerNote(row: row("G-3"), startStep: 30, length: 2, velocity: 0.76)
        ]

        patterns["triangle"] = [
            SequencerNote(row: row("C-3"), startStep: 0, length: 2, velocity: 0.95),
            SequencerNote(row: row("C-3"), startStep: 4, length: 2, velocity: 0.9),
            SequencerNote(row: row("C#3"), startStep: 8, length: 2, velocity: 0.92),
            SequencerNote(row: row("G-3"), startStep: 12, length: 2, velocity: 0.78),
            SequencerNote(row: row("F#3"), startStep: 16, length: 2, velocity: 0.94),
            SequencerNote(row: row("G-3"), startStep: 20, length: 2, velocity: 0.78),
            SequencerNote(row: row("D#3"), startStep: 24, length: 2, velocity: 0.9),
            SequencerNote(row: row("C-3"), startStep: 28, length: 4, velocity: 0.98)
        ]

        patterns["noise"] = [
            SequencerNote(row: row("C-5"), startStep: 1, length: 1, velocity: 0.62),
            SequencerNote(row: row("G-5"), startStep: 5, length: 1, velocity: 0.42),
            SequencerNote(row: row("C-5"), startStep: 9, length: 1, velocity: 0.66),
            SequencerNote(row: row("G-5"), startStep: 13, length: 1, velocity: 0.42),
            SequencerNote(row: row("C-5"), startStep: 17, length: 1, velocity: 0.66),
            SequencerNote(row: row("G-5"), startStep: 21, length: 1, velocity: 0.42),
            SequencerNote(row: row("C-5"), startStep: 25, length: 1, velocity: 0.7),
            SequencerNote(row: row("G-5"), startStep: 29, length: 1, velocity: 0.48)
        ]

        patterns["saw"] = [
            SequencerNote(row: row("G-5"), startStep: 6, length: 1, velocity: 0.42),
            SequencerNote(row: row("A#5"), startStep: 15, length: 1, velocity: 0.5),
            SequencerNote(row: row("C-6"), startStep: 22, length: 1, velocity: 0.46),
            SequencerNote(row: row("D#6"), startStep: 31, length: 1, velocity: 0.52)
        ]

        patterns["kick"] = [0, 3, 8, 12, 16, 20, 24, 28].map { step in
            SequencerNote(row: row("C-4"), startStep: step, length: 1, velocity: step.isMultiple(of: 8) ? 1.0 : 0.82)
        }

        patterns["snare"] = [7, 15, 23, 31].map { step in
            SequencerNote(row: row("C-5"), startStep: step, length: 1, velocity: step == 31 ? 0.96 : 0.84)
        }

        patterns["hat"] = stride(from: 2, to: 32, by: 2).map { step in
            SequencerNote(row: row("G-5"), startStep: step, length: 1, velocity: step.isMultiple(of: 8) ? 0.64 : 0.42)
        }

        return ChipTuneProject(
            tempo: 156,
            steps: 32,
            rowNotes: rows,
            channels: ChipTuneChannel.defaults,
            patterns: patterns
        )
    }
}

struct RemoteChipTuneConfig: Codable {
    var tempo: Double?
    var steps: Int?
    var notes: [String]?
    var channels: [RemoteChipTuneChannel]?
}

struct RemoteChipTuneChannel: Codable {
    var id: String
    var title: String?
    var waveform: ChipWaveform?
    var volume: Double?
}
