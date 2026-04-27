1. caliptra_top_tb_soc_bfm.sv implements the top level BFM interface to caliptra_top, which drives the fuses and sets the fuse_done and BootGo 
    for example these come from the bfm:
    SoC: Writing fuse done register
    SoC: Writing BootGo register
2. BFM (caliptra_top_tb_pkg) is instantiated in 
    caliptra_top_tb_services.sv  
    caliptra_top_tb  instantiates the caliptra_top_tb_services module, which in turn instantiates the bfm.

3. The test-flow is controlled two ways:
    Caliptra's reset and power are driven by testbench BFM
    Once the Caliptra boot-flow FSM reaches ready_for_fuses de-asserted (meaning fuses are loaded), BootGo is set to start running the code from ROM
    CLP: ROM Flow in progress 
    Next state: ready_for_mb_processing