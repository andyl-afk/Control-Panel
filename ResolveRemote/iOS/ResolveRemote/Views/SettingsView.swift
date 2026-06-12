import SwiftUI

/// Settings tab: all connection UI lives here now, plus haptic preferences
/// and an About section. Auto-connect (Phase 1.3) is unchanged — this is
/// just where the fields moved.
struct SettingsView: View {
    @EnvironmentObject private var connection: RemoteConnection

    private enum Field {
        case host
        case port
    }

    // Same keys ResolveRemoteApp uses for auto-connect.
    @AppStorage("hostIP") private var host = ""
    @AppStorage("portText") private var portText = "49321"
    // Read by HapticsEngine.
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("hapticIntensity") private var hapticIntensity = "medium"
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 14) {
                TrackedLabel(text: "SETTINGS", size: 13, color: Theme.textPrimary)
                    .frame(height: 44)

                section("CONNECTION") {
                    HStack(spacing: 8) {
                        TextField("Mac IP (e.g. 192.168.1.20)", text: $host)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .host)
                            .padding(9)
                            .background(Theme.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        TextField("Port", text: $portText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .port)
                            .padding(9)
                            .frame(width: 76)
                            .background(Theme.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: toggleConnection) {
                        Text(buttonTitle)
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(connection.isConnected ? Theme.surfaceRaised : Theme.colorAccent)
                            .foregroundColor(connection.isConnected ? Theme.textPrimary : .black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(connection.state.label)
                            .font(.caption)
                            .foregroundColor(statusColor)
                        if let message = connection.lastError, !connection.isConnected {
                            Text("— \(message)")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                    }
                }

                section("HAPTICS") {
                    Toggle(isOn: $hapticsEnabled) {
                        Text("Haptic feedback")
                            .font(.footnote)
                            .foregroundColor(Theme.textPrimary)
                    }
                    .tint(Theme.colorAccent)

                    Picker("Intensity", selection: $hapticIntensity) {
                        Text("Light").tag("light")
                        Text("Medium").tag("medium")
                        Text("Strong").tag("strong")
                    }
                    .pickerStyle(.segmented)
                    .disabled(!hapticsEnabled)
                    .onChange(of: hapticIntensity) { _, _ in
                        // Sample the new strength immediately.
                        HapticsEngine.shared.heavyBump()
                    }
                }

                section("ABOUT") {
                    HStack {
                        Text("Resolve Remote")
                            .font(.footnote)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(versionString)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
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

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TrackedLabel(text: title, size: 9)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buttonTitle: String {
        switch connection.state {
        case .connected, .connecting, .reconnecting:
            return "Disconnect"
        case .disconnected, .error:
            return connection.lastError != nil && !host.isEmpty ? "Retry" : "Connect"
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected:                 return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected, .error:      return .red
        }
    }

    private func toggleConnection() {
        focusedField = nil
        HapticsEngine.shared.buttonTap()
        switch connection.state {
        case .connected, .connecting, .reconnecting:
            connection.disconnect()
        case .disconnected, .error:
            connection.connect(host: host, port: UInt16(portText) ?? 49321)
        }
    }
}
