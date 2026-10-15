import AppKit
import Foundation
import SwiftUI

@MainActor
final class CloneStore: ObservableObject {
    @Published private(set) var records: [CloneRecord] = []
    @Published private(set) var isCreatingClone = false
    @Published var alertMessage: String?
    @Published var lastCreatedID: UUID?

    private let metadataURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Cloner", isDirectory: true)
        metadataURL = directory.appendingPathComponent("clones.json")
        loadRecords()
    }

    func createClone(from sourceURL: URL, name: String) {
        guard !isCreatingClone else { return }
        isCreatingClone = true
        alertMessage = nil

        let rootURL = CloneEngine.clonesDirectory
        Task {
            do {
                let record = try await Task.detached(priority: .userInitiated) {
                    try CloneEngine.createClone(sourceURL: sourceURL, displayName: name, in: rootURL)
                }.value
                records.insert(record, at: 0)
                lastCreatedID = record.id
                saveRecords()
            } catch {
                alertMessage = error.localizedDescription
            }
            isCreatingClone = false
        }
    }

    func open(_ record: CloneRecord) {
        guard FileManager.default.fileExists(atPath: record.clonePath) else {
            alertMessage = CloneError.cloneMissing.localizedDescription
            return
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.arguments = try CloneEngine.launchArguments(for: record)
            NSWorkspace.shared.openApplication(at: record.cloneURL, configuration: configuration) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    self.alertMessage = "macOS نتوانست clone را باز کند: \(error.localizedDescription)"
                }
            }
        } catch {
            alertMessage = "آماده‌سازی اجرای clone ناموفق بود: \(error.localizedDescription)"
        }
    }

    func moveToTrash(_ record: CloneRecord) {
        let rootPath = CloneEngine.clonesDirectory.standardizedFileURL.path + "/"
        let target = record.cloneURL.standardizedFileURL
        guard target.path.hasPrefix(rootPath) else {
            alertMessage = "مسیر این برنامه خارج از پوشهٔ مدیریت‌شدهٔ Cloner است؛ حذف لغو شد."
            return
        }
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: target, resultingItemURL: &trashedURL)
            records.removeAll { $0.id == record.id }
            saveRecords()
        } catch {
            alertMessage = "انتقال به زباله‌دان ناموفق بود: \(error.localizedDescription)"
        }
    }

    func reveal(_ record: CloneRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.cloneURL])
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([CloneRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.filter { FileManager.default.fileExists(atPath: $0.clonePath) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func saveRecords() {
        do {
            try FileManager.default.createDirectory(
                at: metadataURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            alertMessage = "ذخیرهٔ فهرست cloneها ناموفق بود: \(error.localizedDescription)"
        }
    }
}
