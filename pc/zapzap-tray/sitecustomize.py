"""ZapZap tray icon override (loaded through PYTHONPATH set with `flatpak override`).

Replaces ZapZap's built-in symbolic tray icon with the white outline WhatsApp icon of the Simpleton
theme. Only the SVG template changes; ZapZap still fills in the colour and the unread-count badge.
If ZapZap ever renames the class or attribute, the hook does nothing and the original icon is used.
"""
import importlib.abc
import importlib.util
import sys

# The runtime ships its own sitecustomize (it adds /app/.../site-packages, where ZapZap lives).
# This file shadows it, so run it first.
_RUNTIME_SITECUSTOMIZE = "/usr/lib/python{}.{}/sitecustomize.py".format(*sys.version_info[:2])
try:
    with open(_RUNTIME_SITECUSTOMIZE) as _fh:
        exec(compile(_fh.read(), _RUNTIME_SITECUSTOMIZE, "exec"), {"__name__": "_runtime_sitecustomize"})
except OSError:
    pass

TARGET = "zapzap.assets.icons.tray_icon"

# Simpleton icon (24x24, stroke 1.5) scaled to ZapZap's 256x256 canvas; {color} and {notify} are ZapZap's placeholders.
SYMBOLIC = """<?xml version="1.0" encoding="utf-8"?>
<svg viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
  <g transform="matrix(10.6667, 0, 0, 10.6667, 0, 0)" fill="none" stroke="{color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 3.5a8.5 8.5 0 0 0-7.4 12.7L3.5 20.5l4.4-1.1A8.5 8.5 0 1 0 12 3.5z"/>
    <path d="M9.2 8.6c.3-.4.8-.4 1 0l.7 1.5-.6.8c.5 1.1 1.4 2 2.5 2.5l.8-.6 1.5.7c.4.2.4.7 0 1-.9.8-2.2.8-3.2.2a8 8 0 0 1-2.9-2.9c-.6-1-.6-2.3.2-3.2z" stroke-width="1.2"/>
  </g>
  {notify}
</svg>
"""


class _PatchLoader(importlib.abc.Loader):
    def __init__(self, original):
        self.original = original

    def create_module(self, spec):
        return self.original.create_module(spec)

    def exec_module(self, module):
        self.original.exec_module(module)
        tray = getattr(module, "TrayIcon", None)
        if tray is not None and hasattr(tray, "_SYMBOLIC"):
            tray._SYMBOLIC = SYMBOLIC


class _Finder(importlib.abc.MetaPathFinder):
    def find_spec(self, name, path=None, target=None):
        if name != TARGET:
            return None
        others = [f for f in sys.meta_path if f is not self]
        spec = None
        for finder in others:
            find = getattr(finder, "find_spec", None)
            spec = find(name, path, target) if find else None
            if spec is not None:
                break
        if spec is None or spec.loader is None:
            return None
        spec.loader = _PatchLoader(spec.loader)
        return spec


sys.meta_path[0:0] = [_Finder()]
