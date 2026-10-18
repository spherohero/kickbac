//
//  ContentView.swift
//  KickBAC
//
//  Created by Liam McAuliffe on 10/17/26.
//

import SwiftUI

struct ContentView: View {
    #if DEBUG
    @State private var selectedTab: AppTab = ProcessInfo.processInfo.arguments.contains("--show-profile") ? .me : .home
    #else
    @State private var selectedTab: AppTab = .home
    #endif
    @State private var showsOnboarding = false
    @State private var session = AuthSession()
    @State private var profile = ProfileStore()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", image: "NavHome", value: .home) {
                HomeView { showsOnboarding = true }
            }

            Tab("Party", image: "NavParty", value: .party) {
                blankPage
            }

            Tab("Me", image: "NavMe", value: .me) {
                AccountView(session: session, profile: profile) { showsOnboarding = true }
                    .background(pageBackground.ignoresSafeArea())
            }
        }
        .tint(.primary)
        .background(pageBackground.ignoresSafeArea())
        .tabBarMinimizeBehavior(.never)
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView()
                .environment(session)
                .environment(profile)
        }
        .task { await session.restore() }
        .onChange(of: session.profileOwner, initial: true) {
            profile.load(owner: session.profileOwner)
        }
        .task(id: session.profileOwner) {
            profile.load(owner: session.profileOwner)
            if session.isSignedIn && !showsOnboarding {
                await profile.refresh { try await session.loadProfile() }
            }
        }
        .onChange(of: profile.needsOnboarding) {
            if profile.needsOnboarding { showsOnboarding = true }
        }
        .task(id: session.generation) {
            if session.isSignedIn { await session.checkAPI() }
        }
        .preferredColorScheme(.dark)
    }

    private var blankPage: some View {
        pageBackground
            .ignoresSafeArea()
    }

    private var pageBackground: Color {
        Color("SplashBackground")
    }
}

private enum AppTab: Hashable {
    case home
    case party
    case me
}

#Preview("Dark") {
    ContentView()
}
