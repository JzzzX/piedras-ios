import Foundation
import Observation

struct FolderSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let isDefault: Bool
    let isRecentlyDeleted: Bool

    var displayName: String {
        if isDefault {
            return AppStrings.current.defaultFolderName
        }
        if isRecentlyDeleted {
            return AppStrings.current.recentlyDeletedFolderName
        }
        return name
    }
}

@MainActor
@Observable
final class FolderStore {
    private let apiClient: APIClient
    private let settingsStore: SettingsStore
    private var didLoad = false

    var folders: [FolderSummary] = []
    var draftFolderName = ""
    var isLoading = false
    var isCreating = false
    var isDeleting = false
    var lastErrorMessage: String?

    init(apiClient: APIClient, settingsStore: SettingsStore) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
    }

    var activeFolderID: String? {
        settingsStore.activeCollectionID
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await loadFolders()
    }

    func ensureSystemFoldersReady() async -> Bool {
        if settingsStore.defaultCollectionID != nil,
           settingsStore.recentlyDeletedCollectionID != nil {
            return true
        }

        await loadFolders()

        return settingsStore.defaultCollectionID != nil
            && settingsStore.recentlyDeletedCollectionID != nil
    }

    func loadFolders() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteCollections = try await apiClient.listCollections()
            applyRemoteCollections(remoteCollections)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func createFolder() async -> Bool {
        let trimmedName = draftFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastErrorMessage = AppStrings.current.newFolderNameRequired
            return false
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let createdCollection = try await apiClient.createCollection(.init(name: trimmedName))
            lastErrorMessage = nil
            draftFolderName = ""
            applyCreatedCollection(createdCollection)
            selectFolder(id: createdCollection.id)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func deleteFolder(id: String) async -> Bool {
        guard let folder = folders.first(where: { $0.id == id }) else {
            lastErrorMessage = "文件夹不存在。"
            return false
        }

        guard !folder.isDefault, !folder.isRecentlyDeleted else {
            lastErrorMessage = "系统文件夹不能删除。"
            return false
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await apiClient.deleteCollection(id: id)
            await loadFolders()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func selectFolder(id: String) {
        guard folders.contains(where: { $0.id == id }) else { return }
        settingsStore.selectedCollectionID = id
        lastErrorMessage = nil
    }

    func reset() {
        folders = []
        draftFolderName = ""
        isLoading = false
        isCreating = false
        isDeleting = false
        lastErrorMessage = nil
        didLoad = false
        settingsStore.defaultCollectionID = nil
        settingsStore.recentlyDeletedCollectionID = nil
        settingsStore.selectedCollectionID = nil
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func seedPreviewFolders(defaultID: String = "preview-notes") {
        folders = [
            FolderSummary(id: defaultID, name: "Default Folder", isDefault: true, isRecentlyDeleted: false),
            FolderSummary(id: "preview-archive", name: "项目归档", isDefault: false, isRecentlyDeleted: false),
            FolderSummary(id: "preview-recently-deleted", name: "Recently Deleted", isDefault: false, isRecentlyDeleted: true)
        ]
        settingsStore.defaultCollectionID = defaultID
        settingsStore.recentlyDeletedCollectionID = "preview-recently-deleted"
        settingsStore.selectedCollectionID = defaultID
        lastErrorMessage = nil
        didLoad = true
    }

    private func applyRemoteCollections(_ remoteCollections: [RemoteCollection]) {
        let normalizedFolders = remoteCollections.map {
            FolderSummary(id: $0.id, name: $0.name, isDefault: $0.isDefault, isRecentlyDeleted: $0.isRecentlyDeleted ?? false)
        }

        folders = normalizedFolders
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isDefault != rhs.element.isDefault {
                    return lhs.element.isDefault && !rhs.element.isDefault
                }
                if lhs.element.isRecentlyDeleted != rhs.element.isRecentlyDeleted {
                    return !lhs.element.isRecentlyDeleted && rhs.element.isRecentlyDeleted
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        let defaultFolderID = folders.first(where: \.isDefault)?.id
        let recentlyDeletedFolderID = folders.first(where: \.isRecentlyDeleted)?.id
        settingsStore.defaultCollectionID = defaultFolderID
        settingsStore.recentlyDeletedCollectionID = recentlyDeletedFolderID

        if let selectedCollectionID = settingsStore.selectedCollectionID,
           folders.contains(where: { $0.id == selectedCollectionID }) {
            return
        }

        settingsStore.selectedCollectionID = defaultFolderID
    }

    private func applyCreatedCollection(_ remoteCollection: RemoteCollection) {
        folders.removeAll(where: { $0.id == remoteCollection.id })
        folders.append(
            FolderSummary(
                id: remoteCollection.id,
                name: remoteCollection.name,
                isDefault: remoteCollection.isDefault,
                isRecentlyDeleted: remoteCollection.isRecentlyDeleted ?? false
            )
        )
        if let defaultIndex = folders.firstIndex(where: \.isDefault), defaultIndex != 0 {
            let defaultFolder = folders.remove(at: defaultIndex)
            folders.insert(defaultFolder, at: 0)
        }
        if let recentlyDeletedIndex = folders.firstIndex(where: \.isRecentlyDeleted),
           recentlyDeletedIndex != folders.count - 1 {
            let recentlyDeletedFolder = folders.remove(at: recentlyDeletedIndex)
            folders.append(recentlyDeletedFolder)
        }
    }
}
