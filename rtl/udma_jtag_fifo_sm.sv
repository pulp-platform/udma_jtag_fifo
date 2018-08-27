module udma_jtag_fifo_sm (
    input  logic         jtag_tck_i,
    input  logic         jtag_tdi_i,
    output logic         jtag_tdo_o,
    input  logic         jtag_trstn_i,

    input  logic         jtag_shift_dr_i,
    input  logic         jtag_update_dr_i,
    input  logic         jtag_capture_dr_i,

    input  logic  [31:0] data_rx_o,
    input  logic         data_rx_valid_o,
    input  logic         data_rx_ready_i,

    input  logic  [31:0] data_tx_i,
    input  logic         data_tx_valid_i,
    input  logic         data_tx_ready_o

);

    localparam CMD_R   = 2'b00;
    localparam CMD_W   = 2'b01;
    localparam CMD_RW  = 2'b10;
    localparam CMD_2S  = 2'b11;

    localparam SHIFT_REG_SIZE = 46;

    logic [SHIFT_REG_SIZE-1:0] r_rx_shiftreg;
    logic [SHIFT_REG_SIZE-1:0] s_rx_shiftreg;
    logic [SHIFT_REG_SIZE-1:0] r_tx_shiftreg;
    logic [SHIFT_REG_SIZE-1:0] s_tx_shiftreg;

    logic  [3:0] r_cmd;
    logic  [4:0] r_cnt; 

    logic        s_is_cmd_r;
    logic        s_is_cmd_w;
    logic        s_is_cmd_rw;
    logic        s_is_cnt_cmd;
    logic        s_is_cnt_8b;
    logic        s_is_cnt_16b;
    logic        s_is_cnt_32b;

    logic        s_incr_cnt;
    logic        s_clr_cnt;

    enum logic [2:0] { ST_IDLE, ST_TX, ST_RX, ST_TXRX, ST_2S} r_state,s_state_next;
    enum logic [3:0] { SAMPLE_NONE, SAMPLE_CMD, SAMPLE_8B, SAMPLE_16B, SAMPLE_32B, SAMPLE_ALL} s_sample_rx, s_sample_tx;

    assign s_rx_shiftreg = {jtag_tdi_i,r_cmd[SHIFT_REG_SIZE-1:1]};

    assign s_cmd = s_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-4];

    assign s_is_cmd_r  = (s_cmd == CMD_R);
    assign s_is_cmd_w  = (s_cmd == CMD_W);
    assign s_is_cmd_rw = (s_cmd == CMD_RW);

    always_comb begin
        s_incr_cnt = 1'b0;
        s_clr_cnt  = 1'b0;
        s_state_next = r_state;
        s_sample_rx = SAMPLE_NONE;
        s_sample_tx = SAMPLE_NONE;
        case(r_state)
        ST_IDLE:
        begin
            s_incr_cnt = 1'b1;
            s_sample_rx = SAMPLE_CMD;
            if(s_is_cnt_cmd)
            begin
                s_clr_cnt = 1'b1;
                if(s_is_cmd_r)
                begin
                    s_state_next = ST_RX;
                end
                else if(s_is_cmd_w)
                begin
                    s_state_next = ST_TX;
                end
                else if(s_is_cmd_rw)
                begin
                    s_state_next = ST_TXRX;
                end
                else
                begin
                    s_state_next = ST_2S;
                end
            end
        end
        ST_RX:
        begin
            s_incr_cnt  = 1'b1;
            //s_sample_rx = ;
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
        end
        else
        begin
            if(s_sample_rx == SAMPLE_CMD)
                r_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-4] <= s_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-4];
            else if(s_sample_rx == SAMPLE_8B)
                r_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-8] <= s_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-8];
            else if(s_sample_rx == SAMPLE_16B)
                r_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-16] <= s_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-16];
            else if(s_sample_rx == SAMPLE_32B)
                r_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-32] <= s_rx_shiftreg[SHIFT_REG_SIZE-1:SHIFT_REG_SIZE-32];
            else if(s_sample_rx == SAMPLE_ALL)
                r_rx_shiftreg <= s_rx_shiftreg;
        end
    end
    

endmodule // udma_jtag_fifo_sm