//
//  InteraTermsOfServiceAgreementSheet.swift
//  Intera
//
//  Fixed-height ScrollView for the Terms document (inline on signup). `reachedEnd` becomes true
//  when the reader scrolls the end marker into view — no expanding sheet.
//

import SwiftUI

private enum InteraTermsOfServiceReaderMetrics {
    /// Viewport height for the partially-open document; content scrolls inside.
    static let viewportHeight: CGFloat = 320
}

struct InteraTermsOfServiceDocumentScrollView: View {
    @Binding var reachedEnd: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(Array(InteraTermsOfService.sectionParagraphs.enumerated()), id: \.offset) { _, section in
                    Text(section)
                        .font(InteraFont.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Color.clear
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        reachedEnd = true
                    }
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: InteraTermsOfServiceReaderMetrics.viewportHeight)
        #if os(iOS)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        #endif
    }
}
