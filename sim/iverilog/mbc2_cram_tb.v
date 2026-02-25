// MBC2 CRAM write/read path testbench
// Tests the full path: CPU write -> cram_di masking -> dpram -> read back
`timescale 1ns / 1ps

module mbc2_cram_tb;

reg        clk_sys;
reg        ce_cpu;
reg        reset;
reg [14:0] cart_addr;
reg        cart_a15;
reg  [7:0] cart_di;
reg        cart_wr;
reg        cart_rd;
reg  [7:0] cart_mbc_type;

wire [7:0] cram_q;
wire       ram_enabled;
wire       has_battery;

integer pass_count = 0;
integer fail_count = 0;

mbc2_cram_harness uut (
    .clk_sys       ( clk_sys ),
    .ce_cpu        ( ce_cpu ),
    .reset         ( reset ),
    .cart_addr     ( cart_addr ),
    .cart_a15      ( cart_a15 ),
    .cart_di       ( cart_di ),
    .cart_wr       ( cart_wr ),
    .cart_rd       ( cart_rd ),
    .cart_mbc_type ( cart_mbc_type ),
    .cram_q        ( cram_q ),
    .ram_enabled   ( ram_enabled ),
    .has_battery   ( has_battery )
);

// Clock: 50MHz
initial clk_sys = 0;
always #10 clk_sys = ~clk_sys;

task check;
    input [255:0] name;
    input         condition;
    begin
        if (condition) begin
            $display("  PASS: %0s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: %0s", name);
            fail_count = fail_count + 1;
        end
    end
endtask

// Write to MBC2 register (address < 0x4000)
task mbc2_reg_write;
    input [15:0] addr;
    input [7:0]  data;
    begin
        @(posedge clk_sys);
        cart_a15  = addr[15];
        cart_addr = addr[14:0];
        cart_di   = data;
        cart_wr   = 1'b1;
        ce_cpu    = 1'b1;
        @(posedge clk_sys);
        cart_wr   = 1'b0;
        ce_cpu    = 1'b0;
        @(posedge clk_sys);
    end
endtask

// Write to CRAM (address 0xA000-0xA1FF for MBC2's 512x4 RAM)
task cram_write;
    input [8:0]  ram_addr; // 0-511
    input [7:0]  data;
    begin
        @(posedge clk_sys);
        // MBC2 CRAM is at 0xA000-0xA1FF
        cart_a15  = 1'b1;
        cart_addr = {1'b0, 5'b10000, ram_addr}; // 0xA000 + offset, bit14=0
        cart_di   = data;
        cart_wr   = 1'b1;
        ce_cpu    = 1'b1;
        @(posedge clk_sys);
        cart_wr   = 1'b0;
        ce_cpu    = 1'b0;
        // Wait for dpram write to settle
        @(posedge clk_sys);
        @(posedge clk_sys);
    end
endtask

// Read from CRAM
task cram_read;
    input  [8:0]  ram_addr;
    output [7:0]  data;
    begin
        @(posedge clk_sys);
        cart_a15  = 1'b1;
        cart_addr = {1'b0, 5'b10000, ram_addr};
        cart_rd   = 1'b1;
        cart_wr   = 1'b0;
        ce_cpu    = 1'b0;
        @(posedge clk_sys);
        @(posedge clk_sys);
        data = cram_q;
        cart_rd = 1'b0;
        @(posedge clk_sys);
    end
endtask

// Peek directly at dpram contents
task peek_cram;
    input  [16:0] addr;
    output [7:0]  val;
    begin
        uut.peek_cram(addr, val);
    end
endtask

reg [7:0] readback;
reg [7:0] stored;

initial begin
    $dumpfile("mbc2_cram.vcd");
    $dumpvars(0, mbc2_cram_tb);

    // Initialize - start with cart_mbc_type=0 so MBC2 enable=0 (reset)
    clk_sys       = 0;
    ce_cpu        = 0;
    reset         = 0;
    cart_addr     = 0;
    cart_a15      = 0;
    cart_di       = 0;
    cart_wr       = 0;
    cart_rd       = 0;
    cart_mbc_type = 8'h00; // Not MBC2 yet - allows MBC2 reset via ~enable

    // Hold MBC2 in reset for 2 clocks
    repeat(2) @(posedge clk_sys);
    cart_mbc_type = 8'h06; // Now enable MBC2+Battery
    repeat(2) @(posedge clk_sys);

    $display("=== MBC2 CRAM Write/Read Path Tests ===");
    `ifdef MBC2_WRITE_FIX
    $display("    (running WITH write-masking fix)");
    `else
    $display("    (running WITHOUT write-masking fix)");
    `endif

    // Enable RAM first
    mbc2_reg_write(16'h0000, 8'h0A);
    check("RAM enabled", ram_enabled === 1'b1);

    // ---- Test 1: Write 0x3A, verify upper nibble masked to 0xF ----
    // Fix sets upper nibble to 0xF: {4'hF, 4'hA} = 0xFA
    $display("Test 1: Write 0x3A to CRAM addr 0");
    cram_write(9'd0, 8'h3A);
    peek_cram(17'd0, stored);
    $display("    Stored value: 0x%02X", stored);
    `ifdef MBC2_WRITE_FIX
    check("0x3A stored as 0xFA (write-masked)", stored === 8'hFA);
    `else
    // Without fix, full 0x3A is stored
    check("0x3A stored as 0x3A (unmasked)", stored === 8'h3A);
    `endif

    // ---- Test 2: Write 0xA5, read back, verify ----
    $display("Test 2: Write 0xA5, read back");
    cram_write(9'd1, 8'hA5);
    peek_cram(17'd1, stored);
    $display("    Stored value: 0x%02X", stored);

    cram_read(9'd1, readback);
    $display("    Read back:    0x%02X", readback);
    `ifdef MBC2_WRITE_FIX
    check("0xA5 stored as 0xF5 (masked on write)", stored === 8'hF5);
    check("0xA5 reads back as 0xF5", readback === 8'hF5);
    `else
    check("0xA5 stored as 0xA5 (no write mask)", stored === 8'hA5);
    // Read path still masks, so 0xA5 -> 0xF5
    check("0xA5 reads back as 0xF5 (read-masked)", readback === 8'hF5);
    `endif

    // ---- Test 3: Ultima save sequence ----
    $display("Test 3: Ultima save sequence [0x42, 0xBE, 0xEF, 0x0D]");
    cram_write(9'd10, 8'h42);
    cram_write(9'd11, 8'hBE);
    cram_write(9'd12, 8'hEF);
    cram_write(9'd13, 8'h0D);

    cram_read(9'd10, readback);
    $display("    Read [10]: 0x%02X", readback);
    check("Addr 10: 0x42 reads as 0xF2", readback === 8'hF2);

    cram_read(9'd11, readback);
    $display("    Read [11]: 0x%02X", readback);
    check("Addr 11: 0xBE reads as 0xFE", readback === 8'hFE);

    cram_read(9'd12, readback);
    $display("    Read [12]: 0x%02X", readback);
    check("Addr 12: 0xEF reads as 0xFF", readback === 8'hFF);

    cram_read(9'd13, readback);
    $display("    Read [13]: 0x%02X", readback);
    check("Addr 13: 0x0D reads as 0xFD", readback === 8'hFD);

    // ---- Test 4: Discriminating test ----
    // This test FAILS without the write fix, PASSES with it
    $display("Test 4: DISCRIMINATING - Write 0xD7, peek dpram");
    cram_write(9'd20, 8'hD7);
    peek_cram(17'd20, stored);
    $display("    Stored in dpram: 0x%02X", stored);
    check("DISCRIMINATING: dpram stores 0xF7 (not 0xD7)", stored === 8'hF7);

    // ---- Test 5: Read back discriminating value ----
    $display("Test 5: Read back discriminating value");
    cram_read(9'd20, readback);
    $display("    Read back: 0x%02X", readback);
    // Both with and without fix, read path masks to lower 4 bits | 0xF0
    // With fix: stored 0xF7, read 0xF7. Without fix: stored 0xD7, read 0xF7.
    check("Read back is 0xF7", readback === 8'hF7);

    // ---- Test 6: RAM-disabled write prevention ----
    $display("Test 6: RAM-disabled write prevention");
    // Write a known value first
    cram_write(9'd30, 8'h03);
    peek_cram(17'd30, stored);
    $display("    Before disable: stored 0x%02X", stored);

    // Disable RAM
    mbc2_reg_write(16'h0000, 8'h00);
    check("RAM disabled", ram_enabled === 1'b0);

    // Try to write - should not change memory
    cram_write(9'd30, 8'hFF);
    peek_cram(17'd30, stored);
    $display("    After disabled write: stored 0x%02X", stored);
    `ifdef MBC2_WRITE_FIX
    check("Write blocked when RAM disabled (still 0xF3)", stored === 8'hF3);
    `else
    check("Write blocked when RAM disabled (still 0x03)", stored === 8'h03);
    `endif

    // Summary
    $display("");
    $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count > 0) begin
        $display("SOME TESTS FAILED");
        $finish(1);
    end else begin
        $display("ALL TESTS PASSED");
        $finish(0);
    end
end

endmodule
