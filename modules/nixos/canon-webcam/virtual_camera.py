import os
import weakref

import gi

gi.require_version("Entangle", "0.1")
gi.require_version("Gst", "1.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Peas", "1.0")
gi.require_version("PeasGtk", "1.0")

from gi.repository import Entangle, GObject, Gst, Gtk, Peas, PeasGtk


DEVICE = "/dev/video9"
_active_plugin_ref = None


class VirtualCameraConfig(Gtk.Grid):
    def __init__(self, plugin):
        super().__init__(column_spacing=12, row_spacing=8)
        self._plugin = plugin

        label = Gtk.Label(label="Publish live preview")
        label.set_halign(Gtk.Align.START)
        self.attach(label, 0, 0, 1, 1)

        self.toggle = Gtk.Switch()
        self.toggle.set_halign(Gtk.Align.END)
        self.toggle.set_active(plugin.enabled)
        self.toggle.connect("notify::active", self._toggle_changed)
        self.attach(self.toggle, 1, 0, 1, 1)

        self.status = Gtk.Label()
        self.status.set_halign(Gtk.Align.START)
        self.status.set_line_wrap(True)
        self.status.set_selectable(True)
        self.attach(self.status, 0, 1, 2, 1)

        device = Gtk.Label(label=f"Output device: {DEVICE}")
        device.set_halign(Gtk.Align.START)
        device.get_style_context().add_class("dim-label")
        self.attach(device, 0, 2, 2, 1)

        self.connect("destroy", self._destroyed)
        plugin.register_config_widget(self)
        self.show_all()

    def _toggle_changed(self, toggle, _param):
        self._plugin.set_enabled(toggle.get_active())

    def _destroyed(self, _widget):
        self._plugin.unregister_config_widget(self)

    def sync(self, enabled, status):
        if self.toggle.get_active() != enabled:
            self.toggle.set_active(enabled)
        self.status.set_text(status)


class VirtualCameraPlugin(GObject.Object, Peas.Activatable, PeasGtk.Configurable):
    __gtype_name__ = "EntangleVirtualCameraPlugin"

    object = GObject.Property(type=GObject.Object)

    def __init__(self):
        super().__init__()
        self.enabled = False
        self._status = "Disabled"
        self._pipeline = None
        self._appsrc = None
        self._bus = None
        self._bus_signal = None
        self._preferences = None
        self._preference_signals = []
        self._window_added_signal = None
        self._window_removed_signal = None
        self._windows = {}
        self._config_widgets = weakref.WeakSet()

    def do_activate(self):
        global _active_plugin_ref

        Gst.init(None)

        self._preferences = self.object.get_preferences()
        for prop in ("img-flip-horizontally", "img-flip-vertically"):
            signal = self._preferences.connect(
                f"notify::{prop}", self._orientation_changed
            )
            self._preference_signals.append(signal)

        self._window_added_signal = self.object.connect(
            "window-added", self._window_added
        )
        self._window_removed_signal = self.object.connect(
            "window-removed", self._window_removed
        )

        for window in self.object.get_windows():
            self._attach_window(window)

        # libpeas scans module globals for extension classes. Keep only a
        # weakref here; exposing a GObject instance confuses that scan.
        _active_plugin_ref = weakref.ref(self)

    def do_deactivate(self):
        global _active_plugin_ref

        self.set_enabled(False)

        if self._window_added_signal is not None:
            self.object.disconnect(self._window_added_signal)
            self._window_added_signal = None
        if self._window_removed_signal is not None:
            self.object.disconnect(self._window_removed_signal)
            self._window_removed_signal = None

        for window in list(self._windows):
            self._detach_window(window)

        if self._preferences is not None:
            for signal in self._preference_signals:
                self._preferences.disconnect(signal)
        self._preference_signals = []
        self._preferences = None

        if _active_plugin_ref is not None and _active_plugin_ref() is self:
            _active_plugin_ref = None

    def do_create_configure_widget(self):
        active_plugin = (
            _active_plugin_ref() if _active_plugin_ref is not None else None
        )
        if active_plugin is None:
            label = Gtk.Label(
                label="The virtual-camera plugin is not active.",
                xalign=0,
            )
            label.set_line_wrap(True)
            label.show()
            return label
        return VirtualCameraConfig(active_plugin)

    def register_config_widget(self, widget):
        self._config_widgets.add(widget)
        widget.sync(self.enabled, self._status)

    def unregister_config_widget(self, widget):
        self._config_widgets.discard(widget)

    def _sync_config_widgets(self):
        for widget in list(self._config_widgets):
            widget.sync(self.enabled, self._status)

    def _set_status(self, status):
        self._status = status
        self._sync_config_widgets()

    def set_enabled(self, enabled):
        enabled = bool(enabled)
        if enabled == self.enabled:
            return

        self.enabled = enabled
        if enabled:
            if self._start_pipeline():
                self._set_status("Ready; start Entangle live preview")
            else:
                self.enabled = False
        else:
            self._stop_pipeline()
            self._set_status("Disabled")
        self._sync_config_widgets()

    def _flip_method(self):
        horizontal = self._preferences.img_get_flip_horizontally()
        vertical = self._preferences.img_get_flip_vertically()
        if horizontal and vertical:
            return "rotate-180"
        if horizontal:
            return "horizontal-flip"
        if vertical:
            return "vertical-flip"
        return "none"

    def _start_pipeline(self):
        if self._pipeline is not None:
            return True

        if not os.path.exists(DEVICE):
            self._set_status(
                f"Virtual camera error: {DEVICE} does not exist; "
                "reload v4l2loopback or reboot"
            )
            return False

        description = (
            "appsrc name=source is-live=true format=time do-timestamp=true "
            "block=false max-bytes=8388608 "
            "! queue max-size-buffers=2 leaky=downstream "
            "! jpegdec "
            f"! videoflip method={self._flip_method()} "
            "! videoconvert "
            "! video/x-raw,format=YUY2 "
            f"! v4l2sink device={DEVICE} sync=false"
        )

        try:
            self._pipeline = Gst.parse_launch(description)
            self._appsrc = self._pipeline.get_by_name("source")
            self._appsrc.set_property(
                "caps", Gst.Caps.from_string("image/jpeg,framerate=30/1")
            )

            self._bus = self._pipeline.get_bus()
            self._bus.add_signal_watch()
            self._bus_signal = self._bus.connect("message", self._bus_message)

            result = self._pipeline.set_state(Gst.State.PLAYING)
            if result == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("GStreamer could not start the V4L2 pipeline")
            return True
        except Exception as error:
            self._stop_pipeline()
            self._set_status(f"Virtual camera error: {error}")
            return False

    def _stop_pipeline(self):
        if self._pipeline is not None:
            self._pipeline.set_state(Gst.State.NULL)
        if self._bus is not None:
            if self._bus_signal is not None:
                self._bus.disconnect(self._bus_signal)
            self._bus.remove_signal_watch()

        self._bus_signal = None
        self._bus = None
        self._appsrc = None
        self._pipeline = None

    def _bus_message(self, _bus, message):
        if message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            detail = f": {debug}" if debug else ""
            self.enabled = False
            self._stop_pipeline()
            self._set_status(f"Virtual camera error: {error}{detail}")

    def _orientation_changed(self, _preferences, _param):
        if not self.enabled:
            return
        self._stop_pipeline()
        if not self._start_pipeline():
            self.enabled = False
        self._sync_config_widgets()

    def _window_added(self, _application, window):
        self._attach_window(window)

    def _window_removed(self, _application, window):
        self._detach_window(window)

    def _attach_window(self, window):
        if not isinstance(window, Entangle.CameraManager) or window in self._windows:
            return

        notify = window.connect("notify::camera", self._camera_changed)
        self._windows[window] = {
            "notify": notify,
            "camera": None,
            "preview": None,
        }
        self._bind_camera(window)

    def _detach_window(self, window):
        state = self._windows.pop(window, None)
        if state is None:
            return

        if state["camera"] is not None and state["preview"] is not None:
            state["camera"].disconnect(state["preview"])
        window.disconnect(state["notify"])

    def _camera_changed(self, window, _param):
        self._bind_camera(window)

    def _bind_camera(self, window):
        state = self._windows[window]
        if state["camera"] is not None and state["preview"] is not None:
            state["camera"].disconnect(state["preview"])

        camera = window.get_camera()
        state["camera"] = camera
        state["preview"] = None
        if camera is not None:
            state["preview"] = camera.connect(
                "camera-file-previewed", self._preview_frame
            )

    def _preview_frame(self, _camera, camera_file):
        if not self.enabled or self._appsrc is None:
            return

        data = camera_file.get_data()
        if not data:
            return

        payload = bytes(data)
        buffer = Gst.Buffer.new_allocate(None, len(payload), None)
        buffer.fill(0, payload)
        result = self._appsrc.emit("push-buffer", buffer)

        if result == Gst.FlowReturn.OK:
            if self._status != f"Publishing live preview to {DEVICE}":
                self._set_status(f"Publishing live preview to {DEVICE}")
        elif result != Gst.FlowReturn.FLUSHING:
            self.enabled = False
            self._stop_pipeline()
            self._set_status(f"Virtual camera stopped: {result.value_nick}")
