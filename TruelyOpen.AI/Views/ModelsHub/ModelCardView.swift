//
//  ModelCardView.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine

public struct ModelCardView: View {
    public let title: String
    public let subtitle: String
    public let size: String
    public let parameterCount: String?
    public let isRecommended: Bool
    public let isDownloaded: Bool
    public let isDownloading: Bool
    public let downloadProgress: Double
    public let speedText: String
    public let onDownload: () -> Void
    public let onCancel: () -> Void
    public let onDelete: () -> Void

    public init(
        title: String,
        subtitle: String,
        size: String,
        parameterCount: String? = nil,
        isRecommended: Bool = false,
        isDownloaded: Bool,
        isDownloading: Bool,
        downloadProgress: Double = 0.0,
        speedText: String = "",
        onDownload: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.parameterCount = parameterCount
        self.isRecommended = isRecommended
        self.isDownloaded = isDownloaded
        self.isDownloading = isDownloading
        self.downloadProgress = downloadProgress
        self.speedText = speedText
        self.onDownload = onDownload
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .top, spacing: 12) {
                // Squircle Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.elevatedCardDark)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isDownloaded ? AppTheme.mintAccent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                        )

                    Image(systemName: parameterCount != nil ? "cpu.fill" : "photo.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isDownloaded ? AppTheme.mintAccent : .white.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        if let params = parameterCount {
                            Text("\(params) Params")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.mintAccent)
                        }

                        Text("•  \(size)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()
            }

            // Description
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(2)

            // Progress or Action Row
            if isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(speedText.isEmpty ? "Downloading weights..." : speedText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.mintAccent)
                        Spacer()
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    ProgressView(value: downloadProgress)
                        .tint(AppTheme.mintAccent)

                    Button("Cancel Download", role: .cancel, action: onCancel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.roseAccent)
                        .padding(.top, 4)
                }
                .padding(.top, 4)
            } else if isDownloaded {
                HStack {
                    Spacer()
                    Button(action: onDelete) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("Delete from Device")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.roseAccent.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.roseAccent.opacity(0.1))
                        )
                    }
                }
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download Model (\(size))")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 14/255, green: 16/255, blue: 19/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.mintAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: AppTheme.mintAccent.opacity(0.2), radius: 8, x: 0, y: 4)
                }
            }
        }
        .padding(18)
        .tactileCard(
            cornerRadius: 22,
            strokeColor: isDownloaded ? AppTheme.mintAccent.opacity(0.2) : Color.white.opacity(0.06)
        )
    }
}

