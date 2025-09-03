//
//  StepProgressBar.swift
//  ReelQuick
//
//  Animated stepped progress bar for media categories
//

import SwiftUI

struct StepProgressBar: View {
    @Binding var selection: MediaState
    var counts: MediaCounts
    var isScanning: Bool = false
    var scanProgress: Double = 0.0

    @Environment(\.colorScheme) private var colorScheme

    private let circleSize: CGFloat = 34
    private let lineHeight: CGFloat = 6
    private let sidePadding: CGFloat = 16
    private let verticalPadding: CGFloat = 10

    private var steps: [MediaState] { MediaState.allCases }
    private var selectedIndex: Int { steps.firstIndex(of: selection) ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ZStack {
                // Background card
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)

                VStack(spacing: 0) {
                    // Title labels
                    ZStack(alignment: .leading) {
                        ForEach(Array(steps.enumerated()), id: \.element) { index, state in
                            let startX = sidePadding + circleSize / 2
                            let endX = totalWidth - sidePadding - circleSize / 2
                            let trackLength = max(0, endX - startX)
                            let fraction = steps.count > 1 ? CGFloat(index) / CGFloat(steps.count - 1) : 0
                            let centerX = startX + fraction * trackLength

                            Text(state.rawValue)
                                .font(.footnote.weight(index == selectedIndex ? .semibold : .regular))
                                .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                                .animation(.easeInOut(duration: 0.2), value: selectedIndex)
                                .fixedSize(horizontal: true, vertical: false)
                                .lineLimit(1)
                                .position(x: centerX, y: 10)
                        }
                    }
                    .frame(width: totalWidth, height: 20)
                    .padding(.top, 12)

                    // Progress track and bubbles
                    ZStack {
                        // Background track
                        GeometryReader { _ in
                            Path { path in
                                path.move(to: CGPoint(x: sidePadding + circleSize / 2, y: circleSize / 2))
                                path.addLine(to: CGPoint(x: totalWidth - sidePadding - circleSize / 2, y: circleSize / 2))
                            }
                            .stroke(Color.gray.opacity(0.2), lineWidth: lineHeight)
                        }
                        .frame(height: circleSize)

                        // Filled track
                        GeometryReader { _ in
                            Path { path in
                                let startX = sidePadding + circleSize / 2
                                let endXFull = totalWidth - sidePadding - circleSize / 2
                                let trackLength = max(0, endXFull - startX)
                                let fraction = steps.count > 1 ? CGFloat(selectedIndex) / CGFloat(steps.count - 1) : 0
                                let endX = startX + fraction * trackLength
                                
                                path.move(to: CGPoint(x: startX, y: circleSize / 2))
                                path.addLine(to: CGPoint(x: endX, y: circleSize / 2))
                            }
                            .stroke(AppColors.primary, lineWidth: lineHeight)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedIndex)
                        }
                        .frame(height: circleSize)

                        // Step bubbles
                        HStack(spacing: 0) {
                            ForEach(Array(steps.enumerated()), id: \.element) { index, state in
                                ZStack {
                                    Circle()
                                        .fill(index <= selectedIndex ? AppColors.primary : Color.gray.opacity(0.3))
                                        .frame(width: circleSize, height: circleSize)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedIndex)

                                    if index <= selectedIndex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selection = state
                                    }
                                }

                                if index < steps.count - 1 {
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, sidePadding)
                    }
                    .padding(.vertical, verticalPadding)

                    // Count labels
                    ZStack(alignment: .leading) {
                        ForEach(Array(steps.enumerated()), id: \.element) { index, state in
                            let startX = sidePadding + circleSize / 2
                            let endX = totalWidth - sidePadding - circleSize / 2
                            let trackLength = max(0, endX - startX)
                            let fraction = steps.count > 1 ? CGFloat(index) / CGFloat(steps.count - 1) : 0
                            let centerX = startX + fraction * trackLength
                            let count = counts.count(for: state)

                            Text("\(count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .position(x: centerX, y: 6)
                        }
                    }
                    .frame(width: totalWidth, height: 12)
                    .padding(.bottom, 12)

                    // Scanning progress (only for flagged state)
                    if isScanning && selection == .flagged {
                        VStack(spacing: 4) {
                            ProgressView(value: scanProgress)
                                .tint(AppColors.primary)
                            Text("Scanning: \(Int(scanProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, sidePadding)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
        .frame(height: isScanning && selection == .flagged ? 140 : 120)
        .animation(.easeInOut(duration: 0.3), value: isScanning)
    }
}

