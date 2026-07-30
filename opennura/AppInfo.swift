import Foundation

/// App version identification, shown in the UI and written to the log.
enum AppInfo {
    static var displayVersion: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(marketing)"
    }
}
