`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_top.v — Top-level integration testbench
// Tests the complete ECG secure enclave system.
//////////////////////////////////////////////////////////////////////////////

module tb_top;

    reg          clk_100mhz;
    reg          btn_rst;
    reg  [15:0]  sw;

    // Analog inputs (simulated - XADC won't work in behavioral sim)
    wire         vauxp6, vauxn6;

    // Digital inputs
    reg          leads_off_p;
    reg          leads_off_n;

    // Outputs
    wire         uart_txd;
    wire [3:0]   vga_r, vga_g, vga_b;
    wire         vga_hsync, vga_vsync;
    wire [6:0]   seg;
    wire [3:0]   an;
    wire         dp;
    wire [15:0]  led;

    // DUT
    top_basys3 dut (
        .clk_100mhz(clk_100mhz),
        .btn_rst(btn_rst),
        .sw(sw),
        .vauxp6(vauxp6),
        .vauxn6(vauxn6),
        .leads_off_p(leads_off_p),
        .leads_off_n(leads_off_n),
        .uart_txd(uart_txd),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .seg(seg),
        .an(an),
        .dp(dp),
        .led(led)
    );

    // Clock: 100 MHz (10 ns period)
    initial clk_100mhz = 0;
    always #5 clk_100mhz = ~clk_100mhz;

    // UART receiver for monitoring output
    reg [7:0] uart_rx_data;
    reg       uart_rx_valid;
    integer   uart_byte_count;

    // Simple UART receiver (behavioral)
    task uart_receive_byte;
        output [7:0] data;
        integer i;
        begin
            // Wait for start bit (falling edge on tx line)
            wait(uart_txd == 0);
            #(8680); // Half bit period (center of start bit) at 115200 baud

            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                #(8680); // One bit period
                data[i] = uart_txd;
            end

            #(8680); // Stop bit
            uart_byte_count = uart_byte_count + 1;
        end
    endtask

    // Monitor UART output in background
    initial begin
        uart_byte_count = 0;
        forever begin
            uart_receive_byte(uart_rx_data);
            $display("  UART byte %0d: 0x%02h", uart_byte_count, uart_rx_data);
        end
    end

    // Main test sequence
    initial begin
        $display("=== ECG Secure Enclave Top-Level Testbench ===");
        $display("");

        // Initialize
        btn_rst = 1;
        sw = 16'h0001;    // SW0 = encryption enable
        leads_off_p = 0;
        leads_off_n = 0;

        // Reset
        #1000;
        btn_rst = 0;
        $display("Reset released at %0t ns", $time);

        // Since XADC won't produce real data in behavioral simulation,
        // we primarily verify:
        // 1. Clock dividers are generating correct frequencies
        // 2. VGA sync signals are generated
        // 3. State machines don't lock up
        // 4. UART outputs framed data

        // Wait for a few VGA frames
        #20_000_000; // 20ms

        $display("");
        $display("Checking VGA sync...");
        // Count hsync edges in 1ms
        begin : vga_check
            integer hsync_count;
            integer vsync_count;
            reg hsync_prev, vsync_prev;

            hsync_count = 0;
            vsync_count = 0;
            hsync_prev = vga_hsync;
            vsync_prev = vga_vsync;

            repeat(100000) begin
                @(posedge clk_100mhz);
                if (vga_hsync && !hsync_prev) hsync_count = hsync_count + 1;
                if (vga_vsync && !vsync_prev) vsync_count = vsync_count + 1;
                hsync_prev = vga_hsync;
                vsync_prev = vga_vsync;
            end
            $display("  In 1ms: %0d hsync edges (expect ~31), %0d vsync edges (expect ~0-1)",
                     hsync_count, vsync_count);
        end

        // Test leads-off detection
        $display("");
        $display("Testing leads-off detection...");
        leads_off_p = 1;
        #100000;
        $display("  LED[15] (leads-off) = %b (expect 1)", led[15]);
        leads_off_p = 0;
        #100000;

        // Test switch controls
        $display("");
        $display("Testing encryption toggle...");
        sw[0] = 0;  // Disable encryption
        #100000;
        sw[0] = 1;  // Re-enable
        #100000;

        // Let it run a bit more
        #10_000_000;

        $display("");
        $display("=== Top-Level Test Complete ===");
        $display("  UART bytes transmitted: %0d", uart_byte_count);
        $display("  Final LED state: %016b", led);
        $display("  7-seg: seg=%07b an=%04b", seg, an);
        $finish;
    end

    // Timeout: 100ms simulation time
    initial begin
        #100_000_000;
        $display("TIMEOUT: Simulation completed 100ms");
        $finish;
    end

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
