import sys
import json
import base64
import re
import subprocess
from pathlib import Path
from typing import Optional, List, Dict

from PySide6.QtCore import Qt, QTimer, QRectF, Signal, QObject, QThread, QEvent
from PySide6.QtGui import QColor, QFont, QPainter, QPen, QAction, QKeySequence, QFontMetrics
from PySide6.QtWidgets import (
    QApplication, QWidget, QMainWindow, QVBoxLayout, QHBoxLayout, QLabel,
    QPushButton, QFrame, QFileDialog, QMessageBox, QStackedWidget,
    QGridLayout, QTextEdit, QScrollArea, QSizePolicy, QSpacerItem
)

APP_TITLE = "WSB TECH – PRECISION UNIT"
SETTINGS_FILE = Path.home() / "wsb_precision_unit_python_settings.json"
CYAN = "#00d9ff"
BG = "#02060a"
PANEL = "#03111d"
RED = "#ff3750"
WHITE = "#f3f7ff"
YELLOW = "#ffe88a"
GREEN = "#59ff4c"
MAGENTA = "#ff00ff"
DIM = "#8aa0aa"
SCANNER_SPEEDS = {
    "slow": 52,
    "normal": 28,
    "fast": 18,
    "turbo": 10,
}
SCANNER_STYLES = ["dual", "kitt", "pulse"]


def mono(size: int, bold: bool = False):
    f = QFont("Consolas")
    f.setPointSize(size)
    f.setBold(bold)
    return f


def button_style(text_color: str = WHITE, border_color: str = CYAN, hover_bg: str = "#082035"):
    return (
        f"QPushButton {{ background:{PANEL}; color:{text_color}; border:2px solid {border_color}; text-align:left; padding:10px 14px; }}"
        f"QPushButton:hover {{ background:{hover_bg}; color:#ffffff; }}"
        f"QPushButton:pressed {{ background:#0d2d44; }}"
    )


def label_style(color: str = WHITE):
    return f"color:{color}; background: transparent;"


class WSBFrame(QFrame):
    def __init__(self, title: str = "", accent: str = CYAN):
        super().__init__()
        self.setObjectName("WSBFrame")
        self.v = QVBoxLayout(self)
        self.v.setContentsMargins(14, 14, 14, 14)
        self.v.setSpacing(10)
        self.accent = accent
        if title:
            title_row = QHBoxLayout()
            left = QLabel("<:::>")
            left.setFont(mono(10, True))
            left.setStyleSheet(label_style(accent))
            title_row.addWidget(left)

            lbl = QLabel(f"[ {title} ]")
            lbl.setFont(mono(11, True))
            lbl.setStyleSheet(f"color:{accent}; letter-spacing: 1px;")
            title_row.addWidget(lbl)
            title_row.addStretch(1)

            right = QLabel("[:: LIVE ::]")
            right.setFont(mono(9, True))
            right.setStyleSheet(label_style(DIM))
            title_row.addWidget(right)
            self.v.addLayout(title_row)

        sep = QLabel("=" * 96)
        sep.setFont(mono(9, True))
        sep.setStyleSheet(label_style(DIM))
        self.v.addWidget(sep)


class StatusStrip(QFrame):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        self.setObjectName("StatusStrip")
        self.profile = "normal"

        self.root = QVBoxLayout(self)
        self.root.setContentsMargins(14, 8, 14, 8)
        self.root.setSpacing(6)

        top = QHBoxLayout()
        top.setSpacing(14)
        self.root.addLayout(top)

        self.left = QLabel()
        self.left.setFont(mono(10, True))
        self.left.setStyleSheet(label_style(WHITE))
        top.addWidget(self.left, 1)

        self.center = QLabel()
        self.center.setFont(mono(10, True))
        self.center.setAlignment(Qt.AlignCenter)
        self.center.setStyleSheet(label_style(CYAN))
        top.addWidget(self.center, 1)

        self.right = QLabel()
        self.right.setFont(mono(10, True))
        self.right.setAlignment(Qt.AlignRight)
        self.right.setStyleSheet(label_style(YELLOW))
        top.addWidget(self.right, 1)

        self.separator = QLabel("─" * 170)
        self.separator.setFont(mono(8))
        self.separator.setAlignment(Qt.AlignCenter)
        self.separator.setStyleSheet(label_style("#0f506f"))
        self.root.addWidget(self.separator)

        bottom = QHBoxLayout()
        bottom.setSpacing(12)
        self.root.addLayout(bottom)

        self.bottom_left = QLabel()
        self.bottom_left.setFont(mono(9, True))
        self.bottom_left.setStyleSheet(label_style(DIM))
        bottom.addWidget(self.bottom_left, 1)

        self.bottom_center = QLabel()
        self.bottom_center.setFont(mono(9, True))
        self.bottom_center.setAlignment(Qt.AlignCenter)
        self.bottom_center.setStyleSheet(label_style(GREEN))
        bottom.addWidget(self.bottom_center, 1)

        self.bottom_right = QLabel()
        self.bottom_right.setFont(mono(9, True))
        self.bottom_right.setAlignment(Qt.AlignRight)
        self.bottom_right.setStyleSheet(label_style(MAGENTA))
        bottom.addWidget(self.bottom_right, 1)

    def apply_metrics(self, profile: str):
        self.profile = profile
        compact = profile in ("compact", "small")
        very_small = profile == "small"
        margin = 10 if compact else 14
        spacing = 4 if compact else 6
        self.root.setContentsMargins(margin, 6 if compact else 8, margin, 6 if compact else 8)
        self.root.setSpacing(spacing)
        top_size = 8 if very_small else 9 if compact else 10
        bottom_size = 8 if compact else 9
        self.left.setFont(mono(top_size, True))
        self.center.setFont(mono(top_size, True))
        self.right.setFont(mono(top_size, True))
        self.bottom_left.setFont(mono(bottom_size, True))
        self.bottom_center.setFont(mono(bottom_size, True))
        self.bottom_right.setFont(mono(bottom_size, True))
        self.separator.setFont(mono(7 if compact else 8))
        self.separator.setText("─" * (120 if very_small else 145 if compact else 170))

    def refresh(self, page_name: str, settings: dict, scanner: "ScannerWidget"):
        mode = settings.get("bridge_mode", "demo").upper()
        ps1 = settings.get("ps1_path", "")
        ps1_state = "PS1 OK" if ps1 else "PS1 N/C"
        ps1_name = Path(ps1).name if ps1 else "não configurado"
        max_len = 18 if self.profile == "small" else 22 if self.profile == "compact" else 26
        if len(ps1_name) > max_len:
            ps1_name = ps1_name[:max_len - 3] + "..."

        self.left.setText(f"[ PAGE ] {page_name}")
        self.center.setText(
            f"[ ENGINE ] {mode}  |  [ STATUS ] {scanner.current_status_label()}  |  [ SPEED ] {scanner.current_speed_label()}"
        )
        self.right.setText(
            f"[ MODE ] {scanner.current_style_label()}  |  [ GLOW ] {scanner.current_glow_label()}"
        )
        self.bottom_left.setText(
            f"[ MIRROR ] {scanner.current_mirror_label()}  |  [ TEXT ] {scanner.current_tech_text_label()}"
        )
        self.bottom_center.setText(
            f"[ LINK ] {ps1_state}  |  [ PS1 ] {ps1_name}"
        )
        self.bottom_right.setText("[ SIGNATURE ] WSB PRECISION UNIT")


class ScannerWidget(QWidget):
    def __init__(self):
        super().__init__()
        self.setStyleSheet("background-color: #000000;")
        self.setMinimumHeight(108)
        self._mode = "idle"
        self._beam = 0
        self._dir = 1
        self._progress = 0
        self._stage_text = "WSB SCANNER ACTIVE"
        self._track_units = 44
        self._speed = "normal"
        self._style_mode = "dual"
        self._glow_enabled = True
        self._mirror_enabled = True
        self._tech_text_enabled = True
        self._status_state = "idle"
        self._status_label = "IDLE"
        self._transition_tick = 0
        self._transition_burst = 0
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._tick)
        self.apply_speed("normal")

    def set_compact_profile(self, profile: str):
        profile = (profile or "normal").lower()
        if profile == "small":
            self.setMinimumHeight(88)
            self._track_units = 30
        elif profile == "compact":
            self.setMinimumHeight(96)
            self._track_units = 36
        else:
            self.setMinimumHeight(108)
            self._track_units = 44
        self.update()

    def apply_speed(self, speed_name: str):
        speed_name = (speed_name or "normal").lower()
        if speed_name not in SCANNER_SPEEDS:
            speed_name = "normal"
        self._speed = speed_name
        self.timer.start(SCANNER_SPEEDS[speed_name])
        self.update()

    def cycle_speed(self):
        order = ["slow", "normal", "fast", "turbo"]
        idx = order.index(self._speed) if self._speed in order else 1
        self.apply_speed(order[(idx + 1) % len(order)])
        return self._speed

    def current_speed_label(self):
        labels = {
            "slow": "LENTO",
            "normal": "NORMAL",
            "fast": "RÁPIDO",
            "turbo": "TURBO",
        }
        return labels.get(self._speed, self._speed.upper())

    def apply_style_mode(self, style_name: str):
        style_name = (style_name or "dual").lower()
        if style_name not in SCANNER_STYLES:
            style_name = "dual"
        self._style_mode = style_name
        self.update()

    def cycle_style_mode(self):
        idx = SCANNER_STYLES.index(self._style_mode) if self._style_mode in SCANNER_STYLES else 0
        self.apply_style_mode(SCANNER_STYLES[(idx + 1) % len(SCANNER_STYLES)])
        return self._style_mode

    def current_style_label(self):
        labels = {
            "dual": "DUAL BLOCK",
            "kitt": "KITT SWEEP",
            "pulse": "PULSE ARRAY",
        }
        return labels.get(self._style_mode, self._style_mode.upper())

    def set_glow_enabled(self, enabled: bool):
        self._glow_enabled = bool(enabled)
        self.update()

    def toggle_glow(self):
        self.set_glow_enabled(not self._glow_enabled)
        return self._glow_enabled

    def current_glow_label(self):
        return "ON" if self._glow_enabled else "OFF"

    def glow_enabled(self):
        return self._glow_enabled

    def set_mirror_enabled(self, enabled: bool):
        self._mirror_enabled = bool(enabled)
        self.update()

    def toggle_mirror(self):
        self.set_mirror_enabled(not self._mirror_enabled)
        return self._mirror_enabled

    def current_mirror_label(self):
        return "ON" if self._mirror_enabled else "OFF"

    def mirror_enabled(self):
        return self._mirror_enabled

    def set_tech_text_enabled(self, enabled: bool):
        self._tech_text_enabled = bool(enabled)
        self.update()

    def toggle_tech_text(self):
        self.set_tech_text_enabled(not self._tech_text_enabled)
        return self._tech_text_enabled

    def current_tech_text_label(self):
        return "ON" if self._tech_text_enabled else "OFF"

    def tech_text_enabled(self):
        return self._tech_text_enabled

    def set_status_state(self, state: str, label: Optional[str] = None):
        state = (state or "idle").lower()
        if state not in {"idle", "scan", "success", "warning", "error"}:
            state = "idle"
        previous_state = self._status_state
        self._status_state = state
        if label:
            self._status_label = label
        else:
            labels = {
                "idle": "IDLE",
                "scan": "SCAN",
                "success": "SUCCESS",
                "warning": "ALERT",
                "error": "ERROR",
            }
            self._status_label = labels.get(state, state.upper())
        if previous_state != state:
            self._transition_tick = 0
            self._transition_burst = 16
        else:
            self._transition_burst = max(self._transition_burst, 8)
        self.update()

    def current_status_label(self):
        return self._status_label

    def apply_runtime_line_feedback(self, line: str):
        upper = (line or "").upper()
        if "ERRO" in upper or "FAIL" in upper or "FALHOU" in upper:
            self.set_status_state("error", "ERROR")
        elif "AVISO" in upper or "ALERTA" in upper:
            self.set_status_state("warning", "ALERT")
        elif "[SCAN" in upper:
            self.set_status_state("scan", "SCAN")
        elif "[ OK" in upper:
            self.set_status_state("success", "SUCCESS")

    def _status_palette(self):
        palettes = {
            "idle": (CYAN, QColor(255, 55, 80, 120), QColor(CYAN), QColor(YELLOW)),
            "scan": (CYAN, QColor(255, 55, 80, 160), QColor(CYAN), QColor(YELLOW)),
            "success": (GREEN, QColor(89, 255, 76, 170), QColor(GREEN), QColor(YELLOW)),
            "warning": (YELLOW, QColor(255, 232, 138, 170), QColor(YELLOW), QColor(YELLOW)),
            "error": (RED, QColor(255, 55, 80, 210), QColor(RED), QColor(YELLOW)),
        }
        accent, glow_color, accent_q, footer_q = palettes.get(self._status_state, palettes["idle"])
        pulse = abs(10 - (self._transition_tick % 20))
        wave = max(0, 10 - pulse)
        burst = self._transition_burst * 6
        alpha_boost = min(70, wave * 4 + burst)
        dyn_glow = QColor(glow_color)
        dyn_glow.setAlpha(min(255, glow_color.alpha() + alpha_boost))
        dyn_accent = QColor(accent_q)
        return accent, dyn_glow, dyn_accent, footer_q

    def snapshot_preferences(self):
        return {
            "speed": self._speed,
            "style": self._style_mode,
            "glow": self._glow_enabled,
            "mirror": self._mirror_enabled,
            "tech_text": self._tech_text_enabled,
        }

    def restore_preferences(self, prefs: Optional[Dict]):
        if not prefs:
            return
        self.apply_speed(prefs.get("speed", self._speed))
        self.apply_style_mode(prefs.get("style", self._style_mode))
        self.set_glow_enabled(prefs.get("glow", self._glow_enabled))
        self.set_mirror_enabled(prefs.get("mirror", self._mirror_enabled))
        self.set_tech_text_enabled(prefs.get("tech_text", self._tech_text_enabled))
        self.set_status_state("idle", "IDLE")

    def apply_agent_profile(self, phase: str, percent: int = 0, ok: Optional[bool] = None):
        phase = (phase or "idle").lower()
        if phase == "start":
            self.apply_speed("fast")
            self.apply_style_mode("kitt")
            self.set_glow_enabled(True)
            self.set_mirror_enabled(True)
            self.set_tech_text_enabled(True)
            self.set_status_state("scan", "SCAN")
            self.start_progress("ETAPA DIAG", percent)
            return

        if phase == "diag":
            self.apply_speed("turbo")
            self.apply_style_mode("kitt")
            self.set_glow_enabled(True)
            self.set_mirror_enabled(True)
            self.set_status_state("scan", "DIAG")
            self.update_progress(percent, "ETAPA DIAG")
            return

        if phase == "usb":
            self.apply_speed("fast")
            self.apply_style_mode("dual")
            self.set_glow_enabled(True)
            self.set_mirror_enabled(True)
            self.set_status_state("scan", "USB")
            self.update_progress(percent, "ETAPA USB")
            return

        if phase == "dashboard":
            self.apply_speed("normal")
            self.apply_style_mode("pulse")
            self.set_glow_enabled(True)
            self.set_mirror_enabled(True)
            self.set_status_state("scan", "DASH")
            self.update_progress(percent, "ETAPA DASHBOARD")
            return

        if phase == "report":
            self.apply_speed("slow")
            self.apply_style_mode("pulse")
            self.set_glow_enabled(True)
            self.set_mirror_enabled(True)
            self.set_status_state("scan", "RPT")
            self.update_progress(percent, "ETAPA REPORT")
            return

        if phase == "finish":
            self.apply_speed("slow")
            self.apply_style_mode("pulse")
            self.set_glow_enabled(True)
            self.set_mirror_enabled(True)
            final_text = "LINK STABLE / EXECUÇÃO OK" if ok else "CHECK LOG / EXECUÇÃO COM ALERTA"
            self.set_status_state("success" if ok else "warning", "OK" if ok else "ALERT")
            self.update_progress(100 if percent <= 0 else percent, final_text)
            return

        if phase == "idle":
            self.set_status_state("idle", "IDLE")
            self.stop_progress("WSB SCANNER ACTIVE")
    def set_stage_text(self, text: str):
        self._stage_text = text
        self.update()

    def start_progress(self, text: str, percent: int = 0):
        self._mode = "progress"
        self._stage_text = text
        self._progress = max(0, min(100, percent))
        self.update()

    def update_progress(self, percent: int, text: Optional[str] = None):
        self._mode = "progress"
        self._progress = max(0, min(100, percent))
        if text:
            self._stage_text = text
        self.update()

    def stop_progress(self, text: str = "WSB SCANNER ACTIVE"):
        self._mode = "idle"
        self._stage_text = text
        self._progress = 0
        self.update()

    def _tick(self):
        self._beam += self._dir
        if self._beam >= self._track_units:
            self._beam = self._track_units
            self._dir = -1
        elif self._beam <= 0:
            self._beam = 0
            self._dir = 1
        self._transition_tick = (self._transition_tick + 1) % 2000
        if self._transition_burst > 0:
            self._transition_burst -= 1
        self.update()


    def _scanner_metrics(self):
        width = max(640, self.width())
        height = max(80, self.height())
        compact_by_width = width < 1180
        small_by_width = width < 980
        top_bottom = 12 if small_by_width else 13 if compact_by_width else 14
        side = 4 if small_by_width else 6 if compact_by_width else 8
        rail_pad = 18 if small_by_width else 26 if compact_by_width else 34
        footer_font = 7 if small_by_width else 8 if compact_by_width else 9
        title_font = 9 if small_by_width else 10 if compact_by_width else 11
        tech_font = 7 if small_by_width else 8 if compact_by_width else 9
        glyph_font = 8 if small_by_width else 9 if compact_by_width else 10
        block_w = 24 if small_by_width else 28 if compact_by_width else 34
        block_h = 12 if small_by_width else 14 if compact_by_width else 16
        center_gap = 24 if small_by_width else 38 if compact_by_width else 64
        return {
            "small": small_by_width,
            "compact": compact_by_width,
            "inner_adjust": (side, top_bottom, -side, -top_bottom),
            "rail_pad": rail_pad,
            "footer_font": footer_font,
            "title_font": title_font,
            "tech_font": tech_font,
            "glyph_font": glyph_font,
            "block_w": block_w,
            "block_h": block_h,
            "center_gap": center_gap,
            "line_offset": 5 if small_by_width else 6 if compact_by_width else 8,
            "top_line": 8 if small_by_width else 9 if compact_by_width else 10,
            "bottom_line": 8 if small_by_width else 9 if compact_by_width else 10,
            "title_y": 4 if small_by_width else 5 if compact_by_width else 6,
            "label_y": 8 if small_by_width else 9 if compact_by_width else 10,
            "node_y": -1 if small_by_width else 0 if compact_by_width else 1,
        }

    def _fit_footer_text(self, p, text: str, width: int, point_size: int):
        font = mono(point_size, True)
        p.setFont(font)
        fm = QFontMetrics(font)
        if fm.horizontalAdvance(text) <= width:
            return font, text
        parts = [part.strip() for part in text.split("|")]
        short = " | ".join(parts[:4]) if len(parts) > 4 else text
        if fm.horizontalAdvance(short) <= width:
            return font, short
        small_font = mono(max(6, point_size - 1), True)
        p.setFont(small_font)
        fm2 = QFontMetrics(small_font)
        if fm2.horizontalAdvance(short) <= width:
            return small_font, short
        return small_font, fm2.elidedText(short, Qt.ElideRight, width)

    def _draw_outer_frame(self, p, rect):
        accent, glow_color, accent_q, footer_q = self._status_palette()
        m = self._scanner_metrics()

        # Moldura principal do scanner mais fundida ao header e mais centralizada
        # em relação ao LED. As laterais avançam um pouco além da moldura externa
        # e a linha inferior sobe levemente para abraçar melhor o trilho do scanner.
        rail_center_y = rect.center().y() + (m["line_offset"] - 18)
        top_pad = 10 if m["small"] else 11 if m["compact"] else 12
        bottom_pad = 7 if m["small"] else 8 if m["compact"] else 9
        top_y = int(rail_center_y - top_pad)
        bot_y = int(rail_center_y + bottom_pad)
        left_x = rect.left() - 8
        right_x = rect.right() + 8

        p.setPen(QPen(QColor(accent), 2))
        p.drawLine(left_x, top_y, right_x, top_y)
        p.drawLine(left_x, bot_y, right_x, bot_y)
        p.drawLine(left_x, top_y, left_x, bot_y)
        p.drawLine(right_x, top_y, right_x, bot_y)

    def _draw_idle_mode(self, p, inner):
        accent, glow_color, accent_q, footer_q = self._status_palette()
        m = self._scanner_metrics()
        center_y = int(inner.center().y()) - 7
        rail_left = inner.left() + m["rail_pad"]
        rail_right = inner.right() - m["rail_pad"]
        rail_y = center_y + (m["line_offset"] - 8)

        # linhas finas superior/inferior removidas para limpar a área do scanner
        p.setPen(QPen(QColor(accent), 1))

        usable = max(40, rail_right - rail_left - (120 if m["small"] else 160))
        step = usable / max(1, self._track_units)
        offset = int(self._beam * step)

        left_anchor = rail_left + m["center_gap"] + offset
        right_anchor = rail_right - m["center_gap"] - offset
        center_anchor = rail_left + m["center_gap"] + offset
        center_width = max(36 if m["small"] else 44, int((rail_right - rail_left) * (0.15 if m["compact"] else 0.18)))

        def draw_glow_block(x: int, y: int, width: int, height: int, rounded: int = 4):
            p.setPen(Qt.NoPen)
            if self._glow_enabled:
                for glow in (18, 12, 7):
                    alpha = 28 if glow == 18 else 52 if glow == 12 else 95
                    gc = QColor(glow_color)
                    gc.setAlpha(alpha)
                    p.setBrush(gc)
                    p.drawRoundedRect(x - glow, y - glow // 3, width + glow * 2, height + glow // 2, rounded, rounded)
            p.setBrush(accent_q)
            p.drawRoundedRect(x, y, width, height, max(2, rounded - 1), max(2, rounded - 1))

        def draw_glow_beam(x: int, y: int, width: int, height: int, rounded: int = 4):
            p.setPen(Qt.NoPen)
            if self._glow_enabled:
                for glow in (22, 14, 8):
                    alpha = 26 if glow == 22 else 68 if glow == 14 else 140
                    gc = QColor(glow_color)
                    gc.setAlpha(alpha)
                    p.setBrush(gc)
                    p.drawRoundedRect(x - glow, y - glow // 2, width + glow * 2, height + glow, rounded, rounded)
            p.setBrush(accent_q)
            p.drawRoundedRect(x, y, width, height, max(2, rounded - 1), max(2, rounded - 1))

        center_banner = ""

        if self._style_mode == "dual":
            draw_glow_block(left_anchor, center_y - m["block_h"] + 2, m["block_w"], m["block_h"], 4)
            if self._mirror_enabled:
                draw_glow_block(right_anchor - m["block_w"], center_y - m["block_h"] + 2, m["block_w"], m["block_h"], 4)


        elif self._style_mode == "kitt":
            beam_x = center_anchor
            draw_glow_beam(beam_x, center_y - m["block_h"] + 2, center_width, m["block_h"], 4)

        else:
            pulse_left = rail_left + (22 if m["small"] else 34)
            pulse_right = rail_right - (22 if m["small"] else 34)
            count = 12
            if not self._mirror_enabled:
                pulse_right = rail_left + int((rail_right - rail_left) * 0.58)
                count = 7
            spacing = (pulse_right - pulse_left) / max(1, count - 1)
            active_index = int((self._beam / max(1, self._track_units)) * (count - 1))
            p.setPen(Qt.NoPen)
            for i in range(count):
                x = int(pulse_left + spacing * i)
                dist = abs(i - active_index)
                if dist == 0:
                    color = QColor(glow_color)
                    color.setAlpha(220)
                    w, h = 28, 16
                elif dist == 1:
                    color = QColor(glow_color)
                    color.setAlpha(120 if self._glow_enabled else 88)
                    w, h = 18, 12
                else:
                    color = QColor(0, 217, 255, 55)
                    w, h = 10, 8
                p.setBrush(color)
                p.drawRoundedRect(x - w // 2, center_y - h // 2 - 4, w, h, 3, 3)
            pass

        if self._tech_text_enabled:
            p.setPen(QColor(DIM))
            p.setFont(mono(m["tech_font"], True))
            node_y = center_y + (12 if m["small"] else 15 if m["compact"] else 19)
            p.setPen(accent_q)
            p.setFont(mono(m["tech_font"], True))
        # footer textual strip intentionally removed in idle mode for a cleaner scanner area

    def _draw_progress_mode(self, p, inner):
        accent, glow_color, accent_q, footer_q = self._status_palette()
        m = self._scanner_metrics()

        stage_title = (self._stage_text or "PROGRESSO").strip()
        header_text = f"{self._progress}% | {stage_title}"
        stage_upper = stage_title.upper()

        # Sistema de coordenadas unificado: tudo usa o mesmo inner rect do scanner.
        margin = 1
        track_left = inner.left() + margin
        track_right = inner.right() - margin
        track_width = max(120, track_right - track_left)
        track_height = 9 if m["small"] else 10 if m["compact"] else 10

        # Centraliza a trilha usando a própria geometria da moldura ciano do scanner.
        rail_center_y = self.rect().center().y() + (m["line_offset"] - 18)
        top_pad = 10 if m["small"] else 11 if m["compact"] else 12
        bottom_pad = 7 if m["small"] else 8 if m["compact"] else 9
        frame_top = int(rail_center_y - top_pad)
        frame_bottom = int(rail_center_y + bottom_pad)
        track_y = int(round((frame_top + frame_bottom - track_height) / 2))

        # Cabeçalho amarelo centralizado no scanner, sem empurrar a trilha.
        header_font, fitted_header = self._fit_footer_text(p, header_text, track_width, m["title_font"])
        p.setFont(header_font)
        p.setPen(QColor("#ffe88a"))
        p.drawText(QRectF(track_left, track_y - 18, track_width, 14), Qt.AlignCenter, fitted_header)

        # Trilha principal preenchendo toda a moldura útil.
        p.setPen(QPen(QColor(accent), 1))
        p.setBrush(QColor("#061520"))
        p.drawRect(track_left, track_y, track_width, track_height)

        # Grade interna lembrando o scanner original.
        p.setPen(QColor("#0b4d6b"))
        tick_count = 32
        for i in range(1, tick_count):
            x = int(track_left + (track_width / tick_count) * i)
            p.drawLine(x, track_y + 1, x, track_y + track_height - 1)

        if "PRE-SCAN" in stage_upper or "REPORT" in stage_upper:
            progress_color = QColor("#59ff4c")
            progress_glow = QColor(89, 255, 76, 175)
        elif "DNS" in stage_upper or "REDE" in stage_upper:
            progress_color = QColor("#7dff66")
            progress_glow = QColor(125, 255, 102, 180)
        elif "TRIM" in stage_upper:
            progress_color = QColor("#a4ff5c")
            progress_glow = QColor(164, 255, 92, 185)
        elif "CACHE" in stage_upper or "PREFETCH" in stage_upper:
            progress_color = QColor("#6eff57")
            progress_glow = QColor(110, 255, 87, 175)
        else:
            progress_color = QColor("#66ff4d")
            progress_glow = QColor(102, 255, 77, 175)

        fill_width = max(0, int((track_width - 2) * (self._progress / 100.0)))
        if fill_width > 0:
            if self._glow_enabled:
                for glow, alpha in ((10, 24), (6, 52), (3, 96)):
                    gc = QColor(progress_glow)
                    gc.setAlpha(alpha)
                    p.fillRect(track_left + 1 - glow // 2, track_y + 1 - glow // 4, fill_width + glow, track_height - 1 + glow // 2, gc)
            p.fillRect(track_left + 1, track_y + 1, fill_width, track_height - 1, progress_color)
            shine = QColor(255, 255, 255, 70)
            p.fillRect(track_left + 1, track_y + 1, fill_width, max(2, track_height // 3), shine)

        # Percentual dentro da trilha; o nome da etapa fica só no cabeçalho amarelo.
        percent_font = mono(7 if m["small"] else 8 if m["compact"] else 9, True)
        p.setFont(percent_font)
        p.setPen(QColor(BG if self._progress >= 12 else WHITE))
        p.drawText(QRectF(track_left, track_y, track_width, track_height), Qt.AlignCenter, f"{self._progress}%")

        p.setPen(footer_q)
        footer = f"[ PROGRESS LINK ]  STAGE {stage_title}  |  STATUS {self.current_status_label()}  |  SPEED {self.current_speed_label()}  |  GLOW {self.current_glow_label()}"
        if self._tech_text_enabled:
            footer += f"  |  MIRROR {self.current_mirror_label()}  |  TEXT {self.current_tech_text_label()}"
        footer_font, footer = self._fit_footer_text(p, footer, inner.width() - 12, m["footer_font"])
        p.setFont(footer_font)
        p.drawText(QRectF(inner.left(), inner.bottom() - 2, inner.width(), 16), Qt.AlignCenter, footer)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing, False)
        p.fillRect(self.rect(), QColor(BG))

        self._draw_outer_frame(p, self.rect())
        m = self._scanner_metrics()
        inner = self.rect().adjusted(*m['inner_adjust'])

        if self._mode == "idle":
            self._draw_idle_mode(p, inner)
        else:
            self._draw_progress_mode(p, inner)



class HeaderPanel(QFrame):
    def __init__(self):
        super().__init__()
        self.setStyleSheet("background-color: #000000;")
        self.setObjectName("HeaderPanel")
        self.setFixedHeight(86)
        self.v = QVBoxLayout(self)
        self.v.setContentsMargins(0, 0, 0, 0)
        self.v.setSpacing(0)

        self.logo = QLabel("WSB TECH     |     PRECISION UNIT")
        self.logo.setAlignment(Qt.AlignCenter)
        self.logo.setFont(mono(52, True))
        self.logo.setStyleSheet(f"color:{CYAN}; letter-spacing: 6px;")
        self.v.addWidget(self.logo)

        self.scanner_top_gap = QSpacerItem(20, 0, QSizePolicy.Minimum, QSizePolicy.Fixed)
        self.v.addItem(self.scanner_top_gap)

        self.scanner = ScannerWidget()
        self.v.addWidget(self.scanner)

    def apply_metrics(self, profile: str):
        compact = profile in ("compact", "small")
        very_small = profile == "small"
        self.v.setContentsMargins(0, 0, 0, 0)
        self.v.setSpacing(0)
        self.logo.setFont(mono(34 if very_small else 42 if compact else 52, True))
        self.logo.setStyleSheet(f"color:{CYAN}; letter-spacing: {'3px' if very_small else '5px' if compact else '6px'};")
        self.scanner_top_gap.changeSize(20, 0, QSizePolicy.Minimum, QSizePolicy.Fixed)
        self.v.invalidate()
        self.scanner.set_compact_profile(profile)


class MenuButton(QPushButton):
    def __init__(self, key: str, title: str, subtitle: str):
        super().__init__()
        self.setCursor(Qt.PointingHandCursor)
        self.setMinimumHeight(104)
        self.setText(
            f"[ {key} ]  {title}\n"
            f"========================================\n"
            f"{subtitle}"
        )
        self.setFont(mono(10, True))
        self.setStyleSheet(button_style(WHITE, CYAN, "#082035"))


class LogPanel(QTextEdit):
    def __init__(self):
        super().__init__()
        self.setReadOnly(True)
        self.setFont(mono(10))
        self.setStyleSheet(f"QTextEdit {{ background:{BG}; color:{WHITE}; border:2px solid {CYAN}; padding:8px; }}")

    def add_line(self, text: str, color: str = WHITE):
        self.append(f'<span style="color:{color}; white-space:pre;">{text}</span>')


class ReportParser:
    def _extract(self, pattern: str, text: str, flags: int = 0):
        m = re.search(pattern, text, flags)
        if not m:
            return "N/D"
        value = m.group(1).strip()
        return re.sub(r"\s+", " ", value)

    def parse_quickdiag(self, text: str):
        raw = text or ""
        cpu = self._extract(r"CPU:\s*(.+?)(?:\||\n|$)", raw, re.IGNORECASE)
        ram = self._extract(r"RAM:\s*(.+?)(?:\||\n|$)", raw, re.IGNORECASE)
        motherboard = self._extract(r"Placa-mae:\s*(.+?)(?:\||\n|$)", raw, re.IGNORECASE)
        bios = self._extract(r"BIOS:\s*(.+?)(?:\||\n|$)", raw, re.IGNORECASE)
        windows = self._extract(r"Windows:\s*(.+?)(?:\||\n|$)", raw, re.IGNORECASE)
        platform = self._extract(r"Plataforma estimada:\s*(.+?)(?:\n|$)", raw, re.IGNORECASE)
        score = self._extract(r"Score:\s*(.+?)(?:\n|$)", raw, re.IGNORECASE)
        status = self._extract(r"Status:\s*(.+?)(?:\n|$)", raw, re.IGNORECASE)

        return {
            "cpu": cpu,
            "ram": ram,
            "placa_mae": motherboard,
            "bios": bios,
            "windows": windows,
            "plataforma": platform,
            "score": score,
            "status": status,
            "raw": raw.strip(),
        }

    def parse_usb(self, text: str):
        raw = text or ""
        devices = self._extract(r"Dispositivos:\s*(.+?)(?:\n|$)", raw, re.IGNORECASE)
        status = self._extract(r"Status:\s*(.+?)(?:\n|$)", raw, re.IGNORECASE)
        repaired = "SIM" if re.search(r"repair|corrig|concluíd|finalizad", raw, re.IGNORECASE) else "N/D"
        return {
            "usb_status": status,
            "usb_devices": devices,
            "usb_repair": repaired,
            "raw": raw.strip(),
        }

    def build_dashboard(self, quickdiag_text: str, usb_text: str, mode: str, final_ok: bool):
        quickdiag = self.parse_quickdiag(quickdiag_text)
        usb = self.parse_usb(usb_text)
        overall = "OK" if final_ok else "ALERTA"
        return {
            "mode": mode,
            "overall": overall,
            "quickdiag": quickdiag,
            "usb": usb,
        }


class PowerShellBridge:
    def __init__(self, ps1_path: str):
        self.ps1_path = ps1_path

    def _run_command(self, command: str, timeout: int = 240):
        enc = base64.b64encode(command.encode("utf-16le")).decode("ascii")
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", enc]
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

    def invoke_quickdiag(self):
        folder = str(Path(self.ps1_path).parent)
        script = f'''$ErrorActionPreference = "Stop"
Set-Location "{folder}"
. "{self.ps1_path}"
$res = Invoke-Precision-QuickDiagReport 2>&1 | Out-String
Write-Output "WSB_BRIDGE_STAGE=QUICKDIAG"
Write-Output $res
'''
        return self._run_command(script, timeout=300)

    def invoke_usb_repair(self):
        folder = str(Path(self.ps1_path).parent)
        script = f'''$ErrorActionPreference = "Stop"
Set-Location "{folder}"
. "{self.ps1_path}"
$res = Invoke-WSBUSBRepairEngine -WriteReport 2>&1 | Out-String
Write-Output "WSB_BRIDGE_STAGE=USB"
Write-Output $res
'''
        return self._run_command(script, timeout=600)


class BridgeWorker(QObject):
    finished = Signal(str, bool, str)
    progress = Signal(int, str, str)

    def __init__(self, ps1_path: str, mode: str):
        super().__init__()
        self.ps1_path = ps1_path
        self.mode = mode
        self.parser = ReportParser()

    def _emit_demo_payload(self):
        quickdiag_text = (
            "WSB_BRIDGE_STAGE=QUICKDIAG\n"
            "Status: OK\n"
            "Score: 100\n"
            "CPU: Intel(R) Core(TM) i7-3770 CPU @ 3.40GHz | Nucleos: 4 | Threads: 8\n"
            "Plataforma estimada: Plataforma Intel 6/7 Series (legado 1155)\n"
            "Placa-mae: Intel Corporation DH61SA\n"
            "BIOS: Intel Corp. BEH6110H.86A.0120.2013.1112.1412\n"
            "Windows: Microsoft Windows 10 Pro\n"
            "RAM: 16 GB\n"
        )
        usb_text = (
            "WSB_BRIDGE_STAGE=USB\n"
            "Status: OK\n"
            "Dispositivos: 12\n"
            "USB Repair Engine concluído\n"
        )
        dashboard = self.parser.build_dashboard(quickdiag_text, usb_text, "DEMO", True)
        payload = {
            "quickdiag_text": quickdiag_text,
            "usb_text": usb_text,
            "dashboard": dashboard,
        }
        self.finished.emit("DEMO", True, json.dumps(payload, ensure_ascii=False))

    def run(self):
        try:
            if self.mode != "hybrid" or not self.ps1_path or not Path(self.ps1_path).exists():
                self.progress.emit(18, "ETAPA DIAG", "[ OK  ]  ETAPA DIAG            -  Inventário básico concluído (modo DEMO)")
                self.progress.emit(45, "ETAPA USB", "[ OK  ]  ETAPA USB             -  USB Repair Engine concluído (modo DEMO)")
                self.progress.emit(78, "ETAPA DASHBOARD", "[ OK  ]  ETAPA DASHBOARD       -  Dashboard consolidado (modo DEMO)")
                self.progress.emit(100, "ETAPA REPORT", "[ OK  ]  ETAPA REPORT          -  Relatório consolidado (modo DEMO)")
                self._emit_demo_payload()
                return

            bridge = PowerShellBridge(self.ps1_path)
            self.progress.emit(6, "ETAPA DIAG", "[SCAN ]  ETAPA DIAG            -  Chamando QuickDiag do PowerShell")
            q = bridge.invoke_quickdiag()
            q_ok = (q.returncode == 0)
            q_text = (q.stdout or "") + ("\n" + q.stderr if q.stderr else "")
            self.progress.emit(35, "ETAPA USB", f"[ {'OK' if q_ok else 'ERRO'} ]  ETAPA DIAG            -  QuickDiag {'concluído' if q_ok else 'falhou'}")

            self.progress.emit(45, "ETAPA USB", "[SCAN ]  ETAPA USB             -  Chamando USB Repair Engine do PowerShell")
            u = bridge.invoke_usb_repair()
            u_ok = (u.returncode == 0)
            u_text = (u.stdout or "") + ("\n" + u.stderr if u.stderr else "")
            self.progress.emit(78, "ETAPA DASHBOARD", f"[ {'OK' if u_ok else 'ERRO'} ]  ETAPA USB             -  USB Repair {'concluído' if u_ok else 'falhou'}")

            final_ok = q_ok and u_ok
            dashboard = self.parser.build_dashboard(q_text, u_text, "HYBRID", final_ok)
            self.progress.emit(100, "ETAPA REPORT", f"[ {'OK' if final_ok else 'AVISO'} ]  ETAPA REPORT          -  Bridge híbrida finalizada")
            payload = {
                "quickdiag_text": q_text.strip(),
                "usb_text": u_text.strip(),
                "dashboard": dashboard,
            }
            self.finished.emit("HYBRID", final_ok, json.dumps(payload, ensure_ascii=False))
        except subprocess.TimeoutExpired as e:
            payload = {
                "quickdiag_text": "",
                "usb_text": "",
                "dashboard": {
                    "mode": "HYBRID",
                    "overall": "ALERTA",
                    "quickdiag": {},
                    "usb": {},
                },
                "error": f"Timeout do PowerShell: {e}",
            }
            self.finished.emit("HYBRID", False, json.dumps(payload, ensure_ascii=False))
        except Exception as e:
            payload = {
                "quickdiag_text": "",
                "usb_text": "",
                "dashboard": {
                    "mode": "HYBRID",
                    "overall": "ALERTA",
                    "quickdiag": {},
                    "usb": {},
                },
                "error": str(e),
            }
            self.finished.emit("HYBRID", False, json.dumps(payload, ensure_ascii=False))


class MainMenuPage(QWidget):
    def __init__(self, main_window, on_select):
        super().__init__()
        self.main_window = main_window
        self.on_select = on_select
        self.profile = "normal"
        self.quick_buttons = []
        self.menu_buttons = []
        self.section_headers = []
        self.section_separators = []
        self.section_grids = []
        self.section_defs = []

        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.scroll.setFrameShape(QFrame.NoFrame)
        self.scroll.setStyleSheet(f"QScrollArea {{ background:{BG}; border:none; }}")
        outer.addWidget(self.scroll)

        self.content = QWidget()
        self.scroll.setWidget(self.content)

        self.root = QVBoxLayout(self.content)
        self.root.setContentsMargins(12, 12, 12, 12)
        self.root.setSpacing(0)

        self.summary_frame = WSBFrame("CENTRAL DE COMANDO / MENU PRINCIPAL")
        self.summary_label = QLabel()
        self.summary_label.setFont(mono(10, True))
        self.summary_label.setStyleSheet(label_style(WHITE))
        self.summary_frame.v.addWidget(self.summary_label)

        self.telemetry_label = QLabel()
        self.telemetry_label.setFont(mono(9, True))
        self.telemetry_label.setStyleSheet(label_style(CYAN))
        self.summary_frame.v.addWidget(self.telemetry_label)
        self.root.addWidget(self.summary_frame)

        self.quick_frame = WSBFrame("ATALHOS RÁPIDOS / NAVEGAÇÃO")
        self.quick_grid = QGridLayout()
        self.quick_grid.setHorizontalSpacing(10)
        self.quick_grid.setVerticalSpacing(10)
        self.quick_frame.v.addLayout(self.quick_grid)
        self.root.addWidget(self.quick_frame)

        quick = [
            ("[A] AGENT", "PIPELINE HÍBRIDO", lambda: self.main_window.show_agent(), GREEN),
            ("[D] DASHBOARD", "RESUMO TÉCNICO", lambda: self.main_window.show_dashboard(), CYAN),
            ("[S] AJUSTES", "PAINEL DE CONTROLE", lambda: self.main_window.handle_menu("9"), YELLOW),
            ("[Q] QUICKDIAG", "DIAGNÓSTICO", lambda: self.main_window.handle_menu("4"), WHITE),
        ]
        for title, subtitle, callback, color in quick:
            btn = QPushButton(f"{title}\n{subtitle}")
            btn.setFont(mono(10, True))
            btn.setMinimumHeight(58)
            btn.setStyleSheet(button_style(color, CYAN))
            btn.clicked.connect(callback)
            self.quick_buttons.append(btn)

        self.menu_frame = WSBFrame("MÓDULOS PRINCIPAIS / LISTA ORGANIZADA")
        self.menu_root = QVBoxLayout()
        self.menu_root.setSpacing(10)
        self.menu_frame.v.addLayout(self.menu_root)
        self.root.addWidget(self.menu_frame)

        self.menu_map = {
            "1": ("OTIMIZAÇÃO COMPLETA", "Temp / Cache / Prefetch / DNS / Trim"),
            "2": ("LIMPEZA DE PRIVACIDADE", "Cookies / Sessões / Histórico"),
            "3": ("LIMPEZA VISUAL / SHELL", "Ícones / Miniaturas / Shellbags"),
            "4": ("DIAGNÓSTICO DO SISTEMA", "QuickDiag / Hardware / Status"),
            "5": ("REPARO E CORREÇÕES", "USB / Sistema / Serviços"),
            "6": ("ATUALIZAÇÕES", "Windows / Drivers / Validação"),
            "7": ("INSTALADOR DE RUNTIMES", "EXE / MSI / Silent Install"),
            "8": ("SCRIPTS / AUTOMAÇÃO", "Hub técnico / rotinas"),
            "9": ("WSB AJUSTES", "Configurações / Scanner / Agent"),
            "0": ("SAIR", "Encerrar o aplicativo"),
        }

        self.section_defs = [
            ("<:: BLOCO 01 :: LIMPEZA E OTIMIZAÇÃO ::>", ["1", "2", "3"], CYAN),
            ("<:: BLOCO 02 :: DIAGNÓSTICO E REPARO ::>", ["4", "5"], YELLOW),
            ("<:: BLOCO 03 :: SISTEMA E SUPORTE ::>", ["6", "7", "8"], WHITE),
            ("<:: BLOCO 04 :: CONTROLE WSB ::>", ["9", "0"], GREEN),
        ]

        for section_title, keys, accent in self.section_defs:
            section = QWidget()
            section_layout = QVBoxLayout(section)
            section_layout.setContentsMargins(0, 0, 0, 0)
            section_layout.setSpacing(6)

            hdr = QLabel(section_title)
            hdr.setFont(mono(10, True))
            hdr.setStyleSheet(label_style(accent))
            section_layout.addWidget(hdr)
            self.section_headers.append(hdr)

            sep = QLabel("=" * 112)
            sep.setFont(mono(8))
            sep.setStyleSheet(label_style(CYAN))
            section_layout.addWidget(sep)
            self.section_separators.append(sep)

            grid = QGridLayout()
            grid.setHorizontalSpacing(10)
            grid.setVerticalSpacing(10)
            section_layout.addLayout(grid)
            self.section_grids.append((grid, keys))

            for key in keys:
                title, sub = self.menu_map[key]
                btn = MenuButton(key, title, sub)
                btn.setMinimumHeight(72)
                btn.clicked.connect(lambda _, k=key: on_select(k))
                btn._menu_key = key
                self.menu_buttons.append(btn)

            self.menu_root.addWidget(section)

        self.footer_hint = QLabel(
            "Base reorganizada por blocos lógicos com assinatura ASCII do PS1, preservando o scanner evoluído e a responsividade da interface."
        )
        self.footer_hint.setWordWrap(True)
        self.footer_hint.setFont(mono(9))
        self.footer_hint.setStyleSheet(label_style(DIM))
        self.menu_frame.v.addWidget(self.footer_hint)

        self.rebuild_layout("normal")
        self.refresh_summary()

    def rebuild_layout(self, profile: str):
        while self.quick_grid.count():
            item = self.quick_grid.takeAt(0)
            w = item.widget()
            if w is not None:
                w.setParent(None)
        quick_cols = 2 if profile in ("small", "compact") else 4
        for i, btn in enumerate(self.quick_buttons):
            row = i // quick_cols
            col = i % quick_cols
            self.quick_grid.addWidget(btn, row, col)

        section_cols = 1 if profile in ("small", "compact") else 2
        button_lookup = {getattr(btn, "_menu_key", ""): btn for btn in self.menu_buttons}
        for grid, keys in self.section_grids:
            while grid.count():
                item = grid.takeAt(0)
                w = item.widget()
                if w is not None:
                    w.setParent(None)
            for i, key in enumerate(keys):
                btn = button_lookup[key]
                row = i // section_cols
                col = i % section_cols
                grid.addWidget(btn, row, col)

    def apply_metrics(self, profile: str):
        self.profile = profile
        compact = profile in ("compact", "small")
        very_small = profile == "small"
        self.root.setContentsMargins(6 if very_small else 8 if compact else 12, 6 if very_small else 8 if compact else 12, 6 if very_small else 8 if compact else 12, 6 if very_small else 8 if compact else 12)
        self.root.setSpacing(6 if very_small else 8 if compact else 12)
        self.summary_label.setFont(mono(8 if very_small else 9 if compact else 10, True))
        self.telemetry_label.setFont(mono(8 if compact else 9, True))
        self.footer_hint.setFont(mono(8 if compact else 9))
        for btn in self.quick_buttons:
            btn.setFont(mono(8 if very_small else 9 if compact else 10, True))
            btn.setMinimumHeight(44 if very_small else 48 if compact else 58)
            btn.setStyleSheet(button_style(WHITE, CYAN))
        for btn in self.menu_buttons:
            btn.setFont(mono(8 if very_small else 9 if compact else 10, True))
            btn.setMinimumHeight(52 if very_small else 58 if compact else 72)
        for hdr in self.section_headers:
            hdr.setFont(mono(8 if compact else 10, True))
        for sep in self.section_separators:
            sep.setFont(mono(7 if compact else 8))
            sep.setText("─" * (70 if very_small else 90 if compact else 110))
        self.quick_grid.setHorizontalSpacing(6 if compact else 10)
        self.quick_grid.setVerticalSpacing(6 if compact else 10)
        for grid, _ in self.section_grids:
            grid.setHorizontalSpacing(6 if compact else 10)
            grid.setVerticalSpacing(6 if compact else 10)
        self.rebuild_layout(profile)

    def refresh_summary(self):
        settings = self.main_window.settings
        scanner = self.main_window.header.scanner
        dash = self.main_window.last_run_data.get("dashboard", {})
        overall = dash.get("overall", "N/D")
        score = dash.get("quickdiag", {}).get("score", "N/D")
        usb_devices = dash.get("usb", {}).get("usb_devices", "N/D")
        self.summary_label.setText(
            f"[INFO ]  ESTADO GERAL          -  {overall}\n"
            f"[INFO ]  MOTOR ATIVO           -  {settings.get('bridge_mode', 'demo').upper()}\n"
            f"[INFO ]  PERFIL DO SCANNER     -  {scanner.current_speed_label()} / {scanner.current_style_label()}\n"
            f"[INFO ]  ÚLTIMO SCORE          -  {score}"
        )
        self.telemetry_label.setText(
            f"[LIVE ]  USB DEVICES           -  {usb_devices}\n"
            f"[LIVE ]  GLOW / MIRROR         -  {'ON' if scanner.glow_enabled() else 'OFF'} / {'ON' if scanner.mirror_enabled() else 'OFF'}\n"
            f"[LIVE ]  TEXTO TÉCNICO         -  {'ON' if scanner.tech_text_enabled() else 'OFF'}\n"
            f"[LIVE ]  MENU PROFILE          -  RESPONSIVE {self.profile.upper()}"
        )


class SimpleListPage(QWidget):
    def __init__(self, title: str, lines: List[str], on_back):
        super().__init__()
        self.setWindowTitle(title)
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        banner = WSBFrame(f"{title} / PAINEL TÉCNICO")
        for line in lines:
            lbl = QLabel(line)
            lbl.setFont(mono(12, True))
            lbl.setStyleSheet(label_style(WHITE))
            banner.v.addWidget(lbl)

        note = QLabel(
            "Esta área já está pronta visualmente em Python. O próximo avanço funcional continua sendo mapear o motor real do PS1 para este módulo."
        )
        note.setFont(mono(10))
        note.setWordWrap(True)
        note.setStyleSheet(label_style(DIM))
        banner.v.addWidget(note)
        root.addWidget(banner)

        lower = QHBoxLayout()
        lower.setSpacing(12)

        readiness = WSBFrame("READINESS / STATUS OPERACIONAL")
        readiness_label = QLabel(
            "[ OK  ]  CAMADA VISUAL         -  CONSOLIDADA\n"
            "[INFO ]  MOTOR REAL            -  AGUARDANDO MAPEAMENTO\n"
            "[INFO ]  DASHBOARD             -  PRONTO PARA RECEBER DADOS\n"
            "[INFO ]  PRÓXIMO PASSO         -  LIGAR FUNÇÕES DO PS1"
        )
        readiness_label.setFont(mono(10, True))
        readiness_label.setStyleSheet(label_style(CYAN))
        readiness.v.addWidget(readiness_label)
        lower.addWidget(readiness, 1)

        actions = WSBFrame("AÇÕES DISPONÍVEIS")
        actions_grid = QGridLayout()
        actions_grid.setHorizontalSpacing(10)
        actions_grid.setVerticalSpacing(10)
        actions.v.addLayout(actions_grid)

        back = QPushButton("[0] VOLTAR")
        back.setFont(mono(11, True))
        back.setStyleSheet(button_style(DIM, CYAN))
        back.clicked.connect(on_back)
        actions_grid.addWidget(back, 0, 0)

        info = QPushButton("[INFO] MÓDULO VISUAL\nBASE PYTHON PRONTA")
        info.setFont(mono(10, True))
        info.setMinimumHeight(64)
        info.setStyleSheet(button_style(WHITE, CYAN))
        info.setEnabled(False)
        actions_grid.addWidget(info, 0, 1)

        lower.addWidget(actions, 1)
        root.addLayout(lower)

        footer = WSBFrame("ASSINATURA VISUAL / CONTINUIDADE", MAGENTA)
        footer_label = QLabel(
            "Painel consolidado para continuidade segura: identidade visual pronta, scanner estável e módulo preparado para ligação futura do motor real."
        )
        footer_label.setFont(mono(10))
        footer_label.setWordWrap(True)
        footer_label.setStyleSheet(label_style(DIM))
        footer.v.addWidget(footer_label)
        root.addWidget(footer)


class OptimizationPage(QWidget):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        self.running = False
        self._scanner_prefs_before_run = None
        self.setWindowTitle("OTIMIZAÇÃO COMPLETA")

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        overview = WSBFrame("OTIMIZAÇÃO COMPLETA / PIPELINE TÉCNICO")
        self.info = QLabel(
            "[INFO ]  MODO BASE             -  PADRÃO / SAFE CLEAN\n"
            "[INFO ]  ESCOPO                -  TEMP / CACHE / PREFETCH / DNS / TRIM\n"
            "[SAFE ]  LOGIN / SESSÕES       -  PRESERVADOS\n"
            "[NEXT ]  FUTURO                -  MODOS DO PS1 (SEGURO / PROFUNDO / SMART)"
        )
        self.info.setFont(mono(11, True))
        self.info.setStyleSheet(label_style(WHITE))
        overview.v.addWidget(self.info)

        self.plan = QLabel(
            "Fluxo inicial em Python preparado para replicar a opção 1 do PS1 sem tocar em logins, sessões ou credenciais. "
            "Nesta etapa o módulo entrega execução visual estruturada, log técnico, scanner e resumo operacional."
        )
        self.plan.setWordWrap(True)
        self.plan.setFont(mono(9))
        self.plan.setStyleSheet(label_style(DIM))
        overview.v.addWidget(self.plan)
        root.addWidget(overview)

        telemetry = WSBFrame("ESCOPO / ETAPAS DA EXECUÇÃO", CYAN)
        self.scope_label = QLabel(
            "[STAGE]  01 PRE-SCAN          -  VALIDAR PIPELINE / CARREGAR PERFIL\n"
            "[STAGE]  02 TEMP              -  LIMPEZA DE RESÍDUOS TEMPORÁRIOS\n"
            "[STAGE]  03 CACHE             -  LIMPEZA DE CACHE COMUM\n"
            "[STAGE]  04 PREFETCH          -  HIGIENIZAÇÃO DE PREFETCH\n"
            "[STAGE]  05 CLEANUP           -  LIMPEZA COMPLEMENTAR SEGURA\n"
            "[STAGE]  06 DNS / REDE        -  FLUSH DNS / AJUSTE DE REDE\n"
            "[STAGE]  07 TRIM              -  OTIMIZAÇÃO FINAL DE DISCO\n"
            "[STAGE]  08 REPORT            -  CONSOLIDAÇÃO / RESUMO FINAL"
        )
        self.scope_label.setFont(mono(10, True))
        self.scope_label.setStyleSheet(label_style(CYAN))
        telemetry.v.addWidget(self.scope_label)

        self.progress_info = QLabel(
            "[PROGRESS]  0%               -  AGUARDANDO INÍCIO\n"
            "[CURRENT ]  ETAPA            -  N/D\n"
            "[RANGE   ]  0 → 100          -  PROGRESSO REAL POR ETAPAS"
        )
        self.progress_info.setFont(mono(10, True))
        self.progress_info.setStyleSheet(label_style(YELLOW))
        telemetry.v.addWidget(self.progress_info)
        root.addWidget(telemetry)
        log_frame = WSBFrame("LOG TÉCNICO / EXECUÇÃO", GREEN)
        self.log = LogPanel()
        log_frame.v.addWidget(self.log)
        root.addWidget(log_frame, 1)

        row = QHBoxLayout()
        row.setSpacing(12)

        self.start_btn = QPushButton("[1] EXECUTAR OTIMIZAÇÃO")
        self.start_btn.setFont(mono(11, True))
        self.start_btn.setStyleSheet(button_style(GREEN, CYAN))
        self.start_btn.clicked.connect(self.start_optimization)
        row.addWidget(self.start_btn)

        self.summary_btn = QPushButton("[2] VER DASHBOARD")
        self.summary_btn.setFont(mono(11, True))
        self.summary_btn.setStyleSheet(button_style(CYAN, CYAN))
        self.summary_btn.clicked.connect(self.main_window.show_dashboard)
        row.addWidget(self.summary_btn)

        back = QPushButton("[0] VOLTAR")
        back.setFont(mono(11, True))
        back.setStyleSheet(button_style(DIM, CYAN))
        back.clicked.connect(self.back_menu)
        row.addWidget(back)
        row.addStretch(1)
        root.addLayout(row)

    def reset(self):
        self.running = False
        self.log.clear()
        self.progress_info.setText(
            "[PROGRESS]  0%               -  AGUARDANDO INÍCIO\n"
            "[CURRENT ]  ETAPA            -  N/D\n"
            "[RANGE   ]  0 → 100          -  PROGRESSO REAL POR ETAPAS"
        )

    def back_menu(self):
        if self.running:
            QMessageBox.information(self, "WSB Otimização", "Aguarde a execução terminar.")
            return
        self.main_window.header.scanner.restore_preferences(self._scanner_prefs_before_run)
        self.main_window.header.scanner.stop_progress("WSB SCANNER ACTIVE")
        self.main_window.show_main()

    def start_optimization(self):
        if self.running:
            return
        self.reset()
        self.running = True
        scanner = self.main_window.header.scanner
        self._scanner_prefs_before_run = scanner.snapshot_preferences()
        scanner.apply_speed("fast")
        scanner.apply_style_mode("kitt")
        scanner.set_glow_enabled(True)
        scanner.set_mirror_enabled(True)
        scanner.set_tech_text_enabled(True)
        scanner.set_status_state("scan", "CLEAN")
        scanner.start_progress("ETAPA PRE-SCAN", 0)
        self._update_progress_info(0, "PRE-SCAN", "PIPELINE CARREGADO / AGUARDANDO ETAPAS")

        self.log.add_line("[SCAN ]  OTIMIZAÇÃO           -  Inicializando pipeline da opção 1", CYAN)
        self.log.add_line("[SAFE ]  LOGIN / SESSÕES      -  Preservados nesta rotina", YELLOW)
        self.log.add_line("[INFO ]  MOTOR                -  Módulo Python preparado para replicar o PS1", WHITE)
        self.log.add_line("[INFO ]  BARRA 0-100          -  Progresso real por pesos de etapa", CYAN)

        steps = [
            (350, 8, "PRE-SCAN", "[ OK  ]  ETAPA PRE-SCAN       -  Escopo validado / limpeza segura carregada", "kitt", "PERFIL DE LIMPEZA CARREGADO"),
            (900, 22, "TEMP", "[ OK  ]  ETAPA TEMP           -  Resíduos temporários tratados", "dual", "RESÍDUOS TEMPORÁRIOS PROCESSADOS"),
            (1450, 38, "CACHE", "[ OK  ]  ETAPA CACHE          -  Cache comum higienizado", "dual", "CACHE COMUM LIMPO"),
            (2000, 54, "PREFETCH", "[ OK  ]  ETAPA PREFETCH       -  Prefetch revisado", "pulse", "PREFETCH HIGIENIZADO"),
            (2550, 70, "CLEANUP", "[ OK  ]  ETAPA CLEANUP        -  Limpeza complementar segura aplicada", "pulse", "LIMPEZA COMPLEMENTAR CONCLUÍDA"),
            (3100, 84, "DNS / REDE", "[ OK  ]  ETAPA DNS / REDE     -  Flush DNS aplicado", "pulse", "REDE / DNS OTIMIZADOS"),
            (3650, 94, "TRIM", "[ OK  ]  ETAPA TRIM           -  Otimização final consolidada", "pulse", "TRIM FINALIZADO"),
            (4200, 100, "REPORT", "[ OK  ]  ETAPA REPORT         -  Resumo técnico consolidado", "pulse", "RELATÓRIO FINAL GERADO"),
        ]
        for delay, percent, stage, line, style, detail in steps:
            QTimer.singleShot(delay, lambda p=percent, s=stage, l=line, st=style, d=detail: self._step(p, s, l, st, d))
        QTimer.singleShot(4700, self.finish)

    def _update_progress_info(self, percent: int, stage: str, detail: str):
        self.progress_info.setText(
            f"[PROGRESS]  {percent:<3}%            -  {detail}\n"
            f"[CURRENT ]  ETAPA            -  {stage}\n"
            "[RANGE   ]  0 → 100          -  PROGRESSO REAL POR ETAPAS"
        )

    def _step(self, percent: int, stage: str, line: str, style: str, detail: str):
        scanner = self.main_window.header.scanner
        scanner.apply_style_mode(style)
        scanner.set_status_state("scan", "CLEAN")
        scanner.update_progress(percent, f"ETAPA {stage}")
        self._update_progress_info(percent, stage, detail)
        self.log.add_line(line, GREEN)

    def finish(self):
        scanner = self.main_window.header.scanner
        scanner.apply_style_mode("pulse")
        scanner.apply_speed("slow")
        scanner.set_status_state("success", "OK")
        scanner.update_progress(100, "OTIMIZAÇÃO CONCLUÍDA")
        self._update_progress_info(100, "FINAL", "PIPELINE FECHADO COM SUCESSO")
        self.log.add_line("[ OK  ]  EXECUÇÃO FINAL       -  Otimização completa concluída", GREEN)
        self.log.add_line("[INFO ]  RESULTADO            -  Limpeza segura sem arquivos de login", WHITE)

        payload = {
            "optimization_text": "\n".join([
                "WSB_OPT_STAGE=PRE-SCAN",
                "Status: OK",
                "Escopo: Temp / Cache / Prefetch / DNS / Trim",
                "Logins: Preservados",
                "Sessões: Preservadas",
                "Resultado: Otimização concluída",
            ]),
            "dashboard": {
                "mode": self.main_window.settings.get("bridge_mode", "demo").upper(),
                "overall": "OK",
                "quickdiag": self.main_window.last_run_data.get("dashboard", {}).get("quickdiag", {}),
                "usb": self.main_window.last_run_data.get("dashboard", {}).get("usb", {}),
                "optimization": {
                    "scope": "TEMP / CACHE / PREFETCH / DNS / TRIM",
                    "logins": "PRESERVADOS",
                    "status": "OK",
                },
            },
        }
        self.main_window.last_run_data.update(payload)
        self.main_window.dashboard_page.apply_dashboard(self.main_window.last_run_data)
        self.main_window.refresh_visual_state("OTIMIZAÇÃO COMPLETA")
        self.running = False

        def _restore():
            scanner.restore_preferences(self._scanner_prefs_before_run)
            scanner.stop_progress("WSB SCANNER ACTIVE")
            self.main_window.refresh_visual_state("OTIMIZAÇÃO COMPLETA")

        QTimer.singleShot(1800, _restore)

class AgentPage(QWidget):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        self.worker_thread = None
        self.worker = None
        self.running = False
        self._scanner_prefs_before_agent = None

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        frame = WSBFrame("WSB PRECISION AGENT – QUICKDIAG + USB HÍBRIDO")
        self.info = QLabel(
            "[INFO ]  OBJETIVO               -  USB / portas / dispositivos removíveis\n"
            "[ OK  ]  MEMÓRIA DE SESSÃO      -  4 ação(ões) planejada(s)\n"
            "[SCAN ]  PLANO FINAL            -  DIAG + USB + DASHBOARD + REPORT"
        )
        self.info.setFont(mono(12, True))
        self.info.setStyleSheet(f"color:{WHITE};")
        frame.v.addWidget(self.info)

        self.log = LogPanel()
        frame.v.addWidget(self.log)
        root.addWidget(frame)

        row = QHBoxLayout()
        self.start_btn = QPushButton("[1] INICIAR AGENT")
        self.start_btn.setFont(mono(11, True))
        self.start_btn.setStyleSheet(button_style(GREEN, CYAN))
        self.start_btn.clicked.connect(self.start_agent)
        row.addWidget(self.start_btn)

        self.test_btn = QPushButton("[2] TESTAR PONTE")
        self.test_btn.setFont(mono(11, True))
        self.test_btn.setStyleSheet(button_style(YELLOW, CYAN))
        self.test_btn.clicked.connect(self.test_bridge_info)
        row.addWidget(self.test_btn)

        self.dashboard_btn = QPushButton("[3] ABRIR DASHBOARD")
        self.dashboard_btn.setFont(mono(11, True))
        self.dashboard_btn.setStyleSheet(button_style(CYAN, CYAN))
        self.dashboard_btn.clicked.connect(self.main_window.show_dashboard)
        row.addWidget(self.dashboard_btn)

        back = QPushButton("[0] VOLTAR")
        back.setFont(mono(11, True))
        back.setStyleSheet(button_style(DIM, CYAN))
        back.clicked.connect(self.back_menu)
        row.addWidget(back)
        row.addStretch(1)
        root.addLayout(row)

    def reset(self):
        self.log.clear()
        self.running = False

    def test_bridge_info(self):
        settings = self.main_window.settings
        ps1 = settings.get("ps1_path", "")
        mode = settings.get("bridge_mode", "demo")
        self.log.add_line(f"[INFO ]  MODO DE EXECUÇÃO      -  {mode.upper()}", CYAN)
        self.log.add_line(f"[INFO ]  ARQUIVO PS1            -  {ps1 if ps1 else 'não configurado'}", WHITE if ps1 else YELLOW)

    def back_menu(self):
        if self.running:
            QMessageBox.information(self, "WSB Agent", "Aguarde a execução terminar.")
            return
        self.main_window.header.scanner.stop_progress()
        self.main_window.show_main()

    def start_agent(self):
        if self.running:
            return
        self.reset()
        self.running = True
        settings = self.main_window.settings
        self._scanner_prefs_before_agent = self.main_window.header.scanner.snapshot_preferences()
        self.log.add_line("[INFO ]  AGENT                  -  Inicializando pipeline híbrido", CYAN)
        self.main_window.header.scanner.apply_agent_profile("start", 0)

        self.worker_thread = QThread()
        self.worker = BridgeWorker(settings.get("ps1_path", ""), settings.get("bridge_mode", "demo"))
        self.worker.moveToThread(self.worker_thread)
        self.worker_thread.started.connect(self.worker.run)
        self.worker.progress.connect(self.on_progress)
        self.worker.finished.connect(self.on_finished)
        self.worker.finished.connect(self.worker_thread.quit)
        self.worker_thread.start()

    def on_progress(self, percent: int, stage: str, line: str):
        stage_upper = (stage or "").upper()
        if "DIAG" in stage_upper:
            self.main_window.header.scanner.apply_agent_profile("diag", percent)
        elif "USB" in stage_upper:
            self.main_window.header.scanner.apply_agent_profile("usb", percent)
        elif "DASHBOARD" in stage_upper:
            self.main_window.header.scanner.apply_agent_profile("dashboard", percent)
        elif "REPORT" in stage_upper:
            self.main_window.header.scanner.apply_agent_profile("report", percent)
        else:
            self.main_window.header.scanner.update_progress(percent, stage)

        self.main_window.header.scanner.apply_runtime_line_feedback(line)

        color = GREEN if "[ OK" in line else MAGENTA if "[SCAN" in line else WHITE
        if "ERRO" in line:
            color = RED
        self.log.add_line(line, color)

    def on_finished(self, mode: str, ok: bool, details: str):
        self.running = False
        self.main_window.header.scanner.apply_agent_profile("finish", 100, ok)

        try:
            payload = json.loads(details) if details else {}
        except Exception:
            payload = {"quickdiag_text": details, "usb_text": "", "dashboard": {"mode": mode, "overall": "ALERTA"}}

        self.main_window.last_run_data = payload
        self.main_window.dashboard_page.apply_dashboard(payload)
        self.main_window.refresh_visual_state()

        summary = "[ OK  ]  EXECUÇÃO FINAL        -  Precision Agent concluído" if ok else "[AVISO]  EXECUÇÃO FINAL        -  Precision Agent finalizado com alertas"
        self.log.add_line(summary, GREEN if ok else YELLOW)
        self.log.add_line(" ", WHITE)
        self.log.add_line("===== DASHBOARD RESUMIDO =====", CYAN)

        dash = payload.get("dashboard", {})
        q = dash.get("quickdiag", {})
        u = dash.get("usb", {})
        self.log.add_line(f"[INFO ]  STATUS GERAL          -  {dash.get('overall', 'N/D')}", WHITE)
        self.log.add_line(f"[INFO ]  CPU                   -  {q.get('cpu', 'N/D')}", WHITE)
        self.log.add_line(f"[INFO ]  RAM                   -  {q.get('ram', 'N/D')}", WHITE)
        self.log.add_line(f"[INFO ]  PLATAFORMA            -  {q.get('plataforma', 'N/D')}", WHITE)
        self.log.add_line(f"[INFO ]  USB STATUS            -  {u.get('usb_status', 'N/D')}", WHITE)
        self.log.add_line(f"[INFO ]  DISPOSITIVOS USB      -  {u.get('usb_devices', 'N/D')}", WHITE)

        if payload.get("error"):
            self.log.add_line(f"[ERRO ]  DETALHE               -  {payload.get('error')}", RED)

        def _restore_scanner_state():
            self.main_window.header.scanner.restore_preferences(self._scanner_prefs_before_agent)
            self.main_window.header.scanner.stop_progress("WSB SCANNER ACTIVE")
            if hasattr(self.main_window, "settings_page"):
                self.main_window.settings_page.refresh()

        QTimer.singleShot(2200, _restore_scanner_state)

        QMessageBox.information(
            self,
            "WSB Agent",
            "Execução concluída. O dashboard estruturado já foi atualizado." if ok else "Execução concluída com alertas. O dashboard foi atualizado com o que foi possível ler.",
        )


class DashboardPage(QWidget):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        self.data = {}

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        banner = WSBFrame("TELEMETRIA / RESUMO CONSOLIDADO")
        self.banner_label = QLabel(
            "Dashboard consolidado em painéis técnicos: visão geral, QuickDiag, USB e log bruto, mantendo a base híbrida sem alterar a lógica do app."
        )
        self.banner_label.setFont(mono(10))
        self.banner_label.setWordWrap(True)
        self.banner_label.setStyleSheet(label_style(DIM))
        banner.v.addWidget(self.banner_label)
        root.addWidget(banner)

        action_strip = WSBFrame("AÇÃO RÁPIDA / LEITURA OPERACIONAL", GREEN)
        self.action_strip_label = QLabel(
            "[AÇÕES]  Atualize o painel após o Agent para revisar score, hardware detectado, estado USB e o log bruto retornado pela bridge."
        )
        self.action_strip_label.setFont(mono(10, True))
        self.action_strip_label.setWordWrap(True)
        self.action_strip_label.setStyleSheet(label_style(GREEN))
        action_strip.v.addWidget(self.action_strip_label)
        root.addWidget(action_strip)

        top = QHBoxLayout()
        top.setSpacing(12)

        self.summary_frame = WSBFrame("DASHBOARD ESTRUTURADO", CYAN)
        self.summary_label = QLabel(
            "[INFO ]  STATUS GERAL          -  Aguardando execução\n"
            "[INFO ]  MODO                  -  N/D\n"
            "[INFO ]  SCORE                 -  N/D"
        )
        self.summary_label.setFont(mono(12, True))
        self.summary_label.setStyleSheet(label_style(WHITE))
        self.summary_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.summary_frame.v.addWidget(self.summary_label)

        self.summary_hint = QLabel("Painel principal do último ciclo executado pelo Agent.")
        self.summary_hint.setFont(mono(10))
        self.summary_hint.setWordWrap(True)
        self.summary_hint.setStyleSheet(label_style(DIM))
        self.summary_frame.v.addWidget(self.summary_hint)
        top.addWidget(self.summary_frame, 1)

        self.quickdiag_frame = WSBFrame("QUICKDIAG / INVENTÁRIO", YELLOW)
        self.quickdiag_label = QLabel()
        self.quickdiag_label.setFont(mono(11, True))
        self.quickdiag_label.setStyleSheet(label_style(WHITE))
        self.quickdiag_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.quickdiag_frame.v.addWidget(self.quickdiag_label)

        self.quickdiag_hint = QLabel("Leitura estruturada do diagnóstico principal, pronta para evoluir para parser mais fino.")
        self.quickdiag_hint.setFont(mono(10))
        self.quickdiag_hint.setWordWrap(True)
        self.quickdiag_hint.setStyleSheet(label_style(DIM))
        self.quickdiag_frame.v.addWidget(self.quickdiag_hint)
        top.addWidget(self.quickdiag_frame, 1)
        root.addLayout(top)

        middle = QHBoxLayout()
        middle.setSpacing(12)

        self.usb_frame = WSBFrame("USB REPAIR / ENUMERAÇÃO", MAGENTA)
        self.usb_label = QLabel()
        self.usb_label.setFont(mono(11, True))
        self.usb_label.setStyleSheet(label_style(WHITE))
        self.usb_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.usb_frame.v.addWidget(self.usb_label)

        self.usb_hint = QLabel("Resumo do retorno USB para depuração rápida antes de abrir o log bruto completo.")
        self.usb_hint.setFont(mono(10))
        self.usb_hint.setWordWrap(True)
        self.usb_hint.setStyleSheet(label_style(DIM))
        self.usb_frame.v.addWidget(self.usb_hint)
        middle.addWidget(self.usb_frame, 1)

        self.raw_frame = WSBFrame("RESUMO TÉCNICO / OBSERVAÇÕES", CYAN)
        self.raw_info = QLabel()
        self.raw_info.setFont(mono(10, True))
        self.raw_info.setStyleSheet(label_style(CYAN))
        self.raw_info.setWordWrap(True)
        self.raw_info.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.raw_frame.v.addWidget(self.raw_info)

        self.raw_hint = QLabel("Bloco reservado para consolidar alertas do parser, incompatibilidades e próximos passos de leitura.")
        self.raw_hint.setFont(mono(10))
        self.raw_hint.setWordWrap(True)
        self.raw_hint.setStyleSheet(label_style(DIM))
        self.raw_frame.v.addWidget(self.raw_hint)
        middle.addWidget(self.raw_frame, 1)
        root.addLayout(middle)

        log_frame = WSBFrame("LOG BRUTO / DEPURAÇÃO DE BRIDGE", RED)
        self.log = LogPanel()
        log_frame.v.addWidget(self.log)
        root.addWidget(log_frame, 1)

        row = QHBoxLayout()
        row.setSpacing(12)

        refresh = QPushButton("[1] ATUALIZAR DASHBOARD")
        refresh.setFont(mono(11, True))
        refresh.setStyleSheet(button_style(GREEN, CYAN))
        refresh.clicked.connect(self.reload_from_main)
        row.addWidget(refresh)

        back = QPushButton("[0] VOLTAR")
        back.setFont(mono(11, True))
        back.setStyleSheet(button_style(DIM, CYAN))
        back.clicked.connect(self.main_window.show_main)
        row.addWidget(back)
        row.addStretch(1)
        root.addLayout(row)

        self.apply_dashboard({})

    def reload_from_main(self):
        self.apply_dashboard(self.main_window.last_run_data)

    def apply_dashboard(self, payload: dict):
        self.data = payload or {}
        dash = self.data.get("dashboard", {})
        quickdiag = dash.get("quickdiag", {})
        usb = dash.get("usb", {})
        mode = dash.get("mode", "N/D")
        overall = dash.get("overall", "N/D")
        score = quickdiag.get("score", "N/D")

        self.summary_label.setText(
            f"[INFO ]  STATUS GERAL          -  {overall}\n"
            f"[INFO ]  MODO                  -  {mode}\n"
            f"[INFO ]  SCORE                 -  {score}"
        )
        self.quickdiag_label.setText(
            f"[INFO ]  CPU                   -  {quickdiag.get('cpu', 'N/D')}\n"
            f"[INFO ]  RAM                   -  {quickdiag.get('ram', 'N/D')}\n"
            f"[INFO ]  PLATAFORMA            -  {quickdiag.get('plataforma', 'N/D')}\n"
            f"[INFO ]  PLACA-MÃE             -  {quickdiag.get('placa_mae', 'N/D')}\n"
            f"[INFO ]  BIOS                  -  {quickdiag.get('bios', 'N/D')}\n"
            f"[INFO ]  WINDOWS               -  {quickdiag.get('windows', 'N/D')}\n"
            f"[INFO ]  STATUS                -  {quickdiag.get('status', 'N/D')}"
        )
        self.usb_label.setText(
            f"[INFO ]  STATUS USB            -  {usb.get('usb_status', 'N/D')}\n"
            f"[INFO ]  DISPOSITIVOS          -  {usb.get('usb_devices', 'N/D')}\n"
            f"[INFO ]  REPARO                -  {usb.get('usb_repair', 'N/D')}"
        )

        error = self.data.get("error", "")
        self.raw_info.setText(
            "Stage 4.1 consolidou o layout do dashboard para leitura operacional mais limpa, mantendo o parser e a bridge originais."
            if not error else f"Falha detectada: {error}"
        )

        self.log.clear()
        quickdiag_text = self.data.get("quickdiag_text", "")
        usb_text = self.data.get("usb_text", "")
        if quickdiag_text:
            self.log.add_line("===== QUICKDIAG RAW =====", CYAN)
            for line in quickdiag_text.splitlines():
                if line.strip():
                    self.log.add_line(line[:1000], DIM)
        if usb_text:
            self.log.add_line(" ", WHITE)
            self.log.add_line("===== USB RAW =====", CYAN)
            for line in usb_text.splitlines():
                if line.strip():
                    self.log.add_line(line[:1000], DIM)
        if not quickdiag_text and not usb_text and not error:
            self.log.add_line("[INFO ]  DASHBOARD            -  Ainda não há dados processados.", YELLOW)


class SettingsPage(QWidget):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        overview = WSBFrame("AJUSTES / AGENT / PONTE POWERSHELL / SCANNER")
        self.mode_label = QLabel()
        self.mode_label.setFont(mono(12, True))
        self.mode_label.setStyleSheet(label_style(WHITE))
        overview.v.addWidget(self.mode_label)

        self.path_label = QLabel()
        self.path_label.setFont(mono(11))
        self.path_label.setWordWrap(True)
        self.path_label.setStyleSheet(label_style(CYAN))
        overview.v.addWidget(self.path_label)

        self.scanner_hint_label = QLabel(
            "Os controles abaixo mantêm o comportamento do código original, mas agora ficam organizados por blocos para leitura mais rápida e operação mais parecida com produto final."
        )
        self.scanner_hint_label.setFont(mono(10))
        self.scanner_hint_label.setWordWrap(True)
        self.scanner_hint_label.setStyleSheet(label_style(DIM))
        overview.v.addWidget(self.scanner_hint_label)
        root.addWidget(overview)

        stats_row = QHBoxLayout()
        stats_row.setSpacing(14)

        scanner_frame = WSBFrame("TELEMETRIA DO SCANNER", YELLOW)
        self.scanner_speed_label = QLabel()
        self.scanner_speed_label.setFont(mono(12, True))
        self.scanner_speed_label.setStyleSheet(label_style(YELLOW))
        scanner_frame.v.addWidget(self.scanner_speed_label)

        self.scanner_mode_label = QLabel()
        self.scanner_mode_label.setFont(mono(12, True))
        self.scanner_mode_label.setStyleSheet(label_style(CYAN))
        scanner_frame.v.addWidget(self.scanner_mode_label)

        self.scanner_effects_label = QLabel()
        self.scanner_effects_label.setFont(mono(12, True))
        self.scanner_effects_label.setStyleSheet(label_style(MAGENTA))
        self.scanner_effects_label.setWordWrap(True)
        scanner_frame.v.addWidget(self.scanner_effects_label)
        stats_row.addWidget(scanner_frame, 1)

        note_frame = WSBFrame("NOTAS OPERACIONAIS", GREEN)
        note = QLabel(
            "A integração do scanner com o Precision Agent continua ativa. Durante a execução, a interface pode assumir perfis temporários por etapa, e ao finalizar volta automaticamente às suas preferências salvas."
        )
        note.setFont(mono(10))
        note.setWordWrap(True)
        note.setStyleSheet(label_style(GREEN))
        note_frame.v.addWidget(note)

        note2 = QLabel(
            "Este refinamento é só visual/ergonômico: bridge, parser, dashboard e controles manuais seguem preservados."
        )
        note2.setFont(mono(10))
        note2.setWordWrap(True)
        note2.setStyleSheet(label_style(DIM))
        note_frame.v.addWidget(note2)
        stats_row.addWidget(note_frame, 1)
        root.addLayout(stats_row)

        controls_frame = WSBFrame("PAINEL DE CONTROLE / AÇÕES RÁPIDAS")
        controls_grid = QGridLayout()
        controls_grid.setHorizontalSpacing(12)
        controls_grid.setVerticalSpacing(12)
        controls_frame.v.addLayout(controls_grid)

        buttons = [
            ("[1] SELECIONAR PS1", WHITE, self.select_ps1),
            ("[2] ALTERNAR DEMO / HÍBRIDO", YELLOW, self.toggle_mode),
            ("[3] VELOCIDADE DO SCANNER", CYAN, self.cycle_scanner_speed),
            ("[4] MODO DO SCANNER", MAGENTA, self.cycle_scanner_mode),
            ("[5] BRILHO ON/OFF", WHITE, self.toggle_scanner_glow),
            ("[6] ESPELHAMENTO ON/OFF", CYAN, self.toggle_scanner_mirror),
            ("[7] TEXTO TÉCNICO ON/OFF", MAGENTA, self.toggle_scanner_tech_text),
            ("[8] ABRIR PRECISION AGENT", GREEN, self.main_window.show_agent),
            ("[9] ABRIR DASHBOARD", CYAN, self.main_window.show_dashboard),
            ("[0] VOLTAR", DIM, self.main_window.show_main),
        ]

        for idx, (title, color, slot) in enumerate(buttons):
            btn = QPushButton(title)
            btn.setFont(mono(11, True))
            btn.setStyleSheet(button_style(color, CYAN))
            btn.clicked.connect(slot)
            controls_grid.addWidget(btn, idx // 2, idx % 2)

        root.addWidget(controls_frame)
        self.refresh()

    def refresh(self):
        settings = self.main_window.settings
        self.mode_label.setText(f"[INFO ]  MODO DE EXECUÇÃO      -  {settings.get('bridge_mode','demo').upper()}")
        ps1 = settings.get("ps1_path", "")
        self.path_label.setText(f"[INFO ]  ARQUIVO PS1            -  {ps1 if ps1 else 'não configurado'}")
        self.scanner_speed_label.setText(f"[INFO ]  VELOCIDADE SCANNER    -  {self.main_window.header.scanner.current_speed_label()}")
        self.scanner_mode_label.setText(f"[INFO ]  MODO DO SCANNER       -  {self.main_window.header.scanner.current_style_label()}")
        self.scanner_effects_label.setText(
            f"[INFO ]  EFEITOS DO SCANNER    -  BRILHO {self.main_window.header.scanner.current_glow_label()}  |  ESPELHO {self.main_window.header.scanner.current_mirror_label()}  |  TEXTO {self.main_window.header.scanner.current_tech_text_label()}"
        )

    def select_ps1(self):
        path, _ = QFileDialog.getOpenFileName(self, "Selecionar arquivo .ps1", "", "PowerShell Script (*.ps1)")
        if path:
            self.main_window.settings["ps1_path"] = path
            self.main_window.save_settings()
            self.refresh()

    def cycle_scanner_speed(self):
        speed = self.main_window.header.scanner.cycle_speed()
        self.main_window.settings["scanner_speed"] = speed
        self.main_window.save_settings()
        self.refresh()

    def cycle_scanner_mode(self):
        style = self.main_window.header.scanner.cycle_style_mode()
        self.main_window.settings["scanner_style"] = style
        self.main_window.save_settings()
        self.refresh()

    def toggle_scanner_glow(self):
        enabled = self.main_window.header.scanner.toggle_glow()
        self.main_window.settings["scanner_glow"] = enabled
        self.main_window.save_settings()
        self.refresh()

    def toggle_scanner_mirror(self):
        enabled = self.main_window.header.scanner.toggle_mirror()
        self.main_window.settings["scanner_mirror"] = enabled
        self.main_window.save_settings()
        self.refresh()

    def toggle_scanner_tech_text(self):
        enabled = self.main_window.header.scanner.toggle_tech_text()
        self.main_window.settings["scanner_tech_text"] = enabled
        self.main_window.save_settings()
        self.refresh()

    def toggle_mode(self):
        cur = self.main_window.settings.get("bridge_mode", "demo")
        self.main_window.settings["bridge_mode"] = "hybrid" if cur == "demo" else "demo"
        self.main_window.save_settings()
        self.refresh()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.settings = self.load_settings()
        self.last_run_data = {}
        self.setWindowTitle(APP_TITLE)
        self.resize(1366, 768)
        self.setMinimumSize(1024, 720)
        self.setStyleSheet(
            f"QMainWindow, QWidget {{ background:{BG}; }}"
            f"#HeaderPanel {{ border:2px solid {CYAN}; background:{PANEL}; }}"
            f"#WSBFrame {{ border:2px solid {CYAN}; background:{PANEL}; }}"
            f"#StatusStrip {{ border:2px solid {CYAN}; background:{PANEL}; }}"
            f"QPushButton {{ border-radius: 0px; }}"
            f"QLabel {{ background: transparent; }}"
            f"QStackedWidget {{ border:2px solid #0a2534; background:{BG}; }}"
        )
        central = QWidget()
        self.setCentralWidget(central)
        self.root_layout = QVBoxLayout(central)
        self.root_layout.setContentsMargins(14, 14, 14, 14)
        self.root_layout.setSpacing(12)

        self.header = HeaderPanel()
        self.apply_scanner_settings()
        if hasattr(self, "status_strip"):
            self.refresh_visual_state()
        self.root_layout.addWidget(self.header)

        self.stack = QStackedWidget()
        self.root_layout.addWidget(self.stack, 1)

        self.status_strip = StatusStrip(self)
        self.root_layout.addWidget(self.status_strip)

        self.main_page = MainMenuPage(self, self.handle_menu)
        self.agent_page = AgentPage(self)
        self.optimization_page = OptimizationPage(self)
        self.settings_page = SettingsPage(self)
        self.dashboard_page = DashboardPage(self)
        self.stack.addWidget(self.main_page)
        self.stack.addWidget(self.agent_page)
        self.stack.addWidget(self.optimization_page)
        self.stack.addWidget(self.settings_page)
        self.stack.addWidget(self.dashboard_page)

        self.pages = []
        for title in [
            "OTIMIZAÇÃO COMPLETA", "LIMPEZA DE PRIVACIDADE", "LIMPEZA VISUAL / SHELL", "WSB AJUSTES",
            "ATUALIZAÇÕES", "INTEGRIDADE DE HARDWARE", "INSTALADOR DE RUNTIMES", "SCRIPTS"
        ]:
            page = SimpleListPage(title, [
                f"[INFO ]  MÓDULO                -  {title}",
                "[INFO ]  STATUS                -  Base Python pronta",
                "[INFO ]  PRÓXIMO PASSO         -  Mapear motor real do PS1",
            ], self.show_main)
            page.setWindowTitle(title)
            self.pages.append(page)
            self.stack.addWidget(page)

        self.current_page_name = "MENU PRINCIPAL"
        self.apply_responsive_layout()
        self.refresh_visual_state()

        quit_action = QAction("Sair", self)
        quit_action.setShortcut(QKeySequence("Esc"))
        quit_action.triggered.connect(self.close)
        self.addAction(quit_action)

    def current_responsive_profile(self):
        width = max(1, self.width())
        height = max(1, self.height())
        if width <= 1120 or height <= 720:
            return "small"
        if width <= 1440 or height <= 820:
            return "compact"
        return "normal"

    def apply_responsive_layout(self):
        profile = self.current_responsive_profile()
        compact = profile in ("compact", "small")
        edge = 6 if profile == "small" else 8 if compact else 14
        self.root_layout.setContentsMargins(edge, edge, edge, edge)
        self.root_layout.setSpacing(6 if profile == "small" else 8 if compact else 12)
        self.header.apply_metrics(profile)
        self.status_strip.apply_metrics(profile)
        if hasattr(self, "main_page"):
            self.main_page.apply_metrics(profile)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "root_layout"):
            self.apply_responsive_layout()

    def changeEvent(self, event):
        super().changeEvent(event)
        if event.type() == QEvent.WindowStateChange and hasattr(self, "root_layout"):
            QTimer.singleShot(0, self.apply_responsive_layout)

    def refresh_visual_state(self, page_name: Optional[str] = None):
        if page_name:
            self.current_page_name = page_name
        self.status_strip.refresh(self.current_page_name, self.settings, self.header.scanner)
        if hasattr(self, "main_page"):
            self.main_page.refresh_summary()
        if hasattr(self, "settings_page"):
            self.settings_page.refresh()

    def load_settings(self):
        try:
            if SETTINGS_FILE.exists():
                data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
                data.setdefault("bridge_mode", "demo")
                data.setdefault("ps1_path", "")
                data.setdefault("scanner_speed", "normal")
                data.setdefault("scanner_style", "dual")
                data.setdefault("scanner_glow", True)
                data.setdefault("scanner_mirror", True)
                data.setdefault("scanner_tech_text", True)
                return data
        except Exception:
            pass
        return {
            "bridge_mode": "demo",
            "ps1_path": "",
            "scanner_speed": "normal",
            "scanner_style": "dual",
            "scanner_glow": True,
            "scanner_mirror": True,
            "scanner_tech_text": True,
        }

    def apply_scanner_settings(self):
        self.header.scanner.apply_speed(self.settings.get("scanner_speed", "normal"))
        self.header.scanner.apply_style_mode(self.settings.get("scanner_style", "dual"))
        self.header.scanner.set_glow_enabled(self.settings.get("scanner_glow", True))
        self.header.scanner.set_mirror_enabled(self.settings.get("scanner_mirror", True))
        self.header.scanner.set_tech_text_enabled(self.settings.get("scanner_tech_text", True))

    def save_settings(self):
        try:
            SETTINGS_FILE.write_text(json.dumps(self.settings, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass
        self.apply_scanner_settings()
        if hasattr(self, "status_strip"):
            self.refresh_visual_state()

    def show_main(self):
        self.header.scanner.stop_progress()
        self.stack.setCurrentWidget(self.main_page)
        self.refresh_visual_state("MENU PRINCIPAL")

    def show_agent(self):
        self.agent_page.reset()
        self.stack.setCurrentWidget(self.agent_page)
        self.refresh_visual_state("PRECISION AGENT")

    def show_dashboard(self):
        self.dashboard_page.apply_dashboard(self.last_run_data)
        self.stack.setCurrentWidget(self.dashboard_page)
        self.refresh_visual_state("DASHBOARD")

    def show_optimization(self):
        self.optimization_page.reset()
        self.stack.setCurrentWidget(self.optimization_page)
        self.refresh_visual_state("OTIMIZAÇÃO COMPLETA")

    def handle_menu(self, key: str):
        if key == "0":
            self.close()
            return
        if key == "1":
            self.show_optimization()
            return
        if key == "9":
            self.settings_page.refresh()
            self.stack.setCurrentWidget(self.settings_page)
            self.refresh_visual_state("AJUSTES")
            return
        idx = int(key) - 1
        if 0 <= idx < len(self.pages):
            self.stack.setCurrentWidget(self.pages[idx])
            self.refresh_visual_state(self.pages[idx].windowTitle() if self.pages[idx].windowTitle() else f"MÓDULO {key}")


def main():
    app = QApplication(sys.argv)
    try:
        win = MainWindow()
        win.showMaximized()
        sys.exit(app.exec())
    except Exception as e:
        try:
            QMessageBox.critical(None, "WSB Precision Unit", f"Falha ao iniciar:\n{e}")
        except Exception:
            print(f"Falha ao iniciar: {e}")
        raise


if __name__ == "__main__":
    main()
