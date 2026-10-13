import SwiftUI

/// A small schematic thumbnail of a route, drawn from its points.
///
/// This is a shape preview (like a route silhouette), not a map tile render: it
/// needs no network and no map snapshots, so it is cheap and deterministic. The
/// aspect ratio is preserved, with longitude compressed by latitude so a route
/// in high latitudes is not stretched east-west.
struct RouteThumbnail: View {
    let points: [TrackPoint]

    var body: some View {
        Canvas { context, size in
            let path = routePath(in: size)
            guard !path.isEmpty else { return }
            context.stroke(path,
                           with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 44, height: 44)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private func routePath(in size: CGSize) -> Path {
        guard points.count > 1 else { return Path() }

        let latitudes = points.map { $0.latitude }
        let longitudes = points.map { $0.longitude }
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return Path()
        }

        let inset: CGFloat = 5
        let availableWidth = max(size.width - inset * 2, 1)
        let availableHeight = max(size.height - inset * 2, 1)

        let midLatitude = (minLat + maxLat) / 2 * .pi / 180
        let longitudeScale = max(cos(midLatitude), 0.1)
        let spanX = max((maxLon - minLon) * longitudeScale, 1e-9)
        let spanY = max(maxLat - minLat, 1e-9)
        let scale = min(availableWidth / spanX, availableHeight / spanY)

        let drawnWidth = spanX * scale
        let drawnHeight = spanY * scale
        let originX = inset + (availableWidth - drawnWidth) / 2
        let originY = inset + (availableHeight - drawnHeight) / 2

        func project(_ point: TrackPoint) -> CGPoint {
            CGPoint(x: originX + CGFloat((point.longitude - minLon) * longitudeScale * scale),
                    y: originY + CGFloat((maxLat - point.latitude) * scale))
        }

        var path = Path()
        path.move(to: project(points[0]))
        for point in points.dropFirst() {
            path.addLine(to: project(point))
        }
        return path
    }
}
