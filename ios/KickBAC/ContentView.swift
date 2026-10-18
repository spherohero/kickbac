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
    @State private var practice = PracticeReadingStore()
    @State private var showsDevice = false
    @State private var signInAfterDevice = false
    @State private var partyDeviceLink: PartyDeviceLink?
    @State private var pendingPartyDeviceLink: PartyDeviceLink?
    @State private var deviceLinkError: String?
    @State private var pendingScanDeviceID: String?
    @State private var nfcReadingID: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isRestoring {
                pageBackground.ignoresSafeArea()
                    .overlay { ProgressView("Loading KickBAC") }
            } else if !session.isSignedIn || showsOnboarding {
                OnboardingView(onComplete: completeOnboarding)
                    .environment(session)
                    .environment(profile)
            } else {
                tabs
                    .preferredColorScheme(.dark)
            }
        }
        .tint(.primary)
        .background(pageBackground.ignoresSafeArea())
        .tabBarMinimizeBehavior(.never)
        .sheet(isPresented: $showsDevice, onDismiss: {
            if signInAfterDevice { signInAfterDevice = false; showsOnboarding = true }
            if let link = pendingPartyDeviceLink {
                pendingPartyDeviceLink = nil
                selectedTab = .party
                partyDeviceLink = link
            }
        }) {
            DeviceConnectionView(session: session, flow: deviceFlow, onSignIn: {
                signInAfterDevice = true
                showsDevice = false
            }, onParty: { id, linkAsHost in
                pendingPartyDeviceLink = PartyDeviceLink(deviceID: id, linkAsHost: linkAsHost)
                showsDevice = false
            })
        }
        .task {
            await session.restore()
            if !session.isSignedIn {
                showsDevice = false
                showsOnboarding = true
            }
        }
        .onChange(of: session.isSignedIn) {
            if !session.isRestoring, !session.isSignedIn {
                showsDevice = false
                showsOnboarding = true
            }
        }
        .onChange(of: session.profileOwner, initial: true) {
            nfcReadingID = nil
            profile.load(owner: session.profileOwner)
            deviceFlow.switchOwner(session.profileOwner)
            practice.switchOwner(session.profileOwner)
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
        .task(id: scanTaskID) {
            guard let id = scanTaskID else { return }
            nfcReadingID = UUID()
            if pendingScanDeviceID == id { pendingScanDeviceID = nil }
        }
        .onOpenURL { url in
            guard let baseURL = session.apiBaseURL else { return }
            do {
                let id = try DeviceTarget.parseAppLink(url, baseURL: baseURL)
                if selectedTab == .party, !showsDevice, !showsOnboarding {
                    partyDeviceLink = PartyDeviceLink(deviceID: id, linkAsHost: false)
                    if !session.isRestoring && !session.isSignedIn { showsOnboarding = true }
                    return
                }
                if url.scheme?.lowercased() == "com.liam.kickbac" {
                    selectedTab = .home
                    showsDevice = false
                    pendingScanDeviceID = id
                    if !session.isRestoring && !session.isSignedIn { showsOnboarding = true }
                    return
                }
                if !deviceFlow.hasActiveSession || deviceFlow.targetID != id {
                    try deviceFlow.select(id, baseURL: baseURL)
                }
                selectedTab = .home
                if session.isSignedIn, !session.isRestoring, !showsOnboarding { showsDevice = true }
            } catch DeviceSessionStore.FlowError.activeTest {
                deviceLinkError = "Finish or cancel the current test before choosing another breathalyzer."
            } catch { /* Ignore unrelated URLs, including Auth0 callbacks. */ }
        }
        .alert("Current test in progress", isPresented: Binding(
            get: { deviceLinkError != nil }, set: { if !$0 { deviceLinkError = nil } }
        )) {
            Button("OK") { deviceLinkError = nil }
        } message: {
            Text(deviceLinkError ?? "")
        }
        .environment(practice)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", image: "NavHome", value: .home) {
                HomeView(session: session, deviceFlow: deviceFlow,
                         onRetryTest: { pendingScanDeviceID = deviceFlow.targetID },
                         nfcReadingID: nfcReadingID, onNFCReadingConsumed: { nfcReadingID = nil })
            }
            Tab("Party", image: "NavParty", value: .party) {
                PartyView(profile: profile, owner: session.profileOwner, session: session,
                          deviceFlow: deviceFlow, onSignIn: { showsOnboarding = true },
                          deviceLink: $partyDeviceLink, isSelected: selectedTab == .party)
            }
            Tab("Me", image: "NavMe", value: .me) {
                AccountView(session: session, profile: profile) { showsOnboarding = true }
                    .background(pageBackground.ignoresSafeArea())
            }
        }
    }

    private func completeOnboarding() {
        guard session.isSignedIn else { return }
        showsOnboarding = false
        if pendingScanDeviceID == nil, selectedTab != .party,
           deviceFlow.targetID != nil, profile.remoteState == .saved { showsDevice = true }
    }

    private var pageBackground: Color {
        Color("SplashBackground")
    }

    private var scanTaskID: String? {
        guard !session.isRestoring, session.isSignedIn, !showsOnboarding,
              scenePhase == .active else { return nil }
        return pendingScanDeviceID
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
