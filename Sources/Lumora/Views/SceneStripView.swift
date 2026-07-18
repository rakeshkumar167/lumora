import Combine
import LumoraKit
import SwiftUI

/// Full-width strip of scene chips below the canvas: select, add, delete,
/// reorder, rename, and set each scene's play duration. A Preview toggle
/// cycles through the scenes in the editor.
struct SceneStripView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var editingIndex: Int?
    @FocusState private var nameFocused: Bool
    @State private var showCopyPrompt = false
    @State private var previewing = false
    @State private var previewElapsed: Double = 0
    /// Only alive while previewing, so nothing ticks when idle.
    @State private var previewTimer: AnyCancellable?

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(store.scenes.enumerated()), id: \.element.id) { index, scene in
                        chip(index: index, scene: scene)
                    }
                    Button {
                        if store.activeScene?.surfaces.isEmpty == false {
                            showCopyPrompt = true
                        } else {
                            store.addScene()
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .help("Add scene")
                }
                .padding(.vertical, 8)
            }

            Divider().frame(height: 32)
            activeControls
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(.bar)
        .onDisappear { previewTimer = nil }
        .confirmationDialog(
            "Copy surface outlines from this scene into the new one?",
            isPresented: $showCopyPrompt,
            titleVisibility: .visible
        ) {
            Button("Copy Outlines") { store.addScene(copyOutlinesFromActive: true) }
            Button("Empty Scene") { store.addScene() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(index: Int, scene: ProjectScene) -> some View {
        let isActive = index == store.activeSceneIndex
        VStack(spacing: 1) {
            if editingIndex == index {
                TextField("Name", text: nameBinding(index))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 92)
                    .focused($nameFocused)
                    .onSubmit { editingIndex = nil }
                    .onExitCommand { editingIndex = nil }
            } else {
                Text(scene.name)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            Text("\(Int(scene.duration))s")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 84)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(index) }
        .onTapGesture { store.selectScene(index) }
        .contextMenu {
            Button("Rename") { beginRename(index) }
            Button("Delete", role: .destructive) { store.deleteScene(index) }
                .disabled(store.scenes.count <= 1)
        }
    }

    // MARK: - Controls for the active scene

    private var activeControls: some View {
        HStack(spacing: 10) {
            Stepper(value: durationBinding, in: 1...600, step: 1) {
                Text("\(Int(store.activeScene?.duration ?? 15))s")
                    .font(.caption).monospacedDigit()
            }
            .fixedSize()
            .help("How long this scene plays")

            Divider().frame(height: 20)

            Button { store.moveScene(from: store.activeSceneIndex, to: store.activeSceneIndex - 1) } label: {
                Image(systemName: "arrow.left")
            }
            .disabled(store.activeSceneIndex <= 0)
            .help("Move scene left")

            Button { store.moveScene(from: store.activeSceneIndex, to: store.activeSceneIndex + 1) } label: {
                Image(systemName: "arrow.right")
            }
            .disabled(store.activeSceneIndex >= store.scenes.count - 1)
            .help("Move scene right")

            Button { store.deleteScene(store.activeSceneIndex) } label: {
                Image(systemName: "trash")
            }
            .disabled(store.scenes.count <= 1)
            .help("Delete scene")

            Divider().frame(height: 20)

            Button {
                previewing.toggle()
                previewElapsed = 0
                if previewing {
                    previewTimer = Timer.publish(every: 0.2, on: .main, in: .common)
                        .autoconnect()
                        .sink { _ in advancePreview() }
                } else {
                    previewTimer = nil
                }
            } label: {
                Image(systemName: previewing ? "pause.fill" : "play.fill")
            }
            .help("Preview the scene sequence in the editor")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Helpers

    private func advancePreview() {
        guard previewing, store.scenes.count > 1 else { return }
        previewElapsed += 0.2
        let dur = max(1, store.activeScene?.duration ?? 15)
        if previewElapsed >= dur {
            previewElapsed = 0
            store.selectScene((store.activeSceneIndex + 1) % store.scenes.count)
        }
    }

    private func beginRename(_ index: Int) {
        store.selectScene(index)
        editingIndex = index
        DispatchQueue.main.async { nameFocused = true }
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { store.scenes.indices.contains(index) ? store.scenes[index].name : "" },
            set: { store.renameScene(index, $0) }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { store.activeScene?.duration ?? 15 },
            set: { store.setSceneDuration(store.activeSceneIndex, $0) }
        )
    }
}
