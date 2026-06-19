import Combine
import Foundation

@MainActor
final class ChipTuneStore: ObservableObject {
    static let defaultRemoteURL = "https://raw.githubusercontent.com/exlon360/chiptune-maker/main/config/chiptune-creator.json"
    private static let minimumSteps = 8
    private static let autoExtendPaddingSteps = 64

    @Published var project: ChipTuneProject
    @Published var selectedChannelID: String
    @Published var editMode: ChipTuneEditMode = .draw
    @Published var selectedLength = 1
    @Published var isPlaying = false
    @Published var playheadStep = 0
    @Published var remoteURLString: String
    @Published var statusText = "Ready"

    private let projectDefaultsKey = "ChipTuneCreator.project"
    private let remoteURLDefaultsKey = "ChipTuneCreator.remoteURL"
    private let audio = ChiptuneAudioEngine()
    private var playbackTimer: Timer?
    private var nextPlaybackStep = 0

    init() {
        let loadedProject: ChipTuneProject
        if let data = UserDefaults.standard.data(forKey: projectDefaultsKey),
           let decoded = try? JSONDecoder().decode(ChipTuneProject.self, from: data) {
            loadedProject = decoded
        } else {
            loadedProject = ChipTuneProject.starter()
        }

        let normalizedProject = Self.normalized(project: loadedProject)
        project = normalizedProject
        selectedChannelID = normalizedProject.channels.first?.id ?? "pulse1"
        remoteURLString = UserDefaults.standard.string(forKey: remoteURLDefaultsKey) ?? Self.defaultRemoteURL
        audio.configure(channels: normalizedProject.channels)
        warmCurrentSounds()
    }

    var selectedChannel: ChipTuneChannel {
        project.channels.first(where: { $0.id == selectedChannelID }) ?? project.channels[0]
    }

    var notesForSelectedChannel: [SequencerNote] {
        notes(for: selectedChannelID)
    }

    var stepDuration: TimeInterval {
        60.0 / max(project.tempo, 20.0) / 4.0
    }

    func notes(for channelID: String) -> [SequencerNote] {
        (project.patterns[channelID] ?? [])
            .sorted { lhs, rhs in
                lhs.startStep == rhs.startStep ? lhs.row < rhs.row : lhs.startStep < rhs.startStep
            }
    }

    func selectChannel(_ id: String) {
        guard project.channels.contains(where: { $0.id == id }) else { return }
        selectedChannelID = id
    }

    func setTempo(_ tempo: Double) {
        project.tempo = min(max(tempo, 48), 220)
        saveProject()
        if isPlaying {
            startPlaybackTimer()
        }
    }

    func setSelectedLength(_ length: Int) {
        selectedLength = min(max(length, 1), 16)
    }

    func setSteps(_ steps: Int) {
        setSteps(steps, shouldSave: true)
    }

    func extendSong(by steps: Int) {
        guard steps > 0 else { return }
        setSteps(project.steps + steps)
        statusText = "\(project.steps) steps"
    }

    func doubleSongLength() {
        setSteps(project.steps * 2)
        statusText = "\(project.steps) steps"
    }

    func trimSongToLastNote() {
        let lastUsedStep = project.patterns.values
            .flatMap { $0 }
            .map { $0.startStep + $0.length }
            .max() ?? Self.minimumSteps
        let roundedSteps = max(Self.minimumSteps, ((lastUsedStep + 15) / 16) * 16)
        setSteps(roundedSteps)
        statusText = "\(project.steps) steps"
    }

    private func setSteps(_ steps: Int, shouldSave: Bool) {
        let clamped = max(steps, Self.minimumSteps)
        project.steps = clamped
        for channel in project.channels {
            project.patterns[channel.id] = (project.patterns[channel.id] ?? []).compactMap { note in
                guard note.startStep < clamped else { return nil }
                var clipped = note
                clipped.length = min(note.length, clamped - note.startStep)
                return clipped
            }
        }
        if shouldSave {
            saveProject()
        }
    }

    func applyGridInteraction(row: Int, step: Int) {
        guard project.rowNotes.indices.contains(row), step >= 0, step < project.steps else { return }

        switch editMode {
        case .draw:
            addNote(row: row, step: step)
        case .erase:
            deleteNote(row: row, step: step)
        }
    }

    func addNote(row: Int, step: Int) {
        ensureStepCapacity(through: step + selectedLength + Self.autoExtendPaddingSteps, shouldSave: false)
        let length = min(selectedLength, project.steps - step)
        guard length > 0 else { return }

        var channelNotes = project.patterns[selectedChannelID] ?? []
        let range = step..<(step + length)
        if channelNotes.contains(where: { $0.row == row && rangesOverlap($0.startStep..<($0.startStep + $0.length), range) }) {
            return
        }

        let newNote = SequencerNote(row: row, startStep: step, length: length)
        channelNotes.append(newNote)
        project.patterns[selectedChannelID] = channelNotes
        audio.preload(
            note: project.rowNotes[row],
            channel: selectedChannel,
            duration: stepDuration * Double(length) * 0.96
        )
        preview(row: row, velocity: 0.75)
        saveProject()
    }

    func deleteNote(row: Int, step: Int) {
        var channelNotes = project.patterns[selectedChannelID] ?? []
        let originalCount = channelNotes.count
        channelNotes.removeAll { $0.row == row && $0.covers(step: step) }
        guard channelNotes.count != originalCount else { return }
        project.patterns[selectedChannelID] = channelNotes
        saveProject()
    }

    func delete(noteID: UUID) {
        var channelNotes = project.patterns[selectedChannelID] ?? []
        channelNotes.removeAll { $0.id == noteID }
        project.patterns[selectedChannelID] = channelNotes
        saveProject()
    }

    func resize(noteID: UUID, length: Int) {
        var channelNotes = project.patterns[selectedChannelID] ?? []
        guard let index = channelNotes.firstIndex(where: { $0.id == noteID }) else { return }

        var note = channelNotes[index]
        let requestedLength = max(length, 1)
        ensureStepCapacity(through: note.startStep + requestedLength + Self.autoExtendPaddingSteps, shouldSave: false)
        let clamped = min(requestedLength, project.steps - note.startStep)
        let nextRange = note.startStep..<(note.startStep + clamped)
        let overlapsAnother = channelNotes.contains { candidate in
            candidate.id != noteID &&
            candidate.row == note.row &&
            rangesOverlap(candidate.startStep..<(candidate.startStep + candidate.length), nextRange)
        }

        guard overlapsAnother == false else { return }
        note.length = clamped
        channelNotes[index] = note
        project.patterns[selectedChannelID] = channelNotes
    }

    func finishResize() {
        saveProject()
    }

    func changeRowNote(row: Int, to note: MusicNote) {
        guard project.rowNotes.indices.contains(row) else { return }
        project.rowNotes[row] = note
        preview(row: row, velocity: 0.7)
        saveProject()
    }

    func preview(row: Int, velocity: Double = 1.0) {
        guard project.rowNotes.indices.contains(row) else { return }
        audio.play(
            note: project.rowNotes[row],
            channel: selectedChannel,
            duration: 0.18,
            velocity: velocity
        )
    }

    func updateSelectedChannel(waveform: ChipWaveform) {
        guard let index = project.channels.firstIndex(where: { $0.id == selectedChannelID }) else { return }
        project.channels[index].waveform = waveform
        audio.configure(channels: project.channels)
        saveProject()
    }

    func updateSelectedChannel(volume: Double) {
        guard let index = project.channels.firstIndex(where: { $0.id == selectedChannelID }) else { return }
        project.channels[index].volume = min(max(volume, 0.0), 1.0)
        saveProject()
    }

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func play() {
        audio.configure(channels: project.channels)
        warmCurrentSounds()
        isPlaying = true
        nextPlaybackStep = playheadStep % max(project.steps, 1)
        advanceStep()
        startPlaybackTimer()
        statusText = "Playing"
    }

    func stop() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audio.stopAll()
        isPlaying = false
        playheadStep = 0
        nextPlaybackStep = 0
        statusText = "Stopped"
    }

    func clearSelectedChannel() {
        project.patterns[selectedChannelID] = []
        saveProject()
    }

    func resetSong() {
        stop()
        project = ChipTuneProject.starter()
        selectedChannelID = project.channels.first?.id ?? selectedChannelID
        audio.configure(channels: project.channels)
        warmCurrentSounds()
        saveProject()
        statusText = "Reset"
    }

    func loadRemoteConfig() async {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), trimmed.isEmpty == false else {
            statusText = "Bad config URL"
            return
        }

        statusText = "Loading config"

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let config = try JSONDecoder().decode(RemoteChipTuneConfig.self, from: data)
            apply(remoteConfig: config)
            UserDefaults.standard.set(trimmed, forKey: remoteURLDefaultsKey)
            statusText = "Config loaded"
        } catch {
            statusText = "Config failed"
        }
    }

    func saveProject() {
        if let data = try? JSONEncoder().encode(project) {
            UserDefaults.standard.set(data, forKey: projectDefaultsKey)
        }
    }

    private func apply(remoteConfig: RemoteChipTuneConfig) {
        if let tempo = remoteConfig.tempo {
            project.tempo = min(max(tempo, 48), 220)
        }

        if let steps = remoteConfig.steps {
            setSteps(steps, shouldSave: false)
        }

        if let notes = remoteConfig.notes {
            let parsed = notes.compactMap { MusicNote(trackerName: $0) }
            if parsed.isEmpty == false {
                project.rowNotes = parsed
                removeOutOfRangeNotes()
            }
        }

        if let remoteChannels = remoteConfig.channels {
            for remoteChannel in remoteChannels {
                if let index = project.channels.firstIndex(where: { $0.id == remoteChannel.id }) {
                    if let title = remoteChannel.title {
                        project.channels[index].title = title
                    }
                    if let waveform = remoteChannel.waveform {
                        project.channels[index].waveform = waveform
                    }
                    if let volume = remoteChannel.volume {
                        project.channels[index].volume = min(max(volume, 0.0), 1.0)
                    }
                } else {
                    let channel = ChipTuneChannel(
                        id: remoteChannel.id,
                        title: remoteChannel.title ?? remoteChannel.id,
                        waveform: remoteChannel.waveform ?? .pulse50,
                        volume: min(max(remoteChannel.volume ?? 0.36, 0.0), 1.0)
                    )
                    project.channels.append(channel)
                    project.patterns[channel.id] = project.patterns[channel.id] ?? []
                }
            }
        }

        if let remotePatterns = remoteConfig.patterns {
            ensureStepCapacity(through: Self.requiredSteps(for: remotePatterns), shouldSave: false)
            for (channelID, remoteNotes) in remotePatterns where project.channels.contains(where: { $0.id == channelID }) {
                project.patterns[channelID] = remoteNotes.compactMap { remoteNote in
                    sequencerNote(from: remoteNote)
                }
            }
        }

        audio.configure(channels: project.channels)
        warmCurrentSounds()
        saveProject()
    }

    private func ensureStepCapacity(through requiredStep: Int, shouldSave: Bool) {
        guard requiredStep > project.steps else { return }
        let roundedSteps = ((requiredStep + 15) / 16) * 16
        setSteps(roundedSteps, shouldSave: shouldSave)
    }

    private static func requiredSteps(for patterns: [String: [RemoteSequencerNote]]) -> Int {
        patterns.values
            .flatMap { $0 }
            .map { $0.startStep + max($0.length ?? 1, 1) }
            .max() ?? minimumSteps
    }

    private func sequencerNote(from remoteNote: RemoteSequencerNote) -> SequencerNote? {
        let rowIndex: Int?
        if let row = remoteNote.row, project.rowNotes.indices.contains(row) {
            rowIndex = row
        } else if let noteName = remoteNote.note,
                  let note = MusicNote(trackerName: noteName),
                  let index = project.rowNotes.firstIndex(of: note) {
            rowIndex = index
        } else {
            rowIndex = nil
        }

        guard let rowIndex, project.steps > 0 else {
            return nil
        }

        let startStep = min(max(remoteNote.startStep, 0), project.steps - 1)
        let maxLength = max(1, project.steps - startStep)
        let length = min(max(remoteNote.length ?? 1, 1), maxLength)

        return SequencerNote(
            row: rowIndex,
            startStep: startStep,
            length: length,
            velocity: remoteNote.velocity ?? 1.0
        )
    }

    private func removeOutOfRangeNotes() {
        for channel in project.channels {
            project.patterns[channel.id] = (project.patterns[channel.id] ?? []).filter { note in
                project.rowNotes.indices.contains(note.row)
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer(timeInterval: stepDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStep()
            }
        }
        if let playbackTimer {
            RunLoop.main.add(playbackTimer, forMode: .common)
        }
    }

    private func advanceStep() {
        guard project.steps > 0 else { return }
        playheadStep = nextPlaybackStep

        for channel in project.channels {
            let notes = project.patterns[channel.id] ?? []
            for event in notes where event.startStep == playheadStep && project.rowNotes.indices.contains(event.row) {
                audio.play(
                    note: project.rowNotes[event.row],
                    channel: channel,
                    duration: stepDuration * Double(event.length) * 0.96,
                    velocity: event.velocity
                )
            }
        }

        nextPlaybackStep = (playheadStep + 1) % project.steps
    }

    private func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private static func normalized(project: ChipTuneProject) -> ChipTuneProject {
        var normalized = project
        for channel in ChipTuneChannel.defaults where normalized.channels.contains(where: { $0.id == channel.id }) == false {
            normalized.channels.append(channel)
            normalized.patterns[channel.id] = normalized.patterns[channel.id] ?? []
        }
        return normalized
    }

    private func warmCurrentSounds() {
        for channel in project.channels {
            let events = project.patterns[channel.id] ?? []
            for event in events where project.rowNotes.indices.contains(event.row) {
                audio.preload(
                    note: project.rowNotes[event.row],
                    channel: channel,
                    duration: stepDuration * Double(event.length) * 0.96
                )
            }
        }

        for row in project.rowNotes.prefix(8) {
            audio.preload(note: row, channel: selectedChannel, duration: 0.18)
        }
    }
}
