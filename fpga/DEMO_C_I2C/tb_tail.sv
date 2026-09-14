    initial clk=0;
    always #10 clk=~clk;
    int errors=0, ready_count=0, input_count=0, results=0, check_count=0;
    int self_count=0, self_checks=0, self_fails=0;
    byte rx;
    string line="", check_name, check_status;
    int class_id, p0,p1,p2,p3, ncycles, got, expected;
    byte vectors0[1960], vectors1[1960];
    initial begin
        forever begin
            @(negedge uart1_txd); #500;
            for(int k=0;k<8;k++)begin #1000;rx[k]=uart1_txd;end
            #1000;
            if(rx==10)begin
                $display("UART %s",line);
                if(line=="READY")ready_count++;
                if(line=="INPUT_READY")input_count++;
                if(line.len()>=6 && line.substr(0,5)=="CHECK ")begin
                    check_count++;
                    if($sscanf(line,"CHECK %s %s %h %h",check_name,check_status,got,expected)!=4 || check_status!="PASS" || got !== expected)errors++;
                end
                if($sscanf(line,"SELFTEST_END %d %d",self_checks,self_fails)==2)begin
                    self_count++;
                    if(self_checks<70||self_fails!=0)errors++;
                end
                if($sscanf(line,"RESULT %d %h %h %h %h %d",class_id,p0,p1,p2,p3,ncycles)==6)begin
                    results++;
                    if(results==1 && (class_id!=3 || p0!=0 || p1!=225 || p2!=326 || p3!=3543))errors++;
                    if(results==2 && (class_id!=0 || p0!=1820 || p1!=1261 || p2!=873 || p3!=139))errors++;
                end
                line="";
            end else if(rx!=13)line={line,rx};
        end
    end
    task send(input byte b);
        uart2_rxd=0;#1000;
        for(int i=0;i<8;i++)begin uart2_rxd=b[i];#1000;end
        uart2_rxd=1;#1000;
    endtask
    initial begin
        $readmemh("input0.hex",vectors0);$readmemh("input1.hex",vectors1);
        rst_n=0;gpio_i=0;uart1_rxd=1;uart2_rxd=1;
        jtag_tms=1;jtag_tck=0;jtag_tdi=0;jtag_trst_n=1;
        #151;rst_n=1;
        wait(ready_count>=1);
        send("N");wait(input_count>=1);
        for(int i=0;i<1960;i++)send(vectors0[i]);
        wait(results>=1);wait(ready_count>=2);
        send("N");wait(input_count>=2);
        for(int i=0;i<1960;i++)send(vectors1[i]);
        wait(results>=2);wait(ready_count>=3);
        send("U");#200000;
        for(int i=0;i<256;i++)send(i);
        wait(ready_count>=4);
        send("L");send(8'h5a);send(8'ha5);wait(ready_count>=5);
        if(gpio_o!==16'ha55a)errors++;
        send("E");send(1);wait(ready_count>=6);gpio_i=16'hffff;#20000;
        send("G");wait(ready_count>=7);
        send("E");send(2);wait(ready_count>=8);gpio_i=0;#20000;
        send("G");wait(ready_count>=9);
        send("E");send(0);wait(ready_count>=10);
        send("?");wait(ready_count>=11);
        send("B");wait(ready_count>=12);
        if(errors || self_count!=2 || check_count!=174)$fatal(1,"JURY FAILED errors=%0d checks=%0d",errors,check_count);
        $display("[PASS] JURY_SELFTEST_AND_TWO_INFERENCES checks=%0d errors=0",check_count);
        $finish;
    end
    initial begin #500000000;$fatal(1,"JURY TIMEOUT");end
endmodule
