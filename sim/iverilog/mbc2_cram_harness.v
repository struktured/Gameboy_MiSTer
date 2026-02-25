// MBC2 CRAM write/read harness for simulation
// Extracts the glue logic from cart.v relevant to MBC2 CRAM access
module mbc2_cram_harness (
    input        clk_sys,
    input        ce_cpu,
    input        reset,

    // CPU bus
    input [14:0] cart_addr,
    input        cart_a15,
    input  [7:0] cart_di,
    input        cart_wr,
    input        cart_rd,

    // Cart type
    input  [7:0] cart_mbc_type,

    // CRAM read output
    output [7:0] cram_q,

    // Expose internal signals for test inspection
    output       ram_enabled,
    output       has_battery
);

// MBC2 detection (from cart.v:228)
wire mbc2 = (cart_mbc_type == 5) || (cart_mbc_type == 6);

// nCS: active-low chip select for cartridge space.
// In real Gameboy, nCS=0 for ROM (0x0000-0x7FFF) and CRAM (0xA000-0xBFFF).
// All test accesses target cart space, so tie low.
wire nCS = 1'b0;

// MBC2 mapper instance
wire [22:0] mbc_addr;
wire [7:0]  mbc_cram_do;
wire [16:0] mbc_cram_addr;
wire        mbc_ram_enable;
wire        mbc_has_battery;

// Savestate - not used in test
wire        sleep_savestate = 1'b0;
wire [7:0]  Savestate_CRAMWriteData = 8'h00;
wire [16:0] Savestate_CRAMAddr = 17'd0;
wire        Savestate_CRAMRWrEn = 1'b0;

// MBC2 doesn't use mbc_cram_wr path (it uses the normal cart write path)
wire        mbc_cram_wr = 1'b0;
wire [7:0]  mbc_cram_wr_do = 8'h00;

// Savestate buses (active-low Z for disabled mappers)
wire [15:0] savestate_back;

mbc2 map_mbc2 (
    .enable           ( mbc2 ),

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

    .cram_di          ( cram_q_selected ),
    .cram_do_b        ( mbc_cram_do ),
    .cram_addr_b      ( mbc_cram_addr ),

    .mbc_addr_b       ( mbc_addr ),
    .ram_enabled_b    ( mbc_ram_enable ),
    .has_battery_b    ( mbc_has_battery )
);

assign ram_enabled = mbc_ram_enable;
assign has_battery = mbc_has_battery;

// CRAM address and write logic (from cart.v:405-411)
wire is_cram_addr = ~nCS & ~cart_addr[14]; // address 0xA000-0xBFFF maps to CRAM

wire cram_rd_sig = cart_rd & is_cram_addr;
wire cram_wr_sig = sleep_savestate ? Savestate_CRAMRWrEn : mbc_cram_wr || (cart_wr & is_cram_addr & mbc_ram_enable);

wire [16:0] cram_addr_w = sleep_savestate ? Savestate_CRAMAddr[16:0] : mbc_cram_addr;

// THE FIX: ifdef-controlled write masking for MBC2
`ifdef MBC2_WRITE_FIX
wire [7:0] cram_di_w = sleep_savestate ? Savestate_CRAMWriteData : mbc_cram_wr ? mbc_cram_wr_do : (mbc2 ? {4'hF, cart_di[3:0]} : cart_di);
`else
wire [7:0] cram_di_w = sleep_savestate ? Savestate_CRAMWriteData : mbc_cram_wr ? mbc_cram_wr_do : cart_di;
`endif

// CRAM output mux (from cart.v:401)
wire [7:0] cram_q_h;
wire [7:0] cram_q_l;
wire [7:0] cram_q_selected = cram_addr_w[0] ? cram_q_h : cram_q_l;

// The MBC2 read path feeds cram_q_selected into cram_di of the mapper,
// which applies its own 4-bit masking on reads. For the final output we
// use the mapper's cram_do which includes the read mask.
assign cram_q = mbc_cram_do;

// Dual-port RAM instances (from cart.v:425-451)
dpram #(16) cram_l (
    .clock_a   ( clk_sys ),
    .clken_a   ( 1'b1 ),
    .address_a ( cram_addr_w[16:1] ),
    .wren_a    ( cram_wr_sig & ~cram_addr_w[0] ),
    .data_a    ( cram_di_w ),
    .q_a       ( cram_q_l ),

    .clock_b   ( clk_sys ),
    .clken_b   ( 1'b1 ),
    .address_b ( 16'd0 ),
    .wren_b    ( 1'b0 ),
    .data_b    ( 8'd0 ),
    .q_b       ( )
);

dpram #(16) cram_h (
    .clock_a   ( clk_sys ),
    .clken_a   ( 1'b1 ),
    .address_a ( cram_addr_w[16:1] ),
    .wren_a    ( cram_wr_sig & cram_addr_w[0] ),
    .data_a    ( cram_di_w ),
    .q_a       ( cram_q_h ),

    .clock_b   ( clk_sys ),
    .clken_b   ( 1'b1 ),
    .address_b ( 16'd0 ),
    .wren_b    ( 1'b0 ),
    .data_b    ( 8'd0 ),
    .q_b       ( )
);

// Expose dpram contents for test peeking
// We access the correct dpram based on address LSB
task peek_cram;
    input  [16:0] addr;
    output [7:0]  val;
    begin
        if (addr[0])
            cram_h.peek(addr[16:1], val);
        else
            cram_l.peek(addr[16:1], val);
    end
endtask

endmodule
