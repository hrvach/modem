# S-Registers

Source: [Courier 56K Business Modem User Guide — S-Registers](https://support.usr.com/support/3453c/3453c-ug/s_registers.html)

**Understanding Bit-Mapped S-Registers**

A bit-mapped S-Register uses one number to describe a collection of settings. Bit-mapping allows us to pack a lot of information in a small space.

Bit-mapped registers are in the form of `Sr.b=*n*`, where r is the bit-mapped register;.b is the bit; n is 0 (off) or 1 (on).

The modem displays the value of an S-Register, as a decimal value between 0 and 255. The modem, however, understands the decimal value as a collection of binary digits (bits).

**How bits are mapped to decimal values**

Bits can be mapped into decimal values. Each bit can be either on (1) or off (0). Eight bits create 256 unique combinations of 1s and 0s. Each of the eight bits can be assigned a number corresponding to its position:

```
b b b b b b b b
7 6 5 4 3 2 1 0
```

Also, each bit can be assigned a value corresponding to its number (e.g., the value equals 2 to the power of the bit):

| **Bit** | **Value** |
| --- | --- |
| 7 | 128 |
| 6 | 64 |
| 5 | 32 |
| 4 | 16 |
| 3 | 8 |
| 2 | 4 |
| 1 | 2 |
| 0 | 1 |

**Converting Bits to Decimal Values**

Starting with a string of eight bits, assign each "1" bit a value based on its position. Add the values to come up with the final decimal value.

Here’s an example of how bits are converted to decimal values:

```
01001111
0 + 64 + 0 + 0 + 8 + 4 + 2 + 1 = 79
```

**Converting Decimal Values to Bits**

Convert decimal values to bits by finding the largest decimal equivalent that is less than the decimal value. Subtract the decimal equivalent and mark the equivalent bit "1." Continue until the decimal value is zero. See the example below.

```
113
113 - 64 = 49
01
49 -32 = 17
011
17 -16 = 1
0111
1 -1 = 0
01110001
```

**Setting Bit-Mapped S-Registers**

You can set bit-mapped S-Registers using either bits or decimal values. While it may be simpler for you to set the bits individually, your modem displays the S-Register settings in decimal form.

**Using Bits**

Turning individual bits on and off is the more direct way to set bit-mapped S-Registers. To do this, specify the S-Register that you want to set and then indicate which bits you want to turn on (1) or off (0).

**Example:**`ATS13.0=1.4=1.5=1`, turns bits 0, 4, and 5 on for S-Register 13.

**Using Decimal Values**

An alternative way to set bit-mapped S-Registers is by adding the decimal values of the bits and entering the total.

This example, `ATS13=49`, sets the same value as the one in Using Bits above.

## **A complete list of S-Registers**

| Register | Default | Function |
| --- | --- | --- |
| S0 | 0 | Sets the number of rings on which to   answer in Auto Answer mode. `S0=0` disables Auto Answer. S0=1 enables   Auto Answer and the Courier 56K Business Modem answers on the first   ring. |
| S1 | 0 | Counts and stores the number of rings   from an incoming call. |
| S2 | 43 | Stores the ASCII decimal code for the   escape code character. Default character is “+”. A value   of 128-255 disables the escape code. |
| S3 | 13 | Stores the ASCII decimal code for the   Carriage Return character. Valid range is 0-127. |
| S4 | 10 | Stores the ASCII decimal code for the   Line Feed character. Valid range is 0-127. |
| S5 | 8 | Stores the ASCII decimal code for the   Backspace character. A value of 128-255 disables the Backspace key's   delete function. |
| S6 | 0 | Set the number of seconds the Courier   56K Business Modem waits for a dial tone. |
| S7 | 60 | Sets the number of seconds the Courier   56K Business Modem waits for a carrier. May be set for much longer   duration if, for example, the Courier 56K Business Modem is originating   an international connection. |
| S8 | 2 | Sets the duration, in seconds, for the   pause (,) option in the Dial command and the pause between command   reexecutions (> and `A>` commands). |
| S9 | 6 | Sets the required duration, in tenths   of a second, of the remote device's carrier signal before recognition   by the Courier 56K Business Modem. |
| S10 | 14 | Sets the duration, in tenths of a second,   that the Courier 56K Business Modem waits after loss of carrier before   hanging up. This guard time allows the Courier 56K Business Modem   to distinguish between a line hit, or other disturbance that momentarily   breaks the connection, and a true disconnect (hanging up) by the remote   device. |
| S11 | 70 | Sets the duration and spacing, in milliseconds,   of dialed tones. |
| S12 | 50 | Sets the duration, in fiftieths of a   second, of the guard time for the escape code (`+++`) sequence. |
| S13 | 0 | Bit-mapped register. See the beginning   of this section for information about setting bit-mapped registers.<br><br>**Bit map:**<br>Bit 0 (1): Reset when DTR drops.<br>Bit 1 (2): Reverse normal Auto Answer operation:   On incoming RING, enter Originate Mode and look for an answer tone.<br>Bit 2 (4): Disable 250 ms pause before result code   display.<br>Bit 3 (8): On DTR signal, autodial the number stored   in NVRAM at position 0.<br>Bit 4 (16): At power-on/reset, autodial number stored   in NVRAM at position 0.<br>Bit 5 (32): Disable HST (used for testing V.32terbo   in Dual Standard Courier 56K Business Modems).<br>Bit 6 (64): Disable MNP Level 3 (used for testing   Level 2).<br>Bit 7 (128): Hardware reset (works like powering off   and then on). |
| S14 | 0 | Bit-mapped register ( See the beginning   of this section for information about setting bit-mapped registers).<br><br>**Bit map:**<br>Bit 0 (1): Disconnect on escape code. |
| S15 | 0 | Bit-mapped register. ( See the beginning   of this section for information about setting bit-mapped registers).<br><br>**Bit map:**<br>Bit 0 (1): Disable the Courier 56K Business Modem's   extra high-frequency equalisation if it causes problems on shorter-link   calls for HST modulation only.<br>Bit 1 (2): Disable online fallback.<br>Bit 2 (4): Disable 450 bps back channel HST only.<br>Bit 3 (8): Reset non-ARQ mode Transmit buffer from 1.5K bytes   to 128.The default 1.5K byte non-ARQ buffer allows data   transfer with X- and Y-modem type File Transfer Protocols without   using flow control.   The 128-byte option allows remote users with slower modems to stop   your transmitted data from scrolling off their screens. When remote   users send your computer an XOFF (<Ctrl-S>) and you stop transmitting,   the data in transit doesn’t exceed the size of their screen.<br>Bit 4 (16): Disable MNP Level 4; retransmitting the   larger Level 4 data blocks may be a problem if you expect a great   number of errors during a call.<br>Bit 5 (32): Set Backspace key to delete.<br>Bit 6 (64): Some earlier 2400 bps MNP modems, not   made by U.S. Robotics or Microcom, were not fully compatible with   the MNP protocol. If you have difficulty making a successful 2400   bps MNP connection with a remote MNP modem, it may be because of this   incompatibility. Set S15 to 64 and try again to make the connection.<br>Bit 7 (128): Custom applications only. |
| S16 | 0 | Bit-mapped register. ( See the beginning   of this section for information about setting bit-mapped registers).   For testing, refer to the Testing the Connection section of the Contents   section.<br><br>**Bit map:**<br>Bit 1 (2): Dial Test.<br>Bit 2 (4): Test pattern.<br>Bit 3 (8): Remote digital loopback. |
| S18 | 0 | Test timer for software-initiated loopback   testing (`&T*n*`); disabled when S18 is set to 0. Used to set the   duration of testing, in seconds, before the Courier 56K Business Modem   automatically times out and terminates the test. |
| S19 | 0 | Sets the duration, in minutes, for the   Inactivity Timer. The timer activates when there is no data activity   on the R232 interface, and at the timeout the Courier 56K Business   Modem hangs up. S19=0 disables the timer. |
| S21 | 10 | Sets, in 10-millisecond units, the length   of breaks sent from the Courier 56K Business Modem to the computer   or terminal. Applies to ARQ mode only. |
| S22 | 17 | Stores the ASCII code for the XON character. |
| S23 | 19 | Stores the ASCII code for the XOFF character. |
| S24 | 150 | Sets the duration, in 20-millisecond   units, between pulsed DSR signals when the Courier 56K Business Modem   is set to `&S2` or `&S3`. The default is 3 seconds. |
| S25 | 5 | Sets DTR recognition time in 10-millisecond   units. |
| S26 | 1 | Sets duration, in 10-millisecond units,   of the delay between RTS and the CTS in synchronous mode. |
| S27 | 0 | Bit-mapped register. ( See the beginning   of this section for information about setting bit-mapped registers).<br><br>**Bit map:**<br>Bit 0 (1): Enable ITU-T V.21 modulation at 300   bps for overseas calls. In V.21 mode, the Courier 56K Business Modem   answers both Bell 103 and V.21 calls, but only originates V.21 calls.<br>Bit 1 (2): Enable unencoded (non- trelliscoded)   modulation in V.32 mode; this option is part of the ITU-T V.32 recommendation,   but is rarely used.<br>Bit 2 (4): Disable V.32 modulation; used for   testing HST modulation.<br>Bit 3 (8): Disable 2100 Hz answer tone to allow   two V.42 devices to connect more quickly.<br>Bit 4 (16): See error control handshaking options   below.<br>Bit 5 (32): See error control handshaking options   below.<br>Bit 6 (64): Disable V.42 Detect Phase<br>Bit 7 (128): Unusual software incompatibility.   Some software may not accept some result codes. This setting disables   the codes and displays the 9600 code instead. The call's actual   rate can be viewed on the ATI6 screen.<br><br>**Error control handshaking options: Select the total value of bits 4 and 5:**<br>Bit 4=0, Bit 5=0: Complete handshaking sequence: V.42   Detection, LAPM error control, MNP.<br>Bit 4=16, Bit 5=0: Disable MNP.<br>Bit 4=0, Bit 5=32: Disable V.42 Detection and LAPM.<br>Bit 4=16, Bit 5=32: Disable Detection phase, if you know   that the remote Courier 56K Business Modem does LAPM, but not the   Detection phase. |
| S28 | 8 | Sets the duration in tenths of a second   of the extra 3000/600 Hz answer tones sent during V.32 hand-shaking.   This gives V.32 modems additional time to connect in V.32 mode before   timing out.   If there is difficulty answering older, manually operated V.32 modems   (for example, modems that require a button to be pushed in order to   dial), try lengthening the duration of the extra tones. Setting S28   to zero eliminates the extra tones resulting in a faster connect time   if, for example, the Courier 56K Business Modem is set to use V.21   modulation (300 bps) or V.23 modulation (1200 bps). |
| S29 | 20 | Sets the duration, in tenths of a second,   of the V.21 answer tone. |
| S32 | 9 | Assign Voice/Data switch function<br><br>**Bit map:**<br>Value 0: Disabled<br>Value 1: Voice/Data- originate mode<br>Value 2: Voice/Data- answer mode<br>Value 3: Redial last number<br>Value 4: Dial number stored at position 0<br>Value 5: Auto answer on/off toggle<br>Value 6: Reset modem<br>Value 7: Initiate remote digital loopback<br>Value 8: Busy out the phone line toggle<br>Value 9: Execute stored command (see &ZC command) |
| S34 | 0 | Bit-mapped register. See the beginning   of this section for information about setting bit-mapped registers.<br><br>**Bit map:**<br>Bit 0 (1): Disable V.32 bis. Used for troubleshooting;   Technical Support may ask you to disable V.32bis for testing purposes.<br>Bit 1 (2): Disable the Courier 56K Business   Modem's enhanced, proprietary V.32bis modulation. Used for troubleshooting.<br>Bit 2 (4): Disable the faster retrains that   occur during proprietary V.32 terbo modulation. Used for troubleshooting.<br>Bit 3 (8): Enable V.23. Required for some British   connections.<br>Bit 4 (16): Change MR LED to DSR<br>Bit 6 (64): Disable the remote-access busy message.<br>Bit 7 (128): Disable V.32 terbo. |
| S38 | 0 | Sets the duration, in seconds, before a forced hang-up   and clearing of the Transmit buffer when DTR drops during an ARQ   call.This is provided to allow time for a remote device   to acknowledge receipt of all transmitted data. Default = 0: The   Courier 56K Business Modem immediately hangs up when DTR drops.   If the Courier 56K Business Modem receives the `ATH` command, it ignores   S38 and immediately hangs up. |
| S41 | 0 | Sets the number of allowable remote-access login   Attempts, thus enabling or disabling remote access.The default setting of zero allows no remote login   Attempts, disabling remote access. A value of 1 or greater enables   remote access. If the number of unsuccessful login Attempts exceeds   the limit set by this register, the Courier 56K Business Modem returns   online and any further login Attempts during the remainder of that   connection are refused. |
| S42 | 126 | Stores the ASCII decimal code for the   remote-access escape character. The default character is a tilde (~). |
| S43 | 200 | Sets the duration, in fiftieths of a   second, of the guard time for the remote-access (~~~~) sequence. |
| S44 | 15 | Sets the duration, in seconds, of the   interval between losing carrier and reestablishing a connection. |
| S51 | 0 | Bit-mapped register. See the beginning   of this section for information about setting bit-mapped registers.<br><br>**Bit map:**<br>Bit 0 (1): Disable MNP/V.42 for V.22 (1200 bps)<br>Bit 1 (2): Disable MNP/V.42 for V.22 bis (2400   bps)<br>Bit 2 (4): Disable MNP/V.42 for V.32/V.32 bis/V.32   terbo (9600/14400/19200/21600 bps).<br>Bit 6 (64): Disable Selective Reject |
| S53 | 126 | Bit-mapped register. ( See the beginning   of this section for information about setting bit-mapped registers).<br><br>**Bit map:**<br>Bit 0 (1): Dial security enabled.<br>Bit 1 (2): Prompting enabled.<br>Bit 2 (4): Local-access password protection   enabled.<br>Bit 3 (8): DTMF security enabled.<br><br>*Enabling local-access password   protection disables the &Zn=s command (which stores up to 10   phone numbers) because stored phone numbers occupy the same space   in NVRAM as the dialback numbers for Dial Security accounts.* |
| S54 | 64 | Symbol rate bit-mapped register used   primarily by Technical Support for debugging purposes.<br><br>**Bit map:**<br>Bit 0 (1): Disable 2400 symbol rate.<br>Bit 1 (2): Disable 2743 symbol rate.<br>Bit 2 (4): Disable 2800 symbol rate.<br>Bit 3 (8): Disable 3000 symbol rate.<br>Bit 4 (16): Disable 3200 symbol rate.<br>Bit 5 (32): Disable 3429 symbol rate.<br>Bit 6 (64): Disable Call Indicate (CI).<br>Bit 7 (128): Disable V.8. |
| S55 | 0 | Trellis code bit-mapped register used   primarily by U.S. Robotics Technical Support for debugging purposes.<br><br>**Bit map:**<br>Bit 0 (1): Disable 8S-2D mapping.<br>Bit 1 (2): Disable 16S-4D mapping.<br>Bit 2 (4): Disable 32S-2D mapping.<br>Bit 3 (8): Disable 64S-4D mapping.<br>Bit 7 (128): Enable phase roll detection |
| S56 | 0 | Bit-mapped register primarily used by   Technical Support for debugging purposes.<br><br>**Bit map:**<br>Bit 0 (1): Disable non-linear coding.<br>Bit 1 (2): Disable TX level deviation.<br>Bit 2 (4): Disable preemphasis.<br>Bit 3 (8): Disable precoding.<br>Bit 4 (16): Disable shaping.<br>Bit 5 (32): Disable V.34+<br>Bit 6 (64): Disable V.34.<br>Bit 7 (128): Disable V.FC. |
| S58 | 0 | Bit-mapped register. (See the beginning   of this section for information about setting bit-mapped registers.)<br><br>**Bit map:**<br>Bit 1 (2): Disable Bler Monitor<br>Bit 5 (32): Enables/Disables V.90<br>Bit 6 (64): Disables V.92 functions |
| S59 | 0 | Bit-mapped register. (See the beginning   of this section for information about setting bit-mapped registers).<br><br>**Bit map:**<br>Bit 0 (1): Disable enhanced V.42bis<br>Bit 1 (2): Alternate Caller ID timing |
| S69 | 0 | Bit-mapped register. (See the beginning   of this section for information about setting bit-mapped registers).<br><br>**Bit map:**<br>Bit 0 (1): Disable external Plug and Play<br>Bit 1 (2): Enable Auto Redial<br>Bit 2 (4): See HS LED options below<br>Bit 3 (8): See HS LED options below<br>Bit 5 (32): Disable Digital Line Guard<br>Bit 6 (64): Disable Loop Monitor<br><br>**HS LED options: Select the total value of bits 2 and 3:**<br>Bit 2=0, Bit 3=0: HS LED is on at 2400 and above<br>Bit 2=4, Bit 3=0: HS LED is on at 14400 and above<br>Bit 2=0, Bit 3=8: HS LED is on at 16800 and above<br>Bit 2=4, Bit 3=8: HS LED is on at V.90/V.92 and above |
| S70 | 0 | Bit-mapped Register. (See   the beginning of this section for information about setting bit-mapped   registers.)<br><br>**Bit map:**<br>Bit 0 (1): Enable recognition of Ring A<br>Bit 1 (2): Enable recognition of Ring B<br>Bit 2 (4): Enable recognition of Ring C<br>Bit 3 (8): Enable recognition of Ring D<br>Bit 4 (16): Enable recognition of Ring E |
| S71 | 0 | RCID request delay (1/200 sec) |
| S72 | 0 | Bit-mapped Register. (See the beginning   of this section for information about setting bit-mapped registers.)<br><br>**Bit map:**<br>Bit 0 (1): # of requests<br>Bit 1 (2): # of requests<br>Bit 2 (4): # of requests<br>Bit 3 (8): Request duration * 10 mS<br>Bit 4 (16): Request duration * 10 mS<br>Bit 5 (32): Request duration * 10 mS<br>Bit 6 (64): Request duration * 10 mS<br>Bit 7 (128): Request duration * 10 mS |
| S73 | 0 | Bit-mapped Register. (See the beginning   of this section for information about setting bit-mapped registers.)<br><br>**Bit map:**<br>Bit 0 (1): Request level<br>Bit 1 (2): Request level<br>Bit 2 (4): Request level<br>Bit 3 (8): Request pause * 10 mS<br>Bit 4 (16): Request pause * 10 mS<br>Bit 5 (32): Request pause * 10 mS<br>Bit 6 (64): Request pause * 10 mS<br>Bit 7 (128): Request pause * 10 mS |
