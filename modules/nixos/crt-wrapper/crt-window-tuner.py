#!/usr/bin/env python3
"""Live parameter tuner and per-window switch for the picom CRT shader."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tkinter as tk
from pathlib import Path


# name, label, minimum, maximum, step
PARAMS: list[tuple[str, str, float, float, float]] = [
    ("CRT_PIXEL_PITCH", "Source pixel pitch", 1.0, 12.0, 0.25),
    ("RVM_MODE", "Mode: 0 PVM, 1 Wega, 2 arcade", 0.0, 2.0, 1.0),
    ("HARDPIX", "Pixel hardness", -6.0, -1.0, 0.25),
    ("WARPX", "Warp X", 0.0, 0.20, 0.005),
    ("WARPY", "Warp Y", 0.0, 0.20, 0.005),
    ("RVM_SCAN_DARK", "Scan slope dark/thin", 1.0, 4.0, 0.05),
    ("RVM_SCAN_BRIGHT", "Scan slope bright/fat", 0.5, 3.0, 0.05),
    ("RVM_RECON_SOFT", "Reconstruction softness", -6.0, -1.0, 0.25),
    ("RVM_SCAN_HARD", "Arcade scan hardness", -16.0, -1.0, 0.5),
    ("RVM_DARK", "Mask exposure", 0.0, 1.0, 0.02),
    ("MASKSIZE", "Mask size", 0.0, 18.0, 1.0),
    ("BRIGHTBOOST", "Brightness", 0.25, 2.0, 0.02),
    ("GAMMA_IN", "Input gamma", 1.0, 4.0, 0.05),
    ("GAMMA_OUT", "Output gamma", 1.5, 3.0, 0.05),
]

INTEGER_DEFINES = {"RVM_MODE"}
WINDOW_PROPERTY = "_CRT_SHADER"


def format_glsl(value: float, name: str) -> str:
    if name in INTEGER_DEFINES:
        return str(int(round(value)))
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return text if "." in text else text + ".0"


def define_pattern(name: str) -> re.Pattern[str]:
    return re.compile(rf"(?m)^(#define\s+{re.escape(name)})\s+\S+.*$")


def read_define(text: str, name: str, fallback: float) -> float:
    match = define_pattern(name).search(text)
    if not match:
        return fallback
    try:
        return float(match.group(0).split()[2])
    except (ValueError, IndexError):
        return fallback


def apply_defines(text: str, values: dict[str, float]) -> str:
    for name, value in values.items():
        replacement = rf"\g<1> {format_glsl(value, name)}"
        text = define_pattern(name).sub(replacement, text, count=1)
    return text


class Tuner:
    def __init__(self, template: Path, config_dir: Path) -> None:
        self.template = template
        self.config_dir = config_dir
        self.live_shader = config_dir / "live.glsl"
        self.state_path = config_dir / "tuner-state.json"
        self.config_dir.mkdir(parents=True, exist_ok=True)

        self.template_text = template.read_text()
        saved = self._read_state()

        self.root = tk.Tk()
        self.root.title("CRT Window Shader")
        self.root.minsize(650, 540)
        self.vars: dict[str, tk.DoubleVar] = {}
        self.defaults: dict[str, float] = {}

        self._build_ui(saved)
        self._apply()

    def _read_state(self) -> dict[str, float]:
        try:
            data = json.loads(self.state_path.read_text())
            return {
                str(name): float(value)
                for name, value in data.get("values", {}).items()
            }
        except (OSError, ValueError, TypeError):
            return {}

    def _values(self) -> dict[str, float]:
        return {name: variable.get() for name, variable in self.vars.items()}

    def _save_state(self) -> None:
        temporary = self.state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps({"values": self._values()}, indent=2) + "\n")
        os.replace(temporary, self.state_path)

    def _build_ui(self, saved: dict[str, float]) -> None:
        tk.Label(
            self.root,
            text="Live CRT-RVM settings for windows rendered by picom",
            anchor="w",
            padx=10,
            pady=8,
        ).pack(fill="x")

        buttons = tk.Frame(self.root, padx=8)
        buttons.pack(fill="x")
        tk.Button(
            buttons, text="Enable clicked window", command=lambda: self._window("on")
        ).pack(side="left", padx=2)
        tk.Button(
            buttons, text="Disable clicked window", command=lambda: self._window("off")
        ).pack(side="left", padx=2)
        tk.Button(
            buttons, text="Toggle clicked window", command=lambda: self._window("toggle")
        ).pack(side="left", padx=2)
        tk.Button(buttons, text="Apply settings", command=self._apply).pack(
            side="right", padx=2
        )
        tk.Button(buttons, text="Reset settings", command=self._reset).pack(
            side="right", padx=2
        )

        sliders = tk.Frame(self.root, padx=10, pady=8)
        sliders.pack(fill="both", expand=True)
        sliders.columnconfigure(1, weight=1)

        for row, (name, label, minimum, maximum, step) in enumerate(PARAMS):
            fallback = minimum
            default = read_define(self.template_text, name, fallback)
            self.defaults[name] = default
            value = saved.get(name, default)
            variable = tk.DoubleVar(value=max(minimum, min(maximum, value)))
            self.vars[name] = variable

            tk.Label(sliders, text=label, anchor="w").grid(
                row=row, column=0, sticky="w", padx=(0, 8)
            )
            tk.Scale(
                sliders,
                from_=minimum,
                to=maximum,
                resolution=step,
                orient="horizontal",
                variable=variable,
                command=lambda _value: self._changed(),
            ).grid(row=row, column=1, sticky="ew")

        self.status = tk.Label(
            self.root, text="", anchor="w", padx=10, pady=8, relief="sunken"
        )
        self.status.pack(fill="x")

    def _changed(self) -> None:
        self.status.config(text="Settings changed; click Apply settings to reload.")

    def _apply(self) -> None:
        text = apply_defines(self.template_text, self._values())
        temporary = self.live_shader.with_suffix(".tmp")
        temporary.write_text(text)
        os.replace(temporary, self.live_shader)
        self._save_state()

        result = subprocess.run(["pkill", "-USR1", "-x", "picom"], check=False)
        if result.returncode == 0:
            self.status.config(text="Settings applied; picom reinitialized.")
        else:
            self.status.config(text="Settings saved; start picom with `crt-picom`.")

    def _window(self, action: str) -> None:
        self.status.config(text="Click the application window.")
        self.root.update_idletasks()
        selected = subprocess.run(
            ["xdotool", "selectwindow"],
            check=False,
            capture_output=True,
            text=True,
        )
        if selected.returncode != 0 or not selected.stdout.strip():
            self.status.config(text="Window selection cancelled.")
            return

        window = selected.stdout.strip()
        current = subprocess.run(
            ["xprop", "-id", window, WINDOW_PROPERTY],
            check=False,
            capture_output=True,
            text=True,
        )
        enabled = "= 1" in current.stdout
        turn_on = action == "on" or (action == "toggle" and not enabled)

        if turn_on:
            command = [
                "xprop",
                "-id",
                window,
                "-f",
                WINDOW_PROPERTY,
                "32c",
                "-set",
                WINDOW_PROPERTY,
                "1",
            ]
        else:
            command = ["xprop", "-id", window, "-remove", WINDOW_PROPERTY]
        subprocess.run(command, check=False, stdout=subprocess.DEVNULL)
        self.status.config(
            text=f"CRT shader {'enabled' if turn_on else 'disabled'} on {window}."
        )

    def _reset(self) -> None:
        for name, value in self.defaults.items():
            self.vars[name].set(value)
        self.status.config(text="Defaults restored; click Apply settings to reload.")

    def run(self) -> None:
        self.root.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path(os.path.expanduser("~/.config/crt-wrapper")),
    )
    args = parser.parse_args()
    Tuner(args.template, args.config_dir).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
