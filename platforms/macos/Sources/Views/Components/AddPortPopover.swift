import SwiftUI
import AppKit

struct AddPortPopover: View {
    enum Mode {
        case favorite
        case watch
    }

    let mode: Mode
    let onAdd: (Int, Bool, Bool) -> Void

    @State private var portText = ""
    @State private var notifyOnStart = true
    @State private var notifyOnStop = true
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    private var isValidPort: Bool {
        guard let port = Int(portText) else { return false }
        return port > 0 && port <= 65535
    }

    private var title: String {
        mode == .favorite ? L("ports.addFavoriteTitle") : L("ports.addWatchedTitle")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            TextField(L("ports.addPortField"), text: $portText)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    if isValidPort {
                        handleAdd()
                    }
                }

            if mode == .watch {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(L("ports.notifyOnStart"), isOn: $notifyOnStart)
                        .toggleStyle(.checkbox)

                    Toggle(L("ports.notifyOnStop"), isOn: $notifyOnStop)
                        .toggleStyle(.checkbox)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button(L("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(L("common.add")) {
                    handleAdd()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!isValidPort || (mode == .watch && !notifyOnStart && !notifyOnStop))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            // Make popover window key so TextField can receive focus
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow {
                    window.makeKey()
                }
                isTextFieldFocused = true
            }
        }
    }

    private func handleAdd() {
        guard let port = Int(portText), port > 0, port <= 65535 else { return }
        onAdd(port, notifyOnStart, notifyOnStop)
        dismiss()
    }
}
