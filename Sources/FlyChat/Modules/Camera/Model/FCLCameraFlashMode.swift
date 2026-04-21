#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// User-selectable flash mode for the FlyChat camera module.
public enum FCLCameraFlashMode: String, Sendable, Hashable, CaseIterable {
    case auto
    case on
    case off

    #if canImport(AVFoundation)
    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on: return .on
        case .off: return .off
        }
    }
    #endif
}
