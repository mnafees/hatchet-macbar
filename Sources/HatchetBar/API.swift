import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Profile: Identifiable, Hashable {
    let id: String
    let name: String
    let tenantId: String
    let serverURL: URL
    let token: String
}

struct Meta: Decodable {
    let id: String
    let createdAt: Date
}

struct Tenant: Decodable {
    let metadata: Meta
    let name: String
    let slug: String
    let environment: String?
    let region: String?
}

struct Run: Decodable, Identifiable {
    let metadata: Meta
    let displayName: String
    let status: String
    let startedAt: Date?
    let finishedAt: Date?
    let duration: Int?
    let errorMessage: String?
    var id: String { metadata.id }
}

struct RunList: Decodable { let rows: [Run] }

struct StatusMetric: Decodable {
    let status: String
    let count: Int
}

struct PointMetric: Decodable {
    let time: Date
    let SUCCEEDED: Int
    let FAILED: Int
}

struct PointMetrics: Decodable { let results: [PointMetric]? }

private struct APIErrors: Decodable {
    struct E: Decodable { let description: String }
    let errors: [E]
}

private struct Ignore: Decodable {}

struct Client {
    let profile: Profile
    var token: String { profile.token }
    var tenantId: String { profile.tenantId }
    var serverURL: URL { profile.serverURL }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            var s = try dec.singleValueContainer().decode(String.self)
            if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
                s.replaceSubrange(r, with: "." + (s[r].dropFirst() + "000").prefix(3))
            }
            if let date = iso.date(from: s) ?? isoPlain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    private func call<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil) async throws -> T {
        var comps = URLComponents(url: serverURL.appending(path: "api/v1" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? Self.decoder.decode(APIErrors.self, from: data))?.errors.first?.description
            throw APIError(message: detail ?? "HTTP \(code) on \(path)")
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch let e as DecodingError {
            let (ctx, what): (DecodingError.Context, String) = switch e {
            case .typeMismatch(let t, let c): (c, "expected \(t)")
            case .valueNotFound(let t, let c): (c, "missing \(t)")
            case .keyNotFound(let k, let c): (c, "missing key \(k.stringValue)")
            case .dataCorrupted(let c): (c, "bad value")
            @unknown default: fatalError()
            }
            let field = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            throw APIError(message: "\(path): \(what) at \(field.isEmpty ? "root" : field) (\(ctx.debugDescription))")
        }
    }

    private func stamp(_ d: Date) -> String { Self.isoPlain.string(from: d) }

    func tenant() async throws -> Tenant {
        try await call("GET", "/tenants/\(tenantId)")
    }

    func statusMetrics(since: Date) async throws -> [StatusMetric] {
        try await call("GET", "/stable/tenants/\(tenantId)/task-metrics", query: ["since": stamp(since)])
    }

    func pointMetrics(since: Date) async throws -> [PointMetric] {
        let r: PointMetrics = try await call("GET", "/stable/tenants/\(tenantId)/task-point-metrics", query: ["createdAfter": stamp(since)])
        return r.results ?? []
    }

    func runs(since: Date, limit: Int) async throws -> [Run] {
        let r: RunList = try await call("GET", "/stable/tenants/\(tenantId)/workflow-runs", query: ["since": stamp(since), "limit": String(limit), "only_tasks": "false"])
        return r.rows
    }

    func cancel(_ ids: [String]) async throws {
        let _: Ignore = try await call("POST", "/stable/tenants/\(tenantId)/tasks/cancel", body: ["externalIds": ids])
    }

    func replay(_ ids: [String]) async throws {
        let _: Ignore = try await call("POST", "/stable/tenants/\(tenantId)/tasks/replay", body: ["externalIds": ids])
    }
}
