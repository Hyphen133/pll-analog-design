#!/usr/bin/env python3
"""Cycle-accurate dependency-free model of the default ADPLL configuration."""

PHASE_WIDTH = 24
MODULUS = 1 << PHASE_WIDTH
NOMINAL_FCW = 6_500_000
MIN_FCW = 4_194_304
MAX_FCW = 7_864_320
KP_SHIFT = 3
KI_SHIFT = 7
LOCK_THRESHOLD = 16_384
LOCK_COUNT = 16


def signed_phase(value: int) -> int:
    return value if value < MODULUS // 2 else value - MODULUS


def main() -> None:
    phase = 0
    integrator = 0
    fcw = NOMINAL_FCW
    good_samples = 0
    lock_cycle = None
    output_edges = 0
    previous_msb = 0

    for cycle in range(3_000):
        # One synchronized 10 MHz reference edge per ten 100 MHz cycles.
        if cycle % 10 == 2:
            error = -signed_phase(phase)
            integrator += error >> KI_SHIFT
            integrator = max(-(1 << 22), min((1 << 22) - 1, integrator))
            fcw = NOMINAL_FCW + integrator + (error >> KP_SHIFT)
            fcw = max(MIN_FCW, min(MAX_FCW, fcw))
            good_samples = good_samples + 1 if abs(error) <= LOCK_THRESHOLD else 0
            if good_samples >= LOCK_COUNT and lock_cycle is None:
                lock_cycle = cycle

        phase = (phase + fcw) % MODULUS
        msb = phase >> (PHASE_WIDTH - 1)
        if msb and not previous_msb:
            output_edges += 1
        previous_msb = msb

    assert lock_cycle is not None and lock_cycle < 1_200
    assert abs(fcw - round(0.4 * MODULUS)) <= 2
    assert 1_190 <= output_edges <= 1_210
    print(
        f"PASS: lock_cycle={lock_cycle}, final_fcw={fcw}, "
        f"frequency={100e6 * fcw / MODULUS / 1e6:.6f} MHz"
    )


if __name__ == "__main__":
    main()
