import SwiftUI

// MARK: - API models

/// Live state the nozzle controller pushes to the Worker
/// (GET /api/motor/state). Every field is optional because the Worker
/// returns {} until the device has reported.
nonisolated struct MotorState: Codable, Sendable {
    let mode: String?
    let sliderMm: Int?
    let panDeg: Int?
    let tiltDeg: Int?
    let dial: Int?
    let homed: Bool?
    let lastSeqAck: Int?
    let updatedAt: Double?
}

/// Body for POST /api/motor/command. Nil fields are left out of the JSON.
nonisolated private struct MotorCommand: Encodable, Sendable {
    let kind: String
    var mode: String? = nil
    var speed: Int? = nil
    var deltaDeg: Int? = nil
}

nonisolated private struct CommandResponse: Decodable, Sendable {
    let seq: Int?
}

/// Device modes the user can pick. Raw values are the device's mode names.
enum SuppressionMode: String, CaseIterable, Identifiable {
    case slider = "motor1"
    case pan = "motor2"
    case tilt = "motor3"
    case patrol = "allmotors"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slider: return "Slider Motor"
        case .pan: return "Pan Motor"
        case .tilt: return "Tilt Motor"
        case .patrol: return "Patrol"
        }
    }

    var info: String {
        switch self {
        case .slider:
            return "Take manual control of the nozzle's movement along the rail. Use the speed control that appears below to choose direction and speed."
        case .pan:
            return "Take manual control of turning the nozzle side to side. Use the speed control that appears below to choose direction and speed."
        case .tilt:
            return "Take manual control of tilting the nozzle up and down. Use the speed control that appears below to choose direction and speed."
        case .patrol:
            return "The nozzle sweeps back and forth along the rail and turns side to side on its own, scanning the whole area. You can adjust both sweep speeds below."
        }
    }
}

// MARK: - Model

/// State and commands for the Auto Fire Suppression tab. Mirrors
/// docs/control.html on the website (same endpoints, commands and
/// timings), except the app doesn't ask for the access code.
@Observable
final class AutoSuppressionModel {
    private let baseURL = "https://embersensor.com"
    private let staleAfter: TimeInterval = 5
    private let ackTimeout: TimeInterval = 10
    private let sliderSyncBlock: TimeInterval = 1.5

    var state: MotorState?
    var connectionFailed = false
    var statusText = ""
    var statusIsError = false
    var statusIsSuccess = false
    // Signed in the motor modes (sign = direction); magnitude in Patrol.
    var speed: Double = 0
    // Matches the firmware's default pan sweep speed.
    var panSweepSpeed: Double = 6

    private var awaitingSeq: Int?
    private var awaitingSince = Date()
    private var lastSliderTouch = Date.distantPast
    private var speedTask: Task<Void, Never>?
    private var panSpeedTask: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?
    // The Worker only keeps the latest command, so taps closer together
    // than the device's poll interval are added up and sent as one nudge.
    private var pendingNudge: [String: Int] = ["pan": 0, "tilt": 0]
    private var nudgeTasks: [String: Task<Void, Never>] = [:]

    var mode: String? { state?.mode }
    var isPatrol: Bool { mode == SuppressionMode.patrol.rawValue }

    /// The device accepts speed only in the three motor modes and Patrol.
    var speedActive: Bool {
        guard let mode = mode else { return false }
        return SuppressionMode(rawValue: mode) != nil
    }

    var isOnline: Bool {
        guard let updatedAt = state?.updatedAt else { return false }
        return Date().timeIntervalSince1970 * 1000 - updatedAt <= staleAfter * 1000
    }

    // MARK: Polling

    func refresh() async {
        do {
            let (data, _) = try await send(path: "/api/motor/state")
            let newState = try JSONDecoder().decode(MotorState.self, from: data)
            state = newState
            connectionFailed = false
            syncSpeed(from: newState)
            checkAck(newState)
        } catch {
            connectionFailed = true
        }
    }

    private func syncSpeed(from state: MotorState) {
        // Don't move the slider under the user's finger.
        guard let dial = state.dial, Date().timeIntervalSince(lastSliderTouch) > sliderSyncBlock else { return }
        speed = Double(isPatrol ? abs(dial) : dial)
    }

    private func checkAck(_ state: MotorState) {
        guard let seq = awaitingSeq else { return }
        if let ack = state.lastSeqAck, ack >= seq {
            awaitingSeq = nil
            setStatus("Done", success: true)
        } else if Date().timeIntervalSince(awaitingSince) > ackTimeout {
            awaitingSeq = nil
            setStatus("The system hasn't responded yet.", error: true)
        }
    }

    // MARK: Commands

    func enterMode(_ mode: SuppressionMode) {
        command(MotorCommand(kind: "enterMode", mode: mode.rawValue))
    }

    func action(_ kind: String) {
        command(MotorCommand(kind: kind))
    }

    /// Called only when the user drags the speed slider.
    func speedChanged() {
        lastSliderTouch = Date()
        speedTask?.cancel()
        speedTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            command(MotorCommand(kind: "setSliderSpeed", speed: Int(speed)))
        }
    }

    func panSweepSpeedChanged() {
        panSpeedTask?.cancel()
        panSpeedTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            command(MotorCommand(kind: "setAllMotorsPanSpeed", speed: Int(panSweepSpeed)))
        }
    }

    func nudge(_ axis: String, by degrees: Int) {
        pendingNudge[axis, default: 0] += degrees
        nudgeTasks[axis]?.cancel()
        nudgeTasks[axis] = Task {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            let total = pendingNudge[axis, default: 0]
            pendingNudge[axis] = 0
            guard total != 0 else { return }
            command(MotorCommand(kind: axis == "pan" ? "nudgePan" : "nudgeTilt", deltaDeg: total))
        }
    }

    /// Patrol only: pause the rail sweep.
    func stopRailSweep() {
        command(MotorCommand(kind: "setSliderSpeed", speed: 0))
        speed = 0
        lastSliderTouch = Date()
    }

    /// Patrol only: pause the side-to-side sweep.
    func stopPanSweep() {
        command(MotorCommand(kind: "setAllMotorsPanSpeed", speed: 0))
        panSweepSpeed = 0
    }

    /// Return to menu from any moving mode. Entering menu stops all three
    /// motors and is the only mode where automatic detection runs.
    func stopAll() {
        guard speedActive else { return }
        command(MotorCommand(kind: "enterMode", mode: "menu"))
        speed = 0
        lastSliderTouch = Date()
    }

    private func command(_ command: MotorCommand) {
        setStatus("Sending…", sticky: true)
        Task {
            do {
                let body = try JSONEncoder().encode(command)
                let (data, http) = try await send(path: "/api/motor/command", method: "POST", body: body)
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                if let seq = try? JSONDecoder().decode(CommandResponse.self, from: data).seq {
                    awaitingSeq = seq
                    awaitingSince = Date()
                }
                setStatus(isOnline ? "Sent. Waiting for the system…"
                                   : "Sent. The system will act on it when it reconnects.", sticky: true)
            } catch {
                awaitingSeq = nil
                setStatus("Couldn't send the command. Check your connection and try again.", error: true)
            }
        }
    }

    private func setStatus(_ text: String, success: Bool = false, error: Bool = false, sticky: Bool = false) {
        statusText = text
        statusIsSuccess = success
        statusIsError = error
        statusClearTask?.cancel()
        guard !sticky else { return }
        statusClearTask = Task {
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            statusText = ""
        }
    }

    // MARK: Networking

    private func send(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - View

struct AutoSuppressionView: View {
    @State private var model = AutoSuppressionModel()

    // Nozzle camera stream, the same one the website's page shows.
    private let streamURL = URL(string: "https://livecam.embersensor.com/sspt-cam/")!

    // Motor ranges for the position bars. Kept in sync with the device
    // constants in SliderMotor1.h / PanMotor2.h / TiltMotor3.h.
    private let sliderMinMm = 5.0
    private let sliderMaxMm = 975.0
    private let panMaxAbsDeg = 105.0
    private let tiltMaxAbsDeg = 360.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                positionCard

                if model.state?.homed == false {
                    Text("The nozzle's rail position isn't set yet. Use Re-home rail under Advanced to fix it.")
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                }

                LiveFeedView(url: streamURL)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .cornerRadius(12)
                modeCard
                if model.speedActive {
                    speedCard
                }
                fineAimCard
                advancedCard
                if !model.statusText.isEmpty {
                    Text(model.statusText)
                        .font(.footnote)
                        .foregroundColor(model.statusIsError ? .red : model.statusIsSuccess ? .green : .secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        // Poll only while the tab is on screen; SwiftUI cancels the task
        // when the view disappears.
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text("Thermal Detection · Targeted Spray")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundColor(.orange)
            Text("Automated Fire Detection & Suppression")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
            Text("A thermal camera keeps watch for heat from flames. When it spots a fire, the system moves the spray nozzle along its rail, turns and tilts it toward the fire, and sprays water until the heat is gone, all on its own.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var positionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nozzle Position")
                    .font(.subheadline)
                    .bold()
                Spacer()
                connectionPill
            }
            HStack(alignment: .top, spacing: 12) {
                positionCell(label: "Along rail",
                             value: model.state?.sliderMm.map { "\($0) mm" },
                             fraction: model.state?.sliderMm.map { (Double($0) - sliderMinMm) / (sliderMaxMm - sliderMinMm) },
                             centered: false)
                positionCell(label: "Pan",
                             value: model.state?.panDeg.map { "\($0)°" },
                             fraction: model.state?.panDeg.map { Double($0) / panMaxAbsDeg },
                             centered: true)
                positionCell(label: "Tilt",
                             value: model.state?.tiltDeg.map { "\($0)°" },
                             fraction: model.state?.tiltDeg.map { Double($0) / tiltMaxAbsDeg },
                             centered: true)
            }
        }
        .cardStyle()
    }

    private var connectionPill: some View {
        let (label, color): (String, Color) = {
            if model.connectionFailed { return ("Can't connect", .red) }
            if model.state?.updatedAt == nil { return (model.state == nil ? "Connecting…" : "No data yet", .red) }
            return model.isOnline ? ("Online", .green) : ("Not responding", .orange)
        }()
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .bold()
                .foregroundColor(color)
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operating Mode")
                .font(.subheadline)
                .bold()

            modeBanner

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SuppressionMode.allCases) { mode in
                    modeTile(mode)
                }
            }
        }
        .cardStyle()
    }

    private var modeBanner: some View {
        let text: String
        switch model.mode {
        case "menu":
            text = "Automatic mode: watching for fire. It will aim and spray on its own. Choose a mode below to take manual control."
        case "motor1":
            text = "Manual control: Slider Motor. Automatic detection is paused until you press Stop."
        case "motor2":
            text = "Manual control: Pan Motor. Automatic detection is paused until you press Stop."
        case "motor3":
            text = "Manual control: Tilt Motor. Automatic detection is paused until you press Stop."
        case "allmotors":
            text = "Patrol: the nozzle is sweeping the area. Automatic detection is paused until you press Stop."
        case "panSetup", "tiltSetup":
            text = "Waiting for start-up setup on the device."
        default:
            text = "Waiting for the system…"
        }
        let color: Color = model.mode == "menu" ? .green : .orange
        return Text(text)
            .font(.footnote)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.1))
            .cornerRadius(10)
    }

    private func modeTile(_ mode: SuppressionMode) -> some View {
        let active = model.mode == mode.rawValue
        return HStack(spacing: 4) {
            Button {
                model.enterMode(mode)
            } label: {
                Text(mode.title)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            InfoButton(text: mode.info)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(active ? Color.orange.opacity(0.2) : Color.gray.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(active ? Color.orange : Color.clear, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.isPatrol ? "Rail sweep speed" : "Speed")
                        .font(.subheadline)
                        .bold()
                    InfoButton(text: model.isPatrol
                               ? "How fast the nozzle sweeps along the rail while patrolling. Slide left to slow down, right to speed up."
                               : "Slide away from the middle to move. The farther you slide, the faster it goes. Slide back to the middle to stop.")
                    Spacer()
                    Text("\(Int(model.speed))")
                        .bold()
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { model.speed },
                                          set: { model.speed = $0; model.speedChanged() }),
                           in: model.isPatrol ? 0...20 : -20...20,
                           step: 1)
                        .tint(.orange)
                    if model.isPatrol {
                        Button("Stop") { model.stopRailSweep() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        InfoButton(text: "Pauses the sweep along the rail. The side-to-side sweep keeps going.")
                    }
                }
                if !model.isPatrol {
                    HStack {
                        Text(model.mode == "motor1" ? "Toward home" : "Reverse")
                        Spacer()
                        Text("Stop")
                        Spacer()
                        Text(model.mode == "motor1" ? "Away from home" : "Forward")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if model.isPatrol {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Side-to-side sweep speed")
                            .font(.subheadline)
                            .bold()
                        InfoButton(text: "How fast the nozzle turns side to side while patrolling. Slide left to slow down, right to speed up.")
                        Spacer()
                        Text("\(Int(model.panSweepSpeed))")
                            .bold()
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { model.panSweepSpeed },
                                              set: { model.panSweepSpeed = $0; model.panSweepSpeedChanged() }),
                               in: 0...20,
                               step: 1)
                            .tint(.orange)
                        Button("Stop") { model.stopPanSweep() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        InfoButton(text: "Pauses the side-to-side sweep. The sweep along the rail keeps going.")
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: model.stopAll) {
                    Text("Stop")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }
                InfoButton(text: "Stops all movement right away and hands control back to automatic fire detection.")
            }
        }
        .cardStyle()
    }

    private var fineAimCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fine Aim")
                .font(.subheadline)
                .bold()
            aimRow(axis: "pan", label: "Pan", angle: model.state?.panDeg,
                   info: "Turns the nozzle side to side by 1° or 10° per tap, for precise aiming.")
            aimRow(axis: "tilt", label: "Tilt", angle: model.state?.tiltDeg,
                   info: "Tilts the nozzle up or down by 1° or 10° per tap, for precise aiming.")
            Text("Fine aim can move past the normal limits, so watch the live view.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .cardStyle()
    }

    private func aimRow(axis: String, label: String, angle: Int?, info: String) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .bold()
                InfoButton(text: info)
            }
            .frame(width: 56, alignment: .leading)
            nudgeButton(axis: axis, delta: -10)
            nudgeButton(axis: axis, delta: -1)
            Text(angle.map { "\($0)°" } ?? "—")
                .bold()
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            nudgeButton(axis: axis, delta: 1)
            nudgeButton(axis: axis, delta: 10)
        }
    }

    private func nudgeButton(axis: String, delta: Int) -> some View {
        Button(delta > 0 ? "+\(delta)°" : "−\(-delta)°") {
            model.nudge(axis, by: delta)
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var advancedCard: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                advancedRow(title: "Set pan to 0°", button: "Set", kind: "zeroPan",
                            info: "Saves the nozzle's current side-to-side direction as straight ahead (0°). Line it up first using Fine Aim.")
                Divider()
                advancedRow(title: "Set tilt to 0°", button: "Set", kind: "zeroTilt",
                            info: "Saves the nozzle's current up-and-down angle as level (0°). Line it up first using Fine Aim.")
                Divider()
                advancedRow(title: "Re-home rail", button: "Re-home", kind: "rehome",
                            info: "Moves the nozzle to the end of the rail to find its starting point, then parks it in the middle. Use this if the rail position looks wrong.")
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced")
                .font(.subheadline)
                .bold()
                .foregroundColor(.primary)
        }
        .tint(.secondary)
        .cardStyle()
    }

    private func advancedRow(title: String, button: String, kind: String, info: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
            InfoButton(text: info)
            Spacer()
            Button(button) { model.action(kind) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 10)
    }

    // MARK: Helpers

    private func positionCell(label: String, value: String?, fraction: Double?, centered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundColor(.secondary)
            Text(value ?? "—")
                .font(.headline)
                .monospacedDigit()
            PositionBar(fraction: fraction, centered: centered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thin bar showing where an axis sits in its range. Linear bars fill
/// from the left (fraction 0...1); centered bars fill out from the middle
/// (fraction -1...1). Nil hides the fill.
private struct PositionBar: View {
    let fraction: Double?
    let centered: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.25))
                if centered {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 1, height: 10)
                        .offset(x: width / 2)
                }
                if let fraction = fraction {
                    let f = centered ? max(-1, min(1, fraction)) : max(0, min(1, fraction))
                    let fillWidth = centered ? abs(f) * width / 2 : f * width
                    let start = centered ? (f >= 0 ? width / 2 : width / 2 - fillWidth) : 0
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: fillWidth)
                        .offset(x: start)
                }
            }
        }
        .frame(height: 4)
    }
}

/// Small "i" button that shows a short explanation in a popover.
private struct InfoButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More info")
        .accessibilityHint(text)
        .popover(isPresented: $showing) {
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(idealWidth: 260)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
    }
}
