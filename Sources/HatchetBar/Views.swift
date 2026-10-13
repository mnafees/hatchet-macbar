import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        Group {
            if store.profiles.isEmpty { NoProfilesView() } else { MainView() }
        }
        .frame(width: 680)
    }
}

struct NoProfilesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text("No Hatchet CLI profiles found") } icon: { Image(nsImage: hatchetIcon) }.font(.headline)
            Text("HatchetBar reads tenants from the Hatchet CLI at ~/.hatchet/profiles.yaml. Add one with:")
                .font(.caption).foregroundStyle(.secondary)
            Text("hatchet profile add").font(.caption.monospaced())
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Reload") { store.reloadProfiles() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

let statuses: [(key: String, label: String, color: Color)] = [
    ("COMPLETED", "Succeeded", .green), ("RUNNING", "Running", .yellow), ("FAILED", "Failed", .red),
    ("CANCELLED", "Cancelled", .orange), ("QUEUED", "Queued", .gray),
]

func statusInfo(_ key: String) -> (label: String, color: Color) {
    statuses.first { $0.key == key }.map { ($0.label, $0.color) } ?? (key.capitalized, .secondary)
}

func fmtDuration(_ ms: Int?) -> String {
    guard let ms else { return "–" }
    if ms < 1000 { return "\(ms)ms" }
    if ms < 60_000 { return String(format: "%.2fs", Double(ms) / 1000) }
    return String(format: "%dm %ds", ms / 60_000, (ms % 60_000) / 1000)
}

func workflowName(_ displayName: String) -> String {
    guard let i = displayName.lastIndex(of: "-"), displayName[displayName.index(after: i)...].allSatisfy(\.isNumber) else { return displayName }
    return String(displayName[..<i])
}

struct MainView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                if let snap = store.snapshot {
                    ActivityChart(points: snap.points, windowHours: store.windowHours)
                    chips(snap.counts)
                    RunsTable(runs: snap.runs)
                } else if store.error == nil {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 40)
                }
            }
            .padding(14)
            Divider()
            footer
        }
    }

    private var header: some View {
        @Bindable var store = store
        return HStack(spacing: 8) {
            Picker("Profile", selection: $store.currentId) {
                ForEach(store.profiles) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden().fixedSize()
            if let env = store.snapshot?.tenant.environment {
                Text(env.lowercased()).font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            Picker("Window", selection: $store.windowHours) {
                Text("1h").tag(1); Text("6h").tag(6); Text("24h").tag(24); Text("7d").tag(168)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            if let at = store.snapshot?.at {
                Text(at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
            }
            Button { Task { await store.refresh() } } label: {
                if store.refreshing { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.plain).frame(width: 16).help("Refresh")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func chips(_ counts: [String: Int]) -> some View {
        HStack(spacing: 8) {
            ForEach(statuses, id: \.key) { s in
                Text("\(counts[s.key] ?? 0) \(s.label)")
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundStyle(s.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(s.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
        }
    }

    private var footer: some View {
        @Bindable var store = store
        return HStack {
            Button("Open Dashboard") { store.open("runs") }
            Spacer()
            Picker("Refresh", selection: $store.interval) {
                Text("5s").tag(5.0); Text("15s").tag(15.0); Text("30s").tag(30.0); Text("1m").tag(60.0); Text("5m").tag(300.0)
            }
            .labelsHidden().fixedSize().controlSize(.small)
            Menu {
                Button("Reload profiles") { store.reloadProfiles() }
                Divider()
                Button("Quit HatchetBar") { NSApp.terminate(nil) }.keyboardShortcut("q")
                if !store.diagnostics.isEmpty {
                    Divider()
                    Text(store.diagnostics)
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct ActivityChart: View {
    let points: [PointMetric]
    let windowHours: Int

    var body: some View {
        let peak = CGFloat(max(points.map { $0.SUCCEEDED + $0.FAILED }.max() ?? 0, 1))
        let labelCount = 8
        let step = max(points.count / labelCount, 1)
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let n = max(points.count, 1)
                let slot = size.width / CGFloat(n)
                let barW = max(2, slot * 0.6)
                for (i, p) in points.enumerated() {
                    let x = CGFloat(i) * slot + (slot - barW) / 2
                    var y = size.height
                    for (v, c) in [(p.SUCCEEDED, Color.green), (p.FAILED, Color.red)] where v > 0 {
                        let h = max(2, CGFloat(v) / peak * size.height)
                        y -= h
                        ctx.fill(Path(CGRect(x: x, y: y, width: barW, height: h)), with: .color(c))
                    }
                }
                ctx.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.4)))
            }
            .frame(height: 80)
            .overlay {
                if points.allSatisfy({ $0.SUCCEEDED == 0 && $0.FAILED == 0 }) {
                    Text("No task activity in this window").font(.caption).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(stride(from: 0, to: points.count, by: step)), id: \.self) { i in
                    Text(label(points[i].time)).frame(maxWidth: .infinity)
                }
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func label(_ d: Date) -> String {
        windowHours >= 48
            ? d.formatted(.dateTime.weekday(.abbreviated).hour())
            : d.formatted(date: .omitted, time: .shortened)
    }
}

struct RunsTable: View {
    @Environment(Store.self) private var store
    let runs: [Run]

    private let columns: [GridItem] = [
        .init(.flexible(minimum: 140), alignment: .leading),
        .init(.fixed(78), alignment: .leading),
        .init(.flexible(minimum: 90), alignment: .leading),
        .init(.fixed(80), alignment: .leading),
        .init(.fixed(80), alignment: .leading),
        .init(.fixed(80), alignment: .leading),
        .init(.fixed(64), alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(["Task Name", "Status", "Workflow", "Created", "Started", "Finished", "Duration"], id: \.self) {
                Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(runs) { r in
                let info = statusInfo(r.status)
                Group {
                    Text(r.displayName).lineLimit(1).truncationMode(.middle)
                    Text(info.label).font(.caption.weight(.medium)).foregroundStyle(info.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(info.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    Text(workflowName(r.displayName)).lineLimit(1).foregroundStyle(.secondary)
                    ago(r.metadata.createdAt)
                    ago(r.startedAt)
                    ago(r.finishedAt)
                    Label(fmtDuration(r.duration), systemImage: "clock").font(.caption.monospacedDigit())
                }
                .font(.callout)
                .contentShape(Rectangle())
                .onTapGesture { store.open("runs/\(r.id)") }
                .contextMenu {
                    if r.status == "QUEUED" || r.status == "RUNNING" {
                        Button("Cancel") { store.cancel(r) }
                    } else {
                        Button("Replay") { store.replay(r) }
                    }
                    Button("Open in Dashboard") { store.open("runs/\(r.id)") }
                }
                .help(r.errorMessage ?? "")
            }
        }
        if runs.isEmpty { Text("No runs in this window").font(.caption).foregroundStyle(.tertiary) }
    }

    private func ago(_ d: Date?) -> some View {
        Text(d?.formatted(.relative(presentation: .named)) ?? "N/A").font(.caption).lineLimit(1)
    }
}
