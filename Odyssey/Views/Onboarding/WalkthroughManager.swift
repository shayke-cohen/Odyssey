import SwiftUI

@Observable
@MainActor
final class WalkthroughManager {
    var isActive = false
    var currentIndex = 0
    var anchorFrames: [WalkthroughAnchorID: CGRect] = [:]

    let steps = WalkthroughStep.allSteps

    var currentStep: WalkthroughStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    var isLast: Bool { currentIndex == steps.count - 1 }

    var stepLabel: String {
        "Step \(currentIndex + 1) of \(steps.count)"
    }

    func start() {
        currentIndex = 0
        withAnimation(.easeIn(duration: 0.25)) { isActive = true }
    }

    func advance() {
        if isLast {
            complete()
        } else {
            withAnimation(.spring(duration: 0.35)) { currentIndex += 1 }
        }
    }

    func skip() { complete() }

    private func complete() {
        withAnimation(.easeOut(duration: 0.2)) { isActive = false }
        AppSettings.store.set(true, forKey: AppSettings.walkthroughShownKey)
    }
}
