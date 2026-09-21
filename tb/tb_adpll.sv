`timescale 1ns/1ps
`default_nettype none

module tb_adpll;
    reg clk = 1'b0;
    reg ref_clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b0;

    wire pll_clk;
    wire locked;
    wire signed [23:0] phase_error;
    wire [23:0] frequency_word;

    integer output_edges;
    integer start_edges;
    integer timeout;

    // 100 MHz control clock and 10 MHz reference clock.  The 17 ns offset
    // deliberately keeps the reference asynchronous to the control clock.
    always #5 clk = ~clk;
    initial begin
        #17;
        forever #50 ref_clk = ~ref_clk;
    end

    always @(posedge pll_clk)
        output_edges = output_edges + 1;

    adpll dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .ref_clk(ref_clk),
        .pll_clk(pll_clk),
        .locked(locked),
        .phase_error(phase_error),
        .frequency_word(frequency_word)
    );

    initial begin
        $dumpfile("build/adpll.vcd");
        $dumpvars(0, tb_adpll);
        output_edges = 0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        enable = 1'b1;

        timeout = 0;
        while (!locked && timeout < 3000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!locked) begin
            $display("FAIL: PLL did not lock");
            $fatal(1);
        end

        $display("Locked after %0d control cycles: FCW=%0d error=%0d",
                 timeout, frequency_word, phase_error);

        // Ignore the edge coincident with the start of the measurement.  A
        // 40 MHz clock should produce 200 edges in 5 us (allow quantization).
        start_edges = output_edges;
        repeat (500) @(posedge clk);
        if ((output_edges - start_edges) < 199 ||
            (output_edges - start_edges) > 201) begin
            $display("FAIL: expected 200 +/- 1 output cycles, got %0d",
                     output_edges - start_edges);
            $fatal(1);
        end

        // Missing-reference watchdog must clear lock.
        force ref_clk = 1'b0;
        repeat (80) @(posedge clk);
        if (locked) begin
            $display("FAIL: reference-loss watchdog did not clear lock");
            $fatal(1);
        end
        release ref_clk;

        $display("PASS: ADPLL locks near 40 MHz and detects reference loss");
        $finish;
    end
endmodule

`default_nettype wire
