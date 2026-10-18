"""Private local Wi-Fi entry -> one RAM-only USB provisioning frame.

Never reads OS Wi-Fi profiles, stores credentials, or prints USB input/credentials.
Use a private local session; this is not encrypted serial provisioning.
"""

import argparse
import re
import time
from pathlib import Path


def build_frame(ssid: str, password: str) -> bytearray:
    name = ssid.encode("utf-8")
    if not 1 <= len(name) <= 32 or b"\0" in name:
        raise ValueError("Network name must be 1-32 UTF-8 bytes without NUL.")
    if not 8 <= len(password) <= 63 or any(not 32 <= ord(c) <= 126 for c in password):
        raise ValueError(
            "Use a personal hotspot password of 8-63 printable ASCII characters."
        )
    secret = password.encode("ascii")
    return bytearray(b"KBW1") + bytearray([len(name), len(secret)]) + name + secret


def private_window() -> bytearray | None:
    import tkinter as tk
    from tkinter import messagebox

    root = tk.Tk()
    root.title("kickBAC - private Wi-Fi provisioning")
    root.geometry("510x270")
    root.attributes("-topmost", True)
    root.resizable(False, False)
    result: list[bytearray] = []
    tk.Label(
        root,
        text="Enter your 2.4 GHz personal hotspot/router locally.",
        font=("Segoe UI", 11, "bold"),
    ).pack(pady=(15, 5))
    tk.Label(
        root,
        text="Not chat. No password is printed or saved to a file.\nUse WPA2/WPA3-Personal; captive-portal/enterprise login is unsupported.",
    ).pack()
    form = tk.Frame(root)
    form.pack(pady=12)
    tk.Label(form, text="Wi-Fi network name:").grid(
        row=0, column=0, sticky="e", padx=5, pady=5
    )
    name = tk.Entry(form, width=35)
    name.grid(row=0, column=1)
    tk.Label(form, text="Wi-Fi password:").grid(
        row=1, column=0, sticky="e", padx=5, pady=5
    )
    password = tk.Entry(form, width=35, show="*")
    password.grid(row=1, column=1)

    def submit(_event=None):
        try:
            packet = build_frame(name.get(), password.get())
        except ValueError as error:
            messagebox.showerror("Check entry", str(error), parent=root)
            return
        result.append(packet)
        password.delete(0, tk.END)
        root.destroy()

    tk.Button(root, text="Connect ESP32 and test HTTPS", command=submit, padx=12).pack(
        pady=5
    )
    root.bind("<Return>", submit)
    root.after(300000, root.destroy)
    name.focus_set()
    root.mainloop()
    return result[0] if result else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    args = parser.parse_args()
    print(
        "Opening private local Wi-Fi entry window. Do not put passwords in chat.",
        flush=True,
    )
    packet = private_window()
    if packet is None:
        print("PROVISION_CANCELLED: no credentials sent.")
        return 2

    import serial

    port = serial.Serial()
    port.port = args.port
    port.baudrate = 115200
    port.timeout = 0.4
    port.dtr = False
    port.rts = False
    safe_lines: list[str] = []
    log = Path(__file__).parents[1] / "build" / "wifi-connectivity.log"
    outcome = 1
    try:
        port.open()
        deadline = time.monotonic() + 35
        ready = False
        while time.monotonic() < deadline:
            line = port.readline().decode("utf-8", errors="replace").strip()
            if re.fullmatch(r"probe_[A-Za-z0-9_= .:/+\-]+", line):
                print(line, flush=True)
                safe_lines.append(line)
                if line.startswith("probe_ready "):
                    ready = True
                    break
        if not ready:
            print("PROVISION_FAILED: firmware not ready; no credentials sent.")
            return 1
        port.write(packet)
        port.flush()
        for i in range(len(packet)):
            packet[i] = 0
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            line = port.readline().decode("utf-8", errors="replace").strip()
            if re.fullmatch(r"(?:probe_|CONNECTIVITY_)[A-Za-z0-9_= .:/+\-]+", line):
                print(line, flush=True)
                safe_lines.append(line)
                if line.startswith("CONNECTIVITY_PASS"):
                    outcome = 0
                    break
                if line.startswith("CONNECTIVITY_FAIL"):
                    break
        if outcome:
            print(
                "CONNECTIVITY_NOT_VERIFIED: see sanitized stage output; no insecure fallback."
            )
        return outcome
    except (OSError, serial.SerialException):
        print("PROVISION_FAILED: USB/serial unavailable; no credential values logged.")
        return 1
    finally:
        for i in range(len(packet)):
            packet[i] = 0
        port.close()
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("\n".join(safe_lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
