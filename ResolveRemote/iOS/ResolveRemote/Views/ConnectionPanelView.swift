import SwiftUI

/// Compact connection header shared by the Edit and Colour tabs.
///
/// Collapsed (default): one slim row — status dot, host:port, and the
/// current clip name. Tapping the row expands the full panel (IP/port
/// fields, Connect button, error text); tapping the dot or connecting
/// collapses it again. Expansion state is shared across tabs.
struct ConnectionPanelView: View {
    @EnvironmentObject private var connection: RemoteConnection

    private enum Field {
        case host
        case port
    }

    // Persisted so the fields are pre-filled on next launch and the app can
    // auto-connect (ResolveRemoteApp reads the same keys).
    @AppStorage("hostIP") private var host = ""
    @AppStorage("portText") private var portText = "49321"
    // Shared across tabs so the header looks the same on both.
    @AppStorage("connHeaderExpanded") private var expanded = false
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 8) {
            collapsedRow

            if expanded {
                expandedPanel
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

    // MARK: - Collapsed row

    private var collapsedRow: some View {
        HStack(spacing: 8) {
            Button {
                expanded = false
            } label: {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .frame(width: 28, height: 28) // keep an easy hit area
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text(host.isEmpty ? "no host" : "\(host):\(portText)")
                .font(.caption2.monospaced())
                .foregroundColor(Color(white: 0.6))
                .lineLimit(1)
                .layoutPriority(1)

            Text(connection.colorState?.clip ?? "")
                .font(.caption2)
                .foregroundColor(Color(white: 0.45))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            expanded = true
        }
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
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
                if showsErrorDetail, let message = connection.lastError {
                    Text("— \(message)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var buttonTitle: String {
        switch connection.state {
        case .connected, .connecting, .reconnecting:
            return "Disconnect"
        case .disconnected, .error:
            // After a failed reconnect run, offer Retry against the saved
            // endpoint; otherwise it's a plain first Connect.
            return connection.lastError != nil && !host.isEmpty ? "Retry" : "Connect"
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected:                  return .green
        case .connecting, .reconnecting:  return .orange
        case .disconnected:               return .gray
        case .error:                      return .red
        }
    }

    /// Show the failure reason when we're not in (or heading toward) a
    /// working connection.
    private var showsErrorDetail: Bool {
        switch connection.state {
        case .disconnected, .error: return connection.lastError != nil
        case .connecting, .reconnecting, .connected: return false
        }
    }

    private func toggleConnection() {
        focusedField = nil
        HapticsEngine.shared.buttonTap()
        switch connection.state {
        case .connected, .connecting, .reconnecting:
            connection.disconnect()
        case .disconnected, .error:
            let port = UInt16(portText) ?? 49321
            connection.connect(host: host, port: port)
            expanded = false // connecting collapses the header
        }
    }
}
