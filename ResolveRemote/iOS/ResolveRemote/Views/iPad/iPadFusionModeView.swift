import SwiftUI

/// iPad Fusion mode — Phase 17: the wired control surface. Tools are added
/// for real (allowlisted sidecar-side), the SELECTED PARAMETER knob and XY
/// pad drive live tool inputs through the 30Hz batch path, and comps are
/// managed end-to-end. The iPad owns tool selection by name; `fusion_state`
/// broadcasts keep the readouts truthful (sidecar state, never local
/// optimism). Delete Comp is the one destructive action — real dialog.
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

    private var caps: FusionCapabilityState? { connection.fusionCapabilityState }
    private var fstate: FusionState? { connection.fusionState }
    private var live: Bool { connection.isConnected && fstate?.available == true }

    /// The mockup's 16 tools. `verified` = RegID proven on hardware; the
    /// rest are best-known ids — a wrong one fails clean and gets corrected.
    private let tools: [(label: String, id: String, icon: String, verified: Bool)] = [
        ("Text+", "TextPlus", "textformat", true),
        ("Background", "Background", "rectangle.fill", true),
        ("Merge", "Merge", "square.on.square", true),
        ("Transform", "Transform", "arrow.up.and.down.and.arrow.left.and.right", true),
        ("Tracker", "Tracker", "scope", false),
        ("Planar Tracker", "PlanarTracker", "square.dashed", false),
        ("Blur", "Blur", "drop", false),
        ("Glow", "Glow", "sun.max", false),
        ("Drop Shadow", "Shadow", "square.fill.on.square", false),
        ("Rectangle", "RectangleMask", "rectangle", false),
        ("Ellipse", "EllipseMask", "circle", false),
        ("Polygon", "PolylineMask", "pentagon", false),
        ("Paint", "Paint", "paintbrush", false),
        ("Retime", "TimeSpeed", "timer", false),
        ("Lens Distort", "LensDistort", "camera.filters", false),
        ("Color Corrector", "ColorCorrector", "dial.medium", false),
    ]

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

            PadPanel(title: "CUSTOM SHORTCUTS", centered: true) {
                CustomShortcutStrip(onBlocked: onBlocked)
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

            headerButton("Probe Fusion") {
                guard connection.isConnected else {
                    onBlocked("Probe Fusion — connect to the helper first")
                    return
                }
                HapticsEngine.shared.buttonTap()
                connection.probeFusion()
            }
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
            ForEach(tools, id: \.id) { tool in
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
                        if !tool.verified {
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
