import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    private let appGroupIdentifier = "group.sun.Munecting"
    private let queueKey = "pendingPlaylistLinks"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Munecting에 추가"
        placeholder = "플레이리스트를 내 믹스에 추가합니다."
    }

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        Task { @MainActor in
            do {
                guard let sharedContent = try await firstSharedContent() else {
                    throw ShareImportError.missingURL
                }
                try enqueue(sharedContent)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                let alert = UIAlertController(title: "가져올 수 없어요", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "확인", style: .default))
                present(alert, animated: true)
            }
        }
    }

    override func configurationItems() -> [Any]! { [] }

    private func firstSharedContent() async throws -> SharedContent? {
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let suppliedTitle = inputItems.lazy.compactMap { $0.attributedTitle?.string }.first
        let providers = inputItems.flatMap { $0.attachments ?? [] }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                if let url = item as? URL {
                    return SharedContent(url: url, title: suppliedTitle ?? provider.suggestedName, message: normalized(contentText))
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                if let text = item as? String,
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return SharedContent(url: url, title: suppliedTitle ?? provider.suggestedName, message: normalized(contentText))
                }
            }
        }
        return nil
    }

    private func enqueue(_ content: SharedContent) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw ShareImportError.appGroupUnavailable
        }
        var queue: [QueuedLink] = []
        if let data = defaults.data(forKey: queueKey) {
            queue = (try? JSONDecoder().decode([QueuedLink].self, from: data)) ?? []
        }
        queue.append(QueuedLink(id: UUID(), url: content.url, sharedAt: .now, title: normalized(content.title), message: content.message))
        defaults.set(try JSONEncoder().encode(queue), forKey: queueKey)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct QueuedLink: Codable {
    let id: UUID
    let url: URL
    let sharedAt: Date
    let title: String?
    let message: String?
}

private struct SharedContent {
    let url: URL
    let title: String?
    let message: String?
}

private enum ShareImportError: LocalizedError {
    case missingURL
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .missingURL: "공유 항목에서 플레이리스트 링크를 찾지 못했습니다."
        case .appGroupUnavailable: "Munecting 공유 저장소에 접근할 수 없습니다."
        }
    }
}
