`timescale 1ns/1ps

module memoria #(
    parameter integer CLK_FREQ_HZ = 27_000_000,
    parameter integer SHOW_ON_MS  = 500,
    parameter integer SHOW_OFF_MS = 250,
    parameter integer BLINK_HZ    = 2
) (
    input  wire       clk,
    input  wire       start,
    input  wire [3:0] buttons,
    output reg  [3:0] leds
);

    // ============================================================
    // PARÁMETROS Y CONSTANTES
    // ============================================================

    localparam integer LEVELS = 4;

    localparam integer SHOW_ON_CYCLES    = (CLK_FREQ_HZ / 1000) * SHOW_ON_MS;
    localparam integer SHOW_OFF_CYCLES   = (CLK_FREQ_HZ / 1000) * SHOW_OFF_MS;
    localparam integer BLINK_HALF_PERIOD = CLK_FREQ_HZ / (BLINK_HZ * 2);

    // Tiempo de debounce: ~20 ms (540,000 ciclos a 27 MHz)
    localparam integer DEBOUNCE_CYCLES   = (CLK_FREQ_HZ / 1000) * 20;

    localparam [2:0] IDLE       = 3'd0;
    localparam [2:0] SHOW_ON    = 3'd1;
    localparam [2:0] SHOW_OFF   = 3'd2;
    localparam [2:0] WAIT_INPUT = 3'd3;
    localparam [2:0] SUCCESS    = 3'd4;

    reg [2:0] state;

    // ============================================================
    // MEMORIA DE LA SECUENCIA
    // ============================================================

    reg [1:0] led_sequence [0:LEVELS-1];
    reg [2:0] level;
    reg [2:0] sequence_index;

    // ============================================================
    // GENERADOR LFSR
    // ============================================================

    reg [3:0] lfsr;

    function [1:0] next_random_led;
        input [3:0] random_value;
        input [1:0] previous_led;
        reg [1:0] selected;
        begin
            selected = random_value[1:0];
            if (selected == previous_led)
                selected = selected + 2'd1;
            next_random_led = selected;
        end
    endfunction

    // ============================================================
    // CONTADORES DE TIEMPO
    // ============================================================

    reg [31:0] show_counter;
    reg [31:0] blink_counter;
    reg [2:0]  blink_count;
    reg        blink_state;

    // ============================================================
    // DEBOUNCE Y DETECCIÓN DE FLANCOS
    // ============================================================

    reg [19:0] db_cnt_start;
    reg [19:0] db_cnt_btn [0:3];
    
    reg       start_clean;
    reg [3:0] buttons_clean;

    reg       start_d;
    reg [3:0] buttons_d;

    wire       start_pressed;
    wire [3:0] button_pressed;

    // Proceso de Anti-rebote
    always @(posedge clk) begin
        // Start debounce
        if (start != start_clean) begin
            if (db_cnt_start >= DEBOUNCE_CYCLES) begin
                start_clean <= start;
                db_cnt_start <= 0;
            end else begin
                db_cnt_start <= db_cnt_start + 1'b1;
            end
        end else begin
            db_cnt_start <= 0;
        end

        // Buttons debounce
        begin : debounce_buttons_block
            integer i;
            for (i = 0; i < 4; i = i + 1) begin
                if (buttons[i] != buttons_clean[i]) begin
                    if (db_cnt_btn[i] >= DEBOUNCE_CYCLES) begin
                        buttons_clean[i] <= buttons[i];
                        db_cnt_btn[i] <= 0;
                    end else begin
                        db_cnt_btn[i] <= db_cnt_btn[i] + 1'b1;
                    end
                end else begin
                    db_cnt_btn[i] <= 0;
                end
            end
        end

        // Captura para detección de flanco de bajada (PULL-UP)
        start_d   <= start_clean;
        buttons_d <= buttons_clean;
    end

    assign start_pressed  = (~start_clean) & start_d;
    assign button_pressed = (~buttons_clean) & buttons_d;

    // ============================================================
    // SALIDA DE LOS LEDs (Activos en BAJO)
    // ============================================================

    always @(*) begin
        leds = 4'b1111; // Por defecto apagados

        case (state)
            SHOW_ON: begin
                leds[led_sequence[sequence_index]] = 1'b0;
            end

            WAIT_INPUT: begin
                // Encender el LED del botón presionado actualmente
                leds = buttons_clean; 
            end

            SUCCESS: begin
                leds = blink_state ? 4'b0000 : 4'b1111;
            end

            default: leds = 4'b1111;
        endcase
    end

    // ============================================================
    // INICIALIZACIÓN Y LÓGICA SECUENCIAL
    // ============================================================

    initial begin
        state = IDLE;
        level = 3'd0;
        sequence_index = 3'd0;
        lfsr = 4'b1011;

        show_counter = 32'd0;
        blink_counter = 32'd0;
        blink_count = 3'd0;
        blink_state = 1'b0;

        start_clean = 1'b1;
        buttons_clean = 4'b1111;
        start_d = 1'b1;
        buttons_d = 4'b1111;

        db_cnt_start = 0;
        db_cnt_btn[0] = 0;
        db_cnt_btn[1] = 0;
        db_cnt_btn[2] = 0;
        db_cnt_btn[3] = 0;

        led_sequence[0] = 2'd0;
        led_sequence[1] = 2'd0;
        led_sequence[2] = 2'd0; // CORREGIDO AQUÍ
        led_sequence[3] = 2'd0;
    end

    always @(posedge clk) begin

        // Actualización continua del LFSR
        lfsr <= {lfsr[2:0], lfsr[3] ^ lfsr[2]};

        case (state)

            IDLE: begin
                show_counter   <= 32'd0;
                blink_counter  <= 32'd0;
                blink_count    <= 3'd0;
                blink_state    <= 1'b0;
                sequence_index <= 3'd0;

                if (start_pressed) begin
                    led_sequence[0] <= lfsr[1:0];
                    level           <= 3'd0;
                    sequence_index  <= 3'd0;
                    show_counter    <= 32'd0;
                    state           <= SHOW_ON;
                end
            end

            SHOW_ON: begin
                if (show_counter >= SHOW_ON_CYCLES - 1) begin
                    show_counter <= 32'd0;
                    state        <= SHOW_OFF;
                end else begin
                    show_counter <= show_counter + 1'b1;
                end
            end

            SHOW_OFF: begin
                if (show_counter >= SHOW_OFF_CYCLES - 1) begin
                    show_counter <= 32'd0;
                    if (sequence_index >= level) begin
                        sequence_index <= 3'd0;
                        state          <= WAIT_INPUT;
                    end else begin
                        sequence_index <= sequence_index + 1'b1;
                        state          <= SHOW_ON;
                    end
                end else begin
                    show_counter <= show_counter + 1'b1;
                end
            end

            WAIT_INPUT: begin
                if (button_pressed != 4'b0000) begin
                    if (button_pressed == (4'b0001 << led_sequence[sequence_index])) begin
                        
                        if (sequence_index >= level) begin
                            if (level >= LEVELS - 1) begin
                                // Victoria: 4 niveles superados
                                blink_counter <= 32'd0;
                                blink_count   <= 3'd0;
                                blink_state   <= 1'b1;
                                state         <= SUCCESS;
                            end else begin
                                // Siguiente nivel
                                led_sequence[level + 1] <= next_random_led(lfsr, led_sequence[level]);
                                level          <= level + 1'b1;
                                sequence_index <= 3'd0;
                                show_counter   <= 32'd0;
                                state          <= SHOW_ON;
                            end
                        end else begin
                            // Acierto parcial
                            sequence_index <= sequence_index + 1'b1;
                        end

                    end else begin
                        // Error: Reiniciar
                        level          <= 3'd0;
                        sequence_index <= 3'd0;
                        show_counter   <= 32'd0;
                        state          <= IDLE;
                    end
                end
            end

            SUCCESS: begin
                if (blink_counter >= BLINK_HALF_PERIOD - 1) begin
                    blink_counter <= 32'd0;
                    blink_state   <= ~blink_state;

                    if (blink_count >= 3'd5) begin
                        state       <= IDLE;
                        blink_state <= 1'b0;
                        blink_count <= 3'd0;
                    end else begin
                        blink_count <= blink_count + 1'b1;
                    end
                end else begin
                    blink_counter <= blink_counter + 1'b1;
                end
            end

            default: begin
                state <= IDLE;
            end

        endcase
    end

endmodule