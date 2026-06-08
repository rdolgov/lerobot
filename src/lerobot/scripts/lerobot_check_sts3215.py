#!/usr/bin/env python

import argparse
import sys
from pprint import pformat

PORT = "/dev/tty.usbmodem5AE60574511"
PROTOCOL_VERSION = 0
STS3215_MODEL_NUMBER = 777
MODEL_NUMBER_ADDRESS = 3
SCAN_BAUDRATES = [
    4_800,
    9_600,
    14_400,
    19_200,
    38_400,
    57_600,
    115_200,
    128_000,
    250_000,
    500_000,
    1_000_000,
]


def patch_set_packet_timeout(self, packet_length):
    self.packet_start_time = self.getCurrentTime()
    self.packet_timeout = (self.tx_time_per_byte * packet_length) + (self.tx_time_per_byte * 3.0) + 50


def open_bus(scs, port: str):
    port_handler = scs.PortHandler(port)
    port_handler.setPacketTimeout = patch_set_packet_timeout.__get__(port_handler, scs.PortHandler)
    packet_handler = scs.PacketHandler(PROTOCOL_VERSION)

    if not port_handler.openPort():
        raise ConnectionError(f"Failed to open port '{port}'.")

    return port_handler, packet_handler


def set_baudrate(port_handler, baudrate: int) -> None:
    port_handler.setBaudRate(baudrate)
    if port_handler.getBaudRate() != baudrate:
        raise RuntimeError(f"Failed to set baudrate to {baudrate}.")


def broadcast_ping(scs, port_handler, packet_handler) -> tuple[dict[int, int], int]:
    data_list = {}
    status_length = 6
    rx_length = 0
    wait_length = status_length * scs.MAX_ID
    txpacket = [0] * 6

    tx_time_per_byte = (1000.0 / port_handler.getBaudRate()) * 10.0
    txpacket[scs.PKT_ID] = scs.BROADCAST_ID
    txpacket[scs.PKT_LENGTH] = 2
    txpacket[scs.PKT_INSTRUCTION] = scs.INST_PING

    result = packet_handler.txPacket(port_handler, txpacket)
    if result != scs.COMM_SUCCESS:
        port_handler.is_using = False
        return data_list, result

    timeout_ms = (wait_length * tx_time_per_byte) + (3.0 * scs.MAX_ID) + 16.0
    port_handler.setPacketTimeoutMillis(timeout_ms)

    rxpacket = []
    while not port_handler.isPacketTimeout() and rx_length < wait_length:
        rxpacket += port_handler.readPort(wait_length - rx_length)
        rx_length = len(rxpacket)

    port_handler.is_using = False

    if rx_length == 0:
        return data_list, scs.COMM_RX_TIMEOUT

    while True:
        if rx_length < status_length:
            return data_list, scs.COMM_RX_CORRUPT

        for idx in range(0, rx_length - 1):
            if rxpacket[idx] == 0xFF and rxpacket[idx + 1] == 0xFF:
                break

        if idx == 0:
            checksum = 0
            for idx in range(2, status_length - 1):
                checksum += rxpacket[idx]

            checksum = ~checksum & 0xFF
            if rxpacket[status_length - 1] == checksum:
                data_list[rxpacket[scs.PKT_ID]] = rxpacket[scs.PKT_ERROR]
                del rxpacket[0:status_length]
                rx_length -= status_length

                if rx_length == 0:
                    return data_list, scs.COMM_SUCCESS
            else:
                del rxpacket[0:2]
                rx_length -= 2
        else:
            del rxpacket[0:idx]
            rx_length -= idx


def read_model_number(scs, port_handler, packet_handler, motor_id: int) -> int | None:
    model_number, comm, error = packet_handler.read2ByteTxRx(
        port_handler,
        motor_id,
        MODEL_NUMBER_ADDRESS,
    )

    if comm != scs.COMM_SUCCESS or error != 0:
        return None

    return model_number


def scan_port(scs, port: str) -> dict[int, dict[int, int]]:
    port_handler, packet_handler = open_bus(scs, port)
    baudrate_models = {}

    try:
        for baudrate in SCAN_BAUDRATES:
            set_baudrate(port_handler, baudrate)
            ids_status, comm = broadcast_ping(scs, port_handler, packet_handler)

            if comm != scs.COMM_SUCCESS or not ids_status:
                continue

            models = {}
            for motor_id in sorted(ids_status):
                model_number = read_model_number(scs, port_handler, packet_handler, motor_id)
                if model_number is not None:
                    models[motor_id] = model_number

            if models:
                print(f"Motors found for baudrate={baudrate}: {pformat(models, indent=4)}")
                baudrate_models[baudrate] = models
    finally:
        port_handler.closePort()

    return baudrate_models


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan a Feetech bus for STS3215 motor responses.")
    parser.add_argument(
        "port",
        nargs="?",
        default=PORT,
        help="Serial port for the Feetech controller. If omitted, PORT is used.",
    )
    args = parser.parse_args()
    port = args.port.strip()

    if not port:
        parser.error("port is required unless PORT is set near the top of this file")

    try:
        import scservo_sdk as scs
    except ModuleNotFoundError as exc:
        print(f"Missing Python dependency: {exc.name}")
        print("This command must run from the same environment as your other LeRobot scripts.")
        print("Try reinstalling the editable package with the Feetech extra.")
        return 2

    print(f"Scanning {port} for Feetech motors...")
    baudrate_models = scan_port(scs, port)

    if not baudrate_models:
        print("No motors responded.")
        return 1

    print("\nResponding motor model numbers by baudrate:")
    print(pformat(baudrate_models, indent=4))

    sts3215_ids = []
    for models in baudrate_models.values():
        sts3215_ids.extend(
            motor_id for motor_id, model_number in models.items() if model_number == STS3215_MODEL_NUMBER
        )

    if sts3215_ids:
        print(f"\nSTS3215 responded on ID(s): {sorted(set(sts3215_ids))}")
        return 0

    print(f"\nMotors responded, but none reported STS3215 model number {STS3215_MODEL_NUMBER}.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
