import SwiftUI
import UIKit

@main
struct KeyboardProbeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var text = ""
    @State private var report = "waiting for keyboard..."
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report)
                .font(.system(.footnote, design: .monospaced))
            // 標準のTextField(予測変換ON・オートコレクションON)で測る
            TextField("type here", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            Spacer()
        }
        .padding()
        .task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            focused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { note in
            record(note)
        }
    }

    private func record(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let screen = scene?.screen.bounds ?? .zero
        let safeBottom = scene?.windows.first?.safeAreaInsets.bottom ?? 0

        let result: [String: Any] = [
            "screen_width_pt": screen.width,
            "screen_height_pt": screen.height,
            "keyboard_frame_height_pt": frame.height,           // ホームインジケータ領域を含む
            "keyboard_width_pt": frame.width,
            "keyboard_origin_y_pt": frame.minY,
            "safe_area_bottom_pt": safeBottom,
            "keyboard_height_excluding_safe_area_pt": frame.height - safeBottom,
        ]

        report = result.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")

        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("keyboard.json"))
        }
    }
}
