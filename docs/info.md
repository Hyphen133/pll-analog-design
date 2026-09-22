<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

A classical **analog charge-pump PLL**, built from transistors rather than
standard cells. There is no accumulator, no adder and no digital loop filter
anywhere in the signal path — the control voltage is a real voltage on a real
on-chip capacitor.

```
 clk --->[ PFD ]--->[ charge pump ]--->[ R + C loop filter ]--->[ ring VCO ]---+---> uo[0]
            ^                                   |                             |
            |                                 ua[0]                           |
            +---------------[ divide by 8 ]<---------------------------------+
```

**Phase-frequency detector.** Two edge-triggered flip-flops with `D` tied high,
clocked by the reference and by the divided VCO, cleared once both outputs are
asserted. Being a *frequency* detector as well as a phase detector, it pulls
the loop in from an arbitrary starting frequency rather than relying on the VCO
already being close. Four inverters in the clear path stretch the reset pulse so
both current sources turn on briefly every cycle; that overlap is what removes
the charge-pump dead zone around zero phase error.

**Charge pump.** A current-steering pair: a PMOS source branch switched by `UP`,
an NMOS sink branch switched by `DN`, both mirrored from one bias leg so the up
and down currents track each other across process and temperature. Nominal
current is 5.3 µA, set by an on-chip 240 kΩ `rhigh` resistor; `ua[1]` exposes
the bias node so the current can be overridden externally.

**Loop filter.** Second-order passive: a series R + C1 creates the stabilising
zero, and a shunt C2 (C1/10) suppresses the ripple that the charge-pump pulses
would otherwise inject onto the control line. Values come from
`scripts/loop_filter.py`:

| Component | Value | IHP device |
| --------- | ----- | ---------- |
| R  | 51.2 kΩ | `rhigh`, w = 1 µm, l = 37.7 µm |
| C1 | 3.73 pF | `cap_cmim`, 49.9 × 49.9 µm |
| C2 | 373 fF  | `cap_cmim`, 15.8 × 15.8 µm |

That is a natural frequency of 1.5 MHz with a damping factor of 0.9, comfortably
below the 25 MHz reference (ratio 16.7, so the continuous-time approximation
holds).

**VCO.** A five-stage current-starved ring. The control voltage sets a tail
current through a long-channel NMOS; that current is mirrored into the header
PMOS and footer NMOS of every stage, so stage delay is C·ΔV/I and frequency
rises with `vctrl`. Tuning is monotonic across roughly 0.6–1.6 V.

**Divider.** Three toggle flip-flops, ÷8, closing the loop and providing a
25 MHz output slow enough to drive a pad.

### Caveat

This is a ring-oscillator PLL, so phase noise is far worse than an LC design.
It is a working frequency synthesiser and a teaching vehicle for the classic
charge-pump architecture, not a low-jitter clock source.

## How to test

1. Drive `clk` with a 25 MHz reference and apply power.
2. Hold `ui[0]` (`RSTB`) low briefly, then release it to start the divider from
   a known phase.
3. Watch `ua[0]` (`VCTRL`) on a scope: it should ramp and then settle at roughly
   0.92 V within a couple of microseconds.
4. `uo[0]` (`DIV_OUT`) should then sit at exactly 25 MHz, phase-locked to `clk`,
   which means the VCO is running at 8 × 25 MHz = 200 MHz.
5. `uo[1]` and `uo[2]` (`UP`, `DN`) show the PFD pulses. When locked both are
   narrow and nearly equal — that residual overlap is the anti-dead-zone pulse.
   A persistently wide `UP` means the loop is still pulling up in frequency.
6. To sweep the VCO open-loop, force a voltage on `ua[0]` and watch `uo[0]`;
   dividing the reading by 8 gives the tuning curve.
7. `ua[1]` (`IBIAS`) lets you change the charge-pump current, and hence the loop
   bandwidth, by sourcing current into the node instead of relying on the
   on-chip resistor.

## External hardware

None required. A 25 MHz clock source, an oscilloscope on `ua[0]` and `uo[0]`,
and optionally a current source or potentiometer on `ua[1]`.
