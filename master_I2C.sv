//I2C Master - Standard I2C protocol (fSCL up to 100kHz)

module master_I2C(rst,clk,start,addr_target,data_send,num_bytes_send,num_bytes_receive,SDA_bidir,SCL_bidir,data_received);

//Parameter declarations
//FSM states
localparam IDLE=0;                                  //IDLE state
localparam INITIATE=1;                              //From initiation unitl THD_STA
localparam BIT_CYCLE_LOW_ADDR=2;                    //SCL LOW period for the address TX
localparam BIT_CYCLE_HIGH_ADDR=3;                   //SCL HIGH period for the address TX
localparam BIT_CYCLE_LOW_ADDR_ACK=4;                //SCL LOW period for the ack RX
localparam BIT_CYCLE_HIGH_ADDR_ACK=5;               //SCL HIGH period for the ack RX
localparam BIT_CYCLE_LOW_DATA=6;                    //SCL LOW period for data TX/RX
localparam BIT_CYCLE_HIGH_DATA=7;                   //SCL HIGH period for data TX/RX
localparam BIT_CYCLE_LOW_DATA_ACK=8;                //SCL LOW period for ack bit TX/RX
localparam BIT_CYCLE_HIGH_DATA_ACK=9;               //SCL HIGH period for ack bit RX/TX
localparam TERMINATE_LOW=10;                        //Termination sequence SCL LOW period
localparam TERMINATE_HIGH=11;                       //Termination sequece SCL HIGH period
localparam HALT=12;                                 //HALT state
//Timing parameters
parameter THD_STA=225;                              //Hold time (repeated) START condition. 4.5usec at 50MHZ clock (from spec: minimum of 4us)
parameter TLOW=250;                                 //Low period of the SCL clock. 5usec at 50MHz clock (from spec: minimum of 4.7us)
parameter THIGH=225;                                //High period of the SCL clock. 4.5usec at 50MHZ clock (from spec: minimum of 4us)
parameter TSU_DAT=100;                              //Data setup time. 2us at 50MHz clock (from spec: minimum of 250ns)
parameter TSU_STO=225;                              //Set-up time for STOP condition 4.5us at 50MHz (from spec: minimum of 4us)
parameter THIGH_SAMPLE=50;                          //Sampling instance of the SDA line after positive edge of SCL. 1us at 50MHz clock
//Application parameters 
parameter BYTES_SEND_LOG = 2;                                  //Dictates the maximum number of bytes to be sent (2: 3 byets, 4: 15 bytes...)
parameter BYTES_RECEIVE_LOG = 2;                               //Dictates maximum number of bytes to be received (2: 3 byets, 4: 15 bytes...)
localparam BITS_SEND_MAX=(2**BYTES_SEND_LOG-1)<<3;             //Calculation of maimum number of bit to be sent
localparam BITS_RECEIVE_MAX=(2**BYTES_RECEIVE_LOG-1)<<3;       //Calculation of maximum number of bits to be received
//Input Decelerations
input logic rst;                                         //Active high logic
input logic clk;                                         //Controller's internal clock (50MHz)
input logic start;                                       //When 'start' rises to logic high a read\write operation of a single byte is initiated
input logic [7:0] addr_target;                           //7-bit target address + R/W bit
input logic [BITS_SEND_MAX-1:0] data_send;               //Data to be sent from controller. Data is zero-padded in accordance with the maximum number of bits to be sent
input logic [BYTES_SEND_LOG-1:0] num_bytes_send;         //Number of bytes to be sent from controller-->target (zero-padded as well)
input logic [BYTES_RECEIVE_LOG-1:0] num_bytes_receive;   //Number of bytes to be received from target-->controller (zero-padded as well)
//Output delerations
output logic [BITS_RECEIVE_MAX-1:0] data_received;       //Data received from the target (width dictated by the maximal number of data frames)

//Bidirectional signals
inout SDA_bidir;                                         //SDA line
inout SCL_bidir;                                         //SCL line

//Internal logic signals decelerations
//
logic [BYTES_SEND_LOG+2:0] bits_send;                      //Number of bits to be sent (controller-->target)

logic SCL_tx;                                              //Tri-state logic - SCL output signal
logic SCL_rx;                                              //Tri-state logic - SCL input signal
logic SDA_tx;                                              //Tri-state logic - SDA output signal
logic SDA_rx;                                              //Tri-state logic - SDA input signal

logic [1:0] busy_state;                                    //Calculation of the bus status - FSM states
logic [1:0] next_busy_state;                               //Calculation of the bus status - FSM states
logic busy;                                                //Bus state (logic high if 'busy')

logic initial_comm;                                        //Rises to logic high for one clock period after positive edge of 'start'
logic start_delayed_1;                                     //Internal signal used in the generation of initial_comm
logic start_delayed_2;                                     //Internal signal used in the generation of initial_comm

logic [4:0] state;                                         //Main FSM current state
logic [4:0] next_state;                                    //Main FSM next state

logic [9:0] count_initiate;                                //Counts the initial time frame upon activation (THD_STA)
logic [9:0] count_low;                                     //Counts the Low period of the SCL signal
logic [9:0] count_high;                                    //Counts the High period of the SCL signal

logic [7:0] addr_target_sampled;                           //Sampled 'addr_target'
logic [BITS_SEND_MAX-1:0] data_send_sampled;               //Sampled 'data_send'

logic [3:0] count_addr;                                 //counts until 8 (7-bit address+1 R/W bit) 
logic [3:0] count_data;                                 //counts until 8 (8-bit word)

logic [BYTES_SEND_LOG-1:0] count_bytes_send;            //Counts the number of sent bytes (multiple bytes can be sent in a single iteration)
logic [BYTES_RECEIVE_LOG-1:0] count_bytes_received;     //Counts the number of received bytes (multiple bytes can ne received in a single iteration)

logic rw;                                                  //The LSB of the address frame ('0' for TX and '1' for RX)
logic ack;                                                 //Acknoledgement bit

//HDL code

//Creating a single-cycle pulse when communication is requested ('initial_comm')	
always @(posedge clk or negedge rst)
  if (!rst) begin
    start_delayed_1<=1'b0;
    start_delayed_2<=1'b0;
  end	
  else begin
    start_delayed_1<=start;
    start_delayed_2<=start_delayed_1;
    initial_comm<=start_delayed_1&~start_delayed_2;	
  end

//Bus state detection logic (i.e. free/busy)
always @(*)
  case (busy_state)
    2'b00: next_busy_state = ((SCL_rx==1'b1)&&(SDA_rx==1'b0)) ? 2'b01 : 2'b00;
    2'b01: next_busy_state = ((SCL_rx==1'b0)&&(SDA_rx==1'b0)) ? 2'b10 : ((SCL_rx==1'b1)&&(SDA_rx==1'b1)) ? 2'b00 : 2'b01;	
    2'b10: next_busy_state = ((SCL_rx==1'b1)&&(SDA_rx==1'b0)) ? 2'b11 : 2'b10;
    2'b11: next_busy_state = ((SCL_rx==1'b1)&&(SDA_rx==1'b1)) ? 2'b00 : (( SCL_rx==1'b1)&&(SDA_rx==1'b0)) ? 2'b11 : 2'b10;
  endcase

always @(posedge clk or negedge rst)
  if (!rst)
    busy_state<=2'b00;
  else
    busy_state<=next_busy_state;

assign busy = ((busy_state==2'b10)||(busy_state==2'b11));

//SCL signal generation
always @(*)
case (state)
IDLE: next_state = (initial_comm&~busy) ? INITIATE : IDLE;

INITIATE: next_state = (count_initiate<THD_STA) ? INITIATE : BIT_CYCLE_LOW_ADDR;

//Generate SCL pulses for the address and R/W bit
//Clock synchronization is implemented via the second condition - the 'LOW' period is dictated by the controller with the longest 'TLOW' value
//The 'HIGH' period is dictated by the controller with the hsortest 'THIGH' vlaue
//Arbitration is carried in this section via the (SDA_tx!=SDA_rx) condition during the HIGH period of SCL
BIT_CYCLE_LOW_ADDR: next_state = (count_low<TLOW) ? BIT_CYCLE_LOW_ADDR : (SCL_rx==1'b0) ? BIT_CYCLE_LOW_ADDR: BIT_CYCLE_HIGH_ADDR;

BIT_CYCLE_HIGH_ADDR: next_state = (SDA_tx!=SDA_rx) ? HALT :(count_high<THIGH)&&(SCL_rx==1'b1) ? BIT_CYCLE_HIGH_ADDR : (count_addr<4'd8) ? BIT_CYCLE_LOW_ADDR : BIT_CYCLE_LOW_ADDR_ACK; 

//Generate SCL pulse for the ACK/NACK bit
BIT_CYCLE_LOW_ADDR_ACK: next_state = (count_low<TLOW) ? BIT_CYCLE_LOW_ADDR_ACK : (SCL_rx==1'b0) ? BIT_CYCLE_LOW_ADDR_ACK : BIT_CYCLE_HIGH_ADDR_ACK;

BIT_CYCLE_HIGH_ADDR_ACK: next_state = (count_high<THIGH)&&(SCL_rx==1'b1) ? BIT_CYCLE_HIGH_ADDR_ACK : BIT_CYCLE_LOW_DATA;		

//Generate SCL pulses for the sent/received data. If acknoledge bit is bot received - terminate communication
BIT_CYCLE_LOW_DATA: next_state = (ack==1'b1) ? TERMINATE_LOW : (count_low<TLOW) ? BIT_CYCLE_LOW_DATA : (SCL_rx==1'b0) ? BIT_CYCLE_LOW_DATA : BIT_CYCLE_HIGH_DATA;

BIT_CYCLE_HIGH_DATA: next_state = (count_high<THIGH)&&(SCL_rx==1'b1) ? BIT_CYCLE_HIGH_DATA : (count_data<4'd8) ? BIT_CYCLE_LOW_DATA : BIT_CYCLE_LOW_DATA_ACK;		

//Generate SCL pulse for the ACK/NACK bit
BIT_CYCLE_LOW_DATA_ACK: next_state = (count_low<TLOW) ? BIT_CYCLE_LOW_DATA_ACK : (SCL_rx==1'b0) ? BIT_CYCLE_LOW_DATA_ACK : BIT_CYCLE_HIGH_DATA_ACK;

BIT_CYCLE_HIGH_DATA_ACK: next_state = (count_high<THIGH)&&(SCL_rx==1'b1) ? BIT_CYCLE_HIGH_DATA_ACK : ((rw==1'b0)&&(count_bytes_send==num_bytes_send))||((rw==1'b1)&&(count_bytes_received==num_bytes_receive)) ? TERMINATE_LOW : BIT_CYCLE_LOW_DATA;		

//Generate 'stop' conditions
TERMINATE_LOW: next_state = (count_low<TLOW) ? TERMINATE_LOW : (SCL_rx==1'b0) ? TERMINATE_LOW :TERMINATE_HIGH;

TERMINATE_HIGH: next_state = (count_high<THIGH)&&(SCL_rx==1'b1) ? TERMINATE_HIGH : IDLE;

//HALT state - controller enters HALT state if it loses arbitration and waits until communication is terminated by the winning controller
HALT: next_state = (~busy) ? IDLE : HALT;

default: next_state=IDLE;

endcase

//Calculate FSM next state
always @(posedge clk or negedge rst)
  if (!rst) begin
    state<=IDLE;
  end	
  else begin
    state<=next_state;
  end

//Main I2C protocol logic
always @(posedge clk or negedge rst)
  if (!rst) begin
    count_initiate<='0;
    count_low<='0;
    count_high<='0;
    count_addr<='0;
    count_data<='0;
    count_bytes_send<='0;
    count_bytes_received<='0;
	 data_received<='0;
    rw<='0;
    SCL_tx<=1'b1;
    SDA_tx<=1'b1;
  end
  //Idle state
  else if (state==IDLE) begin
    count_initiate<='0;
    count_low<='0;
    count_high<='0;
    count_addr<='0;
    count_data<='0;
    count_bytes_send<='0;
    count_bytes_received<='0;
	 data_received<='0;
    rw<='0;
    SCL_tx<=1'b1;
    SDA_tx<=1'b1;
  end
  //Initiate communication
  else if (state==INITIATE) begin
    count_initiate<=count_initiate+$bits(count_initiate)'(1);
    SDA_tx<=1'b0;
    SCL_tx<=1'b1;
    addr_target_sampled<=addr_target;              //Sample the target address
    data_send_sampled<=data_send;                  //In case of transmission sample data to be sent
    count_bytes_send<='0;				
	 count_bytes_received<='0;			 
    rw<=addr_target[0];
  end
  //Send 7-bit address + R/W bit
  else if (state==BIT_CYCLE_LOW_ADDR) begin
    if (count_low<TLOW) begin
      SCL_tx<=1'b0;
      count_low<=count_low+$bits(count_low)'(1);     //Start counting the TLOW period only   
    end
    else
      SCL_tx<=1'b1;                    //In case of synchronization - allow other masters with longer TLOW to control the SCL line
    
    if (count_low==(TLOW-TSU_DAT)) begin
      SDA_tx<=addr_target_sampled[7];
      addr_target_sampled<=addr_target_sampled<<1;	
      count_addr<=count_addr+$bits(count_addr)'(1);
    end
    count_high<='0;                   //Reset HIGH period counter 
  end

  else if (state==BIT_CYCLE_HIGH_ADDR) begin
    count_high<=count_high+$bits(count_high)'(1);
    SCL_tx<=1'b1;
    count_low<='0;                  //Reset LOW period counter
  end

  //Receive acknoledgement bit for the address frame
  else if (state==BIT_CYCLE_LOW_ADDR_ACK) begin
    if (count_low<TLOW)	begin 
	  count_low<=count_low+$bits(count_low)'(1);
      SCL_tx<=1'b0;
    end
      else SCL_tx<=1'b1;

    SDA_tx<=1'b1;                   //set to logic high to enable read of the SDA line
    count_high<='0;                 //Reset HIGH period counter
  end

  else if (state==BIT_CYCLE_HIGH_ADDR_ACK) begin
    count_high<=count_high+$bits(count_high)'(1);
    if (count_high==THIGH_SAMPLE) 
      ack<=SDA_rx;
    SCL_tx<=1'b1;
    count_low<='0;                 //Reset LOW period counter
  end	

  //Send or receive an 8-bit data frame
  else if (state==BIT_CYCLE_LOW_DATA) begin
    if (count_low<TLOW) begin
      count_low<=count_low+$bits(count_low)'(1);
      SCL_tx<=1'b0;
      end
    else 
      SCL_tx<=1'b1;
    count_high<='0;

    if ((count_low==TLOW-TSU_DAT)&&(rw==1'b0)) begin      //In case of master TX
      SDA_tx<=data_send_sampled[bits_send-1];
      data_send_sampled<=data_send_sampled<<1;			
      count_data<=count_data+$bits(count_data)'(1);
    end
    else if (rw==1'b1)                                    //In case of target TX
      SDA_tx<=1'b1;

  end

  else if (state==BIT_CYCLE_HIGH_DATA) begin
    count_high<=count_high+$bits(count_high)'(1);
    if ((count_high==THIGH_SAMPLE)&&(rw==1'b1)) begin
      data_received<={data_received[BITS_RECEIVE_MAX-2:0],SDA_rx};
      count_data<=count_data+$bits(count_data)'(1);
    end	
  count_low<='0;
  SCL_tx<=1'b1;
  end

  //Send or receive acknoledgement bit for the data frame
  else if (state==BIT_CYCLE_LOW_DATA_ACK) begin
    if (count_low<TLOW) begin
      count_low<=count_low+$bits(count_low)'(1);
      SCL_tx<=1'b0;
    end
    else 
      SCL_tx<=1'b1;	

  if ((count_low==TLOW-TSU_DAT)&&(rw==1'b1)) begin
	 if (count_bytes_received==num_bytes_receive-$bits(num_bytes_receive)'(1)) begin
      SDA_tx<=1'b1;              //After the last byte return a NACK
      count_bytes_received<=count_bytes_received+$bits(count_bytes_received)'(1);
	 end
	 else begin
      SDA_tx<=1'b0;
      count_bytes_received<=count_bytes_received+$bits(count_bytes_received)'(1);	
    end
  end
  else if (rw==1'b0)
    SDA_tx<=1'b1;

  count_high<='0;               //Reset HIGH period counter
  end

  else if (state==BIT_CYCLE_HIGH_DATA_ACK) begin
    count_high<=count_high+$bits(count_high)'(1);
    if ((count_high==THIGH_SAMPLE)&&(rw==1'b0)) begin
      ack<=SDA_rx;
      count_bytes_send<=count_bytes_send+$bits(count_bytes_send)'(1);
    end
    SCL_tx<=1'b1;
    count_low<='0;             //Reset LOW period counter
    count_data<='0;            //Reset the bit counter (indicates a byte has been sent/received)
  end

  //Terminate communication (free the bus)
  else if (state==TERMINATE_LOW) begin	
    if (count_low<TLOW) begin
      count_low<=count_low+$bits(count_low)'(1);
      SCL_tx<=1'b0;
    end
    else 
      SCL_tx<=1'b1;

    if ((count_low==TLOW-TSU_DAT)&&(1'b1)) begin
      SDA_tx<=1'b0;
    end
    count_high<='0;            //Reset HIGH period counter
  end
  
  else if (state==TERMINATE_HIGH) begin
    count_high<=count_high+$bits(count_high)'(1);
    if ((count_high==TSU_STO)&&(1'b1))
      SDA_tx<=1'b1;
    count_low<='0;            //Reset LOW period counter
    SCL_tx<=1'b1;
  end

  else if (state==HALT) begin
    SDA_tx<=1'b1;
    SCL_tx<=1'b1;
  end

//Calculating the number of bits in each communication interval (send and receive)
assign bits_send = num_bytes_send<<3; 
  
//Assign SDA_tx and SCL_tx values
assign SDA_bidir = SDA_tx ? 1'bz : 1'b0;
assign SDA_rx = SDA_bidir;

assign SCL_bidir = SCL_tx ? 1'bz : 1'b0;
assign SCL_rx=SCL_bidir; 
				   
endmodule