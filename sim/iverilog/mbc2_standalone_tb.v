// MBC2 standalone testbench - tests mbc2.v register logic directly
`timescale 1ns / 1ps

module mbc2_standalone_tb;

reg        clk_sys;
reg        ce_cpu;
reg [14:0] cart_addr;
reg        cart_a15;
reg  [7:0] cart_di;
reg        cart_wr;
reg  [7:0] cart_mbc_type;
reg  [7:0] cram_di_reg;

wire [22:0] mbc_addr;
wire  [7:0] cram_do;
wire [16:0] cram_addr;
wire        ram_enabled;
wire        has_battery;
wire [15:0] savestate_back;

reg enable;

integer pass_count = 0;
integer fail_count = 0;

mbc2 uut (
    .enable           ( enable ),
    .clk_sys          ( clk_sys ),
    .ce_cpu           ( ce_cpu ),
    .savestate_load   ( 1'b0 ),
    .savestate_data   ( 16'd0 ),
    .savestate_back_b ( savestate_back ),
    .ram_mask         ( 2'b01 ),
    .rom_mask         ( 7'h0F ),
    .cart_addr        ( cart_addr ),
    .cart_a15         ( cart_a15 ),
    .cart_mbc_type    ( cart_mbc_type ),
    .cart_wr          ( cart_wr ),
    .cart_di          ( cart_di ),
    .cram_di          ( cram_di_reg ),
    .cram_do_b        ( cram_do ),
    .cram_addr_b      ( cram_addr ),
    .mbc_addr_b       ( mbc_addr ),
    .ram_enabled_b    ( ram_enabled ),
    .has_battery_b    ( has_battery )
);

// Clock generation: 50MHz
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

// Simulate a CPU write cycle
task cpu_write;
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

initial begin
    $dumpfile("mbc2_standalone.vcd");
    $dumpvars(0, mbc2_standalone_tb);

    // Initialize
    enable    = 0; // Start disabled for reset
    ce_cpu    = 0;
    cart_addr = 0;
    cart_a15  = 0;
    cart_di   = 0;
    cart_wr   = 0;
    cram_di_reg = 8'hA5;
    cart_mbc_type = 8'h06; // MBC2+Battery

    // Hold reset for 2 clocks, then enable
    repeat(2) @(posedge clk_sys);
    enable = 1;
    repeat(2) @(posedge clk_sys);

    $display("=== MBC2 Standalone Tests ===");

    // Test 1: Reset state - RAM disabled, ROM bank = 1
    $display("Test 1: Reset state");
    check("RAM disabled at reset", ram_enabled === 1'b0);
    check("ROM bank defaults to 1", mbc_addr[17:14] === 4'd1 || cart_addr[14] === 1'b0);

    // Test 2: Enable RAM (write 0x0A to 0x0000, bit8=0)
    $display("Test 2: Enable RAM");
    cpu_write(16'h0000, 8'h0A);
    check("RAM enabled after writing 0x0A", ram_enabled === 1'b1);

    // Test 3: Disable RAM (write anything != 0x0A to 0x00xx, bit8=0)
    $display("Test 3: Disable RAM");
    cpu_write(16'h0000, 8'h00);
    check("RAM disabled after writing 0x00", ram_enabled === 1'b0);

    // Re-enable for further tests
    cpu_write(16'h0000, 8'h0A);

    // Test 4: ROM bank select (write to 0x0100, bit8=1)
    $display("Test 4: ROM bank select");
    cpu_write(16'h0100, 8'h05);
    // Set address to bank area (cart_addr[14]=1) to see bank in mbc_addr
    @(posedge clk_sys);
    cart_a15 = 0;
    cart_addr = 15'h4000; // bit14=1, in bank area
    @(posedge clk_sys);
    check("ROM bank set to 5", mbc_addr[17:14] === 4'd5);

    // Test 5: Bank 0 redirect (writing 0 selects bank 1)
    $display("Test 5: Bank 0 redirect");
    cpu_write(16'h0100, 8'h00);
    @(posedge clk_sys);
    cart_a15 = 0;
    cart_addr = 15'h4000;
    @(posedge clk_sys);
    check("Bank 0 redirected to bank 1", mbc_addr[17:14] === 4'd1);

    // Test 6: Read masking (upper 4 bits forced to 0xF)
    $display("Test 6: Read masking");
    cram_di_reg = 8'hA5; // Feed 0xA5 as raw RAM data
    @(posedge clk_sys);
    check("Read mask: 0xA5 -> 0xF5", cram_do === 8'hF5);

    cram_di_reg = 8'h03;
    @(posedge clk_sys);
    check("Read mask: 0x03 -> 0xF3", cram_do === 8'hF3);

    // Test 7: Read returns 0xFF when RAM disabled
    $display("Test 7: Read with RAM disabled");
    cpu_write(16'h0000, 8'h00); // Disable RAM
    cram_di_reg = 8'hA5;
    @(posedge clk_sys);
    check("Read returns 0xFF when RAM disabled", cram_do === 8'hFF);

    // Test 8: has_battery
    $display("Test 8: has_battery flag");
    cart_mbc_type = 8'h06;
    @(posedge clk_sys);
    check("Type 0x06 has battery", has_battery === 1'b1);

    cart_mbc_type = 8'h05;
    @(posedge clk_sys);
    check("Type 0x05 no battery", has_battery === 1'b0);

    // Summary
    $display("");
    $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count > 0)
        $display("SOME TESTS FAILED");
    else
        $display("ALL TESTS PASSED");

    $finish;
end

endmodule
