//
//  AvatarView.swift
//  Intera
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
        guard let root = URL(string: AppConfiguration.messagingAPIRootTrimmed) else { return nil }
        let origin = root.deletingLastPathComponent().deletingLastPathComponent()
        if let u = URL(string: t, relativeTo: origin)?.absoluteURL { return u }
        // Some APIs omit the leading slash on app-relative paths.
        if !t.hasPrefix("/") {
            return URL(string: "/" + t, relativeTo: origin)?.absoluteURL
        }
        return nil
    }

    /// Prefer this for **AsyncImage** so full URLs with spaces / odd characters still load when possible.
    static func urlForAsyncImage(from raw: String?) -> URL? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return nil }
        if let u = absoluteHTTPURL(from: t) { return u }
        return url(from: t)
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
}

enum AvatarClipStyle: Equatable {
    case circle
    /// 1:1 image with optional continuous corner radius (use `0` for a sharp square).
    case square(cornerRadius: CGFloat = 6)
}

/// Empty-state avatar: olive **outline** `person` (same glyph family as the Profile hub tab’s `person.fill`).
struct InteraDefaultProfileAvatarGlyph: View {
    /// Outer size of the avatar slot (width and height of the clipped area).
    var slotDiameter: CGFloat

    private var iconFontSize: CGFloat {
        max(13, slotDiameter * 0.48)
    }

    var body: some View {
        ZStack {
            Color.oliveGreen.opacity(0.08)
            Image(systemName: "person")
                .font(InteraFont.system(size: iconFontSize, weight: .semibold))
                .foregroundStyle(Color.oliveGreen)
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
        InteraDefaultProfileAvatarGlyph(slotDiameter: size)
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
            .campusCutsStyle(.caption)
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
                    .campusCutsStyle(.bodyMedium)
                Spacer()
            }
        }
    }
    .padding()
}
