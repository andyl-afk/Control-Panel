import SwiftUI

/// iPad Fairlight / Tracks mode — a utility page, not a mixer. Transport and
/// Add Marker ride the existing wired keyboard commands; the track and
/// marker-navigation utilities are honestly labelled placeholders gated on
/// the probed `track_control` capability. No meters, no faders, no EQ.
struct iPadFairlightModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    private var caps: CapabilityState? { connection.capabilityState }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrackedLabel(text: "TRANSPORT", size: 9)
            TransportBar(send: sendCommand)
                .frame(maxWidth: 480)

            TrackedLabel(text: "MARKERS", size: 9)
            markerRow

            TrackedLabel(text: "TRACK UTILITIES", size: 9)
            trackRow

            TrackedLabel(text: "PROCESSING", size: 9)
            processingRow

            Spacer()
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
        .frame(maxWidth: 480)
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
        .frame(maxWidth: 480)
    }

    private var processingRow: some View {
        HStack(spacing: 8) {
            // The real Resolve 21 probe returned voice_isolation: unknown —
            // shown as Experimental, never executed.
            ControlSurfaceButton(title: "Voice Isolation", subtitle: "Studio AI",
                                 icon: "waveform.badge.mic",
                                 status: caps.status(for: "voice_isolation"),
                                 wired: false, onBlocked: onBlocked)
        }
        .frame(maxWidth: 480 / 3 + 8)
    }

    private func sendCommand(_ cmd: String) {
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: cmd)
    }
}
