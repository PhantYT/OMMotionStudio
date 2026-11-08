import SwiftUI

@main
struct OMMotionStudioApp: App {
    @StateObject private var bluetooth = BluetoothManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
        }
    }
}
