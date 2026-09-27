//
//  PulseIndicator.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine

public struct PulseIndicator: View {
    public let isActive: Bool
    public let color: Color

    @State private var isPulsing = false

    public init(isActive: Bool, color: Color = AppTheme.mintAccent) {
        self.isActive = isActive
        self.color = color
    }

    public var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.0 : 1.0)
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            Circle()
                .fill(isActive ? color : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
        .onAppear {
            if isActive {
                isPulsing = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            isPulsing = newValue
        }
    }
}
