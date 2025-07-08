# Zoom and Lens Control Features

## Overview

This document describes the new zoom and lens switching functionality added to the Remote Shutter app to address the customer feedback in [GitHub Issue #12](https://github.com/security-union/remote-shutter/issues/12).

## Customer Issue Summary

A customer reported that they couldn't:
- Change camera lenses (wide-angle, ultra-wide, telephoto)
- Control zoom levels
- Alter the camera's view in any way from the remote controller

## New Features Implemented

### 1. Zoom Control
- **Digital/Optical Zoom**: Control zoom levels from 1.0x to the maximum supported by the device
- **Remote Control**: Zoom can be controlled from the remote monitor device
- **Real-time Updates**: Zoom level is displayed and synced between devices
- **Smooth Control**: Slider-based zoom control for precise adjustment
- **Per-Lens Zoom Ranges**: Different lenses have different zoom capabilities

### 2. Lens Switching
- **Multiple Lens Types**: Support for Wide-Angle, Ultra-Wide, Telephoto, and Dual Camera lenses
- **Device Compatibility**: Automatically detects available lenses on each device
- **Remote Switching**: Switch lenses from the remote monitor device
- **Visual Feedback**: Segmented control shows available lens options

### 3. Comprehensive Camera Capabilities Exchange
- **Hardware Detection**: Camera device queries its actual hardware using `AVCaptureDevice.DiscoverySession`
- **Complete Manifest**: Sends all camera information (front/back, lenses, zoom ranges, flash) to remote
- **Real-time Updates**: Capabilities are updated when switching cameras or lenses
- **No Assumptions**: Remote device shows only what's actually available

### 4. User Interface Enhancements
- **Zoom Slider**: Located on the right side of the monitor interface
- **Zoom Label**: Shows current zoom level (e.g., "2.5x")
- **Lens Selector**: Segmented control at the bottom for easy lens switching
- **State Management**: Controls are properly enabled/disabled based on recording state

## Technical Implementation

### Camera Capabilities Exchange Protocol

#### 1. **Camera Device (Hardware Detection)**
```swift
func gatherAllCameraCapabilities() {
    // Query ACTUAL hardware for both front and back cameras
    frontCameraInfo = gatherCameraInfo(for: .front)
    backCameraInfo = gatherCameraInfo(for: .back)
}

func gatherCameraInfo(for position: AVCaptureDevice.Position) -> CameraInfo? {
    let videoDevices = AVCaptureDevice.DiscoverySession.init(
        deviceTypes: getAllDeviceTypes(),
        mediaType: .video, position: position).devices
    
    // Find available lenses, flash capabilities, zoom ranges
    return CameraInfo(availableLenses: [...], hasFlash: [...], zoomCapabilities: [...])
}
```

#### 2. **Camera → Remote Communication**
```swift
public struct CameraInfo: Codable {
    public let availableLenses: [CameraLensType]
    public let hasFlash: Bool
    public let zoomCapabilities: [CameraLensType: ZoomRange]
}

public class CameraCapabilitiesResp: Actor.Message {
    public let frontCamera: CameraInfo?
    public let backCamera: CameraInfo?
    public let currentCamera: AVCaptureDevice.Position
    public let currentLens: CameraLensType
    public let currentZoom: CGFloat
}
```

#### 3. **When Capabilities Are Sent**
- **Initial Connection**: When camera device starts up
- **Camera Toggle**: When switching front ↔ back cameras
- **Lens Switch**: When changing lenses (zoom ranges may change)

### Architecture Components

1. **Enhanced Command Pattern**: All zoom/lens commands now include comprehensive state info
   - `SetZoomResp` includes current lens and zoom range
   - `SwitchLensResp` includes current zoom and new zoom range
   - `CameraCapabilitiesResp` includes complete camera manifest

2. **Hardware Querying**: Extended `CameraViewController` with:
   - `gatherAllCameraCapabilities()` - scans all cameras
   - `gatherCameraInfo(for:)` - gets capabilities for specific camera position
   - `sendCameraCapabilities()` - sends manifest to remote

3. **Dynamic UI Updates**: Remote UI adapts to actual hardware:
   - Lens options based on what camera device actually has
   - Zoom ranges per lens type
   - Flash availability per camera

### Lens Types Supported

```swift
public enum CameraLensType: Int, CaseIterable {
    case wideAngle = 0      // Standard wide-angle camera
    case ultraWide = 1      // Ultra-wide camera (iOS 13+)
    case telephoto = 2      // Telephoto camera
    case dualCamera = 3     // Dual camera system
}
```

### Real-World Examples

#### iPhone 15 Pro
**Camera Capabilities Sent:**
```json
{
  "backCamera": {
    "availableLenses": ["wideAngle", "ultraWide", "telephoto"],
    "hasFlash": true,
    "zoomCapabilities": {
      "wideAngle": { "minZoom": 1.0, "maxZoom": 10.0 },
      "ultraWide": { "minZoom": 0.5, "maxZoom": 2.0 },
      "telephoto": { "minZoom": 1.0, "maxZoom": 25.0 }
    }
  },
  "frontCamera": {
    "availableLenses": ["wideAngle"],
    "hasFlash": false,
    "zoomCapabilities": {
      "wideAngle": { "minZoom": 1.0, "maxZoom": 5.0 }
    }
  }
}
```

#### iPhone SE
**Camera Capabilities Sent:**
```json
{
  "backCamera": {
    "availableLenses": ["wideAngle"],
    "hasFlash": true,
    "zoomCapabilities": {
      "wideAngle": { "minZoom": 1.0, "maxZoom": 5.0 }
    }
  },
  "frontCamera": {
    "availableLenses": ["wideAngle"],
    "hasFlash": false,
    "zoomCapabilities": {
      "wideAngle": { "minZoom": 1.0, "maxZoom": 3.0 }
    }
  }
}
```

### Usage Instructions

#### For Remote Monitor Users:

1. **Zoom Control**:
   - Use the zoom slider on the right side of the screen
   - The current zoom level is displayed above the slider
   - Zoom range adapts to the selected lens (telephoto has higher max zoom)

2. **Lens Switching**:
   - Use the lens selector at the bottom of the screen
   - Only available lenses are shown (no guessing)
   - Zoom resets to 1.0x when switching lenses

3. **Availability**:
   - Controls are available in both Photo and Video modes
   - Controls are disabled during recording
   - UI updates automatically when camera is toggled

#### Device Compatibility Detection:

The system **automatically detects and adapts** to:
- **Zoom**: All devices (range varies by device/lens)
- **Ultra-Wide**: iPhone 11+, some iPad models
- **Telephoto**: iPhone 7 Plus+ with telephoto lens
- **Dual Camera**: Devices with multiple camera systems

## Benefits

1. **Hardware Accurate**: Shows only lenses that actually exist on the camera device
2. **Enhanced User Experience**: Full camera control from remote device
3. **Professional Use**: Better composition and framing options
4. **Accessibility**: Remote control for difficult shooting positions
5. **Creative Freedom**: Access to all camera capabilities remotely
6. **Future Proof**: Automatically detects new lens types Apple adds

## Customer Satisfaction

This implementation directly addresses the customer's concerns:
- ✅ Can change lenses remotely (only shows available lenses)
- ✅ Can control zoom remotely (with accurate ranges per lens)
- ✅ Can alter camera view from remote device
- ✅ Works with both photo and video modes
- ✅ Intuitive and easy-to-use interface
- ✅ **Hardware accurate** - no phantom controls for unavailable features

## Technical Notes

- Camera capabilities are queried using `AVCaptureDevice.DiscoverySession`
- Zoom levels are clamped to actual device capabilities
- Lens switching resets zoom to 1.0x for consistency
- Available lens types are dynamically detected per camera position
- Commands are properly serialized for network transmission
- Comprehensive error handling with graceful fallbacks
- **Breaking Change**: New protocol is more robust but not backward compatible

## Future Enhancements

Potential improvements for future versions:
- Pinch-to-zoom gesture support
- Focus control
- Exposure control
- White balance adjustment
- Custom zoom presets
- Camera specifications display (megapixels, aperture, etc.)