import SwiftUI
import PhotosUI
import UIKit

/// A drink's photos in a row, cover first. Tap one to view them full screen; Add photo
/// adds more (camera or library, several at once) without replacing any.
struct PhotoPickerField: View {
    @Binding var photos: [Data]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var viewing: PhotoViewerItem?
    /// The photo being dragged (its current position) and how far it sits from that slot.
    @State private var dragging: Int?
    @State private var dragStart = 0
    @State private var dragOffset: CGFloat = 0

    private let thumbnailSize: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                thumbnail(image, at: index)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollDisabled(dragging != nil)
                Text(photos.count > 1 ? "The first photo shows in the list. Press and hold a photo, then drag it to move it." : "")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .opacity(photos.count > 1 ? 1 : 0)
                    .frame(height: photos.count > 1 ? nil : 0)
            }

            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo", systemImage: "camera") {
                        afterMenuCloses { showingCamera = true }
                    }
                }
                Button("Choose from Library", systemImage: "photo.on.rectangle") {
                    afterMenuCloses { showingLibrary = true }
                }
            } label: {
                Label("Add photo", systemImage: "plus")
            }
            // Keep Take Photo first; iOS otherwise flips menus that open upward.
            .menuOrder(.fixed)
            // In a Form row every plain button reacts to a tap anywhere in the row;
            // borderless keeps the photos and this menu apart.
            .buttonStyle(.borderless)
        }
        .photosPicker(isPresented: $showingLibrary, selection: $selectedItems, maxSelectionCount: nil, matching: .images)
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photos.append(compressed(data))
                    }
                }
                selectedItems = []
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $cameraImage, isPresented: $showingCamera)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, image in
            if let image, let data = image.jpegData(compressionQuality: 0.7) {
                photos.append(data)
                cameraImage = nil
            }
        }
        .fullScreenCover(item: $viewing) { item in
            PhotoViewer(images: photos.compactMap(UIImage.init(data:)), startIndex: item.index)
        }
    }

    private func thumbnail(_ image: UIImage, at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Color.clear
            .frame(width: thumbnailSize, height: thumbnailSize)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Fill mode overflows the frame; clipping hides that part but it still catches taps.
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { viewing = PhotoViewerItem(index: index) }
            .scaleEffect(dragging == index ? 1.08 : 1)
            .shadow(color: .black.opacity(dragging == index ? 0.25 : 0), radius: 8, y: 4)
            .offset(x: dragging == index ? dragOffset : 0)
            .zIndex(dragging == index ? 1 : 0)
            .gesture(reorderGesture(startingAt: index))
            .overlay(alignment: .topTrailing) {
                Button {
                    photos.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(4)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove photo")
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(index == 0 ? "First photo" : "Photo \(index + 1)")
    }

    /// Press and hold, then drag sideways: the photo follows your finger and the others
    /// make room, so it lands where you let go.
    private func reorderGesture(startingAt index: Int) -> some Gesture {
        let step = thumbnailSize + 10
        return LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    dragging = index
                    dragStart = index
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                let moved = drag?.translation.width ?? 0
                let target = min(max(dragStart + Int((moved / step).rounded()), 0), photos.count - 1)
                if let current = dragging, target != current {
                    withAnimation(.easeOut(duration: 0.15)) {
                        let data = photos.remove(at: current)
                        photos.insert(data, at: target)
                        dragging = target
                    }
                }
                dragOffset = moved - CGFloat((dragging ?? dragStart) - dragStart) * step
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    dragging = nil
                    dragOffset = 0
                }
            }
    }

    /// Presenting while the menu is still closing is ignored, so wait for it.
    private func afterMenuCloses(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    private func compressed(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.7) ?? data
    }
}

private struct PhotoViewerItem: Identifiable {
    let index: Int
    var id: Int { index }
}
