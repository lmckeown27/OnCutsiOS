//
//  DiscoverServiceAreasMap.swift
//  OnCuts
//
//  MapKit Discover map: the utility-pill miles radius is the framed map radius.
//  Pill changes reframe the camera; pinch-zoom updates the pill miles to match.
//

import MapKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)

struct DiscoverServiceAreasMap: View {
    let areas: [DiscoverServiceArea]
    @Binding var selectedAreaId: String?
    /// Browse center (device or manual place from the utility pill).
    var browseCenter: CLLocationCoordinate2D?
    /// Search radius in meters from the utility-pill miles setting (e.g. 25 mi → ~40_233 m).
    var browseRadiusMeters: CLLocationDistance?
    /// When true, map draws edge-to-edge (no rounded clip).
    var fillsScreen: Bool = false
    /// Fired when the user selects an operator area (including re-tapping the same one).
    var onAreaSelected: (() -> Void)? = nil
    /// Visible map region as the user pans/zooms — drives the pull-up operator list.
    var onVisibleRegionChange: ((MKCoordinateRegion) -> Void)? = nil
    /// When the user pinches the map, report the new visible radius in miles so the utility pill stays linked.
    var onVisibleRadiusMilesChange: ((Double) -> Void)? = nil
    /// Operators drawn as a general area, not an exact pin.
    var operators: [ServiceProvider] = []
    /// Darker area: closest operator, or the one the client last featured.
    var featuredOperatorId: String? = nil
    var onOperatorTap: ((ServiceProvider) -> Void)? = nil
    /// Overlapping labels collapse to one control. Tapping it hands those operators to the pull-up.
    var onOperatorGroupTap: (([ServiceProvider]) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var displayedClusters: [DiscoverMapAreaCluster] = []
    /// Skip echoing camera updates that we caused from the utility pill.
    @State private var suppressRadiusEcho = false
    @State private var lastAppliedRadiusMeters: CLLocationDistance = -1
    @State private var lastAppliedCenter: CLLocationCoordinate2D?
    /// Last map→pill radius we published (meters) — used to ignore pan-only camera ends.
    @State private var lastPublishedVisibleRadiusMeters: CLLocationDistance = -1
    /// Remount Map when browse center first arrives — SwiftUI Map often skips content that
    /// was added only after the initial mount (why the pin appeared only after leaving Discover).
    @State private var mapMountEpoch: Int = 0
    /// Until the pill-driven frame has settled, ignore MapKit’s initial camera (often ~world/100mi).
    @State private var hasCompletedInitialBrowseFrame = false
    /// Visible radius of the auto-framed map. Zooming in closer does not resize operator labels past this.
    @State private var lockedLabelRadiusMeters: CLLocationDistance?
    /// Closest the camera may get: the zoom where labels reach `maxLabelZoomScale`.
    @State private var minimumCameraDistance: CLLocationDistance?

    var body: some View {
        Map(
            position: $cameraPosition,
            bounds: minimumCameraDistance.map { MapCameraBounds(minimumDistance: $0) },
            interactionModes: [.pan, .zoom]
        ) {
                if let browseCenter, let browseRadiusMeters, browseRadiusMeters > 0 {
                    MapCircle(center: browseCenter, radius: browseRadiusMeters)
                        .foregroundStyle(Color.oliveGreen.opacity(0.10))
                        .stroke(
                            Color.oliveGreen.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.75, dash: [7, 5])
                        )
                }

                ForEach(labelClusters) { cluster in
                    let isFeatured = cluster.members.contains { $0.provider.id == featuredOperatorId }
                    MapCircle(center: cluster.center, radius: displayedRadius(for: cluster))
                        .foregroundStyle(
                            isFeatured
                                ? Color.oliveGreen.opacity(0.16)
                                : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )

                    Annotation("", coordinate: cluster.center, anchor: .center) {
                        if cluster.members.count == 1, let provider = cluster.members.first?.provider {
                            DiscoverOperatorMapPin(
                                provider: provider,
                                isFeatured: isFeatured,
                                scale: labelZoomScale,
                                onTap: { onOperatorTap?(provider) }
                            )
                        } else {
                            DiscoverOperatorGroupLabel(
                                count: cluster.members.count,
                                isFeatured: isFeatured,
                                scale: labelZoomScale,
                                onTap: { onOperatorGroupTap?(cluster.providers) }
                            )
                        }
                    }
                }

                // Native MapCircle pin — always paints with Map content (no MapProxy / Annotation).
                if let browseCenter {
                    let dotRadius = userLocationDotRadiusMeters()
                    MapCircle(center: browseCenter, radius: dotRadius * 2.1)
                        .foregroundStyle(Color.white.opacity(colorScheme == .dark ? 0.32 : 0.38))
                    MapCircle(center: browseCenter, radius: dotRadius)
                        .foregroundStyle(Color.oliveGreenBase)
                        .stroke(Color.white, lineWidth: 2.5)
                }
            }
            .id("discover-map-\(mapMountEpoch)")
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
                updateMinimumCameraDistance(from: context)
                refreshClusters(for: context.region)
                onVisibleRegionChange?(context.region)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                refreshClusters(for: context.region)
                onVisibleRegionChange?(context.region)
                publishVisibleRadiusMilesIfNeeded(from: context.region)
            }
            .accessibilityElement(children: .contain)
            .onAppear {
                rebuildClusters()
                applyBrowseRadiusCamera(animated: false)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(DiscoverMapChromeClip(fillsScreen: fillsScreen))
        .ignoresSafeArea(edges: fillsScreen ? .all : [])
        .background {
            if fillsScreen {
                DiscoverMapSafeAreaBleedBridge()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            suppressRadiusEcho = true
            rebuildClusters()
            applyBrowseRadiusCamera(animated: false)
        }
        .onChange(of: areas.map(\.id)) { _, _ in
            rebuildClusters()
        }
        .onChange(of: browseRadiusMeters ?? -1) { _, newValue in
            guard newValue > 0 else { return }
            if suppressRadiusEcho {
                lastAppliedRadiusMeters = newValue
                return
            }
            if let visible = visibleRegion,
               let visibleRadiusMeters = Self.visibleRadiusMeters(from: visible),
               abs(visibleRadiusMeters - newValue) / max(newValue, 1) < 0.15 {
                lastAppliedRadiusMeters = newValue
                lastPublishedVisibleRadiusMeters = newValue
                return
            }
            if abs(newValue - lastAppliedRadiusMeters) < 40 { return }
            applyBrowseRadiusCamera(animated: true)
        }
        .onChange(of: browseCenter != nil) { hadCenter, hasCenter in
            // Remount once when center first resolves so Map content includes the pin from frame 0.
            // (SwiftUI Map often skips content that appears only after the initial mount.)
            if !hadCenter, hasCenter {
                remountMapForBrowseCenter()
            }
        }
        .onChange(of: browseCenter?.latitude ?? .nan) { _, _ in
            guard browseCenter != nil else { return }
            applyBrowseRadiusCamera(animated: true)
        }
        .onChange(of: browseCenter?.longitude ?? .nan) { _, _ in
            guard browseCenter != nil else { return }
            applyBrowseRadiusCamera(animated: true)
        }
    }

    /// Region used to size and group labels. Inside the opening frame, keep that opening size.
    private var labelSizingRegion: MKCoordinateRegion? {
        guard let visibleRegion else { return nil }
        guard let locked = lockedLabelRadiusMeters, locked > 0,
              let visible = Self.visibleRadiusMeters(from: visibleRegion),
              visible < locked
        else { return visibleRegion }
        return MKCoordinateRegion(
            center: visibleRegion.center,
            latitudinalMeters: locked * 2,
            longitudinalMeters: locked * 2
        )
    }

    /// Grows the labels with the circles when zoomed in past the opening frame. Capped so a label never fills the screen.
    private var labelZoomScale: CGFloat {
        guard let visibleRegion,
              let locked = lockedLabelRadiusMeters, locked > 0,
              let visible = Self.visibleRadiusMeters(from: visibleRegion), visible > 0
        else { return 1 }
        return CGFloat(min(max(locked / visible, 1), Self.maxLabelZoomScale))
    }

    private static let maxLabelZoomScale: Double = 2.5

    /// Camera distance scales with visible radius, so any frame gives the distance at which labels stop growing.
    private func updateMinimumCameraDistance(from context: MapCameraUpdateContext) {
        guard minimumCameraDistance == nil,
              let locked = lockedLabelRadiusMeters, locked > 0,
              let visible = Self.visibleRadiusMeters(from: context.region), visible > 0,
              context.camera.distance > 0
        else { return }
        let floorRadius = locked / Self.maxLabelZoomScale
        minimumCameraDistance = context.camera.distance * floorRadius / visible
    }

    /// Ground radius only. Zooming in makes the circle look bigger on screen; it never covers less ground.
    private func displayedRadius(for cluster: DiscoverOperatorLabelCluster) -> CLLocationDistance {
        max(DiscoverOperatorPrivacyArea.minimumRadiusMeters, cluster.radiusMeters)
    }

    /// One general area per operator. The drawn center is offset from the real coordinate so the circle shows the neighborhood without marking the shop.
    private var privacyAreas: [DiscoverOperatorPrivacyArea] {
        let areas = operators.compactMap { provider in
            DiscoverOperatorPrivacyArea.make(for: provider, visibleRegion: labelSizingRegion)
        }
        return DiscoverOperatorPrivacyArea.holdingSplitSize(areas)
    }

    /// Labels that overlap at the opening zoom stay combined when the user zooms in closer.
    private var labelClusters: [DiscoverOperatorLabelCluster] {
        DiscoverOperatorLabelCluster.build(from: privacyAreas, visibleRegion: labelSizingRegion)
    }

    /// ~constant on-screen size for the user pin (scales with zoom like the dashed rings).
    private func userLocationDotRadiusMeters() -> CLLocationDistance {
        if let visibleRegion {
            let ring = MyBarbersDiscover.mapAreaScreenConstantRadiusMeters(for: visibleRegion)
            return max(24, ring * 0.065)
        }
        if let browseRadiusMeters, browseRadiusMeters > 0 {
            return max(28, browseRadiusMeters * 0.012)
        }
        return 40
    }

    private func remountMapForBrowseCenter() {
        suppressRadiusEcho = true
        hasCompletedInitialBrowseFrame = false
        lastAppliedRadiusMeters = -1
        lastAppliedCenter = nil
        lastPublishedVisibleRadiusMeters = -1
        visibleRegion = nil
        // Seed camera before remount so MapKit never briefly shows a world-scale view
        // that echoes ~100 mi into the utility pill.
        if let browseCenter,
           let browseRadiusMeters,
           browseRadiusMeters > 0,
           browseCenter.latitude.isFinite,
           browseCenter.longitude.isFinite {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: browseCenter,
                    latitudinalMeters: browseRadiusMeters * 2,
                    longitudinalMeters: browseRadiusMeters * 2
                )
            )
        }
        mapMountEpoch &+= 1
    }

    private func publishVisibleRadiusMilesIfNeeded(from region: MKCoordinateRegion) {
        guard !suppressRadiusEcho else { return }
        guard hasCompletedInitialBrowseFrame else { return }
        guard let radiusMeters = Self.visibleRadiusMeters(from: region) else { return }

        if lastPublishedVisibleRadiusMeters > 0 {
            let delta = abs(radiusMeters - lastPublishedVisibleRadiusMeters)
            if delta / lastPublishedVisibleRadiusMeters < 0.08 { return }
        }
        if lastPublishedVisibleRadiusMeters > 0,
           abs(radiusMeters - lastPublishedVisibleRadiusMeters) < 800 {
            return
        }

        lastPublishedVisibleRadiusMeters = radiusMeters
        let miles = radiusMeters / 1609.344
        guard miles.isFinite, miles > 0 else { return }
        onVisibleRadiusMilesChange?(miles)
    }

    private func rebuildClusters() {
        let region = visibleRegion ?? fallbackRegionForClustering()
        refreshClusters(for: region)
    }

    private func refreshClusters(for region: MKCoordinateRegion) {
        let screenRadius = MyBarbersDiscover.mapAreaScreenConstantRadiusMeters(for: region)
        let mergeDistance = MyBarbersDiscover.mapAreaMergeDistanceMeters(for: region)
        let next = MyBarbersDiscover.clusterMapAreas(
            areas,
            mergeDistanceMeters: mergeDistance,
            baseRadiusMeters: screenRadius
        )
        if next != displayedClusters {
            displayedClusters = next
        }
        promoteSelectionToContainingCluster(in: next)
    }

    /// When a selected individual area merges into a combined ring on zoom-out, select that combined cluster.
    private func promoteSelectionToContainingCluster(in clusters: [DiscoverMapAreaCluster]) {
        guard let currentSelection = selectedAreaId else { return }
        guard let match = clusters.first(where: { cluster in
            if cluster.id == currentSelection { return true }
            if cluster.memberAreaIds.contains(currentSelection) { return true }
            return cluster.memberAreaIds.contains { memberId in
                MyBarbersDiscover.selectionContainsArea(selectionId: currentSelection, areaId: memberId)
            }
        }) else { return }

        guard match.id != currentSelection else { return }
        selectedAreaId = match.id
    }

    private func fallbackRegionForClustering() -> MKCoordinateRegion {
        if let browseCenter, let browseRadiusMeters, browseRadiusMeters > 0 {
            return MKCoordinateRegion(
                center: browseCenter,
                latitudinalMeters: browseRadiusMeters * 2,
                longitudinalMeters: browseRadiusMeters * 2
            )
        }
        return MKCoordinateRegion(
            center: browseCenter ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )
    }

    /// Frames the map so the visible radius matches the utility-pill miles.
    private func applyBrowseRadiusCamera(animated: Bool) {
        guard let browseCenter,
              let browseRadiusMeters,
              browseRadiusMeters > 0,
              browseCenter.latitude.isFinite,
              browseCenter.longitude.isFinite
        else { return }

        let centerChanged: Bool = {
            guard let last = lastAppliedCenter else { return true }
            return abs(last.latitude - browseCenter.latitude) > 0.00005
                || abs(last.longitude - browseCenter.longitude) > 0.00005
        }()
        let radiusChanged = abs(browseRadiusMeters - lastAppliedRadiusMeters) >= 40
        guard centerChanged || radiusChanged || lastAppliedRadiusMeters < 0 else { return }

        suppressRadiusEcho = true
        lastAppliedRadiusMeters = browseRadiusMeters
        lastAppliedCenter = browseCenter
        lockedLabelRadiusMeters = browseRadiusMeters
        minimumCameraDistance = nil

        let region = MKCoordinateRegion(
            center: browseCenter,
            latitudinalMeters: browseRadiusMeters * 2,
            longitudinalMeters: browseRadiusMeters * 2
        )
        let next: MapCameraPosition = .region(region)

        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                cameraPosition = next
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cameraPosition = next
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            suppressRadiusEcho = false
            lastPublishedVisibleRadiusMeters = browseRadiusMeters
            hasCompletedInitialBrowseFrame = true
        }
    }

    private static func visibleRadiusMeters(from region: MKCoordinateRegion) -> CLLocationDistance? {
        MyBarbersDiscover.visibleMapRadiusMeters(from: region)
    }
}

private struct DiscoverMapChromeClip: ViewModifier {
    let fillsScreen: Bool

    func body(content: Content) -> some View {
        if fillsScreen {
            content
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Forces underlying `MKMapView` to ignore safe-area layout margins so MapKit tiles
/// fill the status-bar / home-indicator strips when SwiftUI has already bled the container.
private struct DiscoverMapSafeAreaBleedBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let mapView = uiView.onCuts_firstSuperviewMKMapView()
                ?? uiView.window?.onCuts_firstDescendantMKMapView()
            else { return }
            mapView.insetsLayoutMarginsFromSafeArea = false
            mapView.preservesSuperviewLayoutMargins = false
            if let superview = mapView.superview {
                mapView.frame = superview.bounds
                mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }
    }
}

private extension UIView {
    func onCuts_firstSuperviewMKMapView() -> MKMapView? {
        var current: UIView? = self
        while let view = current {
            if let map = view as? MKMapView { return map }
            for sub in view.subviews {
                if let map = sub as? MKMapView { return map }
                if let nested = sub.onCuts_firstDescendantMKMapView() { return nested }
            }
            current = view.superview
        }
        return nil
    }

    func onCuts_firstDescendantMKMapView() -> MKMapView? {
        if let map = self as? MKMapView { return map }
        for sub in subviews {
            if let found = sub.onCuts_firstDescendantMKMapView() { return found }
        }
        return nil
    }
}

private struct DiscoverOperatorPrivacyArea: Identifiable {
    let provider: ServiceProvider
    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance

    var id: String { provider.id }

    /// About half a mile of ground. Never smaller at any zoom, so a building never becomes the marker.
    static let minimumRadiusMeters: CLLocationDistance = 800
    /// Snap grid. Every operator in the same cell gets the same center, so precision below this is thrown away.
    /// The minimum radius covers the cell's half-diagonal (~640 m), so the operator is always inside the circle.
    static let gridCellMeters: CLLocationDistance = 900

    static func make(
        for provider: ServiceProvider,
        visibleRegion: MKCoordinateRegion?
    ) -> DiscoverOperatorPrivacyArea? {
        guard let exact = provider.serviceCoordinate else { return nil }
        return DiscoverOperatorPrivacyArea(
            provider: provider,
            center: snappedToGrid(exact),
            radiusMeters: radiusMeters(for: visibleRegion)
        )
    }

    /// Center of the grid cell holding `exact`. Discards sub-cell precision instead of a reversible shift.
    static func snappedToGrid(_ exact: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let latStep = gridCellMeters / 111_320
        let row = (exact.latitude / latStep).rounded(.down)
        let rowCenterLat = (row + 0.5) * latStep
        let cosLat = max(0.2, abs(cos(rowCenterLat * .pi / 180)))
        let lngStep = gridCellMeters / (111_320 * cosLat)
        let column = (exact.longitude / lngStep).rounded(.down)
        return CLLocationCoordinate2D(latitude: rowCenterLat, longitude: (column + 0.5) * lngStep)
    }

    static func radiusMeters(for region: MKCoordinateRegion?) -> CLLocationDistance {
        guard let region,
              let visible = MyBarbersDiscover.visibleMapRadiusMeters(from: region)
        else { return minimumRadiusMeters }
        return radiusMeters(forVisibleRadius: visible)
    }

    static func radiusMeters(forVisibleRadius visible: CLLocationDistance) -> CLLocationDistance {
        let oneMile = 1_609.344
        // Inside a mile, keep the same ground size. Zooming closer must not shrink the area.
        if visible <= oneMile {
            return minimumRadiusMeters
        }
        let scale = min(visible / oneMile, 3)
        return minimumRadiusMeters * scale
    }

    /// Once a combined label splits, each operator keeps the size it had at the split. Zooming in further does not shrink it.
    static func holdingSplitSize(_ areas: [DiscoverOperatorPrivacyArea]) -> [DiscoverOperatorPrivacyArea] {
        guard areas.count > 1 else { return areas }
        let locations = areas.map { CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude) }
        return areas.enumerated().map { index, area in
            var nearest = CLLocationDistance.infinity
            for (otherIndex, other) in locations.enumerated() where otherIndex != index {
                nearest = min(nearest, locations[index].distance(from: other))
            }
            guard nearest.isFinite else { return area }
            let splitVisible = DiscoverOperatorLabelCluster.splitVisibleRadiusMeters(forDistance: nearest)
            let held = max(area.radiusMeters, radiusMeters(forVisibleRadius: splitVisible))
            return DiscoverOperatorPrivacyArea(provider: area.provider, center: area.center, radiusMeters: held)
        }
    }
}

private struct DiscoverOperatorLabelCluster: Identifiable {
    let members: [DiscoverOperatorPrivacyArea]
    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance

    var id: String { members.map(\.id).sorted().joined(separator: "|") }
    var providers: [ServiceProvider] { members.map(\.provider) }

    static func build(
        from areas: [DiscoverOperatorPrivacyArea],
        visibleRegion: MKCoordinateRegion?
    ) -> [DiscoverOperatorLabelCluster] {
        guard !areas.isEmpty else { return [] }
        let mergeMeters = mergeDistanceMeters(visibleRegion: visibleRegion)
        var groups: [[DiscoverOperatorPrivacyArea]] = areas.map { [$0] }
        var didMerge = true
        while didMerge {
            didMerge = false
            var index = 0
            while index < groups.count {
                var other = index + 1
                while other < groups.count {
                    if groupsOverlap(groups[index], groups[other], mergeMeters: mergeMeters) {
                        groups[index].append(contentsOf: groups[other])
                        groups.remove(at: other)
                        didMerge = true
                    } else {
                        other += 1
                    }
                }
                index += 1
            }
        }
        return groups.map(make)
    }

    /// Label footprint at the current zoom. Inside a mile, keep the 1-mile footprint so the label does not shrink or split.
    static func mergeDistanceMeters(visibleRegion: MKCoordinateRegion?) -> CLLocationDistance {
        let oneMile = 1_609.344
        let visible = visibleRegion.flatMap { MyBarbersDiscover.visibleMapRadiusMeters(from: $0) } ?? oneMile
        let sizingRadius = max(visible, oneMile)
        return max(480, sizingRadius * mergeFactor)
    }

    /// Label width relative to the visible map radius. Labels closer than this share one "X Operators" label.
    static let mergeFactor = 140.0 / 195.0

    /// Visible map radius where two operators `distance` apart stop sharing a label.
    static func splitVisibleRadiusMeters(forDistance distance: CLLocationDistance) -> CLLocationDistance {
        max(1_609.344, distance / mergeFactor)
    }

    private static func groupsOverlap(
        _ lhs: [DiscoverOperatorPrivacyArea],
        _ rhs: [DiscoverOperatorPrivacyArea],
        mergeMeters: CLLocationDistance
    ) -> Bool {
        for left in lhs {
            for right in rhs {
                let distance = CLLocation(latitude: left.center.latitude, longitude: left.center.longitude)
                    .distance(from: CLLocation(latitude: right.center.latitude, longitude: right.center.longitude))
                if distance < mergeMeters { return true }
            }
        }
        return false
    }

    private static func make(_ members: [DiscoverOperatorPrivacyArea]) -> DiscoverOperatorLabelCluster {
        let latitude = members.reduce(0.0) { $0 + $1.center.latitude } / Double(members.count)
        let longitude = members.reduce(0.0) { $0 + $1.center.longitude } / Double(members.count)
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        if members.count == 1, let only = members.first {
            return DiscoverOperatorLabelCluster(members: members, center: only.center, radiusMeters: only.radiusMeters)
        }
        let centroid = CLLocation(latitude: latitude, longitude: longitude)
        var radius = members.map(\.radiusMeters).max() ?? DiscoverOperatorPrivacyArea.minimumRadiusMeters
        for member in members {
            let distance = centroid.distance(
                from: CLLocation(latitude: member.center.latitude, longitude: member.center.longitude)
            )
            radius = max(radius, distance + member.radiusMeters * 0.45)
        }
        return DiscoverOperatorLabelCluster(members: members, center: center, radiusMeters: radius)
    }
}

private struct DiscoverOperatorGroupLabel: View {
    let count: Int
    let isFeatured: Bool
    var scale: CGFloat = 1
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\(count) Operators")
                .font(OnCutsFont.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(isFeatured ? Color.white : Color.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 8 * scale)
                .background(isFeatured ? Color.black : Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6 * scale, y: 2 * scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) Operators")
        .accessibilityHint("Shows these operators in the list")
    }
}

private struct DiscoverOperatorMapPin: View {
    let provider: ServiceProvider
    let isFeatured: Bool
    var scale: CGFloat = 1
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6 * scale) {
                pinThumbnail
                Text(DiscoverNearbyCopy.pinCaption(for: provider))
                    .font(OnCutsFont.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(isFeatured ? Color.white : Color.black)
                    .lineLimit(1)
            }
            .padding(.leading, 4 * scale)
            .padding(.trailing, 8 * scale)
            .padding(.vertical, 4 * scale)
            .background(isFeatured ? Color.black : Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6 * scale, y: 2 * scale)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.businessName), general area, \(DiscoverNearbyCopy.pinCaption(for: provider))")
    }

    private var pinThumbnail: some View {
        DiscoverPinAvatar(imageUrl: provider.profileImageUrl, diameter: 22 * scale)
            .accessibilityHidden(true)
    }
}

/// Map annotations often drop `AsyncImage` loads. Fetch through the same URL resolver the rest of the app uses.
private struct DiscoverPinAvatar: View {
    let imageUrl: String?
    var diameter: CGFloat = 22
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                OnCutsDefaultProfileAvatarGlyph(slotDiameter: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: imageUrl ?? "") {
            await load()
        }
    }

    private func load() async {
        guard let url = ProfileImageURLResolver.urlForAsyncImage(from: imageUrl) else {
            image = nil
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let loaded = UIImage(data: data)
            else { return }
            image = loaded
        } catch {
            image = nil
        }
    }
}

#else

struct DiscoverServiceAreasMap: View {
    let areas: [DiscoverServiceArea]
    @Binding var selectedAreaId: String?
    var browseCenter: CLLocationCoordinate2D? = nil
    var browseRadiusMeters: CLLocationDistance? = nil
    var fillsScreen: Bool = false
    var onAreaSelected: (() -> Void)? = nil
    var onVisibleRegionChange: ((MKCoordinateRegion) -> Void)? = nil
    var onVisibleRadiusMilesChange: ((Double) -> Void)? = nil
    var operators: [ServiceProvider] = []
    var featuredOperatorId: String? = nil
    var onOperatorTap: ((ServiceProvider) -> Void)? = nil
    var onOperatorGroupTap: (([ServiceProvider]) -> Void)? = nil

    var body: some View {
        Rectangle()
            .fill(Color.neutral200)
            .overlay {
                Text(areas.isEmpty ? "Map" : "\(areas.count) areas")
                    .font(OnCutsFont.caption)
                    .foregroundStyle(Color.neutral500)
            }
    }
}

#endif
