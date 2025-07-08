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

### 2. Lens Switching
- **Multiple Lens Types**: Support for Wide-Angle, Ultra-Wide, Telephoto, and Dual Camera lenses
- **Device Compatibility**: Automatically detects available lenses on each device
- **Remote Switching**: Switch lenses from the remote monitor device
- **Visual Feedback**: Segmented control shows available lens options

### 3. User Interface Enhancements
- **Zoom Slider**: Located on the right side of the monitor interface
- **Zoom Label**: Shows current zoom level (e.g., "2.5x")
- **Lens Selector**: Segmented control at the bottom for easy lens switching
- **State Management**: Controls are properly enabled/disabled based on recording state

## Technical Implementation

### Architecture Components

1. **Command Pattern**: New UI and Remote commands for zoom and lens operations
   - `UICmd.SetZoom` / `RemoteCmd.SetZoom`
   - `UICmd.SwitchLens` / `RemoteCmd.SwitchLens`

2. **Camera Enhancement**: Extended `CameraViewController` with:
   - `setZoom(zoomFactor:)` method
   - `switchLens(to:)` method
   - Enhanced camera discovery with multiple lens types

3. **State Management**: New states for handling zoom and lens operations:
   - `monitorSettingZoom`
   - `monitorSwitchingLens`

4. **UI Controls**: Programmatically created zoom and lens controls that integrate with the existing interface

### Lens Types Supported

```swift
public enum CameraLensType: Int, CaseIterable {
    case wideAngle = 0      // Standard wide-angle camera
    case ultraWide = 1      // Ultra-wide camera (iOS 13+)
    case telephoto = 2      // Telephoto camera
    case dualCamera = 3     // Dual camera system
}
```

### Usage Instructions

#### For Remote Monitor Users:

1. **Zoom Control**:
   - Use the zoom slider on the right side of the screen
   - The current zoom level is displayed above the slider
   - Zoom range depends on the camera device capabilities

2. **Lens Switching**:
   - Use the lens selector at the bottom of the screen
   - Available options depend on the camera device
   - Common options: "Wide", "Ultra Wide", "Telephoto"

3. **Availability**:
   - Controls are available in both Photo and Video modes
   - Controls are disabled during recording
   - Automatic fallback to wide-angle if requested lens is unavailable

#### Device Compatibility:

- **Zoom**: Available on all devices with camera
- **Ultra-Wide**: iPhone 11 and newer, some iPad models
- **Telephoto**: iPhone 7 Plus and newer with telephoto lens
- **Dual Camera**: Devices with multiple camera systems

## Benefits

1. **Enhanced User Experience**: Full camera control from remote device
2. **Professional Use**: Better composition and framing options
3. **Accessibility**: Remote control for difficult shooting positions
4. **Creative Freedom**: Access to all camera capabilities remotely

## Customer Satisfaction

This implementation directly addresses the customer's concerns:
- ✅ Can change lenses remotely
- ✅ Can control zoom remotely  
- ✅ Can alter camera view from remote device
- ✅ Works with both photo and video modes
- ✅ Intuitive and easy-to-use interface

## Technical Notes

- Zoom levels are clamped to device capabilities
- Lens switching resets zoom to 1.0x for consistency
- Available lens types are dynamically detected
- Commands are properly serialized for network transmission
- Error handling provides fallback options

## Future Enhancements

Potential improvements for future versions:
- Pinch-to-zoom gesture support
- Focus control
- Exposure control
- White balance adjustment
- Custom zoom presets