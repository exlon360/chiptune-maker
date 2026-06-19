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

    static func suffocatedByHatredNotes() -> [MusicNote] {
        [
            "C-6", "B-5", "A#5", "A-5", "G#5", "G-5", "F#5", "F-5",
            "D#5", "D-5", "C#5", "C-5", "B-4", "A#4", "A-4", "G#4",
            "G-4", "F#4", "F-4", "E-4", "D#4", "D-4", "C#4", "C-4",
            "B-3", "A#3", "A-3", "G#3", "G-3", "F#3", "F-3", "E-3",
            "D#3", "D-3", "C#3", "C-3"
        ].compactMap { MusicNote(trackerName: $0) }
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

    static func blankDraft() -> ChipTuneProject {
        let rows = MusicNote.defaultRows()
        let patterns = Dictionary(uniqueKeysWithValues: ChipTuneChannel.defaults.map { ($0.id, [SequencerNote]()) })

        return ChipTuneProject(
            tempo: 156,
            steps: 64,
            rowNotes: rows,
            channels: ChipTuneChannel.defaults,
            patterns: patterns
        )
    }

    static func songNotesDraft() -> ChipTuneProject {
        let rows = MusicNote.suffocatedByHatredNotes()
        let patterns = Dictionary(uniqueKeysWithValues: ChipTuneChannel.defaults.map { ($0.id, [SequencerNote]()) })

        return ChipTuneProject(
            tempo: 156,
            steps: 64,
            rowNotes: rows.isEmpty ? MusicNote.defaultRows() : rows,
            channels: ChipTuneChannel.defaults,
            patterns: patterns
        )
    }

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

        func tokens(_ value: String) -> [String?] {
            value
                .split(whereSeparator: { $0.isWhitespace })
                .map { token -> String? in
                    let noteName = String(token)
                    return noteName == "--" ? nil : noteName
                }
        }

        let extractedLead = tokens("""
A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 C#5 C#5 -- F-5 F-5 F-5 F-5 F-5
D#5 D#5 D#5 D#5 D#5 D#5 D#5 D#5 D#5 D#5 -- D#3 D#3 D#3 C#5 C#5
D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 F-5 -- A#3 F-5 F-5 F-5 F-5
F-5 F-5 A#3 F#3 F-5 C#5 F#3 -- A#3 C#5 C#5 C#5 C#5 C#5 C#5 C#5
F-3 D#5 D#5 D#5 D#5 C-5 C-5 C-5 E-3 F-3 F-3 C#5 C#5 C#5 C#5 C#5
A-3 A-4 A-4 A-4 A-4 A#3 A#4 A#4 A#4 A#4 A#4 A#4 A#4 F-4 C#5 --
F-4 F-5 F-5 F-5 F-5 A#3 D#5 D#5 D#5 D#5 D#5 D#5 D#5 D#5 D#5 D#5
D#5 D#5 C#5 C#5 C#5 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 F-5
F-5 F-5 F-5 F-5 F-5 -- C#4 -- A#3 C#4 C#4 C#4 C#4 C#4 -- C#5
C#5 C#5 C#5 C#5 C#5 E-3 F-3 D#5 D#5 D#5 F-3 -- C-5 C-5 C-5 C#5
C#5 C#5 C#5 F-3 E-3 A-4 A-4 A-4 A-4 A-4 -- -- -- -- A#3 A#5
F-4 A#3 F-5 F-5 F-5 F-5 F-4 F#5 A#3 -- F-5 F-5 F-5 -- A#3 B-4
C#4 A-3 A-5 A#3 A-3 A-3 C#4 F-5 -- C#4 F-5 A-3 -- F#5 A-3 F-5
-- -- F-5 C#4 G#3 B-4 D-5 D#5 D#5 D#5 D#5 G#3 C-5 C-5 C-5 C-5
G#3 -- C#5 -- F-5 F-5 F-5 F-5 F-5 -- C-5 C-5 C-5 C-5 C-5 F-5
F-3 C-4 F-5 F-3 C-4 C-4 F-3 D#5 C-4 -- A-4 A-4 A-4 A-4 A-4 C-5
-- A#3 A#5 C#4 A#3 -- C#4 F-5 F-5 F-5 F-5 A#3 C#4 F#5 A#3 F-5
F-4 A#3 F-5 F-4 A#4 D#5 C#4 -- A-3 -- A-5 A-3 F-4 F-5 F-5 F-5
-- -- F#5 C#4 F-5 F-5 F-5 F-5 F-5 A-4 B-4 C#5 D#5 D#5 D#5 D#5
D#5 C-5 C-5 C-4 -- C-5 G#3 C#5 C#5 -- F-5 F-5 F-5 F-5 C-4 C-5
C-5 C-5 C-5 F-3 -- F-5 F-5 F-5 F-5 -- -- C-4 F-3 D#5 C-4 A-4
A-4 A-4 A-4 A-4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 --
-- -- -- -- -- -- -- -- -- -- A#3 A#3 F-3 F-3 F-3 F#3
F#3 E-3 F-3 F-3 -- -- D#3 D#3 -- F#3 F#3 F-3 F-3 F-3 A#3 A#3
A#3 E-3 D#3 -- F-3 F-3 F-3 F-3 F-3 -- -- D#3 F-3 F-3 F-3 F#3
F#3 A-3 A-3 A#3 A#3 A#3 F-3 D#3 D#3 F#3 F-3 F-3 F-3 -- -- D#3
C#3 -- D-3 F-3 F-3 F-3 F-3 F-3 F-3 A#3 A#3 F-3 F-3 D#3 -- F#3
-- E-3 F-3 D-3 C#3 -- F-3 -- C#3 F#3 F-3 A-3 A-3 A-3 A#3 A#3
A#3 E-3 D#3 F-3 F-3 F-3 F-3 F-3 F-3 C#3 -- D#3 D#3 C#3 F#3 F#3
F#3 E-3 F-3 A#3 A#3 A#3 F-3 D#3 E-3 F#3 F-3 F-3 F-3 F-3 -- D-3
-- E-3 -- F#3 F#3 F#3 A-3 A-3 A-3 A#3 A#3 F-3 E-3 D#3 F-3 F-3
F-3 F-3 F-3 -- D-3 C#3 D#3 -- F-3 F-3 F-3 F-3 F-3 E-3 A#3 A#3
E-3 F-3 D#3 F#3 F#3 F#3 F-3 E-3 -- C#3 -- F-3 D-3 C#3 F#3 F#3
A-3 A-3 A#3 A#3 A#3 A#3 E-3 E-3 -- F#3 F#3 -- F-3 F-3 C#3 C#3
D#3 D#3 D#3 -- F-3 F#3 -- A#3 A#3 A#3 A#3 -- F-3 -- F#5 F#3
F-3 F-3 F-3 -- C#4 D-3 F-5 -- D-3 F#5 C#3 A-5 A-3 A-3 A#3 D#3
F-3 F-3 F-3 F#3 F#3 F#3 E-3 -- C#3 C#3 -- F-3 C#4 -- F#3 D#3
-- F-3 E-3 A#3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 E-3 -- D-3
D-3 C#4 D#3 F-3 F-3 G-3 A-3 E-3 -- A#4 A#3 F-3 F-3 F-3 -- F#3
F-3 F-3 F-3 C#3 C#3 D#4 D#3 D#3 -- F#3 F-3 F-3 F-3 -- A#3 C#3
F-3 D#4 F#3 F#5 C#3 F-3 F-3 F-3 C#3 C#3 C#3 F-5 D-3 F-3 F#3 F#3
-- -- A#3 A#3 A#3 -- E-3 F-3 F#3 D#3 D#3 E-3 F-3 -- C#3 D-3
D#3 D#3 D-3 F#3 F#3 D#3 F-3 E-3 A#3 A#3 F-4 F-3 F-3 F-3 F-3 --
E-3 F-3 D-3 -- -- F-3 -- D#3 F-3 F-3 A-3 A-3 A-3 -- A#4 A#4
A#4 A#4 F#5 -- A#4 F-4 A#5 -- A#3 -- F-3 F-3 F#5 -- F#4 F#4
F-4 F-4 -- -- C#3 C#3 C#3 C#5 C#5 C#5 -- -- C#3 C#3 F#4 F#4
-- C#3 -- F-4 F-4 D-3 C#3 C#3 B-4 D#3 D#3 D#3 D#3 D#3 D#3 D#3
D#3 D#3 D#3 D-3 F#4 F-3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 -- -- F-3
F-3 F-3 F#5 F#3 F#4 -- F-3 F-3 F-3 F-3 F-3 D#4 D#4 C-5 F-3 D#4
D#4 E-3 A#4 A#4 A#4 E-3 -- F-5 F-3 A#4 E-3 F-3 A#5 A#3 -- F#5
E-3 -- -- F-4 F-4 F-4 E-3 -- -- C#5 -- C#3 -- -- D-5 --
-- C#3 -- -- A#4 D-3 C#3 -- D-3 C#3 -- G#3 D-3 D#3 D#3 D#3
D#3 D#3 D#3 -- F#5 D#3 D#3 D#3 D#3 D#3 E-3 E-3 E-3 E-3 E-3 D#3
D#3 D#3 -- F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 E-3 F-4 A-5
F-3 F-3 F-3 F-3 F-3 F-3 -- A#5 A#4 A-3 E-3 E-3 E-3 F#5 F#3 F-3
F-3 F-3 C#3 C#3 D#3 D#3 D#3 F#5 F#3 F-3 F-3 F-3 A#3 A#3 A#3 --
C#3 F-3 F#3 C#3 -- F-3 E-3 -- C#3 -- D#3 D#3 -- F#5 F#3 A-3
A-3 D-3 A#3 A#3 F-3 D#4 E-3 F#3 D#3 F-3 F-3 F-3 D#3 -- D-3 E-3
D#3 F#3 F#5 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 -- F#5 F#3 E-3
F-3 C#3 C#3 C-3 F-3 -- D#3 -- E-3 D-3 A-3 F-3 A#3 A#4 -- F-3
F-3 F#3 F#3 F#3 F-3 F-3 F-3 D-3 -- C#3 D#3 D#3 F#3 F#3 F-3 F-3
F-3 -- A#3 C#3 F-3 F-3 F-3 F#3 F#3 F-3 F-3 F-3 -- C#3 C#3 C#3
C#3 F#3 F#3 -- -- A-3 A-3 A#3 A#3 F-3 D#4 E-3 F#5 D#3 D#3 E-3
F-3 D-3 D-3 D-3 E-3 C#5 D#3 F#3 F#3 D#3 F-4 F-3 A#3 A#3 A-3 E-3
F-3 F-3 F-3 F-3 F-3 F-3 -- C#3 -- F-3 D#3 E-3 E-3 E-3 A#3 A-3
E-3 B-4 A#3 A#3 E-3 A#4 A#3 A#3 A#3 E-3 A#4 A#4 A-4 A-4 A#3 A-3
A-3 B-4 A#4 A-3 B-3 A#4 -- F-4 F-4 -- C#3 D-3 -- F-4 D-3 C#3
C#3 D-3 -- C-3 -- C#3 C#3 C#3 C#3 -- E-3 C#3 D#3 -- E-3 D#3
D#3 D#3 -- D-3 D#3 D#3 F-4 D-3 F#5 E-4 D#3 D#3 D-4 D#5 C#4 D#3
C#5 D-5 C-4 C-5 F-3 F-3 D#4 -- C#5 E-3 F-3 D#4 D#4 C#5 C#4 --
B-3 C-4 F-3 F-3 F-3 A-4 A#4 B-3 A#3 F-4 A#4 A#3 A#3 A#3 A#3 A#3
A#3 A#3 A-4 A-3 A-3 A-3 A#4 A#3 A#3 A#3 -- -- E-4 F-4 E-3 C#3
-- F-4 E-4 A-4 D-3 -- C#3 -- F#4 F#4 F#4 -- -- C#3 C#3 C#3
D-3 -- D#3 F-3 D-5 C#5 D#3 D#3 D#3 D#3 D#3 F#4 -- D#3 D#3 D#3
F-3 F-4 D#3 D#3 D#3 D#3 F-5 F-3 F-3 F-3 F-3 G#4 E-3 F-3 F-3 F-3
F-3 F-3 F-3 F-3 F-3 F-3 F-3 E-3 E-3 E-3 F-3 A#3 A#3 A-3 F-5 E-3
-- F#3 F-3 F-3 F-3 D#3 C#3 D-3 F-3 -- D#3 F#3 F#3 F-3 F-4 --
A#3 A#3 A#3 F-3 F-3 F-3 F#3 F#3 F-3 F-3 F-3 C#5 C#3 D#3 D#3 D#3
-- F#3 F-3 A-3 -- D-3 A#3 B-4 F-3 D#4 E-3 F#3 D#3 D#3 E-3 E-3
D-3 -- -- E-3 C#5 -- F#3 F#3 E-3 F-3 F-3 A#3 A#3 F-3 F-3 F-3
F-3 F-3 F-3 F-3 F-3 -- C#3 D-3 E-3 E-3 E-3 F#5 F#5 -- A-3 E-3
A#3 A#4 E-3 F-5 F-3 F-3 F#3 F#3 E-3 E-3 E-3 C#3 -- F-3 C#4 D#3
F#3 F#3 F-3 F-3 F-3 -- -- C#3 E-3 F-3 F#3 F#3 F#3 F-3 C#3 C#3
C#3 C#3 -- D#3 C#3 F-3 F#3 F#3 A-3 -- D#3 D#3 A#3 E-3 E-3 E-3
F#3 F#3 E-3 F-3 F-3 -- C#3 D-3 E-3 C#5 D#3 -- -- F-3 F-3 F-3
A#3 A#3 C-3 F-3 F-3 F#5 F#3 F-3 F-5 -- C#3 C#3 -- E-3 D#3 --
E-3 F-3 F-3 A-3 A-3 -- -- F-3 F-3 F-3 F-3 F-3 F-3 E-3 E-3 E-3
-- -- F-3 D#3 D#3 F-3 -- F-4 F-3 F-3 -- A#3 C#3 E-3 -- D-3
F#3 F#3 -- F-3 -- C#3 -- D#3 D#3 D#3 D-3 F-3 F#3 A-4 F-3 A#3
A#4 A#4 F-3 D#3 -- F-3 F-3 F-3 F-3 F-3 C#3 -- A#3 E-3 C#5 F-3
G-3 F#3 F-5 F-3 F#3 A#3 A#3 F-3 F-3 F-3 F#3 -- F-3 F-3 F-3 F-3
C#3 C-3 E-3 -- G-3 F#5 E-3 -- A-3 A-3 B-5 -- F-4 F-3 F-3 --
G-4 F-4 E-3 -- D-3 C#3 C#3 F-3 D#3 F#4 F#4 F-3 F-3 F-3 E-3 A#3
-- A-3 A#5 -- F#4 G#4 -- F-3 F-3 F-3 C#4 -- D#3 D#3 D#3 --
F#3 A-4 C#4 C-3 D-3 A#3 B-4 F-3 D#3 F#3 F#3 D-3 F-3 F-3 -- C#5
-- D#4 E-3 A-4 -- F-3 F-3 F-3 E-3 F#3 B-4 A#3 F-3 D#4 C-5 F#5
E-3 E-3 E-3 F-4 C#3 -- A-4 F-5 D#3 D#3 F#5 F-3 F-3 F-3 F-3 A#3
A#4 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 C#3 -- D-3 D#3 D#3 -- F#3
-- F-4 A#5 C-5 -- A#3 C-5 D-5 -- F#4 F-3 F-4 -- E-3 C-4 A#5
C#3 D#3 F-4 C#4 D-3 F#3 A-4 G#4 E-3 -- A-4 A#5 E-3 D#3 F-3 F-4
D#3 F#3 E-3 E-3 C#3 C#3 D#4 F-4 C#5 -- F#3 F#3 F-3 C-3 F#3 F#4
-- D#3 E-3 F-3 F#5 -- -- F-5 F-3 F-3 C#3 D-3 E-3 -- F#3 F#5
E-3 -- A-3 E-3 A#3 C-3 F-4 F-3 F-3 F-3 F-3 F#3 E-3 C#3 C#3 C#3
C-3 D#3 D#3 -- F#5 F#3 F-4 F-3 G#5 A#3 -- -- -- F-3 -- F#3
F-3 F-3 C#3 C#3 C#3 D-4 D#3 C-3 C#5 -- F#3 F#4 A-3 E-3 D#3 --
-- D#3 F-3 G-4 F#3 F#3 E-3 F-3 C-5 C#4 -- D#4 D#5 C#5 -- F-3
F-3 F-3 D#3 G-3 F#3 A#3 E-3 E-3 F-3 F#5 -- F#3 F-5 F-4 D-3 D-3
C#5 E-3 D#3 D#3 F#5 E-3 E-3 A-3 A-3 B-4 C-6 F-3 F-3 F-3 F-3 F-3
E-4 E-3 -- C-3 -- F-4 -- D#3 F#4 F#4 F-4 -- F-3 F-3 C#3 --
E-4 F-3 D#4 F#4 F#3 F#3 C#3 F-3 -- C#3 C#3 E-3 C#4 D-4 C-5 F-3
B-3 C-4 -- D-4 A#4 A#5 F-3 D#3 F#3 F-3 F-3 F-3 -- F-5 D-3 C-3
-- E-3 C#5 F-3 C#4 F#3 -- E-3 -- A#3 B-5 F-3 F-3 F-3 C#4 --
-- F-3 F-3 C#3 -- C#5 E-3 E-3 -- F-4 E-3 E-3 E-3 A-3 B-4 C-3
F-4 F-3 F-3 -- F#3 F-5 E-3 -- D-3 C-3 C#3 F-3 -- -- F#5 F-3
F-3 F-3 E-3 A#3 -- F-4 E-3 F-3 -- F#3 F#3 F-3 -- C#3 E-4 C#5
F-3 C#4 D#3 -- F-3 C-3 -- -- D#3 D#3 D#3 E-3 -- F#3 F#3 F#3
F-3 D#3 E-3 C#5 C#3 D#3 E-3 C#4 -- D-3 -- F-3 E-3 A#3 A#3 A#3
F-3 F-3 F#5 F#5 -- E-3 -- C-5 -- D-3 -- E-3 E-3 E-3 F#5 F-3
F-3 F-3 F-3 A#5 A#5 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4
A#4 A#4 A#4 -- -- A#5 A#5 A#5 A#5 A#4 A#4 A#4 A#4 A#4 A#4 B-5
C-6 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 A#4 -- -- --
""")

        let extractedBass = tokens("""
A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3
A#3 A#3 A#3 A#3 A#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3
D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 -- A#3 A#3 A#3 A#3 A#3
A#3 A#3 A#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3
F-3 A-3 A-3 A-3 A-3 C-4 F-3 F-3 F-3 F-3 F-3 E-3 -- F-3 C-4 --
A-3 A-3 A-3 A-3 A-3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3
A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 -- D#3 D#3 D#3 D#3 D#3 D#3
D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 A#3
A#3 A#3 A#3 F#3 -- -- F#3 A#3 A#3 F#3 F#3 F#3 F#3 F#3 F#3 F#3
F#3 F#3 F#3 F#3 F#3 E-3 F-3 F-3 F-3 F-3 F-3 C-4 C-4 C-4 C-4 --
F-3 E-3 E-3 E-3 E-3 A-3 A-3 A-3 A-3 A-3 F-3 A#3 -- F-3 A#3 --
F-3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3
A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3
A-3 A-3 A-3 A#3 G#3 G#3 G#3 G#3 G#3 G#3 G#3 G#3 C-4 C-4 C-4 C-4
C-4 C-4 C-4 -- G#3 G#3 G#3 C-4 C-4 C-4 C-4 C-4 C-4 C-4 C-4 C-4
C-4 C-4 C-4 C-4 C-4 C-4 C-4 C-4 C-4 -- A-3 -- F-3 A-3 -- F-3
-- A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 F-3 -- A#3 A#3
A#3 A#3 A#3 F-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 --
-- A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 A-3 C-4 G#3 G#3 G#3 G#3 G#3
G#3 C-4 C-4 C-4 C-4 C-4 G#3 -- C-4 -- G#3 G#3 G#3 C-4 C-4 F-3
F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 -- -- C-4 F-3 -- C-4 C-4
C-4 C-4 C-4 C-4 -- A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 --
-- -- -- -- -- -- -- -- -- -- A#3 A#3 F-3 F-3 F-3 F#3
F#3 E-3 F-3 F-3 C#3 -- D#3 D#3 C#3 F#3 F#3 F-3 F-3 F-3 A#3 A#3
A#3 E-3 D#3 -- F-3 F-3 F-3 F-3 F-3 -- C#3 D#3 F-3 F-3 F-3 F#3
F#3 A-3 A-3 A#3 A#3 A#3 F-3 D#3 D#3 F#3 F-3 F-3 F-3 F-3 -- D#3
C#3 -- D-3 F-3 F-3 F-3 F-3 F-3 F-3 A#3 A#3 F-3 F-3 D#3 -- F#3
F-3 F-3 F-3 D-3 C#3 -- F-3 -- C#3 F#3 F-3 A-3 A-3 A-3 A#3 A#3
A#3 E-3 D#3 F-3 F-3 F-3 F-3 F-3 F-3 C#3 -- D#3 D#3 C#3 F#3 F#3
F#3 E-3 F-3 A#3 A#3 A#3 F-3 D#3 E-3 F#3 F-3 F-3 F-3 F-3 -- D-3
-- E-3 -- F#3 F#3 F#3 A-3 A-3 A-3 A#3 A#3 F-3 E-3 D#3 F-3 F-3
F-3 F-3 F-3 -- D-3 C#3 D#3 -- F-3 F-3 F-3 F-3 F-3 E-3 A#3 A#3
E-3 F-3 D#3 F#3 F#3 F#3 F-3 E-3 -- C#3 -- F-3 D-3 C#3 F#3 F#3
A-3 A-3 A#3 A#3 A#3 A#3 E-3 E-3 -- F#3 F#3 -- F-3 F-3 C#3 C#3
D#3 D#3 D#3 -- F-3 F-3 F-3 A#3 A#3 A#3 A#3 -- F-3 -- F#3 F#3
F-3 F-3 F-3 -- C#3 D-3 D-3 D-3 D-3 F#3 C#3 A-3 A-3 A-3 A#3 D#3
D#3 D#3 F-3 F#3 F#3 F#3 E-3 F-3 C#3 C#3 -- F-3 D#3 D#3 D#3 D#3
-- F-3 E-3 A#3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 E-3 -- D-3
D-3 -- D#3 F-3 F-3 G-3 A-3 E-3 -- A#3 A#3 F-3 F-3 F-3 F#3 F#3
F-3 F-3 F-3 C#3 C#3 -- D#3 D#3 -- F#3 F-3 F-3 F-3 -- A#3 C#3
F-3 F-3 F#3 F#3 C#3 F-3 F-3 F-3 C#3 C#3 C#3 D-3 D-3 F-3 F#3 F#3
-- -- A#3 A#3 A#3 C-3 E-3 F-3 F#3 D#3 D#3 E-3 F-3 -- C#3 D-3
D#3 D#3 D-3 F#3 F#3 D#3 F-3 E-3 A#3 A#3 A-3 F-3 F-3 F-3 F-3 F#3
E-3 F-3 D-3 -- -- F-3 C-4 D#3 F-3 F-3 A-3 A-3 A-3 -- A#3 A#3
A#3 A#3 F-3 -- A#3 E-3 F-3 -- A#3 -- F-3 F-3 F-3 -- F#3 F-3
F-3 F-3 -- -- C#3 C#3 C#3 C#3 C#3 C#3 C-3 -- C#3 C#3 -- D-3
-- C#3 C#3 C#3 C#3 C#3 C#3 C#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3
D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 -- F-3 F-3
F-3 F-3 F-3 F#3 F#3 -- F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3
E-3 E-3 -- F-3 A#3 A#3 A#3 F-3 F-3 A#3 E-3 F-3 A#3 A#3 -- B-3
E-3 -- -- A#3 E-3 E-3 E-3 -- D-3 C#3 C#3 C#3 -- -- C#3 C#3
C#3 C#3 -- -- D-3 D-3 C#3 -- D-3 C#3 -- G#3 D-3 D#3 D#3 D#3
D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3
D#3 D#3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3
F-3 F-3 F-3 F-3 F-3 F-3 E-3 -- A#3 A-3 E-3 E-3 E-3 F#3 F#3 F-3
F-3 F-3 C#3 C#3 D#3 D#3 D#3 F#3 F#3 F-3 F-3 F-3 A#3 A#3 A#3 --
C#3 F-3 F#3 C#3 -- F-3 E-3 C#3 C#3 -- D#3 D#3 -- C#3 F#3 A-3
A-3 D-3 A#3 A#3 F-3 D#3 E-3 F#3 D#3 F-3 F-3 F-3 D#3 C#3 D-3 E-3
D#3 F#3 F#3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 -- F#3 F#3 E-3
F-3 C#3 C#3 C-3 F-3 D#3 D#3 F#3 E-3 D-3 A-3 F-3 A#3 A#3 F-3 F-3
F-3 F#3 F#3 F#3 F-3 F-3 F-3 D-3 -- C#3 D#3 D#3 F#3 F#3 F-3 F-3
F-3 -- A#3 C#3 F-3 F-3 F-3 F#3 F#3 F-3 F-3 F-3 -- C#3 C#3 C#3
C#3 F#3 F#3 -- A-3 A-3 A-3 A#3 A#3 F-3 D#3 E-3 F-3 D#3 D#3 E-3
F-3 D-3 D-3 D-3 E-3 D#3 D#3 F#3 F#3 D#3 F-3 F-3 A#3 A#3 A-3 E-3
F-3 F-3 F-3 F-3 F-3 F-3 -- C#3 -- F-3 D#3 E-3 E-3 E-3 A#3 A-3
E-3 -- A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A-3
A-3 B-3 A#3 A-3 B-3 E-3 -- D-3 C#3 C#3 C#3 D-3 -- F-3 D-3 C#3
C#3 D-3 -- C-3 D-3 D-3 D-3 C#3 C#3 -- E-3 C#3 D#3 D#3 D#3 D#3
D#3 D#3 -- D-3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D-3 E-3 D#3 D#3
E-3 F-3 C-4 C-4 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3
B-3 C-4 F-3 F-3 F-3 F-3 -- B-3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3
A#3 A#3 A-3 A-3 A-3 A-3 A#3 A#3 A#3 A#3 E-3 -- -- F-3 E-3 C#3
-- -- C#3 C#3 D-3 -- C#3 -- C-3 -- F#3 -- -- C#3 C#3 C#3
D-3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 D#3
D#3 D#3 D#3 D#3 D#3 D#3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3
F-3 F-3 F-3 F-3 F-3 F-3 F-3 E-3 E-3 E-3 F-3 A#3 A#3 A-3 E-3 E-3
C-3 F#3 F-3 F-3 F-3 D#3 C#3 D-3 F-3 D#3 D#3 F#3 F#3 F-3 F-3 A#3
A#3 A#3 A#3 F-3 F-3 F-3 F#3 F#3 F-3 F-3 F-3 C#3 C#3 D#3 D#3 D#3
-- F#3 F-3 A-3 -- D-3 A#3 B-3 F-3 D#3 E-3 F#3 D#3 D#3 E-3 E-3
D-3 C#3 C#3 E-3 F#3 F#3 F#3 F#3 E-3 F-3 F-3 A#3 A#3 F-3 F-3 F-3
F-3 F-3 F-3 F-3 F-3 C-3 C#3 D-3 E-3 E-3 E-3 E-3 E-3 -- A-3 E-3
A#3 A#3 E-3 F-3 F-3 F-3 F#3 F#3 E-3 E-3 E-3 C#3 -- F-3 D#3 D#3
F#3 F#3 F-3 F-3 F-3 -- A#3 C#3 E-3 F-3 F#3 F#3 F#3 F-3 C#3 C#3
C#3 C#3 -- D#3 C#3 F-3 F#3 F#3 A-3 -- D#3 D#3 A#3 E-3 E-3 E-3
F#3 F#3 E-3 F-3 F-3 -- C#3 D-3 E-3 D#3 D#3 -- -- F-3 F-3 F-3
A#3 A#3 C-3 F-3 F-3 F#3 F#3 F-3 F-3 F-3 C#3 C#3 -- E-3 D#3 D-3
E-3 F-3 F-3 A-3 A-3 A#3 -- F-3 F-3 F-3 F-3 F-3 F-3 E-3 E-3 E-3
-- C#3 F-3 D#3 D#3 F-3 -- -- F-3 F-3 -- A#3 C#3 C#3 C#3 D-3
F#3 F#3 -- F-3 C#3 C#3 -- D#3 D#3 D#3 D-3 F-3 F#3 A#3 A#3 A#3
D#3 D#3 D#3 D#3 -- F-3 F-3 F-3 F-3 F-3 C#3 -- A#3 E-3 D#3 F-3
G-3 F#3 F-3 F-3 F#3 A#3 A#3 F-3 F-3 F-3 F#3 -- F-3 F-3 F-3 F-3
C#3 C-3 E-3 -- G-3 F#3 E-3 -- A-3 A-3 A#3 -- F-3 F-3 F-3 C-3
F#3 -- E-3 -- D-3 C#3 C#3 F-3 D#3 D#3 F#3 F-3 F-3 F-3 E-3 A#3
-- A-3 E-3 C#3 F#3 F#3 F#3 F-3 F-3 F-3 C#3 -- D#3 D#3 D#3 --
F#3 A-3 C#3 C-3 D-3 A#3 D#3 D#3 D#3 F#3 F#3 D-3 F-3 F-3 -- D#3
D#3 D#3 D#3 D#3 -- F-3 F-3 F-3 E-3 F#3 B-3 A#3 F-3 F-3 F-3 F#3
E-3 E-3 E-3 F-3 C#3 -- D-3 E-3 D#3 D#3 F#3 F-3 F-3 F-3 F-3 A#3
C#3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 C#3 -- D-3 D#3 D#3 -- F#3
-- F-3 F-3 E-3 C#3 A#3 C-4 F-3 C#3 E-3 F-3 F#3 -- E-3 C-4 C#3
C#3 D#3 D#3 D#3 D-3 F#3 E-3 E-3 E-3 -- A#3 B-3 E-3 D#3 F-3 F-3
D#3 F#3 E-3 E-3 C#3 C#3 F#3 E-3 D-3 -- F#3 F#3 F-3 C-3 F#3 F#3
-- D#3 E-3 F-3 F#3 -- F-3 F-3 F-3 F-3 C#3 D-3 E-3 -- F#3 G-3
E-3 -- A-3 E-3 A#3 C-3 G-3 F-3 F-3 F-3 F-3 F#3 E-3 C#3 C#3 C#3
C-3 D#3 D#3 D#3 F#3 F#3 D-3 F-3 F-3 A#3 -- -- -- F-3 C-3 F#3
F-3 F-3 C#3 C#3 C#3 C#3 D#3 C-3 -- -- F#3 G-3 A-3 E-3 D#3 --
A#3 D#3 F-3 F#3 F#3 F#3 E-3 F-3 F-3 C#3 -- D-3 E-3 C-4 -- F-3
F-3 F-3 D#3 G-3 F#3 A#3 E-3 E-3 F-3 F#3 F#3 F#3 F-3 F-3 D-3 D-3
C-3 E-3 D#3 D#3 E-3 E-3 E-3 A-3 A-3 B-3 C#3 F-3 F-3 F-3 F-3 F-3
F-3 E-3 -- C-3 -- C#3 -- D#3 D#3 F#3 -- -- F-3 F-3 C#3 --
C-3 F-3 F-3 D#3 F#3 F#3 C#3 F-3 -- C#3 C#3 E-3 -- D-3 C-4 F-3
B-3 C-4 C#3 C#3 D#3 D#3 D#3 D#3 F#3 F-3 F-3 F-3 F-3 F-3 D-3 C-3
-- E-3 D#3 F-3 D-3 F#3 F-3 E-3 -- A#3 A#3 F-3 F-3 F-3 -- --
F-3 F-3 F-3 C#3 C#3 -- E-3 E-3 F#3 F#3 E-3 E-3 E-3 A-3 A#3 C-3
F-3 F-3 F-3 -- F#3 F-3 E-3 -- D-3 C-3 C#3 F-3 -- E-3 F#3 F-3
F-3 F-3 E-3 A#3 C#3 A-3 E-3 F-3 -- F#3 F#3 F-3 C#3 C#3 D-3 --
F-3 D-3 D#3 -- F-3 C-3 G#3 -- D#3 D#3 D#3 E-3 F-3 F#3 F#3 F#3
F-3 D#3 D#3 D#3 D#3 D#3 D#3 D#3 -- D-3 -- F-3 E-3 A#3 A#3 A#3
F-3 F-3 F-3 F#3 -- E-3 E-3 F-3 -- D-3 D-3 D-3 D-3 E-3 F#3 F-3
F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 F-3 B-3 G#3 A#3
F-3 B-3 A#3 A#3 F-3 F-3 F-3 F-3 B-3 A#3 A#3 A#3 A#3 A#3 A#3 A#3
A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 A#3 -- -- --
""")

        let extractedHarmony = tokens("""
A#4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- --
A#4 A#4 -- -- A#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- --
D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- -- A#4 A#4 -- --
A#4 A#4 -- -- F#4 F#4 -- -- F#4 F#4 -- -- F#4 F#4 -- --
F-4 A-4 -- -- A-4 C-5 -- -- F-4 F-4 -- -- C#4 F-4 -- --
A-4 A-4 -- -- A-4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- --
A#4 A#4 -- -- A#4 A#4 -- -- A#4 -- -- -- D#4 D#4 -- --
D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- --
A#4 A#4 -- -- -- -- -- -- A#4 F#4 -- -- F#4 F#4 -- --
F#4 F#4 -- -- F#4 E-4 -- -- F-4 F-4 -- -- C-5 C-5 -- --
F-4 E-4 -- -- E-4 A-4 -- -- A-4 A-4 -- -- -- F-4 -- --
F-4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- --
A-4 A-4 -- -- A-4 A-4 -- -- A-4 A-4 -- -- A-4 A-4 -- --
A-4 A-4 -- -- G#4 G#4 -- -- G#4 G#4 -- -- C-5 C-5 -- --
C-5 C-5 -- -- G#4 G#4 -- -- C-5 C-5 -- -- C-5 C-5 -- --
C-5 C-5 -- -- C-5 C-5 -- -- C-5 -- -- -- F-4 A-4 -- --
-- A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- -- F-4 F#4 -- --
A#4 A#4 -- -- A-4 A-4 -- -- A-4 A-4 -- -- A-4 A-4 -- --
-- A-4 -- -- A-4 A-4 -- -- A-4 A-4 -- -- G#4 G#4 -- --
G#4 C-5 -- -- C-5 C-5 -- -- C-5 -- -- -- G#4 C-5 -- --
F-4 F-4 -- -- F-4 F-4 -- -- F-4 -- -- -- F-4 D#4 -- --
C-5 C-5 -- -- -- A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- --
-- -- -- -- -- -- -- -- -- -- -- -- F-4 F-4 -- --
F#4 E-4 -- -- C#4 -- -- -- C#4 F#4 -- -- F-4 F-4 -- --
A#4 E-4 -- -- F-4 F-4 -- -- F-4 -- -- -- F-4 F-4 -- --
F#4 A-4 -- -- A#4 A#4 -- -- D#4 F#4 -- -- F-4 F-4 -- --
C#4 -- -- -- F-4 F-4 -- -- F-4 A#4 -- -- F-4 D#4 -- --
F-4 F-4 -- -- C#4 -- -- -- C#4 F#4 -- -- A-4 A-4 -- --
A#4 E-4 -- -- F-4 F-4 -- -- F-4 C#4 -- -- D#4 C#4 -- --
F#4 E-4 -- -- A#4 A#4 -- -- E-4 F#4 -- -- F-4 F-4 -- --
-- E-4 -- -- F#4 F#4 -- -- A-4 A#4 -- -- E-4 D#4 -- --
F-4 F-4 -- -- D-4 C#4 -- -- F-4 F-4 -- -- F-4 E-4 -- --
E-4 F-4 -- -- F#4 F#4 -- -- -- C#4 -- -- D-4 C#4 -- --
A-4 A-4 -- -- A#4 A#4 -- -- -- F#4 -- -- F-4 F-4 -- --
D#4 D#4 -- -- F-4 F-4 -- -- A#4 A#4 -- -- F-4 -- -- --
F-4 F-4 -- -- C#4 D-4 -- -- D-4 F#4 -- -- A-4 A-4 -- --
D#4 D#4 -- -- F#4 F#4 -- -- C#4 C#4 -- -- D#4 D#4 -- --
-- F-4 -- -- F-4 F-4 -- -- F-4 F-4 -- -- F-4 E-4 -- --
D-4 -- -- -- F-4 G-4 -- -- -- A#4 -- -- F-4 F-4 -- --
F-4 F-4 -- -- C#4 -- -- -- -- F#4 -- -- F-4 -- -- --
F-4 F-4 -- -- C#4 F-4 -- -- C#4 C#4 -- -- D-4 F-4 -- --
-- -- -- -- A#4 C-4 -- -- F#4 D#4 -- -- F-4 -- -- --
D#4 D#4 -- -- F#4 D#4 -- -- A#4 A#4 -- -- F-4 F-4 -- --
E-4 F-4 -- -- -- F-4 -- -- F-4 F-4 -- -- A-4 -- -- --
A#4 A#4 -- -- A#4 E-4 -- -- A#4 -- -- -- F-4 -- -- --
F-4 F-4 -- -- C#4 C#4 -- -- C#4 C#4 -- -- C#4 C#4 -- --
-- C#4 -- -- C#4 C#4 -- -- D#4 D#4 -- -- D#4 D#4 -- --
D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- -- D#4 -- -- --
F-4 F-4 -- -- F#4 -- -- -- F-4 F-4 -- -- F-4 F-4 -- --
E-4 E-4 -- -- A#4 A#4 -- -- F-4 A#4 -- -- A#4 A#4 -- --
E-4 -- -- -- E-4 E-4 -- -- D-4 C#4 -- -- -- -- -- --
C#4 C#4 -- -- D-4 D-4 -- -- D-4 C#4 -- -- D-4 D#4 -- --
D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- --
D#4 D#4 -- -- F-4 F-4 -- -- F-4 F-4 -- -- F-4 F-4 -- --
F-4 F-4 -- -- F-4 F-4 -- -- A#4 A-4 -- -- E-4 F#4 -- --
F-4 F-4 -- -- D#4 D#4 -- -- F#4 F-4 -- -- A#4 A#4 -- --
C#4 F-4 -- -- -- F-4 -- -- C#4 -- -- -- -- C#4 -- --
A-4 D-4 -- -- F-4 D#4 -- -- D#4 F-4 -- -- D#4 C#4 -- --
D#4 F#4 -- -- F-4 F-4 -- -- F-4 F-4 -- -- -- F#4 -- --
F-4 C#4 -- -- F-4 D#4 -- -- E-4 D-4 -- -- A#4 A#4 -- --
F-4 F#4 -- -- F-4 F-4 -- -- -- C#4 -- -- F#4 F#4 -- --
F-4 -- -- -- F-4 F-4 -- -- F#4 F-4 -- -- -- C#4 -- --
C#4 F#4 -- -- A-4 A-4 -- -- A#4 F-4 -- -- F-4 D#4 -- --
F-4 D-4 -- -- E-4 D#4 -- -- F#4 D#4 -- -- A#4 A#4 -- --
F-4 F-4 -- -- F-4 F-4 -- -- -- F-4 -- -- E-4 E-4 -- --
E-4 -- -- -- A#4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- --
A-4 B-4 -- -- B-4 E-4 -- -- C#4 C#4 -- -- -- F-4 -- --
C#4 D-4 -- -- D-4 D-4 -- -- C#4 -- -- -- D#4 D#4 -- --
D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- -- D-4 E-4 -- --
E-4 F-4 -- -- F-4 F-4 -- -- F-4 F-4 -- -- F-4 F-4 -- --
B-4 C-5 -- -- F-4 F-4 -- -- A#4 A#4 -- -- A#4 A#4 -- --
A#4 A#4 -- -- A-4 A-4 -- -- A#4 A#4 -- -- E-3 F-4 -- --
-- -- -- -- D-4 -- -- -- C-4 -- -- -- -- C#4 -- --
D-4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- -- D#4 D#4 -- --
D#4 D#4 -- -- D#4 D#4 -- -- F-4 F-4 -- -- F-4 F-4 -- --
F-4 F-4 -- -- F-4 F-4 -- -- E-4 E-4 -- -- A#4 A-4 -- --
C-4 F#4 -- -- F-4 D#4 -- -- F-4 D#4 -- -- F#4 F-4 -- --
A#4 A#4 -- -- F-4 F-4 -- -- F-4 F-4 -- -- C#4 D#4 -- --
-- F#4 -- -- -- D-4 -- -- F-4 D#4 -- -- D#4 D#4 -- --
D-4 C#4 -- -- F#4 F#4 -- -- E-4 F-4 -- -- A#4 F-4 -- --
F-4 F-4 -- -- F-4 C-4 -- -- E-4 E-4 -- -- E-4 -- -- --
A#4 A#4 -- -- F-4 F-4 -- -- E-4 E-4 -- -- -- F-4 -- --
F#4 F#4 -- -- F-4 -- -- -- E-4 F-4 -- -- F#4 F-4 -- --
C#4 C#4 -- -- C#4 F-4 -- -- A-4 -- -- -- A#4 E-4 -- --
F#4 F#4 -- -- F-4 -- -- -- E-4 D#4 -- -- -- F-4 -- --
A#4 A#4 -- -- F-4 F#4 -- -- F-4 F-4 -- -- -- E-4 -- --
E-4 F-4 -- -- A-4 A#4 -- -- F-4 F-4 -- -- F-4 E-4 -- --
-- C#4 -- -- D#4 F-4 -- -- F-4 F-4 -- -- C#4 C#4 -- --
F#4 F#4 -- -- C#4 C#4 -- -- D#4 D#4 -- -- F#4 A#4 -- --
D#4 D#4 -- -- -- F-4 -- -- F-4 F-4 -- -- A#4 E-4 -- --
G-4 F#4 -- -- F#4 A#4 -- -- F-4 F-4 -- -- F-4 F-4 -- --
C#4 C-4 -- -- G-4 F#4 -- -- A-4 A-4 -- -- F-4 F-4 -- --
F#4 -- -- -- D-4 C#4 -- -- D#4 D#4 -- -- F-4 F-4 -- --
-- A-4 -- -- F#4 F#4 -- -- F-4 F-4 -- -- D#4 D#4 -- --
F#4 A-4 -- -- D-4 A#4 -- -- D#4 F#4 -- -- F-4 F-4 -- --
D#4 D#4 -- -- -- F-4 -- -- E-4 F#4 -- -- F-4 F-4 -- --
E-4 E-4 -- -- C#4 -- -- -- D#4 D#4 -- -- F-4 F-4 -- --
C#4 F-4 -- -- F-4 F-4 -- -- F-4 C#4 -- -- D#4 D#4 -- --
-- F-4 -- -- C#4 A#4 -- -- C#4 E-4 -- -- -- E-4 -- --
C#4 D#4 -- -- D-4 F#4 -- -- E-4 -- -- -- E-4 D#4 -- --
D#4 F#4 -- -- C#4 C#4 -- -- D-4 -- -- -- F-4 C-4 -- --
-- D#4 -- -- F#4 -- -- -- F-4 F-4 -- -- E-4 -- -- --
E-4 -- -- -- A#4 C-4 -- -- F-4 F-4 -- -- E-4 C#4 -- --
C-4 D#4 -- -- F#4 F#4 -- -- F-4 A#4 -- -- -- F-4 -- --
F-4 F-4 -- -- C#4 C#4 -- -- -- -- -- -- A-4 E-4 -- --
A#4 D#4 -- -- F#4 F#4 -- -- F-4 C#4 -- -- E-4 C-5 -- --
F-4 F-4 -- -- F#4 A#4 -- -- F-4 F#4 -- -- F-4 F-4 -- --
C-4 E-4 -- -- E-4 E-4 -- -- A-4 B-4 -- -- F-4 F-4 -- --
F-4 E-4 -- -- -- C#4 -- -- D#4 F#4 -- -- F-4 F-4 -- --
C-4 F-4 -- -- F#4 F#4 -- -- -- C#4 -- -- C#3 D-4 -- --
B-4 C-5 -- -- D#4 D#4 -- -- F#4 F-4 -- -- F-4 F-4 -- --
-- E-4 -- -- D-4 F#4 -- -- -- A#4 -- -- F-4 F-4 -- --
F-4 F-4 -- -- C#4 -- -- -- F#4 F#4 -- -- E-4 A-4 -- --
F-4 F-4 -- -- F#4 F-4 -- -- D-4 C-4 -- -- -- E-4 -- --
F-4 F-4 -- -- C#4 A-4 -- -- -- F#4 -- -- C#4 C#4 -- --
F-4 D-4 -- -- F-4 C-4 -- -- D#4 D#4 -- -- F-4 F#4 -- --
F-4 D#4 -- -- D#4 D#4 -- -- -- D-4 -- -- E-4 A#4 -- --
F-4 F-4 -- -- -- E-4 -- -- -- D-4 -- -- D-4 E-4 -- --
F-4 F-4 -- -- F-4 F-4 -- -- F-4 F-4 -- -- F-4 B-4 -- --
F-4 B-4 -- -- F-4 F-4 -- -- B-4 A#4 -- -- A#4 A#4 -- --
A#4 A#4 -- -- A#4 A#4 -- -- A#4 A#4 -- -- A#4 -- -- --
""")

        let songSteps = extractedLead.count

        patterns["pulse1"] = sequence(extractedLead, velocity: 0.94)
        patterns["pulse2"] = sequence(extractedHarmony, velocity: 0.62)
        patterns["triangle"] = sequence(extractedBass, velocity: 0.9)

        patterns["noise"] = stride(from: 1, to: songSteps, by: 4).map { step in
            note(step.isMultiple(of: 8) ? "C-5" : "G-5", step: step, velocity: step.isMultiple(of: 16) ? 0.58 : 0.38)
        }

        patterns["saw"] = extractedLead.enumerated().compactMap { step, name -> SequencerNote? in
            guard let name,
                  step.isMultiple(of: 32) || step % 16 == 12 || step % 16 == 15 else {
                return nil
            }
            return note(name, step: step, velocity: step.isMultiple(of: 32) ? 0.44 : 0.34)
        }

        let kickPattern = [0, 3, 4, 8, 10, 12]
        patterns["kick"] = (0..<songSteps).compactMap { step in
            guard kickPattern.contains(step % 16) else { return nil }
            return note("C-4", step: step, velocity: step.isMultiple(of: 16) ? 1.0 : 0.82)
        }

        patterns["snare"] = (0..<songSteps).compactMap { step in
            guard step % 16 == 7 || step % 16 == 15 else { return nil }
            return note("C-5", step: step, velocity: step % 16 == 15 ? 0.94 : 0.84)
        }

        patterns["hat"] = stride(from: 0, to: songSteps, by: 2).map { step in
            note("G-5", step: step, velocity: step.isMultiple(of: 8) ? 0.66 : 0.42)
        }

        return ChipTuneProject(
            tempo: 156,
            steps: songSteps,
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
