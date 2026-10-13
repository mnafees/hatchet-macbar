import AppKit
import Foundation
import Observation

@Observable @MainActor
final class Store {
    struct Snapshot {
        var tenant: Tenant
        var counts: [String: Int]
        var points: [PointMetric]
        var runs: [Run]
        var at: Date
    }

    private(set) var profiles: [Profile] = []
    var currentId: String? {
        didSet {
            guard oldValue != currentId else { return }
            UserDefaults.standard.set(currentId, forKey: "current")
            snapshot = nil
            error = nil
            Task { await refresh() }
        }
    }
    var snapshot: Snapshot?
    var error: String?
    var diagnostics = ""
    var refreshing = false
    var interval: Double = UserDefaults.standard.object(forKey: "interval") as? Double ?? 30 {
        didSet { UserDefaults.standard.set(interval, forKey: "interval"); startTimer() }
    }
    var windowHours: Int = UserDefaults.standard.object(forKey: "window") as? Int ?? 24 {
        didSet { UserDefaults.standard.set(windowHours, forKey: "window"); Task { await refresh() } }
    }
    private var timer: Task<Void, Never>?

    init() {
        reloadProfiles()
        startTimer()
        Task { await refresh() }
    }

    var current: Profile? { profiles.first { $0.id == currentId } }
    private var client: Client? { current.map(Client.init) }

    func reloadProfiles() {
        let (loaded, defaultName) = loadProfiles()
        profiles = loaded
        if !profiles.contains(where: { $0.id == currentId }) {
            let saved = UserDefaults.standard.string(forKey: "current")
            currentId = [saved, defaultName].compactMap { $0 }.first { id in profiles.contains { $0.id == id } } ?? profiles.first?.id
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.interval ?? 30))
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        reloadProfiles()
        guard let client else { return }
        refreshing = true
        defer { refreshing = false }
        let since = Date().addingTimeInterval(-Double(windowHours) * 3600)
        do {
            async let tenant = client.tenant()
            async let metrics = client.statusMetrics(since: since)
            async let points = client.pointMetrics(since: since)
            async let runs = client.runs(since: since, limit: 15)
            let counts = Dictionary(try await metrics.map { ($0.status, $0.count) }, uniquingKeysWith: +)
            let snap = Snapshot(tenant: try await tenant, counts: counts, points: try await points, runs: try await runs, at: .now)
            guard client.profile.id == currentId else { return }
            snapshot = snap
            error = nil
            diagnostics = "\(client.serverURL.host() ?? "?") · metrics \(counts.values.reduce(0, +)) · points \(snap.points.count) · runs \(snap.runs.count)"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func act(_ op: @escaping (Client) async throws -> Void) {
        guard let client else { return }
        Task {
            do { try await op(client); await refresh() } catch { self.error = error.localizedDescription }
        }
    }

    func cancel(_ r: Run) { act { try await $0.cancel([r.id]) } }
    func replay(_ r: Run) { act { try await $0.replay([r.id]) } }

    func open(_ path: String) {
        guard let client else { return }
        NSWorkspace.shared.open(client.serverURL.appending(path: "tenants/\(client.tenantId)/" + path))
    }
}
