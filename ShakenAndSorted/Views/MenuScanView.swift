import SwiftUI
import PhotosUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct MenuScanView: View {
    var onRecognized: (MenuRecognitionResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var words: [MenuWord] = []
    @State private var strokes: [HighlightStroke] = []
    @State private var mode: HighlightMode = .name
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                if let image {
                    highlighterCanvas(image)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Scan menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                if image != nil {
                    modePicker
                }
            }
            .safeAreaInset(edge: .bottom) {
                if image != nil {
                    controls
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $image, isPresented: $showingCamera)
                    .ignoresSafeArea()
            }
            .alert("Could not read the menu", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isReading {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Reading the menu…")
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
        .onChange(of: image) { _, newImage in
            strokes = []
            words = []
            mode = .name
            if let newImage {
                Task { await readText(in: newImage) }
            }
        }
    }

    private var fit: CGRect {
        guard let image else { return .zero }
        return MenuHighlightReader.aspectFitRect(imageSize: image.size, in: canvasSize)
    }

    /// Word boxes each mode has picked up, in canvas coordinates, for drawing.
    private var highlightedWords: [HighlightMode: [CGRect]] {
        let fit = fit
        let picked = MenuHighlightReader.assignments(words: words, strokes: strokes, fit: fit)
        var rects: [HighlightMode: [CGRect]] = [:]
        for word in words {
            guard let strokeIndex = picked[word.id] else { continue }
            rects[strokes[strokeIndex].mode, default: []]
                .append(MenuHighlightReader.canvasRect(for: word, fit: fit).insetBy(dx: -1, dy: -1))
        }
        return rects
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "menucard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Photo a menu, then highlight one drink.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            Text("Swipe over the name, ingredients, and price like a highlighter — each in its own color.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose from library", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }

    private func highlighterCanvas(_ image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                HighlighterCanvas(
                    image: image,
                    size: geo.size,
                    mode: mode,
                    strokes: $strokes,
                    highlightedWords: highlightedWords
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                canvasSize = newSize
            }
            .accessibilityLabel("Menu photo. Swipe over words to highlight them. Pinch to zoom.")
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(HighlightMode.allCases, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(option.color))
                            .frame(width: 12, height: 12)
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(mode == option ? AppTheme.primaryText : AppTheme.secondaryText)
                    .background(
                        Capsule().fill(mode == option ? Color(option.color).opacity(0.3) : AppTheme.card)
                    )
                    .overlay(
                        Capsule().strokeBorder(mode == option ? Color(option.color) : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text("Swipe over words to highlight. Pinch to zoom, two fingers to move.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Photo", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                Button {
                    strokes.removeLast()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(strokes.isEmpty)

                Button {
                    strokes = []
                } label: {
                    Label("Clear", systemImage: "eraser")
                }
                .buttonStyle(.bordered)
                .disabled(strokes.isEmpty)
            }
            .labelStyle(.iconOnly)

            Button {
                useHighlights()
            } label: {
                Label("Fill in drink", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReading || strokes.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.card.ignoresSafeArea(edges: .bottom))
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let loaded = UIImage(data: data) {
            await MainActor.run { image = loaded.normalizedUp() }
        }
    }

    @MainActor
    private func readText(in image: UIImage) async {
        isReading = true
        defer { isReading = false }
        do {
            let found = try await MenuTextReader.words(in: image)
            // Ignore a result for a photo that has since been replaced.
            guard self.image === image else { return }
            words = found
            if found.isEmpty {
                errorMessage = MenuRecognitionError.noText.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func useHighlights() {
        let result = MenuHighlightReader.result(words: words, strokes: strokes, fit: fit)
        guard result.hasAnything else {
            errorMessage = MenuRecognitionError.nothingHighlighted.localizedDescription
            return
        }
        var scanned = result
        scanned.photoData = image?.normalizedUp().jpegData(compressionQuality: 0.7)
        onRecognized(scanned)
        dismiss()
    }
}

/// Menu photo you swipe over like a highlighter. One finger highlights; pinch
/// zooms and two fingers pan. Strokes are kept in unzoomed canvas coordinates.
struct HighlighterCanvas: UIViewRepresentable {
    let image: UIImage
    let size: CGSize
    let mode: HighlightMode
    @Binding var strokes: [HighlightStroke]
    let highlightedWords: [HighlightMode: [CGRect]]

    func makeCoordinator() -> Coordinator {
        Coordinator(strokes: $strokes)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let coordinator = context.coordinator
        let scrollView = UIScrollView()
        scrollView.delegate = coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.contentInsetAdjustmentBehavior = .never

        let content = UIView()
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        content.addSubview(imageView)
        for layer in coordinator.layers {
            content.layer.addSublayer(layer)
        }
        scrollView.addSubview(content)

        let draw = HighlightPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.draw(_:)))
        draw.maximumNumberOfTouches = 1
        draw.delegate = coordinator
        content.addGestureRecognizer(draw)
        // A second finger means zoom or move, so drop the stroke the first finger started.
        scrollView.pinchGestureRecognizer?.addTarget(coordinator, action: #selector(Coordinator.cancelStroke(_:)))
        scrollView.panGestureRecognizer.addTarget(coordinator, action: #selector(Coordinator.cancelStroke(_:)))

        coordinator.content = content
        coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.strokes = $strokes
        coordinator.mode = mode
        coordinator.highlightedWords = highlightedWords

        if coordinator.image !== image {
            coordinator.image = image
            coordinator.imageView?.image = image
            scrollView.setZoomScale(1, animated: false)
        }
        if coordinator.size != size {
            coordinator.size = size
            scrollView.setZoomScale(1, animated: false)
            let frame = CGRect(origin: .zero, size: size)
            coordinator.content?.frame = frame
            coordinator.imageView?.frame = frame
            coordinator.layers.forEach { $0.frame = frame }
            scrollView.contentSize = size
        }
        coordinator.redraw()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var strokes: Binding<[HighlightStroke]>
        var mode: HighlightMode = .name
        var highlightedWords: [HighlightMode: [CGRect]] = [:]
        weak var content: UIView?
        weak var imageView: UIImageView?
        var image: UIImage?
        var size: CGSize = .zero

        private var strokeLayers: [HighlightMode: CAShapeLayer] = [:]
        private var wordLayers: [HighlightMode: CAShapeLayer] = [:]
        private let liveLayer = CAShapeLayer()
        private var livePoints: [CGPoint] = []
        private var strokeCancelled = false
        private var zoomScale: CGFloat = 1

        /// Pen width on screen; divided by zoom so it stays the same size under your finger.
        private let penWidth: CGFloat = 14

        init(strokes: Binding<[HighlightStroke]>) {
            self.strokes = strokes
            super.init()
            for mode in HighlightMode.allCases {
                let stroke = CAShapeLayer()
                stroke.fillColor = mode.color.withAlphaComponent(0.2).cgColor
                strokeLayers[mode] = stroke
                let words = CAShapeLayer()
                words.fillColor = mode.color.withAlphaComponent(0.45).cgColor
                wordLayers[mode] = words
            }
        }

        var layers: [CALayer] {
            HighlightMode.allCases.compactMap { strokeLayers[$0] }
                + HighlightMode.allCases.compactMap { wordLayers[$0] }
                + [liveLayer]
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            content
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func draw(_ gesture: HighlightPanGestureRecognizer) {
            guard let content else { return }
            let point = gesture.location(in: content)
            switch gesture.state {
            case .began:
                // The pan only starts after the finger has moved a little; begin where it landed.
                livePoints = [gesture.touchDownLocation ?? point, point]
                strokeCancelled = gesture.numberOfTouches > 1
            case .changed:
                guard !strokeCancelled else { return }
                livePoints.append(point)
            case .ended:
                livePoints.append(point)
                if !strokeCancelled, !livePoints.isEmpty {
                    strokes.wrappedValue.append(
                        HighlightStroke(mode: mode, points: livePoints, width: penWidth / zoomScale)
                    )
                }
                livePoints = []
                strokeCancelled = false
            default:
                livePoints = []
                strokeCancelled = false
            }
            redraw()
        }

        @objc func cancelStroke(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began else { return }
            strokeCancelled = true
            livePoints = []
            redraw()
        }

        func redraw() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for mode in HighlightMode.allCases {
                let strokePath = CGMutablePath()
                for stroke in strokes.wrappedValue where stroke.mode == mode {
                    strokePath.addPath(Self.outline(of: stroke.points, width: stroke.width))
                }
                strokeLayers[mode]?.path = strokePath

                let wordPath = CGMutablePath()
                for rect in highlightedWords[mode] ?? [] {
                    wordPath.addRoundedRect(in: rect, cornerWidth: 3, cornerHeight: 3)
                }
                wordLayers[mode]?.path = wordPath
            }
            liveLayer.fillColor = mode.color.withAlphaComponent(0.35).cgColor
            liveLayer.path = strokeCancelled || livePoints.isEmpty
                ? nil
                : Self.outline(of: livePoints, width: penWidth / zoomScale)
            CATransaction.commit()
        }

        private static func outline(of points: [CGPoint], width: CGFloat) -> CGPath {
            let line = CGMutablePath()
            guard let first = points.first else { return line }
            line.move(to: first)
            points.dropFirst().forEach { line.addLine(to: $0) }
            if points.count == 1 { line.addLine(to: first) }
            return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }
    }
}

/// A one-finger pan that remembers where the finger first touched down.
final class HighlightPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var touchDownLocation: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDownLocation == nil {
            touchDownLocation = touches.first?.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDownLocation = nil
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var image: UIImage?
        @Binding var isPresented: Bool

        init(image: Binding<UIImage?>, isPresented: Binding<Bool>) {
            _image = image
            _isPresented = isPresented
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let picked = info[.originalImage] as? UIImage {
                image = picked.normalizedUp()
            }
            isPresented = false
        }
    }
}
