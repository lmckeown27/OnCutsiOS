//
//  DiscoverServiceAreasMap.swift
//  OnCuts
//
//  MapKit service-area circles for Discover (fixed ~0.4 km blobs + optional browse radius).
//

import MapKit
import SwiftUI

#if os(iOS)

struct DiscoverServiceAreasMap: View {
    let areas: [DiscoverServiceArea]
    @Binding var selectedAreaId: String?
    /// Browse search radius (meters) centered on the user’s browse point when distance filter is on.
    var browseCenter: CLLocationCoordinate2D?
    var browseRadiusMeters: CLLocationDistance?

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var selectedArea: DiscoverServiceArea? {
        guard let selectedAreaId else { return nil }
        return areas.first(where: { $0.id == selectedAreaId })
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(areas) { area in
                let coordinate = CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude)
                let isSelected = area.id == selectedAreaId
                MapCircle(center: coordinate, radius: MyBarbersDiscover.mapAreaRadiusMeters)
                    .foregroundStyle(isSelected ? Color.oliveGreen.opacity(0.38) : Color.black.opacity(0.28))
                    .stroke(isSelected ? Color.oliveGreen : Color.black.opacity(0.85), lineWidth: isSelected ? 2.5 : 1.5)
            }

            if let browseCenter, let browseRadiusMeters, browseRadiusMeters > 0 {
                MapCircle(center: browseCenter, radius: browseRadiusMeters)
                    .foregroundStyle(Color.clear)
                    .stroke(
                        Color.oliveGreen.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // Tap targets for area selection (MapCircle is not tappable in all OS versions).
            GeometryReader { geo in
                ForEach(areas) { area in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedAreaId == area.id {
                                selectedAreaId = nil
                            } else {
                                selectedAreaId = area.id
                            }
                        }
                    } label: {
                        Circle()
                            .fill(Color.black.opacity(0.001))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .position(approxScreenPoint(for: area, in: geo.size))
                    .accessibilityLabel(area.title)
                }
            }
        }
        .onAppear {
            fitCamera()
        }
        .onChange(of: areas.map(\.id)) { _, _ in
            fitCamera()
        }
        .onChange(of: selectedAreaId) { _, _ in
            if let selectedArea {
                withAnimation(.easeInOut(duration: 0.25)) {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(
                                latitude: selectedArea.latitude,
                                longitude: selectedArea.longitude
                            ),
                            latitudinalMeters: 2_400,
                            longitudinalMeters: 2_400
                        )
                    )
                }
            }
        }
    }

    /// Approximate pin placement for hit targets when the map is roughly fitted to all areas.
    private func approxScreenPoint(for area: DiscoverServiceArea, in size: CGSize) -> CGPoint {
        guard let region = fittedRegion(),
              region.span.latitudeDelta > 0,
              region.span.longitudeDelta > 0
        else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let x = (area.longitude - (region.center.longitude - region.span.longitudeDelta / 2))
            / region.span.longitudeDelta
        let y = ((region.center.latitude + region.span.latitudeDelta / 2) - area.latitude)
            / region.span.latitudeDelta
        return CGPoint(
            x: min(size.width - 22, max(22, x * size.width)),
            y: min(size.height - 22, max(22, y * size.height))
        )
    }

    private func fittedRegion() -> MKCoordinateRegion? {
        if let selectedArea {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: selectedArea.latitude, longitude: selectedArea.longitude),
                latitudinalMeters: 2_400,
                longitudinalMeters: 2_400
            )
        }
        guard !areas.isEmpty else {
            if let browseCenter {
                return MKCoordinateRegion(center: browseCenter, latitudinalMeters: 8_000, longitudinalMeters: 8_000)
            }
            return nil
        }
        let lats = areas.map(\.latitude)
        let lngs = areas.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max()
        else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let latDelta = max(0.04, (maxLat - minLat) * 1.6)
        let lngDelta = max(0.04, (maxLng - minLng) * 1.6)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
    }

    private func fitCamera() {
        guard let region = fittedRegion() else {
            cameraPosition = .automatic
            return
        }
        cameraPosition = .region(region)
    }
}

#else

struct DiscoverServiceAreasMap: View {
    let areas: [DiscoverServiceArea]
    @Binding var selectedAreaId: String?
    var browseCenter: CLLocationCoordinate2D? = nil
    var browseRadiusMeters: CLLocationDistance? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.neutral200)
            .overlay {
                Text(areas.isEmpty ? "Map" : "\(areas.count) areas")
                    .font(OnCutsFont.caption)
                    .foregroundStyle(Color.neutral500)
            }
    }
}

#endif
