import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct CloneSource: Identifiable {
    let id = UUID()
    let url: URL
}

struct ClonerWindow: View {
    @EnvironmentObject private var store: CloneStore
    @State private var selection: UUID?
    @State private var sourceForSheet: CloneSource?
    @State private var deleteConfirmation = false

    private var selectedRecord: CloneRecord? {
        store.records.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 580)
        .sheet(item: $sourceForSheet) { source in
            NewCloneSheet(sourceURL: source.url) { name in
                store.createClone(from: source.url, name: name)
            }
        }
        .onChange(of: store.lastCreatedID) { newID in
            if let newID { selection = newID }
        }
        .alert("خطا", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("باشه", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .confirmationDialog("این clone به زباله‌دان منتقل شود؟", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("انتقال به زباله‌دان", role: .destructive) {
                if let selectedRecord {
                    store.moveToTrash(selectedRecord)
                    selection = nil
                }
            }
            Button("انصراف", role: .cancel) {}
        } message: {
            Text("برنامهٔ اصلی حذف یا تغییر نمی‌کند.")
        }
        .overlay(alignment: .bottom) {
            if store.isCreatingClone {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("در حال کپی و امضای برنامه…")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 18)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("نمونه‌های من") {
                ForEach(store.records) { record in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: record.clonePath))
                            .resizable()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(record.sourceURL.deletingPathExtension().lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(record.id)
                    .contextMenu {
                        Button("بازکردن", systemImage: "arrow.up.forward.app") { store.open(record) }
                        Button("نمایش در Finder", systemImage: "folder") { store.reveal(record) }
                        Divider()
                        Button("انتقال به زباله‌دان", systemImage: "trash", role: .destructive) {
                            selection = record.id
                            deleteConfirmation = true
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cloner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: chooseSourceApp) {
                    Label("ساخت clone", systemImage: "plus")
                }
                .help("یک برنامهٔ macOS انتخاب کن")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedRecord {
            cloneDetails(selectedRecord)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text("هنوز cloneای نداری")
                    .font(.title2.weight(.semibold))
                Text("از یک برنامهٔ مک نمونهٔ جدا بساز تا مستقل بازش کنی.")
                    .foregroundStyle(.secondary)
                Button("انتخاب برنامه") { chooseSourceApp() }
                    .buttonStyle(.borderedProminent)
            }
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cloneDetails(_ record: CloneRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: record.clonePath))
                        .resizable()
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.name).font(.largeTitle.weight(.semibold))
                        Label("نمونهٔ جداگانه", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button {
                        store.open(record)
                    } label: {
                        Label("بازکردن", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        store.reveal(record)
                    } label: {
                        Label("نمایش در Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .destructive) {
                        deleteConfirmation = true
                    } label: {
                        Label("حذف clone", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 0) {
                    detailRow("برنامهٔ اصلی", value: record.sourcePath)
                    Divider()
                    detailRow("مسیر clone", value: record.clonePath)
                    Divider()
                    detailRow("Bundle ID جدید", value: record.bundleIdentifier)
                    Divider()
                    detailRow("ساخته‌شده", value: record.createdAt.formatted(date: .long, time: .shortened))
                }
                .padding(.horizontal, 16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

                Label("برنامهٔ اصلی دست‌نخورده می‌ماند. بعضی برنامه‌ها به‌دلیل محدودیت امضا یا حساب کاربری ممکن است در clone درست کار نکنند.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(record.name)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
    }

    private func chooseSourceApp() {
        let panel = NSOpenPanel()
        panel.title = "انتخاب برنامه برای clone"
        panel.prompt = "انتخاب برنامه"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            sourceForSheet = CloneSource(url: url)
        }
    }
}

private struct NewCloneSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceURL: URL
    let onCreate: (String) -> Void
    @State private var name: String

    init(sourceURL: URL, onCreate: @escaping (String) -> Void) {
        self.sourceURL = sourceURL
        self.onCreate = onCreate
        _name = State(initialValue: "\(sourceURL.deletingPathExtension().lastPathComponent) Copy")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ساخت clone جدید")
                    .font(.title2.weight(.semibold))
                Text("برنامه کپی می‌شود و Bundle ID جدا می‌گیرد.")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("برنامه") {
                Text(sourceURL.lastPathComponent)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            TextField("نام clone", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            HStack {
                Text("ذخیره در ~/Applications/Cloner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("انصراف", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("ساخت clone", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func create() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        onCreate(cleanName)
        dismiss()
    }
}
