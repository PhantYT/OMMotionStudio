
import SwiftUI

@main
struct OMMotionStudioApp: App {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var camera = CameraManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .environmentObject(camera)
                .preferredColorScheme(.dark)
        }
    }
}
