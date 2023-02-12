# I2C Communication Protocol

> SystemVerilog I2C communication protocol  

Implementention in SystemVerilog of __I2C Communication protocol__.  

## Get Started

The source files  are located at the repository root:

- [I2C Controller](./master_I2C.sv)
- [I2C Target](./target_I2C.sv)
- [Multi-Masters Multi-Targets System](./I2C.sv)
- [I2C TB](./I2C_TB.sv)

##
This repository containts a SystemVerilog implementation of I2C controller and target modules designed in accordance with the [I2C-bus specification manual by NXP (Rev. 7.0, October 2021)](https://www.pololu.com/file/0J435/UM10204.pdf)

The two modules are built as FSMs which emcapsulte the periodic structure of the I2C protocol. It is advised to draw a simple flowchart when reading the sourcecode for better undrstanding. Shown below is a simplified version of the controller's flowchart for better understanding:
![Controller_flowchart](./docs/flowchart.jpg) 

Apart from 'vanilla' I2C protocol following features are supported:
1.  Clock stretching
2.	Clock synchronization and arbritration for multi-controller systems

All timing parameters are defined as constants which can be overidden to comply with different target'/controllers' requirement. Please refer to section 6 of the I2C bus specification manual for the definition ofthese timing intervals. 
The open drain configuration is mimicked here by using 'tri1' wire type for the SCL and SDA lines.
## Testbench

The testbench comprises five tests covering key scenarios of multi-controller (3) multi-target (2) I2C systems.

1.	Communication between controller '1' and target '1'. Write data from controller to target (3 data frames).
	Here the data sent from the controller to the peripheral unit is 24-bit long (3 data frames, 110010101111000110101111). 
	The target unit is 'target_1' (addr_1=7'b1000111) which is configured to execute byte-level clock streching.
	
	**Communication between controller '1' and target '1':**
		![tst1_wave](./docs/tst1_wave.jpg)  
		
2.	Communication between controller '2' and target '2'. Write data from controller to target (2 data frames).
	Here the data sent from the controller to the peripheral unit is 16-bit long (2 data frames, 0011010111001111). 
	The target unit is 'target_2' (addr_1=7'b1001111) which is configured to execute byte-level clock streching.
	
	**Communication between controller '2' and target '2':**
		![tst2](./docs/tst2_wave.jpg)  

3.	Communication between controller '3' and an unkown target (address mismatch - terminated after the acknoledgement bit)
	Here the address of the target device (7'b1111110) does not match to any existing devices on the line. 
	
	**Communication between controller '3' and unkown target device:**
		![tst3](./docs/tst3_wave.jpg)  

4.	Communication between controller '1' and target '2'. Read data from target to controller (2 bytes are read)
	Note: Clock strectching is carried only when data is transferred from the controller to the target.
	
	**Communication between controller 3 and unkown target device:**
		![tst4](./docs/tst4_wave.jpg)  
		
5.	Communication between controller '1' and target '1'. Read data from target to controller (1 byte is read)
	Note: Clock strectching is carried only when data is transferred from the controller to the target.
	
	**Communication between controller 3 and unkown target device:**
		![tst5](./docs/tst5_wave.jpg)  

6.	Clock synchronization and arbitration verification
	The two controllers try to control the I2C lines. The timing specifiaction of the two are deliberately different to verify the clock synchronization logic (please see the I2C protocal manual for detailed explanation). Controller '1' is the 'winner' of the arbritration procedure (after the 4th address bit).
	
	**Clock synchronization and arbitration verification: controller '1' wins the arbritration proccess:**
		![tst6](./docs/tst6_wave.jpg)  
		
## Support

I will be happy to answer any questions.  
Approach me here using GitHub Issues or at tom.urkin@gmail.com