# Appendix A — Pinouts and Signal Descriptions (SPRU056D)

Source: SPRU056D, *TMS320C5x User's Guide*, June 1998, Appendix A, PDF pp.614–637
(printed pp.A-1–A-24). Only authority: `~/workspace/user/files/spru056d.pdf`
(SHA-256 `a31e285f…` — same file as `c5x_users_guide.pdf` in the research notes).
Every factual claim below cites appendix/section + table/figure number + both page
numbers (PDF index page and printed page).

## A.0 Overview

The TMS320C5x DSPs are available in a 100-pin quad flat-pack (QFP), 100-pin thin
quad flat-pack (TQFP), 128-pin TQFP, 132-pin bumpered quad flat-pack (BQFP), and
144-pin TQFP package. All packages conform to JEDEC specifications for
electrical/electronic components. [App A intro, PDF p.614 (printed p.A-1)]

| Section | Package / content | Devices | PDF p. | Printed p. |
|---|---|---|---|---|
| A.1 | 100-pin QFP (Fig. A–1, Table A–1) | ’C52 | 615–616 | A-2–A-3 |
| A.2 | 100-pin TQFP (Fig. A–2, Table A–2) | ’C51, ’C52, ’C53S, ’LC56 | 617–618 | A-4–A-5 |
| A.3 | 128-pin TQFP (Fig. A–3, Table A–3) | ’LC57 | 619–620 | A-6–A-7 |
| A.4 | 132-pin BQFP (Fig. A–4, Table A–4) | ’C50, ’C51, ’C53 | 621–622 | A-8–A-9 |
| A.5 | 144-pin TQFP (Fig. A–5, Table A–5) | ’C57S | 623–624 | A-10–A-11 |
| A.6 | 100-pin TQFP device-specific pins (Table A–6) | ’C51, ’C52, ’C53S, ’LC56 | 625 | A-12 |
| A.7 | Signal descriptions (Tables A–7–A–18) | all | 626–637 | A-13–A-24 |

## How the pin tables below were produced

- Tables A–1–A–5 are transcribed **in full, sorted by pin number** (the manual
  sorts by signal name). Each table was parsed mechanically from the
  `pdftotext -layout` extraction and verified: every pin 1..N appears exactly
  once (100/100/128/132/144 rows, no missing or duplicate pins).
- The pinout **figures** (A–1–A–5) are top-view pin diagrams whose assignments
  match the tables; the figures are NOT separately transcribed — the layout
  extraction scrambles the figure edge labels spatially, so figure-only labels
  are not trusted. Where a figure and its table disagree, the table governs.
  [INFERENCE: figures and tables agree by construction; the one checked case,
  Table A–1 pin 61, was verified against a 200-dpi render of PDF p.616.]
- Signal names are reproduced exactly as printed, including these manual
  quirks: Table A–1 prints pin 61 as `X2/CLKIN1` (Figure A–1 shows `X2/CLKIN`);
  Table A–4/A–5 not-connected pins print as `{` in the extraction and are
  rendered here as `NC†` per the tables' own footnote; Table A–6 pin numbers
  carrying `}` in the extraction are the `‡` footnote marker
  ("No change in function").
- `NC` = not connected (reserved). `*` (Table A–2) = reserved for specific
  devices, see Table A–6.


## A.1 100-pin QFP Pinout (’C52) — Table A–1

Figure A–1 (PJ package, top view) and Table A–1 give the
pin/signal assignments. [App A, §A.1, PDF p.616 (printed p.A-3)]

| Pin | Signal |
|---:|---|
| 1 | D8 |
| 2 | VDDD |
| 3 | VSSD |
| 4 | VSSD |
| 5 | D7 |
| 6 | D6 |
| 7 | D5 |
| 8 | D4 |
| 9 | D3 |
| 10 | D2 |
| 11 | D1 |
| 12 | D0 |
| 13 | TMS |
| 14 | VDDD |
| 15 | VDDD |
| 16 | TCK |
| 17 | VSSD |
| 18 | VSSD |
| 19 | INT1 |
| 20 | INT2 |
| 21 | INT3 |
| 22 | INT4 |
| 23 | NMI |
| 24 | DR |
| 25 | VSSI |
| 26 | FSR |
| 27 | CLKR |
| 28 | VDDA |
| 29 | VSSA |
| 30 | A0 |
| 31 | A1 |
| 32 | A2 |
| 33 | A3 |
| 34 | A4 |
| 35 | A5 |
| 36 | A6 |
| 37 | A7 |
| 38 | A8 |
| 39 | A9 |
| 40 | VDDI |
| 41 | TDI |
| 42 | VSSA |
| 43 | CLKMD1 |
| 44 | A10 |
| 45 | A11 |
| 46 | A12 |
| 47 | A13 |
| 48 | A14 |
| 49 | A15 |
| 50 | VDDA |
| 51 | RD |
| 52 | WE |
| 53 | VSSC |
| 54 | DS |
| 55 | IS |
| 56 | PS |
| 57 | R/W |
| 58 | STRB |
| 59 | BR |
| 60 | CLKIN2 |
| 61 | X2/CLKIN1 |
| 62 | X1 |
| 63 | VDDC |
| 64 | TDO |
| 65 | VSSI |
| 66 | VSSI |
| 67 | CLKMD2 |
| 68 | FSX |
| 69 | VSSI |
| 70 | DX |
| 71 | † (NC) |
| 72 | HOLDA |
| 73 | XF |
| 74 | CLKOUT1 |
| 75 | VDDI |
| 76 | VDDI |
| 77 | VDDC |
| 78 | VDDC |
| 79 | EMU0 |
| 80 | EMU1/OFF |
| 81 | VSSC |
| 82 | TOUT |
| 83 | VSSI |
| 84 | CLKX |
| 85 | VSSI |
| 86 | VSSI |
| 87 | RS |
| 88 | READY |
| 89 | HOLD |
| 90 | BIO |
| 91 | TRST |
| 92 | VSSI |
| 93 | MP/MC |
| 94 | D15 |
| 95 | D14 |
| 96 | D13 |
| 97 | D12 |
| 98 | D11 |
| 99 | D10 |
| 100 | D9 |

† pin 71 is not connected (reserved).


## A.2 100-pin TQFP Pinout (’C51, ’C52, ’C53S, ’LC56) — Table A–2

Figure A–2 (PZ package, top view) and Table A–2 give the
pin/signal assignments. [App A, §A.2, PDF p.618 (printed p.A-5)]

| Pin | Signal |
|---:|---|
| 1 | EMU0 |
| 2 | EMU1/OFF |
| 3 | VSSC |
| 4 | TOUT |
| 5 | * |
| 6 | * |
| 7 | * |
| 8 | * |
| 9 | RS |
| 10 | READY |
| 11 | HOLD |
| 12 | BIO |
| 13 | TRST |
| 14 | VSSI |
| 15 | VSSI |
| 16 | MP/MC |
| 17 | D15 |
| 18 | D14 |
| 19 | D13 |
| 20 | D12 |
| 21 | D11 |
| 22 | D10 |
| 23 | D9 |
| 24 | D8 |
| 25 | VDDD |
| 26 | VSSD |
| 27 | VSSD |
| 28 | D7 |
| 29 | D6 |
| 30 | D5 |
| 31 | D4 |
| 32 | D3 |
| 33 | D2 |
| 34 | D1 |
| 35 | D0 |
| 36 | TMS |
| 37 | VDDD |
| 38 | TCK |
| 39 | VSSD |
| 40 | VSSD |
| 41 | INT1 |
| 42 | INT2 |
| 43 | INT3 |
| 44 | INT4 |
| 45 | NMI |
| 46 | * |
| 47 | * |
| 48 | * |
| 49 | * |
| 50 | VDDA |
| 51 | VSSA |
| 52 | A0 |
| 53 | A1 |
| 54 | A2 |
| 55 | A3 |
| 56 | A4 |
| 57 | A5 |
| 58 | A6 |
| 59 | A7 |
| 60 | A8 |
| 61 | A9 |
| 62 | VDDI |
| 63 | TDI |
| 64 | VSSA |
| 65 | VSSA |
| 66 | CLKMD1 |
| 67 | A10 |
| 68 | A11 |
| 69 | A12 |
| 70 | A13 |
| 71 | A14 |
| 72 | A15 |
| 73 | VDDA |
| 74 | RD |
| 75 | WE |
| 76 | VSSC |
| 77 | DS |
| 78 | IS |
| 79 | PS |
| 80 | R/W |
| 81 | STRB |
| 82 | BR |
| 83 | * |
| 84 | X2/CLKIN |
| 85 | X1 |
| 86 | VDDC |
| 87 | TDO |
| 88 | VSSI |
| 89 | VSSI |
| 90 | CLKMD2 |
| 91 | * |
| 92 | * |
| 93 | * |
| 94 | * |
| 95 | HOLDA |
| 96 | XF |
| 97 | CLKOUT1 |
| 98 | VDDI |
| 99 | VDDI |
| 100 | VDDC |

* pins are reserved for specific devices (see Table A–6).


## A.3 128-pin TQFP Pinout (’LC57) — Table A–3

Figure A–3 (PBK package, top view) and Table A–3 give the
pin/signal assignments. [App A, §A.3, PDF p.620 (printed p.A-7)]

| Pin | Signal |
|---:|---|
| 1 | HINT |
| 2 | EMU0 |
| 3 | EMU1/OFF |
| 4 | VSSC |
| 5 | VSSC |
| 6 | TOUT |
| 7 | BCLKX |
| 8 | CLKX |
| 9 | VDDC |
| 10 | BFSR |
| 11 | BCLKR |
| 12 | RS |
| 13 | READY |
| 14 | HOLD |
| 15 | BIO |
| 16 | VDDC |
| 17 | VDDC |
| 18 | IAQ |
| 19 | TRST |
| 20 | VSSI |
| 21 | VSSI |
| 22 | MP/MC |
| 23 | D15 |
| 24 | D14 |
| 25 | D13 |
| 26 | D12 |
| 27 | D11 |
| 28 | D10 |
| 29 | D9 |
| 30 | D8 |
| 31 | VDDD |
| 32 | VDDD |
| 33 | VSSD |
| 34 | VSSD |
| 35 | D7 |
| 36 | D6 |
| 37 | D5 |
| 38 | D4 |
| 39 | D3 |
| 40 | D2 |
| 41 | D1 |
| 42 | D0 |
| 43 | HCNTL0 |
| 44 | TMS |
| 45 | HCNTL1 |
| 46 | VDDD |
| 47 | VDDD |
| 48 | TCK |
| 49 | VSSD |
| 50 | VSSD |
| 51 | HR/W |
| 52 | INT1 |
| 53 | INT2 |
| 54 | INT3 |
| 55 | INT4 |
| 56 | HBIL |
| 57 | NMI |
| 58 | DR |
| 59 | BDR |
| 60 | FSR |
| 61 | CLKR |
| 62 | VDDA |
| 63 | VDDA |
| 64 | HAS |
| 65 | HCS |
| 66 | VSSA |
| 67 | A0 |
| 68 | A1 |
| 69 | A2 |
| 70 | A3 |
| 71 | A4 |
| 72 | A5 |
| 73 | A6 |
| 74 | A7 |
| 75 | A8 |
| 76 | A9 |
| 77 | VDDI |
| 78 | VDDI |
| 79 | HDS2 |
| 80 | HDS1 |
| 81 | TDI |
| 82 | VSSA |
| 83 | VSSA |
| 84 | CLKMD1 |
| 85 | A10 |
| 86 | A11 |
| 87 | A12 |
| 88 | A13 |
| 89 | A14 |
| 90 | A15 |
| 91 | VDDA |
| 92 | HRDY |
| 93 | HD0 |
| 94 | RD |
| 95 | HD1 |
| 96 | WE |
| 97 | VSSC |
| 98 | VSSC |
| 99 | HD2 |
| 100 | DS |
| 101 | IS |
| 102 | PS |
| 103 | R/W |
| 104 | STRB |
| 105 | HD3 |
| 106 | BR |
| 107 | CLKMD3 |
| 108 | X2/CLKIN |
| 109 | X1 |
| 110 | VDDC |
| 111 | TDO |
| 112 | VSSI |
| 113 | VSSI |
| 114 | HD4 |
| 115 | CLKMD2 |
| 116 | HD5 |
| 117 | FSX |
| 118 | HD6 |
| 119 | BFSX |
| 120 | HD7 |
| 121 | DX |
| 122 | BDX |
| 123 | HOLDA |
| 124 | XF |
| 125 | CLKOUT1 |
| 126 | VDDI |
| 127 | VDDI |
| 128 | VDDC |


## A.4 132-pin BQFP Pinout (’C50, ’C51, ’C53) — Table A–4

Figure A–4 (PQ package, top view) and Table A–4 give the
pin/signal assignments. [App A, §A.4, PDF p.622 (printed p.A-9)]

| Pin | Signal |
|---:|---|
| 1 | IAQ |
| 2 | TRST |
| 3 | VSSI |
| 4 | VSSI |
| 5 | MP/MC |
| 6 | D15 |
| 7 | D14 |
| 8 | D13 |
| 9 | D12 |
| 10 | D11 |
| 11 | D10 |
| 12 | D9 |
| 13 | D8 |
| 14 | VDDD |
| 15 | VDDD |
| 16 | NC† |
| 17 | NC† |
| 18 | NC† |
| 19 | NC† |
| 20 | VSSD |
| 21 | VSSD |
| 22 | NC† |
| 23 | D7 |
| 24 | D6 |
| 25 | D5 |
| 26 | D4 |
| 27 | D3 |
| 28 | D2 |
| 29 | D1 |
| 30 | D0 |
| 31 | TMS |
| 32 | VDDD |
| 33 | VDDD |
| 34 | TCK |
| 35 | VSSD |
| 36 | VSSD |
| 37 | NC† |
| 38 | INT1 |
| 39 | INT2 |
| 40 | INT3 |
| 41 | INT4 |
| 42 | NMI |
| 43 | DR |
| 44 | TDR |
| 45 | FSR |
| 46 | CLKR |
| 47 | VDDA |
| 48 | VDDA |
| 49 | NC† |
| 50 | NC† |
| 51 | NC† |
| 52 | NC† |
| 53 | VSSA |
| 54 | VSSA |
| 55 | A0 |
| 56 | A1 |
| 57 | A2 |
| 58 | A3 |
| 59 | A4 |
| 60 | A5 |
| 61 | A6 |
| 62 | A7 |
| 63 | A8 |
| 64 | A9 |
| 65 | VDDI |
| 66 | VDDI |
| 67 | TDI |
| 68 | VSSA |
| 69 | VSSA |
| 70 | NC† |
| 71 | CLKMD1 |
| 72 | A10 |
| 73 | A11 |
| 74 | A12 |
| 75 | A13 |
| 76 | A14 |
| 77 | A15 |
| 78 | NC† |
| 79 | NC† |
| 80 | VDDA |
| 81 | VDDA |
| 82 | RD |
| 83 | WE |
| 84 | NC† |
| 85 | NC† |
| 86 | VSSC |
| 87 | VSSC |
| 88 | NC† |
| 89 | DS |
| 90 | IS |
| 91 | PS |
| 92 | R/W |
| 93 | STRB |
| 94 | BR |
| 95 | CLKIN2 |
| 96 | X2/CLKIN |
| 97 | X1 |
| 98 | VDDC |
| 99 | VDDC |
| 100 | TDO |
| 101 | VSSI |
| 102 | VSSI |
| 103 | CLKMD2 |
| 104 | FSX |
| 105 | TFSX/TFRM |
| 106 | DX |
| 107 | TDX |
| 108 | HOLDA |
| 109 | XF |
| 110 | CLKOUT1 |
| 111 | NC† |
| 112 | IACK |
| 113 | VDDI |
| 114 | VDDI |
| 115 | NC† |
| 116 | NC† |
| 117 | NC† |
| 118 | EMU0 |
| 119 | EMU1/OFF |
| 120 | VSSC |
| 121 | VSSC |
| 122 | TOUT |
| 123 | TCLKX |
| 124 | CLKX |
| 125 | TFSR/TADD |
| 126 | TCLKR |
| 127 | RS |
| 128 | READY |
| 129 | HOLD |
| 130 | BIO |
| 131 | VDDC |
| 132 | VDDC |

† pins are not connected (reserved). In the extraction these print as “{”.


## A.5 144-pin TQFP Pinout (’C57S) — Table A–5

Figure A–5 (PGE package, top view) and Table A–5 give the
pin/signal assignments. [App A, §A.5, PDF p.624 (printed p.A-11)]

| Pin | Signal |
|---:|---|
| 1 | HINT |
| 2 | EMU0 |
| 3 | NC† |
| 4 | EMU1/OFF |
| 5 | VSSC |
| 6 | VSSC |
| 7 | TOUT |
| 8 | BCLKX |
| 9 | CLKX |
| 10 | VDDC |
| 11 | BFSR |
| 12 | BCLKR |
| 13 | RS |
| 14 | READY |
| 15 | HOLD |
| 16 | NC† |
| 17 | BIO |
| 18 | VDDC |
| 19 | VDDC |
| 20 | IAQ |
| 21 | TRST |
| 22 | VSSI |
| 23 | VSSI |
| 24 | MP/MC |
| 25 | D15 |
| 26 | D14 |
| 27 | D13 |
| 28 | NC† |
| 29 | D12 |
| 30 | D11 |
| 31 | D10 |
| 32 | D9 |
| 33 | NC† |
| 34 | D8 |
| 35 | VDDD |
| 36 | VDDD |
| 37 | VSSD |
| 38 | VSSD |
| 39 | D7 |
| 40 | D6 |
| 41 | NC† |
| 42 | D5 |
| 43 | D4 |
| 44 | D3 |
| 45 | NC† |
| 46 | D2 |
| 47 | D1 |
| 48 | D0 |
| 49 | HCNTL0 |
| 50 | TMS |
| 51 | HCNTL1 |
| 52 | VDDD |
| 53 | VDDD |
| 54 | TCK |
| 55 | VSSD |
| 56 | VSSD |
| 57 | NC† |
| 58 | HR/W |
| 59 | INT1 |
| 60 | INT2 |
| 61 | INT3 |
| 62 | INT4 |
| 63 | HBIL |
| 64 | NMI |
| 65 | DR |
| 66 | BDR |
| 67 | FSR |
| 68 | CLKR |
| 69 | VDDA |
| 70 | VDDA |
| 71 | HAS |
| 72 | NC† |
| 73 | HCS |
| 74 | VSSA |
| 75 | A0 |
| 76 | A1 |
| 77 | A2 |
| 78 | NC† |
| 79 | A3 |
| 80 | A4 |
| 81 | A5 |
| 82 | A6 |
| 83 | NC† |
| 84 | A7 |
| 85 | A8 |
| 86 | A9 |
| 87 | VDDI |
| 88 | VDDI |
| 89 | HDS2 |
| 90 | HDS1 |
| 91 | TDI |
| 92 | VSSA |
| 93 | VSSA |
| 94 | CLKMD1 |
| 95 | A10 |
| 96 | A11 |
| 97 | NC† |
| 98 | A12 |
| 99 | A13 |
| 100 | A14 |
| 101 | NC† |
| 102 | A15 |
| 103 | VDDA |
| 104 | HRDY |
| 105 | HD0 |
| 106 | RD |
| 107 | HD1 |
| 108 | WE |
| 109 | VSSC |
| 110 | VSSC |
| 111 | HD2 |
| 112 | DS |
| 113 | IS |
| 114 | PS |
| 115 | R/W |
| 116 | STRB |
| 117 | NC† |
| 118 | HD3 |
| 119 | BR |
| 120 | NC† |
| 121 | CLKMD3 |
| 122 | X2/CLKIN |
| 123 | X1 |
| 124 | VDDC |
| 125 | NC† |
| 126 | TDO |
| 127 | VSSI |
| 128 | VSSI |
| 129 | HD4 |
| 130 | CLKMD2 |
| 131 | HD5 |
| 132 | FSX |
| 133 | HD6 |
| 134 | BFSX |
| 135 | HD7 |
| 136 | DX |
| 137 | BDX |
| 138 | HOLDA |
| 139 | XF |
| 140 | CLKOUT1 |
| 141 | NC† |
| 142 | VDDI |
| 143 | VDDI |
| 144 | VDDC |

† pins are not connected (reserved). In the extraction these print as “{”.


## A.6 100-Pin TQFP Device-Specific Pinouts — Table A–6

Table A–6 lists device-specific pin/signal assignments for the ’C51, ’C52,
’C53S, and ’LC56 in the 100-pin TQFP package. Common assignments are Figure
A–2 / Table A–2. [App A, §A.6, PDF p.625 (printed p.A-12)]

| Pin | ’C51 | ’C52 | ’C53S | ’LC56† |
|---:|---|---|---|---|
| 5 | TCLKX | VSSI | CLKX2 | BCLKX |
| 6‡ | CLKX | CLKX | CLKX1 | CLKX |
| 7 | TFSR/TADD | VSSI | FSR2 | BFSR |
| 8 | TCLKR | VSSI | CLKR2 | BCLKR |
| 46‡ | DR | DR | DR1 | DR |
| 47 | TDR | VSSI | DR2 | BDR |
| 48‡ | FSR | FSR | FSR1 | FSR |
| 49‡ | CLKR | CLKR | CLKR1 | CLKR |
| 83 | CLKIN2 | CLKIN2 | CLKIN2 | CLKMD3 |
| 91‡ | FSX | FSX | FSX1 | FSX |
| 92 | TFSX/TFRM | VSSI | FSX2 | BFSX |
| 93‡ | DX | DX | DX1 | DX |
| 94 | TDX | NC§ | DX2 | BDX |

† Pin names beginning with B indicate signals on the buffered serial port
(BSP). ‡ No change in function. § NC = these pins are not connected
(reserved). (The `‡` marker prints as `}` in the extraction; pins 6, 46, 48,
49, 91, 93 carry it.)

## A.7 Signal Descriptions — Tables A–7–A–18

Tables A–7–A–18 list each signal, its operating state(s), and its function.
State legend (all tables): I = Input, O = Output, Z = High impedance,
S = Supply. `{` = "The OFF signal, when active (low), puts all ’C5x output
drivers into the high-impedance state." General note on every table: input
pins that are unused may be connected to VDD or to an external pullup
resistor. [App A, §A.7, PDF pp.626–637 (printed pp.A-13–A-24)]

Each row below is a faithful one-line condensation of the manual's
description; wording in quotes is verbatim. Full verbatim descriptions are
in the manual tables cited per row group.

### Table A–7. Address and Data Bus [PDF p.626 (printed p.A-13)]

| Signal | State | Function (one line) |
|---|---|---|
| A15 (MSB)–A0 (LSB) | I/O/Z | Parallel bidirectional 3-state address bus, multiplexed to external data/program memory or I/O; Hi-Z in hold mode or when OFF active (low); inputs for external DMA access of on-chip single-access RAM; inputs while HOLDA is active low if BR is externally driven low. |
| D15 (MSB)–D0 (LSB) | I/O/Z | Parallel bidirectional 3-state data bus between core CPU and external data/program memory or I/O; Hi-Z when not outputting, when RS or HOLD is asserted, or when OFF active (low); also used in external DMA access of on-chip single-access RAM. |

Note on Table A–7: "The BR pin has an internal pullup for performing DMA to the on-chip RAM."

### Table A–8. Memory Control [PDF p.627 (printed p.A-14)]

| Signal | State | Function (one line) |
|---|---|---|
| DS, PS, IS | O/Z | Data, program, and I/O space select signals; always high unless low level is asserted for communicating to a particular external space; Hi-Z in hold mode or when OFF active (low). |
| RD | O/Z | Read select; active on all external program, data, and I/O reads; may connect directly to the output enable (OE) of external devices; Hi-Z in hold mode or when OFF active (low). |
| READY | I | Data ready input; if low (device not ready) the processor waits one cycle and checks READY again; also indicates a bus grant to an external device after a BR (bus request) signal. |
| R/W | I/O/Z | Read/write; normally high (read), low for a write; Hi-Z in hold mode or when OFF active (low); also used in external DMA of on-chip RAM — while HOLDA and IAQ are active (low), indicates DMA data-bus direction (high = read, low = write). |
| STRB | I/O/Z | Strobe; always high unless asserted low to indicate an external bus cycle; Hi-Z in hold mode or when OFF active (low); also used in external DMA of on-chip single-access RAM — while HOLDA and IAQ are active (low), selects the memory access. |
| WE | O/Z | Write enable; falling edge indicates the device is driving the external data bus (D15–D0); data can be latched by an external device on the rising edge; active on all external program, data, and I/O writes; Hi-Z in hold mode or when OFF active (low). |

### Table A–9. Multiprocessing [PDF p.628 (printed p.A-15)]

| Signal | State | Function (one line) |
|---|---|---|
| BIO | I | Branch control input; can control a conditional branch instruction; sampled during the fetch of the conditional branch instruction. |
| BR | I/O/Z | Bus request; asserted during access of external global data memory space; READY is asserted to the device when the global data memory is available; can extend the data memory address space by up to 32K words; Hi-Z when OFF active (low); used in external DMA of on-chip single-access RAM — while HOLDA is active low, BR is externally driven low to request access. |
| HOLD | I | Hold input; asserted to request control of the address, data, and control lines; when HOLDA is acknowledged, these lines go Hi-Z. |
| HOLDA | O/Z | Hold acknowledge; indicates to external circuitry the processor is in a hold state and address/data/memory-control lines are Hi-Z for external access of local memory; Hi-Z when OFF active (low). |
| IACK | O/Z | Interrupt acknowledge; indicates receipt of an interrupt and that the program counter is fetching the interrupt vector location designated by A15–A0; Hi-Z when OFF active (low). |
| IAQ | O/Z | Instruction acquisition; asserted when there is an instruction address on the address bus; Hi-Z when OFF active (low); also used in external DMA of on-chip single-access RAM — while HOLDA is active low, acknowledges the BR request and stops indicating instruction acquisition. |
| XF | O/Z | External flag output (latched software-programmable signal); set high or low by specific instructions or by loading ST1; for signalling other processors in multiprocessor configurations or as a general-purpose output; Hi-Z when OFF active (low); set high at reset. |

### Table A–10. Initialization, Interrupt, and Reset Operations [PDF p.629 (printed p.A-16)]

| Signal | State | Function (one line) |
|---|---|---|
| INT4, INT3, INT2, INT1 | I | External user interrupt inputs; prioritized and maskable by IMR and the INTM bit in ST0; can be polled and reset via IFR. |
| MP/MC | I | Microprocessor/microcomputer mode select pin; if active (low) at reset (microcomputer mode), internal program ROM is mapped into program memory; in microprocessor mode all program memory is external; sampled only during reset; mode can be overridden via the MP/MC bit in PMST. |
| NMI | I | Nonmaskable interrupt; cannot be masked via IMR or the INTM bit in ST0; when activated, the processor traps to the appropriate vector location. |
| RS | I | Reset input; terminates execution and forces the program counter to 0; when RS is brought high, execution begins at location 0h of program memory; RS affects various registers and status bits. |

### Table A–11. Supply [PDF p.629 (printed p.A-16)]

| Signal | State | Function |
|---|---|---|
| VDDA | S | Power supply for address bus. |
| VDDC | S | Power supply for memory control signals. |
| VDDD | S | Power supply for data bus. |
| VDDI | S | Power supply for inputs and internal logic. |
| VSSA | S | Ground for address bus. |
| VSSC | S | Ground for memory control signals. |
| VSSD | S | Ground for data bus. |
| VSSI | S | Ground for inputs and internal logic. |

### Table A–12. Oscillator/Timer [PDF p.630 (printed p.A-17)]

| Signal | State | Function (one line) |
|---|---|---|
| CLKIN2† | I | External clock input; divide-by-1 input clock for driving the internal machine rate; PLL clock input for ’C50, ’C51, ’C52, ’C53, ’C53S. († Not available on ’LC56, ’C57S, ’LC57.) |
| CLKOUT1 | O/Z | Master clock output; cycles at the machine-cycle rate of the CPU; the internal machine cycle is bounded by the rising edges of this signal; Hi-Z when OFF active (low). |
| TOUT | O | Timer output; issues a pulse when the on-chip timer counts down past zero; the pulse is a CLKOUT1 cycle wide. |
| X1 | O | Internal oscillator output; output pin from the internal oscillator for the crystal; if the internal oscillator is not used, leave unconnected; does NOT go Hi-Z when OFF active (low). |
| X2/CLKIN | I | External clock input; input pin to internal oscillator from the crystal; if the internal oscillator is not used, a clock may be input on this pin; PLL clock input for ’LC56, ’C57S, ’LC57. |
| CLKMD1 | I | Clock mode input; determines clock mode — see Tables A–13 and A–14. |
| CLKMD2 | I | Clock mode input; determines clock mode — see Tables A–13 and A–14. |
| CLKMD3§ | I | Clock mode input; determines clock mode — see Table A–14. (§ Not available on ’C50, ’C51, ’C52, ’C53, ’C53S.) |

### Table A–13. Oscillator/Timer Standard Options (’C50, ’C51, ’C52, ’C53, ’C53S only) [PDF p.631 (printed p.A-18)]

| CLKMD1 | CLKMD2 | Clock mode |
|---:|---:|---|
| 0 | 0 | PLL disabled; internal oscillator disabled; input clock provided to X2/CLKIN pin; external clock with divide-by-2 option. |
| 0 | 1 | Reserved for test purposes. |
| 1 | 0 | PLL enabled; internal oscillator disabled; input clock provided to CLKIN2 pin; external clock option: for ’C50, ’C51, ’C53, ’C53S multiply-by-1; for ’C52 multiply-by-2. |
| 1 | 1 | PLL disabled; internal oscillator enabled; input clock provided to X2/CLKIN pin; internal or external divide-by-2 option. |

### Table A–14. Oscillator/Timer Expanded Options (’LC56, ’C57S, ’LC57 only) [PDF p.632 (printed p.A-19)]

| CLKMD1 | CLKMD2 | CLKMD3 | Clock mode |
|---:|---:|---:|---|
| 0 | 0 | 0 | PLL enabled; internal oscillator disabled; external multiply-by-3 option. |
| 0 | 0 | 1 | Internal oscillator disabled; external divide-by-2 option. |
| 0 | 1 | 0 | PLL enabled; internal oscillator disabled; external multiply-by-4 option. |
| 0 | 1 | 1 | PLL enabled; internal oscillator disabled; external multiply-by-2 option. |
| 1 | 0 | 0 | PLL enabled; internal oscillator disabled; external multiply-by-5 option. |
| 1 | 0 | 1 | PLL enabled; internal oscillator disabled; external multiply-by-1 option. |
| 1 | 1 | 0 | PLL enabled; internal oscillator disabled; external multiply-by-9 option. |
| 1 | 1 | 1 | Internal oscillator enabled; external/internal divide-by-2 option. |

### Table A–15. Serial Port Interface [PDF p.633 (printed p.A-20)]

| Signal | State | Function (one line) |
|---|---|---|
| CLKR, CLKR1, CLKR2, TCLKR | I | Receive clock; external clock for clocking data into the data receive shift register (RSR) from the data receive pin(s): ’C50/’C51/’C53: DR or TDR; ’C53S: DR1 or DR2; ’C51/’C52/’LC56/’C57S/’LC57: DR. Must be present during serial port transfers; if the port is not used, the pin(s) can be sampled as an input via the IN0 bit in SPC (and/or TSPC). |
| CLKX, CLKX1, CLKX2, TCLKX | I/O/Z | Transmit clock; clocks data from the data transmit shift register (XSR) to the data transmit pin(s): ’C50/’C51/’C53: DX or TDX; ’C53S: DX1 or DX2; ’C51/’C52/’LC56/’C57S/’LC57: DX. Input if the MCM bit in SPC (TSPC) is cleared; driven by the device at 1/4 the CLKOUT1 frequency when MCM is set; if the port is not used, the pin(s) can be sampled as an input via the IN1 bit in SPC (and/or TSPC); Hi-Z when OFF active (low). |
| DR, DR1, DR2, TDR | I | Received serial data; the RSR receives serial data through this input pin. |
| DX, DX1, DX2, TDX | O/Z | Transmitted serial data; the XSR transmits serial data through this pin; Hi-Z when not transmitting and when OFF active (low). |
| FSR, FSR1, FSR2, TFSR/TADD | I/O/Z | Receive frame synchronization; the falling edge initiates the data receive process, beginning the clocking of the RSR; TFSR becomes an input/output (TADD) pin when the ’C50, ’C51, ’C53 are operating in TDM mode (TDM bit = 1), used to output/input the address of the port; Hi-Z when OFF active (low). |
| FSX, FSX1, FSX2, TFSX/TFRM | I/O/Z | Transmit frame synchronization; the falling edge initiates the data transmit process, beginning the clocking of the XSR; default operating condition after reset is an input; software-selectable as an output when the TXM bit in SPC (TSPC) is set; Hi-Z when OFF active (low); when the ’C50, ’C51, ’C53 are in TDM mode (TDM bit = 1), the TFSX pin becomes TFRM (TDM frame synch). |

### Table A–16. Buffered Serial Port Interface (’LC56 and ’C57 only) [PDF p.634 (printed p.A-21)]

| Signal | State | Function (one line) |
|---|---|---|
| BCLKR | I | Receive clock; clocks data into the data receive shift register (BRSR) from the data receive (BDR) pin; falling edge of BCLKR if the CLKP bit in SPCE is cleared, rising edge if set; if the port is not used, the pin can be sampled as an input via the IN0 bit in SPC. |
| BCLKX | I/O/Z | Transmit clock; clocks data from the data transmit shift register (BXSR) to the data transmit (BDX) pin; rising edge if CLKP in SPCE is cleared, falling edge if set. (The manual's description here says "CLKX" where BCLKX is meant — as printed.) Input if the MCM bit in BSPC is cleared; when MCM = 1, driven by an on-chip source at 1/(CLKDV+1) of CLKOUT; CLKDV is defined in SPCE; CLKDV odd or 0 → 50% duty cycle; CLKDV even (= 2p): CLKP = 0 → high p+1 cycles, low p cycles; CLKP = 1 → high p cycles, low p+1 cycles. Default operating condition after reset is an input; if unused, samplable as an input via the IN1 bit in SPC. |
| BDR | I | Received serial data; the BRSR receives serial data through this input pin. |
| BDX | O/Z | Transmitted serial data; the BXSR transmits serial data through this pin; Hi-Z when not transmitting and when OFF active (low). |
| BFSR | O | Receive frame synchronization; initiates the data receive process; active high upon reset; configurable as active low by setting the FSP bit in SPCE. |
| BFSX | I/O/Z | Transmit frame synchronization; initiates the data transmit process; an input upon reset; configurable as an output by setting the TXM bit in SPC; active high upon reset; configurable as active low by setting the FSP bit in SPCE. |

### Table A–17. Host Port Interface (’C57 only) [PDF pp.635–636 (printed pp.A-22–A-23)]

| Signal | State | Function (one line) |
|---|---|---|
| HAS | I | Address strobe input; hosts with a multiplexed address/data bus connect HAS to their ALE pin or equivalent; HBIL, HCNTL0/1, and HR/W are then latched on the HAS falling edge; when used, HAS must precede the later of HCS, HDS1, or HDS2 (see the ’C5x data sheet for detailed HPI timing); hosts with separate address/data bus can tie HAS to logic 1, in which case HBIL, HCNTL0/1, and HR/W are latched by the later of HDS1, HDS2, or HCS falling edge while HAS stays inactive (high). |
| HBIL | I | Byte identification input; identifies first or second byte of transfer (not most/least significant — specified by the BOB bit in HPIC); low = first byte, high = second byte. |
| HCNTL0, HCNTL1 | I | Control inputs; indicate type of host access: 00 = host can read or write the HPIC; 01 = read/write the HPI data latches (HPIA postincremented when data is read, preincremented when data is written); 10 = read/write the HPIA (HPIA points to the HPI memory; DSP does not have access to the HPIA); 11 = read/write the HPI data latches, HPIA not affected. |
| HCS | I | Chip select input; enable for the HPI, must be low during an access but may stay low between accesses; normally precedes HDS1 and HDS2; also samples HCNTL0/1, HR/W, and HBIL if HAS is not used and HDS1 or HDS2 are already low. |
| HD7 (MSB)–HD0 (LSB) | I/O/Z | Parallel bidirectional 3-state data bus; Hi-Z when not outputting (HDSx and HCS = 1) or when OFF active (low). |
| HDS1, HDS2 | I | Data strobe inputs; control transfer of data during host access cycles; when HAS is not used, used to sample HBIL, HCNTL0/1, and HR/W when HCS is already low; hosts with separate read/write strobes connect those strobes to either HDS1 or HDS2; hosts with a single data strobe connect it to either HDS1 or HDS2, connecting the unused pin high; regardless of HDS connections, HR/W is still required to determine transfer direction; because HDS1 and HDS2 are internally exclusive-NORed, hosts with a high-true data strobe can connect it to one HDS input with the other connected low. |
| HINT | O/Z | Host interrupt; controlled by the HINT bit in HPIC; driven high when the ’C5x is being reset; Hi-Z when OFF active (low). |
| HRDY | O/Z | HPI ready output; high = HPI ready for a transfer; low = HPI busy completing the internal portion of the previous transaction; Hi-Z when OFF active (low); HCS enables HRDY — HRDY is always high when HCS is high. |
| HR/W | I | Read/write input; hosts must drive high to read HPI and low to write HPI; hosts without a R/W strobe can use an address line. |

### Table A–18. Emulation/Testing [PDF p.637 (printed p.A-24)]

| Signal | State | Function (one line) |
|---|---|---|
| TCK | I | IEEE JTAG 1149.1 test clock; normally a free-running clock with 50% duty cycle; TAP input signals (TMS, TDI) are clocked into the TAP controller, instruction register, or selected test data register on the rising edge of TCK; changes at the TAP output (TDO) occur on the falling edge of TCK. |
| TDI | I | IEEE JTAG 1149.1 test data input; clocked into the selected register (instruction or data) on a rising edge of TCK. |
| TDO | O/Z | IEEE JTAG 1149.1 test data output; contents of the selected register (instruction or data) are shifted out of TDO on the falling edge of TCK; Hi-Z except when scanning data; Hi-Z when OFF active low. |
| TMS | I | IEEE JTAG 1149.1 test mode select; serial control input clocked into the TAP controller on the rising edge of TCK. |
| TRST | I | IEEE JTAG 1149.1 test reset; when active high, gives the IEEE 1149.1 scan system control of the operations of the device; if not connected or driven low, the device operates in functional mode and the signals are ignored. |
| EMU0 | I/O/Z | Emulator pin 0; when TRST is driven low, EMU0 must be high for activation of the OFF condition; when TRST is driven high, EMU0 is used as an interrupt to or from the emulator system; defined as input/output via IEEE 1149.1 scan. |
| EMU1/OFF | I/O/Z | Emulator pin 1 / disable all outputs; when TRST is driven high, used as an interrupt to or from the emulator system, defined as input/output via IEEE 1149.1 scan; when TRST is driven low, configured as OFF — active (low) puts all output drivers into Hi-Z. OFF is used exclusively for testing and emulation (not for multiprocessing). OFF condition requires, for at least 2 machine cycles: TRST = low, EMU0 = high, EMU1/OFF = low. |

Note on Table A–18: "For emulation, TRST has an internal pulldown, and TMS, TCK, and TDI have internal pullups. EMU0 and EMU1 require external pullups to support emulation."

## Unverified / extraction notes (Appendix A)

- Figures A–1–A–5: the layout extraction scrambles the spatial (edge) labels of
  the pin diagrams, so no figure-only pin assignment is transcribed here; the
  tables above are the authoritative pin data. [UNVERIFIED — figure edge-label
  order, App A, PDF pp.615, 617, 619, 621, 623]
- Table A–1 pin 61 prints as `X2/CLKIN1`; Figure A–1 shows `X2/CLKIN`.
  Verified against a 200-dpi render of PDF p.616 that the table really prints
  `X2/CLKIN1` (manual quirk, not an extraction error). [App A, Table A–1,
  PDF p.616 (printed p.A-3)]
- Table A–16 BCLKX description says "CLKX" for the clocked-edge and MCM
  sentences; read as BCLKX (as printed, flagged above). [App A, Table A–16,
  PDF p.634 (printed p.A-21)]
