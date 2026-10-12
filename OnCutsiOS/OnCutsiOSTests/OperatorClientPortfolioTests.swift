//
//  OperatorClientPortfolioTests.swift
//  OnCutsTests
//

import Testing
import Foundation
@testable import OnCuts

struct OperatorClientPortfolioTests {
    @Test func ordersSavedThenCatalogThenUntaggedExtras() {
        let preview = OperatorPortfolioPreview(
            items: [
                item(id: "p1", specialties: ["fade"], sortOrder: 0, isCover: true, isVideo: false),
                item(id: "v1", specialties: ["custom-art"], sortOrder: 1, isCover: false, isVideo: true),
            ],
            specialtyIds: ["taper", "missing-specialty", "fade"]
        )
        let sections = OperatorClientPortfolioAssembly.sections(
            providerType: "barber",
            offeredSpecialtyKeys: ["Haircut", "Fade", "Taper"],
            offers: [
                OperatorPortfolioOffer(name: "Haircut", slug: "haircut", price: 30),
                OperatorPortfolioOffer(name: "Fade", slug: "fade", price: Decimal(string: "25.50")!),
                OperatorPortfolioOffer(name: "Taper", slug: "taper", price: 25),
            ],
            preview: preview
        )
        #expect(sections.map(\.id) == ["taper", "fade", "haircut", "custom-art"])
        #expect(sections.first { $0.id == "fade" }?.priceLabel == "$25.50")
        #expect(sections.first { $0.id == "taper" }?.priceLabel == "$25")
        #expect(sections.first { $0.id == "haircut" }?.hasWork == false)
        #expect(sections.first { $0.id == "custom-art" }?.hasWork == true)
        #expect(sections.first { $0.id == "fade" }?.items.map(\.id) == ["p1"])
    }

    @Test func coverIsNewestPhotoAndNeverAVideo() {
        let older = item(
            id: "old",
            specialties: ["fade"],
            sortOrder: 0,
            isCover: false,
            isVideo: false,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newer = item(
            id: "new",
            specialties: ["fade"],
            sortOrder: 1,
            isCover: false,
            isVideo: false,
            createdAt: Date(timeIntervalSince1970: 50)
        )
        let video = item(
            id: "vid",
            specialties: ["fade"],
            sortOrder: 2,
            isCover: true,
            isVideo: true,
            createdAt: Date(timeIntervalSince1970: 80)
        )
        let sections = OperatorClientPortfolioAssembly.sections(
            providerType: "barber",
            offeredSpecialtyKeys: ["Fade"],
            offers: [],
            preview: OperatorPortfolioPreview(items: [older, newer, video], specialtyIds: [])
        )
        #expect(sections.first?.items.map(\.id) == ["new", "old", "vid"])
    }

    @Test func markedCoverPhotoWins() {
        let marked = item(id: "cover", specialties: ["nails"], sortOrder: 2, isCover: true, isVideo: false)
        let other = item(id: "other", specialties: ["nails"], sortOrder: 0, isCover: false, isVideo: false)
        let sections = OperatorClientPortfolioAssembly.sections(
            providerType: "beauty",
            offeredSpecialtyKeys: ["Nails"],
            offers: [],
            preview: OperatorPortfolioPreview(items: [other, marked], specialtyIds: [])
        )
        #expect(sections.first?.items.map(\.id) == ["cover", "other"])
    }

    @Test func instagramHandleStripsAtSign() {
        let url = OperatorClientPortfolioAssembly.instagramURL(from: "@studio.name")
        #expect(url?.absoluteString == "https://instagram.com/studio.name")
    }

    private func item(
        id: String,
        specialties: [String],
        sortOrder: Int,
        isCover: Bool,
        isVideo: Bool,
        createdAt: Date? = nil
    ) -> OperatorPortfolioItem {
        OperatorPortfolioItem(
            id: id,
            mediaType: isVideo ? "video" : "photo",
            mediaURL: nil,
            thumbnailURL: nil,
            caption: nil,
            sortOrder: sortOrder,
            specialties: specialties,
            bookingId: nil,
            isCover: isCover,
            createdAt: createdAt
        )
    }
}
