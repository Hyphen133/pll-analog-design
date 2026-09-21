`default_nettype none

// Synthesizable all-digital phase-locked loop.
//
// The phase accumulator is a numerically-controlled oscillator (NCO).  Its MSB
// is the output clock.  At every reference edge, a PI loop filter adjusts the
// frequency-control word to drive the wrapped accumulator phase toward zero.
// NOMINAL_FCW must be close to:
//
//   (f_out / f_clk) * 2**PHASE_WIDTH
//
// The defaults assume f_clk=100 MHz, f_ref=10 MHz and f_out=40 MHz.  The loop
// locks to the harmonic nearest NOMINAL_FCW, so the control clock must be at
// least twice the requested output frequency.
module adpll #(
    parameter integer PHASE_WIDTH       = 24,
    parameter integer NOMINAL_FCW       = 6500000,
    parameter integer MIN_FCW           = 4194304,
    parameter integer MAX_FCW           = 7864320,
    parameter integer KP_SHIFT          = 3,
    parameter integer KI_SHIFT          = 7,
    parameter integer LOCK_THRESHOLD    = 16384,
    parameter integer UNLOCK_THRESHOLD  = 65536,
    parameter integer LOCK_COUNT        = 16,
    parameter integer REF_TIMEOUT_CYCLES = 64
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         enable,
    input  wire                         ref_clk,
    output wire                         pll_clk,
    output reg                          locked,
    output reg signed [PHASE_WIDTH-1:0] phase_error,
    output reg        [PHASE_WIDTH-1:0] frequency_word
);

    localparam integer LOCK_COUNTER_WIDTH = $clog2(LOCK_COUNT + 1);
    localparam integer TIMEOUT_WIDTH = $clog2(REF_TIMEOUT_CYCLES + 1);
    localparam signed [PHASE_WIDTH+1:0] INTEGRATOR_MAX =
        (1 <<< (PHASE_WIDTH - 2)) - 1;
    localparam signed [PHASE_WIDTH+1:0] INTEGRATOR_MIN =
        -(1 <<< (PHASE_WIDTH - 2));

    // ASYNC_REG guides synthesis/P&R to keep the synchronizer stages together.
    (* ASYNC_REG = "TRUE" *) reg [2:0] ref_sync;

    reg [PHASE_WIDTH-1:0] phase_accumulator;
    reg signed [PHASE_WIDTH+1:0] integrator;
    reg [LOCK_COUNTER_WIDTH-1:0] lock_counter;
    reg [TIMEOUT_WIDTH-1:0] ref_timeout;

    wire ref_rise = ref_sync[1] & ~ref_sync[2];
    wire signed [PHASE_WIDTH-1:0] wrapped_phase =
        $signed(phase_accumulator);

    reg signed [PHASE_WIDTH+1:0] error_extended;
    reg signed [PHASE_WIDTH+1:0] integrator_candidate;
    reg signed [PHASE_WIDTH+1:0] integrator_limited;
    reg signed [PHASE_WIDTH+1:0] control_candidate;
    reg [PHASE_WIDTH-1:0] absolute_error;

    // PI arithmetic is combinational; its result is sampled only on ref_rise.
    always @* begin
        error_extended = -{{2{wrapped_phase[PHASE_WIDTH-1]}}, wrapped_phase};

        if (error_extended < 0)
            absolute_error = (~error_extended[PHASE_WIDTH-1:0]) + 1'b1;
        else
            absolute_error = error_extended[PHASE_WIDTH-1:0];

        integrator_candidate = integrator + (error_extended >>> KI_SHIFT);
        if (integrator_candidate > INTEGRATOR_MAX)
            integrator_limited = INTEGRATOR_MAX;
        else if (integrator_candidate < INTEGRATOR_MIN)
            integrator_limited = INTEGRATOR_MIN;
        else
            integrator_limited = integrator_candidate;

        control_candidate = $signed(NOMINAL_FCW) + integrator_limited
                          + (error_extended >>> KP_SHIFT);
    end

    assign pll_clk = enable ? phase_accumulator[PHASE_WIDTH-1] : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_sync <= 3'b000;
        end else begin
            ref_sync <= {ref_sync[1:0], ref_clk};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_accumulator <= {PHASE_WIDTH{1'b0}};
            frequency_word    <= NOMINAL_FCW[PHASE_WIDTH-1:0];
            integrator        <= {(PHASE_WIDTH+2){1'b0}};
            phase_error       <= {PHASE_WIDTH{1'b0}};
            lock_counter      <= {LOCK_COUNTER_WIDTH{1'b0}};
            ref_timeout       <= {TIMEOUT_WIDTH{1'b0}};
            locked            <= 1'b0;
        end else if (!enable) begin
            phase_accumulator <= {PHASE_WIDTH{1'b0}};
            frequency_word    <= NOMINAL_FCW[PHASE_WIDTH-1:0];
            integrator        <= {(PHASE_WIDTH+2){1'b0}};
            phase_error       <= {PHASE_WIDTH{1'b0}};
            lock_counter      <= {LOCK_COUNTER_WIDTH{1'b0}};
            ref_timeout       <= {TIMEOUT_WIDTH{1'b0}};
            locked            <= 1'b0;
        end else begin
            phase_accumulator <= phase_accumulator + frequency_word;

            if (ref_rise) begin
                ref_timeout <= {TIMEOUT_WIDTH{1'b0}};
                phase_error <= error_extended[PHASE_WIDTH-1:0];
                integrator  <= integrator_limited;

                if (control_candidate < $signed(MIN_FCW))
                    frequency_word <= MIN_FCW[PHASE_WIDTH-1:0];
                else if (control_candidate > $signed(MAX_FCW))
                    frequency_word <= MAX_FCW[PHASE_WIDTH-1:0];
                else
                    frequency_word <= control_candidate[PHASE_WIDTH-1:0];

                if (absolute_error <= LOCK_THRESHOLD) begin
                    if (lock_counter < LOCK_COUNT)
                        lock_counter <= lock_counter + 1'b1;
                    if (lock_counter >= LOCK_COUNT - 1)
                        locked <= 1'b1;
                end else begin
                    lock_counter <= {LOCK_COUNTER_WIDTH{1'b0}};
                    if (absolute_error > UNLOCK_THRESHOLD)
                        locked <= 1'b0;
                end
            end else if (ref_timeout < REF_TIMEOUT_CYCLES) begin
                ref_timeout <= ref_timeout + 1'b1;
            end else begin
                lock_counter <= {LOCK_COUNTER_WIDTH{1'b0}};
                locked <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
