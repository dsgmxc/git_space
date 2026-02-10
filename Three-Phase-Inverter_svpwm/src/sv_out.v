module sv_out #(
    parameter TIM_WIDTH = 16,		// 时间比例位宽 = 幅度比例位宽，q0.15格式
    parameter SEC_WIDTH = 3
)(
    input  wire        clk,             // 系统时钟
    input  wire        rst_n,           // 复位信号

    // --- 来自上一级模块的输入 (这些信号在PWM周期外会变化) ---
    input  wire signed [TIM_WIDTH-1:0] t1_in,       // 作用时间T1 (Q15格式)
    input  wire signed [TIM_WIDTH-1:0] t2_in,       // 作用时间T2 (Q15格式)
    input  wire [SEC_WIDTH-1:0]      sector_in,      // 扇区号 (1-6)

    // --- 系统参数 ---
    input  wire signed [TIM_WIDTH-1:0]    t_period_cnt, // 一个PWM周期的计数值 (T_pwm / T_clk)
    output wire signed [TIM_WIDTH-1:0]	  debug_t1,
    output wire signed [TIM_WIDTH-1:0]	  debug_t2,
    // --- 输出到驱动电路的三路PWM信号 ---
    output reg         pwm_a,           // A相PWM
    output reg         pwm_b,           // B相PWM
    output reg         pwm_c            // C相PWM
);

	//=====================================================================
    // 第2步：PWM周期计数器
    //=====================================================================
    reg [TIM_WIDTH-1:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
        end else if (cnt >= t_period_cnt) begin
            cnt <= 0;
        end else begin
            cnt <= cnt + 1;
        end
    end

    //=====================================================================
    // 【新增】第0步：在每个PWM周期开始时，锁存输入信号
    //=====================================================================
    // 这些reg将在整个PWM周期内保持稳定
    reg signed [TIM_WIDTH-1:0] t1_latched;
    reg signed [TIM_WIDTH-1:0] t2_latched;
    reg [SEC_WIDTH-1:0]      sector_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t1_latched <= 0;
            t2_latched <= 0;
            sector_latched <= 1;
        end else begin
            // 当计数器归零时，表示新周期开始，锁存新的输入
            if (cnt == 0) begin
                t1_latched <= t1_in;
                t2_latched <= t2_in;
                sector_latched <= sector_in;
            end
            // 在周期其他时间，保持锁存值不变
        end
    end

    //=====================================================================
    // 第1步：将锁存的Q15格式时间转换为计数值
    //=====================================================================
    wire signed [2*TIM_WIDTH-1:0] t1_mult = t1_latched * t_period_cnt;
    wire signed [2*TIM_WIDTH-1:0] t2_mult = t2_latched * t_period_cnt;
    
    wire signed [TIM_WIDTH-1:0] t1_cnt = t1_mult[2*TIM_WIDTH-2:TIM_WIDTH-1];
    wire signed [TIM_WIDTH-1:0] t2_cnt = t2_mult[2*TIM_WIDTH-2:TIM_WIDTH-1];
	assign debug_t1 = t1_cnt;
    assign debug_t2 = t2_cnt;
	wire signed [TIM_WIDTH-1:0] t_sum = t1_cnt + t2_cnt;
	wire signed [TIM_WIDTH-1:0] t_zero_period;
	assign t_zero_period =  (t_sum > t_period_cnt) ? 0 : (t_period_cnt - t_sum);

    //=====================================================================
    // 第1.5步：计算对称式的7个时间分割点
    //=====================================================================
    // 波形序列: V0(T0/4) -> V1(T1/2) -> V2(T2/2) -> V7(T0/2) -> V2(T2/2) -> V1(T1/2) -> V0(T0/4)
    wire signed [TIM_WIDTH-1:0] t_qtr_period = t_zero_period >> 2;       // T0/4
    wire signed [TIM_WIDTH-1:0] t_half_t1 = t1_cnt >> 1;                 // T1/2
    wire signed [TIM_WIDTH-1:0] t_half_t2 = t2_cnt >> 1;                 // T2/2

    // 7个时间段的边界点
    wire signed [TIM_WIDTH-1:0] ta = t_qtr_period;                                       // T0/4
    wire signed [TIM_WIDTH-1:0] tb = ta + t_half_t1;                                     // T0/4 + T1/2
    wire signed [TIM_WIDTH-1:0] tc = tb + t_half_t2;                                     // T0/4 + T1/2 + T2/2
    wire signed [TIM_WIDTH-1:0] td = tc + (t_zero_period >> 1);                          // T0/4 + T1/2 + T2/2 + T0/2
    wire signed [TIM_WIDTH-1:0] te = td + t_half_t2;                                     // T0/4 + T1/2 + T2/2 + T0/2 + T2/2
    wire signed [TIM_WIDTH-1:0] tf = te + t_half_t1;                                     // T0/4 + T1/2 + T2/2 + T0/2 + T2/2 + T1/2


    //=====================================================================
    // 第3步：比较器，确定当前处于哪个7个时间段
    //=====================================================================
    reg [2:0] pwm_phase; 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_phase <= 3'b000;
        end else begin
            if (cnt < ta)          pwm_phase <= 3'b000; // Phase 0: T0/4 (V0)
            else if (cnt < tb)     pwm_phase <= 3'b001; // Phase 1: T1/2
            else if (cnt < tc)     pwm_phase <= 3'b010; // Phase 2: T2/2
            else if (cnt < td)     pwm_phase <= 3'b011; // Phase 3: T0/2 (V7)
            else if (cnt < te)     pwm_phase <= 3'b100; // Phase 4: T2/2
            else if (cnt < tf)     pwm_phase <= 3'b101; // Phase 5: T1/2
            else                   pwm_phase <= 3'b110; // Phase 6: T0/4 (V0)
        end
    end

    //=====================================================================
    // 第4步：扇区映射，根据锁存的扇区和时间段生成对称PWM波形
    //=====================================================================
    // 定义每个扇区在T1和T2期间对应的开关状态 (1=高电平, 0=低电平)
    // {A, B, C}
    localparam [2:0] SECTOR_1_T1 = 3'b100, SECTOR_1_T2 = 3'b110;
    localparam [2:0] SECTOR_2_T1 = 3'b110, SECTOR_2_T2 = 3'b010;
    localparam [2:0] SECTOR_3_T1 = 3'b010, SECTOR_3_T2 = 3'b011;
    localparam [2:0] SECTOR_4_T1 = 3'b011, SECTOR_4_T2 = 3'b001;
    localparam [2:0] SECTOR_5_T1 = 3'b001, SECTOR_5_T2 = 3'b101;
    localparam [2:0] SECTOR_6_T1 = 3'b101, SECTOR_6_T2 = 3'b100;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {pwm_a, pwm_b, pwm_c} <= 3'b000;
        end else begin
            case (pwm_phase)
                // Phase 0 & 6: T0/4 periods, use zero vector V0(000)
                3'b000, 3'b110: begin
                    {pwm_a, pwm_b, pwm_c} <= 3'b000;
                end
                
                // Phase 1 & 5: T1/2 periods (对称复用)
                3'b001, 3'b101: begin
                    case (sector_latched) // 【修改】使用锁存的扇区值
                        3'd1: {pwm_a, pwm_b, pwm_c} <= SECTOR_1_T1;
                        3'd2: {pwm_a, pwm_b, pwm_c} <= SECTOR_2_T1;
                        3'd3: {pwm_a, pwm_b, pwm_c} <= SECTOR_3_T1;
                        3'd4: {pwm_a, pwm_b, pwm_c} <= SECTOR_4_T1;
                        3'd5: {pwm_a, pwm_b, pwm_c} <= SECTOR_5_T1;
                        3'd6: {pwm_a, pwm_b, pwm_c} <= SECTOR_6_T1;
                        default: {pwm_a, pwm_b, pwm_c} <= 3'b000;
                    endcase
                end
                
                // Phase 2 & 4: T2/2 periods (对称复用)
                3'b010, 3'b100: begin
                    case (sector_latched) // 【修改】使用锁存的扇区值
                        3'd1: {pwm_a, pwm_b, pwm_c} <= SECTOR_1_T2;
                        3'd2: {pwm_a, pwm_b, pwm_c} <= SECTOR_2_T2;
                        3'd3: {pwm_a, pwm_b, pwm_c} <= SECTOR_3_T2;
                        3'd4: {pwm_a, pwm_b, pwm_c} <= SECTOR_4_T2;
                        3'd5: {pwm_a, pwm_b, pwm_c} <= SECTOR_5_T2;
                        3'd6: {pwm_a, pwm_b, pwm_c} <= SECTOR_6_T2;
                        default: {pwm_a, pwm_b, pwm_c} <= 3'b000;
                    endcase
                end
                
                // Phase 3: T0/2 period, use zero vector V7(111)
                3'b011: begin
                    {pwm_a, pwm_b, pwm_c} <= 3'b111;
                end
                
                default: {pwm_a, pwm_b, pwm_c} <= 3'b000;
            endcase
        end
    end

endmodule

