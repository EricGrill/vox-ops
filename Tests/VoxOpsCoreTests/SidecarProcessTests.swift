import Testing
import Foundation
@testable import VoxOpsCore

@Suite("SidecarProcess")
struct SidecarProcessTests {
    @Test("launches process and reads stdout")
    func launchAndRead() async throws {
        let sidecar = SidecarProcess(executablePath: "/bin/echo", arguments: ["hello voxops"])
        try sidecar.start()
        let output = try await sidecar.readLine()
        #expect(output == "hello voxops")
        sidecar.stop()
    }

    @Test("reports not running after stop")
    func stopStatus() throws {
        let sidecar = SidecarProcess(executablePath: "/bin/cat", arguments: [])
        try sidecar.start()
        #expect(sidecar.isRunning == true)
        sidecar.stop()
        Thread.sleep(forTimeInterval: 0.1)
        #expect(sidecar.isRunning == false)
    }

    @Test("writes to stdin and reads response")
    func stdinStdout() async throws {
        let sidecar = SidecarProcess(executablePath: "/bin/cat", arguments: [])
        try sidecar.start()
        try sidecar.writeLine("ping")
        let output = try await sidecar.readLine()
        #expect(output == "ping")
        sidecar.stop()
    }
}
