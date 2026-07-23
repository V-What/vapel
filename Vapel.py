"""
LightChat overlay - recoit les positions/PV pousses par light_chat.lua via HTTP
(POST local) et affiche un overlay transparent, click-through, par-dessus la
fenetre Roblox. Le menu (touche configurable, toggle ESP) vit cote Lua ;
ce script ne fait que le rendu.

A installer : pip install pywin32
"""

import ctypes
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import win32api
import win32con
import win32gui

# --- Reseau --------------------------------------------------------------
# DOIT matcher OVERLAY_ENDPOINT dans light_chat.lua.
HTTP_HOST = "127.0.0.1"
HTTP_PORT = 8787
ROBLOX_WINDOW_CLASS = "WINDOWSCLIENT"
RENDER_INTERVAL_MS = 16  # ~60 FPS, independant de la cadence d'arrivee des donnees

# --- ESP (texte au-dessus des joueurs) ------------------------------------
ESP_FONT_NAME = "Segoe UI"
ESP_FONT_SIZE = 14
ESP_FONT_BOLD = True
ESP_LABEL_WIDTH = 120
ESP_LABEL_HEIGHT = 40
ESP_NAME_COLOR = (255, 255, 255)  # nom toujours blanc
ESP_NEUTRAL_COLOR = (200, 200, 200)  # ligne PV/distance quand les PV sont masques

# Seuils de %HP (decroissants) -> couleur. Le premier seuil depasse gagne.
HEALTH_COLORS = (
    (0.6, (90, 220, 120)),
    (0.3, (230, 200, 80)),
    (0.0, (230, 80, 80)),
)

TRANSPARENT_KEY = win32api.RGB(0, 0, 0)  # couleur "trou" -> click-through


def health_color(pct):
    for threshold, color in HEALTH_COLORS:
        if pct > threshold:
            return color
    return HEALTH_COLORS[-1][1]


class Overlay:
    def __init__(self):
        self.hwnd = None
        self.players = []
        self.enabled = False  # pilote depuis le menu in-game (light_chat.lua)
        self.show_health = True
        self.show_distance = False
        self._register_class()
        self._create_window()

        log_font = win32gui.LOGFONT()
        log_font.lfFaceName = ESP_FONT_NAME
        log_font.lfHeight = -ESP_FONT_SIZE
        log_font.lfWeight = 700 if ESP_FONT_BOLD else 400
        self.font = win32gui.CreateFontIndirect(log_font)

    def _register_class(self):
        wc = win32gui.WNDCLASS()
        wc.lpfnWndProc = self._wnd_proc
        wc.lpszClassName = "LightChatOverlayPy"
        wc.hInstance = win32api.GetModuleHandle(None)
        self.class_atom = win32gui.RegisterClass(wc)

    def _create_window(self):
        ex_style = (
            win32con.WS_EX_LAYERED
            | win32con.WS_EX_TRANSPARENT
            | win32con.WS_EX_TOOLWINDOW
            | win32con.WS_EX_TOPMOST
        )
        self.hwnd = win32gui.CreateWindowEx(
            ex_style,
            self.class_atom,
            "LightChatOverlay",
            win32con.WS_POPUP,
            0, 0, 1, 1,
            0, 0,
            win32api.GetModuleHandle(None),
            None,
        )
        win32gui.SetLayeredWindowAttributes(self.hwnd, TRANSPARENT_KEY, 0, win32con.LWA_COLORKEY)

    def _wnd_proc(self, hwnd, msg, wparam, lparam):
        if msg == win32con.WM_PAINT:
            self._paint(hwnd)
            return 0
        if msg == win32con.WM_ERASEBKGND:
            return 1  # on efface deja tout dans _paint -> evite le flicker
        if msg == win32con.WM_DESTROY:
            win32gui.PostQuitMessage(0)
            return 0
        return win32gui.DefWindowProc(hwnd, msg, wparam, lparam)

    def apply_update(self, data):
        # Appele depuis le thread du serveur HTTP a chaque requete recue.
        # Simple reassignation d'attributs -> pas besoin de lock (le GIL rend
        # ces affectations atomiques, et _paint lit toujours un etat coherent).
        self.enabled = bool(data.get("enabled", False))
        self.show_health = bool(data.get("showHealth", True))
        self.show_distance = bool(data.get("showDistance", False))
        self.players = data.get("players", [])

    def _tick(self):
        self._sync_position()
        win32gui.InvalidateRect(self.hwnd, None, False)
        win32gui.UpdateWindow(self.hwnd)  # force le WM_PAINT immediatement (pas via la queue)

    def _sync_position(self):
        roblox_hwnd = win32gui.FindWindow(ROBLOX_WINDOW_CLASS, None)
        if not roblox_hwnd or win32gui.GetForegroundWindow() != roblox_hwnd:
            win32gui.ShowWindow(self.hwnd, win32con.SW_HIDE)
            return

        left, top, right, bottom = win32gui.GetClientRect(roblox_hwnd)
        origin_x, origin_y = win32gui.ClientToScreen(roblox_hwnd, (0, 0))
        width, height = max(right - left, 1), max(bottom - top, 1)

        win32gui.SetWindowPos(
            self.hwnd,
            win32con.HWND_TOPMOST,
            origin_x, origin_y, width, height,
            win32con.SWP_NOACTIVATE | win32con.SWP_SHOWWINDOW,
        )

    def _paint(self, hwnd):
        hdc, ps = win32gui.BeginPaint(hwnd)
        left, top, right, bottom = win32gui.GetClientRect(hwnd)
        width, height = max(right - left, 1), max(bottom - top, 1)

        # Double buffering : on dessine dans un bitmap memoire puis on blit
        # d'un coup, sinon le FillRect + DrawText en direct scintille a 60Hz.
        mem_dc = win32gui.CreateCompatibleDC(hdc)
        bitmap = win32gui.CreateCompatibleBitmap(hdc, width, height)
        old_bitmap = win32gui.SelectObject(mem_dc, bitmap)
        old_font = win32gui.SelectObject(mem_dc, self.font)

        brush = win32gui.CreateSolidBrush(TRANSPARENT_KEY)
        win32gui.FillRect(mem_dc, (0, 0, width, height), brush)
        win32gui.DeleteObject(brush)

        if self.enabled:
            win32gui.SetBkMode(mem_dc, win32con.TRANSPARENT)
            half_w, half_h = ESP_LABEL_WIDTH // 2, ESP_LABEL_HEIGHT // 2
            for p in self.players:
                x, y = int(p["x"]), int(p["y"])

                win32gui.SetTextColor(mem_dc, win32api.RGB(*ESP_NAME_COLOR))
                win32gui.DrawText(
                    mem_dc, p["name"], -1,
                    (x - half_w, y - half_h, x + half_w, y - half_h + 18),
                    win32con.DT_CENTER,
                )

                info_parts = []
                if self.show_health:
                    info_parts.append("{}/{}".format(p["hp"], p["maxHp"]))
                if self.show_distance and p.get("dist") is not None:
                    info_parts.append("{}m".format(p["dist"]))

                if info_parts:
                    if self.show_health:
                        pct = p["hp"] / max(p["maxHp"], 1)
                        color = health_color(pct)
                    else:
                        color = ESP_NEUTRAL_COLOR
                    win32gui.SetTextColor(mem_dc, win32api.RGB(*color))
                    win32gui.DrawText(
                        mem_dc, " | ".join(info_parts), -1,
                        (x - half_w, y - half_h + 18, x + half_w, y + half_h),
                        win32con.DT_CENTER,
                    )

        win32gui.BitBlt(hdc, 0, 0, width, height, mem_dc, 0, 0, win32con.SRCCOPY)

        win32gui.SelectObject(mem_dc, old_font)
        win32gui.SelectObject(mem_dc, old_bitmap)
        win32gui.DeleteObject(bitmap)
        win32gui.DeleteDC(mem_dc)
        win32gui.EndPaint(hwnd, ps)

    def run(self):
        # WM_TIMER est basse-priorite et fusionne/retarde ses ticks quand la
        # queue de messages est occupee -> boucle explicite a la place, avec
        # la resolution timer Windows forcee a 1ms (sinon ~15.6ms par defaut).
        ctypes.windll.winmm.timeBeginPeriod(1)
        try:
            while True:
                win32gui.PumpWaitingMessages()
                self._tick()
                time.sleep(RENDER_INTERVAL_MS / 1000)
        finally:
            ctypes.windll.winmm.timeEndPeriod(1)


def make_update_handler(overlay):
    class UpdateHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self.send_response(400)
                self.end_headers()
                return
            overlay.apply_update(data)
            self.send_response(204)
            self.end_headers()

        def log_message(self, format, *args):
            pass  # coupe le log par-requete par defaut (spam a 60Hz)

    return UpdateHandler


def run_http_server(overlay):
    server = ThreadingHTTPServer((HTTP_HOST, HTTP_PORT), make_update_handler(overlay))
    server.serve_forever()


def main():
    overlay = Overlay()
    threading.Thread(target=run_http_server, args=(overlay,), daemon=True).start()
    overlay.run()


if __name__ == "__main__":
    main()
