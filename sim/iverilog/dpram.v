// Behavioral dual-port RAM for iverilog simulation
// Replaces Altera-specific dpram.vhd
module dpram #(
    parameter addr_width = 8,
    parameter data_width = 8
)(
    input                       clock_a,
    input                       clken_a,
    input  [addr_width-1:0]     address_a,
    input  [data_width-1:0]     data_a,
    input                       wren_a,
    output reg [data_width-1:0] q_a,

    input                       clock_b,
    input                       clken_b,
    input  [addr_width-1:0]     address_b,
    input  [data_width-1:0]     data_b,
    input                       wren_b,
    output reg [data_width-1:0] q_b
);

reg [data_width-1:0] mem [0:(2**addr_width)-1];

// Port A
always @(posedge clock_a) begin
    if (clken_a) begin
        if (wren_a) begin
            mem[address_a] <= data_a;
            q_a <= data_a; // write-through
        end else begin
            q_a <= mem[address_a];
        end
    end
end

// Port B
always @(posedge clock_b) begin
    if (clken_b) begin
        if (wren_b) begin
            mem[address_b] <= data_b;
            q_b <= data_b;
        end else begin
            q_b <= mem[address_b];
        end
    end
end

// Task to peek at memory contents (for testbench verification)
task peek;
    input  [addr_width-1:0] addr;
    output [data_width-1:0] val;
    begin
        val = mem[addr];
    end
endtask

endmodule
