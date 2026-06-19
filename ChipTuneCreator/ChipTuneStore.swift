import Combine
import Foundation

@MainActor
final class ChipTuneStore: ObservableObject {
    static let defaultRemoteURL = "https://raw.githubusercontent.com/exlon360/chiptune-maker/main/config/chiptune-creator.json"
    private static let pageTitles = ["Draft", "Song Notes", "Suffocated"]
    private static let minimumSteps = 8
    private static let autoExtendPaddingSteps = 64

    @Published var project: ChipTuneProject
    @Published var currentPageIndex = 0
    @Published var selectedChannelID: String
    @Published var editMode: ChipTuneEditMode = .draw
    @Published var selectedLength = 1
    @Published var isPlaying = false
    @Published var playheadStep = 0
    @Published var remoteURLString: String
    @Published var statusText = "Ready"
    @Published var selectedNoteID: UUID?
    @Published var isLooping = false
    @Published var loopStartStep = 0
    @Published var loopEndStep = 16
    @Published var keyFoldEnabled = false
    @Published var selectedKeyRoot = 0
    @Published var selectedScale: PianoRollScale = .minor

    private let projectDefaultsKey = "ChipTuneCreator.project"
    private let projectPageDefaultsPrefix = "ChipTuneCreator.project.page."
    private let currentPageDefaultsKey = "ChipTuneCreator.currentPage"
    private let remoteURLDefaultsKey = "ChipTuneCreator.remoteURL"
    private let loopEnabledDefaultsKey = "ChipTuneCreator.loop.enabled"
    private let loopStartDefaultsKey = "ChipTuneCreator.loop.start"
    private let loopEndDefaultsKey = "ChipTuneCreator.loop.end"
    private let keyFoldDefaultsKey = "ChipTuneCreator.key.fold"
    private let keyRootDefaultsKey = "ChipTuneCreator.key.root"
    private let keyScaleDefaultsKey = "ChipTuneCreator.key.scale"
    private let audio = ChiptuneAudioEngine()
    private var playbackTimer: Timer?
    private var nextPlaybackStep = 0

    init() {
        let savedPage = UserDefaults.standard.integer(forKey: currentPageDefaultsKey)
        let initialPage = Self.clampedPageIndex(savedPage)
        currentPageIndex = initialPage
        let loadedProject = Self.storedProject(
            pageIndex: initialPage,
            pagePrefix: projectPageDefaultsPrefix,
            legacyKey: projectDefaultsKey
        ) ?? Self.defaultProject(for: initialPage)

        let normalizedProject = Self.normalized(project: loadedProject, pageIndex: initialPage)
        project = normalizedProject
        selectedChannelID = normalizedProject.channels.first?.id ?? "pulse1"
        remoteURLString = UserDefaults.standard.string(forKey: remoteURLDefaultsKey) ?? Self.defaultRemoteURL
        isLooping = UserDefaults.standard.bool(forKey: loopEnabledDefaultsKey)
        loopStartStep = UserDefaults.standard.integer(forKey: loopStartDefaultsKey)
        if UserDefaults.standard.object(forKey: loopEndDefaultsKey) != nil {
            loopEndStep = UserDefaults.standard.integer(forKey: loopEndDefaultsKey)
        } else {
            loopEndStep = min(16, max(normalizedProject.steps, 1))
        }
        keyFoldEnabled = UserDefaults.standard.bool(forKey: keyFoldDefaultsKey)
        selectedKeyRoot = min(max(UserDefaults.standard.integer(forKey: keyRootDefaultsKey), 0), 11)
        if let savedScale = UserDefaults.standard.string(forKey: keyScaleDefaultsKey),
           let scale = PianoRollScale(rawValue: savedScale) {
            selectedScale = scale
        }
        audio.configure(channels: normalizedProject.channels)
        normalizeLoopRange()
        warmCurrentSounds()
    }

    var pageTitle: String {
        Self.pageTitles[currentPageIndex]
    }

    var pageIndicator: String {
        "\(currentPageIndex + 1)/\(Self.pageTitles.count)"
    }

    var pageCount: Int {
        Self.pageTitles.count
    }

    var isSongNotesPage: Bool {
        currentPageIndex == 1
    }

    func pageTitle(for pageIndex: Int) -> String {
        Self.pageTitles[Self.clampedPageIndex(pageIndex)]
    }

    func songTitle(for pageIndex: Int) -> String {
        switch Self.clampedPageIndex(pageIndex) {
        case 0:
            return "Draft Song"
        case 1:
            return "Song Notes"
        default:
            return "Suffocated by Hatred"
        }
    }

    var songNotes: [MusicNote] {
        MusicNote.suffocatedByHatredNotes()
    }

    var selectedChannel: ChipTuneChannel {
        project.channels.first(where: { $0.id == selectedChannelID }) ?? project.channels[0]
    }

    var notesForSelectedChannel: [SequencerNote] {
        notes(for: selectedChannelID)
    }

    var visibleRows: [PianoRollRow] {
        project.rowNotes.enumerated().compactMap { index, note in
            guard keyFoldEnabled == false || isNoteInSelectedKey(note) else { return nil }
            return PianoRollRow(index: index, note: note)
        }
    }

    var keyFilterTitle: String {
        guard keyFoldEnabled else { return "All Notes" }
        return "\(MusicNote.sharpNames[selectedKeyRoot]) \(selectedScale.title)"
    }

    var loopTitle: String {
        "\(loopStartStep + 1)-\(loopEndStep)"
    }

    var selectedNote: SequencerNote? {
        guard let selectedNoteID else { return nil }
        return project.patterns[selectedChannelID]?.first { $0.id == selectedNoteID }
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

    func visibleRowPosition(for rowIndex: Int) -> Int? {
        visibleRows.firstIndex { $0.index == rowIndex }
    }

    func selectChannel(_ id: String) {
        guard project.channels.contains(where: { $0.id == id }) else { return }
        selectedChannelID = id
        if selectedNote == nil {
            selectedNoteID = nil
        }
    }

    func nextPage() {
        switchPage(to: currentPageIndex + 1)
    }

    func previousPage() {
        switchPage(to: currentPageIndex - 1)
    }

    func setPage(_ pageIndex: Int) {
        switchPage(to: pageIndex)
    }

    private func switchPage(to pageIndex: Int) {
        saveProject()
        stop()

        let nextIndex = Self.wrappedPageIndex(pageIndex)
        currentPageIndex = nextIndex
        UserDefaults.standard.set(nextIndex, forKey: currentPageDefaultsKey)

        let loadedProject = Self.storedProject(
            pageIndex: nextIndex,
            pagePrefix: projectPageDefaultsPrefix,
            legacyKey: projectDefaultsKey
        ) ?? Self.defaultProject(for: nextIndex)
        let normalizedProject = Self.normalized(project: loadedProject, pageIndex: nextIndex)

        project = normalizedProject
        selectedChannelID = normalizedProject.channels.first?.id ?? "pulse1"
        selectedNoteID = nil
        playheadStep = 0
        nextPlaybackStep = 0
        audio.configure(channels: normalizedProject.channels)
        normalizeLoopRange()
        warmCurrentSounds()
        statusText = pageTitle
    }

    func setTempo(_ tempo: Double) {
        project.tempo = min(max(tempo, 48), 220)
        saveProject()
        if isPlaying {
            startPlaybackTimer()
        }
    }

    func nudgeTempo(by amount: Double) {
        setTempo(project.tempo + amount)
    }

    func setLoopEnabled(_ enabled: Bool) {
        isLooping = enabled
        normalizeLoopRange()
        saveLoopSettings()
        if enabled && (playheadStep < loopStartStep || playheadStep >= loopEndStep) {
            playheadStep = loopStartStep
            nextPlaybackStep = loopStartStep
        }
        statusText = enabled ? "Loop \(loopTitle)" : "Loop off"
    }

    func setLoopStart(_ step: Int) {
        loopStartStep = min(max(step, 0), max(project.steps - 1, 0))
        if loopEndStep <= loopStartStep {
            loopEndStep = min(project.steps, loopStartStep + 1)
        }
        normalizeLoopRange()
        saveLoopSettings()
        statusText = "Loop \(loopTitle)"
    }

    func setLoopEnd(_ step: Int) {
        loopEndStep = min(max(step, 1), max(project.steps, 1))
        if loopEndStep <= loopStartStep {
            loopStartStep = max(0, loopEndStep - 1)
        }
        normalizeLoopRange()
        saveLoopSettings()
        statusText = "Loop \(loopTitle)"
    }

    func setLoopLength(_ length: Int) {
        let clampedLength = min(max(length, 1), max(project.steps, 1))
        if loopStartStep + clampedLength > project.steps {
            loopStartStep = max(0, project.steps - clampedLength)
        }
        loopEndStep = min(project.steps, loopStartStep + clampedLength)
        normalizeLoopRange()
        saveLoopSettings()
        statusText = "Loop \(loopTitle)"
    }

    func shiftLoop(by amount: Int) {
        let length = max(1, loopEndStep - loopStartStep)
        let nextStart = min(max(loopStartStep + amount, 0), max(project.steps - length, 0))
        loopStartStep = nextStart
        loopEndStep = min(project.steps, nextStart + length)
        normalizeLoopRange()
        saveLoopSettings()
        statusText = "Loop \(loopTitle)"
    }

    func setKeyFoldEnabled(_ enabled: Bool) {
        keyFoldEnabled = enabled
        selectedNoteID = visibleRowPositionForSelectedNote() == nil ? nil : selectedNoteID
        saveKeySettings()
        statusText = enabled ? keyFilterTitle : "All notes"
    }

    func setKeyRoot(_ root: Int) {
        selectedKeyRoot = min(max(root, 0), 11)
        keyFoldEnabled = true
        selectedNoteID = visibleRowPositionForSelectedNote() == nil ? nil : selectedNoteID
        saveKeySettings()
        statusText = keyFilterTitle
    }

    func setScale(_ scale: PianoRollScale) {
        selectedScale = scale
        keyFoldEnabled = true
        selectedNoteID = visibleRowPositionForSelectedNote() == nil ? nil : selectedNoteID
        saveKeySettings()
        statusText = keyFilterTitle
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
        normalizeLoopRange()
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
        case .scroll:
            break
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
        selectedNoteID = newNote.id
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
        let deletedSelectedNote = channelNotes.contains { $0.id == selectedNoteID && $0.row == row && $0.covers(step: step) }
        let originalCount = channelNotes.count
        channelNotes.removeAll { $0.row == row && $0.covers(step: step) }
        guard channelNotes.count != originalCount else { return }
        project.patterns[selectedChannelID] = channelNotes
        if deletedSelectedNote {
            selectedNoteID = nil
        }
        saveProject()
    }

    func delete(noteID: UUID) {
        var channelNotes = project.patterns[selectedChannelID] ?? []
        channelNotes.removeAll { $0.id == noteID }
        project.patterns[selectedChannelID] = channelNotes
        if selectedNoteID == noteID {
            selectedNoteID = nil
        }
        saveProject()
    }

    func select(noteID: UUID) {
        guard project.patterns[selectedChannelID]?.contains(where: { $0.id == noteID }) == true else { return }
        selectedNoteID = noteID
        statusText = "Note selected"
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
        selectedNoteID = noteID
    }

    func finishResize() {
        saveProject()
    }

    func updateSelectedNoteLength(_ length: Int) {
        guard let selectedNoteID else { return }
        resize(noteID: selectedNoteID, length: length)
        finishResize()
    }

    func updateSelectedNoteVelocity(_ velocity: Double) {
        guard let selectedNoteID,
              var channelNotes = project.patterns[selectedChannelID],
              let index = channelNotes.firstIndex(where: { $0.id == selectedNoteID }) else {
            return
        }

        var note = channelNotes[index]
        note.velocity = min(max(velocity, 0.05), 1.0)
        channelNotes[index] = note
        project.patterns[selectedChannelID] = channelNotes
        statusText = "Note \(Int(note.velocity * 100))"
        saveProject()
    }

    func previewSelectedNote() {
        guard let selectedNote, project.rowNotes.indices.contains(selectedNote.row) else { return }
        audio.play(
            note: project.rowNotes[selectedNote.row],
            channel: selectedChannel,
            duration: stepDuration * Double(selectedNote.length) * 0.96,
            velocity: selectedNote.velocity
        )
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

    func preview(songNote: MusicNote) {
        audio.play(
            note: songNote,
            channel: selectedChannel,
            duration: 0.28,
            velocity: 1.0
        )
        statusText = songNote.displayName
    }

    func useSongNotesForRows() {
        let rows = MusicNote.suffocatedByHatredNotes()
        guard rows.isEmpty == false else { return }
        project.rowNotes = rows
        removeOutOfRangeNotes()
        selectedNoteID = nil
        saveProject()
        statusText = "Song notes"
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
        normalizeLoopRange()
        if isLooping {
            nextPlaybackStep = (playheadStep >= loopStartStep && playheadStep < loopEndStep) ? playheadStep : loopStartStep
        } else {
            nextPlaybackStep = playheadStep % max(project.steps, 1)
        }
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
        selectedNoteID = nil
        saveProject()
    }

    func resetSong() {
        stop()
        project = Self.defaultProject(for: currentPageIndex)
        selectedChannelID = project.channels.first?.id ?? selectedChannelID
        selectedNoteID = nil
        audio.configure(channels: project.channels)
        normalizeLoopRange()
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
            UserDefaults.standard.set(data, forKey: Self.projectKey(pageIndex: currentPageIndex, prefix: projectPageDefaultsPrefix))
            if currentPageIndex == 0 {
                UserDefaults.standard.set(data, forKey: projectDefaultsKey)
            }
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
            selectedNoteID = nil
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

        let followingStep = playheadStep + 1
        if isLooping {
            nextPlaybackStep = followingStep >= loopEndStep ? loopStartStep : followingStep
        } else {
            nextPlaybackStep = followingStep % project.steps
        }
    }

    private func isNoteInSelectedKey(_ note: MusicNote) -> Bool {
        let interval = (note.semitone - selectedKeyRoot + 12) % 12
        return selectedScale.intervals.contains(interval)
    }

    private func visibleRowPositionForSelectedNote() -> Int? {
        guard let selectedNote else { return nil }
        return visibleRowPosition(for: selectedNote.row)
    }

    private func normalizeLoopRange() {
        let stepCount = max(project.steps, 1)
        loopStartStep = min(max(loopStartStep, 0), max(stepCount - 1, 0))
        loopEndStep = min(max(loopEndStep, loopStartStep + 1), stepCount)
        if loopEndStep <= loopStartStep {
            loopStartStep = 0
            loopEndStep = min(16, stepCount)
        }
    }

    private func saveLoopSettings() {
        UserDefaults.standard.set(isLooping, forKey: loopEnabledDefaultsKey)
        UserDefaults.standard.set(loopStartStep, forKey: loopStartDefaultsKey)
        UserDefaults.standard.set(loopEndStep, forKey: loopEndDefaultsKey)
    }

    private func saveKeySettings() {
        UserDefaults.standard.set(keyFoldEnabled, forKey: keyFoldDefaultsKey)
        UserDefaults.standard.set(selectedKeyRoot, forKey: keyRootDefaultsKey)
        UserDefaults.standard.set(selectedScale.rawValue, forKey: keyScaleDefaultsKey)
    }

    private func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private static func defaultProject(for pageIndex: Int) -> ChipTuneProject {
        switch clampedPageIndex(pageIndex) {
        case 0:
            return ChipTuneProject.blankDraft()
        case 1:
            return ChipTuneProject.songNotesDraft()
        default:
            return ChipTuneProject.starter()
        }
    }

    private static func projectKey(pageIndex: Int, prefix: String) -> String {
        "\(prefix)\(clampedPageIndex(pageIndex))"
    }

    private static func storedProject(pageIndex: Int, pagePrefix: String, legacyKey: String) -> ChipTuneProject? {
        let pageKey = projectKey(pageIndex: pageIndex, prefix: pagePrefix)
        if let data = UserDefaults.standard.data(forKey: pageKey),
           let decoded = try? JSONDecoder().decode(ChipTuneProject.self, from: data) {
            return decoded
        }

        guard clampedPageIndex(pageIndex) == 0,
              let data = UserDefaults.standard.data(forKey: legacyKey),
              let decoded = try? JSONDecoder().decode(ChipTuneProject.self, from: data) else {
            return nil
        }

        return decoded
    }

    private static func clampedPageIndex(_ pageIndex: Int) -> Int {
        min(max(pageIndex, 0), pageTitles.count - 1)
    }

    private static func wrappedPageIndex(_ pageIndex: Int) -> Int {
        let pageCount = pageTitles.count
        return (pageIndex % pageCount + pageCount) % pageCount
    }

    private static func normalized(project: ChipTuneProject, pageIndex: Int) -> ChipTuneProject {
        var normalized = project
        for channel in ChipTuneChannel.defaults where normalized.channels.contains(where: { $0.id == channel.id }) == false {
            normalized.channels.append(channel)
            normalized.patterns[channel.id] = normalized.patterns[channel.id] ?? []
        }
        if clampedPageIndex(pageIndex) == 2 {
            for songChannel in ChipTuneChannel.suffocatedSongDefaults {
                guard let index = normalized.channels.firstIndex(where: { $0.id == songChannel.id }) else { continue }
                normalized.channels[index].title = songChannel.title
                normalized.channels[index].waveform = songChannel.waveform
            }
        }
        return normalized
    }

    private func warmCurrentSounds() {
        var warmedKeys = Set<String>()

        for channel in project.channels {
            let events = project.patterns[channel.id] ?? []
            for event in events where project.rowNotes.indices.contains(event.row) {
                let warmKey = "\(channel.id)-\(event.row)-\(event.length)"
                guard warmedKeys.insert(warmKey).inserted else { continue }

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
