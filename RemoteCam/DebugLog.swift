/// Debug-only logging. Compiles to nothing in Release builds.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
