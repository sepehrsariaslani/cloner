import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
final class CloneStore: ObservableObject {
    @Published private(set) var records: [CloneRecord] = []
    @Published private(set) var isCreatingClone = false
    @Published var alertMessage: String?
    @Published var lastCreatedID: UUID?

    private let metadataURLs: [URL]
    private let cloneRoots: [URL]

    init() {
        let fileManager = FileManager.default
        let homes = Self.candidateHomeDirectories()
        let roots = homes.map {
            $0.appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Cloner", isDirectory: true)
        }
        cloneRoots = Self.uniqueURLs(roots)

        var supportDirectories = [
            CloneEngine.homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        ]
        supportDirectories.append(contentsOf: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
        supportDirectories.append(contentsOf: homes.map {
            $0.appendingPathComponent("Library/Application Support", isDirectory: true)
        })
        let metadataCandidates = Self.uniqueURLs(supportDirectories.map {
            $0.appendingPathComponent("Cloner", isDirectory: true)
                .appendingPathComponent("clones.json")
        })
        metadataURLs = metadataCandidates
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
        let fileManager = FileManager.default
        var recordsByPath: [String: CloneRecord] = [:]

        for url in metadataURLs {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([CloneRecord].self, from: data) else {
                continue
            }
            for record in decoded where fileManager.fileExists(atPath: record.clonePath) {
                let path = URL(fileURLWithPath: record.clonePath).standardizedFileURL.path
                if recordsByPath[path].map({ $0.createdAt < record.createdAt }) ?? true {
                    recordsByPath[path] = record
                }
            }
        }

        for root in cloneRoots {
            let apps = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for appURL in apps where appURL.pathExtension.lowercased() == "app" {
                let path = appURL.standardizedFileURL.path
                guard recordsByPath[path] == nil,
                      let data = try? Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")),
                      let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      let bundleIdentifier = info["CFBundleIdentifier"] as? String,
                      bundleIdentifier.hasPrefix("com.cloner.clone.") else {
                    continue
                }

                let values = try? appURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let createdAt = values?.creationDate ?? values?.contentModificationDate ?? Date()
                recordsByPath[path] = CloneRecord(
                    id: UUID(),
                    name: (info["CFBundleDisplayName"] as? String)
                        ?? (info["CFBundleName"] as? String)
                        ?? appURL.deletingPathExtension().lastPathComponent,
                    sourcePath: "",
                    clonePath: path,
                    sourceBundleIdentifier: nil,
                    bundleIdentifier: bundleIdentifier,
                    createdAt: createdAt
                )
            }
        }

        records = recordsByPath.values.sorted { $0.createdAt > $1.createdAt }
        if !records.isEmpty {
            saveRecords()
        }
    }

    private func saveRecords() {
        do {
            guard let metadataURL = metadataURLs.first else { return }
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

    private static func candidateHomeDirectories() -> [URL] {
        var candidates = [
            FileManager.default.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        ]
        if let environmentHome = ProcessInfo.processInfo.environment["HOME"], !environmentHome.isEmpty {
            candidates.append(URL(fileURLWithPath: environmentHome, isDirectory: true))
        }
        if let account = getpwuid(getuid()), let accountHome = account.pointee.pw_dir {
            candidates.append(URL(fileURLWithPath: String(cString: accountHome), isDirectory: true))
        }
        return uniqueURLs(candidates)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
