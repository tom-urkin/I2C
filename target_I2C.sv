//I2C Target - Standard I2C protocol (fSCL up to 100kHz)

module target_I2C(rst,clk,data_send,SDA_bidir,SCL_bidir,data_received);

//Parameter declarations
localparam IDLE=0;                                      //IDLE state
localparam BIT_CYCLE_LOW_ADDR=1;                        //SCL LOW period for the address RX
localparam BIT_CYCLE_HIGH_ADDR=2;                       //SCL HIGH period for the address RX
localparam BIT_CYCLE_LOW_ADDR_ACK=3;                    //SCL LOW period for the ack TX
localparam BIT_CYCLE_HIGH_ADDR_ACK=4;                   //SCL HIGH period for the ack TX
localparam CLOCK_STRETCHING = 5;                        //Clock strecthing (byte level clock streching option)
localparam BIT_CYCLE_LOW_DATA=6;                        //LOW period for data TX/RX
localparam BIT_CYCLE_HIGH_DATA=7;                       //HIGH period for data TX/RX
localparam BIT_CYCLE_LOW_DATA_ACK=8;                    //LOW period for ack bit TX/RX
localparam BIT_CYCLE_HIGH_DATA_ACK=9;                   //HIGH period for ack bit RX/TX
localparam HALT=10;                                     //HALT state
//Timing parameters
parameter THD_STA=225;                                  //Hold time for START condition. 4.5usec at 50MHZ clock (from spec: minimum of 4us)
parameter SDA_UPDATE=50;                                //Target SDA update instance after positive edge of SCL
parameter TSU_DAT=100;                                  //Data setup time. 2us at 50MHz clock (from spec: minimum of 250ns)
parameter TSU_STO=225;                                  //Set-up time for STOP condition 4.5us at 50MHz (from spec: minimum of 4us)
parameter THIGH_SAMPLE=50;                              //Sampling instance of the SDA line after positive edge of SCL. 1us at 50MHz clock

//Application parameters
parameter BYTES_SEND = 2;                               //Number of bytes to be sent (target-->controller)
parameter BITS_SEND=BYTES_SEND<<3;                      //Calculation of number of bit to be sent
parameter BYTES_RECEIVE=2;                              //Number of bytes to be received (controller-->target)
parameter BITS_RECEIVE=BYTES_RECEIVE<<3;                //Calculation of number of bits to be received
parameter ADDR_TARGET=7'b0000111;                       //Target address
parameter STRETCH = 1000;                               //Number of clock cycles for clock-stretching after each address\data byte

//Input Deceleration
input logic rst;                                        //Active high logic
input logic clk;                                        //target's internal clock (50MHz)
input logic [BITS_SEND-1:0] data_send;                  //Data to be sent to the controller (R/W='0')

//Output deleration
output logic [BITS_RECEIVE-1:0] data_received;          //Data received from the controller (R/W='1')

//Bidirectional signals
inout SDA_bidir;                                        //Serial data
inout SCL_bidir;                                        //Serial clock

//Internal logic signals decelerations
logic SCL_tx;                                           //Tri-state logic - SCL output signal
logic SCL_rx;                                           //Tri-state logic - SCL input signal
logic SDA_tx;                                           //Tri-state logic - SDA output signal
logic SDA_rx;                                           //Tri-state logic - SDA input signal

logic [1:0] busy_state;                                 //Calculation of the bus status - FSM states
logic [1:0] next_busy_state;                            //Calculation of the bus status - FSM states
logic busy;                                             //Bus state (logic high if 'busy')

logic [4:0] state;                                      //Main FSM current state
logic [4:0] next_state;                                 //Main FSM next state

logic [9:0] count_low;                                  //Counts the Low period of the SCL signal
logic [9:0] count_high;                                 //Counts the High period of the SCL signal

logic [7:0] addr_received;                              //The first 8-bit frame sent by the controller
logic [BITS_SEND-1:0] data_send_sampled;                //Sampled 'data_send'

logic [3:0] count_addr;                                 //counts until 8 
logic [3:0] count_data;                                 //counts until 8
logic [9:0] count_stretch;                              //Maximum clock strecth period of 255 clock cycles (can also be declared as parameter if needed)
logic [BYTES_SEND-1:0] count_bytes_send;                //Counts the number of sent bytes (multiple bytes can be sent in a single iteration)
logic [BYTES_RECEIVE-1:0] count_bytes_received;         //Counts the number of received bytes (multiple bytes can ne received in a single iteration)

logic rw;                                               //The LSB of the address frame ('0' for TX and '1' for RX)
logic ack;                                              //Acknoledgement bit

//HDL code

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

//FSM next state logic
always @(*)
case (state)
//During termination sequence carried by the controller the 'busy' signal is still high - initiate iteration only if the 'bytes' counters equal zero
IDLE: next_state= busy&&(count_bytes_received=='0)&&(count_bytes_send=='0) ? BIT_CYCLE_LOW_ADDR : IDLE; //TRY WITHOUT THIS LINE

//Receiving address frame
BIT_CYCLE_LOW_ADDR: next_state = (SCL_rx==1'b0) ? BIT_CYCLE_LOW_ADDR : BIT_CYCLE_HIGH_ADDR;

BIT_CYCLE_HIGH_ADDR: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_ADDR : (count_addr<4'd8) ? BIT_CYCLE_LOW_ADDR : BIT_CYCLE_LOW_ADDR_ACK; 

//Respond with ACK bit if received address matches the target's address
BIT_CYCLE_LOW_ADDR_ACK: next_state = (addr_received[7:1]!=ADDR_TARGET) ? HALT : (SCL_rx==1'b0) ? BIT_CYCLE_LOW_ADDR_ACK : BIT_CYCLE_HIGH_ADDR_ACK;

BIT_CYCLE_HIGH_ADDR_ACK: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_ADDR_ACK : CLOCK_STRETCHING;		

//Clock strecthing (only for receiving data - remove the ~rw condition to implement for both TX and RX)
CLOCK_STRETCHING : next_state = (count_stretch<STRETCH)&&(~rw) ? CLOCK_STRETCHING: BIT_CYCLE_LOW_DATA;

//Sent or received data frame
BIT_CYCLE_LOW_DATA: next_state = (SCL_rx==1'b0) ? BIT_CYCLE_LOW_DATA : BIT_CYCLE_HIGH_DATA;

BIT_CYCLE_HIGH_DATA: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_DATA : (count_data<4'd8) ? BIT_CYCLE_LOW_DATA : BIT_CYCLE_LOW_DATA_ACK;		

//ACK/NACK bit
BIT_CYCLE_LOW_DATA_ACK: next_state = (SCL_rx==1'b0) ? BIT_CYCLE_LOW_DATA_ACK : BIT_CYCLE_HIGH_DATA_ACK;

BIT_CYCLE_HIGH_DATA_ACK: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_DATA_ACK : (ack==1'b1)&&(rw==1'b1) ? HALT :((count_bytes_received!=BYTES_RECEIVE)&&(rw==1'b0)) ? CLOCK_STRETCHING : ((count_bytes_send!=BYTES_SEND)&&(rw==1'b1)) ? CLOCK_STRETCHING : IDLE;

//HALT state - enter if the received address does not match
HALT: next_state = (~busy) ? IDLE : HALT;

default: next_state=IDLE;

endcase

//Calculate FSM next state
always @(posedge clk or negedge rst)
  if (!rst)
    state<=IDLE;
  else
  state<=next_state;

//Main I2C protocol logic
always @(posedge clk or negedge rst)
  if (!rst) begin
    count_low<='0;
    count_high<='0;
    count_addr<='0;
    count_data<='0;
    count_bytes_send<='0;
    count_bytes_received<='0;
    count_stretch<='0;
	 data_received<='0;
    SCL_tx<=1'b1;
    SDA_tx<=1'b1;
  end

  //Idle state
  else if (state==IDLE) begin
    if (busy==1'b0) begin
    count_low<='0;
    count_high<='0;
    count_addr<='0;
    count_data<='0;
    count_bytes_send<='0;
    count_bytes_received<='0;
    count_stretch<='0;
	 data_received<='0;
    SCL_tx<=1'b1;
    SDA_tx<=1'b1;
  end
  else begin                                      //Do no interfere with the termination sequence carried by the controller
    SDA_tx<=1'b1;	
    SCL_tx<=1'b1;
  end
  end

  //Receive 7-bit address + R/W bit
  else if (state==BIT_CYCLE_LOW_ADDR)
    count_high<='0;                               //Reset High period counter

  else if (state==BIT_CYCLE_HIGH_ADDR) begin
    data_send_sampled<=data_send;                 //Data to be sent if the controller asks for data from the target
    count_high<=count_high+$bits(count_low)'(1);

  if (count_high==THIGH_SAMPLE) begin
    addr_received<={addr_received[6:0],SDA_rx};
    count_addr<=count_addr+$bits(count_addr)'(1);
  end
  count_low<='0;                                  //Reset LOW period counter
  end

  //Send acknoledgement bit for the address frame if the address matches the target's address
  else if (state==BIT_CYCLE_LOW_ADDR_ACK) begin
    count_low<=count_low+$bits(count_low)'(1);
    if ((count_low==SDA_UPDATE)&&(addr_received[7:1]==ADDR_TARGET)) 
      SDA_tx<=1'b0;
  count_high<='0;                                //Reset HIGH period counter
  end

  else if (state==BIT_CYCLE_HIGH_ADDR_ACK)       //During this period the controller sampled the ack bit
    count_low<='0;

  else if (state==CLOCK_STRETCHING) begin
    SCL_tx<=1'b0;
    SDA_tx<=1'b1;
    count_stretch<=count_stretch+$bits(count_stretch)'(1);
  end

  //Send or receive an 8-bit data frame
  else if (state==BIT_CYCLE_LOW_DATA) begin
    count_low<=count_low+$bits(count_low)'(1);
    SCL_tx<=1'b1;                                //Give back control of the SCL line to the controller after clock stretching period

  if ((count_low==SDA_UPDATE)&&(rw==1'b1)) begin
    SDA_tx<=data_send_sampled[BITS_SEND-1];
    data_send_sampled<=data_send_sampled<<1;			
    count_data<=count_data+$bits(count_data)'(1);
  end
  else if (rw==1'b0)
    SDA_tx<=1'b1;
  count_high<='0;                                //Reset HIGH period counter
  end

  else if (state==BIT_CYCLE_HIGH_DATA) begin
    count_high<=count_high+$bits(count_low)'(1);

  if ((count_high==THIGH_SAMPLE)&&(rw==1'b0)) begin
    data_received<={data_received[BITS_RECEIVE-2:0],SDA_rx};
    count_data<=count_data+$bits(count_data)'(1);
  end
  count_low<='0;                                 //Reset LOW period counter
  end

  //Send or receive acknoledgement bit for the data frame
  else if (state==BIT_CYCLE_LOW_DATA_ACK) begin
    count_low<=count_low+$bits(count_low)'(1);

  if ((count_low<SDA_UPDATE) && (rw==1'b0)) 
    SDA_tx<=1'b1;
  if ((count_low==SDA_UPDATE)&&(rw==1'b0)) begin
    count_bytes_received<=count_bytes_received+$bits(count_bytes_received)'(1);
    SDA_tx<=1'b0;                               //send acknoledgement bit
  end
    count_high<='0;                             //Reset HIGH period counter
    count_stretch<='0;                          //Reset clock strectching counter
  end

  else if (state==BIT_CYCLE_HIGH_DATA_ACK) begin
    count_high<=count_high+$bits(count_low)'(1);
    count_low<='0;
    if ((count_high==THIGH_SAMPLE)&&(rw==1'b1)) begin
      ack<=SDA_rx;                               //Sample acknoledge bit sent by the controller
      count_bytes_send<=count_bytes_send+$bits(count_bytes_send)'(1);
      count_data<='0;                            //Reset the bit counter (indicates a byte has been sent/received)
    end
    else if (count_high==THIGH_SAMPLE) begin
      count_data<='0;                            //Reset the bit counter (indicates a byte has been sent/received)
      count_bytes_send<=count_bytes_send+$bits(count_bytes_send)'(1);
    end

  else if (state==HALT) begin
    SDA_tx=1'b1;
    SCL_tx=1'b1;
  end

end

assign rw = addr_received[0];
//Assign SDA_tx and SCL_tx values
assign SDA_bidir = SDA_tx ? 1'bz : 1'b0;
assign SDA_rx = SDA_bidir;

assign SCL_bidir = SCL_tx ? 1'bz : 1'b0;
assign SCL_rx=SCL_bidir; 

endmodule