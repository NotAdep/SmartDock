import Foundation

/// Asks GitHub whether a newer release exists: shortly after launch, then once a day.
/// It only reads the public "latest release" page; nothing is sent about the user.
final class UpdateChecker {
    struct Release: Equatable {
        let version: String
        let downloadURL: URL
    }

    /// A newer release, if the last check found one.
    private(set) var available: Release?
    var onChange: (() -> Void)?

    var checksAutomatically: Bool {
        get { !defaults.bool(forKey: Self.disabledKey) }
        set {
            defaults.set(!newValue, forKey: Self.disabledKey)
            schedule()
        }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static let disabledKey = "disableUpdateChecks"
    private let endpoint = URL(string: "https://api.github.com/repos/NotAdep/SmartDock/releases/latest")!
    private let defaults = UserDefaults.standard
    private var timer: Timer?

    func start() {
        schedule()
        guard checksAutomatically else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check() }
    }

    /// Checks now. The completion gets the newer release, nil when up to date, or an error.
    func check(completion: ((Result<Release?, Error>) -> Void)? = nil) {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SmartDock/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<Release?, Error>
            if let error {
                result = .failure(error)
            } else if let data, (response as? HTTPURLResponse)?.statusCode == 200, let latest = Self.parse(data) {
                result = .success(Self.isVersion(latest.version, newerThan: Self.currentVersion) ? latest : nil)
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            DispatchQueue.main.async {
                if case .success(let release) = result, let self, release != self.available {
                    self.available = release
                    self.onChange?()
                }
                completion?(result)
            }
        }.resume()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard checksAutomatically else { return }
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reads the version and the DMG link (or the release page) from GitHub's response.
    static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.lowercased().hasSuffix(".dmg") }
        guard let link = (dmg ?? json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: version, downloadURL: link)
    }

    /// Compares dotted versions numerically, so 2.0.10 is newer than 2.0.9.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
