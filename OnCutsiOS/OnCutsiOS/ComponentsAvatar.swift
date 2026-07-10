//
//  AvatarView.swift
//  OnCuts
//
//  Avatar component with olive outline person placeholder when no photo (or image load fails).
//

import SwiftUI

/// Resolves stored profile picture strings (absolute or app-relative) for `AsyncImage` and toolbar avatars.
enum ProfileImageURLResolver {
    static func url(from raw: String?) -> URL? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return nil }
        if let absolute = absoluteHTTPURL(from: t) { return absolute }
        if t.hasPrefix("uploads/") {
            return url(from: "/api/" + t)
        }
        guard let root = URL(string: AppConfiguration.messagingAPIRootTrimmed) else {
            return s3PublicURL(from: t)
        }
        let origin = root.deletingLastPathComponent().deletingLastPathComponent()
        if let u = URL(string: t, relativeTo: origin)?.absoluteURL { return u }
        // Some APIs omit the leading slash on app-relative paths.
        if !t.hasPrefix("/") {
            if let u = URL(string: "/" + t, relativeTo: origin)?.absoluteURL { return u }
        }
        return s3PublicURL(from: t)
    }

    /// Prefer this for **AsyncImage** so full URLs with spaces / odd characters still load when possible.
    static func urlForAsyncImage(from raw: String?) -> URL? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return nil }
        if let u = absoluteHTTPURL(from: t) { return u }
        return url(from: t)
    }

    /// Stores a fetchable absolute URL string on models (list + detail share the same value).
    static func normalizedStorageString(from raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return nil }
        return urlForAsyncImage(from: t)?.absoluteString ?? t
    }

    private static func absoluteHTTPURL(from t: String) -> URL? {
        if t.hasPrefix("//"), let u = URL(string: "https:" + t) { return u }
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            if let u = URL(string: t), u.scheme != nil { return u }
            if #available(iOS 17.0, macOS 14.0, *) {
                return URL(string: t, encodingInvalidCharacters: true)
            }
        }
        return nil
    }

    /// Bare S3 object keys and legacy filenames (`abc.webp`) stored on `users.avatarUrl`.
    private static func s3PublicURL(from stored: String) -> URL? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }
        let key = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard !key.isEmpty else { return nil }
        let encoded = key.split(separator: "/").map { segment in
            String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
        }.joined(separator: "/")
        return URL(string: "https://campuscut-images.s3.us-west-1.amazonaws.com/\(encoded)")
    }
}

/// Square provider thumb for browse cards (resolves app-relative avatar URLs + reloads reliably in `LazyVStack`).
struct ServiceProviderProfileThumbnail: View {
    let imageUrl: String?
    let businessName: String
    var size: CGFloat = 80
    var cornerRadius: CGFloat = 12

    private var resolvedURL: URL? {
        ProfileImageURLResolver.urlForAsyncImage(from: imageUrl)
    }

    var body: some View {
        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        loadingPlaceholder
                    case .failure:
                        initialsPlaceholder
                    @unknown default:
                        loadingPlaceholder
                    }
                }
                .id(resolvedURL.absoluteString)
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var loadingPlaceholder: some View {
        Rectangle()
            .fill(Color.brand.opacity(0.2))
            .overlay {
                OnCutsDefaultProfileAvatarGlyph(slotDiameter: size)
            }
    }

    private var initialsPlaceholder: some View {
        Rectangle()
            .fill(Color.brand.opacity(0.2))
            .overlay {
                Text(businessName.prefix(2).uppercased())
                    .font(
                        size >= 100
                            ? OnCutsFont.title
                            : (size >= 72 ? OnCutsFont.headline : OnCutsFont.caption(weight: .bold))
                    )
                    .foregroundStyleOliveGreen()
            }
    }
}

enum AvatarClipStyle: Equatable {
    case circle
    /// 1:1 image with optional continuous corner radius (use `0` for a sharp square).
    case square(cornerRadius: CGFloat = 6)
}

/// Empty-state avatar: olive **outline** `person` (same glyph family as the Profile hub tab’s `person.fill`).
struct OnCutsDefaultProfileAvatarGlyph: View {
    /// Outer size of the avatar slot (width and height of the clipped area).
    var slotDiameter: CGFloat

    private var iconFontSize: CGFloat {
        max(13, slotDiameter * 0.48)
    }

    var body: some View {
        ZStack {
            Color.oliveGreen.opacity(0.08)
            Image(systemName: "person")
                .font(OnCutsFont.system(size: iconFontSize, weight: .semibold))
                .foregroundStyleOnCutsShellIconSecondary()
        }
        .accessibilityHidden(true)
    }
}

struct AvatarView: View {
    let imageUrl: String?
    let name: String
    var size: CGFloat = 48
    var fontSize: CGFloat?
    var clipStyle: AvatarClipStyle = .circle

    private var resolvedImageURL: URL? {
        ProfileImageURLResolver.urlForAsyncImage(from: imageUrl)
    }
    
    var body: some View {
        Group {
            if let imageURL = resolvedImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        placeholderGlyph
                    @unknown default:
                        placeholderGlyph
                    }
                }
            } else {
                placeholderGlyph
            }
        }
        .id(imageUrl ?? "")
        .frame(width: size, height: size)
        .modifier(AvatarClipModifier(style: clipStyle))
        .accessibilityLabel(accessibilityLabel)
    }

    private var placeholderGlyph: some View {
        OnCutsDefaultProfileAvatarGlyph(slotDiameter: size)
    }

    private var accessibilityLabel: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "Profile" }
        return "\(n) profile"
    }
}

private struct AvatarClipModifier: ViewModifier {
    let style: AvatarClipStyle

    func body(content: Content) -> some View {
        switch style {
        case .circle:
            content.clipShape(Circle())
        case .square(let cornerRadius):
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Preview

#Preview("Sizes") {
    VStack(spacing: .space4) {
        HStack(spacing: .space4) {
            AvatarView(imageUrl: nil, name: "Alex Johnson", size: 32)
            AvatarView(imageUrl: nil, name: "Maria Garcia", size: 48)
            AvatarView(imageUrl: nil, name: "Jordan Smith", size: 64)
            AvatarView(imageUrl: nil, name: "Taylor Lee", size: 80)
        }
        
        Text("With profile outline placeholder")
            .onCutsStyle(.caption)
    }
    .padding()
}

#Preview("Names") {
    VStack(spacing: .space4) {
        ForEach([
            "Alex Johnson",
            "Maria",
            "Jordan Smith-Lee",
            "T"
        ], id: \.self) { name in
            HStack {
                AvatarView(imageUrl: nil, name: name, size: 48)
                Text(name)
                    .onCutsStyle(.bodyMedium)
                Spacer()
            }
        }
    }
    .padding()
}
