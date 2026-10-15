import Foundation

enum CloneEngine {
    static var clonesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Cloner", isDirectory: true)
    }

    static func createClone(sourceURL: URL, displayName: String, in rootURL: URL = clonesDirectory) throws -> CloneRecord {
        let fileManager = FileManager.default
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CloneError.emptyName }

        let source = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        guard source.pathExtension.lowercased() == "app" else { throw CloneError.notAnApp }

        let sourceInfoURL = source.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: sourceInfoURL.path) else { throw CloneError.missingInfoPlist }

        var sourceFormat = PropertyListSerialization.PropertyListFormat.xml
        let sourceData = try Data(contentsOf: sourceInfoURL)
        guard let sourceInfo = try PropertyListSerialization.propertyList(
            from: sourceData,
            options: [],
            format: &sourceFormat
        ) as? [String: Any] else {
            throw CloneError.invalidMetadata
        }

        guard let executable = sourceInfo["CFBundleExecutable"] as? String,
              fileManager.fileExists(atPath: source.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
            throw CloneError.missingExecutable
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let safeName = sanitizedName(name)
        let cloneURL = uniqueCloneURL(named: safeName, in: rootURL)
        guard cloneURL.standardizedFileURL.path != source.path else { throw CloneError.notAnApp }

        try fileManager.copyItem(at: source, to: cloneURL)
        var keepClone = false
        defer {
            if !keepClone {
                try? fileManager.removeItem(at: cloneURL)
            }
        }

        let newBundleIdentifier = "com.cloner.clone.\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
        var cloneInfo = sourceInfo
        cloneInfo["CFBundleIdentifier"] = newBundleIdentifier
        cloneInfo["CFBundleName"] = name
        cloneInfo["CFBundleDisplayName"] = name

        let cloneInfoData = try PropertyListSerialization.data(
            fromPropertyList: cloneInfo,
            format: sourceFormat,
            options: 0
        )
        try cloneInfoData.write(to: cloneURL.appendingPathComponent("Contents/Info.plist"), options: .atomic)

        let entitlements = try readEntitlements(from: source).map(sanitizedEntitlements)
        let temporaryEntitlements = try writeTemporaryEntitlements(entitlements)
        defer {
            if let temporaryEntitlements {
                try? fileManager.removeItem(at: temporaryEntitlements.deletingLastPathComponent())
            }
        }

        var arguments = ["--force", "--sign", "-", "--identifier", newBundleIdentifier]
        if let temporaryEntitlements {
            arguments += ["--entitlements", temporaryEntitlements.path]
        }
        arguments.append(cloneURL.path)

        let signing = try runCodeSign(arguments)
        guard signing.status == 0 else {
            throw CloneError.signingFailed(signing.message)
        }

        let verification = try runCodeSign(["--verify", "--strict", cloneURL.path])
        guard verification.status == 0 else {
            throw CloneError.verificationFailed(verification.message)
        }

        keepClone = true
        return CloneRecord(
            id: UUID(),
            name: name,
            sourcePath: source.path,
            clonePath: cloneURL.path,
            sourceBundleIdentifier: sourceInfo["CFBundleIdentifier"] as? String,
            bundleIdentifier: newBundleIdentifier,
            createdAt: Date()
        )
    }

    static func launchArguments(for record: CloneRecord) throws -> [String] {
        guard usesChromiumUserDataDirectory(record.cloneURL) else { return [] }

        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cloner", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(record.bundleIdentifier, isDirectory: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        return ["--user-data-dir=\(supportDirectory.path)"]
    }

    private static func usesChromiumUserDataDirectory(_ appURL: URL) -> Bool {
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        if FileManager.default.fileExists(atPath: resources.appendingPathComponent("app.asar").path) {
            return true
        }

        let frameworks = contents.appendingPathComponent("Frameworks", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        return names.contains { name in
            name.localizedCaseInsensitiveContains("Electron Framework") ||
            name.localizedCaseInsensitiveContains("Chromium Embedded Framework") ||
            name.localizedCaseInsensitiveContains("Codex Framework")
        }
    }

    private static func sanitizedName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let cleaned = name.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Clone" : cleaned
    }

    private static func uniqueCloneURL(named name: String, in rootURL: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = rootURL.appendingPathComponent("\(name).app", isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(name) \(index).app", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private static func readEntitlements(from appURL: URL) throws -> Data? {
        let result = try runCodeSign(["-d", "--entitlements", ":-", appURL.path])
        guard result.status == 0 else { return nil }
        let data = result.output
        guard !data.isEmpty else { return nil }

        var format = PropertyListSerialization.PropertyListFormat.xml
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) != nil else {
            throw CloneError.unsupportedEntitlements
        }
        return data
    }

    private static func sanitizedEntitlements(_ data: Data) -> Data {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var values = (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )) as? [String: Any] else {
            return data
        }

        // These values are bound to the original Team ID / App ID. Retaining them
        // on an ad-hoc signature makes macOS reject otherwise valid app copies.
        values.removeValue(forKey: "com.apple.application-identifier")
        values.removeValue(forKey: "com.apple.developer.team-identifier")
        values.removeValue(forKey: "com.apple.security.application-groups")
        values.removeValue(forKey: "keychain-access-groups")
        for key in values.keys.filter({ $0.hasPrefix("com.apple.developer.") }) {
            values.removeValue(forKey: key)
        }

        return (try? PropertyListSerialization.data(
            fromPropertyList: values,
            format: format,
            options: 0
        )) ?? data
    }

    private static func writeTemporaryEntitlements(_ data: Data?) throws -> URL? {
        guard let data else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cloner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("entitlements.plist")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func runCodeSign(_ arguments: [String]) throws -> (status: Int32, output: Data, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return (127, Data(), error.localizedDescription)
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(data: errorOutput.isEmpty ? output : errorOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "کد خروج: \(process.terminationStatus)"
        return (process.terminationStatus, output, message)
    }
}
