import SwiftUI

struct ContentView: View {
    @StateObject private var store = ChipTuneStore()
    @State private var showingRemoteConfig = false

    var body: some View {
        ZStack {
            ChipBackdrop()

            VStack(spacing: 10) {
                HeaderView(store: store, remoteAction: { showingRemoteConfig = true })
                ChannelStrip(store: store)
                TransportPanel(store: store)
                SequencerGridView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MixerPanel(store: store)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showingRemoteConfig) {
            RemoteConfigView(store: store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var store: ChipTuneStore
    let remoteAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ChipTune Creator")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(Int(store.project.tempo)) BPM / \(store.selectedChannel.title) / \(store.statusText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            Button(action: remoteAction) {
                Image(systemName: "arrow.down.doc.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(ChipIconButtonStyle(tint: .chipSky))

            Button {
                store.togglePlayback()
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 48, height: 40)
            }
            .buttonStyle(ChipPrimaryButtonStyle(isActive: store.isPlaying))
        }
    }
}

private struct ChannelStrip: View {
    @ObservedObject var store: ChipTuneStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.project.channels) { channel in
                    Button {
                        store.selectChannel(channel.id)
                    } label: {
                        Label(channel.title, systemImage: channel.waveform.symbolName)
                            .font(.caption.weight(.black))
                            .frame(height: 34)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(ChipCapsuleButtonStyle(tint: channel.waveform.tint, isSelected: store.selectedChannelID == channel.id))
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct TransportPanel: View {
    @ObservedObject var store: ChipTuneStore

    var body: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $store.editMode) {
                Label("Draw", systemImage: "pencil.tip.crop.circle.fill").tag(ChipTuneEditMode.draw)
                Label("Erase", systemImage: "eraser.fill").tag(ChipTuneEditMode.erase)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 188)

            Stepper(value: Binding(
                get: { store.selectedLength },
                set: { store.setSelectedLength($0) }
            ), in: 1...16) {
                Label("\(store.selectedLength)", systemImage: "arrow.left.and.right")
                    .font(.caption.weight(.black))
                    .frame(minWidth: 54)
            }

            Button {
                store.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 36, height: 34)
            }
            .buttonStyle(ChipIconButtonStyle(tint: .chipRose))

            Button {
                store.clearSelectedChannel()
            } label: {
                Image(systemName: "trash.fill")
                    .frame(width: 36, height: 34)
            }
            .buttonStyle(ChipIconButtonStyle(tint: .chipGold))
        }
    }
}

private struct SequencerGridView: View {
    @ObservedObject var store: ChipTuneStore
    @State private var lastPaintedPoint: GridPaintPoint?
    @State private var armedResizeNoteID: UUID?
    @State private var resizeSession: ResizeSession?

    private let rowHeight: CGFloat = 30
    private let stepWidth: CGFloat = 32
    private let labelWidth: CGFloat = 68
    private let headerHeight: CGFloat = 24

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 1) {
                    Color.clear.frame(width: labelWidth, height: headerHeight)

                    ForEach(Array(store.project.rowNotes.enumerated()), id: \.offset) { index, note in
                        NoteRowMenu(
                            note: note,
                            palette: MusicNote.trackerPalette().reversed(),
                            action: { nextNote in store.changeRowNote(row: index, to: nextNote) }
                        )
                        .frame(width: labelWidth, height: rowHeight)
                    }
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 1) {
                        StepHeader(steps: store.project.steps, stepWidth: stepWidth, height: headerHeight)

                        ZStack(alignment: .topLeading) {
                            GridBackground(
                                rows: store.project.rowNotes.count,
                                steps: store.project.steps,
                                rowHeight: rowHeight,
                                stepWidth: stepWidth
                            )

                            ForEach(store.notesForSelectedChannel) { note in
                                let displayNote = store.project.rowNotes.indices.contains(note.row) ? store.project.rowNotes[note.row] : MusicNote(semitone: 0, octave: 4)
                                NoteBlock(
                                    note: note,
                                    displayNote: displayNote,
                                    stepWidth: stepWidth,
                                    rowHeight: rowHeight,
                                    isArmed: armedResizeNoteID == note.id,
                                    editMode: store.editMode,
                                    previewAction: { store.preview(row: note.row, velocity: note.velocity) },
                                    deleteAction: { store.delete(noteID: note.id) },
                                    armResizeAction: { armedResizeNoteID = note.id },
                                    resizeAction: { translation in
                                        resize(note: note, translation: translation)
                                    },
                                    resizeEndAction: {
                                        resizeSession = nil
                                        armedResizeNoteID = nil
                                        store.finishResize()
                                    }
                                )
                                .offset(
                                    x: CGFloat(note.startStep) * stepWidth + 1,
                                    y: CGFloat(note.row) * rowHeight + 2
                                )
                            }

                            if store.isPlaying {
                                Rectangle()
                                    .fill(Color.chipMint.opacity(0.9))
                                    .frame(width: 2, height: CGFloat(store.project.rowNotes.count) * rowHeight)
                                    .offset(x: CGFloat(store.playheadStep) * stepWidth)
                                    .shadow(color: .chipMint.opacity(0.8), radius: 6)
                            }
                        }
                        .frame(
                            width: CGFloat(store.project.steps) * stepWidth,
                            height: CGFloat(store.project.rowNotes.count) * rowHeight
                        )
                        .contentShape(Rectangle())
                        .gesture(gridPaintGesture)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var gridPaintGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let point = gridPoint(for: value.location), point != lastPaintedPoint else { return }
                lastPaintedPoint = point
                store.applyGridInteraction(row: point.row, step: point.step)
            }
            .onEnded { _ in
                lastPaintedPoint = nil
            }
    }

    private func gridPoint(for location: CGPoint) -> GridPaintPoint? {
        let row = Int(location.y / rowHeight)
        let step = Int(location.x / stepWidth)
        guard row >= 0,
              row < store.project.rowNotes.count,
              step >= 0,
              step < store.project.steps else {
            return nil
        }
        return GridPaintPoint(row: row, step: step)
    }

    private func resize(note: SequencerNote, translation: CGFloat) {
        if resizeSession == nil {
            resizeSession = ResizeSession(noteID: note.id, originalLength: note.length)
        }

        guard let session = resizeSession, session.noteID == note.id else { return }
        let deltaSteps = Int((translation / stepWidth).rounded())
        store.resize(noteID: note.id, length: session.originalLength + deltaSteps)
    }
}

private struct StepHeader: View {
    let steps: Int
    let stepWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<steps, id: \.self) { step in
                Text(step.isMultiple(of: 4) ? "\(step + 1)" : "")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(step.isMultiple(of: 16) ? Color.chipGold : Color.white.opacity(0.46))
                    .frame(width: stepWidth, height: height)
                    .background(step.isMultiple(of: 4) ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
            }
        }
    }
}

private struct GridBackground: View {
    let rows: Int
    let steps: Int
    let rowHeight: CGFloat
    let stepWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<steps, id: \.self) { step in
                        Rectangle()
                            .fill(cellColor(row: row, step: step))
                            .frame(width: stepWidth, height: rowHeight)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(step.isMultiple(of: 4) ? Color.white.opacity(0.16) : Color.white.opacity(0.07))
                                    .frame(width: 1)
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.055))
                                    .frame(height: 1)
                            }
                    }
                }
            }
        }
    }

    private func cellColor(row: Int, step: Int) -> Color {
        if step.isMultiple(of: 16) {
            return Color.chipInk.opacity(row.isMultiple(of: 2) ? 0.82 : 0.72)
        }
        if step.isMultiple(of: 4) {
            return Color.chipPanel.opacity(row.isMultiple(of: 2) ? 0.78 : 0.66)
        }
        return Color.white.opacity(row.isMultiple(of: 2) ? 0.045 : 0.028)
    }
}

private struct NoteBlock: View {
    let note: SequencerNote
    let displayNote: MusicNote
    let stepWidth: CGFloat
    let rowHeight: CGFloat
    let isArmed: Bool
    let editMode: ChipTuneEditMode
    let previewAction: () -> Void
    let deleteAction: () -> Void
    let armResizeAction: () -> Void
    let resizeAction: (CGFloat) -> Void
    let resizeEndAction: () -> Void

    var body: some View {
        let width = max(16, CGFloat(note.length) * stepWidth - 3)

        HStack(spacing: 2) {
            Text(note.length > 2 ? "\(displayNote.displayName) \(note.length)" : displayNote.displayName)
                .font(.caption2.weight(.black))
                .foregroundStyle(.black.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.leading, 6)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .frame(width: 4, height: rowHeight - 12)
                .padding(.trailing, 4)
        }
        .frame(width: width, height: rowHeight - 4)
        .background(isArmed ? Color.chipGold : Color.chipMint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: (isArmed ? Color.chipGold : Color.chipMint).opacity(0.22), radius: 5, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode == .erase {
                deleteAction()
            } else {
                previewAction()
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { armResizeAction() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isArmed || value.startLocation.x >= width - 14 else { return }
                    resizeAction(value.translation.width)
                }
                .onEnded { _ in
                    resizeEndAction()
                }
        )
    }
}

private struct NoteRowMenu: View {
    let note: MusicNote
    let palette: ReversedCollection<[MusicNote]>
    let action: (MusicNote) -> Void

    var body: some View {
        Menu {
            ForEach(Array(palette)) { candidate in
                Button(candidate.displayName) {
                    action(candidate)
                }
            }
        } label: {
            Text(note.displayName)
                .font(.caption.weight(.black))
                .foregroundStyle(Color.chipMint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.chipMint.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

private struct MixerPanel: View {
    @ObservedObject var store: ChipTuneStore

    var body: some View {
        panelContent
            .padding(10)
            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var panelContent: some View {
        VStack(spacing: 8) {
            waveRow
            tempoRow
            volumeSlider
        }
    }

    private var waveRow: some View {
        HStack(spacing: 10) {
            Picker("Wave", selection: waveformBinding) {
                ForEach(ChipWaveform.allCases) { waveform in
                    Label(waveform.title, systemImage: waveform.symbolName).tag(waveform)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.resetSong()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 38, height: 34)
            }
            .buttonStyle(ChipIconButtonStyle(tint: Color.chipSky))
        }
    }

    private var tempoRow: some View {
        HStack(spacing: 10) {
            Label("\(Int(store.project.tempo))", systemImage: "metronome.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(Color.chipGold)
                .frame(width: 64, alignment: .leading)

            Slider(value: tempoBinding, in: 60...190, step: 1)
                .tint(Color.chipGold)

            Label("\(Int(store.selectedChannel.volume * 100))", systemImage: "speaker.wave.2.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(Color.chipSky)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var volumeSlider: some View {
        Slider(value: volumeBinding, in: 0...1)
            .tint(Color.chipSky)
    }

    private var waveformBinding: Binding<ChipWaveform> {
        Binding<ChipWaveform>(
            get: { store.selectedChannel.waveform },
            set: { store.updateSelectedChannel(waveform: $0) }
        )
    }

    private var tempoBinding: Binding<Double> {
        Binding<Double>(
            get: { store.project.tempo },
            set: { store.setTempo($0) }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding<Double>(
            get: { store.selectedChannel.volume },
            set: { store.updateSelectedChannel(volume: $0) }
        )
    }
}

private struct RemoteConfigView: View {
    @ObservedObject var store: ChipTuneStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ChipBackdrop()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("GitHub Config", systemImage: "arrow.down.doc.fill")
                        .font(.headline.weight(.black))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(ChipIconButtonStyle(tint: .chipRose))
                }

                TextField("Raw JSON URL", text: $store.remoteURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }

                HStack {
                    Text(store.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await store.loadRemoteConfig() }
                    } label: {
                        Label("Load", systemImage: "arrow.down.circle.fill")
                            .frame(minWidth: 92, minHeight: 38)
                    }
                    .buttonStyle(ChipPrimaryButtonStyle(isActive: true))
                }
            }
            .padding(16)
        }
    }
}

private struct ChipBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.018, blue: 0.025),
                Color(red: 0.04, green: 0.07, blue: 0.065),
                Color(red: 0.055, green: 0.035, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct ChipPrimaryButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(isActive ? .black : .white)
            .background(
                isActive
                    ? Color.chipMint.opacity(configuration.isPressed ? 0.8 : 1.0)
                    : Color.white.opacity(configuration.isPressed ? 0.16 : 0.09),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isActive ? 0.36 : 0.14), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct ChipIconButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(tint)
            .background(tint.opacity(configuration.isPressed ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct ChipCapsuleButtonStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.black : tint)
            .background(isSelected ? tint : tint.opacity(configuration.isPressed ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.34) : tint.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct GridPaintPoint: Equatable {
    let row: Int
    let step: Int
}

private struct ResizeSession {
    let noteID: UUID
    let originalLength: Int
}

private extension ChipWaveform {
    var symbolName: String {
        switch self {
        case .pulse12:
            return "waveform.path"
        case .pulse25:
            return "alternatingcurrent"
        case .pulse50:
            return "waveform"
        case .pulse75:
            return "waveform.path.ecg"
        case .triangle:
            return "triangle.fill"
        case .saw:
            return "chart.line.uptrend.xyaxis"
        case .sine:
            return "waveform.path"
        case .pluck:
            return "guitars.fill"
        case .noise:
            return "sparkles"
        case .kick:
            return "circle.circle.fill"
        case .snare:
            return "smallcircle.filled.circle.fill"
        case .hat:
            return "asterisk"
        case .tom:
            return "record.circle"
        }
    }

    var tint: Color {
        switch self {
        case .pulse12:
            return .chipMint
        case .pulse25:
            return .chipSky
        case .pulse50:
            return .chipGold
        case .pulse75:
            return .chipOrange
        case .triangle:
            return .chipViolet
        case .saw:
            return .chipSky
        case .sine:
            return .chipMint
        case .pluck:
            return .chipGold
        case .noise:
            return .chipRose
        case .kick:
            return .chipOrange
        case .snare:
            return .chipRose
        case .hat:
            return .chipSky
        case .tom:
            return .chipViolet
        }
    }
}

private extension Color {
    static let chipInk = Color(red: 0.025, green: 0.032, blue: 0.038)
    static let chipPanel = Color(red: 0.085, green: 0.098, blue: 0.11)
    static let chipMint = Color(red: 0.52, green: 0.96, blue: 0.64)
    static let chipSky = Color(red: 0.42, green: 0.78, blue: 1.0)
    static let chipGold = Color(red: 1.0, green: 0.76, blue: 0.24)
    static let chipRose = Color(red: 1.0, green: 0.36, blue: 0.47)
    static let chipViolet = Color(red: 0.72, green: 0.54, blue: 1.0)
    static let chipOrange = Color(red: 1.0, green: 0.54, blue: 0.24)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
