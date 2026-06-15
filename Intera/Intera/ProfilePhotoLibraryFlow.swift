//
//  ProfilePhotoLibraryFlow.swift
//  Intera
//
//  Photo library pick (full image) + square crop overlay (matches profile avatar; drag to position).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS) || os(visionOS)

// MARK: - UIImagePickerController (library, no system crop)

struct ProfileLibraryImagePicker: UIViewControllerRepresentable {
    /// Set to `false` when the user cancels; on success only `onImagePicked` runs (sheet stays open for crop).
    @Binding var isPresented: Bool
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileLibraryImagePicker

        init(_ parent: ProfileLibraryImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.isPresented = false
                return
            }
            parent.onImagePicked(image)
        }
    }
}

// MARK: - Full image + draggable square crop (WYSIWYG vs profile avatar)

/// On-screen crop matches `LiquidProfileUpload` / `AvatarView` square avatars.
private enum ProfileAvatarCropMetrics {
    static let displayDiameter: CGFloat = 120
    /// Same as `AvatarView` `clipStyle: .square(cornerRadius:)` / `LiquidProfileUpload.avatarCornerRadius`.
    static let displayCornerRadius: CGFloat = 15

    static func cropSquareCornerRadius(canvasSquareSide: CGFloat) -> CGFloat {
        let s = max(canvasSquareSide, 1)
        let scaled = displayCornerRadius * s / displayDiameter
        return min(scaled, s / 2 - 0.5)
    }
}

struct ProfileCircularCropSheet: View {
    let image: UIImage
    var onUsePhoto: (UIImage) -> Void
    var onChooseDifferent: () -> Void

    private let exportSide: CGFloat = 1024

    /// Fitted image rect in the crop canvas (matches `scaledToFit` placement).
    @State private var layoutImageRect: CGRect = .zero
    /// Circle center in canvas coordinates (same space as `layoutImageRect`).
    @State private var circleCenter: CGPoint = .zero
    @State private var circleRadius: CGFloat = ProfileAvatarCropMetrics.displayDiameter / 2
    @State private var dragBase: CGPoint = .zero
    @State private var didPlaceCircle = false

    private var iw: CGFloat { max(image.size.width, 1) }
    private var ih: CGFloat { max(image.size.height, 1) }

    private static func aspectFit(imageSize: CGSize, in bounding: CGSize) -> CGRect {
        let ix = max(imageSize.width, 1)
        let iy = max(imageSize.height, 1)
        let scale = min(bounding.width / ix, bounding.height / iy)
        let w = ix * scale
        let h = iy * scale
        let x = (bounding.width - w) / 2
        let y = (bounding.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func clampCenter(_ c: CGPoint, radius: CGFloat, imageRect: CGRect) -> CGPoint {
        let inset = imageRect.insetBy(dx: radius, dy: radius)
        guard inset.minX <= inset.maxX, inset.minY <= inset.maxY else { return CGPoint(x: imageRect.midX, y: imageRect.midY) }
        return CGPoint(
            x: min(max(c.x, inset.minX), inset.maxX),
            y: min(max(c.y, inset.minY), inset.maxY)
        )
    }

    /// Diameter matches profile avatar (120pt), but never larger than the fitted image.
    private static func cropCircleRadius(for imageRect: CGRect) -> CGFloat {
        let maxD = min(imageRect.width, imageRect.height)
        let d = min(ProfileAvatarCropMetrics.displayDiameter, maxD)
        return d / 2
    }

    private func syncLayoutAndCircle(imageRect: CGRect) {
        layoutImageRect = imageRect
        let r = Self.cropCircleRadius(for: imageRect)
        circleRadius = r
        if !didPlaceCircle {
            circleCenter = CGPoint(x: imageRect.midX, y: imageRect.midY)
            dragBase = circleCenter
            didPlaceCircle = true
        } else {
            circleCenter = clampCenter(circleCenter, radius: r, imageRect: imageRect)
            dragBase = circleCenter
        }
    }

    private func exportCroppedImage() -> UIImage? {
        let imageRect = layoutImageRect
        guard imageRect.width > 1, imageRect.height > 1 else { return nil }

        let imgW = image.size.width
        let imgH = image.size.height
        let s = imgW / imageRect.width
        let cx = (circleCenter.x - imageRect.minX) * s
        let cy = (circleCenter.y - imageRect.minY) * s
        let r = circleRadius * s
        let side = 2 * r
        guard side > 2 else { return nil }

        let crop = CGRect(x: cx - r, y: cy - r, width: side, height: side)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let out = CGSize(width: exportSide, height: exportSide)
        let renderer = UIGraphicsImageRenderer(size: out, format: format)
        return renderer.image { _ in
            let scale = exportSide / side
            let draw = CGRect(
                x: -crop.origin.x * scale,
                y: -crop.origin.y * scale,
                width: imgW * scale,
                height: imgH * scale
            )
            image.draw(in: draw)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("The frame matches your profile picture. Drag to choose what appears in your avatar.")
                    .font(InteraFont.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GeometryReader { geo in
                    let imageRect = Self.aspectFit(imageSize: CGSize(width: iw, height: ih), in: geo.size)
                    let cropSide = circleRadius * 2
                    let cropCorner = ProfileAvatarCropMetrics.cropSquareCornerRadius(canvasSquareSide: cropSide)
                    ZStack {
                        Color(uiColor: .secondarySystemFill)

                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)

                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geo.size))
                            let cropRect = CGRect(
                                x: circleCenter.x - circleRadius,
                                y: circleCenter.y - circleRadius,
                                width: cropSide,
                                height: cropSide
                            )
                            path.addRoundedRect(in: cropRect, cornerSize: CGSize(width: cropCorner, height: cropCorner), style: .continuous)
                        }
                        .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                        RoundedRectangle(cornerRadius: cropCorner, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: cropSide, height: cropSide)
                            .position(circleCenter)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { g in
                                let next = CGPoint(
                                    x: dragBase.x + g.translation.width,
                                    y: dragBase.y + g.translation.height
                                )
                                circleCenter = clampCenter(next, radius: circleRadius, imageRect: imageRect)
                            }
                            .onEnded { _ in
                                dragBase = circleCenter
                            }
                    )
                    .onAppear {
                        syncLayoutAndCircle(imageRect: imageRect)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        let ir = Self.aspectFit(imageSize: CGSize(width: iw, height: ih), in: newSize)
                        syncLayoutAndCircle(imageRect: ir)
                    }
                }
                .frame(minHeight: 320, maxHeight: 440)
                .background(Color(uiColor: .systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        if let out = exportCroppedImage() {
                            onUsePhoto(out)
                        }
                    } label: {
                        Text("Use This Photo")
                            .font(InteraFont.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.oliveGreen)

                    Button("Choose Different Photo", action: onChooseDifferent)
                        .font(InteraFont.body.weight(.medium))
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#endif
