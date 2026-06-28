import SwiftUI
import UIKit

private struct MotionCommand: Equatable {
    let x: Double
    let y: Double
    let theta: Double
}

struct ContentView: View {
    @StateObject private var client = LeKiwiWebSocketClient()
    @State private var selectedCamera = "front"
    @State private var speed = 0.08
    @State private var turnSpeed = 25.0
    @State private var activeCommand: MotionCommand?

    private let commandTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    connectionPanel
                    cameraPanel
                    telemetryPanel
                    controlPanel
                }
                .padding()
            }
            .navigationTitle("LeKiwi")
            .onReceive(commandTimer) { _ in
                sendActiveCommand()
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
                    activeCommand = nil
                    client.sendStopCommand()
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
                    stopMotion()
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

    private var selectedImage: UIImage? {
        selectedCamera == "front" ? client.frontImage : client.wristImage
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

#Preview {
    ContentView()
}
