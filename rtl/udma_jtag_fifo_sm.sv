module udma_jtag_fifo_sm #(
    parameter CFG_WIDTH = 13
) (
    input  logic                 jtag_tck_i,
    input  logic                 jtag_tdi_i,
    output logic                 jtag_tdo_o,
    input  logic                 jtag_trstn_i,

    input  logic                 jtag_shift_dr_i,
    input  logic                 jtag_update_dr_i,
    input  logic                 jtag_capture_dr_i,

    output logic [CFG_WIDTH-1:0] cfg_value_o,
    output logic                 cfg_valid_o,
    input  logic                 cfg_ack_i,

    output logic          [31:0] data_rx_o,
    output logic                 data_rx_valid_o,
    input  logic                 data_rx_ready_i,

    input  logic          [31:0] data_tx_i,
    input  logic                 data_tx_valid_i,
    output logic                 data_tx_ready_o

);

    localparam CMD_R8     = 4'h0;
    localparam CMD_R16    = 4'h1;
    localparam CMD_R32    = 4'h2;
    localparam CMD_W8     = 4'h3;
    localparam CMD_W16    = 4'h4;
    localparam CMD_W32    = 4'h5;
    localparam CMD_RW8    = 4'h6;
    localparam CMD_RW16   = 4'h7;
    localparam CMD_RW32   = 4'h8;
    localparam CMD_SETUP  = 4'h9;
    localparam CMD_CRC    = 4'hA;
    localparam CMD_STATUS = 4'hB;

    localparam SR_WIDTH = CFG_WIDTH + 4;

    logic [SR_WIDTH-1:0] r_rx_shiftreg;
    logic [SR_WIDTH-1:0] s_rx_shiftreg;
    logic         [31:0] r_tx_shiftreg;
    logic         [31:0] s_tx_shiftreg;

    logic  [3:0] s_cmd;

    logic  [4:0] r_cnt; 

    logic        s_is_cmd_r;
    logic        s_is_cmd_r8;
    logic        s_is_cmd_r16;
    logic        s_is_cmd_r32;
    logic        s_is_cmd_w;
    logic        s_is_cmd_w8;
    logic        s_is_cmd_w16;
    logic        s_is_cmd_w32;
    logic        s_is_cmd_rw;
    logic        s_is_cmd_rw8;
    logic        s_is_cmd_rw16;
    logic        s_is_cmd_rw32;

    logic        s_update_size;
    logic        s_update_setup;
    logic        s_update_rx_sr;
    logic        s_update_tx_sr;
    logic        r_update_setup_dly;

    logic        s_incr_cnt;
    logic        s_clr_cnt;

    logic        s_data_ready;
    logic        s_data_valid;
    logic [31:0] s_data_out;

    logic        r_is_8b;
    logic        r_is_16b;
    logic        r_is_32b;

    logic        s_is_8b;
    logic        s_is_16b;
    logic        s_is_32b;

    enum logic [2:0] { ST_IDLE, ST_TX, ST_RX, ST_TXRX, ST_SETUP} r_state,s_state_next;
    
    assign s_cmd  = r_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-4];

    assign s_is_cmd_r8   = (s_cmd == CMD_R8);
    assign s_is_cmd_r16  = (s_cmd == CMD_R16);
    assign s_is_cmd_r32  = (s_cmd == CMD_R32);
    assign s_is_cmd_w8   = (s_cmd == CMD_W8);
    assign s_is_cmd_w16  = (s_cmd == CMD_W16);
    assign s_is_cmd_w32  = (s_cmd == CMD_W32);
    assign s_is_cmd_rw8  = (s_cmd == CMD_RW8);
    assign s_is_cmd_rw16 = (s_cmd == CMD_RW16);
    assign s_is_cmd_rw32 = (s_cmd == CMD_RW32);

    assign s_is_cmd_r = s_is_cmd_r8 | s_is_cmd_r16 | s_is_cmd_r32;
    assign s_is_cmd_w = s_is_cmd_w8 | s_is_cmd_w16 | s_is_cmd_w32;
    assign s_is_cmd_rw = s_is_cmd_rw8 | s_is_cmd_rw16 | s_is_cmd_rw32;

    assign jtag_tdo_o = ( r_cnt == 0 ) ? data_tx_i[0] : r_tx_shiftreg[0];

    assign data_rx_o       = s_data_out;
    assign data_rx_valid_o = s_data_valid;
    assign data_tx_ready_o = s_data_ready;

    assign cfg_value_o = r_rx_shiftreg[CFG_WIDTH-1:0];

    edge_propagator_tx i_edge_prop (
        .clk_i   ( jtag_tck_i   ),
        .rstn_i  ( jtag_trstn_i ),
        .valid_i ( r_update_setup_dly ),
        .ack_i   ( cfg_ack_i ),
        .valid_o ( cfg_valid_o )
    );
   
    always_comb begin
        s_incr_cnt     = 1'b0;
        s_clr_cnt      = 1'b0;
        s_state_next   = r_state;
        s_update_size  = 1'b0;
        s_update_setup = 1'b0;
        s_data_valid   = 1'b0;
        s_data_ready   = 1'b0;
        s_data_out     =  'h0;
        s_rx_shiftreg  = r_rx_shiftreg;
        s_tx_shiftreg  = r_tx_shiftreg;
        s_update_rx_sr = 1'b0;
        s_update_tx_sr = 1'b0;
        s_is_8b        = 1'b0;
        s_is_16b       = 1'b0;
        s_is_32b       = 1'b0;
        case(r_state)
        ST_IDLE:
        begin
            s_update_rx_sr = jtag_shift_dr_i;
            s_rx_shiftreg  = {jtag_tdi_i,r_rx_shiftreg[SR_WIDTH-1:1]};
            if(jtag_update_dr_i)
            begin
                s_clr_cnt = 1'b1;
                if(s_is_cmd_r)
                begin
                    s_update_size = 1'b1;
                    if(s_is_cmd_r8)
                        s_is_8b = 1'b1;
                    else if(s_is_cmd_r16)
                        s_is_16b = 1'b1;
                    else
                        s_is_32b = 1'b1;
                    s_state_next  = ST_TX;
                end
                else if(s_is_cmd_w)
                begin
                    s_update_size = 1'b1;
                    if(s_is_cmd_w8)
                        s_is_8b = 1'b1;
                    else if(s_is_cmd_w16)
                        s_is_16b = 1'b1;
                    else
                        s_is_32b = 1'b1;
                    s_state_next = ST_RX;
                end
                else if(s_is_cmd_rw)
                begin
                    s_update_size = 1'b1;
                    if(s_is_cmd_rw8)
                        s_is_8b = 1'b1;
                    else if(s_is_cmd_rw16)
                        s_is_16b = 1'b1;
                    else
                        s_is_32b = 1'b1;
                    s_state_next = ST_TXRX;
                end
                else
                begin
                    s_update_setup = 1'b1;
                end
            end
        end
        ST_RX:
        begin
            s_update_rx_sr = jtag_shift_dr_i;
            s_rx_shiftreg  = {jtag_tdi_i,r_rx_shiftreg[SR_WIDTH-1:1]};
            if(jtag_shift_dr_i)
            begin
                s_incr_cnt  = 1'b1;
                if(r_is_8b)
                begin
                    if(r_cnt == 'h7)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_valid = 1'b1;
                        s_data_out = {24'h0,s_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-8]};
                    end
                end
                else if(r_is_16b)
                begin
                    if(r_cnt == 'hF)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_valid = 1'b1;
                        s_data_out = {16'h0,s_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-16]};
                    end
                end
                else
                begin
                    if(r_cnt == 'h1F)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_valid = 1'b1;
                        s_data_out = s_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-32];
                    end
                end
            end
            else if(jtag_update_dr_i)
            begin
                s_state_next = ST_IDLE;
            end
        end
        ST_TX:
        begin
            s_update_tx_sr = jtag_shift_dr_i;
            s_tx_shiftreg  = (r_cnt == 0) ? {1'b0,data_tx_i[31:1]} : {1'b0,r_tx_shiftreg[31:1]};
            if(jtag_shift_dr_i)
            begin
                s_incr_cnt  = 1'b1;
                if(r_is_8b)
                begin
                    if(r_cnt == 'h7)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_ready = 1'b1;
                    end
                end
                else if(r_is_16b)
                begin
                    if(r_cnt == 'hF)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_ready = 1'b1;
                    end
                end
                else
                begin
                    if(r_cnt == 'h1F)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_ready = 1'b1;
                    end
                end
            end
            else if(jtag_update_dr_i)
            begin
                s_state_next = ST_IDLE;
            end
        end
        ST_TXRX:
        begin
            s_update_tx_sr = jtag_shift_dr_i;
            s_update_rx_sr = jtag_shift_dr_i;
            s_tx_shiftreg  = (r_cnt == 0) ? {1'b0,data_tx_i[31:1]} : {1'b0,r_tx_shiftreg[31:1]};
            s_rx_shiftreg  = {jtag_tdi_i,r_rx_shiftreg[SR_WIDTH-1:1]};
            if(jtag_shift_dr_i)
            begin
                s_incr_cnt  = 1'b1;
                if(r_is_8b)
                begin
                    if(r_cnt == 'h7)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_ready = 1'b1;
                        s_data_valid = 1'b1;
                        s_data_out = {24'h0,s_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-8]};
                    end
                end
                else if(r_is_16b)
                begin
                    if(r_cnt == 'hF)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_ready = 1'b1;
                        s_data_valid = 1'b1;
                        s_data_out = {16'h0,s_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-16]};
                    end
                end
                else
                begin
                    if(r_cnt == 'h1F)
                    begin
                        s_clr_cnt    = 1'b1;
                        s_data_ready = 1'b1;
                        s_data_valid = 1'b1;
                        s_data_out = s_rx_shiftreg[SR_WIDTH-1:SR_WIDTH-32];
                    end
                end
            end
            else if(jtag_update_dr_i)
            begin
                s_state_next = ST_IDLE;
            end
        end
        endcase // r_state
     end 

    always_ff @(posedge jtag_tck_i, negedge jtag_trstn_i)
    begin
        if(~jtag_trstn_i)
        begin
            r_cnt <= 'h0;
        end
        else
        begin
            if(s_clr_cnt)
                r_cnt <= 'h0;
            else if(s_incr_cnt)
                r_cnt <= r_cnt + 1;
        end
    end

    always_ff @(posedge jtag_tck_i, negedge jtag_trstn_i)
    begin
        if(~jtag_trstn_i)
        begin
            r_state <= ST_IDLE;
        end
        else
        begin
            r_state <= s_state_next;
        end
    end

    always_ff @(posedge jtag_tck_i, negedge jtag_trstn_i)
    begin
        if(~jtag_trstn_i)
        begin
            r_rx_shiftreg <= 'h0;
            r_tx_shiftreg <= 'h0;
            r_update_setup_dly <= 'h0;
            r_is_8b <= 'h0;
            r_is_16b <= 'h0;
            r_is_32b <= 'h0;
        end
        else
        begin
            r_update_setup_dly <= s_update_setup;
            if(s_update_rx_sr)
                r_rx_shiftreg <= s_rx_shiftreg;
            if(s_update_tx_sr)
                r_tx_shiftreg <= s_tx_shiftreg;
            if(s_update_size)
            begin
                r_is_8b  <= s_is_8b;
                r_is_16b <= s_is_16b;
                r_is_32b <= s_is_32b;
            end
        end
    end
    

endmodule // udma_jtag_fifo_sm
