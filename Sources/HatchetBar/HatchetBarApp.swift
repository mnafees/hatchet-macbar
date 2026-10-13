import SwiftUI

@main
struct HatchetBarApp: App {
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            RootView().environment(store)
        } label: {
            Image(nsImage: hatchetIcon)
            if store.error != nil {
                Text("!")
            } else if let points = store.snapshot?.points, points.contains(where: { $0.SUCCEEDED > 0 || $0.FAILED > 0 }) {
                Image(nsImage: sparkline(points))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

func sparkline(_ points: [PointMetric]) -> NSImage {
    let last = Array(points.suffix(20))
    let slot: CGFloat = 2.5
    let size = NSSize(width: CGFloat(last.count) * slot, height: 16)
    let maxOk = CGFloat(max(last.map(\.SUCCEEDED).max() ?? 0, 1))
    let maxFail = CGFloat(max(last.map(\.FAILED).max() ?? 0, 1))
    let img = NSImage(size: size, flipped: true) { _ in
        let mid = size.height / 2
        for (i, p) in last.enumerated() {
            let x = CGFloat(i) * slot
            NSColor.black.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: 1.5, height: size.height), xRadius: 0.75, yRadius: 0.75).fill()
            if p.SUCCEEDED > 0 {
                let h = max(1.5, CGFloat(p.SUCCEEDED) / maxOk * (mid - 1))
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: mid - h, width: 1.5, height: h), xRadius: 0.75, yRadius: 0.75).fill()
            }
            if p.FAILED > 0 {
                let h = max(1.5, CGFloat(p.FAILED) / maxFail * (mid - 1))
                NSColor.black.withAlphaComponent(0.55).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: mid, width: 1.5, height: h), xRadius: 0.75, yRadius: 0.75).fill()
            }
        }
        return true
    }
    img.isTemplate = true
    return img
}

let hatchetIcon: NSImage = {
    let img = NSImage(contentsOf: Bundle.module.url(forResource: "hatchet", withExtension: "svg")!)!
    img.size = NSSize(width: 18, height: 18)
    img.isTemplate = true
    return img
}()
