`timescale 1ns/100ps
module I2C_TB ();

//Parameters
parameter BYTES_SEND_LOG=2;                                 //Dictates the maximum number of bytes to be sent (2: 3 byets, 4: 15 bytes...)
parameter BYTES_RECEIVE_LOG=2;                              //Dictates maximum number of bytes to be received (2: 3 byets, 4: 15 bytes...)
parameter BITS_SEND_MAX = (2**BYTES_SEND_LOG-1)<<3;         //Calculation of maimum number of bits to be sent


logic clk;                                                  //For simplicity both controller and target clocks are 50MHz
logic rst;                                                  //Active high logic

logic start_1;                                              //Initial communication by controller 1
logic [BITS_SEND_MAX-1:0] data_send_1;                      //Data to be sent from controller 1
logic [BYTES_SEND_LOG-1:0] num_bytes_send_1;                //Number of bytes to be sent from controller 1
logic [BYTES_RECEIVE_LOG-1:0] num_bytes_receive_1;          //Number of bytes to be recevied in controller 1
logic [7:0] addr_target_1;                                  //Target address for controller 1

logic start_2;                                              //Initial communication by controller 2
logic [BITS_SEND_MAX-1:0] data_send_2;                      //Data to be sent from controller 2
logic [BYTES_SEND_LOG-1:0] num_bytes_send_2;                //Number of bytes to be sent from controller 2
logic [BYTES_RECEIVE_LOG-1:0] num_bytes_receive_2;          //Number of bytes to be recevied in controller 2
logic [7:0] addr_target_2;                                  //Target address for controller 2

logic start_3;                                              //Initial communication by controller 3
logic [BITS_SEND_MAX-1:0] data_send_3;                      //Data to be sent from controller 3
logic [BYTES_SEND_LOG-1:0] num_bytes_send_3;                //Number of bytes to be sent from controller 3
logic [BYTES_RECEIVE_LOG-1:0] num_bytes_receive_3;          //Number of bytes to be recevied in controller 3
logic [7:0] addr_target_3;                                  //Target address for controller 3

I2C s1(
        .rst(rst),
        .clk(clk),
        .start_1(start_1),
        .data_send_1(data_send_1),
        .num_bytes_send_1(num_bytes_send_1),
        .num_bytes_receive_1(num_bytes_receive_1),
        .addr_target_1(addr_target_1),
        .start_2(start_2),
        .data_send_2(data_send_2),
        .num_bytes_send_2(num_bytes_send_2),
        .num_bytes_receive_2(num_bytes_receive_2),	
        .addr_target_2(addr_target_2),
        .start_3(start_3),
        .data_send_3(data_send_3),
        .num_bytes_send_3(num_bytes_send_3),
        .num_bytes_receive_3(num_bytes_receive_3),	
        .addr_target_3(addr_target_3)
);

initial 
begin
  rst<=1'b0;
  start_1<=1'b0;
  start_2<=1'b0;
  start_3<=1'b0;
  clk<=1'b0;

  num_bytes_send_1<=2;
  num_bytes_receive_1<=2;
  data_send_1<=100;

  num_bytes_send_2<=2;
  num_bytes_receive_2<=2;
  data_send_2<=199;

  num_bytes_send_3<=2;
  num_bytes_receive_3<=2;
  data_send_3<=88;

  #1000
  rst<=1'b1;
  //Test 1 - Communication between controller 1 and target 1. Write data from controller to target (3 bytes are written)
  #50000
  start_1<=1'b1;
  addr_target_1<=8'b10001110;
  num_bytes_send_1<=3;
  data_send_1<=24'b110010101111000110101111;		
  #500
  start_1<=1'b0;
  //Test 2 - Communication between controller 2 and target 2. Write data from controller to target (2 bytes are written)
  @(negedge s1.m1.busy)
  #1000
  start_2<=1'b1;	
  addr_target_2<=8'b10011110;
  num_bytes_send_2<=2;
  data_send_2<=24'b0011010111001111;
  #500
  start_2<=1'b0;	
  //Test 3 - Communication between controller 3 and an unkown target (address mismatch - terminated after the acknoledgement bit)
  @(negedge s1.m1.busy)
  #1000
  start_3<=1'b1;
  addr_target_3<=8'b11111101;
  #500
  start_3<=1'b0;
  //Test 4 - Communication between controller 1 and target 2. Read data from target to controller (2 bytes are read)
  @(negedge s1.m1.busy)	
  #5000
  start_1<=1'b1;
  addr_target_1<=8'b10011111;
  num_bytes_receive_1<=2;
  #500
  start_1<=1'b0;
  //Test 5 - Communication between controller 1 and target 1. Read data from target to controller (1 byte is read)
  @(negedge s1.m1.busy)	
  #5000
  start_1<=1'b1;
  addr_target_1<=8'b10001111;
  num_bytes_receive_1<=1;
  #500
  start_1<=1'b0;	
  //Test 6 - Clock synchronization and arbitration verification 
  @(negedge s1.m1.busy)
  #5000
  start_1<=1'b1;
  addr_target_1<=8'b10001110;
  data_send_1<=24'b110011001111000011111100;
  num_bytes_send_1<=3;
  #400
  start_2<=1'b1;	
  addr_target_2<=8'd10011110;
  num_bytes_send_2<=2;
  data_send_2<=24'b0011010111001111;
  #500
  start_1<=1'b0;
  start_2<=1'b0;
end

always				
begin
  #20
  clk=~clk;
end


endmodule


