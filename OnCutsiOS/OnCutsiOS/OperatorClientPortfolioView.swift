//
//  OperatorClientPortfolioView.swift
//  OnCuts
//
//  Customer Client View: vertical scroll of specialty covers, then a section grid.
//

import AVKit
import SwiftUI

struct OperatorClientPortfolioView: View {
    let provider: ServiceProvider
    var headlineColor: Color = .primary
    var bodyColor: Color = .secondary
    let onBook: () -> Void

    @State private var sections: [OperatorPortfolioSection] = []
    @State private var availabilityDays: [ServiceProvider.DayAvailability] = []
    @State private var shownProvider: ServiceProvider?
    @State private var galleryHidden = false
    @State private var isLoading = false
    @State private var openSectionID: String?
    @State private var viewerItem: OperatorPortfolioItem?

    private var profile: ServiceProvider { shownProvider ?? provider }

    private var openSection: OperatorPortfolioSection? {
        guard let openSectionID else { return nil }
        return sections.first { $0.id == openSectionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let openSection {
                sectionHeader(openSection)
                workGrid(openSection.items, columns: 3)
            } else {
                header
                if !availabilityDays.isEmpty {
                    availabilityGrid
                }
                if isLoading && sections.isEmpty && !galleryHidden {
                    ProgressView()
                        .tint(Color.oliveGreen)
                        .frame(maxWidth: .infinity)
                } else if !galleryHidden {
                    specialtyGrid
                }
            }
        }
        .task(id: provider.id) {
            await load()
        }
        .fullScreenCover(item: $viewerItem) { item in
            OperatorPortfolioMediaViewer(item: item) {
                viewerItem = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ServiceProviderProfileThumbnail(
                imageUrl: profile.profileImageUrl,
                businessName: profile.businessName,
                size: 56,
                cornerRadius: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.businessName)
                    .font(OnCutsFont.headlineSmall.weight(.semibold))
                    .foregroundStyle(headlineColor)
                    .lineLimit(1)
                if let url = OperatorClientPortfolioAssembly.instagramURL(from: profile.instagramHandle),
                   !profile.instagramDisplayHandle.isEmpty {
                    Link(destination: url) {
                        Text(profile.instagramDisplayHandle)
                            .font(OnCutsFont.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: "#8A3AB9"))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onBook) {
                Text("Book")
                    .font(OnCutsFont.body(weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.oliveGreen)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Book \(profile.businessName)")
        }
    }

    private var specialtyGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(sections) { section in
                if section.hasWork {
                    Button {
                        openSectionID = section.id
                    } label: {
                        specialtyTile(section)
                    }
                    .buttonStyle(.plain)
                } else {
                    specialtyTile(section)
                }
            }
        }
    }

    private func specialtyTile(_ section: OperatorPortfolioSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            portfolioFrame(cornerRadius: 12) {
                if section.hasWork, let url = section.coverItem?.tileURL {
                    portfolioImage(url)
                    if section.coverItem?.isVideo == true {
                        playBadge
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(headlineColor.opacity(0.35), lineWidth: 1)
                        .overlay {
                            Text("No Work Attached")
                                .font(OnCutsFont.caption.weight(.semibold))
                                .foregroundStyle(bodyColor)
                                .multilineTextAlignment(.center)
                                .padding(8)
                        }
                }
            }

            Text(section.titleLine)
                .font(OnCutsFont.caption.weight(.semibold))
                .foregroundStyle(headlineColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ section: OperatorPortfolioSection) -> some View {
        HStack(spacing: 8) {
            Button {
                openSectionID = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(OnCutsFont.body(weight: .semibold))
                    .foregroundStyle(headlineColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All specialties")

            Text(section.titleLine)
                .font(OnCutsFont.headlineSmall.weight(.semibold))
                .foregroundStyle(headlineColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func workGrid(_ items: [OperatorPortfolioItem], columns count: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                Button {
                    viewerItem = item
                }                 label: {
                    portfolioFrame(cornerRadius: 8) {
                        if let url = item.tileURL {
                            portfolioImage(url)
                        } else {
                            Color.black.opacity(0.2)
                        }
                        if item.isVideo {
                            playBadge
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isVideo ? "Play video" : "View photo")
            }
        }
    }

    private var availabilityGrid: some View {
        let first = Array(availabilityDays.prefix(4))
        let second = Array(availabilityDays.dropFirst(4))
        return VStack(alignment: .leading, spacing: 16) {
            Text("Availability this Week")
                .font(OnCutsFont.headlineSmall)
                .foregroundStyle(headlineColor)
            availabilityRow(first)
            if !second.isEmpty {
                availabilityRow(second)
            }
        }
    }

    private func availabilityRow(_ days: [ServiceProvider.DayAvailability]) -> some View {
        let columnCount = 4
        let maxSlots = days.map(\.timeSlots.count).max() ?? 0
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    Text(day.dayOfWeek)
                        .font(OnCutsFont.caption.weight(.medium))
                        .foregroundStyle(headlineColor)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0 ..< max(0, columnCount - days.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            ForEach(0 ..< maxSlots, id: \.self) { slotIndex in
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        Text(slotIndex < day.timeSlots.count ? day.timeSlots[slotIndex] : "")
                            .font(OnCutsFont.caption2)
                            .foregroundStyle(bodyColor)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(0 ..< max(0, columnCount - days.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private static func sortedOpenDays(_ days: [ServiceProvider.DayAvailability]?) -> [ServiceProvider.DayAvailability] {
        guard let days else { return [] }
        return days.filter(\.isAvailable).sorted { lhs, rhs in
            weekdayRank(lhs.dayOfWeek) < weekdayRank(rhs.dayOfWeek)
        }
    }

    private static func weekdayRank(_ raw: String) -> Int {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        return names.firstIndex(where: { key.hasPrefix($0) }) ?? names.count
    }

    /// Locks each tile to 9:16 and clips the photo inside that frame so neighbors do not overlap.
    private func portfolioFrame<Content: View>(
        cornerRadius: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Color.clear
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        content()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func portfolioImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Color.black.opacity(0.15)
            }
        }
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(OnCutsFont.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(Circle().fill(Color.black.opacity(0.45)))
    }

    @MainActor
    private func load() async {
        isLoading = true
        galleryHidden = false
        defer { isLoading = false }

        async let previewTask = OperatorPortfolioPreviewAPI.fetch(barberId: provider.id)
        async let profileTask = OperatorPortfolioPreviewAPI.fetchProfile(barberId: provider.id)

        let profileResult = try? await profileTask
        if let profileResult {
            shownProvider = profileResult.provider
        }
        let activeProvider = profileResult?.provider ?? provider
        let offers = profileResult?.offers ?? (provider.services ?? []).map { service in
            OperatorPortfolioOffer(
                name: service.name,
                slug: OperatorPortfolioCatalog.slug(service.name),
                price: service.exactPrice ?? Decimal(service.price)
            )
        }
        availabilityDays = Self.sortedOpenDays(activeProvider.availability)

        do {
            switch try await previewTask {
            case .hidden:
                galleryHidden = true
                sections = []
            case .available(let preview):
                galleryHidden = false
                sections = OperatorClientPortfolioAssembly.sections(
                    providerType: activeProvider.providerType,
                    offeredSpecialtyKeys: activeProvider.offeredSpecialties ?? [],
                    offers: offers,
                    preview: preview
                )
            }
        } catch {
            if OnCutsRefreshCancellation.isBenignCancellation(error) { return }
            galleryHidden = false
            sections = OperatorClientPortfolioAssembly.sections(
                providerType: activeProvider.providerType,
                offeredSpecialtyKeys: activeProvider.offeredSpecialties ?? [],
                offers: offers,
                preview: OperatorPortfolioPreview(items: [], specialtyIds: [])
            )
        }
    }
}

/// Booked-specialty work inside a conversation. Renders nothing when that specialty has no pieces.
struct OperatorPortfolioSpecialtyStrip: View {
    let barberId: String
    let serviceName: String

    @State private var items: [OperatorPortfolioItem] = []
    @State private var viewerItem: OperatorPortfolioItem?

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    let columns = [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                    ]
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(items) { item in
                            Button {
                                viewerItem = item
                            }                             label: {
                                Color.clear
                                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                    .overlay {
                                        GeometryReader { geo in
                                            ZStack {
                                                if let url = item.tileURL {
                                                    AsyncImage(url: url) { phase in
                                                        if case .success(let image) = phase {
                                                            image.resizable().scaledToFill()
                                                        } else {
                                                            Color.white.opacity(0.08)
                                                        }
                                                    }
                                                } else {
                                                    Color.white.opacity(0.08)
                                                }
                                                if item.isVideo {
                                                    Image(systemName: "play.fill")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(.white)
                                                        .padding(6)
                                                        .background(Circle().fill(Color.black.opacity(0.45)))
                                                }
                                            }
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .clipped()
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .fullScreenCover(item: $viewerItem) { item in
                    OperatorPortfolioMediaViewer(item: item) {
                        viewerItem = nil
                    }
                }
            }
        }
        .task(id: "\(barberId)|\(serviceName)") {
            await load()
        }
    }

    @MainActor
    private func load() async {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedService = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedService.isEmpty else {
            items = []
            return
        }
        async let previewTask = OperatorPortfolioPreviewAPI.fetch(barberId: trimmedId)
        async let profileTask = OperatorPortfolioPreviewAPI.fetchProfile(barberId: trimmedId)
        guard let previewStatus = try? await previewTask, case .available(let preview) = previewStatus else {
            items = []
            return
        }
        let profile = try? await profileTask
        let built = OperatorClientPortfolioAssembly.sections(
            providerType: profile?.provider.providerType,
            offeredSpecialtyKeys: profile?.provider.offeredSpecialties ?? [],
            offers: profile?.offers ?? [],
            preview: preview
        )
        let match = OperatorClientPortfolioAssembly.section(matchingServiceName: trimmedService, in: built)
        items = match?.hasWork == true ? (match?.items ?? []) : []
    }
}

private struct OperatorPortfolioMediaViewer: View {
    let item: OperatorPortfolioItem
    let onClose: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if item.isVideo, let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let url = item.mediaURL ?? item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .padding(16)
                    }
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
        }
        .onAppear {
            guard item.isVideo, let url = item.mediaURL else { return }
            let next = AVPlayer(url: url)
            player = next
            next.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
