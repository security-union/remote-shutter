import XCTest
import FlatBuffers
@testable import RemoteCam

class FlatBuffersIntegrationTests: XCTestCase {
    
    var modernController: ModernCameraController!
    var p2pCommunication: ModernP2PCommunication!
    var stateObserver: ModernStateObserver!
    
    override func setUp() {
        super.setUp()
        modernController = ModernCameraController()
        p2pCommunication = ModernP2PCommunication()
        stateObserver = ModernStateObserver()
    }
    
    override func tearDown() {
        modernController = nil
        p2pCommunication = nil
        stateObserver = nil
        super.tearDown()
    }
    
    // MARK: - Basic Serialization Tests
    
    func testCameraCommandSerialization() {
        // Test TorchCommand
        let torchCommand = CameraCommand(
            id: "test-torch-123",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        do {
            let serializedData = try p2pCommunication.serialize(command: torchCommand)
            XCTAssertGreaterThan(serializedData.count, 0, "Serialized data should not be empty")
            
            let deserializedCommand = try p2pCommunication.deserialize(data: serializedData)
            XCTAssertEqual(deserializedCommand.id, torchCommand.id)
            XCTAssertEqual(deserializedCommand.type, torchCommand.type)
            XCTAssertEqual(deserializedCommand.torchEnabled, torchCommand.torchEnabled)
            
            print("✅ Torch command serialization test passed")
        } catch {
            XCTFail("Failed to serialize/deserialize torch command: \(error)")
        }
    }
    
    func testCameraStateResponseSerialization() {
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
            id: "test-response-456",
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
            XCTAssertGreaterThan(serializedData.count, 0, "Serialized data should not be empty")
            
            let deserializedResponse = try p2pCommunication.deserialize(responseData: serializedData)
            XCTAssertEqual(deserializedResponse.id, response.id)
            XCTAssertEqual(deserializedResponse.success, response.success)
            XCTAssertEqual(deserializedResponse.capabilities.hasTorch, response.capabilities.hasTorch)
            XCTAssertEqual(deserializedResponse.currentTorchEnabled, response.currentTorchEnabled)
            XCTAssertEqual(deserializedResponse.currentZoomFactor, response.currentZoomFactor, accuracy: 0.01)
            
            print("✅ Camera state response serialization test passed")
        } catch {
            XCTFail("Failed to serialize/deserialize camera state response: \(error)")
        }
    }
    
    func testAllCommandTypes() {
        let commandTypes: [CameraCommandType] = [
            .torch, .flash, .switchCamera, .zoom, .focus, 
            .takePhoto, .startVideoRecording, .stopVideoRecording, .getCapabilities
        ]
        
        for commandType in commandTypes {
            let command = createTestCommand(type: commandType)
            
            do {
                let serializedData = try p2pCommunication.serialize(command: command)
                let deserializedCommand = try p2pCommunication.deserialize(data: serializedData)
                
                XCTAssertEqual(deserializedCommand.type, commandType)
                XCTAssertEqual(deserializedCommand.id, command.id)
                
                print("✅ Command type \(commandType) serialization test passed")
            } catch {
                XCTFail("Failed to serialize/deserialize \(commandType) command: \(error)")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testSerializationPerformance() {
        let command = CameraCommand(
            id: "perf-test-123",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        measure {
            for _ in 0..<1000 {
                do {
                    let _ = try p2pCommunication.serialize(command: command)
                } catch {
                    XCTFail("Serialization failed: \(error)")
                }
            }
        }
    }
    
    func testDeserializationPerformance() {
        let command = CameraCommand(
            id: "perf-test-456",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        let serializedData: Data
        do {
            serializedData = try p2pCommunication.serialize(command: command)
        } catch {
            XCTFail("Failed to serialize test command: \(error)")
            return
        }
        
        measure {
            for _ in 0..<1000 {
                do {
                    let _ = try p2pCommunication.deserialize(data: serializedData)
                } catch {
                    XCTFail("Deserialization failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testCommandExecution() {
        let expectation = XCTestExpectation(description: "Command execution")
        
        let command = CameraCommand(
            id: "exec-test-789",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        modernController.execute(command: command) { result in
            switch result {
            case .success(let response):
                XCTAssertTrue(response.success)
                XCTAssertEqual(response.id, command.id)
                XCTAssertNotNil(response.capabilities)
                print("✅ Command execution test passed")
            case .failure(let error):
                XCTFail("Command execution failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testStateObserver() {
        let expectation = XCTestExpectation(description: "State observer")
        
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
            supportedPhotoFormats: [.jpeg],
            supportedVideoFormats: [.mp4]
        )
        
        let response = CameraStateResponse(
            id: "observer-test-123",
            success: true,
            capabilities: capabilities,
            currentTorchEnabled: true,
            currentFlashMode: .on,
            currentCameraPosition: .back,
            currentZoomFactor: 1.0,
            errorMessage: nil,
            timestamp: Date()
        )
        
        stateObserver.addObserver(id: "test-observer") { state in
            XCTAssertEqual(state.capabilities.hasTorch, true)
            XCTAssertEqual(state.currentTorchEnabled, true)
            print("✅ State observer test passed")
            expectation.fulfill()
        }
        
        stateObserver.updateState(response)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidDataDeserialization() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        
        do {
            let _ = try p2pCommunication.deserialize(data: invalidData)
            XCTFail("Should have thrown an error for invalid data")
        } catch {
            print("✅ Invalid data deserialization correctly threw error: \(error)")
        }
    }
    
    func testErrorResponse() {
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
            
            XCTAssertFalse(deserializedResponse.success)
            XCTAssertEqual(deserializedResponse.errorMessage, "Camera not available")
            print("✅ Error response serialization test passed")
        } catch {
            XCTFail("Failed to serialize/deserialize error response: \(error)")
        }
    }
    
    // MARK: - Size Comparison Tests
    
    func testSerializationSizeComparison() {
        let command = CameraCommand(
            id: "size-test-123",
            type: .torch,
            torchEnabled: true,
            timestamp: Date()
        )
        
        do {
            let flatBuffersData = try p2pCommunication.serialize(command: command)
            
            // Simulate NSCoding size (approximate)
            let nscodingData = try NSKeyedArchiver.archivedData(withRootObject: [
                "id": command.id,
                "type": command.type.rawValue,
                "torchEnabled": command.torchEnabled ?? false,
                "timestamp": command.timestamp
            ] as [String : Any], requiringSecureCoding: false)
            
            print("📊 Serialization size comparison:")
            print("   FlatBuffers: \(flatBuffersData.count) bytes")
            print("   NSCoding:    \(nscodingData.count) bytes")
            print("   Reduction:   \(100 - (flatBuffersData.count * 100 / nscodingData.count))%")
            
            XCTAssertLessThan(flatBuffersData.count, nscodingData.count, "FlatBuffers should be smaller than NSCoding")
        } catch {
            XCTFail("Size comparison test failed: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestCommand(type: CameraCommandType) -> CameraCommand {
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

// MARK: - Test Extensions

extension FlatBuffersIntegrationTests {
    
    func testRoundTripAccuracy() {
        let originalCommand = CameraCommand(
            id: "roundtrip-test-123",
            type: .zoom,
            zoomFactor: 3.14159,
            timestamp: Date()
        )
        
        do {
            let serializedData = try p2pCommunication.serialize(command: originalCommand)
            let deserializedCommand = try p2pCommunication.deserialize(data: serializedData)
            
            XCTAssertEqual(deserializedCommand.id, originalCommand.id)
            XCTAssertEqual(deserializedCommand.type, originalCommand.type)
            XCTAssertEqual(deserializedCommand.zoomFactor!, originalCommand.zoomFactor!, accuracy: 0.0001)
            
            print("✅ Round-trip accuracy test passed")
        } catch {
            XCTFail("Round-trip accuracy test failed: \(error)")
        }
    }
    
    func testConcurrentSerialization() {
        let expectation = XCTestExpectation(description: "Concurrent serialization")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        for i in 0..<10 {
            queue.async {
                let command = CameraCommand(
                    id: "concurrent-test-\(i)",
                    type: .torch,
                    torchEnabled: i % 2 == 0,
                    timestamp: Date()
                )
                
                do {
                    let serializedData = try self.p2pCommunication.serialize(command: command)
                    let deserializedCommand = try self.p2pCommunication.deserialize(data: serializedData)
                    
                    XCTAssertEqual(deserializedCommand.id, command.id)
                    XCTAssertEqual(deserializedCommand.torchEnabled, command.torchEnabled)
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent serialization failed for task \(i): \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        print("✅ Concurrent serialization test passed")
    }
} 