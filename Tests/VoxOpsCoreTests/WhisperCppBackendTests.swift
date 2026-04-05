import Testing
import Foundation
@testable import VoxOpsCore

@Suite("WhisperCppBackend")
struct WhisperCppBackendTests {
    @Test("has correct id")
    func backendId() {
        let backend = WhisperCppBackend(scriptPath: "/nonexistent/run.sh", modelPath: "/nonexistent/model.bin")
        #expect(backend.id == "whisper.cpp")
    }

    @Test("starts in idle status")
    func initialStatus() {
        let backend = WhisperCppBackend(scriptPath: "/nonexistent/run.sh", modelPath: "/nonexistent/model.bin")
        if case .idle = backend.status {
            // correct
        } else {
            Issue.record("Expected idle status")
        }
    }
}
