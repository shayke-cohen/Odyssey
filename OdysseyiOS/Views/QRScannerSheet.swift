// OdysseyiOS/Views/QRScannerSheet.swift
import SwiftUI
import VisionKit

/// Full-screen QR scanner that fires onCode(_:) with the raw string value of the
/// first QR code found, then dismisses itself.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            _DataScannerRepresentable(onCode: { code in
                onCode(code)
                dismiss()
            })
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .padding()
                }
                .accessibilityIdentifier("pairing.qrScanner.closeButton")
                .accessibilityLabel("Close scanner")
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Camera not available")
                    .font(.headline)
                Text("QR scanning requires a device with a camera.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// MARK: - UIViewControllerRepresentable wrapper

private struct _DataScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        guard !vc.isScanning else { return }
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var fired = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue {
                    fired = true
                    dataScanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}
