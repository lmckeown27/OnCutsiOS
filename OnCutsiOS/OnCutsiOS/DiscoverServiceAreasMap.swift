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

    /// Unselected dashed rings: black on light maps, white on dark maps.
    private var areaRingStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var areaRingFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                if let browseCenter, let browseRadiusMeters, browseRadiusMeters > 0 {
                    MapCircle(center: browseCenter, radius: browseRadiusMeters)
                        .foregroundStyle(Color.oliveGreen.opacity(0.12))
                        .stroke(Color.oliveGreen.opacity(0.95), lineWidth: 2.5)
                }

                ForEach(displayedClusters) { cluster in
                    let coordinate = CLLocationCoordinate2D(
                        latitude: cluster.latitude,
                        longitude: cluster.longitude
                    )
                    let isSelected = isClusterSelected(cluster)

                    MapCircle(center: coordinate, radius: cluster.radiusMeters)
                        .foregroundStyle(
                            isSelected ? Color.oliveGreen.opacity(0.16) : areaRingFillColor
                        )
                        .stroke(
                            isSelected
                                ? (colorScheme == .dark ? Color.white : Color.oliveGreen)
                                : areaRingStrokeColor,
                            style: StrokeStyle(
                                lineWidth: isSelected ? 2.5 : (cluster.memberAreaIds.count > 1 ? 1.25 : 1),
                                dash: cluster.memberAreaIds.count > 1 ? [8, 6] : [6, 5]
                            )
                        )
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
                refreshClusters(for: context.region)
                onVisibleRegionChange?(context.region)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                refreshClusters(for: context.region)
                onVisibleRegionChange?(context.region)
                publishVisibleRadiusMilesIfNeeded(from: context.region)
            }
            .onTapGesture { position in
                guard let coordinate = proxy.convert(position, from: .local) else { return }
                selectCluster(containing: coordinate)
            }
            .accessibilityElement(children: .contain)
            .onAppear {
                rebuildClusters()
                applyBrowseRadiusCamera(animated: false)
            }
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

    private func isClusterSelected(_ cluster: DiscoverMapAreaCluster) -> Bool {
        guard let selectedAreaId else { return false }
        if selectedAreaId == cluster.id { return true }
        if cluster.memberAreaIds.contains(selectedAreaId) { return true }
        return cluster.memberAreaIds.contains { memberId in
            MyBarbersDiscover.selectionContainsArea(selectionId: selectedAreaId, areaId: memberId)
        }
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

    private func selectCluster(containing coordinate: CLLocationCoordinate2D) {
        let tap = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: (cluster: DiscoverMapAreaCluster, distance: CLLocationDistance)?
        for cluster in displayedClusters {
            let center = CLLocation(latitude: cluster.latitude, longitude: cluster.longitude)
            let distance = tap.distance(from: center)
            guard distance <= cluster.radiusMeters else { continue }
            if let current = best {
                if distance < current.distance {
                    best = (cluster, distance)
                }
            } else {
                best = (cluster, distance)
            }
        }
        guard let best else { return }

        if isClusterSelected(best.cluster) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAreaId = nil
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedAreaId = best.cluster.id
        }
        onAreaSelected?()
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
