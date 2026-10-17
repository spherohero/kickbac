//
//  ContentView.swift
//  KickBAC
//
//  Created by Liam McAuliffe on 10/17/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var systemAppearance
    @State private var appearance: ColorScheme?
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", image: "NavHome", value: .home) {
                blankPage
            }

            Tab("Party", image: "NavParty", value: .party) {
                blankPage
            }

            Tab("Me", image: "NavMe", value: .me) {
                blankPage
            }
        }
        .tint(.primary)
        .tabBarMinimizeBehavior(.never)
        .overlay(alignment: .topTrailing) {
            appearanceButton
                .padding(.top, 12)
                .padding(.trailing, 20)
        }
        .preferredColorScheme(appearance)
    }

    private var blankPage: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }

    private var appearanceButton: some View {
        let isDark = (appearance ?? systemAppearance) == .dark

        return Button(isDark ? "Light mode" : "Dark mode") {
            appearance = isDark ? .light : .dark
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.glass)
        .controlSize(.small)
        .accessibilityIdentifier("appearanceToggle")
    }
}

private enum AppTab: Hashable {
    case home
    case party
    case me
}

#Preview("Light") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
