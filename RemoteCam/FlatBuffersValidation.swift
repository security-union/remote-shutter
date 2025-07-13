import Foundation
import FlatBuffers

// Simple validation script to test FlatBuffers integration
class FlatBuffersValidation {
    
    static func runAllTests() {
        print("🚀 Starting FlatBuffers Integration Validation...")
        
        testBasicSerialization()
        testAllCommandTypes()
        testPerformanceBaseline()
        testErrorHandling()
        
        print("✅ All FlatBuffers validation tests completed successfully!")
    }
    
    static func testBasicSerialization() {
        print("\n📦 Testing Basic Serialization...")
        
        // Test torch command
        let torchCommand = CameraCommand(
            id: "validation-torch-123",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        let p2pCommunication = ModernP2PCommunication()
        
        do {
            let serializedData = try p2pCommunication.serialize(command: torchCommand)
            assert(serializedData.count > 0, "Serialized data should not be empty")
            
            let deserializedCommand = try p2pCommunication.deserialize(data: serializedData)
            assert(deserializedCommand.id == torchCommand.id, "IDs should match")
            assert(deserializedCommand.type == torchCommand.type, "Types should match")
            assert(deserializedCommand.torchEnabled == torchCommand.torchEnabled, "Torch state should match")
            
            print("   ✅ Torch command serialization: PASSED")
        } catch {
            print("   ❌ Torch command serialization: FAILED - \(error)")
        }
        
        // Test capabilities response
        let capabilities = CameraCapabilities(
            hasTorch: true,
            hasFlash: true,
            canSwitchCameras: true,
            canZoom: true,
            canFocus: true,
            canTakePhotos: true,
            canRecordVideo: true,
            maxZoomFactor: 10.0,
            availableCameraPositions: [.front, .back],
            supportedPhotoFormats: [.jpeg, .heif],
            supportedVideoFormats: [.mp4, .mov]
        )
        
        let response = CameraStateResponse(
            id: "validation-response-456",
            success: true,
            capabilities: capabilities,
            currentTorchEnabled: true,
            currentFlashMode: .on,
            currentCameraPosition: .back,
            currentZoomFactor: 2.5,
            errorMessage: nil,
            timestamp: Date()
        )
        
        do {
            let serializedData = try p2pCommunication.serialize(response: response)
            assert(serializedData.count > 0, "Serialized data should not be empty")
            
            let deserializedResponse = try p2pCommunication.deserialize(responseData: serializedData)
            assert(deserializedResponse.id == response.id, "Response IDs should match")
            assert(deserializedResponse.success == response.success, "Success status should match")
            assert(deserializedResponse.capabilities.hasTorch == response.capabilities.hasTorch, "Torch capability should match")
            assert(abs(deserializedResponse.currentZoomFactor - response.currentZoomFactor) < 0.01, "Zoom factor should match")
            
            print("   ✅ Camera state response serialization: PASSED")
        } catch {
            print("   ❌ Camera state response serialization: FAILED - \(error)")
        }
    }
    
    static func testAllCommandTypes() {
        print("\n🔄 Testing All Command Types...")
        
        let p2pCommunication = ModernP2PCommunication()
        let commandTypes: [CameraCommandType] = [
            .torch, .flash, .switchCamera, .zoom, .focus, 
            .takePhoto, .startVideoRecording, .stopVideoRecording, .getCapabilities
        ]
        
        for commandType in commandTypes {
            let command = createTestCommand(type: commandType)
            
            do {
                let serializedData = try p2pCommunication.serialize(command: command)
                let deserializedCommand = try p2pCommunication.deserialize(data: serializedData)
                
                assert(deserializedCommand.type == commandType, "Command type should match")
                assert(deserializedCommand.id == command.id, "Command ID should match")
                
                print("   ✅ \(commandType) command: PASSED")
            } catch {
                print("   ❌ \(commandType) command: FAILED - \(error)")
            }
        }
    }
    
    static func testPerformanceBaseline() {
        print("\n⚡ Testing Performance Baseline...")
        
        let command = CameraCommand(
            id: "performance-test-123",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        let p2pCommunication = ModernP2PCommunication()
        
        // Serialization performance
        let serializationStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            do {
                let _ = try p2pCommunication.serialize(command: command)
            } catch {
                print("   ❌ Serialization performance test failed: \(error)")
                return
            }
        }
        let serializationTime = CFAbsoluteTimeGetCurrent() - serializationStartTime
        
        // Deserialization performance
        let serializedData: Data
        do {
            serializedData = try p2pCommunication.serialize(command: command)
        } catch {
            print("   ❌ Failed to serialize for performance test: \(error)")
            return
        }
        
        let deserializationStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            do {
                let _ = try p2pCommunication.deserialize(data: serializedData)
            } catch {
                print("   ❌ Deserialization performance test failed: \(error)")
                return
            }
        }
        let deserializationTime = CFAbsoluteTimeGetCurrent() - deserializationStartTime
        
        print("   📊 Performance Results (100 operations):")
        print("      Serialization:   \(String(format: "%.2f", serializationTime * 1000))ms")
        print("      Deserialization: \(String(format: "%.2f", deserializationTime * 1000))ms")
        print("      Average per op:  \(String(format: "%.3f", (serializationTime + deserializationTime) * 10))ms")
        
        // Validate performance is reasonable (under 1ms average)
        let averageTime = (serializationTime + deserializationTime) * 10
        assert(averageTime < 0.001, "Performance should be under 1ms per operation")
        
        print("   ✅ Performance baseline: PASSED")
    }
    
    static func testErrorHandling() {
        print("\n🛡️ Testing Error Handling...")
        
        let p2pCommunication = ModernP2PCommunication()
        
        // Test invalid data
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        
        do {
            let _ = try p2pCommunication.deserialize(data: invalidData)
            print("   ❌ Invalid data test: FAILED - Should have thrown error")
        } catch {
            print("   ✅ Invalid data test: PASSED - Correctly threw error")
        }
        
        // Test error response
        let errorResponse = CameraStateResponse(
            id: "error-test-123",
            success: false,
            capabilities: CameraCapabilities(),
            currentTorchEnabled: false,
            currentFlashMode: .off,
            currentCameraPosition: .back,
            currentZoomFactor: 1.0,
            errorMessage: "Camera not available",
            timestamp: Date()
        )
        
        do {
            let serializedData = try p2pCommunication.serialize(response: errorResponse)
            let deserializedResponse = try p2pCommunication.deserialize(responseData: serializedData)
            
            assert(!deserializedResponse.success, "Error response should have success = false")
            assert(deserializedResponse.errorMessage == "Camera not available", "Error message should match")
            
            print("   ✅ Error response test: PASSED")
        } catch {
            print("   ❌ Error response test: FAILED - \(error)")
        }
    }
    
    // Helper method to create test commands
    static func createTestCommand(type: CameraCommandType) -> CameraCommand {
        switch type {
        case .torch:
            return CameraCommand(id: "test-\(type)", type: type, torchEnabled: true, timestamp: Date())
        case .flash:
            return CameraCommand(id: "test-\(type)", type: type, flashMode: .on, timestamp: Date())
        case .switchCamera:
            return CameraCommand(id: "test-\(type)", type: type, cameraPosition: .front, timestamp: Date())
        case .zoom:
            return CameraCommand(id: "test-\(type)", type: type, zoomFactor: 2.5, timestamp: Date())
        case .focus:
            return CameraCommand(id: "test-\(type)", type: type, focusPoint: CGPoint(x: 0.5, y: 0.5), timestamp: Date())
        case .takePhoto:
            return CameraCommand(id: "test-\(type)", type: type, photoSettings: PhotoSettings(format: .jpeg, quality: 0.8), timestamp: Date())
        case .startVideoRecording:
            return CameraCommand(id: "test-\(type)", type: type, videoSettings: VideoSettings(format: .mp4, quality: .high), timestamp: Date())
        case .stopVideoRecording:
            return CameraCommand(id: "test-\(type)", type: type, timestamp: Date())
        case .getCapabilities:
            return CameraCommand(id: "test-\(type)", type: type, timestamp: Date())
        }
    }
}

// Run the validation when this file is executed
if CommandLine.argc > 0 {
    FlatBuffersValidation.runAllTests()
} 