#!/usr/bin/env python3
"""Live tuner / switcher for the Ghostty CRT custom shaders.

Ghostty has no native shader-parameter UI, custom shaders are compile-time GLSL
with no user-uniform passthrough, and it only *reloads* a custom shader when the
configured path changes (not when the file content changes) -- but it can be told
to hard-reload its whole config via SIGUSR2.

So this tool fakes "live" tuning and switching:

  * pick one of the available shaders (radio buttons),
  * read its canonical .glsl (passed via ``--shader name=PATH``) as a template,
  * show a slider per tunable ``#define`` seeded from that template,
  * on any change, rewrite the shader with the new values to a *uniquely named*
    file under ~/.config/ghostty/shaders/live/,
  * point ``shader-tune.conf`` (included last by the managed config) at it, and
  * send SIGUSR2 to Ghostty so it reloads and recompiles.

Per-shader slider values, the selected shader, and whether an override is active
are persisted to ``crt-tuner-state.json`` in the config dir, so switching shaders
(and restarting the tuner) keeps each shader's edits instead of snapping back to
the source defaults. "Save" rewrites that state on demand; "Export #defines"
prints/writes the chosen values so you can paste them back into the repo shader;
"Disable override" clears shader-tune.conf to restore the managed shader selected
by ``programs.ghostty.shader``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
import tkinter as tk
from pathlib import Path

# (define name, label, min, max, step) per shader.
PARAMS_BY_SHADER: dict[str, list[tuple[str, str, float, float, float]]] = {
    "crt-geom": [
        ("scanline_weight", "Scanline weight", 0.05, 0.80, 0.01),
        ("DOTMASK", "Dot mask", 0.00, 1.00, 0.01),
        ("SHARPER", "Sharpness", 1.0, 4.0, 1.0),
        ("CRTgamma", "CRT gamma", 1.0, 4.0, 0.05),
        ("monitorgamma", "Monitor gamma", 1.5, 3.0, 0.05),
        ("SATURATION", "Saturation", 0.0, 2.0, 0.05),
        ("lum", "Luminance boost", -0.5, 0.5, 0.01),
        ("CURVATURE", "Curvature on/off", 0.0, 1.0, 1.0),
        ("d", "Tube distance", 0.8, 3.0, 0.05),
        ("R", "Tube radius", 1.5, 5.0, 0.05),
        ("cornersize", "Corner size", 0.0, 0.10, 0.005),
        ("cornersmooth", "Corner smoothness", 100.0, 2000.0, 50.0),
        ("overscan_x", "Overscan X", 90.0, 110.0, 0.5),
        ("overscan_y", "Overscan Y", 90.0, 110.0, 0.5),
    ],
    "crt-lottes": [
        ("HARDSCAN", "Scanline hardness", -20.0, -1.0, 0.5),
        ("HARDPIX", "Pixel hardness", -6.0, -1.0, 0.25),
        ("WARPX", "Warp X", 0.0, 0.20, 0.005),
        ("WARPY", "Warp Y", 0.0, 0.20, 0.005),
        ("MASKDARK", "Mask dark", 0.0, 1.0, 0.02),
        ("MASKLIGHT", "Mask light", 1.0, 2.0, 0.02),
        ("MASKSIZE", "Mask size (0=off, screen px)", 0.0, 18.0, 1.0),
        ("MASKTYPE", "Mask type 0grille 1TV 2VGAs 3VGA", 0.0, 3.0, 1.0),
        ("SHADOWMASK", "Mask on/off", 0.0, 1.0, 1.0),
        ("BRIGHTBOOST", "Brightness", 0.5, 2.0, 0.02),
        ("GAMMA_IN", "Gamma in", 1.0, 4.0, 0.05),
        ("GAMMA_OUT", "Gamma out", 1.5, 3.0, 0.05),
    ],
    "crt-rvm": [
        ("RVM_MODE", "Mode 0PVM 1Wega 2arcade", 0.0, 2.0, 1.0),
        ("HARDPIX", "Pixel hardness", -6.0, -1.0, 0.25),
        ("WARPX", "Warp X", 0.0, 0.20, 0.005),
        ("WARPY", "Warp Y", 0.0, 0.20, 0.005),
        ("RVM_SCAN_DARK", "Scan slope dark/thin", 1.0, 4.0, 0.05),
        ("RVM_SCAN_BRIGHT", "Scan slope bright/fat", 0.5, 3.0, 0.05),
        ("RVM_RECON_SOFT", "Recon soft (mode1)", -6.0, -1.0, 0.25),
        ("RVM_SCAN_HARD", "Scan hard (mode2)", -16.0, -1.0, 0.5),
        ("RVM_DARK", "Mask exposure dark", 0.0, 1.0, 0.02),
        ("MASKSIZE", "Mask size (0=off, screen px)", 0.0, 18.0, 1.0),
        ("BRIGHTBOOST", "Brightness", 0.5, 2.0, 0.02),
        ("GAMMA_IN", "Gamma in", 1.0, 4.0, 0.05),
        ("GAMMA_OUT", "Gamma out", 1.5, 3.0, 0.05),
    ],
}

# Defines that must be emitted as bare integers (so the GLSL preprocessor can use
# them in `#if`, e.g. RVM's compile-time mode selection).
INTEGER_DEFINES = {"RVM_MODE"}

DEBOUNCE_MS = 180


def fmt(value: float, name: str = "") -> str:
    """Format a number as a GLSL literal.

    Integer-only defines (see ``INTEGER_DEFINES``) are emitted without a decimal
    point so they can be used in preprocessor ``#if`` expressions; everything
    else becomes a float literal (always with a decimal point).
    """
    if name in INTEGER_DEFINES:
        return str(int(round(value)))
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return text if "." in text else text + ".0"


def define_re(name: str) -> re.Pattern[str]:
    return re.compile(rf"(?m)^(#define\s+{re.escape(name)})\s+\S+.*$")


def read_define(text: str, name: str, fallback: float) -> float:
    m = define_re(name).search(text)
    if not m:
        return fallback
    token = m.group(0).split()[2]
    try:
        return float(token)
    except ValueError:
        return fallback


def apply_defines(text: str, values: dict[str, float]) -> str:
    for name, value in values.items():
        text = define_re(name).sub(rf"\g<1> {fmt(value, name)}", text)
    return text


class Tuner:
    def __init__(
        self, shaders: dict[str, Path], default: str, config_dir: Path
    ) -> None:
        self.shaders = shaders
        self.config_dir = config_dir
        self.live_dir = config_dir / "shaders" / "live"
        self.tune_conf = config_dir / "shader-tune.conf"
        self.state_path = config_dir / "crt-tuner-state.json"
        self.live_dir.mkdir(parents=True, exist_ok=True)

        state = self._read_state()
        # Per-shader tuned values, persisted so switching shaders (and restarting
        # the tuner) keeps each shader's edits rather than reverting to the
        # source defaults.
        self.saved: dict[str, dict[str, float]] = state.get("values", {})
        self.override_enabled: bool = bool(state.get("override", False))

        saved_sel = state.get("selected")
        if saved_sel in shaders:
            self.current = saved_sel
        elif default in shaders:
            self.current = default
        else:
            self.current = next(iter(shaders))

        self.base_text = ""
        self.vars: dict[str, tk.DoubleVar] = {}
        self._pending: str | None = None

        self.root = tk.Tk()
        self.root.title("Ghostty CRT Tuner")
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self._build_ui()
        self._load_shader(self.current)

        # If an override was active last session, re-apply it so the saved state
        # is live immediately (no need to nudge a slider first).
        if self.override_enabled:
            self._apply()

    def _build_ui(self) -> None:
        tk.Label(
            self.root,
            text="Live CRT shader tuning (writes shader-tune.conf, reloads Ghostty)",
            anchor="w",
            padx=10,
            pady=8,
        ).pack(fill="x")

        sel = tk.Frame(self.root)
        sel.pack(fill="x", padx=10)
        tk.Label(sel, text="Shader:").pack(side="left")
        self.shader_var = tk.StringVar(value=self.current)
        for name in self.shaders:
            tk.Radiobutton(
                sel,
                text=name,
                value=name,
                variable=self.shader_var,
                command=self._on_select_shader,
            ).pack(side="left", padx=4)

        self.slider_frame = tk.Frame(self.root)
        self.slider_frame.pack(fill="both", expand=True, padx=10, pady=6)

        btns = tk.Frame(self.root)
        btns.pack(fill="x", pady=8)
        tk.Button(btns, text="Reset", command=self._reset).pack(side="left", padx=6)
        tk.Button(btns, text="Save", command=self._save).pack(side="left", padx=6)
        tk.Button(btns, text="Export #defines", command=self._export).pack(
            side="left", padx=6
        )
        tk.Button(btns, text="Disable override", command=self._disable).pack(
            side="left", padx=6
        )

        self.status = tk.Label(self.root, text="Ready.", anchor="w", padx=10, pady=6)
        self.status.pack(fill="x")

    def _load_shader(self, name: str) -> None:
        self.current = name
        self.base_text = self.shaders[name].read_text()
        for child in self.slider_frame.winfo_children():
            child.destroy()
        self.vars = {}

        saved = self.saved.get(name, {})
        for i, (define, label, lo, hi, step) in enumerate(PARAMS_BY_SHADER[name]):
            # Prefer a previously-tuned value, falling back to the source default.
            initial = saved.get(define, read_define(self.base_text, define, lo))
            initial = min(max(float(initial), lo), hi)
            var = tk.DoubleVar(value=initial)
            self.vars[define] = var
            tk.Label(self.slider_frame, text=label, anchor="w", width=18).grid(
                row=i, column=0, sticky="w", padx=(0, 4)
            )
            tk.Scale(
                self.slider_frame,
                from_=lo,
                to=hi,
                resolution=step,
                orient="horizontal",
                length=320,
                variable=var,
                command=lambda _v: self._on_change(),
            ).grid(row=i, column=1, sticky="we")
        self.slider_frame.columnconfigure(1, weight=1)

    # -- state persistence ----------------------------------------------------
    def _read_state(self) -> dict:
        try:
            return json.loads(self.state_path.read_text())
        except (OSError, ValueError):
            return {}

    def _capture_current(self) -> None:
        if self.vars:
            self.saved[self.current] = {
                name: var.get() for name, var in self.vars.items()
            }

    def _persist(self) -> None:
        self._capture_current()
        data = {
            "selected": self.current,
            "override": self.override_enabled,
            "values": self.saved,
        }
        tmp = self.state_path.with_suffix(".json.tmp")
        try:
            tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
            tmp.replace(self.state_path)
        except OSError:
            pass

    # -- actions --------------------------------------------------------------
    def _on_select_shader(self) -> None:
        # Stash the outgoing shader's values before swapping so they survive.
        self._capture_current()
        self._load_shader(self.shader_var.get())
        self._apply()

    def _on_change(self) -> None:
        if self._pending is not None:
            self.root.after_cancel(self._pending)
        self._pending = self.root.after(DEBOUNCE_MS, self._apply)

    def _current_values(self) -> dict[str, float]:
        return {name: var.get() for name, var in self.vars.items()}

    def _apply(self) -> None:
        self._pending = None
        self.override_enabled = True
        text = apply_defines(self.base_text, self._current_values())

        # Unique filename guarantees the configured path changes, which is what
        # makes Ghostty actually recompile the shader on reload.
        target = self.live_dir / f"crt-{time.time_ns()}.glsl"
        target.write_text(text)
        self._cleanup_live(keep=target)

        self.tune_conf.write_text(
            "# Auto-generated by ghostty-crt-tuner. Delete to restore the\n"
            "# managed shader, or use the tool's \"Disable override\" button.\n"
            "custom-shader =\n"
            f"custom-shader = {target}\n"
            "custom-shader-animation = true\n"
        )
        self._reload()
        self._persist()
        self.status.config(text=f"Applied {self.current} -> {target.name}")

    def _cleanup_live(self, keep: Path) -> None:
        for old in self.live_dir.glob("crt-*.glsl"):
            if old != keep:
                try:
                    old.unlink()
                except OSError:
                    pass

    def _reload(self) -> None:
        # SIGUSR2 makes Ghostty hard-reload its config (re-reading shader-tune.conf
        # and recompiling the now-changed shader path). The real GTK process is the
        # Nix-wrapped ".ghostty-wrapped", so we substring-match instead of using -x;
        # the tuner itself runs as python3 and won't be matched.
        try:
            result = subprocess.run(["pkill", "-USR2", "ghostty"], check=False)
        except FileNotFoundError:
            self.status.config(text="pkill not found; cannot signal Ghostty")
            return
        if result.returncode not in (0, 1):
            self.status.config(text=f"pkill returned {result.returncode}")

    def _reset(self) -> None:
        self.base_text = self.shaders[self.current].read_text()
        for name, var in self.vars.items():
            var.set(read_define(self.base_text, name, var.get()))
        self._disable()

    def _disable(self) -> None:
        # Empty file -> managed config's custom-shader stays in effect.
        self.override_enabled = False
        self.tune_conf.write_text("")
        self._cleanup_live(keep=Path("/nonexistent"))
        self._reload()
        self._persist()
        self.status.config(text="Override disabled (managed shader restored).")

    def _save(self) -> None:
        self._persist()
        self.status.config(text=f"Saved state -> {self.state_path}")

    def _on_close(self) -> None:
        self._persist()
        self.root.destroy()

    def _export(self) -> None:
        lines = [
            f"#define {name} {fmt(var.get(), name)}"
            for name, var in self.vars.items()
        ]
        out = self.config_dir / f"{self.current}.defines"
        out.write_text("\n".join(lines) + "\n")
        print(f"// {self.current}\n" + "\n".join(lines))
        self.status.config(text=f"Wrote {out}")

    def run(self) -> None:
        self.root.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(description="Live Ghostty CRT shader tuner")
    parser.add_argument(
        "--shader",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="A selectable shader, e.g. crt-geom=/path/to/crt-geom.glsl",
    )
    parser.add_argument(
        "--default", default="", help="Name of the shader to select on startup"
    )
    parser.add_argument(
        "--config-dir",
        default=os.path.expanduser("~/.config/ghostty"),
        help="Ghostty config directory",
    )
    args = parser.parse_args()

    shaders: dict[str, Path] = {}
    for spec in args.shader:
        if "=" not in spec:
            parser.error(f"--shader expects NAME=PATH, got: {spec}")
        name, _, path = spec.partition("=")
        p = Path(path)
        if name not in PARAMS_BY_SHADER:
            parser.error(f"unknown shader '{name}' (no parameter table)")
        if not p.is_file():
            parser.error(f"shader not found: {p}")
        shaders[name] = p

    if not shaders:
        parser.error("at least one --shader NAME=PATH is required")

    Tuner(shaders, args.default, Path(args.config_dir)).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
