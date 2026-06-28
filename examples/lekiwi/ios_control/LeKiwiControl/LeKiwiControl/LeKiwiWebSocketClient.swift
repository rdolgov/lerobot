import Foundation
import SwiftUI
import UIKit

final class LeKiwiWebSocketClient: ObservableObject {
    @Published var endpoint: String = "ws://pi5-robot.local:8765"
    @Published var isConnected = false
    @Published var statusText = "Disconnected"
    @Published var frontImage: UIImage?
    @Published var wristImage: UIImage?
    @Published var lastX: Double = 0
    @Published var lastY: Double = 0
    @Published var lastTheta: Double = 0

    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    func connect() {
        disconnect(sendStop: false)

        guard let url = URL(string: endpoint) else {
            statusText = "Invalid URL"
            return
        }

        let newTask = session.webSocketTask(with: url)
        task = newTask
        statusText = "Connecting..."
        newTask.resume()
        isConnected = true
        statusText = "Connected"
        receiveLoop()
    }

    func disconnect(sendStop: Bool = true) {
        if sendStop {
            sendStopCommand()
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        statusText = "Disconnected"
    }

    func sendCommand(x: Double, y: Double, theta: Double) {
        sendJSON([
            "type": "command",
            "x": x,
            "y": y,
            "theta": theta,
        ])
    }

    func sendStopCommand() {
        sendJSON(["type": "stop"])
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        task.send(.string(text)) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.statusText = "Send failed: \(error.localizedDescription)"
                    self?.isConnected = false
                }
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveLoop()
            case .failure(let error):
                DispatchQueue.main.async {
                    self.statusText = "Receive failed: \(error.localizedDescription)"
                    self.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleTextMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let type = root["type"] as? String
        if type == "hello" {
            let message = root["message"] as? String ?? "Connected"
            DispatchQueue.main.async {
                self.statusText = message
            }
            return
        }

        if type == "error" {
            let message = root["message"] as? String ?? "Bridge error"
            DispatchQueue.main.async {
                self.statusText = message
            }
            return
        }

        guard type == "observation",
              let observation = root["observation"] as? [String: Any]
        else {
            return
        }

        let front = decodeImage(observation["front"])
        let wrist = decodeImage(observation["wrist"])
        let x = number(observation["x.vel"])
        let y = number(observation["y.vel"])
        let theta = number(observation["theta.vel"])

        DispatchQueue.main.async {
            if let front {
                self.frontImage = front
            }
            if let wrist {
                self.wristImage = wrist
            }
            self.lastX = x ?? self.lastX
            self.lastY = y ?? self.lastY
            self.lastTheta = theta ?? self.lastTheta
            self.statusText = "Receiving observations"
        }
    }

    private func decodeImage(_ value: Any?) -> UIImage? {
        guard let encoded = value as? String,
              !encoded.isEmpty,
              let data = Data(base64Encoded: encoded)
        else {
            return nil
        }
        return UIImage(data: data)
    }

    private func number(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }
}
