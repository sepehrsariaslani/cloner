import Foundation

struct CloneRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sourcePath: String
    let clonePath: String
    let sourceBundleIdentifier: String?
    let bundleIdentifier: String
    let createdAt: Date

    var cloneURL: URL { URL(fileURLWithPath: clonePath) }
    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
}

enum CloneError: LocalizedError {
    case notAnApp
    case missingInfoPlist
    case missingExecutable
    case invalidMetadata
    case emptyName
    case unsupportedEntitlements
    case signingFailed(String)
    case verificationFailed(String)
    case cloneMissing

    var errorDescription: String? {
        switch self {
        case .notAnApp:
            return "پوشهٔ انتخاب‌شده یک برنامهٔ macOS با پسوند .app نیست."
        case .missingInfoPlist:
            return "فایل Contents/Info.plist در برنامه پیدا نشد."
        case .missingExecutable:
            return "فایل اجرایی اصلی برنامه پیدا نشد."
        case .invalidMetadata:
            return "اطلاعات bundle قابل‌خواندن یا ویرایش نیست."
        case .emptyName:
            return "برای نمونه یک نام انتخاب کن."
        case .unsupportedEntitlements:
            return "Entitlements امضای منبع قابل‌خواندن نیست؛ برای جلوگیری از ساخت clone ناقص، عملیات متوقف شد."
        case .signingFailed(let message):
            return "امضای clone انجام نشد: \(message)"
        case .verificationFailed(let message):
            return "بررسی امضای clone ناموفق بود: \(message)"
        case .cloneMissing:
            return "فایل clone پیدا نشد."
        }
    }
}
