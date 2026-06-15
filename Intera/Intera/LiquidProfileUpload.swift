//
//  LiquidProfileUpload.swift
//  Intera
//
//  Profile avatar with upload progress ring, success bounce, and error retry.
//

import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liquid profile avatar + upload

struct LiquidProfileUpload: View {
    let imageURL: URL?
    /// Upload prepared image data (API applies size limits). Throw on recoverable failure; handle 401 in caller without rethrowing.
    let onUpload: (Data) async throws -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var uploadProgress: CGFloat = 0
    @State private var isUploading = false
    @State private var uploadError = false
    @State private var successScale: CGFloat = 1
    @State private var showChangePhotoOptions = false
    @State private var showPhotoLibraryPicker = false
    #if os(iOS)
    @State private var showCameraCapture = false
    #endif
    #if os(iOS) || os(visionOS)
    /// After library pick; drives circular crop UI before upload.
    @State private var libraryReviewImage: UIImage?
    @State private var libraryCropSessionID = UUID()
    #endif
    /// Same bytes as upload so the preview doesn’t swap to a differently-oriented remote `AsyncImage` until the URL has loaded.
    @State private var localAvatarJPEG: Data?

    /// Matches `ProfileAvatarCropMetrics.displayDiameter` in `ProfilePhotoLibraryFlow` (crop preview WYSIWYG).
    private let avatarSize: CGFloat = 120
    /// Matches `AvatarView` / messaging (`clipStyle: .square(cornerRadius:)`).
    private let avatarCornerRadius: CGFloat = 15

    private var avatarShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: avatarCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                avatarImageContent
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(avatarShape)
                    .scaleEffect(successScale)
                    .overlay {
                        if isUploading {
                            avatarShape
                                .fill(.ultraThinMaterial)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        progressRing
                    }
                    .overlay {
                        errorRing
                    }
                    .overlay {
                        avatarShape
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
            }
            .frame(width: avatarSize, height: avatarSize)

            if uploadError {
                Button {
                    uploadError = false
                    showChangePhotoOptions = true
                } label: {
                    Text("Try Again")
                        .font(InteraFont.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                guard !isUploading else { return }
                showChangePhotoOptions = true
            } label: {
                Text(isUploading ? "Uploading…" : "Change Profile Picture")
                    .font(InteraFont.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: uploadError)
        .confirmationDialog("Change Profile Picture", isPresented: $showChangePhotoOptions, titleVisibility: .visible) {
            Button("Choose from Library") {
                #if os(iOS) || os(visionOS)
                libraryReviewImage = nil
                #endif
                showPhotoLibraryPicker = true
            }
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    showCameraCapture = true
                }
            }
            #endif
            Button("Cancel", role: .cancel) {}
        }
        #if os(macOS)
        .photosPicker(isPresented: $showPhotoLibraryPicker, selection: $selectedItem, matching: .images)
        #endif
        #if os(iOS) || os(visionOS)
        .sheet(isPresented: $showPhotoLibraryPicker, onDismiss: {
            libraryReviewImage = nil
        }) {
            Group {
                if let review = libraryReviewImage {
                    ProfileCircularCropSheet(
                        image: review,
                        onUsePhoto: { cropped in
                            guard let data = cropped.jpegData(compressionQuality: 0.82) else {
                                uploadError = true
                                showPhotoLibraryPicker = false
                                libraryReviewImage = nil
                                return
                            }
                            Task {
                                await runUpload(with: data)
                                showPhotoLibraryPicker = false
                                libraryReviewImage = nil
                            }
                        },
                        onChooseDifferent: {
                            libraryReviewImage = nil
                        }
                    )
                    .id(libraryCropSessionID)
                } else {
                    ProfileLibraryImagePicker(isPresented: $showPhotoLibraryPicker) { picked in
                        libraryReviewImage = picked
                        libraryCropSessionID = UUID()
                    }
                    .ignoresSafeArea()
                }
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showCameraCapture) {
            ProfileCameraCaptureView(isPresented: $showCameraCapture) { image in
                guard let imageData = image.jpegData(compressionQuality: 0.82) else {
                    uploadError = true
                    return
                }
                await runUpload(with: imageData)
            }
            .ignoresSafeArea()
        }
        #endif
        #if os(macOS)
        .onChange(of: selectedItem) { _, new in
            Task { await handlePhotosPickerItem(new) }
        }
        #endif
    }

    @ViewBuilder
    private var avatarImageContent: some View {
        ZStack {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .onAppear {
                                    if localAvatarJPEG != nil {
                                        localAvatarJPEG = nil
                                    }
                                }
                        case .empty, .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            #if canImport(UIKit)
            if let localAvatarJPEG, let ui = UIImage(data: localAvatarJPEG) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            }
            #endif
        }
    }

    private var placeholder: some View {
        InteraDefaultProfileAvatarGlyph(slotDiameter: avatarSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressRing: some View {
        avatarShape
            .trim(from: 0, to: uploadProgress)
            .stroke(
                LinearGradient(
                    colors: [Color.oliveGreen.opacity(0.35), Color.oliveGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: avatarSize, height: avatarSize)
            .padding(2)
            .opacity(isUploading && uploadProgress > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: uploadProgress)
    }

    private var systemErrorRed: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemRed)
        #else
        Color.red
        #endif
    }

    @ViewBuilder
    private var errorRing: some View {
        if uploadError {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = sin(t * 4.2) * 0.5 + 0.5
                avatarShape
                    .stroke(systemErrorRed.opacity(0.55 + pulse * 0.4), lineWidth: 3)
                    .frame(width: avatarSize, height: avatarSize)
                    .shadow(color: systemErrorRed.opacity(0.35 + pulse * 0.45), radius: 6 + pulse * 12)
            }
        }
    }

    private func handlePhotosPickerItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let data: Data
        if let imported = try? await item.loadTransferable(type: ProfileImagePickerImport.self) {
            data = imported.data
        } else if let d = try? await item.loadTransferable(type: Data.self) {
            data = d
        } else {
            await MainActor.run {
                uploadError = true
                selectedItem = nil
            }
            return
        }
        await runUpload(with: data)
        await MainActor.run {
            selectedItem = nil
        }
    }

    @MainActor
    private func runUpload(with data: Data) async {
        localAvatarJPEG = data
        uploadError = false
        isUploading = true
        uploadProgress = 0
        successScale = 1

        let progressTask = Task { @MainActor in
            var p: CGFloat = 0
            while p < 0.92 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 70_000_000)
                p += 0.035
                uploadProgress = min(p, 0.92)
            }
        }

        do {
            try await onUpload(data)
            progressTask.cancel()
            uploadProgress = 1.0
            isUploading = false
            try? await Task.sleep(nanoseconds: 120_000_000)
            uploadProgress = 0
            withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                successScale = 1.1
            }
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                successScale = 1.0
            }
        } catch {
            progressTask.cancel()
            isUploading = false
            uploadProgress = 0
            uploadError = true
            localAvatarJPEG = nil
        }
    }
}

// MARK: - Photos import

private struct ProfileImagePickerImport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: UTType.image) { data in
            ProfileImagePickerImport(data: data)
        }
    }
}
