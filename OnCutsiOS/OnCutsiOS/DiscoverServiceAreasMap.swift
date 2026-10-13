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
    /// Map edges covered by chrome (top bar, resting pull-up). The opening frame centers the client's pin in what's left.
    var focusInsets: EdgeInsets = EdgeInsets()

    @Environment(\.colorScheme) private var colorScheme
    @State private var mapSize: CGSize = .zero

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
                updateMinimumCameraDistance(from: context)
                // Sub-pixel camera jitter would re-render every label and re-apply bounds, which can feed back forever.
                guard Self.regionChangedVisibly(from: visibleRegion, to: context.region) else { return }
                visibleRegion = context.region
                refreshClusters(for: context.region)
                onVisibleRegionChange?(context.region)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                if Self.regionChangedVisibly(from: visibleRegion, to: context.region) {
                    visibleRegion = context.region
                    refreshClusters(for: context.region)
                    onVisibleRegionChange?(context.region)
                }
                publishVisibleRadiusMilesIfNeeded(from: context.region)
            }
            .accessibilityElement(children: .contain)
            .onAppear {
                rebuildClusters()
                applyBrowseRadiusCamera(animated: false)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let firstMeasure = mapSize.width < 1 && size.width > 0
            mapSize = size
            if firstMeasure, lastAppliedRadiusMeters > 0 {
                lastAppliedRadiusMeters = -1
                applyBrowseRadiusCamera(animated: false)
            }
        }
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

    /// Region used to size the privacy circles. Inside the opening frame, keep that opening size.
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

    /// Grows the labels when zoomed in past the opening frame, slower than the map zooms so nearby labels pull apart.
    private var labelZoomScale: CGFloat {
        guard let visible = currentVisibleRadiusMeters,
              let locked = lockedLabelRadiusMeters, locked > 0
        else { return 1 }
        let zoom = max(locked / visible, 1)
        return CGFloat(min(pow(zoom, Self.labelGrowthExponent), Self.maxLabelZoomScale))
    }

    private var currentVisibleRadiusMeters: CLLocationDistance? {
        guard let visibleRegion,
              let visible = Self.visibleRadiusMeters(from: visibleRegion), visible > 0
        else { return nil }
        return visible
    }

    private static let maxLabelZoomScale: Double = 1.9
    /// Below 1, labels grow slower than the map. 0.4 reaches the 1.9× cap at ~5× zoom.
    private static let labelGrowthExponent: Double = 0.4

    /// Camera distance scales with visible radius, so any frame gives the distance at which labels stop growing.
    private func updateMinimumCameraDistance(from context: MapCameraUpdateContext) {
        guard minimumCameraDistance == nil,
              let locked = lockedLabelRadiusMeters, locked > 0,
              let visible = Self.visibleRadiusMeters(from: context.region), visible > 0,
              context.camera.distance > 0
        else { return }
        let floorRadius = locked / pow(Self.maxLabelZoomScale, 1 / Self.labelGrowthExponent)
        minimumCameraDistance = context.camera.distance * floorRadius / visible
    }

    /// Ground radius only. Zooming in makes the circle look bigger on screen; it never covers less ground.
    private func displayedRadius(for cluster: DiscoverOperatorLabelCluster) -> CLLocationDistance {
        max(DiscoverOperatorPrivacyArea.minimumRadiusMeters, cluster.radiusMeters)
    }

    /// One general area per operator. The drawn center is offset from the real coordinate so the circle shows the neighborhood without marking the shop.
    private var privacyAreas: [DiscoverOperatorPrivacyArea] {
        operators.compactMap { provider in
            DiscoverOperatorPrivacyArea.make(for: provider, visibleRegion: labelSizingRegion)
        }
    }

    /// Operators whose labels would collide on screen share one "X Operators" label; zooming in splits them apart.
    private var labelClusters: [DiscoverOperatorLabelCluster] {
        DiscoverOperatorLabelCluster.build(
            from: privacyAreas,
            pointsPerMeter: screenPointsPerMeter,
            labelScale: Double(labelZoomScale)
        )
    }

    private var screenPointsPerMeter: Double? {
        guard let visibleRegion, mapSize.width > 0 else { return nil }
        let cosLat = max(0.2, abs(cos(visibleRegion.center.latitude * .pi / 180)))
        let widthMeters = visibleRegion.span.longitudeDelta * 111_320 * cosLat
        guard widthMeters > 0, widthMeters.isFinite else { return nil }
        return Double(mapSize.width) / widthMeters
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
                    center: framingCenter(for: browseCenter, radiusMeters: browseRadiusMeters),
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
            center: framingCenter(for: browseCenter, radiusMeters: browseRadiusMeters),
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

    /// Camera center that puts `pin` midway between the covered top and bottom edges instead of behind the pull-up.
    /// A square region fits the map's width, so one point is `2 * radius / width` meters.
    private func framingCenter(
        for pin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        guard mapSize.width > 0, mapSize.height > 0 else { return pin }
        let openTop = min(focusInsets.top, mapSize.height)
        let openBottom = max(openTop, mapSize.height - focusInsets.bottom)
        let shiftPoints = (openTop + openBottom) / 2 - mapSize.height / 2
        let shiftMeters = Double(shiftPoints) * radiusMeters * 2 / Double(mapSize.width)
        return CLLocationCoordinate2D(latitude: pin.latitude + shiftMeters / 111_320, longitude: pin.longitude)
    }

    /// True when the camera moved or zoomed by more than ~0.2% of the view. Smaller changes aren't visible.
    private static func regionChangedVisibly(from old: MKCoordinateRegion?, to new: MKCoordinateRegion) -> Bool {
        guard let old else { return true }
        let latSpan = max(new.span.latitudeDelta, 1e-9)
        let lngSpan = max(new.span.longitudeDelta, 1e-9)
        let threshold = 0.002
        return abs(new.center.latitude - old.center.latitude) / latSpan > threshold
            || abs(new.center.longitude - old.center.longitude) / lngSpan > threshold
            || abs(new.span.latitudeDelta - old.span.latitudeDelta) / latSpan > threshold
            || abs(new.span.longitudeDelta - old.span.longitudeDelta) / lngSpan > threshold
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
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        // Already configured this map: skip the view-tree search (it ran on every update and could walk every hub tab).
        if let configured = coordinator.mapView, configured.window != nil { return }
        DispatchQueue.main.async {
            guard let mapView = uiView.onCuts_nearbyMKMapView() else { return }
            coordinator.mapView = mapView
            mapView.insetsLayoutMarginsFromSafeArea = false
            mapView.preservesSuperviewLayoutMargins = false
            if let superview = mapView.superview {
                mapView.frame = superview.bounds
                mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }
    }

    final class Coordinator {
        weak var mapView: MKMapView?
    }
}

private extension UIView {
    /// The bridge sits in the map's `.background`, so the map is within a few ancestors. Never search the whole window.
    func onCuts_nearbyMKMapView(maxAncestorLevels: Int = 6) -> MKMapView? {
        var current: UIView? = self
        var level = 0
        while let view = current, level <= maxAncestorLevels {
            if let map = view as? MKMapView { return map }
            for sub in view.subviews where sub !== self {
                if let found = sub.onCuts_firstDescendantMKMapView() { return found }
            }
            current = view.superview
            level += 1
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
}

private struct DiscoverOperatorLabelCluster: Identifiable {
    let members: [DiscoverOperatorPrivacyArea]
    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance

    var id: String { members.map(\.id).sorted().joined(separator: "|") }
    var providers: [ServiceProvider] { members.map(\.provider) }

    /// Used before the map has measured itself (no screen scale yet).
    static let fallbackGroupingDistanceMeters: CLLocationDistance = 1_609.344
    /// Breathing room between neighboring labels before they merge.
    private static let labelGapPoints: Double = 6

    /// Merges operators whose labels would overlap at the current zoom. A merged label is wider and sits at the
    /// group's centroid, so passes repeat until no two labels collide.
    static func build(
        from areas: [DiscoverOperatorPrivacyArea],
        pointsPerMeter: Double?,
        labelScale: Double
    ) -> [DiscoverOperatorLabelCluster] {
        guard !areas.isEmpty else { return [] }
        guard let pointsPerMeter, pointsPerMeter > 0, pointsPerMeter.isFinite else {
            return mergingPasses(areas.map { [$0] }) { lhs, rhs in
                groundDistanceMeters(lhs.center, rhs.center) < fallbackGroupingDistanceMeters
            }
        }
        var captionLengths: [String: Int] = [:]
        for area in areas {
            captionLengths[area.id] = DiscoverNearbyCopy.pinCaption(for: area.provider).count
        }
        return mergingPasses(areas.map { [$0] }) { lhs, rhs in
            labelsOverlap(
                lhs.estimatedLabelSize(scale: labelScale, captionLengths: captionLengths),
                at: lhs.center,
                rhs.estimatedLabelSize(scale: labelScale, captionLengths: captionLengths),
                at: rhs.center,
                pointsPerMeter: pointsPerMeter
            )
        }
    }

    private static func mergingPasses(
        _ initial: [[DiscoverOperatorPrivacyArea]],
        shouldMerge: (DiscoverOperatorLabelCluster, DiscoverOperatorLabelCluster) -> Bool
    ) -> [DiscoverOperatorLabelCluster] {
        var groups = initial
        while true {
            let clusters = groups.map(make)
            var parent = Array(groups.indices)
            func root(_ index: Int) -> Int {
                var index = index
                while parent[index] != index {
                    parent[index] = parent[parent[index]]
                    index = parent[index]
                }
                return index
            }
            var mergedAny = false
            for lhs in clusters.indices {
                for rhs in clusters.indices where rhs > lhs {
                    let a = root(lhs), b = root(rhs)
                    guard a != b, shouldMerge(clusters[lhs], clusters[rhs]) else { continue }
                    parent[b] = a
                    mergedAny = true
                }
            }
            guard mergedAny else { return clusters }
            var merged: [Int: [DiscoverOperatorPrivacyArea]] = [:]
            var order: [Int] = []
            for index in groups.indices {
                let key = root(index)
                if merged[key] == nil { order.append(key) }
                merged[key, default: []].append(contentsOf: groups[index])
            }
            groups = order.compactMap { merged[$0] }
        }
    }

    private static func labelsOverlap(
        _ a: (width: Double, height: Double),
        at lhs: CLLocationCoordinate2D,
        _ b: (width: Double, height: Double),
        at rhs: CLLocationCoordinate2D,
        pointsPerMeter: Double
    ) -> Bool {
        let cosLat = max(0.2, abs(cos((lhs.latitude + rhs.latitude) * 0.5 * .pi / 180)))
        let dx = abs(lhs.longitude - rhs.longitude) * 111_320 * cosLat * pointsPerMeter
        let dy = abs(lhs.latitude - rhs.latitude) * 111_320 * pointsPerMeter
        return dx < (a.width + b.width) / 2 + labelGapPoints
            && dy < (a.height + b.height) / 2 + labelGapPoints
    }

    /// Mirrors the padding in `DiscoverOperatorMapPin` / `DiscoverOperatorGroupLabel`; Inter averages ~0.56 em per glyph.
    private func estimatedLabelSize(scale: Double, captionLengths: [String: Int]) -> (width: Double, height: Double) {
        if members.count == 1, let only = members.first {
            let caption = Double(captionLengths[only.id] ?? 12) * 11 * 0.56
            return ((4 + 22 + 6 + 8 + caption) * scale, (22 + 8) * scale)
        }
        let text = Double("\(members.count) Operators".count) * 13 * 0.56
        return ((24 + text) * scale, (16 + 16) * scale)
    }

    private static func groundDistanceMeters(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        let cosLat = max(0.2, abs(cos((lhs.latitude + rhs.latitude) * 0.5 * .pi / 180)))
        let north = (lhs.latitude - rhs.latitude) * 111_320
        let east = (lhs.longitude - rhs.longitude) * 111_320 * cosLat
        return (north * north + east * east).squareRoot()
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

    /// Pins re-run `.task` whenever the Home page re-appears; reuse decoded avatars instead of refetching each time.
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    private func load() async {
        guard let url = ProfileImageURLResolver.urlForAsyncImage(from: imageUrl) else {
            image = nil
            return
        }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let raw = UIImage(data: data)
            else { return }
            // Decode off the main thread so many pins loading at once don't stall scrolling.
            let loaded = await raw.byPreparingForDisplay() ?? raw
            guard !Task.isCancelled else { return }
            Self.cache.setObject(loaded, forKey: url as NSURL)
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
