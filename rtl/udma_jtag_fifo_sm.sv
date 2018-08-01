module udma_jtag_fifo_sm (
    input  logic         jtag_tck_i,
    input  logic         jtag_tdi_i,
    output logic         jtag_tdo_o,
    input  logic         jtag_trstn_i,

    input  logic         jtag_shift_dr_i,
    input  logic         jtag_pause_dr_i,
    input  logic         jtag_update_dr_i,
    input  logic         jtag_capture_dr_i,

    input  logic  [31:0] data_rx_o,
    input  logic         data_rx_valid_o,
    input  logic         data_rx_ready_i,

    input  logic  [31:0] data_tx_i,
    input  logic         data_tx_valid_i,
    input  logic         data_tx_ready_o

);

  	enum logic [1:0] { ST_IDLE, ST_SEND, ST_RECEIVE} r_state,s_state_next;

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

    

endmodule // udma_jtag_fifo_sm