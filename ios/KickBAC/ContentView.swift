//
//  ContentView.swift
//  KickBAC
//
//  Created by Liam McAuliffe on 10/17/26.
//

import SwiftUI

struct ContentView: View {
    #if DEBUG
    @State private var selectedTab: AppTab = ProcessInfo.processInfo.arguments.contains("--show-party") ? .party
        : ProcessInfo.processInfo.arguments.contains("--show-profile") ? .me : .home
    #else
    @State private var selectedTab: AppTab = .home
    #endif
    @State private var showsOnboarding = false
    @State private var session = AuthSession()
    @State private var profile = ProfileStore()
    @State private var deviceFlow = DeviceSessionStore()
    @State private var showsDevice = false
    @State private var signInAfterDevice = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", image: "NavHome", value: .home) {
                HomeView(session: session, deviceFlow: deviceFlow,
                         onConnect: { showsDevice = true }, onOnboarding: { showsOnboarding = true })
            }

            Tab("Party", image: "NavParty", value: .party) {
                PartyView(profile: profile, owner: session.profileOwner)
            }

            Tab("Me", image: "NavMe", value: .me) {
                AccountView(session: session, profile: profile) { showsOnboarding = true }
                    .background(pageBackground.ignoresSafeArea())
            }
        }
        .tint(.primary)
        .background(pageBackground.ignoresSafeArea())
        .tabBarMinimizeBehavior(.never)
        .sheet(isPresented: $showsDevice, onDismiss: {
            if signInAfterDevice { signInAfterDevice = false; showsOnboarding = true }
        }) {
            DeviceConnectionView(session: session, flow: deviceFlow) {
                signInAfterDevice = true
                showsDevice = false
            }
        }
        .fullScreenCover(isPresented: $showsOnboarding, onDismiss: {
            if session.isSignedIn, deviceFlow.targetID != nil, profile.remoteState == .saved { showsDevice = true }
        }) {
            OnboardingView()
                .environment(session)
                .environment(profile)
        }
        .task { await session.restore() }
        .onChange(of: session.profileOwner, initial: true) {
            profile.load(owner: session.profileOwner)
            deviceFlow.switchOwner(session.profileOwner)
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
        .task(id: session.generation) {
            if session.isSignedIn { await session.loadStats() }
        }
        .task(id: scenePhase == .active ? deviceFlow.pollID : nil) {
            if scenePhase == .active && session.isSignedIn {
                await deviceFlow.poll(fetch: { try await session.testSession($0) }, onComplete: { await session.checkAPI() })
            }
        }
        .onOpenURL { url in
            guard let baseURL = session.apiBaseURL else { return }
            do {
                try deviceFlow.select(url.absoluteString, baseURL: baseURL)
                selectedTab = .home
                if !showsOnboarding { showsDevice = true }
            } catch { /* Ignore unrelated URLs, including Auth0 callbacks. */ }
        }
        .preferredColorScheme(.dark)
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
