#include "soc/rtc_cntl_reg.h"
#include "soc/rtc_io_reg.h"
#include "soc/soc_ulp.h"

/*.bss section (zero-initialized data) */
.bss

sensors_setup:
    .global sensors_setup
    .set  sensors_setup_low_mask, 0
    .set  sensors_setup_high_mask, 4
    .long 0
    .long 0
    
sensors:
    .global sensors
    .set  sensor_off_change_count, 0
    .set  sensor_off_rise_count, 4
    .set  sensor_off_fall_count, 8
    .set  sensor_word_rise_count, 1
    .set  sensor_word_fall_count, 2
    .set  sensor_word_size, 3

    .long 0, 0, 0   //change count, rise count, fall count
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0
    .long 0, 0, 0


sensor_update:      //GPIO update control structure
    .set  sensor_update_low16_prev, 0
    .set  sensor_update_low16, 4
    .set  sensor_update_high16_prev, 8
    .set  sensor_update_high16, 12
    .set  sensor_update_current_prev, 16
    .set  sensor_update_current, 20
    .set  sensor_update_i, 24
    .set  sensor_update_off, 28
    .set  sensor_update_ret, 32
    
    .long 0         //low16_prev:   prev low 16 GPIO states
    .long 0         //low16:        low 16 GPIO states
    .long 0         //high16_prev:  prev high 16 GPIO states
    .long 0         //high16:       high 16 GPIO states
    .long 0         //current_prev: previous bits currently used in update loop (contains low16_prev or high16_prev)
    .long 0         //current:      bits currently used in update loop (contains low16 or high16)
    .long 0         //i:            RTC GPIO index
    .long 0         //off:          RTC GPIO events offset
    .long 0         //ret:          return JUMP address

clk:                //clock control structure 
    .set  clk_off_ticks, 0
    .set  clk_off_ms, 4
    .set  clk_off_s, 8
    .set  clk_off_elapsed, 12    
    .set  idle_threshold, 15    //stop ulp after that many seconds of inactivity

    .long 0   //ticks
    .long 0   //ms
    .long 0   //s
    .long 0   //elapsed
    
/*.text section (code) */
.text
    .global entry
entry:
//--------------------------
//Start by reading the lower 16 bit of the 48bit clock value
//--------------------------
    //set clk to current RTC clock lower 16 bits
    WRITE_RTC_REG(RTC_CNTL_TIME_UPDATE_REG, RTC_CNTL_TIME_UPDATE_S, 1, 1);    //must update register before reading it
    READ_RTC_REG(RTC_CNTL_TIME0_REG, 0, 16);                                  //read register
    AND   R0, R0, 0x3fff                                                      //keep lower 14 bits only
    MOVE  R1, 0
    MOVE  R3, clk   
    ST    R0, R3, clk_off_ticks     //=RTC lower 14 bits
    ST    R1, R3, clk_off_ms        //=0
    ST    R1, R3, clk_off_s         //=0
    ST    R1, R3, clk_off_elapsed   //=0

    MOVE  R3, sensor_update
    READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S, 16)
    ST    R0, R3, sensor_update_low16
    READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 16, 2)
    ST    R0, R3, sensor_update_high16
    
//--------------------------
//main ulp program loop
//--------------------------
loop:

//--------------------------
//Update elapsed time(not precise)
//--------------------------
updateClk:
    WRITE_RTC_REG(RTC_CNTL_TIME_UPDATE_REG, RTC_CNTL_TIME_UPDATE_S, 1, 1);    //must update register before reading it
    READ_RTC_REG(RTC_CNTL_TIME0_REG, 0, 16);                                  //read register
    AND   R1, R0, 0x3fff

    MOVE  R3, clk                 //
    LD    R2, R3, clk_off_ticks   //R3=*clk
    SUB   R0, R1, R2              //NewTime-LastTime
    RSH   R0, R0, 15              //R0 >>= 15
    AND   R0, R0, 1               //R2 &= 1   (keep bit 0, not sure if RSH is rotate or shift)
    MOVE  R3, clk                 
    ST    R1, R3, clk_off_ticks   //update clk_ticks
    JUMPR notWrapped, 0, EQ       //check for overflow
wrapped:
    MOVE  R0, 16383
    SUB   R0, R0, R2              //R0=16383 - OldTime  
    ADD   R0, R0, R1              //R0=Wrap diff+NewTime
    JUMP  storeElapsed
notWrapped:
    SUB   R0, R1, R2              //NewTime-LastTime
  
storeElapsed:
    MOVE  R3, clk                 //R3=&clk_elapsed
    LD    R2, R3, clk_off_elapsed
    ADD   R1, R2, R0              //elapsed += new elapsed

    AND   R0, R0, 0x7             //drift adjust: add lower 3 bits as extra elapsed
    ADD   R1, R1, R0              //add drift adjustment

    AND   R2, R1, 0xff00          //extract approx milliseconds (1ms = 0x2000, but it was shifted by 1 so 1ms=0x1000)
    AND   R1, R1, 0x00ff          //keep ms fractions
    ST    R1, R3, clk_off_elapsed //write clk_elapsed

    RSH   R2, R2, 8               //div by 256
    LD    R1, R3, clk_off_ms      //load clk_ms
    ADD   R1, R2, R1              //old += new elaped ms

    AND   R0, R1, 0xfc00          //mask thousands of ms (seconds)
    AND   R1, R1, 0x03ff          
    ST    R1, R3, clk_off_ms      //write clk_ms

    RSH   R0, R0, 10              //div by 1024, close enough to 1000 for our current needs
    LD    R1, R3, clk_off_s   
    ADD   R1, R1, R0
    ST    R1, R3, clk_off_s       //store new elapsed seconds

//--------------------------
//read a set of predefined GPIOs
//--------------------------
readLowGPIOS:
    MOVE  R3, sensor_update
    LD    R1, R3, sensor_update_low16
    ST    R1, R3, sensor_update_low16_prev
    READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S, 16)
    ST    R0, R3, sensor_update_low16   //sensor_update.low16 = RTC_GPIO_IN_REG
readHighGPIOS:
    LD    R1, R3, sensor_update_high16
    ST    R1, R3, sensor_update_high16_prev
    READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 16, 2)
    ST    R0, R3, sensor_update_high16   //sensor_update.low16 = RTC_GPIO_IN_REG

updateLowGPIOS_Init:
    MOVE  R0, 0
    ST    R0, R3, sensor_update_i       //sensor_update.i = RTC GPIO index 0
    ST    R0, R3, sensor_update_off     //sensor_update.off = 0
    MOVE  R0, updateLowGPIOS_Loop
    ST    R0, R3, sensor_update_ret     //sensor_update.ret = &readRTC_GPIO_0End
    LD    R0, R3, sensor_update_low16_prev
    ST    R0, R3, sensor_update_current_prev
    LD    R0, R3, sensor_update_low16
    ST    R0, R3, sensor_update_current
    JUMP  updateGPIO

updateLowGPIOS_Loop:
    MOVE  R3, sensor_update
    LD    R0, R3, sensor_update_i
    JUMPR updateLowGPIOS_End, 15, EQ

    ADD   R0, R0, 1
    ST    R0, R3, sensor_update_i       //sensor_update.i = RTC GPIO index 0
    LD    R0, R3, sensor_update_off
    ADD   R0, R0, sensor_word_size
    ST    R0, R3, sensor_update_off     //sensor_update.off = 0
    JUMP  updateGPIO
updateLowGPIOS_End:

updateHighGPIOS_Init:
    MOVE  R0, 0
    ST    R0, R3, sensor_update_i       //sensor_update.i = RTC GPIO index 0
    LD    R0, R3, sensor_update_off
    ADD   R0, R0, sensor_word_size
    ST    R0, R3, sensor_update_off     //sensor_update.off = 0
    MOVE  R0, updateHighGPIOS_Loop
    ST    R0, R3, sensor_update_ret     //sensor_update.ret = &updateRTC_GPIO_0End
    LD    R0, R3, sensor_update_high16_prev
    ST    R0, R3, sensor_update_current_prev
    LD    R0, R3, sensor_update_high16
    ST    R0, R3, sensor_update_current
    JUMP  updateGPIO

updateHighGPIOS_Loop:
    MOVE  R3, sensor_update
    LD    R0, R3, sensor_update_i
    JUMPR updateGPIOSEnd, 1, EQ

    ADD   R0, R0, 1
    ST    R0, R3, sensor_update_i       //sensor_update.i = RTC GPIO index 0
    LD    R0, R3, sensor_update_off
    ADD   R0, R0, sensor_word_size
    ST    R0, R3, sensor_update_off     //sensor_update.off = 0
    JUMP  updateGPIO
    
updateGPIO:
    MOVE  R3, sensor_update
    LD    R0, R3, sensor_update_current
    LD    R1, R3, sensor_update_i
    
    RSH   R0, R0, R1
    AND   R2, R0, 1                   //R2 = new sensor state
    
    LD    R0, R3, sensor_update_current_prev
    RSH   R0, R0, R1
    AND   R0, R0, 1                   //R0 = old sensor state
    
    SUB   R0, R2, R0                  //sub to check if old state == new state 
    JUMPR updateGPIOEnd, 0, EQ          //jump to updateGPIOEnd if sensor has NOT changed(same value)

    WAIT  60250                       //wait ~7.5ms (8K cycles == 1ms)
    WAIT  60250                       //wait ~7.5ms
    WAIT  60250                       //wait ~7.5ms
    WAIT  60250                       //wait ~7.5ms

    LD    R1, R3, sensor_update_off
    MOVE  R3, sensors
    ADD   R3, R3, R1                  //R3 = &sensors[i]

    LD    R0, R3, sensor_off_change_count
    ADD   R0, R0, 1
    ST    R0, R3, sensor_off_change_count //increase sensor change counts
    
    MOVE  R0, R2
    JUMPR GPIO_Fall, 0, EQ          //jump to GPIO_Fall if sensor state is 0

GPIO_Rise:
    ADD   R3, R3, sensor_word_rise_count
    jump  GPIO_Increment
GPIO_Fall:
    ADD   R3, R3, sensor_word_fall_count
GPIO_Increment:
    LD    R0, R3, 0
    ADD   R0, R0, 1
    ST    R0, R3, 0

    MOVE  R3, clk
    MOVE  R0, 0
    ST    R0, R3, clk_off_s           //reset elapsed

updateGPIOEnd:
    MOVE  R3, sensor_update
    LD    R0, R3, sensor_update_ret   //load return address
    JUMP  R0

updateGPIOSEnd: 

//--------------------------
//Check if elapsed time reached, wake main CPU if needed
//--------------------------
checkMainWakeup:
    MOVE  R3, clk
    LD    R0, R3, clk_off_s
    JUMPR checkMainWakeupEnd, idle_threshold, LT
is_rdy_for_wakeup:                   
    READ_RTC_FIELD(RTC_CNTL_LOW_POWER_ST_REG, RTC_CNTL_RDY_FOR_WAKEUP)    // Read RTC_CNTL_RDY_FOR_WAKEUP bit
    AND r0, r0, 1
    JUMP is_rdy_for_wakeup, eq    // Retry until the bit is set
    WAKE
    HALT
checkMainWakeupEnd:
    JUMP    loop
    
