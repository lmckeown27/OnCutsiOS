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
    /// Operators drawn as pins (thumbnail, next open time, starting price).
    var operators: [ServiceProvider] = []
    /// Dark pin: closest operator, or the one the client last featured.
    var featuredOperatorId: String? = nil
    var onOperatorTap: ((ServiceProvider) -> Void)? = nil

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

    var body: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                if let browseCenter, let browseRadiusMeters, browseRadiusMeters > 0 {
                    MapCircle(center: browseCenter, radius: browseRadiusMeters)
                        .foregroundStyle(Color.oliveGreen.opacity(0.10))
                        .stroke(
                            Color.oliveGreen.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.75, dash: [7, 5])
                        )
                }

                ForEach(operators) { provider in
                    if let coordinate = provider.serviceCoordinate {
                        Annotation("", coordinate: coordinate, anchor: .bottom) {
                            DiscoverOperatorMapPin(
                                provider: provider,
                                isFeatured: provider.id == featuredOperatorId,
                                onTap: { onOperatorTap?(provider) }
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

private struct DiscoverOperatorMapPin: View {
    let provider: ServiceProvider
    let isFeatured: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    pinThumbnail
                    Text(DiscoverNearbyCopy.pinCaption(for: provider))
                        .font(OnCutsFont.system(size: 11, weight: .semibold))
                        .foregroundStyle(isFeatured ? Color.white : Color.black)
                        .lineLimit(1)
                }
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(isFeatured ? Color.black : Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

                Circle()
                    .fill(isFeatured ? Color.black : Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.businessName), \(DiscoverNearbyCopy.pinCaption(for: provider))")
    }

    private var pinThumbnail: some View {
        DiscoverPinAvatar(imageUrl: provider.profileImageUrl)
            .accessibilityHidden(true)
    }
}

/// Map annotations often drop `AsyncImage` loads. Fetch through the same URL resolver the rest of the app uses.
private struct DiscoverPinAvatar: View {
    let imageUrl: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                OnCutsDefaultProfileAvatarGlyph(slotDiameter: 22)
            }
        }
        .frame(width: 22, height: 22)
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
