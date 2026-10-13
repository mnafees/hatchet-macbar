import Foundation

let profilesPath = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".hatchet/profiles.yaml")
let defaultCloudURL = URL(string: "https://cloud.hatchet.run")!

func loadProfiles() -> (profiles: [Profile], defaultName: String?) {
    guard let text = try? String(contentsOf: profilesPath, encoding: .utf8) else { return ([], nil) }
    let root = parseYAML(text)
    let entries = (root["profiles"] as? [String: Any]) ?? [:]
    let profiles = entries.compactMap { key, raw -> Profile? in
        guard let p = raw as? [String: Any], let tenantId = p["tenantid"] as? String, let token = p["token"] as? String else { return nil }
        var url = (p["apiserverurl"] as? String).flatMap(URL.init(string:)) ?? defaultCloudURL
        if url.host() == "cloud.onhatchet.run" { url = defaultCloudURL }
        return Profile(id: key, name: (p["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key, tenantId: tenantId, serverURL: url, token: token)
    }
    return (profiles.sorted { $0.name < $1.name }, root["defaultprofile"] as? String)
}

// ponytail: minimal block-mapping YAML reader, enough for viper's profiles.yaml; swap for a real parser if lists or multi-line values ever appear
func parseYAML(_ text: String) -> [String: Any] {
    var root: [String: Any] = [:]
    var stack: [(indent: Int, path: [String])] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.replacingOccurrences(of: "\t", with: "    ")
        let indent = line.prefix { $0 == " " }.count
        let content = line.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty, !content.hasPrefix("#"), let colon = content.firstIndex(of: ":") else { continue }
        let key = content[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        var value = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q { value = String(value.dropFirst().dropLast()) }
        while let last = stack.last, last.indent >= indent { stack.removeLast() }
        let path = (stack.last?.path ?? []) + [key]
        if value.isEmpty {
            set(&root, path[...], [String: Any]())
            stack.append((indent, path))
        } else {
            set(&root, path[...], value)
        }
    }
    return root
}

private func set(_ dict: inout [String: Any], _ path: ArraySlice<String>, _ value: Any) {
    guard let head = path.first else { return }
    if path.count == 1 { dict[head] = value; return }
    var child = (dict[head] as? [String: Any]) ?? [:]
    set(&child, path.dropFirst(), value)
    dict[head] = child
}
