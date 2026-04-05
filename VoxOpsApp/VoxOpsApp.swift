import SwiftUI

@main
struct VoxOpsApp: App {
    var body: some Scene {
        MenuBarExtra("VoxOps", systemImage: "waveform.circle") {
            Text("VoxOps — Starting...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
