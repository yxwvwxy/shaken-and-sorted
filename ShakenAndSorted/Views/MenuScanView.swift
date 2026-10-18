import SwiftUI
import PhotosUI
import UIKit

struct MenuScanView: View {
    var onRecognized: (MenuRecognitionResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var path = Path()
    @State private var currentStroke = Path()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingAPIKey = false
    @State private var apiKeyDraft = ""
    @State private var isRecognizing = false
    @State private var errorMessage: String?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                if let image {
                    drawingCanvas(image)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("API Key") {
                        apiKeyDraft = APIKeyStore.openAIKey
                        showingAPIKey = true
                    }
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
            .sheet(isPresented: $showingAPIKey) {
                apiKeySheet
            }
            .alert("Could not recognize", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isRecognizing {
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
        .onChange(of: image) { _, _ in
            path = Path()
            currentStroke = Path()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "menucard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Photo a menu, then circle one drink.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            Text("A rough loop is enough. If the line covers a little text, that is fine.")
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

    private func drawingCanvas(_ image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)

                Canvas { context, _ in
                    context.stroke(
                        path,
                        with: .color(AppTheme.accent),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    context.stroke(
                        currentStroke,
                        with: .color(AppTheme.accent.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                }
                .contentShape(Rectangle())
                .gesture(drawGesture)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                canvasSize = newSize
            }
            .accessibilityLabel("Menu photo. Draw a circle around one drink.")
        }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if currentStroke.isEmpty {
                    currentStroke.move(to: value.startLocation)
                }
                currentStroke.addLine(to: value.location)
            }
            .onEnded { _ in
                path.addPath(currentStroke)
                currentStroke = Path()
            }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text("Circle the drink, then recognize.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Photo", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    path = Path()
                    currentStroke = Path()
                } label: {
                    Label("Clear", systemImage: "eraser")
                }
                .buttonStyle(.bordered)
                .disabled(path.isEmpty && currentStroke.isEmpty)
            }

            Button {
                Task { await recognize() }
            } label: {
                Label("Recognize", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRecognizing || (path.isEmpty && currentStroke.isEmpty))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.card.ignoresSafeArea(edges: .bottom))
    }

    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $apiKeyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    Text("Stored on this iPhone only. Used to read the circled drink. Model: \(MenuRecognizer.model).")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAPIKey = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        APIKeyStore.openAIKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        showingAPIKey = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(AppTheme.accent)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let loaded = UIImage(data: data) {
            await MainActor.run { image = loaded.normalizedUp() }
        }
    }

    @MainActor
    private func recognize() async {
        guard let image else { return }
        var drawn = path
        drawn.addPath(currentStroke)
        guard !drawn.isEmpty else {
            errorMessage = MenuRecognitionError.noCircle.localizedDescription
            return
        }

        if !APIKeyStore.hasOpenAIKey {
            apiKeyDraft = APIKeyStore.openAIKey
            showingAPIKey = true
            return
        }

        guard let cropped = MenuCropper.crop(
            image: image,
            path: drawn,
            containerSize: canvasSize
        ) else {
            errorMessage = MenuRecognitionError.cropFailed.localizedDescription
            return
        }

        isRecognizing = true
        defer { isRecognizing = false }

        do {
            let result = try await MenuRecognizer.recognize(image: cropped)
            onRecognized(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
