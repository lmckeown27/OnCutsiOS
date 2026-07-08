//
//  OnCutsChatImagePreparation.swift
//  OnCuts
//
//  Downscales and JPEG-compresses chat images before upload so requests stay under typical
//  reverse-proxy body limits (nginx default 1m) and upload is faster.
//

#if canImport(UIKit)
import UIKit

enum OnCutsChatImagePreparation {
    /// Pixels; long edge cap for full-resolution photos from library/camera.
    private static let maxLongEdge: CGFloat = 1920
    private static let jpegQuality: CGFloat = 0.78

    /// Returns data for multipart upload, MIME type, and a preview `UIImage` aligned with the encoded pixels.
    static func dataForChatUpload(image: UIImage, originalData: Data) -> (data: Data, mimeType: String, preview: UIImage) {
        let visual = scaleDownIfNeeded(image)
        if let jpeg = visual.jpegData(compressionQuality: Self.jpegQuality), !jpeg.isEmpty {
            return (jpeg, "image/jpeg", visual)
        }
        if let png = visual.pngData() {
            return (png, "image/png", visual)
        }
        let mime: String = originalData.isProbablyPNGMagic ? "image/png" : "image/jpeg"
        return (originalData, mime, image)
    }

    private static func scaleDownIfNeeded(_ image: UIImage) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let long = max(w, h)
        guard long > maxLongEdge, long > 0 else { return image }
        let ratio = maxLongEdge / long
        let newW = (w * ratio).rounded(.down)
        let newH = (h * ratio).rounded(.down)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newW, height: newH), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: newW, height: newH))
        }
    }
}

private extension Data {
    var isProbablyPNGMagic: Bool {
        let sig = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        return count >= sig.count && starts(with: sig)
    }
}
#endif
