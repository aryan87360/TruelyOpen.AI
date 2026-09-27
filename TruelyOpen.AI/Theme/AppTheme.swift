//
//  AppTheme.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine
import UIKit

public struct AppTheme {
    // MARK: - Core Palette (Matte Charcoal & Vibrant Mint Neomorphic)

    /// Deep neutral obsidian canvas (#0E1013)
    public static let backgroundDark = Color(red: 14/255, green: 16/255, blue: 19/255)
    /// Elevated matte dark layer (#171920)
    public static let surfaceDark = Color(red: 23/255, green: 25/255, blue: 32/255)
    /// Primary matte charcoal container (#1F222B)
    public static let cardDark = Color(red: 31/255, green: 34/255, blue: 43/255)
    /// Elevated tactile card / chip (#282C37)
    public static let elevatedCardDark = Color(red: 40/255, green: 44/255, blue: 55/255)

    // Signature Hero Accent: Vibrant Mint / Emerald Jade (#1ED796)
    public static let mintAccent = Color(red: 30/255, green: 215/255, blue: 150/255)
    public static let mintDark = Color(red: 16/255, green: 124/255, blue: 84/255)
    public static let mintSoft = mintAccent.opacity(0.15)

    // Legacy alias mapped to new mint system for backwards compatibility
    public static let cyanAccent = mintAccent
    public static let emeraldAccent = mintAccent

    // Reference Pastel Accents (inspired by the reference palette)
    public static let pastelCream = Color(red: 246/255, green: 241/255, blue: 229/255)
    public static let pastelBlue = Color(red: 135/255, green: 174/255, blue: 253/255)
    public static let pastelPurple = Color(red: 196/255, green: 166/255, blue: 245/255)
    public static let pastelPink = Color(red: 242/255, green: 164/255, blue: 188/255)

    public static let purpleAccent = pastelPurple
    public static let roseAccent = Color(red: 255/255, green: 75/255, blue: 110/255)
    public static let amberAccent = Color(red: 255/255, green: 180/255, blue: 50/255)

    // Borders & Specular Highlights
    public static let borderSubtle = Color.white.opacity(0.065)
    public static let borderMedium = Color.white.opacity(0.12)
    public static let borderGlow = mintAccent.opacity(0.3)

    // MARK: - Gradients

    public static let primaryGradient = LinearGradient(
        colors: [mintAccent, Color(red: 20/255, green: 184/255, blue: 166/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let emeraldGradient = primaryGradient

    public static let roseGradient = LinearGradient(
        colors: [roseAccent, purpleAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let backgroundGradient = LinearGradient(
        colors: [
            backgroundDark,
            Color(red: 11/255, green: 13/255, blue: 16/255)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Haptics

    public static func hapticImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    public static func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - Tactile View Modifiers

public struct TactileCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var strokeColor: Color = AppTheme.borderSubtle
    var fillColor: Color = AppTheme.cardDark
    var shadowRadius: CGFloat = 14

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: shadowRadius, x: 0, y: 6)
            )
    }
}

public struct TactilePillModifier: ViewModifier {
    var strokeColor: Color = AppTheme.borderSubtle
    var fillColor: Color = AppTheme.cardDark

    public func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(fillColor)
                    .overlay(
                        Capsule()
                            .stroke(strokeColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
            )
    }
}

public extension View {
    func tactileCard(
        cornerRadius: CGFloat = 26,
        strokeColor: Color = AppTheme.borderSubtle,
        fillColor: Color = AppTheme.cardDark,
        shadowRadius: CGFloat = 14
    ) -> some View {
        self.modifier(TactileCardModifier(
            cornerRadius: cornerRadius,
            strokeColor: strokeColor,
            fillColor: fillColor,
            shadowRadius: shadowRadius
        ))
    }

    func tactilePill(
        strokeColor: Color = AppTheme.borderSubtle,
        fillColor: Color = AppTheme.cardDark
    ) -> some View {
        self.modifier(TactilePillModifier(strokeColor: strokeColor, fillColor: fillColor))
    }

    // GlassCard alias updated to use tactile matte continuous surfaces
    func glassCard(
        cornerRadius: CGFloat = 26,
        strokeColor: Color = AppTheme.borderSubtle,
        fillColor: Color = AppTheme.cardDark
    ) -> some View {
        self.modifier(TactileCardModifier(
            cornerRadius: cornerRadius,
            strokeColor: strokeColor,
            fillColor: fillColor,
            shadowRadius: 12
        ))
    }
}
