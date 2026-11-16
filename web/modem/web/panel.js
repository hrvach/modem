// Front-panel driver: maps the board latches the CPU writes (ports 0x10, 0x12,
// 0x14) onto the lamps of courier-front-panel.svg. Bits and polarity follow
// courier-emu/courier_emu/panel.py (FRONT_PANEL_LEDS). Lamps the reference
// model cannot name (HS, RD, SD, TR, RS) are not driven and stay off.
const LATCH_PORTS = [0x10, 0x12, 0x14];

const FRONT_PANEL_LEDS = [
  { name: 'AA',  port: 0x14, mask: 0x10, activeLow: true },
  { name: 'CD',  port: 0x14, mask: 0x01, activeLow: true },
  { name: 'OH',  port: 0x10, mask: 0x01, activeLow: false },
  { name: 'MR',  port: 0x12, mask: 0x02, activeLow: true },
  { name: 'CS',  port: 0x14, mask: 0x02, activeLow: true },
  { name: 'SYN', port: 0x14, mask: 0x80, activeLow: true },
  { name: 'ARQ', port: 0x14, mask: 0x20, activeLow: true },
];

// The SVG's twelve lamps, left to right, by label.
const LAMP_ORDER = ['HS', 'AA', 'CD', 'OH', 'RD', 'SD', 'TR', 'MR', 'RS', 'CS', 'SYN', 'ARQ'];

class PanelDriver {
  constructor(root) {
    this.lamps = [...root.querySelectorAll('rect')]
      .filter((r) => /url\(#ledO(n|ff)\)/.test(r.getAttribute('fill') || ''));
    this.latch = {};          // port -> last value, or -1 if never written
    this.uart = { RD: false, SD: false, TR: false, RS: false };   // UART and control lamps
    this.render();
  }

  // values: [v0x10, v0x12, v0x14], -1 for a port never written.
  setLatches(values) {
    LATCH_PORTS.forEach((port, i) => { this.latch[port] = values[i]; });
    this.render();
  }

  // Lamps with no latch bit follow the UART and control lines: RD (modem to DTE),
  // SD (DTE to modem), TR (DTR asserted) and RS (RTS asserted).
  setUart(name, on) {
    this.uart[name] = on;
    this.render();
  }

  lit(led) {
    const v = this.latch[led.port];
    if (v === undefined || v < 0) return false;          // never written: not lit
    const level = (v & led.mask) !== 0;
    return led.activeLow ? !level : level;
  }

  render() {
    this.lamps.forEach((rect, i) => {
      const label = LAMP_ORDER[i];
      const led = FRONT_PANEL_LEDS.find((l) => l.name === label);
      const on = led ? this.lit(led) : !!this.uart[label];
      rect.setAttribute('fill', on ? 'url(#ledOn)' : 'url(#ledOff)');
      if (on) rect.setAttribute('filter', 'url(#glow)');
      else rect.removeAttribute('filter');
    });
  }
}
