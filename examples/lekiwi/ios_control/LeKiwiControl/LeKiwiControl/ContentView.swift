import SwiftUI
import UIKit

private enum ControlMode: String, CaseIterable, Identifiable {
    case drive = "Drive"
    case arm = "Arm"

    var id: String { rawValue }
}

private struct MotionCommand: Equatable {
    let x: Double
    let y: Double
    let theta: Double
}

private struct ArmTargets: Equatable {
    var shoulderPan: Double = 0
    var shoulderLift: Double = 0
    var elbowFlex: Double = 0
    var wristFlex: Double = 0
    var wristRoll: Double = 0
    var gripper: Double = 0

    var joints: [String: Double] {
        [
            "arm_shoulder_pan.pos": shoulderPan,
            "arm_shoulder_lift.pos": shoulderLift,
            "arm_elbow_flex.pos": elbowFlex,
            "arm_wrist_flex.pos": wristFlex,
            "arm_wrist_roll.pos": wristRoll,
            "arm_gripper.pos": gripper,
        ]
    }
}

struct ContentView: View {
    @StateObject private var client = LeKiwiWebSocketClient()
    @State private var selectedCamera = "front"
    @State private var selectedMode = ControlMode.drive
    @State private var speed = 0.08
    @State private var turnSpeed = 25.0
    @State private var activeCommand: MotionCommand?
    @State private var armTargets = ArmTargets()
    @State private var liveArmControl = false
    @State private var didSyncArmTargets = false

    private let commandTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    connectionPanel
                    cameraPanel

                    Picker("Mode", selection: $selectedMode) {
                        ForEach(ControlMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedMode == .drive {
                        telemetryPanel
                        controlPanel
                    } else {
                        armPanel
                    }
                }
                .padding()
            }
            .navigationTitle("LeKiwi")
            .onReceive(commandTimer) { _ in
                sendActiveCommand()
            }
            .onChange(of: client.armObservationVersion) { _, _ in
                if !didSyncArmTargets {
                    syncArmTargets()
                    didSyncArmTargets = true
                }
            }
        }
    }

    private var connectionPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: client.isConnected ? "wifi" : "wifi.slash")
                    .foregroundStyle(client.isConnected ? .green : .secondary)
                TextField("WebSocket URL", text: $client.endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button {
                    client.isConnected ? client.disconnect() : client.connect()
                } label: {
                    Label(client.isConnected ? "Disconnect" : "Connect", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    stopAll()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Text(client.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cameraPanel: some View {
        VStack(spacing: 10) {
            Picker("Camera", selection: $selectedCamera) {
                Text("Front").tag("front")
                Text("Wrist").tag("wrist")
            }
            .pickerStyle(.segmented)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.92))
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera")
                            .font(.largeTitle)
                        Text("No image yet")
                            .font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var telemetryPanel: some View {
        VStack(spacing: 12) {
            HStack {
                telemetry("x", client.lastX, "m/s")
                telemetry("y", client.lastY, "m/s")
                telemetry("theta", client.lastTheta, "deg/s")
            }

            VStack {
                HStack {
                    Label("Linear", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    Spacer()
                    Text("\(speed, specifier: "%.2f") m/s")
                        .monospacedDigit()
                }
                Slider(value: $speed, in: 0.02...0.25, step: 0.01)
            }

            VStack {
                HStack {
                    Label("Turn", systemImage: "rotate.left")
                    Spacer()
                    Text("\(turnSpeed, specifier: "%.0f") deg/s")
                        .monospacedDigit()
                }
                Slider(value: $turnSpeed, in: 5...90, step: 5)
            }
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HoldButton(title: "Turn L", systemImage: "rotate.left") {
                    activeCommand = MotionCommand(x: 0, y: 0, theta: 1)
                    sendActiveCommand()
                } onRelease: {
                    stopMotion()
                }

                HoldButton(title: "Forward", systemImage: "arrow.up") {
                    activeCommand = MotionCommand(x: 1, y: 0, theta: 0)
                    sendActiveCommand()
                } onRelease: {
                    stopMotion()
                }

                HoldButton(title: "Turn R", systemImage: "rotate.right") {
                    activeCommand = MotionCommand(x: 0, y: 0, theta: -1)
                    sendActiveCommand()
                } onRelease: {
                    stopMotion()
                }
            }

            HStack(spacing: 12) {
                HoldButton(title: "Left", systemImage: "arrow.left") {
                    activeCommand = MotionCommand(x: 0, y: 1, theta: 0)
                    sendActiveCommand()
                } onRelease: {
                    stopMotion()
                }

                Button {
                    stopAll()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                HoldButton(title: "Right", systemImage: "arrow.right") {
                    activeCommand = MotionCommand(x: 0, y: -1, theta: 0)
                    sendActiveCommand()
                } onRelease: {
                    stopMotion()
                }
            }

            HStack(spacing: 12) {
                Spacer()
                HoldButton(title: "Back", systemImage: "arrow.down") {
                    activeCommand = MotionCommand(x: -1, y: 0, theta: 0)
                    sendActiveCommand()
                } onRelease: {
                    stopMotion()
                }
                Spacer()
            }
        }
    }

    private var armPanel: some View {
        VStack(spacing: 14) {
            ArmSketch(target: armTargets, observed: observedArmTargets) { location, size in
                updateArmTargetFromSketch(location, in: size)
            }

            HStack(spacing: 10) {
                Button {
                    syncArmTargets()
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    sendArmTargets()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Toggle(isOn: $liveArmControl) {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .toggleStyle(.switch)
                .fixedSize()
            }

            VStack(spacing: 12) {
                jointSlider("Pan", systemImage: "arrow.left.and.right", value: armBinding(\.shoulderPan), range: -120...120, units: "deg")
                jointSlider("Shoulder", systemImage: "arrow.up.forward", value: armBinding(\.shoulderLift), range: -120...120, units: "deg")
                jointSlider("Elbow", systemImage: "angle", value: armBinding(\.elbowFlex), range: -140...140, units: "deg")
                jointSlider("Wrist", systemImage: "hand.point.up.left", value: armBinding(\.wristFlex), range: -140...140, units: "deg")
                jointSlider("Roll", systemImage: "rotate.3d", value: armBinding(\.wristRoll), range: -180...180, units: "deg")
                jointSlider("Grip", systemImage: "hand.draw", value: armBinding(\.gripper), range: 0...100, units: "%")
            }
        }
    }

    private var selectedImage: UIImage? {
        selectedCamera == "front" ? client.frontImage : client.wristImage
    }

    private var observedArmTargets: ArmTargets {
        ArmTargets(
            shoulderPan: client.armShoulderPan,
            shoulderLift: client.armShoulderLift,
            elbowFlex: client.armElbowFlex,
            wristFlex: client.armWristFlex,
            wristRoll: client.armWristRoll,
            gripper: client.armGripper
        )
    }

    private func telemetry(_ label: String, _ value: Double, _ units: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value, specifier: "%.2f")")
                .font(.headline.monospacedDigit())
            Text(units)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func jointSlider(
        _ label: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        units: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer()
                Text("\(formattedSliderValue(value.wrappedValue, units: units)) \(units)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func armBinding(_ keyPath: WritableKeyPath<ArmTargets, Double>) -> Binding<Double> {
        Binding {
            armTargets[keyPath: keyPath]
        } set: { newValue in
            armTargets[keyPath: keyPath] = newValue
            sendLiveArmTargets()
        }
    }

    private func sendActiveCommand() {
        guard client.isConnected, let command = activeCommand else { return }
        client.sendCommand(
            x: command.x * speed,
            y: command.y * speed,
            theta: command.theta * turnSpeed
        )
    }

    private func stopMotion() {
        activeCommand = nil
        client.sendStopCommand()
    }

    private func stopAll() {
        activeCommand = nil
        client.sendStopCommand()
        client.sendArmStopCommand()
    }

    private func syncArmTargets() {
        armTargets = observedArmTargets
    }

    private func sendArmTargets() {
        guard client.isConnected else { return }
        client.sendArmTargets(armTargets.joints)
    }

    private func sendLiveArmTargets() {
        guard liveArmControl else { return }
        sendArmTargets()
    }

    private func updateArmTargetFromSketch(_ location: CGPoint, in size: CGSize) {
        let origin = ArmSketch.origin(in: size)
        let dx = Double(location.x - origin.x)
        let dy = Double(location.y - origin.y)
        let angle = atan2(dy, dx) * 180.0 / Double.pi
        let distance = max(1.0, hypot(dx, dy))
        let maxReach = Double(min(size.width, size.height)) * 0.58
        let reach = min(max(distance / maxReach, 0.35), 1.0)

        armTargets.shoulderLift = clamped(angle + 90.0, to: -120...120)
        armTargets.elbowFlex = clamped((reach - 1.0) * 115.0, to: -140...20)
        sendLiveArmTargets()
    }
}

private struct ArmSketch: View {
    let target: ArmTargets
    let observed: ArmTargets
    let onDrag: (CGPoint, CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let targetPoints = armPoints(for: target, in: size)
                let observedPoints = armPoints(for: observed, in: size)
                let baseCenter = Self.origin(in: size)

                var observedPath = Path()
                observedPath.addLines(observedPoints)
                context.stroke(
                    observedPath,
                    with: .color(Color.secondary.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 7])
                )

                var targetPath = Path()
                targetPath.addLines(targetPoints)
                context.stroke(
                    targetPath,
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )

                let baseRect = CGRect(x: baseCenter.x - 24, y: baseCenter.y - 14, width: 48, height: 28)
                context.fill(Path(ellipseIn: baseRect), with: .color(Color(.tertiarySystemFill)))
                context.stroke(Path(ellipseIn: baseRect), with: .color(.secondary), lineWidth: 1)

                let panAngle = degreesToRadians(target.shoulderPan - 90)
                let panEnd = CGPoint(
                    x: baseCenter.x + CGFloat(cos(panAngle)) * 26,
                    y: baseCenter.y + CGFloat(sin(panAngle)) * 26
                )
                var panPath = Path()
                panPath.move(to: baseCenter)
                panPath.addLine(to: panEnd)
                context.stroke(panPath, with: .color(.secondary), lineWidth: 2)

                for point in targetPoints {
                    let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                    context.stroke(Path(ellipseIn: rect), with: .color(.accentColor), lineWidth: 2)
                }

                drawGripper(context: context, points: targetPoints, opening: target.gripper)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDrag(value.location, proxy.size)
                    }
            )
        }
        .frame(height: 230)
    }

    static func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.82)
    }

    private func armPoints(for targets: ArmTargets, in size: CGSize) -> [CGPoint] {
        let origin = Self.origin(in: size)
        let scale = min(size.width, size.height) / 4.1
        let shoulderAngle = -90.0 + targets.shoulderLift
        let elbowAngle = shoulderAngle + targets.elbowFlex
        let wristAngle = elbowAngle + targets.wristFlex

        let shoulder = endpoint(from: origin, length: scale * 1.08, degrees: shoulderAngle)
        let elbow = endpoint(from: shoulder, length: scale * 0.9, degrees: elbowAngle)
        let wrist = endpoint(from: elbow, length: scale * 0.58, degrees: wristAngle)
        return [origin, shoulder, elbow, wrist]
    }

    private func endpoint(from point: CGPoint, length: CGFloat, degrees: Double) -> CGPoint {
        let radians = degreesToRadians(degrees)
        return CGPoint(
            x: point.x + CGFloat(cos(radians)) * length,
            y: point.y + CGFloat(sin(radians)) * length
        )
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }

    private func drawGripper(context: GraphicsContext, points: [CGPoint], opening: Double) {
        guard points.count >= 2, let tip = points.last, let previous = points.dropLast().last else { return }
        let dx = tip.x - previous.x
        let dy = tip.y - previous.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let span = CGFloat(8 + clamped(opening, to: 0...100) * 0.12)

        var path = Path()
        path.move(to: CGPoint(x: tip.x + normal.x * span, y: tip.y + normal.y * span))
        path.addLine(to: CGPoint(x: tip.x + normal.x * (span + 10), y: tip.y + normal.y * (span + 10)))
        path.move(to: CGPoint(x: tip.x - normal.x * span, y: tip.y - normal.y * span))
        path.addLine(to: CGPoint(x: tip.x - normal.x * (span + 10), y: tip.y - normal.y * (span + 10)))
        context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }
}

private struct HoldButton: View {
    let title: String
    let systemImage: String
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(isPressed ? Color.accentColor.opacity(0.26) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
    }
}

private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}

private func formattedSliderValue(_ value: Double, units: String) -> String {
    units == "%" ? String(format: "%.0f", value) : String(format: "%.1f", value)
}

#Preview {
    ContentView()
}
