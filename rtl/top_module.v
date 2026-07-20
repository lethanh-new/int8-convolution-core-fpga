module top_module (
    input wire clk,
    input wire rst_n,
    input wire [7:0] pixel_in,
    input wire valid_in,
    output wire valid_out,
    output wire signed [7:0] out_mac
);
    // =========================================================================
    // 1. KHAI BÁO DÂY (WIRES) 
    // =========================================================================
    // Dây nối Điểm ảnh từ Sliding Window
    wire sw_valid_out; 
    wire [7:0] px00, px01, px02, px10, px11, px12, px20, px21, px22;
    
    // Dây nối Trọng số từ ROM
    wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;

    // Dây hứng ngõ ra của Conv Core
    wire signed [31:0] w_out_int32; 
    wire signed [7:0]  w_out_int8; 
    wire               w_conv_valid_out; 

    // =========================================================================
    // 2. LẮP RÁP CÁC MODULE 
    // =========================================================================

    // Khối 1: Cửa sổ quét ảnh 
    sliding_window #(.DATA_WIDTH(8), .IMG_WIDTH(28)) u_sliding_window (
        .clk(clk), .rst_n(rst_n), 
        .in_valid(valid_in), .pixel_in(pixel_in),
        .out_valid(sw_valid_out), 
        .p00(px00), .p01(px01), .p02(px02), 
        .p10(px10), .p11(px11), .p12(px12), 
        .p20(px20), .p21(px21), .p22(px22)
    );

    // Khối 2: ROM Trọng số 
    kernel_rom u_kernel_rom (
        .kernel_sel(2'd0), 
        .w00(w00), .w01(w01), .w02(w02), 
        .w10(w10), .w11(w11), .w12(w12), 
        .w20(w20), .w21(w21), .w22(w22)
    );

    // Khối 3: Lõi Nhân chập MAC + ReLU + Clip 
    conv_core_int8 u_conv_core (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(sw_valid_out), 
        
        // Cấp 9 điểm ảnh
        .p00(px00), .p01(px01), .p02(px02),
        .p10(px10), .p11(px11), .p12(px12),
        .p20(px20), .p21(px21), .p22(px22),
        
        // Cấp 9 trọng số từ ROM vào Lõi
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        
        // Cấp bias = 0 theo tài liệu README
        .bias(32'd0),
        
        // Hứng kết quả ngõ ra 
        .out_valid(w_conv_valid_out),
        .out_int32(w_out_int32),    
        .out_int8(w_out_int8)
       
    );
    
    // =========================================================================
    // 3. GÁN NGÕ RA CHÍNH 
    // =========================================================================
    assign valid_out = w_conv_valid_out;
    assign out_mac   = w_out_int8; 

endmodule
