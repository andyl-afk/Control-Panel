import SwiftUI

/// iPad Fairlight / Tracks mode — a utility page, not a mixer (the mockup's
/// fader/meter panel stays out: Resolve's API exposes no live audio state,
/// and faking meters would break the honesty rules). Transport and Add
/// Marker ride the existing wired keyboard commands; track and marker-nav
/// utilities are badged placeholders gated on the probed capabilities.
struct iPadFairlightModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    private var caps: CapabilityState? { connection.capabilityState }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    PadPanel(title: "TRANSPORT", centered: true) {
                        PadTransportRow(send: sendCommand)
                    }

                    PadPanel(title: "MARKERS", centered: true) {
                        markerRow
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    PadPanel(title: "TRACK UTILITIES", centered: true) {
                        trackRow
                    }

                    PadPanel(title: "PROCESSING", centered: true) {
                        processingRow
                    }

                    Spacer()
                }
                .frame(width: 380)
            }

            PadPanel(title: "CUSTOM SHORTCUTS", centered: true) {
                CustomShortcutStrip(onBlocked: onBlocked)
            }
        }
    }

    private var markerRow: some View {
        HStack(spacing: 8) {
            ControlSurfaceButton(
                title: "Add Marker",
                icon: "bookmark.fill",
                status: caps.status(for: "markers"),
                wired: true,
                action: { connection.send(cmd: CommandName.marker) },
                onBlocked: onBlocked
            )
            ControlSurfaceButton(title: "Prev Marker", icon: "chevron.left.to.line",
                                 status: caps.status(for: "markers"),
                                 wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Next Marker", icon: "chevron.right.to.line",
                                 status: caps.status(for: "markers"),
                                 wired: false, onBlocked: onBlocked)
        }
    }

    private var trackRow: some View {
        let trackStatus = caps.status(for: "track_control")
        return HStack(spacing: 8) {
            ControlSurfaceButton(title: "Track Enable", icon: "speaker.wave.2",
                                 status: trackStatus, wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Track Lock", icon: "lock",
                                 status: trackStatus, wired: false, onBlocked: onBlocked)
            ControlSurfaceButton(title: "Track Name", icon: "textformat",
                                 status: trackStatus, wired: false, onBlocked: onBlocked)
        }
    }

    private var processingRow: some View {
        // The real Resolve 21 probe returned voice_isolation: unknown —
        // shown as Experimental, never executed.
        ControlSurfaceButton(title: "Voice Isolation", subtitle: "Studio AI",
                             icon: "waveform.badge.mic",
                             status: caps.status(for: "voice_isolation"),
                             wired: false, onBlocked: onBlocked)
            .frame(maxWidth: 180)
    }

    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}
