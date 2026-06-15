// Add your memory initialization code here. 
// You MUST KEEP "helloworld.mem" file constant, since it will be automatically
// added to the Vivado project, you should only change boot ROM memory array path.

initial begin
    $readmemh("helloworld.mem", dut.u_soc_top.u_boot_rom.rom_mem);
end
