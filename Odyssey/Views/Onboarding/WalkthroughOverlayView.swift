import SwiftUI

// MARK: - Root overlay

struct WalkthroughOverlayView: View {
    @Environment(WalkthroughManager.self) private var manager

    var body: some View {
        GeometryReader { geo in
            if let step = manager.currentStep {
                let frame = manager.anchorFrames[step.id] ?? .zero
                ZStack {
                    SpotlightLayer(targetFrame: frame, windowSize: geo.size)
                    TooltipLayer(step: step, targetFrame: frame, windowSize: geo.size, manager: manager)
                }
            }
        }
        .ignoresSafeArea()
        .onKeyPress(.escape) { manager.skip(); return .handled }
        .onKeyPress(.rightArrow) { manager.advance(); return .handled }
        .accessibilityIdentifier("walkthrough.overlay")
    }
}

// MARK: - Spotlight (dark bg + cutout)

private struct SpotlightLayer: View {
    let targetFrame: CGRect
    let windowSize: CGSize

    private let padding: CGFloat = 6
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Canvas { ctx, size in
            // Full dark background
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.72))
            )
            // Punch cutout with destinationOut blend
            var cutout = Path()
            let inset = targetFrame.insetBy(dx: -padding, dy: -padding)
            cutout.addRoundedRect(in: inset, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            ctx.blendMode = .destinationOut
            ctx.fill(cutout, with: .color(.white))
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.35), value: targetFrame)
    }
}

// MARK: - Tooltip layer

private struct TooltipLayer: View {
    let step: WalkthroughStep
    let targetFrame: CGRect
    let windowSize: CGSize
    let manager: WalkthroughManager

    private let tooltipWidth: CGFloat = 260
    private let tooltipPad: CGFloat = 12
    private let arrowSize: CGFloat = 8
    private let spotlightPad: CGFloat = 6

    var body: some View {
        let placement = computePlacement()
        ZStack(alignment: .topLeading) {
            tooltipBubble
                .frame(width: tooltipWidth)
                .position(x: placement.tipCenter.x, y: placement.tipCenter.y)

            ArrowShape(side: placement.arrowSide)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .frame(width: arrowSize * 2, height: arrowSize)
                .position(x: placement.arrowPos.x, y: placement.arrowPos.y)
        }
        .animation(.spring(duration: 0.35), value: targetFrame)
    }

    // MARK: Bubble content

    private var tooltipBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manager.stepLabel.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("walkthrough.stepLabel")

            Text(step.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("walkthrough.stepTitle")

            Text(step.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use when: \(step.whenToUse)")
                .font(.caption)
                .italic()
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 4) {
                    ForEach(0..<manager.steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == manager.currentIndex
                                  ? Color.accentColor
                                  : Color.primary.opacity(0.15))
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                Button("Skip") { manager.skip() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityIdentifier("walkthrough.skipButton")

                Button(manager.isLast ? "Done" : "Next →") { manager.advance() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
                    .padding(.leading, 6)
                    .accessibilityIdentifier("walkthrough.nextButton")
            }
        }
        .padding(tooltipPad)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Layout computation

    private struct Placement {
        let tipCenter: CGPoint
        let arrowPos: CGPoint
        let arrowSide: ArrowSide
    }

    private func computePlacement() -> Placement {
        let cutout = targetFrame.insetBy(dx: -spotlightPad, dy: -spotlightPad)
        let tipH: CGFloat = 200  // estimated tooltip height
        let gap: CGFloat = arrowSize + 4

        // Try preferred side, fall back if out of bounds
        let sides: [WalkthroughTooltipSide] = [step.preferredSide, .right, .left, .below, .above]
        for side in sides {
            if let placement = placement(for: side, cutout: cutout, tipH: tipH, gap: gap) {
                return placement
            }
        }
        // Guaranteed fallback: center of window
        return Placement(
            tipCenter: CGPoint(x: windowSize.width / 2, y: windowSize.height / 2),
            arrowPos: CGPoint(x: windowSize.width / 2, y: windowSize.height / 2 - tipH / 2),
            arrowSide: .top
        )
    }

    private func placement(
        for side: WalkthroughTooltipSide,
        cutout: CGRect,
        tipH: CGFloat,
        gap: CGFloat
    ) -> Placement? {
        let halfW = tooltipWidth / 2
        let halfH = tipH / 2
        let margin: CGFloat = 12

        switch side {
        case .right:
            let x = cutout.maxX + gap + halfW
            guard x + halfW + margin < windowSize.width else { return nil }
            let y = (cutout.midY).clamped(to: halfH + margin...(windowSize.height - halfH - margin))
            let arrowX = cutout.maxX + gap - arrowSize / 2
            let arrowY = cutout.midY
            return Placement(
                tipCenter: CGPoint(x: x, y: y),
                arrowPos: CGPoint(x: arrowX, y: arrowY),
                arrowSide: .left
            )

        case .left:
            let x = cutout.minX - gap - halfW
            guard x - halfW - margin > 0 else { return nil }
            let y = (cutout.midY).clamped(to: halfH + margin...(windowSize.height - halfH - margin))
            let arrowX = cutout.minX - gap + arrowSize / 2
            let arrowY = cutout.midY
            return Placement(
                tipCenter: CGPoint(x: x, y: y),
                arrowPos: CGPoint(x: arrowX, y: arrowY),
                arrowSide: .right
            )

        case .above:
            let y = cutout.minY - gap - halfH
            guard y - halfH - margin > 0 else { return nil }
            let x = (cutout.midX).clamped(to: halfW + margin...(windowSize.width - halfW - margin))
            let arrowX = cutout.midX
            let arrowY = cutout.minY - gap + arrowSize / 2
            return Placement(
                tipCenter: CGPoint(x: x, y: y),
                arrowPos: CGPoint(x: arrowX, y: arrowY),
                arrowSide: .bottom
            )

        case .below:
            let y = cutout.maxY + gap + halfH
            guard y + halfH + margin < windowSize.height else { return nil }
            let x = (cutout.midX).clamped(to: halfW + margin...(windowSize.width - halfW - margin))
            let arrowX = cutout.midX
            let arrowY = cutout.maxY + gap - arrowSize / 2
            return Placement(
                tipCenter: CGPoint(x: x, y: y),
                arrowPos: CGPoint(x: arrowX, y: arrowY),
                arrowSide: .top
            )
        }
    }
}

// MARK: - Arrow shape

enum ArrowSide { case left, right, top, bottom }

private struct ArrowShape: Shape {
    let side: ArrowSide

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Comparable clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
