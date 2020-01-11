module packet_assembler (
    input clk_pixel,
    input enable,
    input [23:0] header, // See Table 5-8 Packet Types
    input [55:0] sub [3:0],
    output logic [8:0] packet_data, // See Figure 5-4 Data Island Packet and ECC Structure
    output logic packet_enable
);

// Initialize parity bits to 0
logic [7:0] parity [4:0] = '{8'd0, 8'd0, 8'd0, 8'd0, 8'd0};

// See Figure 5-5 Error Correction Code generator. Generalization of a CRC with binary BCH.
// See https://en.wikipedia.org/wiki/BCH_code#Systematic_encoding:_The_message_as_a_prefix for further information.
function automatic [7:0] next_ecc;
input [7:0] ecc, next_bch_bit;
begin
    next_ecc = (ecc >> 1) ^ ((ecc[0] ^ next_bch_bit) ? 8'b10000011 : 8'd0);
end
endfunction

wire [7:0] parity_next [4:0] = '{next_ecc(parity[4], bch4[0]), next_ecc(parity[3], bch[3][0]), next_ecc(parity[2], bch[2][0]), next_ecc(parity[1], bch[1][0]), next_ecc(parity[0], bch[0][0])};

// The parity needs to be calculated 2 bits at a time for blocks 0 to 3.
// There's 56 bits being sent 2 bits at a time over TMDS channels 1 & 2, so the parity bits wouldn't be ready in time otherwise.
wire [7:0] parity_next_next [3:0] = '{next_ecc(parity_next[3], bch[3][1]), next_ecc(parity_next[2], bch[2][1]), next_ecc(parity_next[1], bch[1][1]), next_ecc(parity_next[0], bch[0][1])};

// 32 pixel wrap-around counter. See Section 5.2.3.4 for further information.
logic [4:0] counter = 5'd0;

always @(posedge clk_pixel)
begin
    if (enable)
    begin
        if (counter < 5'd24) // Compute ECC only on subpacket data, not on itself
        begin
            parity[3:0] <= parity_next_next;
            parity[4] <= parity_next[4];
        end
        else if (counter == 5'd31) // Reset ECC for next packet
        begin
            parity <= '{8'd0, 8'd0, 8'd0, 8'd0, 8'd0};
        end
    end
end

wire [63:0] bch [3:0] = '{{parity[3], sub[3]}, {parity[2], sub[2]}, {parity[1], sub[1]}, {parity[0], sub[0]}};
wire [31:0] bch4 = {parity[4], header};

// BCH packets 0 to 3 are transferred two bits at a time, requiring a counter from 0 to 63, incrementing two at a time.
// See Section 5.2.3.4 for further information.
wire [5:0] idx = {counter, 1'b0};

assign packet_enable = counter == 5'd0 && enable;

always @(posedge clk_pixel)
begin
    if (enable)
    begin
        packet_data <= {{bch[3][idx + 1], bch[2][idx + 1], bch[1][idx + 1], bch[0][idx + 1]}, {bch[3][idx], bch[2][idx], bch[1][idx], bch[0][idx]}, bch4[counter]};
        counter <= counter + 5'd1;
    end
end

endmodule
