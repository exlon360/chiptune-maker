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
                if store.isSongNotesPage {
                    SongNotesPanel(store: store)
                }
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

                Text("\(store.pageTitle) \(store.pageIndicator) / \(Int(store.project.tempo)) BPM / \(store.selectedChannel.title) / \(store.statusText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            SetsMenu(store: store)

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

private struct SetsMenu: View {
    @ObservedObject var store: ChipTuneStore

    var body: some View {
        Menu {
            ForEach(0..<store.pageCount, id: \.self) { pageIndex in
                Button {
                    store.setPage(pageIndex)
                } label: {
                    Label(
                        store.pageTitle(for: pageIndex),
                        systemImage: pageIndex == store.currentPageIndex ? "checkmark.circle.fill" : "music.note.list"
                    )
                }
            }

            Divider()

            Button {
                store.nextPage()
            } label: {
                Label("More", systemImage: "ellipsis.circle.fill")
            }
        } label: {
            Label("Sets", systemImage: "square.grid.2x2.fill")
                .font(.caption.weight(.black))
                .frame(width: 78, height: 40)
        }
        .buttonStyle(ChipIconButtonStyle(tint: .chipMint))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Picker("Mode", selection: $store.editMode) {
                    Label("Draw", systemImage: "pencil.tip.crop.circle.fill").tag(ChipTuneEditMode.draw)
                    Label("Erase", systemImage: "eraser.fill").tag(ChipTuneEditMode.erase)
                }
                .pickerStyle(.segmented)
                .frame(width: 172)

                Stepper(value: Binding(
                    get: { store.selectedLength },
                    set: { store.setSelectedLength($0) }
                ), in: 1...16) {
                    Label("\(store.selectedLength)", systemImage: "arrow.left.and.right")
                        .font(.caption.weight(.black))
                        .frame(minWidth: 54)
                }

                SongLengthMenu(store: store)

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
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SongLengthMenu: View {
    @ObservedObject var store: ChipTuneStore

    var body: some View {
        Menu {
            Button {
                store.extendSong(by: 16)
            } label: {
                Label("+16 steps", systemImage: "plus")
            }

            Button {
                store.extendSong(by: 64)
            } label: {
                Label("+64 steps", systemImage: "plus")
            }

            Button {
                store.extendSong(by: 256)
            } label: {
                Label("+256 steps", systemImage: "forward.end.fill")
            }

            Button {
                store.doubleSongLength()
            } label: {
                Label("Double length", systemImage: "arrow.left.and.right")
            }

            Button {
                store.trimSongToLastNote()
            } label: {
                Label("Trim to notes", systemImage: "scissors")
            }
        } label: {
            Label("\(store.project.steps)", systemImage: "arrow.right.to.line")
                .font(.caption.weight(.black))
                .frame(width: 84, height: 34)
        }
        .buttonStyle(ChipIconButtonStyle(tint: .chipMint))
    }
}

private struct SequencerGridView: View {
    @ObservedObject var store: ChipTuneStore
    @State private var lastPaintedPoint: GridPaintPoint?
    @State private var armedResizeNoteID: UUID?
    @State private var resizeSession: ResizeSession?
    @State private var isResizingNote = false

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
                                    isSelected: store.selectedNoteID == note.id,
                                    editMode: store.editMode,
                                    previewAction: { store.preview(row: note.row, velocity: note.velocity) },
                                    deleteAction: { store.delete(noteID: note.id) },
                                    selectAction: { store.select(noteID: note.id) },
                                    armResizeAction: {
                                        store.select(noteID: note.id)
                                        armedResizeNoteID = note.id
                                    },
                                    resizeStartAction: {
                                        isResizingNote = true
                                        armedResizeNoteID = note.id
                                        store.select(noteID: note.id)
                                    },
                                    resizeAction: { translation in
                                        resize(note: note, translation: translation)
                                    },
                                    resizeEndAction: {
                                        isResizingNote = false
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
                guard isResizingNote == false else { return }
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

private struct SongNotesPanel: View {
    @ObservedObject var store: ChipTuneStore

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 54), spacing: 8)]
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Label("Song Notes", systemImage: "pianokeys")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.chipMint)

                Spacer(minLength: 0)

                Button {
                    store.useSongNotesForRows()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 34, height: 32)
                }
                .buttonStyle(ChipIconButtonStyle(tint: .chipSky))
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.songNotes) { note in
                        Button {
                            store.preview(songNote: note)
                        } label: {
                            Text(note.displayName)
                                .font(.caption.weight(.black))
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(ChipCapsuleButtonStyle(tint: .chipMint, isSelected: false))
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: 112)
        }
        .padding(10)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.chipMint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct StepHeader: View {
    let steps: Int
    let stepWidth: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(0.035)))

            let labelEvery = steps > 2048 ? 16 : 4
            for step in stride(from: 0, to: max(steps, 1), by: 4) {
                let x = CGFloat(step) * stepWidth
                let blockColor = step.isMultiple(of: 16) ? Color.white.opacity(0.1) : Color.white.opacity(0.055)
                context.fill(
                    Path(CGRect(x: x, y: 0, width: stepWidth * 4, height: height)),
                    with: .color(blockColor)
                )

                guard step.isMultiple(of: labelEvery) else { continue }
                let text = Text("\(step + 1)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(step.isMultiple(of: 16) ? Color.chipGold : Color.white.opacity(0.46))
                context.draw(text, at: CGPoint(x: x + stepWidth / 2, y: height / 2), anchor: .center)
            }
        }
        .frame(width: max(stepWidth, CGFloat(max(steps, 1)) * stepWidth), height: height)
    }
}

private struct GridBackground: View {
    let rows: Int
    let steps: Int
    let rowHeight: CGFloat
    let stepWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.chipInk.opacity(0.76)))

            for row in 0..<max(rows, 1) {
                let y = CGFloat(row) * rowHeight
                let color = Color.white.opacity(row.isMultiple(of: 2) ? 0.045 : 0.026)
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)), with: .color(color))
            }

            for step in stride(from: 0, to: max(steps, 1), by: 4) {
                let x = CGFloat(step) * stepWidth
                let color = step.isMultiple(of: 16) ? Color.chipInk.opacity(0.48) : Color.chipPanel.opacity(0.34)
                context.fill(Path(CGRect(x: x, y: 0, width: stepWidth * 4, height: size.height)), with: .color(color))
            }

            for step in 0...max(steps, 1) {
                let x = CGFloat(step) * stepWidth
                let lineColor = step.isMultiple(of: 4) ? Color.white.opacity(0.16) : Color.white.opacity(0.07)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(lineColor))
            }

            for row in 0...max(rows, 1) {
                let y = CGFloat(row) * rowHeight
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(0.055)))
            }
        }
        .frame(
            width: max(stepWidth, CGFloat(max(steps, 1)) * stepWidth),
            height: max(rowHeight, CGFloat(max(rows, 1)) * rowHeight)
        )
    }
}

private struct NoteBlock: View {
    let note: SequencerNote
    let displayNote: MusicNote
    let stepWidth: CGFloat
    let rowHeight: CGFloat
    let isArmed: Bool
    let isSelected: Bool
    let editMode: ChipTuneEditMode
    let previewAction: () -> Void
    let deleteAction: () -> Void
    let selectAction: () -> Void
    let armResizeAction: () -> Void
    let resizeStartAction: () -> Void
    let resizeAction: (CGFloat) -> Void
    let resizeEndAction: () -> Void

    @State private var isHoldResizing = false
    @State private var didDragResize = false

    var body: some View {
        let width = max(16, CGFloat(note.length) * stepWidth - 3)
        let isResizing = isArmed || isHoldResizing || didDragResize
        let noteFill = isResizing ? Color.chipGold : (isSelected ? Color.chipSky : Color.chipMint)

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
        .background(noteFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected || isResizing ? Color.white.opacity(0.76) : Color.white.opacity(0.45), lineWidth: isSelected || isResizing ? 2 : 1)
        }
        .shadow(color: noteFill.opacity(0.22), radius: 5, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode == .erase {
                deleteAction()
            } else {
                selectAction()
                previewAction()
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { armResizeAction() }
        )
        .highPriorityGesture(resizeDragGesture(width: width))
    }

    private func resizeDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard editMode != .erase else { return }
                let horizontalDrag = abs(value.translation.width)
                let verticalDrag = abs(value.translation.height)
                let beganOnHandle = value.startLocation.x >= width - 20
                let shouldResize = isArmed || isHoldResizing || beganOnHandle || horizontalDrag > max(8, verticalDrag)
                guard shouldResize else { return }

                beginResize()
                didDragResize = true
                resizeAction(value.translation.width)
            }
            .onEnded { _ in
                guard didDragResize || isHoldResizing || isArmed else { return }
                isHoldResizing = false
                didDragResize = false
                resizeEndAction()
            }
    }

    private func beginResize() {
        guard isHoldResizing == false && didDragResize == false else { return }
        isHoldResizing = true
        resizeStartAction()
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
            selectedNoteRow
            selectedNoteVolumeSlider
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

    @ViewBuilder
    private var selectedNoteRow: some View {
        if let note = store.selectedNote {
            HStack(spacing: 10) {
                Label(selectedNoteTitle(note), systemImage: "music.note")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.chipMint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Stepper(value: selectedNoteLengthBinding, in: 1...max(store.project.steps, 1)) {
                    Label("\(note.length)", systemImage: "arrow.left.and.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.chipGold)
                        .frame(width: 58)
                }
                .frame(maxWidth: 142)

                Button {
                    store.previewSelectedNote()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 34, height: 32)
                }
                .buttonStyle(ChipIconButtonStyle(tint: .chipMint))
            }
        } else {
            HStack(spacing: 10) {
                Label("Note --", systemImage: "music.note")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var selectedNoteVolumeSlider: some View {
        if let note = store.selectedNote {
            HStack(spacing: 10) {
                Label("\(Int(note.velocity * 100))", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.chipMint)
                    .frame(width: 64, alignment: .leading)

                Slider(value: selectedNoteVelocityBinding, in: 0.05...1, step: 0.01)
                    .tint(Color.chipMint)
            }
        }
    }

    private func selectedNoteTitle(_ note: SequencerNote) -> String {
        let noteName = store.project.rowNotes.indices.contains(note.row) ? store.project.rowNotes[note.row].displayName : "--"
        return "\(noteName) @ \(note.startStep + 1)"
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

    private var selectedNoteVelocityBinding: Binding<Double> {
        Binding<Double>(
            get: { store.selectedNote?.velocity ?? 1.0 },
            set: { store.updateSelectedNoteVelocity($0) }
        )
    }

    private var selectedNoteLengthBinding: Binding<Int> {
        Binding<Int>(
            get: { store.selectedNote?.length ?? 1 },
            set: { store.updateSelectedNoteLength($0) }
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
