import SwiftUI

/// Settings tab: all connection UI lives here now, plus haptic preferences
/// and an About section. Auto-connect (Phase 1.3) is unchanged — this is
/// just where the fields moved.
struct SettingsView: View {
    @EnvironmentObject private var connection: RemoteConnection
    @EnvironmentObject private var browser: BonjourBrowser

    private enum Field {
        case host
        case port
    }

    // Same keys ResolveRemoteApp uses for auto-connect.
    @AppStorage("hostIP") private var host = ""
    @AppStorage("portText") private var portText = "49321"
    /// Last-used Bonjour service; auto-connect prefers it when discoverable.
    @AppStorage("preferredServiceName") private var preferredServiceName = ""
    // Read by HapticsEngine.
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    /// Production default: diagnostics (probes, smoke tests) stay hidden
    /// unless explicitly enabled from the About section.
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("hapticIntensity") private var hapticIntensity = "medium"
    @AppStorage("wheelTextureEnabled") private var wheelTextureEnabled = true
    @FocusState private var focusedField: Field?
    @State private var showCapabilities = false
    @State private var showSmokeTests = false
    @State private var showFusionCapabilities = false
    @State private var showFusionSmokeTests = false

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 14) {
                TrackedLabel(text: "SETTINGS", size: 13, color: Theme.textPrimary)
                    .frame(height: 44)

                section("NEARBY MACS") {
                    if browser.discovered.isEmpty {
                        Text("Searching for Macs running the helper…")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        ForEach(browser.discovered) { mac in
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .font(.caption)
                                    .foregroundColor(mac.name == preferredServiceName
                                                     ? Theme.colorAccent : Theme.textSecondary)
                                Text(mac.name)
                                    .font(.footnote)
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    HapticsEngine.shared.buttonTap()
                                    preferredServiceName = mac.name
                                    connection.connect(serviceNamed: mac.name, endpoint: mac.endpoint)
                                } label: {
                                    Text("Connect")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Theme.colorAccent)
                                        .foregroundColor(.black)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

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
                        if connection.isConnected, let ms = connection.latencyMs {
                            Text("\(ms) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(latencyColor(ms))
                        }
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

                    Toggle(isOn: $wheelTextureEnabled) {
                        Text("Wheel texture (continuous spin feel)")
                            .font(.footnote)
                            .foregroundColor(Theme.textPrimary)
                    }
                    .tint(Theme.colorAccent)
                    .disabled(!hapticsEnabled)
                }

                if developerMode {
                    diagnosticsSection
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

                    Toggle(isOn: $developerMode) {
                        Text("Developer diagnostics")
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .tint(Theme.colorAccent)
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
        // Browse only while this tab is visible.
        .onAppear { browser.acquire("settings") }
        .onDisappear { browser.release("settings") }
        .sheet(isPresented: $showCapabilities) {
            CapabilityProbeView()
                .environmentObject(connection)
        }
        .sheet(isPresented: $showSmokeTests) {
            ColorSmokeTestView()
                .environmentObject(connection)
        }
        .sheet(isPresented: $showFusionCapabilities) {
            FusionCapabilitiesView()
                .environmentObject(connection)
        }
        .sheet(isPresented: $showFusionSmokeTests) {
            FusionSmokeTestView()
                .environmentObject(connection)
        }
    }

    /// Probes and smoke tests — developer mode only (Phase 21).
    private var diagnosticsSection: some View {
        section("DIAGNOSTICS") {
                    Button {
                        showCapabilities = true
                    } label: {
                        HStack {
                            Text("Resolve capabilities")
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSmokeTests = true
                    } label: {
                        HStack {
                            Text("Colour smoke tests")
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFusionCapabilities = true
                    } label: {
                        HStack {
                            Text("Fusion capabilities")
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFusionSmokeTests = true
                    } label: {
                        HStack {
                            Text("Fusion smoke tests")
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
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

    private func latencyColor(_ ms: Int) -> Color {
        switch ms {
        case ..<40:   return .green
        case ..<120:  return .orange
        default:      return .red
        }
    }

    private func toggleConnection() {
        focusedField = nil
        HapticsEngine.shared.buttonTap()
        switch connection.state {
        case .connected, .connecting, .reconnecting:
            connection.disconnect()
        case .disconnected, .error:
            // Manual connect makes manual IP the preference again.
            preferredServiceName = ""
            connection.connect(host: host, port: UInt16(portText) ?? 49321)
        }
    }
}
