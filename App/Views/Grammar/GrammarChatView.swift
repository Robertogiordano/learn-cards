import LearnCore
import PhotosUI
import SwiftUI

/// Ask the tutor about a pill. The conversation is saved with the pill; each question sends
/// the lesson summary and only the latest turns, so it stays cheap.
struct GrammarChatView: View {
    let pillID: UUID
    /// Opened from the lesson: shows a Close button instead of relying on the back button.
    var isSheet = false

    @ObservedObject private var store = GrammarPillStore.shared

    var body: some View {
        if let pill = store.pill(pillID) {
            TutorChatView(chat: chat(for: pill), isSheet: isSheet)
        } else {
            ContentUnavailableView("Pill deleted", systemImage: "trash")
                .navigationTitle("Ask the tutor")
        }
    }

    private func chat(for pill: GrammarPill) -> TutorChat {
        let pillID = pill.id
        return TutorChat(
            intro: "Ask anything about \(pill.lesson.title), in Italian or English. Tap the camera to send a page of your book.",
            suggestions: GrammarChatPrompt.suggestions(for: pill),
            messages: pill.chat,
            allowsPhotos: true,
            clearMessage: "The questions and answers about this pill are removed.",
            append: { message in GrammarPillStore.shared.update(pillID) { $0.chat.append(message) } },
            clear: {
                let store = GrammarPillStore.shared
                GrammarChatImageStore.delete(store.pill(pillID)?.chat.compactMap(\.imageName) ?? [])
                store.update(pillID) { $0.chat = [] }
            },
            answer: { key, history in
                guard let pill = GrammarPillStore.shared.pill(pillID) else { throw CancellationError() }
                return try await OpenRouterClient(apiKey: key, model: OpenRouterModels.grammarModel())
                    .grammarChat(pill: pill, history: history)
            }
        )
    }
}

/// What a tutor chat is about: its messages, where they are kept and how answers are asked for.
struct TutorChat {
    var intro: String
    /// Ready-made questions, shown while the chat is empty.
    var suggestions: [String]
    var messages: [GrammarChatMessage]
    /// Whether the learner can send a photo with a question.
    var allowsPhotos: Bool
    /// What "Clear chat" removes, for its confirmation.
    var clearMessage: String
    var append: (GrammarChatMessage) -> Void
    var clear: () -> Void
    /// The tutor's answer to the conversation so far, with the OpenRouter key.
    var answer: (_ key: String, _ history: [GrammarChatMessage]) async throws -> String
}

/// A chat with the tutor: bubbles, ready-made questions, an optional photo and the input bar.
struct TutorChatView: View {
    let chat: TutorChat
    /// Opened as a sheet: shows a Close button instead of relying on the back button.
    var isSheet = false

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isWaiting = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false
    @FocusState private var isFocused: Bool
    /// Photo waiting to be sent with the next question.
    @State private var pendingImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsCamera = false

    var body: some View {
        conversation
            .navigationTitle("Ask the tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Clear chat", systemImage: "trash", role: .destructive) { confirmsClear = true }
                            .disabled(chat.messages.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    defer { pickerItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        pendingImage = image
                    } else {
                        errorMessage = "Could not read the image."
                    }
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in pendingImage = image }
                    .ignoresSafeArea()
            }
            .confirmationDialog("Clear this chat?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { chat.clear() }
            } message: {
                Text(chat.clearMessage)
            }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    intro
                    ForEach(chat.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if isWaiting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .id("waiting")
                    }
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                            Button("Try again") { send(nil) }
                                .buttonStyle(.bordered)
                        }
                        .id("error")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChange(of: chat.messages.count) { _, _ in scrollToEnd(proxy, animated: true) }
            .onChange(of: isWaiting) { _, waiting in
                if waiting { withAnimation { proxy.scrollTo("waiting", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(chat.intro, systemImage: "bubble.left.and.text.bubble.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if chat.messages.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chat.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { send(suggestion) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isWaiting)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func bubble(_ message: GrammarChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let name = message.imageName {
                    ChatPhoto(name: name)
                }
                if !message.text.isEmpty {
                    markdownText(message.text)
                        .textSelection(.enabled)
                        .padding(12)
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .background(isUser ? Color.purple : Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var canSend: Bool { (!draft.trimmed.isEmpty || pendingImage != nil) && !isWaiting }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pendingImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: pendingImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        self.pendingImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .padding(3)
                    .accessibilityLabel("Remove photo")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                if chat.allowsPhotos {
                    Menu {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take a photo", systemImage: "camera") { showsCamera = true }
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose from library", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "camera.circle").font(.system(size: 32))
                    }
                    .disabled(isWaiting)
                    .accessibilityLabel("Add a photo")
                }
                messageField
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var messageField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Your question", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit { if canSend { send(draft) } }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = chat.messages.last?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    /// Sends a new question, or asks again for the last unanswered one when `text` is nil.
    private func send(_ text: String?) {
        guard !isWaiting else { return }
        var history = chat.messages
        if let question = text?.trimmed, !question.isEmpty || pendingImage != nil {
            var imageName: String?
            if let pendingImage {
                // Big enough to read a book page, small enough to keep the request cheap.
                guard let jpeg = ImagePreprocessor.jpegData(from: pendingImage, maxDimension: 1600, quality: 0.7),
                      let name = try? GrammarChatImageStore.save(jpeg) else {
                    errorMessage = "Could not prepare the photo."
                    return
                }
                imageName = name
            }
            let message = GrammarChatMessage(role: .user, text: question, imageName: imageName)
            chat.append(message)
            history.append(message)
            draft = ""
            pendingImage = nil
        }
        guard history.last?.role == .user else { return }
        // The question stays in the chat, so Try again works once the key is set.
        guard let key = Secrets.openRouterKey else {
            errorMessage = OpenRouterClient.ClientError.missingAPIKey.localizedDescription
            return
        }
        isWaiting = true
        errorMessage = nil
        let answer = chat.answer
        let append = chat.append
        Task { @MainActor in
            defer { isWaiting = false }
            do {
                let text = try await answer(key, history)
                append(GrammarChatMessage(role: .assistant, text: text.trimmed))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A photo sent in the chat; tap to see it full screen.
private struct ChatPhoto: View {
    let name: String

    @State private var showsFull = false

    var body: some View {
        if let data = GrammarChatImageStore.data(name), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture { showsFull = true }
                .fullScreenCover(isPresented: $showsFull) {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Button {
                            showsFull = false
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.largeTitle)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .white.opacity(0.3))
                        }
                        .padding()
                        .accessibilityLabel("Close")
                    }
                }
        } else {
            Label("Photo not available", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
