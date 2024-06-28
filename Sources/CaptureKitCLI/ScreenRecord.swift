import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import ArgumentParser


struct Config: Codable {
    let fps: Int
    let showCursor: Bool
    let displayId: CGDirectDisplayID
}

@main
struct CaptureKitCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "capturekit",
        abstract: "A command-line tool for screen recording using ScreenCaptureKit"
    )

    func run() throws {
        let service = ScreenRecorderService()
        service.start()
        
        RunLoop.main.run()
    }
}

class ScreenRecorder: NSObject, SCStreamOutput {
    private let videoSampleBufferQueue = DispatchQueue(label: "ScreenRecorder.VideoSampleBufferQueue")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var stream: SCStream?
    
    private var sessionStarted = false
    private var firstSampleTime: CMTime = .zero
    private var lastSampleBuffer: CMSampleBuffer?
    
    private var config: Config?
    private var outputURL: URL?
    private var frameCount: Int = 0
    private var isRecording = false
    
    func startCapture(configJSON: String) async throws {
        guard !isRecording else {
            print("Recording is already in progress")
            return
        }

        guard let jsonData = configJSON.data(using: .utf8) else {
            throw NSError(domain: "ScreenCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        
        config = try JSONDecoder().decode(Config.self, from: jsonData)
        
        let availableContent = try await SCShareableContent.current
        print("Available displays: \(availableContent.displays.map { "\($0.displayID)" }.joined(separator: ", "))")
        
        guard let display = availableContent.displays.first(where: { $0.displayID == config?.displayId ?? CGMainDisplayID() }) else {
            throw NSError(domain: "ScreenCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Display not found"])
        }
        
        // Get display size and scale factor
        let displayBounds = CGDisplayBounds(display.displayID)
        let displaySize = displayBounds.size
        let displayScaleFactor: Int
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            displayScaleFactor = mode.pixelWidth / mode.width
        } else {
            displayScaleFactor = 1
        }
        
        // Calculate video size (downsized if necessary)
        let videoSize = ScreenRecorder.downsizedVideoSize(source: displaySize, scaleFactor: displayScaleFactor)
        
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = videoSize.width
        streamConfiguration.height = videoSize.height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config?.fps ?? 60))
        streamConfiguration.queueDepth = 6
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = config?.showCursor ?? false
        
        print("Display dimensions: \(videoSize.width)x\(videoSize.height)")
        print("FPS: \(config?.fps ?? 60)")
        print("Show cursor: \(config?.showCursor ?? false)")
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: nil)
        
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fileName = "output_\(Int(Date().timeIntervalSince1970)).mov"
        outputURL = currentDirectoryURL.appendingPathComponent(fileName)
        
        print("Output URL: \(outputURL?.path ?? "Unknown")")
        
        // Create AVAssetWriter for a QuickTime movie file
        guard let outputURL = outputURL else {
            throw NSError(domain: "ScreenCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid output URL"])
        }
        assetWriter = try AVAssetWriter(url: outputURL, fileType: .mov)
        
        // Setup video encoding settings
        guard let assistant = AVOutputSettingsAssistant(preset: .preset3840x2160) else {
            throw NSError(domain: "ScreenCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Can't create AVOutputSettingsAssistant"])
        }
        assistant.sourceVideoFormat = try CMVideoFormatDescription(videoCodecType: .h264, width: videoSize.width, height: videoSize.height)
        
        guard var outputSettings = assistant.videoSettings else {
            throw NSError(domain: "ScreenCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "AVOutputSettingsAssistant has no videoSettings"])
        }
        outputSettings[AVVideoWidthKey] = videoSize.width
        outputSettings[AVVideoHeightKey] = videoSize.height
        
        // Create AVAssetWriter input for video
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        guard let assetWriter = assetWriter, let videoInput = videoInput, assetWriter.canAdd(videoInput) else {
            throw NSError(domain: "ScreenCapture", code: 6, userInfo: [NSLocalizedDescriptionKey: "Can't add input to asset writer"])
        }
        assetWriter.add(videoInput)
        
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
        try await stream?.startCapture()
        
        guard assetWriter.startWriting() else {
            throw NSError(domain: "ScreenCapture", code: 7, userInfo: [NSLocalizedDescriptionKey: "Couldn't start writing to AVAssetWriter"])
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        sessionStarted = true
        isRecording = true
        frameCount = 0
        firstSampleTime = .zero
        
        print("Capture started.")
    }
    
    func stopCapture() async throws -> String {
        guard isRecording else {
            print("No recording in progress")
            return ""
        }

        isRecording = false
        
        try await stream?.stopCapture()
        stream = nil
        
        // Repeat the last frame to ensure the recording is of the expected length
        if let originalBuffer = lastSampleBuffer, let videoInput = videoInput {
            let additionalTime = CMTime(seconds: ProcessInfo.processInfo.systemUptime, preferredTimescale: 600) - firstSampleTime
            let timing = CMSampleTimingInfo(duration: originalBuffer.duration, presentationTimeStamp: additionalTime, decodeTimeStamp: originalBuffer.decodeTimeStamp)
            if let additionalSampleBuffer = try? CMSampleBuffer(copying: originalBuffer, withNewTiming: [timing]) {
                videoInput.append(additionalSampleBuffer)
            }
        }
        
        assetWriter?.endSession(atSourceTime: lastSampleBuffer?.presentationTimeStamp ?? .zero)
        videoInput?.markAsFinished()
        await assetWriter?.finishWriting()
        
        let outputPath = outputURL?.path ?? "Unknown"
        print("Recording saved to: \(outputPath)")
        print("Total frames captured: \(frameCount)")
        
        // Reset for next recording
        assetWriter = nil
        videoInput = nil
        sessionStarted = false
        
        return outputPath
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sessionStarted, type == .screen, sampleBuffer.isValid, isRecording else { return }
        
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachment = attachments.first,
              let statusRawValue = attachment[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else { return }
        
        if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
            if firstSampleTime == .zero {
                firstSampleTime = sampleBuffer.presentationTimeStamp
            }
            
            let lastSampleTime = sampleBuffer.presentationTimeStamp - firstSampleTime
            lastSampleBuffer = sampleBuffer
            
            let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: lastSampleTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            if let retimedSampleBuffer = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) {
                videoInput.append(retimedSampleBuffer)
                frameCount += 1
                if frameCount % 60 == 0 {
                    print("Frames captured: \(frameCount)")
                }
            } else {
                print("Couldn't copy CMSampleBuffer, dropping frame")
            }
        } else {
            print("AVAssetWriterInput isn't ready, dropping frame")
        }
    }
    
    private static func downsizedVideoSize(source: CGSize, scaleFactor: Int) -> (width: Int, height: Int) {
        let maxSize = CGSize(width: 4096, height: 2304)
        let w = source.width * Double(scaleFactor)
        let h = source.height * Double(scaleFactor)
        let r = max(w / maxSize.width, h / maxSize.height)
        return r > 1
            ? (width: Int(w / r), height: Int(h / r))
            : (width: Int(w), height: Int(h))
    }
}

class ScreenRecorderService {
    private let recorder = ScreenRecorder()
    private let commandQueue = DispatchQueue(label: "com.screenrecorder.commandQueue")
    
    func start() {
        print("ScreenRecorderService started. Available commands:")
        print("start {config_json} - Start recording")
        print("stop - Stop recording")
        print("exit - Exit the service")
        
        DispatchQueue.global().async {
            while let command = readLine() {
                self.handleCommand(command)
            }
        }
    }
    
    private func handleCommand(_ command: String) {
        let components = command.split(separator: " ", maxSplits: 1)
        guard let action = components.first else { return }
        
        switch action {
        case "start":
            guard components.count > 1 else {
                print("Error: Config JSON required for start command")
                return
            }
            let configJSON = String(components[1])
            commandQueue.async {
                Task {
                    do {
                        try await self.recorder.startCapture(configJSON: configJSON)
                    } catch {
                        print("Error starting capture: \(error)")
                    }
                }
            }
        case "stop":
            commandQueue.async {
                Task {
                    do {
                        let outputPath = try await self.recorder.stopCapture()
                        print("Recording stopped. Output path: \(outputPath)")
                    } catch {
                        print("Error stopping capture: \(error)")
                    }
                }
            }
        case "exit":
            print("Exiting ScreenRecorderService")
            exit(0)
        default:
            print("Unknown command: \(action)")
        }
    }
}