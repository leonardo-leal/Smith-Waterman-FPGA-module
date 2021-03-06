// Author: Ilir Likalla


/* NOTES:
	- in this version of the feeder module the state machines are expressed as single 'always@' blocks
	- code based on VERILOG 2001 standard.
	- possible faults are associated by the comment "!X!"
*/


// input selection macros:
`define ID		buffer_in[(IN_WIDTH-1)-:ID_WIDTH]
`define LENGTH 	buffer_in[(2*TARGET_LENGTH+LEN_WIDTH-1)-:LEN_WIDTH]
`define TARGET 	buffer_in[(2*TARGET_LENGTH-1):0]

module SM_feeder
	#( parameter
		TARGET_LENGTH = 128,			// target sequence's length	
		LEN_WIDTH = 12,					// sequence's length width in bits
		ID_WIDTH = 48,					// sequence's ID width in bits
		IN_WIDTH = (ID_WIDTH			
				+ LEN_WIDTH
				+ (2*TARGET_LENGTH))	// input's width (data_in)
	)(
	input clk,
	input rst,
	input ld,							// load signal
	input toggle,						// toggle from ScoringModule
	input [IN_WIDTH-1:0] feed_in,		// input data
	input re0,							// id0 fifo's read enable
	input re1,							// id1 fifo's read enable
	output reg en0,
	output reg en1,
	output reg [1:0] data_out,
	output reg full,					// is set when the feeder is full of targets
	output [ID_WIDTH-1:0] id0,
	output [ID_WIDTH-1:0] id1				
	);
	
	// --- internal signals: ---

	// counter signals:
	reg [LEN_WIDTH-1:0] counter0;			// counter for toggle 0
	reg [LEN_WIDTH-1:0] counter1;			// counter for toggle 1
	
	// sequence related signals:
	reg [LEN_WIDTH-1:0] length0;		// sequence's length register 0
	reg [LEN_WIDTH-1:0] length1;		// sequence's length register 1
	reg [2*TARGET_LENGTH-1:0] target0;	// target sequence registers
	reg [2*TARGET_LENGTH-1:0] target1;	// target sequence registers
	reg loaded0;						// is set when the respective target register is loaded
	reg loaded1;						// is set when the respective target register is loaded
	reg [IN_WIDTH-1:0] buffer_in;		// input buffer
	reg buffer_vld;						// valid signal for the buffer_in

	// state signals:
	localparam 	idle = 1'b0,
				feed = 1'b1;
	reg [1:0] state;						// state register
	wire [2:0] state_w;

	// fifo signals:
	reg we0, we1;
	wire full0, full1;
 
	// --- instantiations: ---
	
	// fifo for toggle 0:
	fifo
	#(
		.WIDTH(ID_WIDTH),
		.DEPTH(4)
	) id_fifo0 (
	.rst(rst),
	.clk(clk),
	.we(we0),
	.re(re0),
	.in(`ID),
	.full(full0),
	.out(id0)
	);

	// fifo fot toggle 1:
	fifo
	#(
		.WIDTH(ID_WIDTH),
		.DEPTH(4)
	) id_fifo1 (
	.rst(rst),
	.clk(clk),
	.we(we1),
	.re(re1),
	.in(`ID),
	.full(full1),
	.out(id1)
	);

	
    

	// --- sequential part: ---

	
	// input buffer logic:
	always@(posedge clk)
	begin
		buffer_vld <= 1'b0;
		if(~loaded0 || ~ loaded1)
			{buffer_vld, buffer_in} <= {ld, feed_in};
	end
	
	// state machine:
	assign state_w = {toggle,state};
	always@(posedge clk)
	begin	
		if(~rst)
		begin
			loaded0 <= 1'b0;
			loaded1 <= 1'b0;
			en0 <= 1'b0;
			en1 <= 1'b0;
			state <= {idle, idle};
		end else
		begin
			case(state_w)
			//if any of the target registers is empty, load new sequence:
			{1'b1, state[1], idle}:		// mutually exclusive events!

				if(buffer_vld && ~loaded0)											// !X! ->  data might be overwritten. error signal?
				begin
					length0 <= `LENGTH;
					target0 <= `TARGET;
					loaded0 <= 1'b1;	
					en0 <= 1'b1;
					state[0] <= feed;				// enable the state machine to feed data on toggle 0
				end 
					
			{1'b0, idle, state[0]}:
				if(buffer_vld && ~loaded1)						// else load the second register, if it's also empty.
				begin
					length1 <= `LENGTH;
					target1 <= `TARGET;
					loaded1 <= 1'b1;	
					en1 <= 1'b1;
					state[1] <= feed;				// enable the state machine to feed data on toggle 1
				end
	
			// feed state 0 (feeds data on toggle 0 !X!):	
			{1'b1, state[1], feed}:			
				begin
					// feed the first sequence:
					target0[2*TARGET_LENGTH-1:0] <= {2'b00,target0[2*TARGET_LENGTH-1:2]}; // feed bases to scoring module, by shifting out the sequence !X!
					if(counter0 == (length0 - 1))
					begin 
						en0 <= 1'b0;
						loaded0 <= 1'b0;
						state[0] <= idle;
					end						
				end  
			// feed state 1 (feeds data on toggle 1 !X!):	
			{1'b0, feed, state[0]}:			
				begin
					// feed the second sequence:
					target1[2*TARGET_LENGTH-1:0] <= {2'b00,target1[2*TARGET_LENGTH-1:2]}; // feed bases to scoring module, by shifting out the sequence !X!
					if(counter1 == (length1 - 1))
					begin 
						en1 <= 1'b0;
						loaded1 <= 1'b0;
						state[1] <= idle;
					end						
				end  
			
			default: state <= {idle, idle};						// go to "safe" state
		endcase
		end
	end
	
	// base counter for toggle 0:		
	always@(posedge clk)
		if(~rst | ~en0)
			counter0 <= 0;
		else if( en0 & toggle)
			counter0 <= counter0 + 1;


	// base counter for toggle 1:		
	always@(posedge clk)
		if(~rst | ~en1)
			counter1 <= 0;
		else if( en1 & ~toggle)
			counter1 <= counter1 + 1;
			
	// --- combinational part: ---	

	always@*
	begin
		we0 = 0;
		we1 = 0;
		data_out = 0;
		data_out = (toggle)? target1[1:0] : target0[1:0];
		full = (buffer_vld && (loaded0 || loaded1)) || (loaded0 && loaded1) || full0 || full1 ;
		if({toggle, state[0]} == {1'b1, idle})
			we0 = buffer_vld && ~loaded0;
		if({toggle, state[1]} == {1'b0, idle}) 
			we1 = buffer_vld && ~loaded1;
	end
	

	
endmodule
