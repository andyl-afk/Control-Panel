import SwiftUI

/// One entry in the curated Fusion tool catalog (Phase 18). `verified`
/// means AddTool with this id succeeded on real hardware; unverified ids
/// are best-known and fail clean if wrong. Must stay a subset of the
/// sidecar's FUSION_ADD_TOOL_IDS allowlist.
struct FusionCatalogEntry: Identifiable {
    let id: String
    let label: String
    let icon: String
    let category: String
    let verified: Bool
    var note: String?
}

/// The curated catalog behind the customisable TOOLS grid. Hardware pass
/// on Resolve 21.0.0b AND 21.0.2 verified the whole catalog minus the
/// planar tools (confirmed not creatable via scripting in Resolve 21).
enum FusionToolCatalog {
    static let all: [FusionCatalogEntry] = [
        // Generators / text
        .init(id: "Background", label: "Background", icon: "rectangle.fill", category: "GENERATORS", verified: true),
        .init(id: "FastNoise", label: "Fast Noise", icon: "water.waves", category: "GENERATORS", verified: true),
        .init(id: "TextPlus", label: "Text+", icon: "textformat", category: "GENERATORS", verified: true),
        .init(id: "Text3D", label: "Text 3D", icon: "cube", category: "GENERATORS", verified: true),
        // Composite
        .init(id: "Merge", label: "Merge", icon: "square.on.square", category: "COMPOSITE", verified: true),
        .init(id: "Dissolve", label: "Dissolve", icon: "square.on.square.dashed", category: "COMPOSITE", verified: true),
        // Transform
        .init(id: "Transform", label: "Transform", icon: "arrow.up.and.down.and.arrow.left.and.right", category: "TRANSFORM", verified: true),
        .init(id: "Resize", label: "Resize", icon: "arrow.up.left.and.arrow.down.right", category: "TRANSFORM", verified: true),
        .init(id: "Crop", label: "Crop", icon: "crop", category: "TRANSFORM", verified: true),
        .init(id: "Letterbox", label: "Letterbox", icon: "rectangle.ratio.16.to.9", category: "TRANSFORM", verified: true),
        .init(id: "DVE", label: "DVE", icon: "rotate.3d", category: "TRANSFORM", verified: true),
        .init(id: "CameraShake", label: "Camera Shake", icon: "camera.metering.unknown", category: "TRANSFORM", verified: true),
        // Tracking
        .init(id: "Tracker", label: "Tracker", icon: "scope", category: "TRACKING", verified: true),
        .init(id: "PlanarTracker", label: "Planar Tracker", icon: "square.dashed", category: "TRACKING", verified: false,
              note: "not scriptable in 21.x"),
        .init(id: "PlanarTransform", label: "Planar Transform", icon: "skew", category: "TRACKING", verified: false,
              note: "not scriptable in 21.x"),
        // Masks
        .init(id: "RectangleMask", label: "Rectangle", icon: "rectangle", category: "MASKS", verified: true),
        .init(id: "EllipseMask", label: "Ellipse", icon: "circle", category: "MASKS", verified: true),
        .init(id: "PolylineMask", label: "Polygon", icon: "pentagon", category: "MASKS", verified: true),
        .init(id: "BSplineMask", label: "B-Spline", icon: "scribble.variable", category: "MASKS", verified: true),
        .init(id: "TriangleMask", label: "Triangle", icon: "triangle", category: "MASKS", verified: true),
        .init(id: "WandMask", label: "Wand", icon: "wand.and.rays", category: "MASKS", verified: true),
        // Blur / sharpen
        .init(id: "Blur", label: "Blur", icon: "drop", category: "BLUR / SHARPEN", verified: true),
        .init(id: "DirectionalBlur", label: "Directional Blur", icon: "wind", category: "BLUR / SHARPEN", verified: true),
        .init(id: "Defocus", label: "Defocus", icon: "camera.aperture", category: "BLUR / SHARPEN", verified: true),
        .init(id: "Sharpen", label: "Sharpen", icon: "triangle.tophalf.filled", category: "BLUR / SHARPEN", verified: true),
        // Light / effects
        .init(id: "Glow", label: "Glow", icon: "sun.max", category: "LIGHT / EFFECTS", verified: true),
        .init(id: "SoftGlow", label: "Soft Glow", icon: "sun.haze", category: "LIGHT / EFFECTS", verified: true),
        .init(id: "Shadow", label: "Drop Shadow", icon: "square.fill.on.square", category: "LIGHT / EFFECTS", verified: true),
        .init(id: "Highlight", label: "Highlight", icon: "sparkles", category: "LIGHT / EFFECTS", verified: true),
        // Colour
        .init(id: "ColorCorrector", label: "Color Corrector", icon: "dial.medium", category: "COLOUR", verified: true),
        .init(id: "ColorCurves", label: "Color Curves", icon: "point.topleft.down.to.point.bottomright.curvepath", category: "COLOUR", verified: true),
        .init(id: "HueCurves", label: "Hue Curves", icon: "circle.grid.cross", category: "COLOUR", verified: true),
        .init(id: "BrightnessContrast", label: "Bright / Contrast", icon: "circle.lefthalf.filled", category: "COLOUR", verified: true),
        .init(id: "ColorGain", label: "Color Gain", icon: "slider.horizontal.3", category: "COLOUR", verified: true),
        .init(id: "WhiteBalance", label: "White Balance", icon: "thermometer.sun", category: "COLOUR", verified: true),
        .init(id: "ChannelBooleans", label: "Channel Booleans", icon: "square.3.layers.3d", category: "COLOUR", verified: true),
        .init(id: "Gamut", label: "Gamut", icon: "paintpalette", category: "COLOUR", verified: true),
        // Keying
        .init(id: "DeltaKeyer", label: "Delta Keyer", icon: "person.and.background.dotted", category: "KEYING", verified: true),
        .init(id: "ChromaKeyer", label: "Chroma Keyer", icon: "drop.triangle", category: "KEYING", verified: true),
        .init(id: "LumaKeyer", label: "Luma Keyer", icon: "circle.righthalf.filled", category: "KEYING", verified: true),
        .init(id: "UltraKeyer", label: "Ultra Keyer", icon: "person.crop.rectangle", category: "KEYING", verified: true),
        .init(id: "MatteControl", label: "Matte Control", icon: "square.2.layers.3d", category: "KEYING", verified: true),
        // Paint / warp
        .init(id: "Paint", label: "Paint", icon: "paintbrush", category: "PAINT / WARP", verified: true),
        .init(id: "GridWarp", label: "Grid Warp", icon: "grid", category: "PAINT / WARP", verified: true),
        .init(id: "Displace", label: "Displace", icon: "water.waves.and.arrow.up", category: "PAINT / WARP", verified: true),
        .init(id: "CornerPositioner", label: "Corner Pin", icon: "arrow.down.forward.and.arrow.up.backward", category: "PAINT / WARP", verified: true),
        // Time / optics
        .init(id: "TimeSpeed", label: "Retime", icon: "timer", category: "TIME / OPTICS", verified: true),
        .init(id: "TimeStretcher", label: "Time Stretcher", icon: "clock.arrow.2.circlepath", category: "TIME / OPTICS", verified: true),
        .init(id: "LensDistort", label: "Lens Distort", icon: "camera.filters", category: "TIME / OPTICS", verified: true),
        .init(id: "FilmGrain", label: "Film Grain", icon: "film", category: "TIME / OPTICS", verified: true),
    ]

    /// The mockup's original 16 — the grid before any customisation.
    static let defaultGridIDs = [
        "TextPlus", "Background", "Merge", "Transform",
        "Tracker", "PlanarTracker", "Blur", "Glow",
        "Shadow", "RectangleMask", "EllipseMask", "PolylineMask",
        "Paint", "TimeSpeed", "LensDistort", "ColorCorrector",
    ]

    static func entry(for id: String) -> FusionCatalogEntry? {
        all.first { $0.id == id }
    }
}

/// iPad Fusion mode — Phase 17: the wired control surface. Tools are added
/// for real (allowlisted sidecar-side), the SELECTED PARAMETER knob and XY
/// pad drive live tool inputs through the 30Hz batch path, and comps are
/// managed end-to-end. The iPad owns tool selection by name; `fusion_state`
/// broadcasts keep the readouts truthful (sidecar state, never local
/// optimism). Delete Comp is the one destructive action — real dialog.
/// Phase 18: the TOOLS grid is customisable from the catalog above
/// (choices persist in fusionToolGridIDs).
struct iPadFusionModeView: View {
    @EnvironmentObject private var connection: RemoteConnection
    var onBlocked: (String) -> Void

    @State private var selectedToolName: String?
    @State private var selectedParam: String?
    @State private var speedMult: Double = 1.0
    @State private var selectedCompIndex: Int = 1
    @State private var showDeleteConfirm = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showProbeDetail = false
    @State private var xyBatcher = VectorBatcher()
    @State private var lastXYPoint: CGPoint?

    /// Comma-separated catalog ids chosen for the grid; empty = defaults.
    @AppStorage("fusionToolGridIDs") private var gridIDsRaw = ""
    @State private var showToolPicker = false

    private var caps: FusionCapabilityState? { connection.fusionCapabilityState }
    private var fstate: FusionState? { connection.fusionState }
    private var live: Bool { connection.isConnected && fstate?.available == true }

    private var gridTools: [FusionCatalogEntry] {
        let ids = gridIDsRaw.isEmpty
            ? FusionToolCatalog.defaultGridIDs
            : gridIDsRaw.split(separator: ",").map(String.init)
        return ids.compactMap(FusionToolCatalog.entry(for:))
    }

    var body: some View {
        VStack(spacing: 12) {
            headerStrip

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    PadPanel(title: "TOOLS", centered: true) {
                        toolsGrid
                    }
                    PadPanel(title: "COMPOSITION ACTIONS", centered: true) {
                        compActions
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    PadPanel(title: "SELECTED PARAMETER", centered: true) {
                        parameterPanel
                    }
                    PadPanel(title: "XY CONTROL", centered: true) {
                        xyPad
                    }
                    PadPanel(title: "MACROS / COMP PRESETS", centered: true) {
                        macrosPanel
                    }
                    Spacer()
                }
                .frame(width: 380)
            }

        }
        .onAppear { refresh() }
        .onChange(of: connection.isConnected) { _, connected in
            if connected { refresh() }
        }
        .onChange(of: connection.fusionState) { _, state in
            adopt(state)
        }
        .onChange(of: connection.lastFusionActionResult) { _, result in
            // A successful add targets the new tool: drop the local selection
            // so the state broadcast that follows is adopted.
            if let result, result.ok, result.cmd == CommandName.fusionAddTool {
                selectedToolName = nil
            }
        }
        .task {
            // Gentle live refresh while the tab is visible (mirrors colour).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard connection.isConnected else { continue }
                connection.send(cmd: CommandName.fusionStatus, mode: "fusion",
                                toolName: selectedToolName)
            }
        }
        .confirmationDialog(
            "Delete \(compName(at: selectedCompIndex) ?? "this comp")? This cannot be undone.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Comp", role: .destructive) {
                HapticsEngine.shared.heavyBump()
                connection.send(cmd: CommandName.fusionDeleteComp, mode: "fusion",
                                index: selectedCompIndex, confirm: true)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename \(compName(at: selectedCompIndex) ?? "comp")", isPresented: $showRenameAlert) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                connection.send(cmd: CommandName.fusionRenameComp, mode: "fusion",
                                name: renameText, index: selectedCompIndex,
                                confirm: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header (compact status + page control)

    private var headerStrip: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(live ? Color(red: 0.3, green: 0.9, blue: 0.45) : .orange)
                .frame(width: 8, height: 8)
            Text(live
                 ? "\(fstate?.clip ?? "clip") · \(fstate?.comp_count ?? 0) comp\((fstate?.comp_count ?? 0) == 1 ? "" : "s") · page \(fstate?.current_page ?? "?")"
                 : (fstate?.reason ?? "Fusion context not available yet"))
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)

            if let result = connection.lastFusionActionResult {
                Text(result.ok ? "✓ \(result.cmd)" : "✕ \(result.cmd)\(result.reason.map { " (\($0))" } ?? "")")
                    .font(.caption)
                    .foregroundColor(result.ok ? Color(red: 0.4, green: 0.85, blue: 0.5) : Theme.lift)
                    .lineLimit(1)
            }

            Spacer()

            headerButton("Open Fusion Page") {
                guard connection.isConnected,
                      caps.status(for: "open_fusion_page") == .supported else {
                    onBlocked("Fusion page — probe hasn't proven page switching yet")
                    return
                }
                HapticsEngine.shared.buttonTap()
                connection.openFusionPage()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func headerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.orange.opacity(connection.isConnected ? 0.85 : 0.25))
                .foregroundColor(.black)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tools grid (wired — adds real tools)

    private var toolsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(gridTools) { tool in
                Button {
                    addTool(tool.id, label: tool.label)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 16))
                            .foregroundColor(live ? Theme.textPrimary : Theme.textSecondary)
                        Text(tool.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(live ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let note = tool.note {
                            Text(note)
                                .font(.system(size: 7))
                                .foregroundColor(.orange.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } else if !tool.verified {
                            Text("id unverified")
                                .font(.system(size: 7))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(Theme.surfaceRaised.opacity(live ? 1 : 0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Grid editor entry point (Phase 18).
            Button {
                HapticsEngine.shared.buttonTap()
                showToolPicker = true
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                    Text("Edit Tools")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showToolPicker) {
            FusionToolPickerView(selectedRaw: $gridIDsRaw)
        }
    }

    private func addTool(_ id: String, label: String) {
        guard live else {
            onBlocked(fstate?.reason ?? "\(label) — no Fusion comp available (open the Fusion page on a clip)")
            return
        }
        HapticsEngine.shared.buttonTap()
        connection.send(cmd: CommandName.fusionAddTool, mode: "fusion",
                        confirm: true, toolId: id)
    }

    // MARK: - Composition actions + comp chips

    private var compActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                compButton("Add Comp", icon: "plus.square") {
                    connection.send(cmd: CommandName.fusionAddComp, mode: "fusion",
                                    confirm: true)
                }
                compButton("Load Comp", icon: "tray.and.arrow.down") {
                    connection.send(cmd: CommandName.fusionLoadComp, mode: "fusion",
                                    index: selectedCompIndex)
                }
                compButton("Rename", icon: "pencil") {
                    renameText = compName(at: selectedCompIndex) ?? ""
                    showRenameAlert = true
                }
                compButton("Export", icon: "square.and.arrow.up") {
                    // No path: the sidecar auto-names into ~/ResolveRemote/Comps.
                    connection.send(cmd: CommandName.fusionExportComp, mode: "fusion",
                                    index: selectedCompIndex)
                }
                compButton("Delete", icon: "trash", destructive: true) {
                    showDeleteConfirm = true
                }
            }

            if let names = fstate?.comp_names, !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(names.enumerated()), id: \.offset) { pair in
                            let index = pair.offset + 1
                            Button {
                                HapticsEngine.shared.buttonTap()
                                selectedCompIndex = index
                            } label: {
                                Text(pair.element)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(selectedCompIndex == index
                                                ? Color.orange.opacity(0.8) : Theme.surfaceRaised)
                                    .foregroundColor(selectedCompIndex == index
                                                     ? .black : Theme.textPrimary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("No comps on this clip yet — Add Comp creates one.")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private func compButton(_ title: String, icon: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            guard connection.isConnected else {
                onBlocked("\(title) — connect to the helper first")
                return
            }
            guard fstate?.comp_names != nil || title == "Add Comp" else {
                onBlocked("\(title) — no clip/comp context yet")
                return
            }
            HapticsEngine.shared.buttonTap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(destructive ? Theme.lift : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(destructive ? Theme.lift.opacity(0.4) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected parameter (live knob)

    private var parameterPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text(fstate?.tool?.name ?? "no tool")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(fstate?.tool?.type ?? "")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button {
                    HapticsEngine.shared.buttonTap()
                    selectedToolName = nil
                    connection.send(cmd: CommandName.fusionStatus, mode: "fusion")
                } label: {
                    Text("Use Active Tool")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Theme.surfaceRaised)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let params = fstate?.params, !params.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(params) { param in
                            Button {
                                HapticsEngine.shared.buttonTap()
                                selectedParam = param.id
                            } label: {
                                Text(param.id)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .background(currentParam?.id == param.id
                                                ? Color.orange.opacity(0.8) : Theme.surfaceRaised)
                                    .foregroundColor(currentParam?.id == param.id
                                                     ? .black : Theme.textPrimary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 14) {
                    DialView(
                        style: .vertical,
                        accent: .orange,
                        onTicks: { ticks in
                            sendParamDelta(ticks)
                        },
                        onDoubleTap: { resetParam() }
                    )
                    .frame(width: 110, height: 110)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(valueReadout)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        speedChips
                        Button {
                            resetParam()
                        } label: {
                            Text("RESET")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(Theme.surfaceRaised)
                                .foregroundColor(Theme.textPrimary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            } else {
                Text(live
                     ? "No mapped parameters for \(fstate?.tool?.type ?? "this tool") yet — the curated map grows as inputs are verified."
                     : "Select or add a tool once a Fusion comp is open.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private var speedChips: some View {
        HStack(spacing: 6) {
            ForEach([("FINE", 0.25), ("NORMAL", 1.0), ("COARSE", 4.0)], id: \.0) { chip in
                Button {
                    HapticsEngine.shared.buttonTap()
                    speedMult = chip.1
                } label: {
                    Text(chip.0)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(speedMult == chip.1
                                    ? Color.orange.opacity(0.8) : Theme.surfaceRaised)
                        .foregroundColor(speedMult == chip.1 ? .black : Theme.textSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentParam: FusionParam? {
        guard let params = fstate?.params, !params.isEmpty else { return nil }
        return params.first { $0.id == selectedParam } ?? params.first
    }

    private var valueReadout: String {
        guard let param = currentParam else { return "—" }
        guard let value = param.value else { return "\(param.id): ?" }
        return String(format: "%@: %.3f", param.id, value)
    }

    private func sendParamDelta(_ ticks: Int) {
        guard live, let toolName = fstate?.tool?.name, let param = currentParam else {
            onBlocked("Parameter knob — no live tool parameter")
            return
        }
        connection.send(cmd: CommandName.fusionParamDelta, mode: "fusion",
                        ticks: ticks, speed: speedMult, param: param.id,
                        toolName: toolName)
    }

    private func resetParam() {
        guard live, let toolName = fstate?.tool?.name, let param = currentParam else {
            onBlocked("Reset — no live tool parameter")
            return
        }
        HapticsEngine.shared.heavyBump()
        connection.send(cmd: CommandName.fusionParamReset, mode: "fusion",
                        param: param.id, toolName: toolName)
    }

    // MARK: - XY pad (live Center control)

    private var xyPad: some View {
        let hasCenter = fstate?.center != nil
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surfaceRaised.opacity(hasCenter ? 1 : 0.5))
            // Crosshair
            Rectangle().fill(Theme.stroke).frame(height: 1)
            Rectangle().fill(Theme.stroke).frame(width: 1)

            if hasCenter, let center = fstate?.center, center.count >= 2 {
                GeometryReader { geo in
                    let nx = min(max(center[0], 0.0), 1.0)
                    let ny = min(max(center[1], 0.0), 1.0)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 12, height: 12)
                        .shadow(color: .orange.opacity(0.8), radius: 4)
                        .position(x: geo.size.width * nx,
                                  y: geo.size.height * (1.0 - ny))
                }
            } else {
                Text(live ? "Select a Transform, Merge or Text+ tool to drive its Center."
                          : "XY pad wakes up with a live Fusion comp.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(height: 150)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard hasCenter, let toolName = fstate?.tool?.name else { return }
                    defer { lastXYPoint = value.location }
                    guard let last = lastXYPoint else { return }
                    // Screen up = +y in Fusion's Center space; sensitivity
                    // pre-multiplied client-side like the trackball.
                    let scale = 0.0015 * speedMult
                    let dx = Double(value.location.x - last.x) * scale
                    let dy = Double(last.y - value.location.y) * scale
                    xyBatcher.onFlush = { fx, fy in
                        connection.send(cmd: CommandName.fusionXYDelta, mode: "fusion",
                                        dx: fx, dy: fy, toolName: toolName)
                    }
                    xyBatcher.add(dx, dy)
                }
                .onEnded { _ in
                    lastXYPoint = nil
                    xyBatcher.finish()
                }
        )
        .overlay(alignment: .bottomTrailing) {
            if hasCenter {
                Button {
                    guard let toolName = fstate?.tool?.name else { return }
                    HapticsEngine.shared.heavyBump()
                    connection.send(cmd: CommandName.fusionParamReset, mode: "fusion",
                                    param: "Center", toolName: toolName)
                } label: {
                    Text("CENTER")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Theme.surface)
                        .foregroundColor(Theme.textSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    // MARK: - Macros / comp presets (folder-driven, like Looks)

    private var macrosPanel: some View {
        VStack(spacing: 8) {
            if let files = connection.fusionCompFiles, !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(files, id: \.self) { file in
                            Button {
                                guard live else {
                                    onBlocked("\(file) — no Fusion comp context to import into")
                                    return
                                }
                                HapticsEngine.shared.buttonTap()
                                connection.send(cmd: CommandName.fusionImportCompFile,
                                                mode: "fusion", confirm: true, name: file)
                            } label: {
                                Text(file)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(Theme.surfaceRaised)
                                    .foregroundColor(Theme.textPrimary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("Drop .comp files into ~/ResolveRemote/Comps on the Mac — they appear here as tap-to-import presets. Export saves there too.")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                guard connection.isConnected else {
                    onBlocked("Refresh presets — connect to the helper first")
                    return
                }
                HapticsEngine.shared.buttonTap()
                connection.send(cmd: CommandName.fusionListCompFiles, mode: "fusion")
            } label: {
                Text("Refresh")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Theme.surfaceRaised)
                    .foregroundColor(Theme.textSecondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func refresh() {
        guard connection.isConnected else { return }
        connection.send(cmd: CommandName.fusionStatus, mode: "fusion",
                        toolName: selectedToolName)
        connection.send(cmd: CommandName.fusionListCompFiles, mode: "fusion")
    }

    private func adopt(_ state: FusionState?) {
        guard let state else { return }
        // Adopt the sidecar's param target when the iPad has no selection
        // (fresh tab, or cleared after adding a tool).
        if selectedToolName == nil, let name = state.tool?.name {
            selectedToolName = name
        }
        // Keep the param chip valid for the current tool.
        if let params = state.params, !params.isEmpty {
            if !(params.contains { $0.id == selectedParam }) {
                selectedParam = params.first?.id
            }
        }
        if let count = state.comp_count, count >= 1, selectedCompIndex > count {
            selectedCompIndex = count
        }
    }

    private func compName(at index: Int) -> String? {
        guard let names = fstate?.comp_names, index >= 1, index <= names.count else {
            return nil
        }
        return names[index - 1]
    }
}

/// Phase 18 — choose which catalog tools appear on the TOOLS grid. Tap
/// toggles; newly added tools append at the end of the grid. Selection
/// persists via the bound AppStorage string (empty = the default 16).
private struct FusionToolPickerView: View {
    @Binding var selectedRaw: String
    @Environment(\.dismiss) private var dismiss

    private var selected: [String] {
        selectedRaw.isEmpty
            ? FusionToolCatalog.defaultGridIDs
            : selectedRaw.split(separator: ",").map(String.init)
    }

    private var categories: [String] {
        var seen: [String] = []
        for entry in FusionToolCatalog.all where !seen.contains(entry.category) {
            seen.append(entry.category)
        }
        return seen
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 12) {
                HStack {
                    TrackedLabel(text: "TOOL GRID", size: 13, color: Theme.textPrimary)
                    Text("\(selected.count) selected")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Button("Reset") {
                        HapticsEngine.shared.buttonTap()
                        selectedRaw = ""
                    }
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    Button("Done") { dismiss() }
                        .font(.footnote.bold())
                        .foregroundColor(Theme.colorAccent)
                }
                .frame(height: 32)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(categories, id: \.self) { category in
                            VStack(alignment: .leading, spacing: 8) {
                                TrackedLabel(text: category, size: 9)
                                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(FusionToolCatalog.all.filter { $0.category == category }) { entry in
                                        pickerTile(entry)
                                    }
                                }
                            }
                        }

                        Text("Unverified ids are best-known guesses — a wrong one fails cleanly when tapped and gets corrected in an update. Tools appear on the grid in the order you add them.")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func pickerTile(_ entry: FusionCatalogEntry) -> some View {
        let isOn = selected.contains(entry.id)
        return Button {
            HapticsEngine.shared.buttonTap()
            toggle(entry.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isOn ? .orange : Theme.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let note = entry.note {
                        Text(note)
                            .font(.system(size: 8))
                            .foregroundColor(.orange.opacity(0.8))
                    } else if !entry.verified {
                        Text("id unverified")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isOn ? .orange : Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(Theme.surfaceRaised.opacity(isOn ? 1 : 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isOn ? Color.orange.opacity(0.5) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        var ids = selected
        if let index = ids.firstIndex(of: id) {
            // Keep at least one tool on the grid.
            guard ids.count > 1 else { return }
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        selectedRaw = ids.joined(separator: ",")
    }
}
