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

        func note(_ name: String, step: Int, length: Int = 1, velocity: Double = 1.0) -> SequencerNote {
            SequencerNote(row: row(name), startStep: step, length: length, velocity: velocity)
        }

        func sequence(_ names: [String?], velocity: Double, sustainRepeats: Bool = true) -> [SequencerNote] {
            var events = [SequencerNote]()
            var previousName: String?

            for (step, optionalName) in names.enumerated() {
                guard let name = optionalName else {
                    previousName = nil
                    continue
                }

                if sustainRepeats,
                   previousName == name,
                   let lastIndex = events.indices.last,
                   events[lastIndex].startStep + events[lastIndex].length == step {
                    events[lastIndex].length += 1
                } else {
                    events.append(note(name, step: step, velocity: velocity))
                }

                previousName = name
            }

            return events
        }

        let extractedLead: [String?] = [
            "G#4", "F-4", "C#4", "C#4", "F#4", "F#4", "A-4", "A-4",
            "C-4", "A#4", "A#4", "F-4", "G-5", "D#4", "F#4", "F#4",
            "C-5", "F-4", "F-4", "G#4", "G#4", "C#4", "D#4", "G#4",
            "C-4", "F#4", "F#4", "F-4", "F-4", "F-4", "A#4", "F-5"
        ]

        let extractedBass: [String?] = [
            "E-3", "F-3", "C#3", "F#3", "F#3", "F#3", "G#3", "A-3",
            "A#3", "A-3", "A#3", "F-3", "D#3", "D-3", "F#3", "F#3",
            "F-3", "F-3", "F-3", "C#3", "C#3", "D#3", "D-3", "C#3",
            "D#3", "F#3", "F#3", "F-3", "F-3", "D#3", "A#3", "A#3"
        ]

        patterns["pulse1"] = sequence(extractedLead, velocity: 0.94)

        patterns["pulse2"] = [
            note("E-4", step: 0, length: 1, velocity: 0.58),
            note("F-4", step: 1, length: 1, velocity: 0.64),
            note("C#4", step: 2, length: 1, velocity: 0.56),
            note("F#4", step: 3, length: 3, velocity: 0.68),
            note("G#4", step: 6, length: 1, velocity: 0.56),
            note("A#4", step: 8, length: 3, velocity: 0.7),
            note("F-4", step: 11, length: 1, velocity: 0.58),
            note("D#4", step: 12, length: 1, velocity: 0.56),
            note("D-4", step: 13, length: 1, velocity: 0.54),
            note("F#4", step: 14, length: 2, velocity: 0.68),
            note("F-4", step: 16, length: 3, velocity: 0.72),
            note("C#4", step: 19, length: 2, velocity: 0.58),
            note("D#4", step: 21, length: 1, velocity: 0.56),
            note("D-4", step: 22, length: 1, velocity: 0.54),
            note("C#4", step: 23, length: 1, velocity: 0.56),
            note("D#4", step: 24, length: 1, velocity: 0.58),
            note("F#4", step: 25, length: 2, velocity: 0.7),
            note("F-4", step: 27, length: 2, velocity: 0.66),
            note("D#4", step: 29, length: 1, velocity: 0.56),
            note("A#4", step: 30, length: 2, velocity: 0.74)
        ]

        patterns["triangle"] = sequence(extractedBass, velocity: 0.92)

        patterns["noise"] = [
            note("C-5", step: 1, velocity: 0.46),
            note("G-5", step: 3, velocity: 0.34),
            note("C-5", step: 5, velocity: 0.44),
            note("G-5", step: 7, velocity: 0.42),
            note("C-5", step: 9, velocity: 0.52),
            note("G-5", step: 11, velocity: 0.36),
            note("C-5", step: 13, velocity: 0.5),
            note("G-5", step: 15, velocity: 0.48),
            note("C-5", step: 17, velocity: 0.5),
            note("G-5", step: 19, velocity: 0.34),
            note("C-5", step: 21, velocity: 0.48),
            note("G-5", step: 23, velocity: 0.4),
            note("C-5", step: 25, velocity: 0.52),
            note("G-5", step: 27, velocity: 0.36),
            note("C-5", step: 29, velocity: 0.58),
            note("G-5", step: 31, velocity: 0.5)
        ]

        patterns["saw"] = [
            note("G#5", step: 0, velocity: 0.34),
            note("F#5", step: 4, length: 2, velocity: 0.38),
            note("A#5", step: 8, length: 2, velocity: 0.36),
            note("G-5", step: 12, velocity: 0.42),
            note("C-6", step: 16, velocity: 0.4),
            note("G#5", step: 19, length: 2, velocity: 0.34),
            note("F#5", step: 25, length: 2, velocity: 0.38),
            note("F-5", step: 31, velocity: 0.48)
        ]

        patterns["kick"] = [0, 3, 4, 8, 10, 12, 16, 19, 20, 24, 27, 28, 30].map { step in
            note("C-4", step: step, velocity: step.isMultiple(of: 8) ? 1.0 : 0.82)
        }

        patterns["snare"] = [7, 15, 23, 31].map { step in
            note("C-5", step: step, velocity: step == 31 ? 0.98 : 0.86)
        }

        patterns["hat"] = stride(from: 0, to: 32, by: 2).map { step in
            note("G-5", step: step, velocity: step.isMultiple(of: 8) ? 0.66 : 0.42)
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
    var patterns: [String: [RemoteSequencerNote]]?
}

struct RemoteChipTuneChannel: Codable {
    var id: String
    var title: String?
    var waveform: ChipWaveform?
    var volume: Double?
}

struct RemoteSequencerNote: Codable {
    var note: String?
    var row: Int?
    var startStep: Int
    var length: Int?
    var velocity: Double?
}
