//
//  MainTabView.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine

public enum AppTab: Int, CaseIterable {
    case chat = 0
    case imageStudio = 1
    case modelHub = 2

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .imageStudio: return "Studio"
        case .modelHub: return "Hub"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .imageStudio: return "paintpalette.fill"
        case .modelHub: return "cylinder.split.1x2.fill"
        }
    }
}

// MARK: - Keyboard Visibility Observer

public final class KeyboardObserver: ObservableObject {
    @Published public var isKeyboardVisible = false
    private var cancellables = Set<AnyCancellable>()

    public init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self?.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self?.isKeyboardVisible = false
                }
            }
            .store(in: &cancellables)
    }
}

public struct MainTabView: View {
    @State private var selectedTab: AppTab = .chat
    @StateObject private var keyboardObserver = KeyboardObserver()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                ChatView(isKeyboardVisible: keyboardObserver.isKeyboardVisible)
                    .tag(AppTab.chat)

                ImageStudioView()
                    .tag(AppTab.imageStudio)

                ModelHubView()
                    .tag(AppTab.modelHub)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            if !keyboardObserver.isKeyboardVisible {
                customBottomTabBar
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Custom Floating Bottom Tab Bar

    private var customBottomTabBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button(action: {
                    if selectedTab != tab {
                        AppTheme.hapticImpact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    }
                }) {
                    ZStack {
                        if isSelected {
                            // Active Tab Pill
                            HStack(spacing: 7) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 15, weight: .bold))

                                Text(tab.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .fixedSize()
                            }
                            .foregroundColor(Color(red: 14/255, green: 16/255, blue: 19/255))
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(
                                Capsule()
                                    .fill(AppTheme.mintAccent)
                                    .shadow(color: AppTheme.mintAccent.opacity(0.4), radius: 10, x: 0, y: 3)
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .center)),
                                    removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .center))
                                )
                            )
                        } else {
                            // Inactive Tab: Perfect uniform circle
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(AppTheme.cardDark)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: 10)
        )
        .padding(.bottom, 12)
    }
}


