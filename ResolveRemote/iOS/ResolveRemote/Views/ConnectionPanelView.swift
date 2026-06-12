import SwiftUI

/// Top panel for entering the Mac helper's IP/port and managing the
/// connection.
struct ConnectionPanelView: View {
    @EnvironmentObject private var connection: RemoteConnection

    private enum Field {
        case host
        case port
    }

    @State private var host = ""
    @State private var portText = "49321"
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statusDot

                TextField("Mac IP (e.g. 192.168.1.20)", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .host)
                    .padding(8)
                    .background(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField("Port", text: $portText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .port)
                    .padding(8)
                    .frame(width: 72)
                    .background(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: toggleConnection) {
                    Text(buttonTitle)
                        .font(.footnote.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(connection.isConnected ? Color(white: 0.25) : Color.orange)
                        .foregroundColor(connection.isConnected ? .white : .black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(connection.state.label)
                    .font(.caption2)
                    .foregroundColor(statusColor)
                if case .error = connection.state, let message = connection.lastError {
                    Text("— \(message)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private var buttonTitle: String {
        switch connection.state {
        case .connected, .connecting: return "Disconnect"
        case .disconnected, .error:   return "Connect"
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .gray
        case .error:        return .red
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private func toggleConnection() {
        focusedField = nil
        HapticsEngine.shared.buttonTap()
        switch connection.state {
        case .connected, .connecting:
            connection.disconnect()
        case .disconnected, .error:
            let port = UInt16(portText) ?? 49321
            connection.connect(host: host, port: port)
        }
    }
}
