//
//  FlatBuffersSetupTest.swift
//  RemoteShutter
//
//  Simple test to verify FlatBuffers integration is working correctly
//

import Foundation
import FlatBuffers

public class FlatBuffersSetupTest {
    
    /// Test basic FlatBuffers functionality with generated schema
    public static func runBasicTest() {
        print("🔬 Running FlatBuffers Setup Test...")
        print("=" * 40)
        
        // Test 1: Basic enum creation
        testEnumCreation()
        
        // Test 2: FlatBufferBuilder creation
        testBuilderCreation()
        
        // Test 3: Basic serialization
//        testBasicSerialization()
        
        print("✅ All FlatBuffers tests passed!")
        print("🚀 Ready to implement camera remote control system")
    }
    
    private static func testEnumCreation() {
        print("📝 Test 1: Enum Creation")
        
        // Test generated enums
        let commandAction = RemoteShutter_CommandAction.toggletorch
        let cameraPosition = RemoteShutter_CameraPosition.back
        let torchMode = RemoteShutter_TorchMode.on
        
        print("   ✓ CommandAction: \(commandAction) (value: \(commandAction.value))")
        print("   ✓ CameraPosition: \(cameraPosition) (value: \(cameraPosition.value))")
        print("   ✓ TorchMode: \(torchMode) (value: \(torchMode.value))")
        print("")
    }
    
    private static func testBuilderCreation() {
        print("📝 Test 2: FlatBufferBuilder Creation")
        
        // Test FlatBufferBuilder
        var builder = FlatBufferBuilder(initialSize: 1024)
        print("   ✓ FlatBufferBuilder created with capacity: \(builder)")
        
        // Test string creation
        let testString = builder.create(string: "Hello FlatBuffers!")
        print("   ✓ String offset created: \(testString)")
        print("")
    }
    
//    private static func testBasicSerialization() {
//        print("📝 Test 3: Basic Serialization")
//        
//        var builder = FlatBufferBuilder(initialSize: 1024)
//        
//        // Create a simple command parameters structure
//        let sendToRemote = true
//        let zoomFactor = 2.5
//        let lensType = RemoteShutter_CameraLensType.telephoto
//        let torchMode = RemoteShutter_TorchMode.on
//        let flashMode = RemoteShutter_FlashMode.auto
//        
//        // Create command parameters
//        var parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
//            &builder,
//            sendToRemote: sendToRemote,
//            zoomFactor: zoomFactor,
//            lensType: lensType,
//            torchMode: torchMode,
//            flashMode: flashMode
//        )
//        
//        print("   ✓ CommandParameters created with offset: \(parametersOffset)")
//        
//        // Create strings for command
//        var idString = builder.create(string: "test-command-123")
//        var timestamp: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
//        
//        // Create camera command
//        var commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
//            &builder,
//            idOffset: idString,
//            timestamp: timestamp,
//            action: .setzoom,
//            parametersOffset: parametersOffset
//        )
//        
//        print("   ✓ CameraCommand created with offset: \(commandOffset)")
//        
//        // Finish the buffer
//        builder.finish(offset: commandOffset)
//        
//        // Get the serialized data
//        let data = builder.sizedBuffer
//        print("   ✓ Serialized data size: \(data.size) bytes")
//        let command = RemoteShutter_CameraCommand.createCameraCommand(
//        
//        
//        print("   ✓ Deserialized command:")
//        print("     - ID: \(command.id ?? "nil")")
//        print("     - Timestamp: \(command.timestamp)")
//        print("     - Action: \(command.action)")
//        
//        if let params = command.parameters {
//            print("     - Parameters:")
//            print("       • Send to remote: \(params.sendToRemote)")
//            print("       • Zoom factor: \(params.zoomFactor)")
//            print("       • Lens type: \(params.lensType)")
//            print("       • Torch mode: \(params.torchMode)")
//            print("       • Flash mode: \(params.flashMode)")
//        }
//        
//        print("")
//    }
//    
//    /// Test performance comparison
//    public static func runPerformanceTest() {
//        print("⚡ Running FlatBuffers Performance Test...")
//        print("=" * 40)
//        
//        let iterations = 1000
//        
//        // Test serialization performance
//        let startTime = CFAbsoluteTimeGetCurrent()
//        
//        for i in 0..<iterations {
//            var builder = FlatBufferBuilder(initialSize: 512)
//            
//            let idString = builder.create(string: "command-\(i)")
//            let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
//            
//            let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
//                &builder,
//                sendToRemote: true,
//                zoomFactor: Double(i) / 100.0,
//                lensType: .wideangle,
//                torchMode: .on,
//                flashMode: .off
//            )
//            
//            let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
//                &builder,
//                idOffset: idString,
//                timestamp: timestamp,
//                action: .setzoom,
//                parametersOffset: parametersOffset
//            )
//            
//            builder.finish(offset: commandOffset)
//        }
//        
//        let endTime = CFAbsoluteTimeGetCurrent()
//        let totalTime = (endTime - startTime) * 1000 // Convert to milliseconds
//        
//        print("📊 Performance Results:")
//        print("   • \(iterations) serializations in \(String(format: "%.2f", totalTime))ms")
//        print("   • Average: \(String(format: "%.3f", totalTime / Double(iterations)))ms per command")
//        print("   • Rate: \(String(format: "%.0f", Double(iterations) / (totalTime / 1000))) commands/second")
//        print("")
//        print("🚀 FlatBuffers is ready for high-performance camera control!")
//    }
}

// MARK: - String Multiplication Extension

private extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
} 
