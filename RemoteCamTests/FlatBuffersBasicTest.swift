import XCTest
import FlatBuffers
import Theater

class FlatBuffersBasicTest: XCTestCase {
    
    func testFlatBuffersIntegration() {
        // Test that we can create a basic FlatBuffers builder
        let builder = FlatBufferBuilder(initialSize: 1024)
        
        // Test that we can create a simple string
        let testString = builder.create(string: "Hello FlatBuffers!")
        XCTAssertNotNil(testString)
        
        print("✅ FlatBuffers integration test passed")
    }
    
    func testTheaterFrameworkAccess() {
        // Test that we can access Theater framework classes
        let actorSystem = ActorSystem()
        XCTAssertNotNil(actorSystem)
        
        print("✅ Theater framework access test passed")
    }
    
    func testFlatBuffersBasicSerialization() {
        // Test basic FlatBuffers serialization without app dependencies
        let builder = FlatBufferBuilder(initialSize: 1024)
        
        // Create a simple string
        let testMessage = builder.create(string: "Basic FlatBuffers test")
        
        // Create a simple table structure
        let offset = builder.createStructOf(size: 16, alignment: 4)
        
        // Verify we can build something
        builder.finish(offset: offset)
        
        let data = builder.data
        XCTAssertGreaterThan(data.count, 0)
        
        print("✅ Basic FlatBuffers serialization test passed")
    }
    
    func testFlatBuffersSchemaTypes() {
        // Test that our generated schema types are accessible
        let builder = FlatBufferBuilder(initialSize: 1024)
        
        // Test that we can reference our schema enums
        let commandType = CameraCommandType.torch
        XCTAssertEqual(commandType, CameraCommandType.torch)
        
        // Test that we can reference our schema response types
        let responseType = CameraResponseType.stateResponse
        XCTAssertEqual(responseType, CameraResponseType.stateResponse)
        
        print("✅ FlatBuffers schema types test passed")
    }
} 