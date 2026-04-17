; ============================================================
; 8051 TIC-TAC-TOE (LM044L 20x4 LCD, 8-bit) + 16 Direct Keys
; MCU: AT89C51 (8051 core)
;
; LCD (8-bit mode):
;   D0..D7  -> P1.0..P1.7
;   RS      -> P0.0
;   RW      -> P0.1
;   E       -> P0.2
;
; Keypad (16 individual buttons, active-LOW):
;   P2.0 = '1'    P2.1 = '2'    P2.2 = '3'    P2.3 = 'A'
;   P2.4 = '4'    P2.5 = '5'    P2.6 = '6'    P2.7 = 'B'
;   P3.0 = '7'    P3.1 = '8'    P3.2 = '9'    P3.3 = 'C'
;   P3.4 = '*'    P3.5 = '0'    P3.6 = '#'    P3.7 = 'D'
;
; Modes:
;   A = PvP
;   B = PvAI  (Human=X, AI=O)
; Reset key:
;   C = Reset anytime / Restart after game over
; ============================================================

            ORG 0000H
            LJMP MAIN

; -----------------------------
; PIN DEFINITIONS
; -----------------------------
RS          EQU P0.0
RW          EQU P0.1
E           EQU P0.2

; -----------------------------
; CONSTANTS
; -----------------------------
MODE_PVP    EQU 0
MODE_AI     EQU 1

EMPTY       EQU 0
XVAL        EQU 1
OVAL        EQU 2

; -----------------------------
; INTERNAL RAM MAP
; -----------------------------
BOARD_BASE  EQU 30H      ; 30H..38H = 9 bytes (cells 1..9)
MODE        EQU 39H
TURN        EQU 3AH      ; 1=X, 2=O
WINNER      EQU 3BH      ; 0=none, 1=X, 2=O, 3=draw
KEY_ASCII   EQU 3DH
CELL_NUM    EQU 3EH      ; 1..9
AI_CELL     EQU 3FH      ; 1..9 or 0
TMPA        EQU 40H
TMPB        EQU 41H
WIN_FLAG    EQU 42H      ; temp storage for win-check result in AI logic

; ============================================================
; MAIN
; ============================================================
MAIN:
            MOV SP, #70H
            MOV PSW, #00H

            ; make P2 and P3 "released" inputs (quasi-bidirectional)
            MOV P2, #0FFH
            MOV P3, #0FFH

            ACALL LCD_INIT
            ACALL LCD_CLEAR

RESET_GAME:
            ACALL BOARD_CLEAR
            ACALL DRAW_GRID
            MOV WINNER, #0

MODE_SELECT:
            ACALL SHOW_MODE_PROMPT

WAIT_MODEKEY:
            ACALL GET_KEY
            MOV KEY_ASCII, A

            CJNE A, #'A', CHK_B
            MOV MODE, #MODE_PVP
            SJMP START_PLAY
CHK_B:
            CJNE A, #'B', WAIT_MODEKEY
            MOV MODE, #MODE_AI

START_PLAY:
            MOV TURN, #XVAL
            ACALL LCD_CLEAR
            ACALL DRAW_GRID
            ACALL DRAW_ALL_CELLS
            ACALL SHOW_STATUS

GAME_LOOP:
            MOV A, WINNER
            JZ  CONTINUE_PLAY
            SJMP GAME_OVER

CONTINUE_PLAY:
            ; PvAI + O's turn => AI moves
            MOV A, MODE
            CJNE A, #MODE_AI, HUMAN_TURN
            MOV A, TURN
            CJNE A, #OVAL, HUMAN_TURN

            ACALL AI_PICK_MOVE
            MOV A, AI_CELL
            JZ  SET_DRAW
            MOV CELL_NUM, A

            ACALL PLACE_TURN_IF_EMPTY
            JNC GAME_LOOP
            SJMP AFTER_MOVE

HUMAN_TURN:
WAIT_MOVE:
            ACALL GET_KEY
            MOV KEY_ASCII, A

            ; Reset anytime
            CJNE A, #'C', NOT_RESET
            SJMP RESET_GAME
NOT_RESET:

            ACALL ASCII_TO_CELL
            JZ WAIT_MOVE

            MOV CELL_NUM, A
            ACALL PLACE_TURN_IF_EMPTY
            JNC WAIT_MOVE

AFTER_MOVE:
            ACALL CHECK_WIN_DRAW

            MOV A, WINNER
            JNZ AFTER_SHOW          ; if winner found, skip turn switch

            ACALL SWITCH_TURN       ; switch turn first so status shows next player

AFTER_SHOW:
            ACALL SHOW_STATUS

            MOV A, WINNER
            JNZ GAME_LOOP           ; winner -> go to GAME_OVER

            SJMP GAME_LOOP

SET_DRAW:
            MOV WINNER, #3
            SJMP GAME_OVER

GAME_OVER:
            ACALL SHOW_GAME_OVER
WAIT_RESTART:
            ACALL GET_KEY
            CJNE A, #'C', WAIT_RESTART
            SJMP RESET_GAME


; ============================================================
; LCD LOW-LEVEL (8-bit)
; ============================================================
LCD_INIT:
            MOV A, #38H
            ACALL LCD_CMD
            ACALL LCD_DELAY

            MOV A, #0CH
            ACALL LCD_CMD
            ACALL LCD_DELAY

            MOV A, #01H
            ACALL LCD_CMD
            ACALL LCD_DELAY

            MOV A, #06H
            ACALL LCD_CMD
            ACALL LCD_DELAY
            RET

LCD_CLEAR:
            MOV A, #01H
            ACALL LCD_CMD
            ACALL LCD_DELAY
            RET

LCD_CMD:
            MOV P1, A
            CLR RS
            CLR RW
            SETB E
            ACALL LCD_DELAY
            CLR E
            RET

LCD_DATA:
            MOV P1, A
            SETB RS
            CLR RW
            SETB E
            ACALL LCD_DELAY
            CLR E
            RET

; 20x4 mapping: 80,C0,94,D4
LCD_GOTO:
            MOV A, R0
            CJNE A, #1, LG2
            MOV A, #080H
            SJMP LG_ADD
LG2:        CJNE A, #2, LG3
            MOV A, #0C0H
            SJMP LG_ADD
LG3:        CJNE A, #3, LG4
            MOV A, #094H
            SJMP LG_ADD
LG4:        MOV A, #0D4H
LG_ADD:     ADD A, R1
            ACALL LCD_CMD
            RET

LCD_PRINT_STR:
LPS1:       CLR A
            MOVC A, @A+DPTR
            JZ LPS_DONE
            ACALL LCD_DATA
            INC DPTR
            SJMP LPS1
LPS_DONE:   RET

LCD_DELAY:
            MOV R6, #35
DLY1:       MOV R7, #255
DLY2:       DJNZ R7, DLY2
            DJNZ R6, DLY1
            RET


; ============================================================
; GRID / DISPLAY HELPERS
; ============================================================
ROW_TEMPLATE: DB ' ','_',' ','|',' ','_',' ','|',' ','_',' ',0
SEP_LINE:     DB '-','-','-','+','-','-','-','+','-','-','-',0

DRAW_GRID:
            ; Row 1 of grid -> LCD line 1
            MOV R0, #1
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #ROW_TEMPLATE
            ACALL LCD_PRINT_STR

            ; Row 2 of grid -> LCD line 2
            MOV R0, #2
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #ROW_TEMPLATE
            ACALL LCD_PRINT_STR

            ; Row 3 of grid -> LCD line 3
            MOV R0, #3
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #ROW_TEMPLATE
            ACALL LCD_PRINT_STR

            ; LCD line 4 is left blank for status
            RET

DRAW_ALL_CELLS:
            MOV CELL_NUM, #1
DAC_LOOP:
            ACALL GET_BOARD_CELL
            CJNE A, #XVAL, DAC_CHK_O
            MOV B, #'X'
            SJMP DAC_DO
DAC_CHK_O:
            CJNE A, #OVAL, DAC_EMPTY
            MOV B, #'O'
            SJMP DAC_DO
DAC_EMPTY:
            MOV B, #'_'
DAC_DO:
            MOV A, CELL_NUM
            ACALL UPDATE_CELL_LCD

            INC CELL_NUM
            MOV A, CELL_NUM
            CJNE A, #10, DAC_LOOP
            RET

UPDATE_CELL_LCD:
            PUSH ACC
            ACALL CELL_TO_POS
            ACALL LCD_GOTO
            MOV A, B
            ACALL LCD_DATA
            POP ACC
            RET

CELL_TO_POS:
            MOV R2, A
            DEC R2
            MOV R3, #0
CTP_ROW:
            CLR C
            MOV A, R2
            SUBB A, #3
            JC  CTP_ROW_DONE
            MOV R2, A
            INC R3
            SJMP CTP_ROW
CTP_ROW_DONE:
            MOV A, R3
            CJNE A, #0, CTP_R1
            MOV R0, #1          ; grid row 0 -> LCD line 1
            SJMP CTP_COL
CTP_R1:     CJNE A, #1, CTP_R2
            MOV R0, #2          ; grid row 1 -> LCD line 2
            SJMP CTP_COL
CTP_R2:     MOV R0, #3          ; grid row 2 -> LCD line 3
CTP_COL:
            MOV A, R2
            CJNE A, #0, CTP_C1
            MOV R1, #1
            RET
CTP_C1:     CJNE A, #1, CTP_C2
            MOV R1, #5
            RET
CTP_C2:
            MOV R1, #9
            RET


; ============================================================
; BOARD ROUTINES
; ============================================================
BOARD_CLEAR:
            MOV R0, #BOARD_BASE
            MOV R1, #9
BC_L:       MOV @R0, #EMPTY
            INC R0
            DJNZ R1, BC_L
            RET

GET_BOARD_CELL:
            MOV A, CELL_NUM
            DEC A
            ADD A, #BOARD_BASE
            MOV R0, A
            MOV A, @R0
            RET

CELL_ADDR_TO_R0:
            MOV A, CELL_NUM
            DEC A
            ADD A, #BOARD_BASE
            MOV R0, A
            RET

PLACE_TURN_IF_EMPTY:
            ACALL CELL_ADDR_TO_R0
            MOV A, @R0
            CJNE A, #EMPTY, PTI_INVALID

            MOV A, TURN
            MOV @R0, A

            MOV A, TURN
            CJNE A, #XVAL, PTI_O
            MOV B, #'X'
            SJMP PTI_UPD
PTI_O:      MOV B, #'O'
PTI_UPD:    MOV A, CELL_NUM
            ACALL UPDATE_CELL_LCD

            SETB C
            RET

PTI_INVALID:
            ACALL SHOW_INVALID_MOVE
            CLR C
            RET

SWITCH_TURN:
            MOV A, TURN
            CJNE A, #XVAL, ST_TOX
            MOV TURN, #OVAL
            RET
ST_TOX:     MOV TURN, #XVAL
            RET


; ============================================================
; WIN/DRAW CHECK
; ============================================================
CHECK_WIN_DRAW:
            MOV WINNER, #0

            MOV R4, #0
            MOV R5, #1
            MOV R6, #2
            ACALL CHECK3
            JZ  CWD_R2
            MOV WINNER, A
            RET
CWD_R2:
            MOV R4, #3
            MOV R5, #4
            MOV R6, #5
            ACALL CHECK3
            JZ  CWD_R3
            MOV WINNER, A
            RET
CWD_R3:
            MOV R4, #6
            MOV R5, #7
            MOV R6, #8
            ACALL CHECK3
            JZ  CWD_C1
            MOV WINNER, A
            RET

CWD_C1:
            MOV R4, #0
            MOV R5, #3
            MOV R6, #6
            ACALL CHECK3
            JZ  CWD_C2
            MOV WINNER, A
            RET
CWD_C2:
            MOV R4, #1
            MOV R5, #4
            MOV R6, #7
            ACALL CHECK3
            JZ  CWD_C3
            MOV WINNER, A
            RET
CWD_C3:
            MOV R4, #2
            MOV R5, #5
            MOV R6, #8
            ACALL CHECK3
            JZ  CWD_D1
            MOV WINNER, A
            RET

CWD_D1:
            MOV R4, #0
            MOV R5, #4
            MOV R6, #8
            ACALL CHECK3
            JZ  CWD_D2
            MOV WINNER, A
            RET
CWD_D2:
            MOV R4, #2
            MOV R5, #4
            MOV R6, #6
            ACALL CHECK3
            JZ  CHECK_DRAW
            MOV WINNER, A
            RET

CHECK_DRAW:
            MOV R0, #BOARD_BASE
            MOV R7, #9
DRL:
            MOV A, @R0
            JZ  NOT_DRAW
            INC R0
            DJNZ R7, DRL
            MOV WINNER, #3
            RET
NOT_DRAW:
            RET

CHECK3:
            MOV A, R4
            ACALL GET_CELL_OFF
            JZ  C3_NOWIN
            MOV B, A

            MOV A, R5
            ACALL GET_CELL_OFF
            CJNE A, B, C3_NOWIN

            MOV A, R6
            ACALL GET_CELL_OFF
            CJNE A, B, C3_NOWIN

            MOV A, B
            RET
C3_NOWIN:
            MOV A, #0
            RET

GET_CELL_OFF:
            ADD A, #BOARD_BASE
            MOV R0, A
            MOV A, @R0
            RET



; ============================================================
; AI (rule-based) - AI always O
; Priority: Win -> Block -> Center -> Corners -> Sides
; Uses HAS_WIN_SYMBOL (does NOT touch WINNER)
; ============================================================

AI_PICK_MOVE:
            MOV AI_CELL, #0

            ; 1) Win move for O
            MOV A, #OVAL
            ACALL FIND_WINNING_MOVE_SAFE
            MOV A, AI_CELL
            JNZ AI_RET

            ; 2) Block X
            MOV A, #XVAL
            ACALL FIND_WINNING_MOVE_SAFE
            MOV A, AI_CELL
            JNZ AI_RET

            ; 3) Center
            MOV CELL_NUM, #5
            ACALL GET_BOARD_CELL
            JNZ AI_CORNERS
            MOV AI_CELL, #5
            SJMP AI_RET

AI_CORNERS:
            ; 4) Corners: 1,3,7,9
            MOV CELL_NUM, #1
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            MOV CELL_NUM, #3
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            MOV CELL_NUM, #7
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            MOV CELL_NUM, #9
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            ; 5) Sides: 2,4,6,8
            MOV CELL_NUM, #2
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            MOV CELL_NUM, #4
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            MOV CELL_NUM, #6
            ACALL AI_TAKE_IF_EMPTY
            MOV A, AI_CELL
            JNZ AI_RET

            MOV CELL_NUM, #8
            ACALL AI_TAKE_IF_EMPTY

AI_RET:
            RET

AI_TAKE_IF_EMPTY:
            ACALL GET_BOARD_CELL
            JNZ AI_TAKE_RET
            MOV A, CELL_NUM
            MOV AI_CELL, A
AI_TAKE_RET:
            RET


; ------------------------------------------------------------
; FIND_WINNING_MOVE_SAFE
; In:  A = symbol to test (XVAL or OVAL)
; Out: AI_CELL = cell (1..9) that makes that symbol win, else 0
; Does NOT modify WINNER
; ------------------------------------------------------------
FIND_WINNING_MOVE_SAFE:
            MOV TMPA, A          ; symbol under test (1 or 2)
            MOV AI_CELL, #0
            MOV CELL_NUM, #1

FWM_LOOP:
            ; skip if not empty
            ACALL GET_BOARD_CELL
            JNZ FWM_NEXT

            ; place test symbol into board cell temporarily
            ; CELL_ADDR_TO_R0: R0 = BOARD_BASE + (CELL_NUM-1)
            ACALL CELL_ADDR_TO_R0
            MOV TMPB, @R0           ; save original value (should be EMPTY)
            MOV A, TMPA
            MOV @R0, A              ; temporarily place test symbol

            ; HAS_WIN_SYMBOL uses GET_CELL_OFF which overwrites R0!
            ; So we save the result into WIN_FLAG and recompute R0 after.
            MOV A, TMPA
            ACALL HAS_WIN_SYMBOL    ; A = 1 if win, A = 0 if not
            MOV WIN_FLAG, A         ; save result before R0 is needed again

            ; Recompute R0 (CELL_NUM is still valid, TMPB holds original value)
            ACALL CELL_ADDR_TO_R0

            ; Revert the board cell
            MOV A, TMPB
            MOV @R0, A

            ; Now check the saved win result
            MOV A, WIN_FLAG
            JZ  FWM_CHECK_NEXT      ; no win for this cell

            ; Found a winning cell - record it and return
            MOV A, CELL_NUM
            MOV AI_CELL, A
            SJMP FWM_RET

FWM_CHECK_NEXT:
            MOV A, AI_CELL
            JNZ FWM_RET             ; already found a cell earlier, return

FWM_NEXT:
            INC CELL_NUM
            MOV A, CELL_NUM
            CJNE A, #10, FWM_LOOP

FWM_RET:
            RET


; ------------------------------------------------------------
; HAS_WIN_SYMBOL
; In:  A = symbol (XVAL=1 or OVAL=2)
; Out: A = 1 if this symbol has a win, else A=0
; ------------------------------------------------------------
HAS_WIN_SYMBOL:
            MOV B, A             ; B = symbol

            ; row1 (0,1,2)
            MOV R4,#0
            MOV R5,#1
            MOV R6,#2
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; row2 (3,4,5)
            MOV R4,#3
            MOV R5,#4
            MOV R6,#5
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; row3 (6,7,8)
            MOV R4,#6
            MOV R5,#7
            MOV R6,#8
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; col1 (0,3,6)
            MOV R4,#0
            MOV R5,#3
            MOV R6,#6
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; col2 (1,4,7)
            MOV R4,#1
            MOV R5,#4
            MOV R6,#7
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; col3 (2,5,8)
            MOV R4,#2
            MOV R5,#5
            MOV R6,#8
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; diag1 (0,4,8)
            MOV R4,#0
            MOV R5,#4
            MOV R6,#8
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            ; diag2 (2,4,6)
            MOV R4,#2
            MOV R5,#4
            MOV R6,#6
            ACALL LINE_IS_SYMBOL
            JNZ HW_YES

            MOV A,#0
            RET

HW_YES:
            MOV A,#1
            RET


; ------------------------------------------------------------
; LINE_IS_SYMBOL
; Checks if board[R4], board[R5], board[R6] are all == B
; Out: A=1 if yes, A=0 if no
; ------------------------------------------------------------
LINE_IS_SYMBOL:
            MOV A,R4
            ACALL GET_CELL_OFF
            CJNE A,B, LIS_NO

            MOV A,R5
            ACALL GET_CELL_OFF
            CJNE A,B, LIS_NO

            MOV A,R6
            ACALL GET_CELL_OFF
            CJNE A,B, LIS_NO

            MOV A,#1
            RET

LIS_NO:
            MOV A,#0
            RET


; ============================================================
; STATUS / MESSAGES
; ============================================================
MSG_TITLE:  DB 'T','I','C',' ','T','A','C',' ','T','O','E',0
MSG_MODE:   DB 'A',':','P','v','P',' ','B',':','A','I',0
MSG_TURN:   DB 'T','u','r','n',':',0
MSG_AI:     DB 'P','v','A','I',0
MSG_PVP:    DB 'P','v','P',0
MSG_INV:    DB 'I','n','v','a','l','i','d',0
MSG_CLR8:   DB ' ',' ',' ',' ',' ',' ',' ',' ',0
MSG_CLR20:  DB ' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',0
MSG_XWIN:   DB 'X',' ','W','I','N',0
MSG_OWIN:   DB 'O',' ','W','I','N',0
MSG_DRAW:   DB 'D','R','A','W',0

SHOW_MODE_PROMPT:
            ACALL LCD_CLEAR
            MOV R0, #1
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #MSG_TITLE
            ACALL LCD_PRINT_STR

            MOV R0, #2
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #MSG_MODE
            ACALL LCD_PRINT_STR
            RET

SHOW_STATUS:
            ; First clear entire line 4 to remove leftover characters
            MOV R0, #4
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #MSG_CLR20
            ACALL LCD_PRINT_STR

            ; Now position cursor for status (col 12)
            MOV R0, #4
            MOV R1, #12
            ACALL LCD_GOTO

            MOV A, WINNER
            JZ  SS_TURN

            CJNE A, #3, SS_WIN
            MOV DPTR, #MSG_DRAW
            ACALL LCD_PRINT_STR
            RET

SS_WIN:
            CJNE A, #2, SS_XWIN    ; if WINNER != 2, jump to X win
            MOV DPTR, #MSG_OWIN    ; WINNER == 2 -> O wins
            ACALL LCD_PRINT_STR
            RET
SS_XWIN:
            MOV DPTR, #MSG_XWIN    ; WINNER == 1 -> X wins
            ACALL LCD_PRINT_STR
            RET

SS_TURN:
            MOV DPTR, #MSG_TURN
            ACALL LCD_PRINT_STR

            MOV A, TURN
            CJNE A, #OVAL, SST_X   ; if TURN != OVAL, jump to print X
            MOV A, #'O'            ; TURN == OVAL -> print O
            SJMP SST_PUT
SST_X:      MOV A, #'X'            ; TURN == XVAL -> print X
SST_PUT:    ACALL LCD_DATA

            MOV A, #' '
            ACALL LCD_DATA

            MOV A, MODE
            CJNE A, #MODE_AI, SST_PVP
            MOV DPTR, #MSG_AI
            ACALL LCD_PRINT_STR
            RET
SST_PVP:
            MOV DPTR, #MSG_PVP
            ACALL LCD_PRINT_STR
            RET

SHOW_INVALID_MOVE:
            MOV R0, #4
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #MSG_INV
            ACALL LCD_PRINT_STR

            ACALL LCD_DELAY
            ACALL LCD_DELAY

            MOV R0, #4
            MOV R1, #0
            ACALL LCD_GOTO
            MOV DPTR, #MSG_CLR8
            ACALL LCD_PRINT_STR
            RET

SHOW_GAME_OVER:
            RET


; ============================================================
; DIRECT 16-KEY INPUT (NO MATRIX)
; Active-LOW: pressed pin reads 0
; Returns ASCII in A
; ============================================================
GET_KEY:
; wait until ALL released
KREL:
            MOV P2, #0FFH
            MOV P3, #0FFH
            MOV A, P2
            CJNE A, #0FFH, KREL
            MOV A, P3
            CJNE A, #0FFH, KREL

; wait for any press
KPOLL:
            ACALL DEBOUNCE_20MS
            MOV A, P2
            CJNE A, #0FFH, KFOUND
            MOV A, P3
            CJNE A, #0FFH, KFOUND
            SJMP KPOLL

KFOUND:
            ACALL DEBOUNCE_20MS

            ; Check P2 keys first
            JNB P2.0, K1
            JNB P2.1, K2
            JNB P2.2, K3
            JNB P2.3, KA
            JNB P2.4, K4
            JNB P2.5, K5
            JNB P2.6, K6
            JNB P2.7, KB

            ; Check P3 keys
            JNB P3.0, K7
            JNB P3.1, K8
            JNB P3.2, K9
            JNB P3.3, KC
            JNB P3.4, KSTAR
            JNB P3.5, K0
            JNB P3.6, KHASH
            JNB P3.7, KD

            SJMP KPOLL

K1:         MOV A, #'1'   
            RET
            
K2:         MOV A, #'2'   
            RET
            
K3:         MOV A, #'3'
            RET
            
KA:         MOV A, #'A'   
            RET

K4:         MOV A, #'4'   
            RET
            
K5:         MOV A, #'5'   
            RET
            
K6:         MOV A, #'6'   
            RET
            
KB:         MOV A, #'B'   
            RET

K7:         MOV A, #'7'   
            RET
            
K8:         MOV A, #'8'   
            RET
            
K9:         MOV A, #'9'   
            RET

KC:         MOV A, #'C'   
            RET

KSTAR:      MOV A, #'*'   
            RET

K0:         MOV A, #'0'   
            RET

KHASH:      MOV A, #'#'   
            RET

KD:         MOV A, #'D'   
            RET

DEBOUNCE_20MS:
            MOV R5, #50
DB1:        MOV R6, #255
DB2:        DJNZ R6, DB2
            DJNZ R5, DB1
            RET


; ASCII_TO_CELL: '1'..'9' -> 1..9 else 0
ASCII_TO_CELL:
            MOV TMPA, A
            CLR C
            SUBB A, #'1'
            JC  ATC_BAD

            MOV A, TMPA
            CLR C
            SUBB A, #':'         ; ':' = '9'+1
            JNC ATC_BAD

            MOV A, TMPA
            CLR C
            SUBB A, #'0'
            RET
ATC_BAD:
            MOV A, #0
            RET

            END