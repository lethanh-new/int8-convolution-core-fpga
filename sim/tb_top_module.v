`timescale 1ns/1ps
module tb_top_module();
    reg clk; reg rst_n; reg [7:0] test_pixel; reg test_valid_in;
    wire test_valid_out; wire signed [7:0] test_out_mac;

    reg [7:0] image_mem [0:783]; 
    integer i; 

    top_module uut (
        .clk(clk), .rst_n(rst_n), .pixel_in(test_pixel), .valid_in(test_valid_in),
        .valid_out(test_valid_out), .out_mac(test_out_mac)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
       
      $readmemh("D:/CNN FINAL/so.hex", image_mem);

        rst_n = 0; test_valid_in = 0; test_pixel = 8'd0;
        #20; rst_n = 1; #10; 

        for (i = 0; i < 784; i = i + 1) begin
            @(posedge clk); 
            test_pixel = image_mem[i]; 
            test_valid_in = 1;         
        end
        
        @(posedge clk);
        test_valid_in = 0; 
    end
endmodule
