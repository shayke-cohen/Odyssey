import Foundation
import Speech
import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceInputService: NSObject {
    // MARK: - Published state
    var isRecording: Bool = false
    var partialTranscript: String = ""
    var audioLevel: Float = 0.0   // 0.0–1.0, for waveform animation
    var permissionGranted: Bool = false
    var error: Error?

    // MARK: - Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        // Request SFSpeechRecognizer authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            permissionGranted = false
            return false
        }

        // Request microphone access
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        permissionGranted = micGranted
        return micGranted
    }

    // MARK: - Recording
    func startRecording() async {
        guard !isRecording else { return }

        // Request permissions if not yet granted
        if !permissionGranted {
            let granted = await requestPermissions()
            guard granted else {
                self.error = VoiceInputError.permissionDenied
                return
            }
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            self.error = VoiceInputError.recognizerUnavailable
            return
        }

        do {
            try await startAudioEngine(recognizer: recognizer)
        } catch {
            self.error = error
        }
    }

    func stopRecording() async -> String {
        guard isRecording else { return partialTranscript }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.0

        let result = partialTranscript
        // Don't clear partialTranscript here — ChatView reads it to inject into text field
        return result
    }

    // MARK: - Private implementation
    private func startAudioEngine(recognizer: SFSpeechRecognizer) async throws {
        // Reset any existing state
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        partialTranscript = ""
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // on-device only, privacy-preserving
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)

            // Compute RMS audio level for waveform animation
            let channelData = buffer.floatChannelData?[0]
            let frameCount = Int(buffer.frameLength)
            if let channelData, frameCount > 0 {
                var rms: Float = 0.0
                for i in 0..<frameCount {
                    rms += channelData[i] * channelData[i]
                }
                rms = sqrt(rms / Float(frameCount))
                let normalized = min(rms * 10.0, 1.0)  // scale to 0–1
                Task { @MainActor [weak self] in
                    self?.audioLevel = normalized
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                }
                if let error {
                    // Ignore cancellation errors (triggered by stopRecording)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        self.error = error
                    }
                }
            }
        }
    }
}

// MARK: - Errors
enum VoiceInputError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission was denied."
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        }
    }
}
