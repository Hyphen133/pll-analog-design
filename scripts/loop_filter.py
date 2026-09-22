#!/usr/bin/env python3
"""Size the PLL loop filter and print the matching IHP SG13G2 geometries.

The filter values depend directly on Kvco, which has to be measured from the
ring oscillator.  Re-run this whenever Kvco is re-extracted (in particular
after the first device-accurate PSP103 simulation) and update the defaults in
spice/blocks.spice with the numbers printed here.

    python3 scripts/loop_filter.py --kvco 500e6
"""

import argparse
import math

# IHP SG13G2 typical-corner process constants.
RHIGH_SHEET_OHM_PER_SQ = 1360.0
CMIM_F_PER_UM2 = 1.5e-15

# Ratio of the shunt ripple capacitor to the main capacitor.  Ten is the
# usual compromise: enough ripple rejection without pushing the parasitic
# pole close to the loop bandwidth.
C2_RATIO = 10.0


def design(icp_a, kvco_hz_per_v, n_div, fn_hz, zeta):
    """Return (R, C1, C2) for a second-order passive charge-pump filter."""
    k_pd = icp_a / (2.0 * math.pi)  # A/rad
    k_vco = 2.0 * math.pi * kvco_hz_per_v  # rad/s/V
    wn = 2.0 * math.pi * fn_hz

    c1 = k_pd * k_vco / (n_div * wn * wn)
    r = 2.0 * zeta / (wn * c1)
    c2 = c1 / C2_RATIO
    return r, c1, c2


def rhigh_geometry(r_ohm, width_um=1.0):
    """Length of a rhigh resistor of the given value at a fixed width."""
    squares = r_ohm / RHIGH_SHEET_OHM_PER_SQ
    return width_um, squares * width_um


def cmim_geometry(c_farad):
    """Side length of a square cap_cmim of the given value."""
    area_um2 = c_farad / CMIM_F_PER_UM2
    return math.sqrt(area_um2)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--icp", type=float, default=5.3e-6, help="charge-pump current [A]")
    p.add_argument("--kvco", type=float, default=500e6, help="VCO gain [Hz/V]")
    p.add_argument("--ndiv", type=int, default=8, help="feedback divide ratio")
    p.add_argument("--fn", type=float, default=1.5e6, help="loop natural frequency [Hz]")
    p.add_argument("--zeta", type=float, default=0.9, help="damping factor")
    p.add_argument("--fref", type=float, default=25e6, help="reference frequency [Hz]")
    args = p.parse_args()

    r, c1, c2 = design(args.icp, args.kvco, args.ndiv, args.fn, args.zeta)
    rw, rl = rhigh_geometry(r)
    c1_side = cmim_geometry(c1)
    c2_side = cmim_geometry(c2)

    print(f"Icp   = {args.icp * 1e6:.2f} uA")
    print(f"Kvco  = {args.kvco / 1e6:.1f} MHz/V")
    print(f"N     = {args.ndiv}")
    print(f"fn    = {args.fn / 1e6:.2f} MHz   zeta = {args.zeta}")
    print()
    print(f"R     = {r / 1e3:.1f} kOhm  -> rhigh    w={rw:.1f}u l={rl:.1f}u")
    print(f"C1    = {c1 * 1e12:.2f} pF    -> cap_cmim w={c1_side:.1f}u l={c1_side:.1f}u")
    print(f"C2    = {c2 * 1e15:.0f} fF    -> cap_cmim w={c2_side:.1f}u l={c2_side:.1f}u")
    print()
    print(f"total MIM area = {(c1 + c2) / CMIM_F_PER_UM2:.0f} um^2")

    # The loop is a sampled system: the reference must be well above the loop
    # bandwidth or the continuous-time design above stops being valid.
    ratio = args.fref / args.fn
    verdict = "ok" if ratio >= 10 else "TOO LOW - raise fref or lower fn"
    print(f"fref / fn      = {ratio:.1f}  ({verdict})")


if __name__ == "__main__":
    main()
