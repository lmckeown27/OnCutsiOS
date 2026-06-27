//
//  TabPicker.swift
//  Intera
//
//  Custom tab picker with underline indicator and badges
//

import SwiftUI

struct TabPicker<T: Hashable>: View {
    let tabs: [T]
    @Binding var selectedTab: T
    let titleFor: (T) -> String
    var badgeFor: ((T) -> Int?)? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, .space4)
        .padding(.top, .space2)
        .padding(.bottom, .space2)
    }
    
    private func tabButton(for tab: T) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: .space1) {
                HStack(spacing: .space1) {
                    Text(titleFor(tab))
                    
                    if let badgeCount = badgeFor?(tab), badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(InteraFont.captionSmall)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.brand)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .font(InteraFont.labelMedium)
                .fontWeight(selectedTab == tab ? .semibold : .regular)
                .foregroundStyle(selectedTab == tab ? Color.brand : Color.neutral500)
                .interaOliveGreenTextOutline(when: selectedTab == tab)
                
                Rectangle()
                    .fill(selectedTab == tab ? Color.brand : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

enum PreviewTab: String, CaseIterable {
    case browse = "Browse"
    case bookings = "My Bookings"
}

#Preview("No Badges") {
    @Previewable @State var selected: PreviewTab = .browse
    
    VStack {
        TabPicker(
            tabs: PreviewTab.allCases,
            selectedTab: $selected,
            titleFor: { $0.rawValue }
        )
        
        Spacer()
        
        Text("Selected: \(selected.rawValue)")
            .avilaPlatformsStyle(.bodyLarge)
    }
}

#Preview("With Badges") {
    @Previewable @State var selected: PreviewTab = .browse
    
    VStack {
        TabPicker(
            tabs: PreviewTab.allCases,
            selectedTab: $selected,
            titleFor: { $0.rawValue },
            badgeFor: { tab in
                tab == .bookings ? 3 : nil
            }
        )
        
        Spacer()
        
        Text("Selected: \(selected.rawValue)")
            .avilaPlatformsStyle(.bodyLarge)
    }
}

enum BarberTab: String, CaseIterable {
    case pending = "Pending"
    case upcoming = "Upcoming"
    case past = "Past"
}

#Preview("Barber Tabs") {
    @Previewable @State var selected: BarberTab = .pending
    
    VStack {
        TabPicker(
            tabs: BarberTab.allCases,
            selectedTab: $selected,
            titleFor: { $0.rawValue },
            badgeFor: { tab in
                switch tab {
                case .pending: return 5
                case .upcoming: return 2
                case .past: return nil
                }
            }
        )
        
        Spacer()
    }
}
