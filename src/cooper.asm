; ---------------------------------------------------------------
; COOPER RUN - motor novo OPTIMIZADO (curvas + velocidade + despiste)
; A versao anterior custava 101k T (o ciclo tem 69888): dai o flicker.
; Cortes: desenho da estrada em linha (sem chamadas), as 2 linhas de
; cada par partilham o padrao, janela do carro de 3 colunas, tabelas
; alinhadas a paginas, contadores em registos alternativos.
; ---------------------------------------------------------------
          ORG 0x8000

LEVATTR   equ 0x47
GRASSATTR equ 0x67         ; relva do troco 1: papel verde brilhante. Os
                            ; trocos 2 e 3 usam amarelo e branco - a cor
                            ; em vigor vive em (grassc), ver set_grass
                            ; nas bermas (aspecto Spy Hunter). E' so' atributo,
                            ; por isso e' imune ao feixe - muda a cor de um
                            ; bloco 8x8, nunca a forma, e pode escrever-se em
                            ; qualquer altura do frame sem rasgar nada.
VROW0     equ 6            ; 1a linha de caracteres com estrada (par 4*6+2=26)
VROWN     equ 14           ; ate a linha 19 (par 78); a 20 ja e o HUD
HW        equ 40               ; meia-largura (multiplo de 8)
NPAIR     equ 80
CARY      equ 120
CARPAIR   equ 60
CARPEND   equ 72
MAXSPD    equ 5         ; era 7: estava rapido demais, sobretudo em curva
ROADTOP   equ 24         ; horizonte na linha 48. Medido: com dois
                          ; adversarios altos ao mesmo tempo, ROADTOP=12
                          ; ainda rasgava 6 linhas do carro
                          ; DEPOIS da estrada (unica ordem em que a estrada
                          ; nao os apaga) - medido: cada adversario acima do
                          ; carro custa ~4900 T e sem esta folga o desenho do
                          ; carro passava a acontecer atras do feixe de video.
ACC       equ 24
BRK       equ 16
BRK2      equ 32          ; travao dedicado (W): o dobro da desaceleracao
MINX      equ 16
MAXX      equ 224
SEGLEN    equ 48
CRASHT    equ 48         ; ~1s: no Road Fighter recupera-se depressa
CRASHMID  equ 24
MINC      equ 72
MAXC      equ 184
MODE_RACE equ 0
MODE_LONG equ 1
MODE_ARC  equ 2
ZONE_RED  equ 1
ZONE_YEL  equ 2
ZONE_GRN  equ 3
ZATTR_RED equ 0x50          ; cores do semaforo (fundo brilhante, papel)
ZATTR_YEL equ 0x70
ZATTR_GRN equ 0x60
LOGOBUF   equ 0xD800           ; copia do logo: 1792 bitmap + 224 atributos.
                                 ; Subiu de 0xD000 quando os carros novos
                                 ; encheram o espaco: o buffer e' preenchido em
                                 ; execucao pelo save_logo, nao vem na fita, por
                                 ; isso muda-se sem mexer no .tap. Acaba em
                                 ; 0xDFDF, bem abaixo da pilha (0xFFE0)
                                ; (o codigo cresceu para la de 0xC000 nesta
                                ; sessao; margem de folga ate ao proximo teto)
PATPG     equ 0x88             ; pagina das tabelas de padroes

start:    di
          ld sp,0xFFF0
          xor a
          out (0xFE),a
          call det_ay          ; ha. AY? (128K ou 48K com interface)
          call save_logo       ; o logo do ecra de loading fica guardado
newgame:  call menu            ; escolhe o modo -> (mode)
          call game_init
          ei

main:     halt                 ; sem adversarios, o motor original cabe bem
          di                   ; no orcamento de 50fps
          ; ---------- DESENHO (de cima para baixo) ----------
          call hud_digit       ; UM algarismo grande, logo a seguir ao halt
                                 ; (feixe ainda no topo). Desenhar aqui os cinco
                                 ; de uma vez - 3 do relogio + 2 da posicao -
                                 ; custava ~27 linhas antes do carro e chegava a
                                 ; rasgar; um por frame custa 5 e o relogio
                                 ; acaba de se actualizar em 3 frames (60ms)
mh_npos:  call clr_oldcar      ; apagar o carro do ciclo anterior
          call clr_oldopp      ; e os adversarios
          call clr_oldopp2
          call wipe_trans      ; a estrada e' sempre redesenhada por cima
          ld a,ROADTOP
          ld (rp),a            ; par corrente do desenho (o topo nao se desenha)
          call opps_above      ; adversarios acima do carro: a estrada ate ao
                                ; fundo de cada um e so' entao o sprite POR CIMA
                                ; (a ordem inversa deixava o risco central e as
                                ; bermas apaga-los: era o "intermitente ou nao
                                ; se ve"). Do mais longe para o mais perto.
          ld a,CARPEND
          call road_to
          call draw_car
          ld a,NPAIR
          call road_to
          call opps_below      ; os que estao abaixo do carro so' agora: as
                                ; linhas deles so' sao varridas pelo feixe muito
                                ; mais tarde, por isso ficam fora do caminho
                                ; critico ate a' linha do carro
          ; ---------- LOGICA (ja nao se toca no ecra) ----------
          ld a,(crashc)
          or a
          jr nz,mn_crash
          call read_keys
          call chk_crash
          call speed_ctl
          call advance
          call verge_upd       ; ANTES do track_calc: a relva tem de casar com
                                ; a estrada que ACABOU de ser desenhada. Depois
                                ; do track_calc o cenbuf ja' e' o do frame
                                ; seguinte e a relva ficava um frame adiantada
                                ; - desalinhamento bem visivel nas curvas.
                                ; (atributos: fora do caminho do feixe)
          call finish_flag     ; bandeira da meta, tambem so' em atributos
          call track_calc
          call opp_upd         ; adversarios: depois do track_calc (usam o
          call opp_hit         ; cenbuf/larguras acabados de calcular)
          call opp_upd2
          call opp_hit2
          call car_attr        ; cor propria de cada carro (so' atributos)
          ld hl,swipec         ; conta para tras o cooldown de colisao
          ld a,(hl)
          or a
          jr z,mn_hud
          dec (hl)
mn_hud:   call hud_needle
          call arc_lvl_chk     ; arcade: nivel cumprido? reinicia o tempo antes
          call hud_clock       ; do relogio poder chegar a zero por sorte
          call hud_barcnt
          ld a,(busy)          ; ja houve limpeza de transicao? adia
          or a
          jr nz,mh_fim
          ld hl,hudjob
          ld a,(hl)
          bit 2,a              ; barra: unico job que fica para aqui - os
          jr z,mh_fim          ; digitos do relogio (bits 0/1/3) desenham-se
          res 2,(hl)           ; no topo do frame seguinte (ver mh_ntim)
          call hud_bardraw
mh_fim:   xor a
          ld (busy),a
          ei
          call sfx_tick        ; som: no fim do ciclo, no tempo que sobra
          call mus_play        ; e a musica, se houver AY
          ld a,(gover)
          or a
          jp z,main
          call end_screen
          jp newgame
mn_crash: dec a
          ld (crashc),a
          jr nz,mn_c1
          ld a,32              ; acabou o castigo: uns frames de imunidade. O
          ld (swipec),a        ; recentrar podia deixar o carro em cima de um
mn_c1:    ld a,(crashc)        ; adversario parado e provocava logo novo
          cp CRASHMID          ; despiste, dois castigos por um so' erro
          jr nz,mn_c2
          ld a,(crashoff)      ; so' o despiste na relva e' que traz o carro de
          or a                 ; volta ao alcatrao. No embate com um adversario
          jr z,mn_c2           ; o carro fica onde esta': saltar para o meio da
mn_recen: ld a,(cenbuf+66)     ; estrada parecia um reinicio, nao um embate
          sub 8
          ld (carx),a
mn_c2:    call advance         ; o mundo NAO congela: a estrada continua a
          call verge_upd       ; os atributos tambem tem de acompanhar: sem
          call finish_flag     ; isto a relva e a bandeira da meta ficavam
                                 ; congeladas onde estavam quando o despiste
                                 ; comecou - via-se uma fila da bandeira presa
                                 ; no cimo do ecra enquanto a estrada rolava
          call track_calc      ; rolar devagar e os adversarios continuam a
          call opp_upd         ; andar. Congelar tudo ~2s era o que fazia o
          call opp_upd2        ; despiste parecer um bloqueio em vez de um
          jp mn_hud            ; rodopio. (opp_hit fica de fora: crashc>0)

cls_bmp:  ld hl,0x4000
          ld de,0x4001
          ld bc,6143
          ld (hl),0
          ldir
          ret

set_attrs: ld hl,0x5800
          ld de,0x5801
          ld bc,767
          ld (hl),LEVATTR
          ldir
          ret

sep_line: ld a,160
          ld c,0
          call getaddr
          ld b,32
sl_l:     ld (hl),0xFF
          inc l
          djnz sl_l
          ret

; A = linha de pixels, C = coluna -> HL
getaddr:  ld h,0
          ld l,a
          and 0xC0
          rrca
          rrca
          rrca
          or h
          ld h,a
          ld a,l
          and 7
          or h
          or 0x40
          ld h,a
          ld a,l
          and 0x38
          rlca
          rlca
          ld l,a
          ld a,c
          add a,l
          ld l,a
          ret

; ---------------------------------------------------------------
; ESTRADA. A = primeiro par, B = quantos pares.
; Por par: berma esq (3 bytes), traco central (3), berma dta (3),
; cada um nas 2 linhas do par, tudo em linha, sem chamadas.
; O padrao e' o mesmo nos tres (HW multiplo de 8) e vive numa
; pagina alinhada: escolher padrao = por um registo.
; O contador do tracejado vive em A' (registos alternativos).
; ---------------------------------------------------------------
draw_road: ld (curp),a          ; A = primeiro par, B = quantos
          push bc
          exx                  ; ponteiro do cenbuf no conjunto alternativo
          ld c,a
          ld b,0
          ld hl,cenbuf
          add hl,bc
          exx
          add a,a              ; y = par*2
          ld c,0
          call getaddr
          ex de,hl             ; DE = ecra, coluna 0
          ld a,(scrollv)
          ld c,a
          ld a,(curp)
          sub c
          and 31
          ex af,af'            ; A' = fase do tracejado
          pop bc               ; B = contador
dr_pair:  exx
          ld a,(hl)            ; centro deste par
          inc hl
          exx
dr_subw:  sub 40               ; x da berma esquerda (auto-modificado: largura)
          ld c,a
          rrca
          rrca
          rrca
          and 31               ; coluna de x
          push de
          ld l,a               ; guardar a coluna em L por agora
          ld a,c
          and 7
          cp 3
          jr nc,dr_na
          dec l                ; deslocamentos 0..2: janela 1 coluna antes
dr_na:    add a,a
          add a,a
          ld c,a               ; C = entrada da tabela (berma+traco)
          ld a,l
          add a,e
          ld e,a               ; DE -> janela da berma esquerda
          ld l,c
          ld h,PATPG
          ; ---- berma esquerda: agora e' a fronteira verde/preta dos
          ;      atributos (verge_upd), nao uma linha no bitmap. So' se
          ;      avanca o ponteiro como o desenho antigo fazia. ----
          inc e
          inc l
          ; ---- traco central ----
          ld a,e
dr_adv1:  add a,4              ; (auto-modificado: HW/8-1)
          ld e,a
          ex af,af'
          inc a
          and 31
          cp 12                ; 12 pares de traco, 20 de intervalo
          jr nc,dr_off
          ex af,af'
          inc l                ; padrao do traco: entrada+2
          ld a,(hl)
          ld (de),a
          inc d
          ld (de),a
          inc e
          inc l
          ld a,(hl)
          ld (de),a
          dec d
          ld (de),a
          jr dr_right
dr_off:   ex af,af'
          xor a                ; sem traco: limpar (o traco antigo desceu)
          ld (de),a
          inc d
          ld (de),a
          inc e
          ld (de),a
          dec d
          ld (de),a
dr_right: ; ---- berma direita: idem, e' cor de atributo ----
          pop de
          ; avancar as 2 linhas do par
          inc d
          inc d
          ld a,d
          and 7
          jr nz,dr_nx
          ld a,e
          add a,32
          ld e,a
          jr c,dr_nx
          ld a,d
          sub 8
          ld d,a
dr_nx:    dec b
          jp nz,dr_pair
          ret

; A = primeiro par, B = contagem, C = meia-largura em px
; ajusta os 3 imediatos do draw_road e desenha o tramo
draw_run: ld d,a
          ld a,b
          or a
          ret z
          ld a,c
          ld (dr_subw+1),a
          rrca
          rrca
          rrca
          and 31
          dec a
          ld (dr_adv1+1),a
          ld a,d
          jp draw_road

; apaga as bermas antigas dos pares que a fronteira de largura
; atravessou neste ciclo (mesmo principio do clr_oldcar)
wipe_trans:
          ld a,(obpos)
          ld d,a
          ld a,(bpos)
          or a
          jr nz,wt_m
          ld a,d
          or a
          ret z                ; nunca houve fronteira
          ld a,d
          add a,8              ; fronteira saiu por baixo: varrer +8
wt_m:     sub d
          ret z
          ret c
          cp 9
          jr c,wt_k
          ld a,8
wt_k:     ld b,a
          ld a,1
          ld (busy),a
          ld a,(owbot)
          ld c,a               ; largura ANTIGA desses pares
wt_l:     ld a,d
          cp NPAIR
          ret nc
          push bc
          push de
          ld hl,cenbuf
          ld l,d
          ld a,(hl)
          ld e,a               ; E = centro
          ld a,d
          add a,a
          ld d,a               ; D = y
          ld a,(owbot)
          ld c,a
          ld a,e
          sub c                ; x da berma esquerda antiga
          ld e,a
          rrca
          rrca
          rrca
          and 31
          ld b,a
          ld a,e
          and 7
          cp 3
          jr nc,wl_n
          dec b                ; caso da janela recuada
wl_n:     ld c,b
          ld a,d
          call getaddr         ; HL = janela esquerda
          xor a
          ld (hl),a
          inc h
          ld (hl),a
          inc l
          ld (hl),a
          dec h
          ld (hl),a
          dec l
          ld a,(owbot)         ; largura/4 = delta de colunas ate a direita
          rrca
          rrca
          and 63
          add a,l
          ld l,a               ; janela direita (mesmo caso: 2w multiplo de 8)
          xor a
          ld (hl),a
          inc h
          ld (hl),a
          inc l
          ld (hl),a
          dec h
          ld (hl),a
          pop de
          pop bc
          inc d
          djnz wt_l
          ret

; ---------------------------------------------------------------
; CARRO: 3 colunas x 24 linhas, fundido com o fundo (nunca apaga)
; ---------------------------------------------------------------
draw_car: ld a,(crashc)        ; a piscar durante o despiste
          or a
          jr z,dc_norm
          and 8
          jr nz,dc_norm
          ld hl,carzero
          jr dc_addr
dc_norm:  ld a,(carx)
          and 7
          ld l,a
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl            ; x8
          ld e,l
          ld d,h
          add hl,hl
          add hl,hl
          add hl,hl            ; x64
          add hl,de            ; x72
          ld de,carbox
          add hl,de
dc_addr:  push hl              ; HL = sprite (ou carzero)
          ld a,(carx)
          ld (oldcarx),a
          srl a
          srl a
          srl a
          ld c,a
          ld a,CARY
          call getaddr
          ex de,hl             ; DE = ecra
          pop hl               ; HL = sprite
          ld b,24
dc_line:  ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          inc e
          ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          inc e
          ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          dec e
          dec e
          inc d
          ld a,d
          and 7
          jr nz,dc_ok
          ld a,e
          add a,32
          ld e,a
          jr c,dc_ok
          ld a,d
          sub 8
          ld d,a
dc_ok:    djnz dc_line
          ret

; ---------------------------------------------------------------
; apaga as 3 colunas onde o carro esteve no ciclo anterior
; ---------------------------------------------------------------
clr_oldcar: ld a,(oldcarx)
          srl a
          srl a
          srl a
          ld c,a
          ld a,CARY
          call getaddr
          ex de,hl
          ld b,24
cl_line:  xor a
          ld (de),a
          inc e
          ld (de),a
          inc e
          ld (de),a
          dec e
          dec e
          inc d
          ld a,d
          and 7
          jr nz,cl_ok
          ld a,e
          add a,32
          ld e,a
          jr c,cl_ok
          ld a,d
          sub 8
          ld d,a
cl_ok:    djnz cl_line
          ret

; ---------------------------------------------------------------
read_keys: call rd_ctl          ; teclas ou Kempston, conforme (ctrl). O rd_ctl
          ld b,a               ; normaliza para bits ACTIVOS A 1, ao contrario
          ld a,(carx)          ; da matriz do teclado
          bit 1,b
          jr z,rk_p
          sub 6
rk_p:     bit 0,b
          jr z,rk_cl
          add a,6
rk_cl:    cp MINX
          jr nc,rk_a
          ld a,MINX
rk_a:     cp MAXX
          jr c,rk_b
          ld a,MAXX
rk_b:     ld (carx),a
          ret

; O limite do despiste tem de ser o MESMO que se ve': a relva e' pintada
; em blocos de 8px, por isso o alcatrao visivel comeca no multiplo de 8
; imediatamente a' esquerda da berma real. Usar a berma exacta fazia o
; carro despistar-se ainda por cima do preto - o "choque com nada".
chk_crash: ld a,(hwcar)
          ld d,a
          ld a,(cenbuf+66)
          sub d
          and 0xF8             ; inicio da 1a celula de alcatrao
          sub 3                ; o CORPO do carro vai de carx+3 a carx+12; a
          ld b,a               ; janela de 24px do sprite e' quase toda vazia.
          ld a,(carx)          ; Usar a janela despistava com o carro ainda a
          cp b                 ; 11px da relva do lado direito - era o grosso
          jr c,cr_hit          ; dos "choques com nada"
          ld a,(cenbuf+66)
          add a,d
          or 7                 ; fim da ultima celula de alcatrao
          sub 11               ; corpo acaba em carx+12: despiste so' quando
          ld b,a               ; carx+12 passa mesmo o ultimo pixel de alcatrao
          ld a,(carx)
          cp b
          ret c
cr_hit:   call sfx_crash
          ld a,(crasht)        ; quanto tempo se fica sem controlo: depende da
          ld (crashc),a        ; dificuldade
          ld a,1               ; despiste FORA da estrada: este e o unico que
          ld (crashoff),a      ; obriga a repor o carro no alcatrao
          ld hl,0x0100         ; nao para de todo: escorrega devagar
          ld (spd),hl
          ret

speed_ctl: call rd_ctl
          ld b,a
          bit 3,b               ; travao dedicado (A ou baixo): mais forte que
          jr z,sc_noB           ; so' largar o acelerador, para travagens
          ld hl,(spd)           ; rapidas antes das curvas
          ld de,BRK2
          or a
          sbc hl,de
          jr nc,sc_set
          ld hl,0
          jr sc_set
sc_noB:   bit 2,b               ; acelerador (Q, cima ou fogo)
          ret z                 ; nem acelerador nem travao: velocidade fica
          ld hl,(spd)           ; exactamente igual, sem desaceleracao nenhuma
          ld de,ACC
          add hl,de
          ld a,(maxspd)         ; tecto por troco: 5, 6, 7. O ponteiro tem
          ld b,a                ; escala absoluta (0..7), por isso sobe mais a
          ld a,h                ; cada troco sem se mexer no mostrador
          cp b
          jr c,sc_set
          ld h,b
          ld l,0
sc_set:   ld (spd),hl
          ret

advance:  ld hl,(sacc)
          ld de,(spd)
          add hl,de
          ld a,h
          ld h,0
          ld (sacc),hl
          ld (steps),a
          or a
          ret z
          ld b,a
adv_l:    push bc
          call track_step
          ld hl,scrollv
          inc (hl)
          ld a,(hl)
          and 31
          ld (hl),a
          pop bc
          djnz adv_l
          ret

track_step: ld hl,(segidx)      ; aplicar o dx do segmento ATUAL primeiro:
          ld (tseg),hl         ; o passo que cruza a fronteira pertence ao
          call seg_dx          ; segmento antigo (coerente com o track_calc)
          ld hl,(cbot)
          add hl,de
          ld a,h
          cp MINC
          jr nc,ts_c1
          ld hl,MINC*256
ts_c1:    ld a,h
          cp MAXC
          jr c,ts_c2
          ld hl,MAXC*256
ts_c2:    ld (cbot),hl
          ld hl,phase          ; e so agora avancar a fase/segmento
          inc (hl)
          ld a,(hl)
          cp SEGLEN
          ret c
          ld (hl),0
          ld hl,(segidx)
          inc hl
          ld a,h
          cp NSEG/256
          jr c,ts_g
          jr nz,ts_h
          ld a,l
          cp NSEG & 255
          jr c,ts_g
ts_h:     ld hl,0              ; o mapa e' um anel nos dois modos jogaveis
          ld a,1               ; (o arcade tem 9 niveis = 3 voltas: o clamp
          ld (lapnew),a        ; antigo congelava a pista no fim da volta 1)
          ld (segidx),hl       ; lapnew avisa o hud_barcnt: barra volta a 0
          ret
ts_g:     ld (segidx),hl
          ret

; ---------------------------------------------------------------
; FORMA DA ESTRADA (fase de logica): integra a curvatura de baixo
; para cima. Ponteiro em BC (pagina alinhada), contador em A'.
; ---------------------------------------------------------------
; ---------------------------------------------------------------
; FORMA DA ESTRADA: integra a curvatura de baixo para cima.
; Interior minimo: o fim de cada segmento e' um valor de C
; pre-calculado (auto-modificado), sem contador por iteracao.
; ---------------------------------------------------------------
track_calc: ld a,(bpos)
          ld (obpos),a         ; memoria para a limpeza do proximo ciclo
          ld a,(wbot)
          ld (owbot),a
          xor a
          ld (bpos),a          ; por defeito: sem fronteira visivel
          ld hl,(segidx)
          ld (tseg),hl
          call seg_dx
          ld a,(tsegw)
          ld (wbot),a          ; largura em baixo
          ld (wtop),a
          ld (curw),a
          ld a,(phase)
          ld (tcnt),a
          ld bc,cenbuf+NPAIR-1
          ld hl,(cbot)
tc_seg:   push hl              ; n = min(SEGLEN - tcnt, pares restantes)
          ld a,SEGLEN
          ld hl,tcnt
          sub (hl)
          ld l,a
          ld a,c
          inc a
          cp l
          jr nc,tcs_a
          ld l,a
tcs_a:    ld a,c
          sub l                ; cstop = C - n (0xFF = fim do ecra)
          ld (tc_cp+1),a
          pop hl
tc_l:     ld a,h
          cp MINC
          jr nc,tc1
          ld a,MINC
tc1:      cp MAXC
          jr c,tc2
          ld a,MAXC
tc2:      ld (bc),a
          dec c
          add hl,de
          ld a,c
tc_cp:    cp 0                 ; (auto-modificado: fim do segmento)
          jp nz,tc_l
          inc a
          jr z,tc_end          ; C=0xFF: buffer completo
          xor a                ; segmento seguinte
          ld (tcnt),a
          push hl
          ld hl,(tseg)
          inc hl
          ld a,h               ; alem do fim: fica no ultimo
          cp NSEG/256
          jr c,tcs_g
          jr nz,tcs_h
          ld a,l
          cp NSEG & 255
          jr c,tcs_g
tcs_h:    ld hl,0              ; anel: a estrada a frente mostra o inicio
tcs_g:    ld (tseg),hl         ; da volta seguinte (nos dois modos)
          call seg_dx
          ld a,(tsegw)         ; a largura mudou?
          ld hl,curw
          cp (hl)
          jr z,tcs_b
          ld (hl),a
          ld hl,bpos
          ld a,(hl)
          or a
          jr nz,tcs_b          ; so a primeira fronteira (por regra, max 1)
          ld a,c
          inc a
          ld (hl),a            ; pares < bpos: wtop; >= bpos: wbot
          ld a,(tsegw)
          ld (wtop),a
tcs_b:    pop hl
          jp tc_seg
tc_end:   ld a,(bpos)          ; largura no arco do carro (par 66)
          cp 67
          ld a,(wbot)
          jr c,tc_hw
          ld a,(wtop)
tc_hw:    ld (hwcar),a
          ret


seg_dx:   push hl              ; a segtab tem so. o dx: 2 bytes por segmento.
          push bc              ; A largura vem do troco e a cor era so. do
          ld hl,(tseg)         ; semaforo, que deixou de existir
          add hl,hl
          ld bc,segtab
          add hl,bc
          ld e,(hl)
          inc hl
          ld d,(hl)
          ld a,(lvlw)
          ld (tsegw),a
          pop bc
          pop hl
          ret
lvlw:     db 60

; ================== HUD (fundo do ecra) ======================
; separador y=160; barra y=163..166; mostrador+timer+nivel y=168..191.
; Cores escritas UMA vez no init. Desenho no fim do ciclo: o feixe
; ja passou o fundo, por isso nunca ha tearing aqui.
; =============================================================
HUDATTR   equ 0x47
BARATTR   equ 0x45
TIMEATTR  equ 0x46
KMATTR    equ 0x45         ; ciano brilhante sobre preto
RACESECS  equ 0x0060         ; BCD: 60 segundos por terco
NSEG      equ 1100
RACELEN   equ 0xC000         ; distancia total da corrida

hud_init: ld hl,0x5A84         ; linha 20: banda da barra (cols 4..27) a ciano
          ld b,24
hi_b:     ld (hl),BARATTR
          inc hl
          djnz hi_b
          ld hl,0x5AAC         ; timer a amarelo: 3 linhas x 6 colunas
          ld b,3
hi_t:     push bc
          push hl
          ld b,6
hi_t2:    ld (hl),TIMEATTR
          inc hl
          djnz hi_t2
          pop hl
          ld de,32
          add hl,de
          pop bc
          djnz hi_t
          ld hl,dialpts        ; mostrador: XOR sobre preto = acende
          call xorpts
          xor a
          ld (nedold),a
          call ned_draw        ; ponteiro na posicao 0
          call mark_speed      ; marcas fixas dos limiares vermelho/amarelo
          call bar_marks       ; marcas dos cinco trocos (fica depois das tabelas)
          ld hl,0x5AB3         ; metros a ciano, linha 21 coluna 19 (4 digitos)
          ld b,3
hi_k:     push bc
          push hl
          ld b,8
hi_k2:    ld (hl),KMATTR
          inc hl
          djnz hi_k2
          pop hl
          ld de,32
          add hl,de
          pop bc
          djnz hi_k
          call hud_top         ; faixa livre por cima da estrada
          jp draw_time

xorpts:   ld e,(hl)
          inc hl
          ld d,(hl)
          inc hl
          ld a,d
          or e
          ret z
          ld a,(hl)
          inc hl
          ld c,a
          ld a,(de)
          xor c
          ld (de),a
          jr xorpts

; ---- ponteiro: so mexe quando a velocidade muda ----
hud_needle:
          ld hl,(spd)
          add hl,hl            ; indice = spd/128 (0..14)
          ld a,h
          ld b,a
          ld a,(nedold)
          cp b
          ret z
          call ned_draw        ; XOR do antigo -> apaga
          ld a,b
          ld (nedold),a
ned_draw: cp 15
          ret nc
          ld l,a
          ld h,0
          add hl,hl
          ld de,nedtab
          add hl,de
          ld a,(hl)
          inc hl
          ld h,(hl)
          ld l,a
          jp xorpts

; ---- marcas fixas no mostrador: meio (indice 7) e 3/4 (indice 11) da
;      escala do ponteiro (0-14) - exactamente os mesmos limiares usados
;      pelo zone_effect. Risca (OR permanente, nao XOR) so' os ultimos 5
;      pontos de cada lista - a ponta do ponteiro, sem chegar ao pivot -
;      sem mudar a cor do atributo (fica so' a risca, sem quadrado). ---
mark_speed: ld hl,ned7
          call ms_mark
          ld hl,ned11
          call ms_mark
          ret

ms_mark:  push hl
          ld b,0                ; B = quantos pontos tem a lista
ms_cnt:   ld e,(hl)
          inc hl
          ld d,(hl)
          inc hl
          ld a,d
          or e
          jr z,ms_cdone
          inc hl
          inc b
          jr ms_cnt
ms_cdone: ld a,b
          sub 5                 ; so' riscar os ultimos 5 pontos
          jr nc,ms_skb
          xor a                 ; lista com menos de 5: risca-a toda
ms_skb:   ld b,a
          pop hl                ; volta ao inicio da lista
ms_skip:  ld a,b
          or a
          jr z,ms_draw
          inc hl
          inc hl
          inc hl
          dec b
          jr ms_skip
ms_draw:  ld e,(hl)
          inc hl
          ld d,(hl)
          inc hl
          ld a,d
          or e
          ret z
          ld a,(hl)
          ld c,a
          ld a,(de)
          or c                  ; OR permanente (nao XOR: nao deve apagar)
          ld (de),a
          inc hl
          jr ms_draw

; ---- bigdraw: A = digito, C = coluna; 24 linhas no fundo ----
bigdraw:  ld l,a
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; hl = digito*16
          ld d,h
          ld e,l               ; de = digito*16 (o save tinha de ser aqui,
          add hl,hl            ; nao logo a seguir ao 1o dobro - isso dava
          add hl,de            ; HL = digito*48    digito*34, nao *48, e cada
                                 ; digito lia cada vez mais atrasado na tabela
                                 ; (8 e 9 acabavam por ler dados de outro sitio)
          ld de,bigdig
          add hl,de
          ld a,(bigyd)         ; normalmente 0x50/0xA0 = y=168 (HUD)
          ld d,a
          ld a,(bigye)
          add a,c
          ld e,a
          ld b,24
bd_l:     ld a,(hl)
          ld (de),a
          inc hl
          inc e
          ld a,(hl)
          ld (de),a
          inc hl
          dec e
          inc d
          ld a,d
          and 7
          jr nz,bd_n
          ld a,e
          add a,32
          ld e,a
          ld a,d
          sub 8
          ld d,a
bd_n:     djnz bd_l
          ret

; ---- draw_point: igual ao bigdraw mas sem indexar por digito (C = coluna) ----
draw_point: ld hl,ptglyph
          ld d,0x50            ; y=168, terco de baixo
          ld a,0xA0
          add a,c
          ld e,a
          ld b,24
dp_l:     ld a,(hl)
          ld (de),a
          inc hl
          inc e
          ld a,(hl)
          ld (de),a
          inc hl
          dec e
          inc d
          ld a,d
          and 7
          jr nz,dp_n
          ld a,e
          add a,32
          ld e,a
          ld a,d
          sub 8
          ld d,a
dp_n:     djnz dp_l
          ret

; ---- timer (BCD): digitos desenhados um por ciclo, quando mudam ----
; --- destino dos algarismos grandes: relogio no HUD, posicao na faixa de cima ---
big_hud:  ld a,0x50            ; y=168, terco de baixo
          ld (bigyd),a
          ld a,0xA0
          ld (bigye),a
          ret
big_top:  ld a,0x40            ; y=16, faixa livre por cima da estrada
          ld (bigyd),a
          ld a,0x40
          ld (bigye),a
          ret

draw_time:
          call draw_cent
          call draw_tens
draw_units:
          call big_hud
          ld a,(tsecs)
          and 15
          ld c,16
          jp bigdraw
draw_tens:
          call big_hud
          ld a,(tsecs)
          rrca
          rrca
          rrca
          rrca
          and 15
          ld c,14
          jp bigdraw
draw_cent:
          call big_hud
          ld a,(tsecs+1)
          and 15
          ld c,12
          jp bigdraw


; --- metros percorridos, fonte grande, 4 digitos, encostado a direita.
;     race: metros dentro do nivel (0-1100), que e' o que interessa para a
;     meta e nao transborda os 4 digitos (o odom satura aos 4095m) ---
draw_km:  ld a,(mode)
          cp MODE_RACE
          jr nz,dk_tot
          ld hl,hudjob         ; na corrida o que interessa e' a POSICAO, e nao
          set 4,(hl)           ; se desenha aqui: isto corre na fase de logica,
          set 5,(hl)           ; ja' com o feixe perto da linha dos digitos.
          ret                   ; marca-se o job para o topo do frame seguinte
dk_tot:   ld hl,(odom)
dk_go:    ld b,4
dkm_sh:   srl h
          rr l
          djnz dkm_sh          ; hl = odom/16 = metros
          ld de,1000
          xor a
dkm_d1:   or a
          sbc hl,de
          jr c,dkm_d1e
          inc a
          jr dkm_d1
dkm_d1e:  add hl,de
          ld (km_d1),a         ; milhares
          ld de,100
          xor a
dkm_d2:   or a
          sbc hl,de
          jr c,dkm_d2e
          inc a
          jr dkm_d2
dkm_d2e:  add hl,de
          ld (km_d2),a         ; centenas
          ld de,10
          xor a
dkm_d3:   or a
          sbc hl,de
          jr c,dkm_d3e
          inc a
          jr dkm_d3
dkm_d3e:  add hl,de
          ld (km_d3),a         ; dezenas
          ld a,l
          ld (km_d4),a         ; unidades
          ld a,(km_d1)
          ld c,19
          call bigdraw
          ld a,(km_d2)
          ld c,21
          call bigdraw
          ld a,(km_d3)
          ld c,23
          call bigdraw
          ld a,(km_d4)
          ld c,25
          jp bigdraw

km_d1:    db 0
km_d2:    db 0
km_d3:    db 0
km_d4:    db 0

hud_clock:
          ld a,(tfr)
          dec a
          ld (tfr),a
          ret nz
          ld a,50              ; 50 frames = 1 segundo (50fps, sem adversarios)
          ld (tfr),a
          call draw_km         ; quilometros percorridos, ao vivo (os dois modos)
          ld a,(tsecs+1)
          ld b,a
          ld a,(tsecs)
          or b
          ret z                ; ja em zero (game over trata-se depois)
          ld a,(tsecs)
          sub 1
          daa                  ; BCD
          ld (tsecs),a
          ld hl,hudjob
          set 0,(hl)           ; unidades mudaram
          cp 0x99              ; emprestimo: baixou a centena
          jr nz,hc_t
          ld a,b
          dec a
          ld (tsecs+1),a
          set 1,(hl)
          set 3,(hl)
          jr hc_dt
hc_t:     and 15
          cp 9
          jr nz,hc_dt
          set 1,(hl)           ; as dezenas tambem
hc_dt:                          ; desenho real feito no topo de main (mh_ntim),
                                 ; logo a seguir ao halt - o mesmo frame em que
                                 ; os bits ficam marcados, mas o mais cedo
                                 ; possivel nesse frame (maxima margem antes do
                                 ; feixe chegar a linha dos digitos)
hc_z:     ld a,(tsecs+1)
          ld b,a
          ld a,(tsecs)
          or b
          ret nz
          ld a,2               ; tempo esgotado: game over
          ld (gover),a
          ret

; ---- race/arcade: niveis de 1100m, cada vez com menos tempo ----
arc_lvl_chk:
          ld hl,(lvldist)      ; progresso DENTRO do nivel (relativo)
          ld a,(steps)
          ld e,a
          ld d,0
          add hl,de
          ld (lvldist),hl
          ld de,17600          ; 1100m em pares
          or a
          sbc hl,de
          ret c                ; nivel ainda nao cumprido
          ld hl,0
          ld (lvldist),hl      ; o proximo conta do zero
          call time_bank       ; guardar o tempo que sobrou: aqui o tsecs ainda
                                 ; e' o do troco que acabou, o arc_li ja' o
                                 ; substitui pelo do troco seguinte
          ld a,(arclvl)
          inc a
          ld (arclvl),a
          cp RACELVLS+1
          jr nc,arc_fim
          call level_break     ; intervalo + relva/largura/velocidade do novo
          ld a,(arclvl)
          jr arc_li
arc_fim:  ld a,(racepos)       ; cumpriu os cinco trocos a tempo: so' ganha
          cp 1                 ; quem chegar em PRIMEIRO
          ld a,2
          jr nz,arc_go
          ld a,1
arc_go:   ld (gover),a
          ret
arc_li:   dec a                ; indice 0-based na tabela (2 bytes por troco:
          add a,a              ; unidades/dezenas em BCD, depois a centena)
          push af
          call rt_base         ; a tabela e' uma por dificuldade
          pop af
          ld e,a
          ld d,0
          add hl,de
          ld a,(hl)
          ld (tsecs),a
          inc hl
          ld a,(hl)
          ld (tsecs+1),a
          ld hl,hudjob         ; redesenhar os 3 digitos do relogio
          set 0,(hl)
          set 1,(hl)
          set 3,(hl)
          ret
RACELVLS  equ 5            ; a corrida sao 5 trocos de 1100m
                            ; um por cada largura de pista da segtab
RACESTART equ 30           ; parte-se em 30.o; ver posmin (o espaco antes das
                            ; tabelas alinhadas esta' cheio, a tabela esta' la')
; os tempos por troco vivem agora na racetime, ao fundo do ficheiro: sao tres
; tabelas, uma por dificuldade, e aqui em cima o espaco antes das tabelas
; alinhadas em 0x8800 esta' contado ao byte
arclvl:   db 0
racepos:  db RACESTART ; posicao na corrida (1 = primeiro)
lvldist:  dw 0        ; pares percorridos dentro do nivel atual (relativo:
                       ; o alvo absoluto em odom transbordava 16 bits aos
                       ; ~4095m e os niveis fundos caiam em cascata)

; ---- barra de progresso: contador sempre; desenho e' um trabalho ----
;      mostra o progresso dentro da volta actual (0-1100 segmentos),
;      dividida em 3 tercos (cada terco = um nivel no arcade) ----
hud_barcnt:
          ld hl,(odom)         ; odometro total (satura, nunca recua)
          ld a,(steps)         ; pares reais avancados este frame (o mesmo
          ld e,a               ; valor que o advance usou p'ra mover o carro -
                                ; usar spd+1 direto perdia a fraccao a cada
                                ; frame e o odometro desviava-se da posicao real
          ld d,0
          add hl,de
          jr nc,hb_od
          ld hl,0xFFFF
hb_od:    ld (odom),hl
          xor a                ; a barra e' a CORRIDA toda, nao a volta ao mapa:
          ld (lapnew),a        ; a volta do mapa (52800 pares) acontece a meio
                                 ; dos 88000 da corrida e antes reiniciava a
                                 ; barra a meio caminho
hb_acc:   ld hl,(barres)       ; residuo de pares dentro do pixel atual
          add hl,de            ; de = steps (ainda de cima)
          ld de,458            ; 458 pares = 1 pixel (5 x 17600 / 192)
          or a
          sbc hl,de
          jr c,hb_keep         ; nao chegou ao pixel seguinte
          ld (barres),hl
          ld a,(dist+1)
          cp 191               ; tecto: nunca desenhar alem do fim da barra
          jr nc,hb_cmp
          inc a
          ld (dist+1),a
          jr hb_cmp
hb_keep:  add hl,de            ; repor: fica no mesmo pixel
          ld (barres),hl
hb_cmp:   ld a,(dist+1)
          ld hl,barold
          cp (hl)
          ret z                ; sem mudanca desde o ultimo desenho
          ld hl,hudjob
          set 2,(hl)
          ret
hud_bardraw:
          ld a,(dist+1)
          ld c,a
          ld (barold),a
          ld b,4               ; 4 linhas: y=163..166
          ld d,0x53
hb_row:   push bc
          ld e,0x84            ; barra nas colunas 4..27
          ld a,c
          rrca
          rrca
          rrca
          and 31
          ld b,a               ; bytes cheios
          or a
          jr z,hb_p
hb_f:     ld a,0xFF
          ld (de),a
          inc e
          djnz hb_f
hb_p:     ld a,c
          and 7
          ld hl,barmsk
          add a,l
          ld l,a
          ld a,(hl)            ; byte parcial
          ld (de),a
          inc e
hb_z:     ld a,e
          cp 0x9C
          jr nc,hb_nx
          xor a
          ld (de),a
          inc e
          jr hb_z
hb_nx:    pop bc
          inc d
          djnz hb_row
          ret

barmsk:   db 0,0x80,0xC0,0xE0,0xF0,0xF8,0xFC,0xFE

carx:     db 128
oldcarx:  db 128
scrollv:  db 0
curp:     db 0
cbot:     dw 0x8000
phase:    db 0
segidx:   dw 0
tseg:     dw 0
tcnt:     db 0
spd:      dw 0
sacc:     dw 0
crashc:   db 0
crashoff: db 0        ; 1 = o despiste foi fora da estrada (unico que recentra)
swipec:   db 0        ; frames ate poder haver nova rocadela/colisao
nedold:   db 0
tsecs:    dw RACESECS
tfr:      db 50
dist:     dw 0
barres:   dw 0        ; residuo de pares dentro do pixel atual da barra
lapnew:   db 0        ; posto a 1 pelo track_step quando a volta da a volta
barold:   db 255
cknext:   db 0x40
mode:     db 0
score:    dw 0
odom:     dw 0
gover:    db 0
tsegw:    db 40
tsegc:    db 0
bpos:     db 0
obpos:    db 0
wtop:     db 40
wbot:     db 40
owbot:    db 40
curw:     db 40
hwcar:    db 40
carcolor: db 0
tcut:     db 0
rp:       db 0
rt_e:     db 0
steps:    db 0
oact:     db 0
oy:       dw 0
ox:       db 128
olane:    db 0
olanev:   db 0        ; deriva lateral (0 = anda a direito)
ospd:     dw 0x0480
oybot:    db 0
olines:   db 0
osprptr:  dw 0        ; endereco do sprite (advbox_m + shift*48), pre-calculado
ooldx:    db 128
ooldy:    db 0
ooldn:    db 0
onextd:   dw 0        ; distancia (odom) para o proximo nascimento (vaga 1)
ospw:     db 60
oact2:    db 0
oy2:      dw 0
ox2:      db 128
olane2:   db 0
olanev2:  db 0
ospd2:    dw 0x0480
oybot2:   db 0
olines2:  db 0
ooldx2:   db 128
ooldy2:   db 0
ooldn2:   db 0
onextd2:  dw 0        ; distancia (odom) para o proximo nascimento (vaga 2)
rndv:     dw 0x1234
hudjob:   db 0
busy:     db 0
oflip:    db 0
bigyd:    db 0x50              ; onde o bigdraw poe os digitos grandes: por
bigye:    db 0xA0              ; omissao y=168 (HUD). O ecra de intervalo
                                 ; sobe-os para o meio e repoe no fim.

; ---------------- tabelas alinhadas ----------------
          DEFS PATPG*256-$,0
          ORG PATPG*256
patw:
          db 0,224,0,192,0,112,0,96
          db 0,56,0,48,28,0,24,0
          db 14,0,12,0,7,0,6,0
          db 3,128,3,0,1,192,1,128

          DEFS 0x8900-$,0
          ORG 0x8900
cenbuf:   ds NPAIR

carzero:  ds 72
carbox:
          db 0,0,0,7,224,0,15,240,0,19,200,0
          db 31,248,0,31,248,0,8,16,0,24,24,0
          db 15,240,0,15,240,0,31,248,0,31,248,0
          db 31,248,0,12,48,0,7,224,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,3,240,0,7,248,0,9,228,0
          db 15,252,0,15,252,0,4,8,0,12,12,0
          db 7,248,0,7,248,0,15,252,0,15,252,0
          db 15,252,0,6,24,0,3,240,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,1,248,0,3,252,0,4,242,0
          db 7,254,0,7,254,0,2,4,0,6,6,0
          db 3,252,0,3,252,0,7,254,0,7,254,0
          db 7,254,0,3,12,0,1,248,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,252,0,1,254,0,2,121,0
          db 3,255,0,3,255,0,1,2,0,3,3,0
          db 1,254,0,1,254,0,3,255,0,3,255,0
          db 3,255,0,1,134,0,0,252,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,126,0,0,255,0,1,60,128
          db 1,255,128,1,255,128,0,129,0,1,129,128
          db 0,255,0,0,255,0,1,255,128,1,255,128
          db 1,255,128,0,195,0,0,126,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,63,0,0,127,128,0,158,64
          db 0,255,192,0,255,192,0,64,128,0,192,192
          db 0,127,128,0,127,128,0,255,192,0,255,192
          db 0,255,192,0,97,128,0,63,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,31,128,0,63,192,0,79,32
          db 0,127,224,0,127,224,0,32,64,0,96,96
          db 0,63,192,0,63,192,0,127,224,0,127,224
          db 0,127,224,0,48,192,0,31,128,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,15,192,0,31,224,0,39,144
          db 0,63,240,0,63,240,0,16,32,0,48,48
          db 0,31,224,0,31,224,0,63,240,0,63,240
          db 0,63,240,0,24,96,0,15,192,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0

bigdig:
          db 0,0,0,0,63,0,63,0,63,0,192,192,192,192,192,192
          db 195,192,195,192,195,192,204,192,204,192,204,192,240,192,240,192
          db 240,192,192,192,192,192,192,192,63,0,63,0,63,0,0,0
          db 0,0,0,0,12,0,12,0,12,0,60,0,60,0,60,0
          db 12,0,12,0,12,0,12,0,12,0,12,0,12,0,12,0
          db 12,0,12,0,12,0,12,0,63,0,63,0,63,0,0,0
          db 0,0,0,0,63,0,63,0,63,0,192,192,192,192,192,192
          db 0,192,0,192,0,192,3,0,3,0,3,0,12,0,12,0
          db 12,0,48,0,48,0,48,0,255,192,255,192,255,192,0,0
          db 0,0,0,0,255,192,255,192,255,192,3,0,3,0,3,0
          db 12,0,12,0,12,0,3,0,3,0,3,0,0,192,0,192
          db 0,192,192,192,192,192,192,192,63,0,63,0,63,0,0,0
          db 0,0,0,0,3,0,3,0,3,0,15,0,15,0,15,0
          db 51,0,51,0,51,0,195,0,195,0,195,0,255,192,255,192
          db 255,192,3,0,3,0,3,0,3,0,3,0,3,0,0,0
          db 0,0,0,0,255,192,255,192,255,192,192,0,192,0,192,0
          db 255,0,255,0,255,0,0,192,0,192,0,192,0,192,0,192
          db 0,192,192,192,192,192,192,192,63,0,63,0,63,0,0,0
          db 0,0,0,0,15,0,15,0,15,0,48,0,48,0,48,0
          db 192,0,192,0,192,0,255,0,255,0,255,0,192,192,192,192
          db 192,192,192,192,192,192,192,192,63,0,63,0,63,0,0,0
          db 0,0,0,0,255,192,255,192,255,192,0,192,0,192,0,192
          db 3,0,3,0,3,0,12,0,12,0,12,0,48,0,48,0
          db 48,0,48,0,48,0,48,0,48,0,48,0,48,0,0,0
          db 0,0,0,0,63,0,63,0,63,0,192,192,192,192,192,192
          db 192,192,192,192,192,192,63,0,63,0,63,0,192,192,192,192
          db 192,192,192,192,192,192,192,192,63,0,63,0,63,0,0,0
          db 0,0,0,0,63,0,63,0,63,0,192,192,192,192,192,192
          db 192,192,192,192,192,192,63,192,63,192,63,192,0,192,0,192
          db 0,192,3,0,3,0,3,0,60,0,60,0,60,0,0,0
          ; indice 10 = glifo em branco (usado para apagar um slot do HUD)
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

ptglyph:  ; ponto decimal: fora da tabela indexada de bigdraw (o passo dessa
          ; tabela nao e' 48 bytes, por isso um "digito 10" nao caia aqui)
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,3,192,3,192,3,192,0,0,0,0

dialpts:
          db 228,86,8
          db 228,83,8
          db 228,81,4
          db 196,86,2
          db 196,84,1
          db 197,82,128
          db 197,80,32
          db 165,86,8
          db 165,85,2
          db 166,84,128
          db 166,83,16
          db 166,82,4
          db 167,82,128
          db 167,82,16
          db 167,83,4
          db 168,84,128
          db 168,85,32
          db 168,86,8
          db 200,80,2
          db 201,82,128
          db 201,84,64
          db 201,86,32
          db 233,81,16
          db 233,83,8
          db 233,86,8
          db 233,86,128
          db 167,86,128
          db 229,86,128
          db 233,86,64
          db 167,85,128
          db 228,86,1
          db 233,86,32
          db 167,84,128
          db 228,86,2
          db 0,0,0
ned0:
          db 230,86,4
          db 230,86,8
          db 230,86,16
          db 230,86,32
          db 230,86,64
          db 230,86,128
          db 229,86,1
          db 229,86,2
          db 229,86,4
          db 229,86,8
          db 229,86,16
          db 229,86,32
          db 0,0,0
ned1:
          db 230,85,4
          db 230,85,8
          db 230,85,16
          db 230,85,32
          db 230,84,64
          db 230,84,128
          db 229,84,1
          db 229,84,2
          db 229,84,4
          db 229,83,8
          db 229,83,16
          db 229,83,32
          db 0,0,0
ned2:
          db 230,85,4
          db 230,84,8
          db 230,84,16
          db 230,83,16
          db 230,83,32
          db 230,83,64
          db 230,82,128
          db 229,82,1
          db 229,81,2
          db 229,81,4
          db 229,80,8
          db 229,80,16
          db 0,0,0
ned3:
          db 230,84,2
          db 230,84,4
          db 230,83,8
          db 230,82,16
          db 230,81,32
          db 230,80,64
          db 230,80,128
          db 197,87,1
          db 197,86,2
          db 197,85,4
          db 0,0,0
ned4:
          db 230,84,2
          db 230,83,2
          db 230,82,4
          db 230,81,8
          db 230,80,16
          db 198,87,32
          db 198,86,32
          db 198,85,64
          db 198,84,128
          db 197,83,1
          db 0,0,0
ned5:
          db 230,83,1
          db 230,82,2
          db 230,81,2
          db 230,81,4
          db 230,80,4
          db 198,87,4
          db 198,86,8
          db 198,85,8
          db 198,84,16
          db 198,83,16
          db 198,82,32
          db 198,81,32
          db 0,0,0
ned6:
          db 230,83,1
          db 230,82,1
          db 230,81,1
          db 230,80,1
          db 198,87,2
          db 198,86,2
          db 198,85,2
          db 198,84,2
          db 198,83,2
          db 198,82,4
          db 198,81,4
          db 198,80,4
          db 0,0,0
ned7:
          db 231,83,128
          db 231,82,128
          db 231,81,128
          db 231,80,128
          db 199,87,128
          db 199,86,128
          db 199,85,128
          db 199,84,128
          db 199,83,128
          db 199,82,128
          db 199,81,128
          db 199,80,128
          db 0,0,0
ned8:
          db 231,83,64
          db 231,82,64
          db 231,81,64
          db 231,80,64
          db 199,87,32
          db 199,86,32
          db 199,85,32
          db 199,84,32
          db 199,83,32
          db 199,82,16
          db 199,81,16
          db 199,80,16
          db 0,0,0
ned9:
          db 231,83,64
          db 231,82,32
          db 231,81,32
          db 231,81,16
          db 231,80,16
          db 199,87,16
          db 199,86,8
          db 199,85,8
          db 199,84,4
          db 199,83,4
          db 199,82,2
          db 199,81,2
          db 0,0,0
ned10:
          db 231,84,32
          db 231,83,32
          db 231,82,16
          db 231,81,8
          db 231,80,4
          db 199,87,2
          db 199,86,2
          db 199,85,1
          db 200,84,128
          db 200,83,64
          db 0,0,0
ned11:
          db 231,84,32
          db 231,84,16
          db 231,83,8
          db 231,82,4
          db 231,81,2
          db 231,80,1
          db 232,80,128
          db 200,87,64
          db 200,86,32
          db 200,85,16
          db 0,0,0
ned12:
          db 231,85,16
          db 231,84,8
          db 231,84,4
          db 231,83,4
          db 231,83,2
          db 231,83,1
          db 232,82,128
          db 232,82,64
          db 232,81,32
          db 232,81,16
          db 232,80,8
          db 232,80,4
          db 0,0,0
ned13:
          db 231,85,16
          db 231,85,8
          db 231,85,4
          db 231,85,2
          db 231,84,1
          db 232,84,128
          db 232,84,64
          db 232,84,32
          db 232,84,16
          db 232,83,8
          db 232,83,4
          db 232,83,2
          db 0,0,0
ned14:
          db 231,86,16
          db 231,86,8
          db 231,86,4
          db 231,86,2
          db 231,86,1
          db 232,86,128
          db 232,86,64
          db 232,86,32
          db 232,86,16
          db 232,86,8
          db 232,86,4
          db 232,86,2
          db 0,0,0
nedtab:  dw ned0,ned1,ned2,ned3,ned4,ned5,ned6,ned7,ned8,ned9,ned10,ned11,ned12,ned13,ned14

; ---- mapa da corrida de 3 minutos ----
segtab:
          dw 65515
          dw 65515
          dw 65517
          dw 65520
          dw 65525
          dw 65531
          dw 0
          dw 11
          dw 21
          dw 32
          dw 37
          dw 37
          dw 29
          dw 16
          dw 3
          dw 65525
          dw 65515
          dw 65507
          dw 65507
          dw 65512
          dw 65517
          dw 65523
          dw 65528
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 3
          dw 5
          dw 8
          dw 8
          dw 5
          dw 3
          dw 65531
          dw 65523
          dw 65515
          dw 65512
          dw 65517
          dw 65525
          dw 0
          dw 11
          dw 21
          dw 29
          dw 29
          dw 24
          dw 19
          dw 11
          dw 0
          dw 65525
          dw 65517
          dw 65515
          dw 65515
          dw 65520
          dw 65531
          dw 5
          dw 13
          dw 16
          dw 13
          dw 11
          dw 5
          dw 0
          dw 0
          dw 3
          dw 8
          dw 8
          dw 8
          dw 8
          dw 5
          dw 3
          dw 0
          dw 65533
          dw 65528
          dw 65520
          dw 65512
          dw 65504
          dw 65496
          dw 65496
          dw 65504
          dw 65517
          dw 65531
          dw 8
          dw 19
          dw 21
          dw 16
          dw 8
          dw 0
          dw 65525
          dw 65520
          dw 65517
          dw 65517
          dw 65517
          dw 65517
          dw 65525
          dw 65533
          dw 5
          dw 13
          dw 21
          dw 29
          dw 32
          dw 29
          dw 27
          dw 24
          dw 19
          dw 11
          dw 65533
          dw 65523
          dw 65512
          dw 65501
          dw 65496
          dw 65496
          dw 65504
          dw 65512
          dw 65520
          dw 65528
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 3
          dw 5
          dw 8
          dw 8
          dw 8
          dw 8
          dw 3
          dw 0
          dw 0
          dw 8
          dw 16
          dw 24
          dw 32
          dw 32
          dw 27
          dw 13
          dw 0
          dw 65525
          dw 65523
          dw 65528
          dw 0
          dw 8
          dw 16
          dw 19
          dw 16
          dw 11
          dw 5
          dw 3
          dw 0
          dw 0
          dw 65533
          dw 65533
          dw 0
          dw 5
          dw 11
          dw 16
          dw 24
          dw 27
          dw 24
          dw 19
          dw 13
          dw 8
          dw 3
          dw 65533
          dw 65528
          dw 65523
          dw 65517
          dw 65515
          dw 65515
          dw 65520
          dw 65531
          dw 5
          dw 16
          dw 21
          dw 21
          dw 19
          dw 13
          dw 8
          dw 3
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 65533
          dw 65528
          dw 65523
          dw 65517
          dw 65512
          dw 65507
          dw 65507
          dw 65512
          dw 65517
          dw 65523
          dw 65528
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 3
          dw 5
          dw 8
          dw 8
          dw 5
          dw 3
          dw 65531
          dw 65525
          dw 65523
          dw 65528
          dw 3
          dw 13
          dw 27
          dw 35
          dw 37
          dw 32
          dw 24
          dw 16
          dw 8
          dw 3
          dw 0
          dw 0
          dw 65533
          dw 65528
          dw 65520
          dw 65509
          dw 65499
          dw 65488
          dw 65485
          dw 65491
          dw 65504
          dw 65523
          dw 5
          dw 24
          dw 35
          dw 37
          dw 32
          dw 24
          dw 16
          dw 8
          dw 3
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 65533
          dw 65528
          dw 65523
          dw 65517
          dw 65512
          dw 65507
          dw 65507
          dw 65512
          dw 65517
          dw 65523
          dw 65528
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 3
          dw 8
          dw 16
          dw 24
          dw 32
          dw 40
          dw 43
          dw 40
          dw 32
          dw 24
          dw 13
          dw 3
          dw 65531
          dw 65528
          dw 65528
          dw 65528
          dw 65533
          dw 0
          dw 0
          dw 65531
          dw 65525
          dw 65520
          dw 65512
          dw 65509
          dw 65509
          dw 65509
          dw 65509
          dw 65509
          dw 65509
          dw 65507
          dw 65507
          dw 65512
          dw 65517
          dw 65523
          dw 65528
          dw 0
          dw 5
          dw 8
          dw 8
          dw 8
          dw 8
          dw 3
          dw 0
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 3
          dw 0
          dw 65533
          dw 65528
          dw 65528
          dw 65528
          dw 65528
          dw 65533
          dw 3
          dw 8
          dw 8
          dw 8
          dw 8
          dw 3
          dw 65533
          dw 65528
          dw 65528
          dw 65528
          dw 65528
          dw 65531
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 3
          dw 8
          dw 16
          dw 24
          dw 32
          dw 40
          dw 40
          dw 32
          dw 19
          dw 5
          dw 65528
          dw 65515
          dw 65509
          dw 65515
          dw 65525
          dw 0
          dw 11
          dw 19
          dw 21
          dw 13
          dw 0
          dw 65523
          dw 65509
          dw 65501
          dw 65499
          dw 65504
          dw 65512
          dw 65523
          dw 65533
          dw 5
          dw 11
          dw 13
          dw 19
          dw 19
          dw 19
          dw 16
          dw 11
          dw 5
          dw 65531
          dw 65523
          dw 65515
          dw 65512
          dw 65515
          dw 65520
          dw 65531
          dw 5
          dw 16
          dw 24
          dw 29
          dw 32
          dw 29
          dw 27
          dw 21
          dw 13
          dw 3
          dw 65525
          dw 65515
          dw 65504
          dw 65499
          dw 65499
          dw 65504
          dw 65512
          dw 65520
          dw 65528
          dw 0
          dw 8
          dw 16
          dw 24
          dw 32
          dw 40
          dw 43
          dw 40
          dw 32
          dw 24
          dw 13
          dw 0
          dw 65525
          dw 65517
          dw 65512
          dw 65507
          dw 65507
          dw 65512
          dw 65520
          dw 65531
          dw 5
          dw 16
          dw 24
          dw 29
          dw 29
          dw 24
          dw 16
          dw 5
          dw 65528
          dw 65515
          dw 65504
          dw 65496
          dw 65493
          dw 65496
          dw 65504
          dw 65515
          dw 65525
          dw 0
          dw 8
          dw 13
          dw 19
          dw 21
          dw 24
          dw 27
          dw 29
          dw 32
          dw 29
          dw 21
          dw 11
          dw 65533
          dw 65520
          dw 65507
          dw 65499
          dw 65501
          dw 65509
          dw 65523
          dw 65533
          dw 8
          dw 13
          dw 11
          dw 5
          dw 65533
          dw 65531
          dw 65528
          dw 65528
          dw 65531
          dw 0
          dw 8
          dw 13
          dw 19
          dw 21
          dw 21
          dw 16
          dw 5
          dw 65533
          dw 65525
          dw 65523
          dw 65523
          dw 65523
          dw 65525
          dw 65523
          dw 65523
          dw 65523
          dw 65525
          dw 65533
          dw 5
          dw 16
          dw 21
          dw 21
          dw 21
          dw 21
          dw 21
          dw 21
          dw 24
          dw 29
          dw 29
          dw 24
          dw 19
          dw 13
          dw 8
          dw 3
          dw 0
          dw 65533
          dw 65528
          dw 65520
          dw 65512
          dw 65504
          dw 65496
          dw 65493
          dw 65499
          dw 65512
          dw 65528
          dw 8
          dw 24
          dw 37
          dw 43
          dw 40
          dw 32
          dw 21
          dw 8
          dw 65528
          dw 65512
          dw 65499
          dw 65488
          dw 65483
          dw 65483
          dw 65488
          dw 65501
          dw 65515
          dw 65528
          dw 0
          dw 5
          dw 8
          dw 3
          dw 65533
          dw 65528
          dw 65528
          dw 65528
          dw 65528
          dw 65531
          dw 65533
          dw 3
          dw 8
          dw 13
          dw 19
          dw 27
          dw 37
          dw 43
          dw 43
          dw 40
          dw 35
          dw 21
          dw 0
          dw 65517
          dw 65501
          dw 65491
          dw 65485
          dw 65488
          dw 65499
          dw 65509
          dw 65523
          dw 0
          dw 13
          dw 27
          dw 37
          dw 48
          dw 53
          dw 53
          dw 48
          dw 37
          dw 27
          dw 16
          dw 8
          dw 3
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 65533
          dw 65528
          dw 65520
          dw 65512
          dw 65504
          dw 65496
          dw 65493
          dw 65499
          dw 65512
          dw 65528
          dw 8
          dw 24
          dw 37
          dw 43
          dw 40
          dw 29
          dw 16
          dw 0
          dw 65520
          dw 65507
          dw 65499
          dw 65501
          dw 65509
          dw 65523
          dw 65533
          dw 8
          dw 13
          dw 13
          dw 11
          dw 5
          dw 3
          dw 0
          dw 0
          dw 65533
          dw 65531
          dw 65528
          dw 65528
          dw 65528
          dw 65528
          dw 65531
          dw 65533
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 3
          dw 8
          dw 13
          dw 19
          dw 24
          dw 27
          dw 21
          dw 8
          dw 65531
          dw 65520
          dw 65509
          dw 65504
          dw 65504
          dw 65512
          dw 65520
          dw 65523
          dw 65525
          dw 65528
          dw 65533
          dw 0
          dw 0
          dw 3
          dw 5
          dw 5
          dw 5
          dw 8
          dw 16
          dw 24
          dw 29
          dw 29
          dw 24
          dw 13
          dw 3
          dw 65528
          dw 65523
          dw 65523
          dw 65523
          dw 65525
          dw 65523
          dw 65520
          dw 65515
          dw 65512
          dw 65515
          dw 65517
          dw 65525
          dw 65533
          dw 5
          dw 8
          dw 8
          dw 8
          dw 5
          dw 5
          dw 8
          dw 16
          dw 24
          dw 32
          dw 35
          dw 32
          dw 24
          dw 16
          dw 8
          dw 0
          dw 0
          dw 3
          dw 8
          dw 8
          dw 5
          dw 0
          dw 65528
          dw 65520
          dw 65515
          dw 65512
          dw 65515
          dw 65523
          dw 65531
          dw 3
          dw 5
          dw 8
          dw 5
          dw 65533
          dw 65525
          dw 65517
          dw 65515
          dw 65515
          dw 65523
          dw 0
          dw 13
          dw 27
          dw 32
          dw 29
          dw 19
          dw 5
          dw 65531
          dw 65520
          dw 65517
          dw 65520
          dw 65523
          dw 65525
          dw 65523
          dw 65523
          dw 65520
          dw 65520
          dw 65525
          dw 65531
          dw 3
          dw 5
          dw 8
          dw 8
          dw 5
          dw 3
          dw 65533
          dw 65528
          dw 65523
          dw 65517
          dw 65512
          dw 65509
          dw 65515
          dw 65525
          dw 0
          dw 11
          dw 21
          dw 24
          dw 19
          dw 11
          dw 5
          dw 0
          dw 65531
          dw 65533
          dw 5
          dw 16
          dw 21
          dw 27
          dw 29
          dw 27
          dw 19
          dw 5
          dw 65533
          dw 65525
          dw 65523
          dw 65525
          dw 65528
          dw 65531
          dw 65525
          dw 65520
          dw 65512
          dw 65501
          dw 65499
          dw 65504
          dw 65520
          dw 0
          dw 16
          dw 29
          dw 32
          dw 27
          dw 13
          dw 0
          dw 65523
          dw 65515
          dw 65515
          dw 65517
          dw 65523
          dw 65528
          dw 0
          dw 8
          dw 13
          dw 19
          dw 24
          dw 29
          dw 29
          dw 21
          dw 11
          dw 0
          dw 65525
          dw 65515
          dw 65507
          dw 65507
          dw 65515
          dw 65525
          dw 0
          dw 11
          dw 19
          dw 21
          dw 16
          dw 5
          dw 65531
          dw 65523
          dw 65520
          dw 65523
          dw 65525
          dw 65531
          dw 0
          dw 0
          dw 65533
          dw 65531
          dw 0
          dw 8
          dw 16
          dw 27
          dw 37
          dw 40
          dw 35
          dw 24
          dw 16
          dw 8
          dw 0
          dw 0
          dw 3
          dw 8
          dw 5
          dw 0
          dw 65528
          dw 65515
          dw 65501
          dw 65488
          dw 65483
          dw 65483
          dw 65488
          dw 65499
          dw 65509
          dw 65520
          dw 65528
          dw 0
          dw 8
          dw 16
          dw 27
          dw 37
          dw 48
          dw 53
          dw 53
          dw 48
          dw 37
          dw 27
          dw 16
          dw 8
          dw 3
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 0
          dw 65533
          dw 65531
          dw 65528
          dw 65525
          dw 65523
          dw 65517
          dw 65517
          dw 65517
          dw 65517
          dw 65517
          dw 65515
          dw 65517
          dw 65517
          dw 65520
          dw 65525
          dw 65531
          dw 5
          dw 11
          dw 13
          dw 11
          dw 3
          dw 65533
          dw 65525
          dw 65523
          dw 65523
          dw 65525
          dw 65531
          dw 65533
          dw 3
          dw 5
          dw 11
          dw 13
          dw 13
          dw 11
          dw 3
          dw 65533
          dw 65528
          dw 65528
          dw 65533
          dw 3
          dw 8
          dw 8
          dw 3
          dw 65531
          dw 65523
          dw 65520
          dw 65523
          dw 65525
          dw 65531
          dw 0
          dw 0
          dw 65533
          dw 65528
          dw 65528
          dw 65528
          dw 65531
          dw 3
          dw 11
          dw 19
          dw 21
          dw 24
          dw 21
          dw 13
          dw 5
          dw 65531
          dw 65523
          dw 65515
          dw 65509
          dw 65507
          dw 65504
          dw 65507
          dw 65512
          dw 65520
          dw 65531
          dw 8
          dw 21
          dw 32
          dw 37
          dw 35
          dw 27
          dw 13
          dw 0
          dw 65525
          dw 65523
          dw 65528
          dw 0
          dw 8
          dw 13
          dw 13
          dw 5
          dw 65531
          dw 65520
          dw 65517
          dw 65520
          dw 65525
          dw 65531
          dw 65533
          dw 0
          dw 65531
          dw 65523
          dw 65517
          dw 65520
          dw 65531
          dw 5
          dw 19
          dw 29
          dw 35
          dw 32
          dw 24
          dw 16
          dw 8
          dw 5
          dw 5
          dw 8
          dw 8
          dw 8
          dw 5
          dw 65533
          dw 65523
          dw 65512
          dw 65504
          dw 65496
          dw 65493
          dw 65496
          dw 65504
          dw 65512
          dw 65520
          dw 65528
          dw 65533
          dw 0
          dw 3
          dw 5
          dw 8
          dw 8
          dw 8
          dw 8
          dw 5
          dw 5
          dw 5
          dw 11
          dw 16
          dw 19
          dw 19
          dw 13
          dw 11
          dw 5
          dw 0
          dw 0
          dw 3
          dw 8
          dw 8
          dw 8
          dw 8
          dw 5
          dw 3
          dw 65533
          dw 65531
          dw 65528
          dw 65528
          dw 65528
          dw 65528
          dw 65531
          dw 65533
          dw 0
          dw 0
          dw 3
          dw 5
          dw 11
          dw 13
          dw 13
          dw 11
          dw 3
          dw 65531
          dw 65520
          dw 65515
          dw 65517
          dw 65523
          dw 65531
          dw 0
          dw 3
          dw 3
          dw 65531
          dw 65523
          dw 65515
          dw 65512

; ===============================================================
; MENU, ECRAS DE FIM, RECORDES
; ===============================================================
; --- guardar/repor o logo do ecra de loading (7 linhas de topo) ---
save_logo: ld hl,0x4000
          ld de,LOGOBUF
          ld b,8
sl_b:     push bc
          ld bc,224            ; 7 linhas de caracteres por bloco
          ldir
          ld a,l               ; saltar a linha de caracteres 7
          add a,32
          ld l,a
          jr nc,sl_nc
          inc h
sl_nc:    pop bc
          djnz sl_b
          ld hl,0x5800
          ld de,LOGOBUF+1792
          ld bc,224
          ldir
          ret

show_logo: ld hl,LOGOBUF
          ld de,0x4000
          ld b,8
sh_b:     push bc
          ld bc,224
          ldir
          ld a,e
          add a,32
          ld e,a
          jr nc,sh_nc
          inc d
sh_nc:    pop bc
          djnz sh_b
          ld hl,LOGOBUF+1792
          ld de,0x5800
          ld bc,224
          ldir
          ret

; --- A = atributo -> pinta o ecra todo ---
fill_attrs: ld hl,0x5800
          ld de,0x5801
          ld (hl),a
          ld bc,767
          ldir
          ret

; --- A = caracter, B = linha (0-23), C = coluna -> fonte da ROM ---
prchar:   push bc
          push de
          ld l,a
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          ld de,0x3C00
          add hl,de
          ex de,hl             ; DE = fonte
          ld a,b
          and 0x18
          add a,0x40
          ld h,a
          ld a,b
          and 7
          rrca
          rrca
          rrca
          add a,c
          ld l,a               ; HL = ecra
          ld b,8
pc_l:     ld a,(de)
          ld (hl),a
          inc de
          inc h
          djnz pc_l
          pop de
          pop bc
          ret

; --- HL = texto terminado em 0, B = linha, C = coluna ---
prstr:    ld a,(hl)
          or a
          ret z
          push hl
          call prchar
          pop hl
          inc hl
          inc c
          jr prstr

; --- HL = numero, B = linha, C = coluna -> 5 digitos ---
prnum:    ld de,10000
          call pn_dig
          ld de,1000
          call pn_dig
          ld de,100
          call pn_dig
          ld de,10
          call pn_dig
          ld a,l
          add a,'0'
          jp prchar
pn_dig:   ld a,'0'
pn_l:     or a
          sbc hl,de
          jr c,pn_e
          inc a
          jr pn_l
pn_e:     add hl,de
          push hl
          call prchar
          pop hl
          inc c
          ret

; --- tsecs (BCD, 3 digitos) -> HL binario ---
bcd2bin:  ld hl,0
          ld a,(tsecs+1)
          and 15
          jr z,b2_t
          ld de,100
b2_c:     add hl,de
          dec a
          jr nz,b2_c
b2_t:     ld a,(tsecs)
          rrca
          rrca
          rrca
          rrca
          and 15
          jr z,b2_u
          ld de,10
b2_d:     add hl,de
          dec a
          jr nz,b2_d
b2_u:     ld a,(tsecs)
          and 15
          ld e,a
          ld d,0
          add hl,de
          ret

; --- esperar tecla (com solta previa) ---
wait_key: ld bc,0x00FE
          in a,(c)
          and 31
          cp 31
          jr nz,wait_key
wk_p:     ld bc,0x00FE
          in a,(c)
          and 31
          cp 31
          jr z,wk_p
          ret

; ---------------- MENU ----------------
menu:     ld a,1               ; entrada normal: o jingle toca
          jr mn_draw
menu_nj:  xor a                ; regresso de um submenu: sem jingle, senao
mn_draw:  ld (jingf),a         ; tocava a cada tecla carregada
          di
          call cls_bmp
          ld a,0x47
          call fill_attrs
          call show_logo
          ld hl,t_m1
          ld bc,0x0908
          call prstr
          ld hl,t_m4
          ld bc,0x0A08
          call prstr
          ld hl,t_m2           ; 3 DIFFICULTY: <nome>
          ld bc,0x0B08
          call prstr
          ld a,(diff)          ; 0 = NORMAL (por omissao), 1 = EASY, 2 = HARD
          ld hl,t_dnorm
          or a
          jr z,mn_dn
          ld hl,t_deasy
          dec a
          jr z,mn_dn
          ld hl,t_dhard
mn_dn:    ld bc,0x0B17
          call prstr
          ld hl,t_m3           ; 4 CONTROL: <nome>
          ld bc,0x0C08
          call prstr
          ld hl,t_ckeys
          ld a,(ctrl)
          or a
          jr z,mn_cn
          ld hl,t_ckemp
mn_cn:    ld bc,0x0C14
          call prstr
          ld hl,t_m5           ; 5 MUSIC: ON/OFF (so' tem efeito em 128K)
          ld bc,0x0D08
          call prstr
          ld hl,t_mon
          ld a,(musopt)
          or a
          jr nz,mn_mn
          ld hl,t_moff
mn_mn:    ld bc,0x0D12
          call prstr
          ld hl,t_msel
          ld bc,0x0F0A
          call prstr
          ld hl,t_mtec
          ld bc,0x1304
          call prstr
          ld hl,t_mcred        ; o credito, em baixo e centrado
          ld bc,0x1502
          call prstr
          ld a,(jingf)
          or a
          call nz,jingle
          ei
mn_w:     ld bc,0xF7FE         ; teclas 1..5
          in a,(c)
          cpl
          and 31
          jr z,mn_w
          rrca
          jr c,mn_s            ; 1: comeca a corrida
          rrca
          jr c,mn_instr        ; 2: instrucoes
          rrca
          jr c,mn_diff         ; 3: dificuldade
          rrca
          jr c,mn_ctrl         ; 4: teclas / Kempston
          jr mn_mus            ; 5: musica
mn_s:     ld a,MODE_RACE
          ld (mode),a
mn_r:     ld bc,0xF7FE         ; esperar que solte
          in a,(c)
          and 31
          cp 31
          jr nz,mn_r
          ret
mn_instr: call show_instructions
          jp menu_nj           ; volta a mostrar o menu (jp: o desenho do menu
                                 ; poe o menu_nj fora do alcance de um jr)
mn_diff:  ld a,(diff)          ; EASY -> NORMAL -> HARD -> EASY
          inc a
          cp 3
          jr c,mn_ds
          xor a
mn_ds:    ld (diff),a
          jr mn_again
mn_ctrl:  ld a,(ctrl)
          xor 1
          ld (ctrl),a
          jr mn_again
mn_mus:   ld a,(musopt)
          xor 1
          ld (musopt),a
mn_again: call mn_r            ; solta a tecla e redesenha com o valor novo
          jp menu_nj

; ---------------- ECRA DE INSTRUCOES ----------------
show_instructions: di
          call cls_bmp
          ld a,0x47
          call fill_attrs
          ld hl,t_i1
          ld bc,0x0208
          call prstr
          ld hl,t_i2
          ld bc,0x0502
          call prstr
          ld hl,t_i2b
          ld bc,0x0602
          call prstr
          ld hl,t_i2c
          ld bc,0x0702
          call prstr
          ld hl,t_i3
          ld bc,0x0802
          call prstr
          ld hl,t_i4
          ld bc,0x0A04
          call prstr
          ld hl,t_i5
          ld bc,0x0B04
          call prstr
          ld hl,t_i6
          ld bc,0x0C04
          call prstr
          ld hl,t_i7
          ld bc,0x0D04
          call prstr
          ld hl,t_i8
          ld bc,0x0E04
          call prstr
          ld hl,t_i9
          ld bc,0x1202
          call prstr
          ei
          jp wait_key          ; qualquer tecla continua (espera soltar e premir)

; ---------------- ARRANQUE DE UMA PARTIDA ----------------
game_init: di
          call cls_bmp
          call set_attrs
          call sep_line
          ld a,128
          ld (carx),a
          ld (oldcarx),a
          ld hl,0x8000
          ld (cbot),hl
          ld hl,0
          ld (segidx),hl
          ld (dist),hl
          ld (barres),hl
          ld (odom),hl
          ld (score),hl
          ld (spd),hl
          ld (sacc),hl
          xor a
          ld (lapnew),a
          ld (phase),a
          ld (crashc),a
          ld (swipec),a
          ld (gover),a
          ld (hudjob),a
          ld (busy),a
          ld (scrollv),a
          ld (bpos),a
          ld (obpos),a
          ld a,50              ; 50 frames = 1 segundo (50fps, sem adversarios)
          ld (tfr),a
          ld a,255
          ld (barold),a
          ld a,0x40
          ld (cknext),a
          xor a
          ld (oact),a          ; sem adversarios em pista
          ld (olines),a
          ld (ooldn),a
          ld (oact2),a
          ld (olines2),a
          ld (ooldn2),a
          ld hl,300            ; ~19m ate ao primeiro adversario
          ld (onextd),hl
          ld hl,700            ; vaga 2 desfasada da vaga 1
          ld (onextd2),hl
          ld hl,(23672)        ; semente: tempo que o jogador levou no menu
          ld a,h
          or l
          jr nz,gi_s
          ld hl,0x1234
gi_s:     ld (rndv),hl
          ld a,1               ; troco 1
          ld (arclvl),a
          ld a,RACESTART       ; a corrida comeca em ultimo
          ld (racepos),a
          ld hl,0
          ld (lvldist),hl      ; distancia percorrida DENTRO do nivel
          ld (tbank),hl        ; tempo poupado, para a pontuacao
          call diff_apply      ; espacamentos e duracao do despiste
          call rt_base         ; tempo do 1o troco desta dificuldade
          ld a,(hl)
          inc hl
          ld h,(hl)
          ld l,a
gi_t:     ld (tsecs),hl
          call stage_intro     ; STAGE 1 e contagem, antes de montar a pista
          call cls_bmp
          call set_attrs
          call sep_line
          call track_calc
          call hud_init
          call mus_init        ; a musica recomeca a cada corrida
          call set_grass       ; relva do troco 1 + pintar tudo no 1o frame
          call pos_clear       ; apaga os slots antigos do HUD
          jp draw_pos          ; e mostra logo a posicao de partida

; ---------------- PONTUACAO ----------------
; os dois modos pontuam pela distancia percorrida (odometro/16 = metros)
; A pontuacao junta as quatro coisas que medem uma boa corrida: distancia
; percorrida, tempo poupado em cada troco, lugares ganhos, e a dificuldade
; em que se correu.
;   metros            (odom/16)              ate' 4095 (o odom satura a 0xFFFF)
;   segundos poupados x20                    ate' ~2100
;   lugares ganhos    (31-posicao) x100      ate' 3000
;   tudo x2 no EASY, x3 no NORMAL, x4 no HARD, depois a dividir por 2
; O maximo da' ~18400, bem dentro dos 5 digitos que o prnum mostra.
calc_score: ld hl,(odom)
          ld b,4
cs_sh:    srl h
          rr l
          djnz cs_sh           ; HL = metros percorridos
          push hl
          ld hl,(tbank)        ; segundos poupados x20
          ld d,h
          ld e,l
          add hl,hl            ; x2
          add hl,hl            ; x4
          add hl,de            ; x5
          add hl,hl            ; x10
          add hl,hl            ; x20
          pop de
          add hl,de            ; + metros
          push hl
          ld a,RACESTART+1     ; lugares ganhos desde a partida
          ld hl,racepos
          sub (hl)
          jr nc,cs_pos
          xor a                ; defensivo: nunca negativo
cs_pos:   ld b,a
          ld hl,0
          ld de,100            ; x100 a somar: isto corre uma vez por corrida
          or a
          jr z,cs_pd
cs_pl:    add hl,de
          djnz cs_pl
cs_pd:    pop de
          add hl,de
          ld d,h               ; --- dificuldade: x2/x3/x4 e depois a metade ---
          ld e,l
          add hl,hl            ; x2 (o EASY fica-se por aqui)
          ld a,(diff)
          or a
          jr z,cs_nor          ; 0 = NORMAL: x3
          dec a
          jr z,cs_end          ; 1 = EASY: x2
          add hl,de            ; 2 = HARD: x4
          add hl,de
          jr cs_end
cs_nor:   add hl,de
cs_end:   srl h
          rr l
          ld (score),hl
          ret

; --- soma ao tbank os segundos que sobraram no troco que acabou. O tsecs
;     esta' em BCD: dezenas e unidades no 1o byte, centenas no 2o ---
tbank:    dw 0
time_bank: ld a,(tsecs)
          ld c,a
          and 15               ; unidades
          ld e,a
          ld a,c
          rrca
          rrca
          rrca
          rrca
          and 15               ; dezenas
          ld b,a
          or a
          jr z,tb_cent
tb_dez:   ld a,e
          add a,10
          ld e,a
          djnz tb_dez
tb_cent:  ld d,0
          ld a,(tsecs+1)       ; as tabelas nunca chegam a's centenas, mas
          or a                 ; fica coerente se um dia chegarem
          jr z,tb_add
          ld b,a
tb_c1:    ld a,e
          add a,100
          ld e,a
          jr nc,tb_c2
          inc d
tb_c2:    djnz tb_c1
tb_add:   ld hl,(tbank)
          add hl,de
          ld (tbank),hl
          ret

; Cada recorde tem 5 bytes: 2 de pontuacao e 3 de nome. Ve' se a pontuacao
; entra no top 3; se entrar, abre-lhe espaco empurrando as de baixo e guarda
; em hs_slot o endereco da entrada conquistada (0 se nao entrou).
hs_upd:   call calc_score
          ld hl,0
          ld (hs_slot),hl
          ld ix,hs_tab
          ld b,3
hu_l:     ld l,(ix+0)
          ld h,(ix+1)
          ex de,hl
          ld hl,(score)
          or a
          sbc hl,de
          jr z,hu_nx
          jr nc,hu_in          ; a nossa e' maior: e' aqui que entra
hu_nx:    ld de,5
          add ix,de
          djnz hu_l
          ret                   ; nao entrou no top 3
hu_in:    push ix              ; empurra as de baixo uma posicao para tras
          pop de
          ld hl,hs_tab+10
          or a
          sbc hl,de            ; HL = bytes a mover = (2-i)*5
          ld b,h
          ld c,l
          ld a,b
          or c
          jr z,hu_set          ; entrou no ultimo lugar: nada a empurrar
          push ix
          pop hl
          add hl,bc
          dec hl               ; ultimo byte da origem (copia-se de tras p'ra
          push hl              ; a frente, senao os blocos sobrepunham-se)
          ld de,5
          add hl,de
          ex de,hl
          pop hl
          lddr
hu_set:   ld hl,(score)
          ld (ix+0),l
          ld (ix+1),h
          ld (ix+2),'A'        ; nome por omissao, caso nao se escreva nada
          ld (ix+3),'A'
          ld (ix+4),'A'
          push ix
          pop hl
          ld (hs_slot),hl
          ret

; --- tres letras para o nome. O/P mudam a letra, qualquer outra confirma ---
ask_name: ld hl,(hs_slot)
          ld a,h
          or l
          ret z                ; nao entrou no top: nao pergunta nada
          push hl
          call cls_bmp         ; ecra proprio: o de fim ja' esta' cheio
          ld a,0x47
          call fill_attrs
          ld hl,t_newrec
          ld bc,0x0A0B
          call prstr
          ld hl,t_name
          ld bc,0x0D03
          call prstr
          ei
          pop hl
          inc hl
          inc hl               ; HL = primeira letra do nome
          ld c,0               ; indice da letra corrente
an_k:     push hl
          push bc
          call an_show
          call kb_get          ; teclado todo: devolve a letra em ASCII,
          pop bc               ; 13 = confirmar, 8 = apagar
          pop hl
          cp 13
          jr z,an_done
          cp 8
          jr z,an_del
          ld (hl),a            ; escreve e passa a' letra seguinte
          inc hl
          inc c
          ld a,c
          cp 3
          jr c,an_k
an_done:  push hl
          push bc
          call an_show         ; deixa as tres letras desenhadas
          pop bc
          pop hl
          di
          ret
an_del:   ld a,c               ; ja' na primeira: nada a apagar
          or a
          jr z,an_k
          dec c
          dec hl
          ld (hl),'A'
          jr an_k

; --- mostra as tres letras na linha 16, colunas 14..16 ---
an_show:  ld hl,(hs_slot)
          inc hl
          inc hl
          ld b,16              ; B = linha 16 (o prchar quer a linha em B)
          ld c,14              ; C = primeira coluna
          ld d,3               ; contador a' parte: o B esta' ocupado
ans_l:    ld a,(hl)
          push hl
          push de
          call prchar          ; preserva BC
          pop de
          pop hl
          inc hl
          inc c
          dec d
          jr nz,ans_l
          ret

t_name:   db "TYPE NAME  0=DEL  ENTER=OK",0
t_newrec: db "NEW RECORD!",0
hs_slot:  dw 0

; --- B = linha da 1a entrada, C = coluna ---
hs_show:  ld ix,hs_tab
          ld d,3               ; 3 lugares
          ld e,'1'
hs_l:     push de
          ld a,e
          call prchar
          inc c
          ld a,'.'
          call prchar
          inc c
          inc c
          ld a,(ix+2)          ; as tres letras do nome
          call prchar
          inc c
          ld a,(ix+3)
          call prchar
          inc c
          ld a,(ix+4)
          call prchar
          inc c
          inc c
          ld l,(ix+0)
          ld h,(ix+1)
          push bc
          call prnum
          pop bc
          ld a,c               ; repor a coluna do inicio da linha
          sub 7
          ld c,a
          inc b                ; linha seguinte
          ld de,5              ; 5 bytes por recorde
          add ix,de
          pop de
          inc e
          dec d
          jr nz,hs_l
          ret

; ---------------- ECRAS DE FIM ----------------
end_screen: di
          call mus_hush
          call hs_upd
          call ask_name        ; se entrou no top 3, pede as tres letras
          call cls_bmp
          ld a,(gover)
          cp 2
          jr z,es_over
; ------ vitoria / fim dos 3 minutos ------
          ld a,0x70            ; preto sobre amarelo vivo (como o loading)
          call fill_attrs
          call draw_trophy
          ld hl,t_win
          ld bc,0x0004
          call prstr
          ld b,17
          jr es_com
; ------ game over ------
es_over:  ld a,0x78            ; preto sobre branco (fundo da imagem)
          call fill_attrs
          call draw_defeated
          ld hl,t_over
          ld bc,0x000B         ; linha 0: acima da imagem, sem sobrepor
          call prstr
          ld b,17
; ------ comum: pontuacao, recordes, prompt ------
es_com:   push bc
          ld hl,t_pts
          pop bc
          push bc
          ld c,6
          call prstr
          pop bc
          push bc
          ld c,15
          ld hl,(score)
          call prnum
          pop bc
          inc b
          push bc
          ld hl,t_rec
          ld c,6
          call prstr
          pop bc
          inc b
          ld c,8
          call hs_show
          ld a,(mode)          ; na corrida diz-se em que lugar se acabou
          cp MODE_RACE
          jr nz,es_nop
          ld hl,t_fpos
          ld bc,0x1604         ; "FINAL POSITION" ocupa 14 colunas: 4..17
          call prstr
          call prpos
es_nop:   ld hl,t_key
          ld bc,0x1704
          call prstr
          ei
          call wait_key
          ret

; --- lugar final em dois algarismos da fonte normal, linha 22 colunas 18/19.
;     A linha 20 esta' ocupada pela lista de recordes e a etiqueta chega a'
;     coluna 16, por isso os algarismos tinham de sair dali ---
prpos:    ld a,(racepos)
          ld b,0
pp_t:     cp 10
          jr c,pp_d
          sub 10
          inc b
          jr pp_t
pp_d:     push af              ; A = unidades
          ld a,b
          or a
          jr z,pp_u            ; abaixo de 10 nao se escreve a dezena
          add a,48
          ld b,22
          ld c,19              ; algarismos DEPOIS do rotulo (antes escreviam
          call prchar          ; o prchar preserva BC (o prstr depende disso)
pp_u:     pop af
          add a,48
          ld b,22
          ld c,20              ; por cima das ultimas letras)
          jp prchar

; --- imagem da vitoria: 160x128 nas colunas 6-25, linhas 8-135 ---
draw_trophy: ld de,vitimg
          ld a,8
          ld b,128
dt_l:     push bc
          push af
          ld c,6
          call getaddr
          ex de,hl
          ld bc,20
          ldir
          ex de,hl
          pop af
          inc a
          pop bc
          djnz dt_l
          ret

t_m1:     db "1  RACE",0
t_m4:     db "2  INSTRUCTIONS",0
t_m2:     db "3  DIFFICULTY:",0
t_m3:     db "4  CONTROL:",0
t_deasy:  db "EASY",0
t_dnorm:  db "NORMAL",0
t_dhard:  db "HARD",0
t_ckeys:  db "KEYS",0
t_ckemp:  db "KEMPSTON",0
t_m5:     db "5  MUSIC:",0
t_mon:    db "ON",0
t_moff:   db "OFF",0
t_msel:   db "PRESS 1 TO 5",0
t_mtec:   db "Q=GAS  A=BRAKE  O/P=TURN",0
t_mcred:  db "A game by MMM with Claude AI",0
t_i1:     db "COOPER RUN",0
t_i2:     db "Q=GAS   A=BRAKE   O/P=TURN",0
t_i2b:    db "KEMPSTON: UP OR FIRE=GAS,",0
t_i2c:    db "DOWN=BRAKE, LEFT/RIGHT=TURN.",0
t_i3:     db "FIVE STAGES OF 1100 METRES.",0
t_i4:     db "BEAT THE CLOCK ON EVERY ONE",0
t_i5:     db "AND FINISH FIRST TO WIN.",0
t_i6:     db "OVERTAKE THE RIVAL CARS -",0
t_i7:     db "THE OTHERS ARE JUST TRAFFIC.",0
t_i8:     db "A HEAD-ON HIT STOPS YOU.",0
t_i9:     db "PRESS ANY KEY TO CONTINUE",0
t_win:    db "FINISH!",0
t_over:   db "GAME OVER",0
t_pts:    db "POINTS",0
t_rec:    db "RECORDS",0
t_fpos:   db "FINAL POSITION",0
t_key:    db "PRESS ANY KEY",0

hs_tab:   dw 60
          db "ACE"
          dw 40
          db "BOB"
          dw 20
          db "CAT"

vitimg:
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,240,0,7,128,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,1,48,0,14,64,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,80,0,5,64,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,2,247,255,247,160,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,2,147,0,124,160,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,2,254,127,127,160,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,2,150,62,60,160,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,2,134,58,56,160,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,1,134,58,56,192,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,1,68,62,57,64,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,1,70,62,57,64,0,0,0,0
          db 0,0,0,0,0,0,0,7,255,254,0,0,198,62,57,128,0,0,0,0
          db 0,0,0,0,0,0,31,240,0,0,255,192,170,62,98,128,0,0,0,0
          db 0,0,0,0,3,255,224,0,0,0,0,30,226,30,98,128,0,0,0,0
          db 0,0,0,0,60,0,0,0,0,0,0,0,83,62,109,0,0,0,0,0
          db 0,0,0,7,192,0,0,0,0,0,0,0,59,62,122,0,0,0,0,0
          db 0,0,0,56,0,0,0,0,127,255,255,255,47,62,94,0,0,0,0,0
          db 0,0,0,128,0,15,255,255,255,255,255,255,157,190,92,0,0,0,0,0
          db 0,0,1,0,127,255,240,0,1,255,128,0,15,190,248,0,0,0,0,0
          db 0,0,4,31,255,236,63,255,254,0,127,255,199,230,176,0,0,0,0,0
          db 0,0,13,254,0,8,192,64,1,255,192,0,2,252,160,0,0,0,0,0
          db 0,0,15,132,255,129,63,255,255,254,255,255,250,252,0,0,0,0,0,0
          db 0,0,25,248,127,242,255,255,255,254,255,252,1,124,64,0,0,0,0,0
          db 0,0,11,250,255,210,255,255,255,241,8,120,0,188,128,0,0,0,0,0
          db 0,0,31,201,128,55,128,0,63,240,8,56,0,217,32,0,0,0,0,0
          db 0,0,23,9,128,55,128,0,31,240,24,56,0,122,80,0,0,0,0,0
          db 0,0,30,9,0,55,128,0,15,207,224,56,0,52,208,0,0,0,0,0
          db 0,0,38,11,0,55,128,0,31,192,0,56,0,62,232,0,0,0,0,0
          db 0,0,46,27,0,55,128,0,31,192,0,24,0,42,104,0,0,0,0,0
          db 0,0,46,27,0,31,0,0,31,128,0,28,0,28,120,0,0,0,0,0
          db 0,0,108,27,0,26,128,0,63,128,0,28,0,28,52,0,0,0,0,0
          db 0,0,124,27,0,26,128,0,63,128,0,28,0,44,52,0,0,0,0,0
          db 0,0,92,23,63,250,128,0,63,143,254,28,0,46,58,0,0,0,0,0
          db 0,0,88,31,127,250,128,0,63,31,255,12,0,72,26,0,0,0,0,0
          db 0,0,216,30,127,250,192,0,127,31,255,12,0,221,30,0,0,0,0,0
          db 0,0,152,30,127,245,192,31,255,63,255,14,1,140,141,0,0,0,0,0
          db 0,0,176,30,255,245,64,127,255,63,255,14,3,49,77,0,0,0,0,0
          db 0,1,176,54,255,245,65,224,223,63,255,142,3,142,206,128,0,0,0,0
          db 0,1,191,246,255,245,67,128,239,63,255,254,3,30,102,128,0,0,0,0
          db 0,1,255,231,192,117,71,31,247,127,127,195,243,0,231,0,0,0,0,0
          db 0,3,127,247,192,124,191,255,255,253,255,255,147,255,239,64,0,0,0,0
          db 0,3,79,239,192,58,191,255,255,207,192,3,179,31,47,192,0,0,0,0
          db 0,3,59,143,192,58,95,240,31,223,0,120,99,31,33,32,0,0,0,0
          db 0,6,0,31,193,250,48,15,224,96,0,63,199,31,102,32,0,0,0,0
          db 0,12,0,33,255,122,0,0,0,39,255,192,15,31,241,16,0,0,0,0
          db 0,24,0,0,63,186,0,0,31,224,0,0,12,255,57,252,0,0,0,0
          db 0,24,0,0,0,158,0,62,255,240,0,0,31,0,248,243,0,0,0,0
          db 0,48,0,128,0,246,3,195,15,252,0,0,31,255,236,120,240,0,0,0
          db 0,32,1,0,0,230,60,0,129,255,0,0,12,127,152,62,15,0,0,0
          db 0,96,1,0,0,7,64,0,48,127,192,0,1,254,240,15,0,224,0,0
          db 0,64,1,64,0,11,0,0,12,31,240,0,0,3,0,7,192,24,0,0
          db 0,64,3,32,0,2,0,0,1,15,252,0,0,1,0,3,224,3,0,0
          db 0,192,3,224,0,20,0,0,0,195,255,0,0,1,0,1,240,0,128,0
          db 1,192,2,0,0,20,0,0,0,48,255,128,0,0,0,0,252,0,32,0
          db 3,192,2,0,0,36,0,0,0,8,127,192,0,0,128,0,254,0,16,0
          db 3,216,2,0,0,40,0,0,0,4,31,224,0,0,0,0,126,0,200,0
          db 3,192,2,0,0,40,0,0,0,242,15,240,0,0,0,0,125,2,20,0
          db 3,130,2,0,0,40,0,0,6,5,7,248,0,3,128,0,126,136,198,0
          db 3,176,2,0,0,40,0,0,8,250,131,252,0,255,126,0,126,131,242,0
          db 1,121,2,0,0,36,0,0,19,142,67,252,0,102,204,0,126,150,11,0
          db 0,249,2,0,0,36,0,0,6,67,65,254,0,58,184,0,126,164,133,0
          db 1,252,130,0,0,36,0,0,37,129,161,254,0,15,224,0,126,171,5,0
          db 3,204,130,0,0,68,64,0,45,1,161,254,0,3,128,0,126,207,131,0
          db 1,252,130,0,0,68,96,0,79,64,241,254,0,0,0,0,126,207,255,0
          db 2,190,2,0,0,66,64,0,75,255,241,255,0,0,0,0,252,207,159,0
          db 6,252,2,0,0,66,124,0,75,195,240,255,255,0,0,1,252,43,3,0
          db 7,230,2,0,0,66,194,0,75,0,201,224,0,0,0,0,3,41,133,0
          db 1,94,2,0,0,67,1,0,9,129,156,0,0,255,255,254,1,148,129,0
          db 1,126,66,0,0,66,224,128,52,193,144,31,255,255,255,255,252,154,19,0
          db 0,234,66,0,0,69,240,64,52,99,39,240,0,0,0,0,31,13,229,0
          db 0,170,66,0,0,75,248,64,27,15,78,31,255,255,255,255,255,167,249,0
          db 0,167,2,0,0,67,252,0,14,242,159,255,248,0,0,0,12,193,225,0
          db 0,183,34,0,0,71,252,32,7,252,191,128,7,255,255,255,255,208,2,0
          db 0,175,178,0,0,95,142,32,1,241,48,255,254,0,0,12,152,80,0,0
          db 0,175,207,0,0,95,62,16,0,1,127,0,3,255,255,251,239,232,2,0
          db 0,183,241,0,0,92,255,16,0,0,64,255,253,128,15,250,40,41,227,0
          db 0,179,236,192,0,93,255,0,0,2,255,128,3,255,255,251,111,249,51,0
          db 0,163,113,16,0,91,255,8,3,226,129,255,255,192,127,251,168,58,19,0
          db 0,235,124,70,0,83,207,8,3,52,255,255,255,0,0,10,47,251,19,0
          db 0,251,127,153,128,87,3,128,7,21,251,159,255,255,255,251,239,235,167,128
          db 0,219,127,226,96,86,121,132,6,21,252,127,254,0,0,12,28,73,231,128
          db 0,206,255,57,152,126,252,196,3,50,252,32,0,255,255,255,254,32,15,192
          db 0,98,255,14,98,108,186,192,3,226,124,63,255,224,0,0,6,32,15,128
          db 0,118,254,3,136,253,147,66,0,193,14,32,0,31,255,255,254,63,240,192
          db 0,63,254,0,226,61,147,98,0,0,254,48,0,0,31,255,254,32,0,64
          db 0,61,252,0,56,249,195,127,255,255,254,63,255,255,192,0,2,0,0,64
          db 0,15,252,0,14,121,231,60,0,0,6,32,0,0,0,0,2,0,0,192
          db 0,7,240,0,3,251,148,88,0,0,6,32,0,0,0,0,6,63,255,192
          db 0,0,0,0,0,218,24,24,0,0,6,32,0,0,0,3,254,32,15,128
          db 0,0,0,0,0,123,57,152,0,0,6,63,255,192,0,3,246,63,255,192
          db 0,0,0,0,0,59,187,157,255,255,246,32,0,127,255,255,254,63,127,128
          db 0,0,0,0,0,59,209,159,0,0,30,63,255,255,255,255,252,123,255,128
          db 0,0,0,0,0,57,129,159,255,255,254,63,255,255,255,255,255,222,255,0
          db 0,0,0,0,0,61,128,159,255,255,252,63,255,255,255,255,255,246,255,0
          db 0,0,0,0,0,61,38,95,255,255,254,127,255,255,255,249,247,255,255,0
          db 0,0,0,0,0,61,38,119,254,127,255,255,255,255,254,0,251,221,254,0
          db 0,0,0,0,0,28,231,55,252,7,255,255,255,248,0,0,254,59,254,0
          db 0,0,0,0,0,30,182,183,252,0,1,254,0,0,0,0,127,255,252,0
          db 0,0,0,0,0,30,76,255,248,0,0,0,0,0,0,0,63,255,248,0
          db 0,0,0,0,0,15,57,111,248,0,0,0,0,0,0,0,31,255,240,0
          db 0,0,0,0,0,15,130,239,248,0,0,0,0,0,0,0,7,255,224,0
          db 0,0,0,0,0,7,196,223,240,0,0,0,0,0,0,0,3,255,0,0
          db 0,0,0,0,0,7,243,223,240,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,3,255,191,224,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,1,255,127,192,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,254,255,128,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,31,252,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; --- imagem do despiste: 160x128 nas colunas 6-25, linhas 8-135 ---
draw_defeated: ld de,defimg
          ld a,8
          ld b,128
dd_l:     push bc
          push af
          ld c,6
          call getaddr
          ex de,hl
          ld bc,20
          ldir
          ex de,hl
          pop af
          inc a
          pop bc
          djnz dd_l
          ret

defimg:
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,3,128,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,31,96,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,3,255,206,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,3,255,223,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,255,255,128,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,15,63,254,224,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,63,255,255,48,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,63,255,123,144,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,127,254,123,216,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,255,248,255,252,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,255,243,254,248,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,249,247,250,126,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,1,251,255,243,63,128,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,3,247,252,231,255,128,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,61,255,251,103,254,120,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,7,243,255,255,127,254,15,192,0,0,0,0,0,0,0
          db 0,0,0,0,0,15,227,252,254,127,255,7,192,0,0,0,0,0,0,0
          db 0,0,0,0,0,120,99,251,252,255,255,4,60,0,0,0,0,0,0,0
          db 0,0,0,0,0,224,51,247,255,254,127,8,14,0,0,0,0,0,0,0
          db 0,0,0,0,1,185,59,239,255,255,63,25,185,0,0,0,0,0,0,0
          db 0,0,0,0,3,9,185,255,255,255,254,19,49,128,0,0,0,0,0,0
          db 0,0,0,0,6,12,153,255,255,255,254,50,96,192,0,0,0,0,0,0
          db 0,0,0,0,12,6,93,255,255,255,254,116,192,96,0,0,0,0,0,0
          db 0,0,0,0,8,3,93,255,255,255,254,117,128,32,0,0,0,0,0,0
          db 0,0,0,0,8,1,28,127,255,255,254,113,128,48,0,0,0,0,0,0
          db 0,0,0,0,31,225,156,255,255,255,252,115,63,240,0,0,0,0,0,0
          db 0,0,0,0,16,224,156,255,255,255,252,114,24,24,0,0,0,0,0,0
          db 0,0,0,0,28,32,252,255,255,255,253,122,19,200,0,0,0,0,0,0
          db 0,0,0,0,63,224,249,255,255,255,253,62,19,232,0,0,0,0,0,0
          db 0,0,0,0,96,192,249,63,255,255,241,30,24,24,0,0,0,0,0,0
          db 0,0,0,0,127,192,249,159,255,255,243,30,12,56,0,0,0,0,0,0
          db 0,0,0,0,127,193,97,223,255,255,242,12,15,236,0,0,0,0,0,0
          db 0,0,0,0,224,3,97,215,255,255,46,13,128,4,0,0,0,0,0,0
          db 0,0,0,0,192,12,240,241,255,254,62,31,0,4,0,0,0,0,0,0
          db 0,0,0,0,128,13,248,113,255,252,124,62,96,6,0,0,0,0,0,0
          db 0,0,0,1,128,1,254,60,191,252,248,254,96,3,0,0,0,0,0,0
          db 0,0,0,1,0,56,255,254,79,225,255,255,192,3,0,0,0,0,0,0
          db 0,0,0,1,3,143,225,255,255,131,255,31,135,3,128,0,0,0,0,0
          db 0,0,0,3,3,220,0,7,248,127,254,0,223,1,128,0,0,0,0,0
          db 0,0,0,2,28,120,0,3,240,127,128,0,120,224,128,0,0,0,0,0
          db 0,0,0,2,16,224,0,8,64,192,0,0,14,113,128,0,0,0,0,0
          db 0,0,0,6,97,0,0,32,199,128,120,0,1,24,192,0,0,0,0,0
          db 0,0,0,4,64,0,0,32,135,128,12,0,0,8,64,0,0,0,0,0
          db 0,0,0,4,192,0,0,64,135,128,6,0,0,8,64,0,0,0,0,0
          db 0,0,0,4,0,0,0,0,142,0,3,0,0,0,64,0,0,0,0,0
          db 0,0,0,4,0,0,6,0,142,0,1,128,0,0,64,0,0,0,0,0
          db 0,0,0,4,0,0,0,0,142,0,0,128,0,0,64,0,0,0,0,0
          db 0,0,0,4,0,0,0,0,143,0,8,192,0,0,64,0,0,0,0,0
          db 0,0,0,4,0,0,0,0,255,128,6,224,0,0,64,0,0,0,0,0
          db 0,0,0,6,0,0,6,0,255,224,38,240,0,0,192,0,0,0,0,0
          db 0,0,0,3,0,0,30,15,255,248,19,254,0,3,128,0,0,0,0,0
          db 0,0,0,3,128,7,255,255,243,121,147,255,248,15,128,0,0,0,0,0
          db 0,0,0,1,248,63,255,255,227,60,223,241,252,31,0,0,0,0,0,0
          db 0,0,0,0,124,124,1,255,195,60,223,224,31,254,0,0,0,0,0,0
          db 0,0,0,0,63,240,0,115,195,31,255,0,31,248,0,0,0,0,0,0
          db 0,0,0,0,3,128,0,17,251,63,252,0,19,128,0,0,0,0,0,0
          db 0,0,0,0,3,128,0,25,254,127,248,0,25,192,0,0,0,0,0,0
          db 0,0,0,0,3,128,0,25,255,255,240,0,13,192,0,0,0,0,0,0
          db 0,0,0,0,3,0,0,137,207,231,48,0,13,192,0,0,0,0,0,0
          db 0,0,0,0,3,0,0,200,243,199,38,0,13,192,0,0,0,0,0,0
          db 0,0,0,0,3,0,0,104,254,63,32,0,2,192,0,0,0,0,0,0
          db 0,0,0,0,2,0,0,104,255,254,44,0,2,192,0,0,0,0,0,0
          db 0,0,0,0,2,192,0,104,199,230,44,0,2,192,0,0,0,0,0,0
          db 0,0,0,0,2,192,0,104,66,6,44,0,2,192,0,0,0,0,0,0
          db 0,0,0,0,7,128,0,24,99,12,48,0,1,192,0,0,0,0,0,0
          db 0,0,0,0,15,0,0,30,127,252,48,0,1,192,0,0,0,0,0,0
          db 0,0,0,0,7,0,2,30,127,252,48,0,1,224,0,15,248,0,0,0
          db 0,0,0,0,7,0,3,28,51,56,49,0,49,224,0,240,7,128,0,0
          db 0,0,0,0,6,32,1,152,56,120,51,0,24,224,1,240,3,128,0,0
          db 0,0,0,0,6,32,0,248,56,248,118,0,24,224,3,128,1,240,0,0
          db 0,0,0,0,6,32,0,120,63,248,248,0,28,224,14,0,0,56,0,0
          db 0,0,0,0,6,192,0,56,8,48,252,0,12,224,28,0,0,28,0,0
          db 0,0,0,0,7,128,0,56,15,224,248,0,12,224,48,0,0,12,0,0
          db 0,0,0,0,7,0,0,24,15,224,240,0,1,224,48,0,0,6,0,0
          db 0,0,0,0,6,0,12,28,4,64,240,0,67,224,112,0,0,3,0,0
          db 0,0,0,0,14,0,6,30,4,64,224,192,3,224,79,0,0,33,0,0
          db 0,0,0,0,12,0,1,30,68,192,225,0,33,224,192,240,0,1,128,0
          db 0,0,0,0,4,0,1,158,68,128,230,0,17,225,192,255,252,133,192,0
          db 0,0,0,0,4,24,0,254,5,131,252,0,25,225,198,7,255,255,192,0
          db 0,0,0,0,4,96,0,126,4,3,248,0,13,193,198,0,0,0,192,0
          db 0,0,0,0,6,192,32,30,0,3,240,240,13,131,128,0,0,0,224,0
          db 0,0,0,0,3,223,226,30,3,3,224,126,1,131,127,255,255,255,32,0
          db 0,0,0,0,3,255,252,30,3,3,225,255,227,131,95,240,127,255,32,0
          db 0,0,0,0,3,255,252,30,3,3,241,255,247,131,95,240,127,255,32,0
          db 0,0,0,0,3,255,255,126,3,27,243,255,255,3,95,240,127,255,32,0
          db 0,0,0,0,3,248,63,255,3,3,255,224,255,3,127,240,127,255,32,0
          db 0,0,0,0,1,224,27,255,3,3,255,128,126,3,127,240,127,255,32,0
          db 0,0,0,0,1,199,211,255,3,7,255,128,30,3,127,240,127,255,224,0
          db 0,0,0,0,0,207,217,255,0,31,252,159,156,3,63,240,127,255,224,0
          db 0,0,0,0,0,223,216,255,0,31,252,159,216,3,31,240,127,255,224,0
          db 0,0,0,0,0,224,56,255,0,7,240,224,48,3,15,240,127,255,224,0
          db 0,0,0,0,0,192,48,255,195,15,248,192,24,3,135,252,127,255,224,0
          db 0,0,0,0,1,223,161,255,255,255,252,143,156,3,193,254,127,255,32,0
          db 0,0,0,0,1,255,225,127,255,255,252,127,252,3,224,15,255,248,96,0
          db 0,0,0,0,3,0,226,127,255,255,254,112,30,1,252,0,0,0,192,0
          db 0,0,0,0,2,126,194,127,255,255,246,7,238,0,191,128,0,0,192,0
          db 0,0,0,0,6,254,194,127,255,255,240,15,238,0,191,128,126,124,192,0
          db 0,0,0,0,15,1,204,127,255,255,241,16,31,0,222,0,0,1,192,0
          db 0,0,0,0,60,0,12,255,255,255,249,0,1,128,199,128,0,1,128,0
          db 0,0,0,0,112,0,28,248,0,0,233,128,0,192,240,224,62,121,0,0
          db 0,0,0,0,96,0,29,240,0,0,109,128,0,96,120,96,28,113,0,0
          db 0,0,0,0,64,0,13,48,0,0,41,0,0,96,127,0,0,3,0,0
          db 0,0,0,1,128,1,230,48,0,0,231,120,0,16,255,248,0,7,0,0
          db 0,0,0,1,191,240,30,248,0,0,243,128,127,144,31,255,255,255,192,0
          db 0,0,0,1,255,248,31,240,0,0,127,192,255,240,11,95,255,250,128,0
          db 0,0,0,1,255,252,123,192,0,0,62,225,255,240,0,15,255,240,0,0
          db 0,0,0,3,255,255,254,0,0,0,7,255,255,248,0,0,0,0,0,0
          db 0,0,0,1,255,255,224,0,0,0,0,127,255,224,0,0,0,0,0,0
          db 0,0,0,0,255,255,224,0,0,0,0,127,255,192,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; ===============================================================
; ADVERSARIOS
; ===============================================================
; --- desenha a estrada de (rp) ate ao par A, respeitando a fronteira
;     de largura; deixa (rp) = A ---
road_to:  ld (rt_e),a
          ld hl,rp
          cp (hl)
          ret c
          ret z
          ld a,(bpos)
          or a
          jr z,rt_low          ; sem fronteira: tudo com wbot
          ld hl,rp
          cp (hl)
          jr c,rt_low          ; fronteira ja passada
          jr z,rt_low
          ld hl,rt_e
          cp (hl)
          jr nc,rt_top         ; fronteira depois do fim: tudo wtop
          ld hl,rp             ; dividir: [rp, bpos) com wtop
          sub (hl)
          ld b,a
          ld a,(wtop)
          ld c,a
          ld a,(hl)
          call draw_run
          ld a,(bpos)
          ld (rp),a
          jr rt_low
rt_top:   ld a,(wtop)
          jr rt_go
rt_low:   ld a,(wbot)
rt_go:    ld c,a
          ld a,(rt_e)
          ld hl,rp
          sub (hl)
          ret z
          ld b,a
          ld a,(hl)
          call draw_run
          ld a,(rt_e)
          ld (rp),a
          ret

; ---------------------------------------------------------------
; RELVA: pinta de verde tudo o que esta' fora da estrada, linha de
; caracteres a linha de caracteres. So' reescreve uma linha quando a
; coluna da berma mudou desde o frame anterior, por isso em recta nao
; custa quase nada. Como e' so' atributo, nao ha' problema de feixe.
; ---------------------------------------------------------------
verge_init:                    ; forca o redesenho de todas as linhas
          ld hl,vprevl
          ld b,VROWN*2
vi_l:     ld (hl),255
          inc hl
          djnz vi_l
          ret

verge_upd:
          ld ix,vprevl
          ld c,VROW0
          ld b,VROWN
vu_row:   push bc
          ld a,c               ; par ao meio desta linha de caracteres = 4*C+2
          add a,a
          add a,a
          add a,2
          ld b,a               ; B = par (BC ja' esta' na pilha)
          ld l,a
          ld h,0
          ld de,cenbuf
          add hl,de
          ld a,(hl)
          ld d,a               ; D = centro da estrada neste par
          ld a,(bpos)          ; largura CERTA para este par: acima da fronteira
          or a                 ; de largura vale wtop, abaixo vale wbot. Usar
          jr z,vu_wb           ; sempre wbot punha a relva 16px fora do sitio
          cp b                 ; nas linhas acima de uma mudanca de largura
          jr c,vu_wb
          jr z,vu_wb
          ld a,(wtop)
          jr vu_w
vu_wb:    ld a,(wbot)
vu_w:     ld e,a               ; E = meia-largura
          ld a,d
          sub e                ; berma esquerda
          jr nc,vu_lok
          xor a                ; encostada ao bordo esquerdo
vu_lok:   rrca
          rrca
          rrca
          and 31
          ld (vleft),a
          ld l,a
          ld a,d
          add a,e              ; berma direita
          jr nc,vu_rok
          ld a,255
vu_rok:   rrca
          rrca
          rrca
          and 31
          ld (vright),a
          ld h,a
          ld a,(ix+0)          ; alguma das bermas mudou de coluna?
          cp l
          jr nz,vu_paint
          ld a,(ix+VROWN)
          cp h
          jr z,vu_next         ; nao mudou: esta linha ja' esta' pintada
vu_paint: ld (ix+0),l
          ld (ix+VROWN),h
          call verge_paint
vu_next:  inc ix
          pop bc
          inc c
          djnz vu_row
          ret

; --- bandeira axadrezada da meta. Pintada em ATRIBUTOS (celulas de 8x8 a
;     alternar preto/branco), que e' seguro face ao feixe: muda a cor de uma
;     celula, nunca a forma. A meta esta' a (17600 - lvldist) pares do carro,
;     e o carro esta' no par 66, por isso aparece no par 66-D enquanto D<=42.
;     Depois de pintar, invalida a cache da linha para o verge_upd a repor
;     assim que a bandeira passa ---
finish_flag:
          ld hl,17600
          ld de,(lvldist)
          or a
          sbc hl,de
          ret c                ; ja' passou a meta
          ld a,h
          or a
          ret nz               ; ainda a mais de 255 pares
          ld a,l
          cp 43
          ret nc               ; ainda nao entrou no ecra
          ld b,a
          ld a,66
          sub b                ; par onde esta' a meta
          srl a
          srl a                ; -> linha de caracteres
          cp VROW0             ; VROWN e' o NUMERO de linhas, nao a ultima:
          ret c                ; as linhas com relva vao de VROW0 a VROW0+VROWN-1
          cp VROW0+VROWN
          ret nc
          ld c,a               ; C = linha onde esta' a meta
          call ff_row          ; duas filas de celulas: a paridade inclui a
          ld a,c               ; linha, por isso o xadrez sai encavalitado
          dec a                ; como numa bandeira a serio
          cp VROW0
          ret c
          ld c,a
; --- pinta a linha C entre as bermas, alternando preto/branco ---
ff_row:   ld a,c
          sub VROW0
          ld e,a               ; E = indice na cache das bermas
          ld d,0
          ld hl,vprevl
          add hl,de
          ld a,(hl)            ; coluna da berma esquerda
          inc a
          ld b,a               ; B = 1a coluna de alcatrao
          push hl
          ld de,VROWN
          add hl,de
          ld a,(hl)            ; coluna da berma direita
          pop hl
          ld (hl),255          ; invalida a cache: o verge_upd repinta a seguir
          ld e,a               ; E = ultima coluna de alcatrao (exclusiva)
          ld a,b
          cp e
          ret nc               ; estrada sem celulas visiveis
; O endereco tem de ser feito em 16 bits. Antes fazia-se linha*32 com cinco
; "add a,a" num registo de 8 bits e so' se olhava para o carry do ULTIMO: das
; linhas 16 a 19 o transporte dava-se num dos add do meio, perdia-se, e a
; fila da bandeira ia parar as linhas 0 a 3 - a faixa de cima do ecra. Era
; esse o traco que aparecia la' em cima quando a meta chegava ao fundo.
; O DE nao pode ser tocado: leva o limite direito do alcatrao.
          ld l,c
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; HL = linha*32, sem estourar
          ld a,l
          add a,b              ; + coluna
          ld l,a
          jr nc,ff_h
          inc h
ff_h:     ld a,h
          add a,0x58
          ld h,a
ff_p:     ld a,b               ; paridade = coluna + linha: assim as duas filas
          add a,c              ; ficam desencontradas e nao ha padrao a saltar
          and 1                ; de frame para frame
          jr z,ff_black
          ld (hl),0x78         ; papel branco
          jr ff_step
ff_black: ld (hl),0x07         ; papel preto (como o resto do alcatrao)
ff_step:  inc hl
          inc b
          ld a,b
          cp e
          jr c,ff_p
          ret

; --- intervalo entre trocos: para o jogo, anuncia o troco novo e a
;     posicao, e volta com a pista limpa e a relva da cor certa ---
; --- pausa de ~1 segundo. O ciclo principal corre com DI: sem reactivar as
;     interrupcoes o halt nunca mais saia e o jogo ficava pendurado ---
lb_pause: push bc
          ei
          ld b,50
lbp_w:    halt
          djnz lbp_w
          di
          pop bc
          ret

; --- ecra de arranque de troco: STAGE n e contagem 3, 2, 1 ---
stage_intro:
          push bc
          call mus_hush        ; o ecra bloqueia: o AY ficava com o acorde preso
          call cls_bmp
          call set_attrs
          ld a,8               ; o piloto a correr para o Mini, por cima do texto
          call draw_wait
          ld hl,t_stage
          ld bc,0x090D         ; "STAGE" a meio, linha 9 (a imagem acaba na 55)
          call prstr
          ld a,0x48            ; numero do troco em algarismo grande (y=88)
          ld (bigyd),a
          ld a,0x60
          ld (bigye),a
          ld a,(arclvl)
          ld c,15
          call bigdraw
          ld hl,t_key          ; espera por uma tecla em vez de contagem
          ld bc,0x1009
          call prstr
          call sfx_stage       ; o jogo esta. parado: da. para tons afinados
          ei                   ; o wait_key le' o teclado directamente, mas o
          call wait_key        ; ciclo principal corre com DI
          di
          ld a,0x50            ; repor o destino normal do bigdraw (HUD)
          ld (bigyd),a
          ld a,0xA0
          ld (bigye),a
          pop bc
          ret

level_break:
          push bc
          call mus_hush
          ld hl,0              ; o carro para em cima da bandeira e fica-se a
          ld (spd),hl          ; ver a meta um segundo, com o ecra tal como
          call sfx_finish      ; ficou no ultimo frame desenhado
          call lb_pause
          call cls_bmp
          call set_attrs
          ld hl,t_done         ; "STAGE COMPLETE"
          ld bc,0x0709
          call prstr
          ld hl,t_pos
          ld bc,0x0B0C
          call prstr
          ld a,0x50            ; posicao em algarismos grandes por baixo (y=136)
          ld (bigyd),a
          ld a,0x20
          ld (bigye),a
          ld a,(racepos)
          ld c,14
          call big2
          call lb_pause
          call lb_pause
          call stage_intro     ; STAGE n + 3, 2, 1 do troco que vem
          call cls_bmp         ; volta a montar o ecra de corrida
          call set_attrs
          call sep_line
          call hud_init
          call set_grass       ; relva do troco novo + repintar tudo
          call pos_clear
          call draw_pos
          ld hl,hudjob
          set 0,(hl)
          set 1,(hl)
          set 3,(hl)
          ld a,255
          ld (barold),a
          pop bc
          ret
t_done:   db "STAGE COMPLETE",0
t_stage:  db "STAGE",0
t_pos:    db "POSITION",0

; --- um algarismo grande por frame, escolhido entre os jobs pendentes:
;     bit 0/1/3 = unidades/dezenas/centena do relogio, bit 4/5 = dezenas/
;     unidades da posicao. Custo constante, seja o que for que mudou ---
hud_digit:
          ld hl,hudjob
          ld a,(hl)
          and 0x3B             ; bit 2 (barra) nao se desenha aqui
          ret z
          rrca
          jr c,hd_j0
          rrca
          jr c,hd_j1
          rrca                 ; bit 2: barra, salta
          rrca
          jr c,hd_j3
          rrca
          jr c,hd_j4
          res 5,(hl)
          jp draw_posu
hd_j0:    res 0,(hl)
          jp draw_units
hd_j1:    res 1,(hl)
          jp draw_tens
hd_j3:    res 3,(hl)
          jp draw_cent
hd_j4:    res 4,(hl)
          jp draw_post         ; explicito: ja' nao esta' aqui a seguir

; --- dezenas e unidades da posicao, cada uma o seu job ---
; --- faixa livre por cima da estrada (linhas 0..5): rotulo POSITION e a area
;     dos dois algarismos. Pintado uma vez por troco, nunca no caminho do feixe ---
; --- a barra e' a corrida toda: quatro marcas a dividi-la nos cinco trocos.
;     A barra ocupa as colunas 4..27, por isso os quintos caem em 9, 14, 18 e 23 ---
; --- desenha a imagem de espera: 128x48 (16 colunas x 6 linhas de chars),
;     centrada nas colunas 8..23, a comecar na linha de PIXELS em A ---
draw_wait:
          ld de,waitimg
          ld b,48
dw_l:     push bc
          push af
          ld c,8               ; coluna 8: 16 chars centrados em 32
          call getaddr
          ex de,hl
          ld bc,16
          ldir
          ex de,hl
          pop af
          inc a
          pop bc
          djnz dw_l
          ret

; ==================== SOM (beeper, 48K e 128K) ====================
; Medido: o ciclo principal deixa 11668 T livres no pior caso. Um tom afinado
; nao cabe la' - a afinacao oscilaria com a carga do frame. Ruido cabe, e a
; instabilidade ate ajuda. Por isso: durante o jogo so' ruido, espalhado por
; varios frames; tons afinados so' nos ecras em que o jogo esta' parado.
sfxc:     db 0                 ; frames que faltam do efeito
sfxp:     db 80                ; meio-periodo base (maior = mais grave)
beepbit:  db 0                 ; estado do bit 4 do porto (borda fica a preto)

sfx_tick: ld a,(sfxc)
          or a
          ret z
          dec a
          ld (sfxc),a
          ld b,4               ; 4 meias-ondas por frame: ~6000 T no maximo,
sfxt_l:   push bc              ; bem dentro dos 11668 que sobram
          call rnd
          and 31
          ld b,a
          ld a,(sfxp)
          add a,b              ; meio-periodo = base + 0..31
          ld c,a
          ld a,(beepbit)
          xor 0x10
          ld (beepbit),a
          out (0xFE),a
sfxt_w:   dec c
          jr nz,sfxt_w
          pop bc
          djnz sfxt_l
          ret

; --- A = frames, C = meio-periodo base ---
sfx_set:  ld (sfxc),a
          ld a,c
          ld (sfxp),a
          ret
sfx_crash: ld a,20             ; despiste: grave e longo
          ld c,90
          jr sfx_set
sfx_bump: ld a,7               ; embate/rocadela: mais curto e agudo
          ld c,45
          jr sfx_set
sfx_pass: ld a,2               ; ultrapassagem: so' um estalido
          ld c,14
          jr sfx_set

; --- tom afinado, bloqueante. So' para ecras parados: HL = meio-periodo em
;     iteracoes, DE = numero de meias-ondas ---
beep_tone: ld a,(beepbit)
          xor 0x10
          ld (beepbit),a
          out (0xFE),a
          push hl
bt_w:     dec hl
          ld a,h
          or l
          jr nz,bt_w
          pop hl
          dec de
          ld a,d
          or e
          jr nz,beep_tone
          ret

sfx_stage: ld hl,300           ; tres notas a subir, no ecra de arranque
          ld de,60
          call beep_tone
          ld hl,240
          ld de,70
          call beep_tone
          ld hl,200
          ld de,90
          jp beep_tone
sfx_finish: ld hl,200          ; meta: quatro notas a subir
          ld de,50
          call beep_tone
          ld hl,160
          ld de,60
          call beep_tone
          ld hl,130
          ld de,70
          call beep_tone
          ld hl,100
          ld de,120
          jp beep_tone

; Os quatro divisores dos cinco trocos. A barra ocupa os pixeis 32..223 (192
; ao todo), por isso os divisores caem em 32+192*n/5 = 70, 109, 147 e 186 -
; que nao sao inicios de coluna. Antes marcava-se sempre o bit 7 das colunas
; 9, 14, 18 e 23, ou seja os pixeis 72, 112, 144 e 184: os espacamentos saiam
; 40, 32 e 40 em vez de 38,4 iguais, e via-se o troco do meio mais curto.
; Agora cada marca leva o seu bit, e escreve-se com OR para nao apagar nada.
bar_marks:
          ld hl,bm_tab
          ld b,12
bm_l:     ld e,(hl)
          inc hl
          ld d,(hl)
          inc hl
          ld c,(hl)            ; mascara do pixel certo dentro da coluna
          inc hl
          ld a,(de)
          or c
          ld (de),a
          djnz bm_l
          jp bar_ends          ; tracos de START e END, ao fundo do ficheiro
bm_tab:   db 0x88,0x51,0x02,  0x8D,0x51,0x04,  0x92,0x51,0x10,  0x97,0x51,0x20
          db 0x88,0x52,0x02,  0x8D,0x52,0x04,  0x92,0x52,0x10,  0x97,0x52,0x20
          db 0x88,0x57,0x02,  0x8D,0x57,0x04,  0x92,0x57,0x10,  0x97,0x57,0x20

hud_top:  ld hl,0x582C         ; POSITION e o numero: linhas 1..4, colunas
          ld c,4               ; 12..19, a ciano
ht_l:     push hl
          ld b,8
ht_l2:    ld (hl),KMATTR
          inc hl
          djnz ht_l2
          pop hl
          ld de,32
          add hl,de
          dec c
          jr nz,ht_l
          ld hl,0x5861         ; STAGE n: encostado a' esquerda, na linha 3,
          ld b,7               ; que e' a do meio do algarismo grande
ht_s:     ld (hl),KMATTR
          inc hl
          djnz ht_s
          ld hl,t_position     ; linha 1: POSITION (8 letras = centrado)
          ld bc,0x010C
          call prstr
          ld hl,t_stage        ; linha 3, coluna 1: STAGE n
          ld bc,0x0301
          call prstr
          ld a,(arclvl)
          add a,48             ; algarismo ASCII
          ld b,3
          ld c,7
          jp prchar
t_position: db "POSITION",0

draw_post: call big_top        ; a posicao vive na faixa por cima da estrada,
          ld a,(racepos)       ; ao centro, por baixo da palavra POSITION
          ld b,0
dpt_l:    cp 10
          jr c,dpt_d
          sub 10
          inc b
          jr dpt_l
dpt_d:    ld a,b
          or a
          jr nz,dpt_n
          ld a,10              ; abaixo de 10 a dezena fica em branco
dpt_n:    ld c,14
          jp bigdraw
draw_posu: call big_top
          ld a,(racepos)
dpu_l:    cp 10
          jr c,dpu_d
          sub 10
          jr dpu_l
dpu_d:    ld c,16
          jp bigdraw

; --- posicao na corrida: dois algarismos grandes nos dois ultimos slots
;     (parte-se em 30.o). Os dois da esquerda sao apagados uma vez, no
;     arranque do troco (bigdraw com o indice 10 = glifo em branco) ---
draw_pos: call big_top         ; desenha os dois algarismos de uma vez, no
          ld a,(racepos)       ; mesmo sitio onde o hud_digit os poe
          ld c,14
          ; cai no big2

; --- big2: A = valor 1..99, C = coluna das dezenas; unidades em C+2 ---
big2:     ld b,0
bg2_t:     cp 10                ; dezenas por subtracoes: nao ha divisao
          jr c,bg2_u
          sub 10
          inc b
          jr bg2_t
bg2_u:     push af
          push bc
          ld a,b
          or a
          jr nz,bg2_td
          ld a,10              ; valor < 10: dezena em branco, nao "0"
bg2_td:    call bigdraw
          pop bc
          ld a,c
          add a,2
          ld c,a
          pop af
          jp bigdraw

pos_clear:                     ; a posicao mudou-se para a faixa de cima: os
          call big_hud         ; quatro slots antigos do HUD ficam em branco
          ld a,10
          ld c,19
          call bigdraw
          ld a,10
          ld c,21
          call bigdraw
          ld a,10
          ld c,23
          call bigdraw
          ld a,10
          ld c,25
          jp bigdraw

; --- cor da relva conforme o troco: 1 verde, 2 amarela, 3 vermelha.
;     Muda a cor E forca o repintar de todas as linhas ---
set_grass:
          ld a,(arclvl)        ; indice 0-based do troco
          dec a
          cp RACELVLS
          jr c,sg_ok
          xor a                ; fora da tabela: fica pelo primeiro
sg_ok:    ld e,a
          ld d,0
          ld hl,spdlvl         ; velocidade maxima do troco
          add hl,de
          ld a,(hl)
          ld (maxspd),a
          ld hl,wlvl           ; largura da estrada do troco
          add hl,de
          ld a,(hl)
          ld (lvlw),a
          ld hl,grasslvl       ; cor da relva do troco
          add hl,de
          ld a,(hl)
          ld (grassc),a
          jp verge_init        ; obriga a repintar tudo com a cor nova

; C = linha de caracteres, (vleft)/(vright) = colunas das bermas
verge_paint:
          ld h,0
          ld l,c
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; C*32
          ld de,0x5800
          add hl,de
          ld a,(grassc)        ; cor da relva deste troco (C ja' nao e' precisa)
          ld c,a
          ld a,(vleft)         ; relva a' esquerda
          or a
          jr z,vp_road
          ld b,a
vp_g1:    ld (hl),c
          inc hl
          djnz vp_g1
vp_road:  ld a,(vright)        ; asfalto entre as bermas
          ld b,a
          ld a,(vleft)
          neg
          add a,b
          inc a
          ld b,a
vp_r1:    ld (hl),LEVATTR
          inc hl
          djnz vp_r1
          ld a,(vright)        ; relva a' direita
          sub 31
          neg
          ret z
          ld b,a
vp_g2:    ld (hl),c
          inc hl
          djnz vp_g2
          ret


grassc:   db GRASSATTR ; cor da relva em vigor (muda por troco)
vleft:    db 0
vright:   db 0
vprevl:   ds VROWN             ; coluna da berma esquerda no frame anterior
vprevr:   ds VROWN             ; idem, direita

; --- deriva lateral: alguns adversarios mudam de faixa devagar, como no
;     Road Fighter. olanev = 0 (segue a direito) ou +-1 px por frame; ao
;     chegar ao limite inverte, por isso ziguezagueia dentro da estrada ---
lane_drift:
          ld a,(olanev)
          or a
          ret z
          push bc              ; o opp_upd tem o CENTRO DA ESTRADA em B e usa-o
                                ; logo a seguir: sem isto o carro ficava preso
                                ; numa coluna fixa do ecra e acabava na relva
          ld b,a
          ld a,(olane)
          add a,b
          ld c,a
          add a,34             ; -34..+34 fica 0..68 (fora disso, inverte)
          cp 69
          jr c,ld_ok
          ld a,(olanev)
          neg
          ld (olanev),a
          pop bc
          ret
ld_ok:    ld a,c
          ld (olane),a
          pop bc
          ret

lane_drift2:
          ld a,(olanev2)
          or a
          ret z
          push bc              ; idem: B traz o centro da estrada do opp_upd2
          ld b,a
          ld a,(olane2)
          add a,b
          ld c,a
          add a,34
          cp 69
          jr c,ld2_ok
          ld a,(olanev2)
          neg
          ld (olanev2),a
          pop bc
          ret
ld2_ok:   ld a,c
          ld (olane2),a
          pop bc
          ret

; --- adversarios ACIMA do carro: estrada + sprite, do mais longe para o mais
;     perto (assim o mais proximo tapa o mais distante) ---
opps_above:
          ld c,0               ; C: bit0 = slot 1 elegivel, bit1 = slot 2
          ld a,(olines)
          or a
          jr z,oa_s2
          ld a,(oy+1)
          cp CARPEND
          jr nc,oa_s2
          set 0,c
oa_s2:    ld a,(olines2)
          or a
          jr z,oa_go
          ld a,(oy2+1)
          cp CARPEND
          jr nc,oa_go
          set 1,c
oa_go:    ld a,c
          or a
          ret z
          cp 3
          jr nz,oa_one
          ld a,(oybot)         ; os dois: primeiro o de fundo mais alto no ecra.
          ld hl,oybot2         ; A estrada seguinte so' pinta pares ABAIXO do
          cp (hl)              ; sprite ja' desenhado (o or_opp corta o sprite
          jr c,oa_12           ; exactamente no oybot), por isso esta ordem
          ld a,(oybot2)        ; incremental nunca apaga nada
          call road_to
          call or_opp2
          ld a,(oybot)
          call road_to
          jp or_opp
oa_12:    ld a,(oybot)         ; slot 1 esta' mais longe
          call road_to
          call or_opp
          ld a,(oybot2)
          call road_to
          jp or_opp2
oa_one:   bit 0,a
          jr z,oa_only2
          ld a,(oybot)
          call road_to
          jp or_opp
oa_only2: ld a,(oybot2)
          call road_to
          jp or_opp2

; --- adversarios ABAIXO do carro: a estrada ja' esta' toda desenhada ---
opps_below:
          ld a,(olines)
          or a
          jr z,ob_s2
          ld a,(oy+1)
          cp CARPEND
          call nc,or_opp
ob_s2:    ld a,(olines2)
          or a
          ret z
          ld a,(oy2+1)
          cp CARPEND
          ret c
          jp or_opp2

; --- apaga as 3 colunas onde o adversario esteve ---
clr_oldopp: ld a,(ooldn)
          or a
          ret z
          ld b,a
          xor a
          ld (ooldn),a
          ld a,(olines)        ; se NAO vai ser redesenhado (morreu no embate,
          or a                 ; saiu de cena) tem mesmo de se apagar. O atalho
          jr z,co_go           ; abaixo parte do principio que o sprite volta
                                 ; a ser desenhado no mesmo sitio - com o
                                 ; adversario morto, o ox/oy ficam congelados,
                                 ; davam "iguais", nao se apagava nada e o carro
                                 ; ficava colado ao ecra: era o glitch do embate
          ld a,(ox)            ; se a posicao exata (x e y) nao mudou desde
          ld c,a               ; o ultimo desenho, o novo sprite e' identico
          ld a,(ooldx)         ; ao antigo: apagar primeiro nao muda o resultado
          cp c
          jr nz,co_go
          ld a,(oy+1)
          add a,a
          ld c,a
          ld a,(ooldy)
          cp c
          jr nz,co_go
co_skip:  ret                  ; x e y iguais: poupa o apagar
co_go:    ld a,(ooldx)
          srl a
          srl a
          srl a
          ld c,a
          ld a,(ooldy)
          call getaddr
          ex de,hl
co_l:     xor a
          ld (de),a
          inc e
          ld (de),a
          inc e
          ld (de),a
          dec e
          dec e
          inc d
          ld a,d
          and 7
          jr nz,co_ok
          ld a,e
          add a,32
          ld e,a
          jr c,co_ok
          ld a,d
          sub 8
          ld d,a
co_ok:    djnz co_l
          ret

; --- funde o adversario com a estrada ja desenhada ---
or_opp:   ld a,(olines)
          or a
          ret z
          ld hl,(osprptr)      ; endereco do sprite (tamanho certo + shift)
          push hl              ; ja' calculado pelo opp_upd na fase de logica
          ld a,(ox)
          ld (ooldx),a
          srl a
          srl a
          srl a
          ld c,a
          ld a,(oy+1)
          add a,a              ; par -> linha de pixels
          ld (ooldy),a
          call getaddr
          ex de,hl             ; DE = ecra
          pop hl               ; HL = sprite
          ld a,(olines)
          ld (ooldn),a
          ld b,a
or_lines: ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          inc e
          ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          inc e
          ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          dec e
          dec e
          inc d
          ld a,d
          and 7
          jr nz,ol_ok
          ld a,e
          add a,32
          ld e,a
          jr c,ol_ok
          ld a,d
          sub 8
          ld d,a
ol_ok:    djnz or_lines
          ret

; --- movimento, nascimento e morte do adversario ---
; A distancia ate' ao proximo nascimento tem de correr SEMPRE, nao so' com o
; lugar vazio: assim o intervalo real era o agendado MAIS o tempo que o carro
; anterior levava a atravessar o ecra, e num troco de 1100m so' apareciam 9
; adversarios - menos do que as 10 ultrapassagens que o troco permite, ou seja
; o maximo era inalcancavel por muito bem que se conduzisse.
opp_tick: ld hl,(onextd)
          ld a,(steps)
          ld e,a
          ld d,0
          or a
          sbc hl,de
          jr nc,ot_s
          ld hl,0              ; ja' passou: fica a zero a' espera de lugar
ot_s:     ld (onextd),hl
          ld hl,(onextd2)
          ld a,(steps)
          ld e,a
          ld d,0
          or a
          sbc hl,de
          jr nc,ot_s2
          ld hl,0
ot_s2:    ld (onextd2),hl
          ret

opp_upd:  call opp_tick
          ld a,(oact)
          or a
          jp z,opp_spawn
          ld hl,(oy)           ; desce com a estrada, sobe com a sua velocidade
          ld a,(steps)
          ld d,a
          ld e,0
          add hl,de
          ld de,(ospd)
          or a
          sbc hl,de
          jr nc,ou_c0          ; sem estouro: segue normalmente
          ld hl,ROADTOP*256    ; travagem momentanea nao mata o adversario:
          jr ou_clamp          ; fica a espera no horizonte
ou_c0:    ld a,h               ; nunca subir acima do horizonte (senao ficava
          cp ROADTOP           ; num par que ja' nao se desenha = invisivel)
          jr nc,ou_clamp
          jp opp_esc           ; fugiu por cima: ultrapassou-nos
ou_clamp: ld (oy),hl
          ld a,h
          cp NPAIR
          jp nc,opp_off        ; saiu por baixo (jp: o codigo da perspectiva
                               ; empurrou o opp_off para fora do alcance do jr)
          push af              ; A ultrapassagem conta-se quando ele passa por
          ld hl,opassed        ; NOS, nao quando desaparece pelo fundo: sao 14
          ld a,(hl)            ; pares de diferenca, uns 200ms de atraso no som
          or a
          jr nz,ou_np
          ld a,(oy+1)
          cp 68                ; o corpo dele passou o nosso (pares 60..67)
          jr c,ou_np
          ld (hl),1
          call pos_up          ; o som fica dentro do pos_up: so' ha' apito
                                 ; quando se ganha mesmo um lugar, e nao ao
                                 ; passar um carro depois da quota esgotada
ou_np:    pop af
          ld l,a               ; centro da estrada nesse par
          ld h,0
          ld de,cenbuf
          add hl,de
          ld b,(hl)
          ld a,(bpos)          ; largura nesse par
          or a
          jr z,ou_wb
          ld hl,oy+1
          cp (hl)
          jr c,ou_wb
          jr z,ou_wb
          ld a,(wtop)
          jr ou_w
ou_wb:    ld a,(wbot)
ou_w:     ld d,a
          call lane_drift      ; ha' carros que fogem de faixa (Road Fighter)
          ld a,(olane)         ; x = centro + faixa - 8
          add a,b
          sub 8
          ld c,a
          ld a,b               ; limite esquerdo: centro - largura + 2
          sub d
          add a,2
          ld e,a
          ld a,c
          cp e
          jr nc,ou_x1
          ld c,e
ou_x1:    ld a,b               ; limite direito: centro + largura - 18
          add a,d
          sub 18
          ld e,a
          ld a,c
          cp e
          jr c,ou_x2
          ld c,e
ou_x2:    ld a,c
          ld (ox),a
          ld a,(ox)            ; endereco do sprite (16 linhas, passo 48 =
          and 7                ; 32+16) pre-calculado aqui na fase de logica;
          ld l,a               ; o or_opp so' le (osprptr). Tamanho unico a
          ld h,0               ; qualquer distancia, por escolha de design.
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; x16
          ld e,l
          ld d,h
          add hl,hl            ; x32
          add hl,de            ; x48
          ld de,(ospr1)        ; escolhido no nascimento: adversario enquanto
          add hl,de            ; houver lugares a ganhar, transito depois
          ld (osprptr),hl
          ld a,(oy+1)          ; banda vertical ocupada (com corte em baixo)
          ld b,a
          add a,8              ; 8 pares = 16 linhas
          cp NPAIR
          jr c,ou_n
          ld a,NPAIR
ou_n:     ld (oybot),a
          sub b
          add a,a
          ld (olines),a
          ret
opp_off:  xor a                ; saiu por baixo. A ultrapassagem ja. foi
                                 ; contada quando ele passou por nos
          ld (oact),a
          ld (olines),a
          ret
; O adversario fugiu-nos pelo topo do ecra. Isto NAO custa um lugar: ele ia a'
; nossa frente e continua a' nossa frente, so' nao chegamos a ultrapassa-lo. O
; castigo e' nao ganhar o lugar. Descer a posicao aqui era um erro grosseiro -
; bater num carro que estava prestes a ser ultrapassado fazia-nos passar, por
; exemplo, de 21.o para 22.o, quando ninguem nos tinha ultrapassado.
opp_esc:  xor a
          ld (oact),a
          ld (olines),a
          ret

; --- separacao entre os dois adversarios: se estao lado a lado e a' mesma
;     distancia, afasta o slot 2. Entra com C = x pretendido do slot 2 e
;     devolve C ja' corrigido; nao mexe em B nem D (centro e largura) ---
; O desvio tem de ser PERSISTENTE: o x pretendido e' recalculado da faixa em
; cada frame, por isso somar-lhe uns pixeis nao acumula nada. Guarda-se o
; desvio em osepx (com vi??s de 128 para nao haver contas com sinal) e mexe-se
; 4px por frame - ao contrario do salto de 22px de uma vez, que era o que se
; via como glitch quando os dois adversarios se cruzavam.
osepx:    db 128               ; 128 = sem desvio; margem util 96..160 (+-32)
opp_sep:  ld a,(oact)
          or a
          jr z,osp_dec         ; o outro nem esta' em pista: volta a' faixa
          ld a,(oy2+1)
          ld e,a
          ld a,(oy+1)
          sub e
          jr nc,osp_v
          neg
osp_v:    cp 24
          jr nc,osp_dec        ; longe verticalmente: podem cruzar-se. O limiar
                                 ; e' o dobro da folga que se quer, para dar
                                 ; tempo de desviar aos poucos
          ld a,(ox)            ; NAO se pode tocar em D: o chamador tem la' a
          ld e,a               ; meia-largura da estrada e usa-a a seguir para
          ld a,(osepx)         ; os limites laterais. So' A e E estao livres
          sub 128              ; (o chamador reatribui E logo a seguir)
          add a,c              ; A = x efectivo = pretendido + desvio actual
          sub e
          jr c,osp_l
          cp 22
          jr nc,osp_app        ; ja' esta' suficientemente a' direita
          ld a,(osepx)         ; mais 4px para a direita
          cp 160
          jr nc,osp_app
          add a,6
          ld (osepx),a
          jr osp_app
osp_l:    neg
          cp 22
          jr nc,osp_app        ; ja' esta' suficientemente a' esquerda
          ld a,(osepx)         ; mais 4px para a esquerda
          cp 97
          jr c,osp_app
          sub 6
          ld (osepx),a
          jr osp_app
osp_dec:  ld a,(osepx)         ; sem necessidade: regressa a' faixa aos poucos
          cp 128
          jr z,osp_app
          jr c,osp_du
          sub 6
          ld (osepx),a
          jr osp_app
osp_du:   add a,6
          ld (osepx),a
osp_app:  ld a,(osepx)
          sub 128
          add a,c
          ld c,a
          ret

; --- posicao na corrida: sobe (numero menor) a cada ultrapassagem nossa,
;     desce quando nos ultrapassam. Limites 1..9 ---
; melhor lugar possivel no fim de cada troco: da' 10, 10 e 9 ultrapassagens
; --- tabelas por troco (5 trocos) ---
; partindo em 30.o e ganhando 6 lugares por troco (5 no ultimo), chega-se a 1.o
posmin:   db 24,18,12,6,1
spdlvl:   db 5,6,7,7,7          ; velocidade maxima (7 e' o fundo da escala do
maxspd:   db 5                  ; ponteiro; acima disso nao havia como mostrar)
wlvl:     db 60,60,60,52,44     ; meia-largura da estrada: os dois ultimos
                                 ; trocos sao mais estreitos
grasslvl: db 0x67,0x70,0x50,0x68,0x58   ; verde, amarelo, vermelho, ciano, magenta
pos_up:   ld a,(mode)          ; so' o adversario (slot 1) mexe na posicao; o
          cp MODE_RACE         ; slot 2 e' trafego e nao conta para a corrida
          ret nz
          push hl
          ld a,(arclvl)        ; melhor lugar possivel neste troco
          dec a
          ld hl,posmin
          add a,l
          ld l,a
          jr nc,pu_n
          inc h
pu_n:     ld a,(racepos)
          cp (hl)
          pop hl
          ret z                ; ja' esgotou as ultrapassagens do troco
          ret c
          ld a,(racepos)
          dec a
          ld (racepos),a
          call sfx_pass
          call ay_pass
          jp pos_show
pos_show: ld hl,hudjob         ; os algarismos da posicao sao redesenhados no
          set 4,(hl)           ; topo dos frames seguintes (um por frame), fora
          set 5,(hl)           ; do caminho critico do feixe
          ret

; --- nascimento: por distancia percorrida, nao por tempo. So' no modo
;     race. Contagem DECRESCENTE em pares (o agendamento absoluto por
;     odom parava de funcionar quando o odom saturava aos ~4095m) ---
opp_spawn: ld a,(mode)
          cp MODE_RACE
          ret nz
          ld hl,(onextd)       ; a contagem corre no opp_tick, todos os frames
          ld a,h               ; (ver la' porque), aqui so' se ve' se chegou
          or l
          ret nz
          call rnd
          and 15
          ld b,a               ; base + 0..15 metros entre adversarios. Como a
          ld a,(dgapo)         ; conta corre sempre (opp_tick), este e' mesmo o
          add a,b              ; espacamento real. E' o travao principal da
                                 ; dificuldade: 65 da' ~15 adversarios num troco
                                 ; de 1100m para as 6 ultrapassagens precisas,
                                 ; 135 da' ~7 e ja' nao se pode falhar quase
                                 ; nenhuma
          ld l,a
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; hl = metros*16 = pares
          ld (onextd),hl
          ld a,(crashc)        ; nao nascem durante o despiste
          or a
          ret nz
          ld a,(steps)         ; nem com o carro quase parado
          cp 3
          ret c
os_born:  xor a
          ld (opassed),a       ; carro novo: ainda nao foi ultrapassado
          ld a,1
          ld (oact),a
          call opp_kind        ; adversario ou so' mais um carro de transito?
          ld hl,ROADTOP*256
          ld (oy),hl           ; nasce no horizonte (primeiro par desenhado)
          call rnd
          and 3
          ld hl,lanetab
          add a,l
          ld l,a
          jr nc,os_l
          inc h
os_l:     ld a,(hl)
          ld (olane),a
          call rnd             ; 1 em cada 4 muda de faixa enquanto anda
          and 3
          jr nz,os_nd
          call rnd
          and 1
          add a,a
          dec a                ; -1 ou +1
          jr os_dv
os_nd:    xor a
os_dv:    ld (olanev),a
          ld a,(steps)         ; velocidade relativa ao jogador: -1 (3/4) ou -2 (1/4)
          ld b,a               ; (mais lento em media do que 50/50)
          call rnd
          and 3
          ld c,1
          jr nz,os_c1
          ld c,2
os_c1:    ld a,b
          sub c
          jr nc,os_v
          xor a
os_v:     push af              ; o rnd destroi HL (ld hl,(rndv)): guardar a subtracao
          call rnd
          and 63               ; a parte fraccionaria so' pode roubar 1/4 de par
          ld l,a               ; por frame. Com os 0..255 antigos, um adversario
                                 ; podia vir praticamente a' nossa velocidade e
                                 ; ficar no ecra dezenas de segundos - era a
                                 ; outra razao para aparecerem tao poucos
          pop af
          ld h,a
          ld (ospd),hl
          jp opp_upd           ; nao voltar aqui com o oybot/ox do carro ANTERIOR:
                                 ; ficavam a dizer "fundo no par 80, ao lado do
                                 ; jogador" e o opp_hit desse mesmo frame dava
                                 ; choque com um carro acabado de nascer no
                                 ; horizonte - o "choque com carro que nao se ve".
                                 ; Com o oact ja' a 1, o opp_upd segue pelo ramo
                                 ; normal e deixa tudo coerente.
lanetab:  db 0xE8,0x00,0x18,0x00

; --- embate com o adversario ---
opp_hit:  ld a,(oact)
          or a
          ret z
          ld a,(crashc)
          or a
          ret nz
          ld a,(swipec)        ; cooldown da rocadela / imunidade pos-despiste
          or a
          ret nz
          ld a,(oybot)         ; o CORPO do nosso carro ocupa os pares 60..67
          cp 61                ; (y=121..134), nao os 72 da janela do sprite.
          ret c                ; oybot = par de baixo exclusivo do adversario
          ld a,(oy+1)          ; e oy+1 o de cima: sobreposicao real e'
          cp 68                ; oybot>=61 e topo<=67
          ret nc
          ld a,(ox)
          ld b,a
          ld a,(carx)
          sub b
          jr nc,oh_p
          neg
oh_p:     cp 10                ; adversario e nosso tem o mesmo corpo: ox+3..
          ret nc               ; ox+12 (10px). Tocam-se ate' |dx|=9. Bater em
          cp 5                 ; CHEIO corta a velocidade; rocar so' empurra
          jp c,oh_full
oh_swipe: call sfx_bump
          ld a,(ox)            ; --- rocadela: empurrao + travagem ---
          ld b,a
          ld a,(carx)
          cp b
          jr c,oh_pl           ; o adversario esta' a' direita: empurra p'ra esq
          add a,10
          jr oh_pc
oh_pl:    sub 10
oh_pc:    cp MINX
          jr nc,oh_p1
          ld a,MINX
oh_p1:    cp MAXX
          jr c,oh_p2
          ld a,MAXX
oh_p2:    ld (carx),a
          ld hl,(spd)          ; e perde velocidade, mas nao para
          ld de,BRK2
          or a
          sbc hl,de
          jr nc,oh_p3
          ld hl,0
oh_p3:    ld (spd),hl
          ld a,16
          ld (swipec),a        ; ~0.3s ate poder haver nova rocadela
          ret

; --- bater em cheio: corta a velocidade para pouco menos de metade e segue.
;     Nao conta como despiste - nao pisca, nao recentra o carro, e o adversario
;     fica em pista. Como passa a ser mais rapido do que nos, afasta-se
;     sozinho; o cooldown evita um segundo embate no mesmo instante ---
oh_full:  jr ohf_body          ; entradas separadas: com as duas no mesmo
oh2_full: jr ohf_body          ; endereco nao se distinguia qual dos
                                 ; adversarios tinha batido
ohf_body: call sfx_bump
          ld hl,(spd)
          srl h
          rr l                 ; metade
          ld de,0x0040
          or a
          sbc hl,de            ; e um pouco menos
          jr nc,ohf_s
          ld hl,0
ohf_s:    ld (spd),hl
          ld a,16
          ld (swipec),a
          ret

; =================================================================
; VAGA 2 DE ADVERSARIO: copia exata da vaga 1, variaveis com sufixo 2
; =================================================================
clr_oldopp2: ld a,(ooldn2)
          or a
          ret z
          ld b,a
          xor a
          ld (ooldn2),a
          ld a,(ooldx2)
          srl a
          srl a
          srl a
          ld c,a
          ld a,(ooldy2)
          call getaddr
          ex de,hl
co2_l:    xor a
          ld (de),a
          inc e
          ld (de),a
          inc e
          ld (de),a
          dec e
          dec e
          inc d
          ld a,d
          and 7
          jr nz,co2_ok
          ld a,e
          add a,32
          ld e,a
          jr c,co2_ok
          ld a,d
          sub 8
          ld d,a
co2_ok:   djnz co2_l
          ret

or_opp2:  ld a,(olines2)
          or a
          ret z
          ld a,(ox2)
          and 7
          ld l,a
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; x16
          ld e,l
          ld d,h
          add hl,hl            ; x32
          add hl,de            ; x48 (16 linhas x 3 bytes)
          ld de,(ospr2)        ; a 2a vaga e' trafego: um dos tres carros,
          add hl,de            ; sorteado no nascimento
          push hl
          ld a,(ox2)
          ld (ooldx2),a
          srl a
          srl a
          srl a
          ld c,a
          ld a,(oy2+1)
          add a,a              ; par -> linha de pixels
          ld (ooldy2),a
          call getaddr
          ex de,hl             ; DE = ecra
          pop hl               ; HL = sprite
          ld a,(olines2)
          ld (ooldn2),a
          ld b,a
or2_lines: ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          inc e
          ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          inc e
          ld a,(de)
          or (hl)
          ld (de),a
          inc hl
          dec e
          dec e
          inc d
          ld a,d
          and 7
          jr nz,ol2_ok
          ld a,e
          add a,32
          ld e,a
          jr c,ol2_ok
          ld a,d
          sub 8
          ld d,a
ol2_ok:   djnz or2_lines
          ret

opp_upd2: ld a,(oact2)
          or a
          jp z,opp_spawn2
          ld hl,(oy2)          ; desce com a estrada, sobe com a sua velocidade
          ld a,(steps)
          ld d,a
          ld e,0
          add hl,de
          ld de,(ospd2)
          or a
          sbc hl,de
          jr nc,ou2_c0         ; sem estouro: segue normalmente
          ld hl,ROADTOP*256    ; travagem momentanea nao mata o adversario
          jr ou2_clamp
ou2_c0:   ld a,h               ; nunca acima do horizonte (par nao desenhado)
          cp ROADTOP
          jr nc,ou2_clamp
          jp opp2_esc          ; fugiu por cima
ou2_clamp:
          ld (oy2),hl
          ld a,h
          cp NPAIR
          jr nc,opp2_off       ; saiu por baixo
          ld l,a               ; centro da estrada nesse par
          ld h,0
          ld de,cenbuf
          add hl,de
          ld b,(hl)
          ld a,(bpos)          ; largura nesse par
          or a
          jr z,ou2_wb
          ld hl,oy2+1
          cp (hl)
          jr c,ou2_wb
          jr z,ou2_wb
          ld a,(wtop)
          jr ou2_w
ou2_wb:   ld a,(wbot)
ou2_w:    ld d,a
          call lane_drift2
          ld a,(olane2)        ; x = centro + faixa - 8
          add a,b
          sub 8
          ld c,a
          call opp_sep         ; afasta-o do outro adversario (antes dos
                                ; limites da estrada, para nao o empurrar
                                ; para fora ao evitar a colisao)
          ld a,b               ; limite esquerdo: centro - largura + 2
          sub d
          add a,2
          ld e,a
          ld a,c
          cp e
          jr nc,ou2_x1
          ld c,e
ou2_x1:   ld a,b               ; limite direito: centro + largura - 18
          add a,d
          sub 18
          ld e,a
          ld a,c
          cp e
          jr c,ou2_x2
          ld c,e
ou2_x2:   ld a,c
          ld (ox2),a
          ld a,(oy2+1)         ; banda vertical ocupada (com corte em baixo)
          ld b,a
          add a,8              ; 8 pares = 16 linhas (mesmo sprite do slot 1)
          cp NPAIR
          jr c,ou2_n
          ld a,NPAIR
ou2_n:    ld (oybot2),a
          sub b
          add a,a
          ld (olines2),a
          ret
opp2_off: xor a                ; o slot 2 e' TRAFEGO: ultrapassa-lo (ou ser
          ld (oact2),a         ; ultrapassado por ele) nao mexe na posicao da
          ld (olines2),a       ; corrida - so' o slot 1 e' adversario a serio
          ret
opp2_esc: xor a
          ld (oact2),a
          ld (olines2),a
          ret

; --- nascimento: por distancia percorrida (odom), nao por tempo ---
opp_spawn2: ld a,(mode)      ; trafego so' no modo race
          cp MODE_RACE
          ret nz
          ld hl,(onextd2)      ; idem: a contagem corre no opp_tick2
          ld a,h
          or l
          ret nz
          call rnd
          and 7
          ld b,a               ; base + 0..7 metros: com o adversario a aparecer
          ld a,(dgapt)         ; de longe em longe, e' o trafego que mantem a
          add a,b              ; estrada com movimento. Nas dificuldades altas
                                 ; adensa-se, para obrigar mesmo a guiar
          ld l,a
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; hl = metros*16 = pares
          ld (onextd2),hl
          ld a,(crashc)        ; nao nascem durante o despiste
          or a
          ret nz
          ld a,(steps)         ; nem com o carro quase parado
          cp 3
          ret c
os2_born: ld a,128
          ld (osepx),a         ; carro novo comeca sem desvio
          ld a,1
          ld (oact2),a
          call traf_pick       ; cada carro de transito sorteia o seu desenho
          ld (ospr2),hl
          ld hl,ROADTOP*256
          ld (oy2),hl          ; nasce no horizonte
          call rnd
          and 3
          ld hl,lanetab
          add a,l
          ld l,a
          jr nc,os2_l
          inc h
os2_l:    ld a,(hl)
          ld (olane2),a
          ld a,(oact)          ; se o adversario tambem esta' no horizonte, o
          or a                 ; carro novo nasce ja' na faixa oposta: nascer
          jr z,os2_ln          ; em cima dele nao dava tempo ao opp_sep de os
          ld a,(oy+1)          ; afastar aos poucos, e ficavam sobrepostos os
          sub ROADTOP          ; primeiros frames
          cp 24
          jr nc,os2_ln
          ld a,(olane)         ; ele a' esquerda (faixa negativa)? nasce a'
          and 0x80             ; direita, e vice-versa
          jr z,os2_lneg
          ld a,0x18
          jr os2_lst
os2_lneg: ld a,0xE8
os2_lst:  ld (olane2),a
os2_ln:   call rnd             ; idem: 1 em cada 4 muda de faixa
          and 3
          jr nz,os2_nd
          call rnd
          and 1
          add a,a
          dec a
          jr os2_dv
os2_nd:   xor a
os2_dv:   ld (olanev2),a
          ld a,(steps)         ; velocidade relativa ao jogador: -1 ou -2
          ld b,a
          call rnd
          and 1
          inc a                ; 1 ou 2
          ld c,a
          ld a,b
          sub c
          jr nc,os2_v
          xor a
os2_v:    push af              ; call rnd faz "ld hl,(rndv)": destruiria H
          call rnd
          and 63               ; idem: sem isto o trafego colava-se a nos
          ld l,a
          pop af
          ld h,a
          ld (ospd2),hl
          jp opp_upd2          ; mesmo motivo do slot 1: sair daqui sem passar
                                 ; pelo opp_upd2 deixava oybot2/ox2 do carro
                                 ; anterior e dava choques invisiveis

; --- embate com o adversario ---
opp_hit2: ld a,(oact2)
          or a
          ret z
          ld a,(crashc)
          or a
          ret nz
          ld a,(swipec)
          or a
          ret nz
          ld a,(oybot2)        ; carro do udg5: pixels nas linhas 1..14, ou
          cp 61                ; seja os 8 pares todos, como o slot 1
          ret c
          ld a,(oy2+1)
          cp 68
          ret nc
          ld a,(ox2)
          ld b,a
          ld a,(carx)
          sub b
          jr nc,oh2_p
          neg
oh2_p:    cp 10                ; corpo ox2+3..ox2+12 (10px), igual ao nosso:
          ret nc               ; tocam-se ate' |dx|=9. Em cheio para, de lado
          cp 5                 ; empurra - mesma regra do slot 1
          jp c,oh2_full
oh2_swipe: call sfx_bump
          ld a,(ox2)
          ld b,a
          ld a,(carx)
          cp b
          jr c,oh2_pl
          add a,10
          jr oh2_pc
oh2_pl:   sub 10
oh2_pc:   cp MINX
          jr nc,oh2_p1
          ld a,MINX
oh2_p1:   cp MAXX
          jr c,oh2_p2
          ld a,MAXX
oh2_p2:   ld (carx),a
          ld hl,(spd)
          ld de,BRK2
          or a
          sbc hl,de
          jr nc,oh2_p3
          ld hl,0
oh2_p3:   ld (spd),hl
          ld a,16
          ld (swipec),a
          ret

; --- gerador pseudo-aleatorio ---
rnd:      ld hl,(rndv)
          ld d,h
          ld e,l
          add hl,hl
          add hl,hl
          add hl,de
          inc hl
          ld (rndv),hl
          ld a,h
          ret


; adversario: o carro do udg10.asm. 16 linhas x 3 bytes, 8 copias pre-deslocadas (passo 48)
advbox_m:
          db 0,0,0,5,160,0,13,176,0,29,184,0
          db 16,8,0,21,168,0,13,176,0,13,176,0
          db 13,176,0,13,176,0,24,24,0,16,8,0
          db 29,184,0,21,168,0,13,176,0,0,0,0
          db 0,0,0,2,208,0,6,216,0,14,220,0
          db 8,4,0,10,212,0,6,216,0,6,216,0
          db 6,216,0,6,216,0,12,12,0,8,4,0
          db 14,220,0,10,212,0,6,216,0,0,0,0
          db 0,0,0,1,104,0,3,108,0,7,110,0
          db 4,2,0,5,106,0,3,108,0,3,108,0
          db 3,108,0,3,108,0,6,6,0,4,2,0
          db 7,110,0,5,106,0,3,108,0,0,0,0
          db 0,0,0,0,180,0,1,182,0,3,183,0
          db 2,1,0,2,181,0,1,182,0,1,182,0
          db 1,182,0,1,182,0,3,3,0,2,1,0
          db 3,183,0,2,181,0,1,182,0,0,0,0
          db 0,0,0,0,90,0,0,219,0,1,219,128
          db 1,0,128,1,90,128,0,219,0,0,219,0
          db 0,219,0,0,219,0,1,129,128,1,0,128
          db 1,219,128,1,90,128,0,219,0,0,0,0
          db 0,0,0,0,45,0,0,109,128,0,237,192
          db 0,128,64,0,173,64,0,109,128,0,109,128
          db 0,109,128,0,109,128,0,192,192,0,128,64
          db 0,237,192,0,173,64,0,109,128,0,0,0
          db 0,0,0,0,22,128,0,54,192,0,118,224
          db 0,64,32,0,86,160,0,54,192,0,54,192
          db 0,54,192,0,54,192,0,96,96,0,64,32
          db 0,118,224,0,86,160,0,54,192,0,0,0
          db 0,0,0,0,11,64,0,27,96,0,59,112
          db 0,32,16,0,43,80,0,27,96,0,27,96
          db 0,27,96,0,27,96,0,48,48,0,32,16
          db 0,59,112,0,43,80,0,27,96,0,0,0

; trafego 1: o carro do udg11.asm, mesmo formato
advbox_v:
          db 0,0,0,5,160,0,11,208,0,19,200,0
          db 28,56,0,24,24,0,31,248,0,13,176,0
          db 9,144,0,9,144,0,9,144,0,31,248,0
          db 30,120,0,25,152,0,13,176,0,0,0,0
          db 0,0,0,2,208,0,5,232,0,9,228,0
          db 14,28,0,12,12,0,15,252,0,6,216,0
          db 4,200,0,4,200,0,4,200,0,15,252,0
          db 15,60,0,12,204,0,6,216,0,0,0,0
          db 0,0,0,1,104,0,2,244,0,4,242,0
          db 7,14,0,6,6,0,7,254,0,3,108,0
          db 2,100,0,2,100,0,2,100,0,7,254,0
          db 7,158,0,6,102,0,3,108,0,0,0,0
          db 0,0,0,0,180,0,1,122,0,2,121,0
          db 3,135,0,3,3,0,3,255,0,1,182,0
          db 1,50,0,1,50,0,1,50,0,3,255,0
          db 3,207,0,3,51,0,1,182,0,0,0,0
          db 0,0,0,0,90,0,0,189,0,1,60,128
          db 1,195,128,1,129,128,1,255,128,0,219,0
          db 0,153,0,0,153,0,0,153,0,1,255,128
          db 1,231,128,1,153,128,0,219,0,0,0,0
          db 0,0,0,0,45,0,0,94,128,0,158,64
          db 0,225,192,0,192,192,0,255,192,0,109,128
          db 0,76,128,0,76,128,0,76,128,0,255,192
          db 0,243,192,0,204,192,0,109,128,0,0,0
          db 0,0,0,0,22,128,0,47,64,0,79,32
          db 0,112,224,0,96,96,0,127,224,0,54,192
          db 0,38,64,0,38,64,0,38,64,0,127,224
          db 0,121,224,0,102,96,0,54,192,0,0,0
          db 0,0,0,0,11,64,0,23,160,0,39,144
          db 0,56,112,0,48,48,0,63,240,0,27,96
          db 0,19,32,0,19,32,0,19,32,0,63,240
          db 0,60,240,0,51,48,0,27,96,0,0,0

; trafego 2: o carro do udg12.asm, mesmo formato
advbox_v2:
          db 0,0,0,1,128,0,5,160,0,13,176,0
          db 31,248,0,31,248,0,28,56,0,8,16,0
          db 11,208,0,11,208,0,12,48,0,24,24,0
          db 23,232,0,16,8,0,15,240,0,0,0,0
          db 0,0,0,0,192,0,2,208,0,6,216,0
          db 15,252,0,15,252,0,14,28,0,4,8,0
          db 5,232,0,5,232,0,6,24,0,12,12,0
          db 11,244,0,8,4,0,7,248,0,0,0,0
          db 0,0,0,0,96,0,1,104,0,3,108,0
          db 7,254,0,7,254,0,7,14,0,2,4,0
          db 2,244,0,2,244,0,3,12,0,6,6,0
          db 5,250,0,4,2,0,3,252,0,0,0,0
          db 0,0,0,0,48,0,0,180,0,1,182,0
          db 3,255,0,3,255,0,3,135,0,1,2,0
          db 1,122,0,1,122,0,1,134,0,3,3,0
          db 2,253,0,2,1,0,1,254,0,0,0,0
          db 0,0,0,0,24,0,0,90,0,0,219,0
          db 1,255,128,1,255,128,1,195,128,0,129,0
          db 0,189,0,0,189,0,0,195,0,1,129,128
          db 1,126,128,1,0,128,0,255,0,0,0,0
          db 0,0,0,0,12,0,0,45,0,0,109,128
          db 0,255,192,0,255,192,0,225,192,0,64,128
          db 0,94,128,0,94,128,0,97,128,0,192,192
          db 0,191,64,0,128,64,0,127,128,0,0,0
          db 0,0,0,0,6,0,0,22,128,0,54,192
          db 0,127,224,0,127,224,0,112,224,0,32,64
          db 0,47,64,0,47,64,0,48,192,0,96,96
          db 0,95,160,0,64,32,0,63,192,0,0,0
          db 0,0,0,0,3,0,0,11,64,0,27,96
          db 0,63,240,0,63,240,0,56,112,0,16,32
          db 0,23,160,0,23,160,0,24,96,0,48,48
          db 0,47,208,0,32,16,0,31,224,0,0,0

; trafego 3: o carro do udg13.asm, mesmo formato
advbox_v3:
          db 0,0,0,1,128,0,13,176,0,13,176,0
          db 13,176,0,2,64,0,4,32,0,4,32,0
          db 7,224,0,7,224,0,7,224,0,27,216,0
          db 24,24,0,27,216,0,2,64,0,0,0,0
          db 0,0,0,0,192,0,6,216,0,6,216,0
          db 6,216,0,1,32,0,2,16,0,2,16,0
          db 3,240,0,3,240,0,3,240,0,13,236,0
          db 12,12,0,13,236,0,1,32,0,0,0,0
          db 0,0,0,0,96,0,3,108,0,3,108,0
          db 3,108,0,0,144,0,1,8,0,1,8,0
          db 1,248,0,1,248,0,1,248,0,6,246,0
          db 6,6,0,6,246,0,0,144,0,0,0,0
          db 0,0,0,0,48,0,1,182,0,1,182,0
          db 1,182,0,0,72,0,0,132,0,0,132,0
          db 0,252,0,0,252,0,0,252,0,3,123,0
          db 3,3,0,3,123,0,0,72,0,0,0,0
          db 0,0,0,0,24,0,0,219,0,0,219,0
          db 0,219,0,0,36,0,0,66,0,0,66,0
          db 0,126,0,0,126,0,0,126,0,1,189,128
          db 1,129,128,1,189,128,0,36,0,0,0,0
          db 0,0,0,0,12,0,0,109,128,0,109,128
          db 0,109,128,0,18,0,0,33,0,0,33,0
          db 0,63,0,0,63,0,0,63,0,0,222,192
          db 0,192,192,0,222,192,0,18,0,0,0,0
          db 0,0,0,0,6,0,0,54,192,0,54,192
          db 0,54,192,0,9,0,0,16,128,0,16,128
          db 0,31,128,0,31,128,0,31,128,0,111,96
          db 0,96,96,0,111,96,0,9,0,0,0,0
          db 0,0,0,0,3,0,0,27,96,0,27,96
          db 0,27,96,0,4,128,0,8,64,0,8,64
          db 0,15,192,0,15,192,0,15,192,0,55,176
          db 0,48,48,0,55,176,0,4,128,0,0,0

; --- imagem de espera: o piloto a correr para o Mini, 128x48 (16x6 chars),
;     desenhada no ecra de arranque de troco. 768 bytes ---
waitimg:
          db 0,0,0,15,192,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,24,96,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,48,48,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,32,24,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,32,8,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,32,232,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,33,252,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,49,240,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,0,62,240,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,7,255,120,0,0,0,0,0,0,0,0,0,0,0
          db 0,0,127,255,56,0,0,0,0,3,255,255,240,0,0,0
          db 0,3,255,191,240,0,0,0,0,255,255,255,255,192,0,0
          db 0,7,232,31,96,0,0,0,7,254,0,0,15,252,0,0
          db 0,7,128,15,128,0,0,0,31,15,255,255,128,62,0,0
          db 0,15,0,53,128,0,0,0,63,254,0,0,127,237,0,0
          db 0,12,127,5,128,0,0,0,97,255,255,159,0,1,128,0
          db 0,24,204,7,128,0,0,0,63,255,255,163,255,255,128,0
          db 0,28,136,11,199,128,0,0,112,63,255,247,255,255,192,0
          db 0,31,24,11,254,192,0,0,112,12,31,223,255,3,192,0
          db 0,30,24,31,234,192,0,0,224,12,7,223,3,3,192,0
          db 0,19,30,23,141,128,0,1,224,12,7,254,3,1,224,0
          db 0,17,63,191,159,0,0,1,192,28,7,236,3,0,224,0
          db 0,27,48,251,240,0,0,1,192,28,7,172,3,0,240,0
          db 0,14,96,113,192,0,0,3,192,28,7,175,131,14,208,0
          db 0,0,96,48,0,0,0,3,192,29,255,231,251,153,232,0
          db 0,0,98,28,0,0,0,6,255,255,255,224,127,255,232,0
          db 0,0,115,6,0,0,0,6,127,247,255,192,15,255,252,0
          db 0,0,248,195,0,0,0,12,0,44,0,16,7,255,255,128
          db 0,0,254,97,128,0,0,16,0,62,0,16,0,0,7,240
          db 0,1,255,152,192,0,0,32,0,124,0,16,0,32,1,12
          db 0,3,63,228,96,0,0,96,0,96,0,8,0,240,0,158
          db 28,230,254,59,32,0,0,111,0,96,0,15,129,152,8,58
          db 63,60,252,15,32,0,0,216,192,96,0,16,97,136,0,50
          db 62,13,216,7,48,0,0,255,96,96,0,32,49,155,255,178
          db 127,195,48,5,144,0,0,255,240,96,0,79,216,222,0,126
          db 126,126,224,7,144,0,0,255,208,96,0,95,232,127,255,254
          db 255,129,192,2,152,0,0,248,240,96,0,255,244,79,255,236
          db 240,255,128,3,216,0,0,246,240,96,0,251,116,237,200,252
          db 224,14,0,3,72,0,1,255,120,96,0,247,244,239,255,252
          db 192,0,0,1,232,192,1,237,120,96,0,247,186,78,0,70
          db 0,0,0,1,185,192,0,233,247,255,255,228,255,255,255,253
          db 0,0,0,0,255,192,0,45,248,0,0,228,249,0,0,1
          db 0,0,0,0,127,128,0,47,127,255,255,230,255,255,255,254
          db 0,0,0,0,127,0,0,55,127,255,255,247,191,255,129,252
          db 0,0,0,0,62,0,0,58,248,0,127,247,127,255,255,240
          db 0,0,0,0,28,0,0,31,248,0,127,250,126,255,255,240
          db 0,0,0,0,0,0,0,15,240,0,63,207,252,0,63,224
          db 0,0,0,0,0,0,0,0,0,0,0,15,248,0,31,192


; ==================== SOM AY (128K) ====================
; O AY gera a onda em hardware: o CPU so' lhe escreve registos uma vez por
; frame. Nada do que estragou o beeper - ondas cortadas pela interrupcao,
; afinacao a oscilar com a carga do frame - se aplica aqui.
AY_SEL    equ 0xFFFD
AY_DAT    equ 0xBFFD

is128k:   db 0
mus_on:   db 0                 ; 1 = musica a tocar
mus_step: dw 0                 ; semicolcheia actual (0..511)
mus_tick: db 1                 ; frames ate a' seguinte
mus_va:   db 0                 ; volumes correntes (com decaimento)
mus_vb:   db 0
mus_vc:   db 0
blipc:    db 0                 ; frames que faltam do blip da ultrapassagem
opassed:  db 0                 ; 1 = ja. contamos a ultrapassagem deste carro

; --- deteccao do AY: escreve 0xFF no registo 1, que so' guarda 4 bits, e le'
;     de volta. Com AY vem 0x0F; sem AY o barramento flutuante da' 0xFF.
;     Nao mexe na paginacao - o nosso codigo vive acima de 0xC000 e paginar
;     ali trocava-o por baixo dos pes ---
det_ay:   ld bc,AY_SEL
          ld a,1
          out (c),a
          ld bc,AY_DAT
          ld a,0xFF
          out (c),a
          ld bc,AY_SEL
          in a,(c)
          cp 0x0F
          ld a,0
          jr nz,day_no
          inc a
day_no:   ld (is128k),a
          or a
          ret z
          jp ay_silence

; --- A = registo, E = valor ---
ay_out:   push bc
          ld bc,AY_SEL
          out (c),a
          ld bc,AY_DAT
          out (c),e
          pop bc
          ret

; --- cala os tres canais ---
ay_silence: ld a,(is128k)
          or a
          ret z
          ld a,8
          ld e,0
          call ay_out
          ld a,9
          ld e,0
          call ay_out
          ld a,10
          ld e,0
          jp ay_out
mus_hush: xor a                ; usado antes dos ecras que bloqueiam
          ld (mus_va),a
          ld (mus_vb),a
          ld (mus_vc),a
          jp ay_silence

mus_init: ld a,(is128k)
          or a
          ret z
          xor a
          ld (mus_step),a
          ld (mus_step+1),a
          ld (blipc),a
          ld (mus_va),a        ; volumes a zero: com a musica desligada nao ha'
          ld (mus_vb),a        ; mus_decay a repo-los e ficava um tom preso
          ld (mus_vc),a
          ld a,1
          ld (mus_tick),a
          ld a,(musopt)        ; a musica pode estar desligada no menu; o AY
          ld (mus_on),a        ; fica pronto na mesma, para o blip
          ld a,7               ; mixer: tons A,B,C ligados, ruido desligado
          ld e,0x38
          call ay_out
          jp ay_silence        ; volumes a zero ate' a' primeira nota

; --- A = indice da nota (0 = silencio), C = registo do periodo (0,2,4) ---
ay_note:  or a
          ret z
          dec a
          ld l,a
          ld h,0
          add hl,hl
          ld de,notetab
          add hl,de
          ld a,c
          ld e,(hl)
          call ay_out          ; byte baixo do periodo
          inc hl
          ld a,c
          inc a
          ld e,(hl)
          jp ay_out            ; byte alto

; --- uma vez por frame ---
mus_play: ld a,(is128k)
          or a
          ret z
          ld a,(mus_on)
          or a
          jp z,blip_only       ; musica desligada: o blip da ultrapassagem nao
                                 ; e' musica e tem de continuar a ouvir-se
          call mus_decay
          ld hl,blipc          ; blip da ultrapassagem: toma o canal C
          ld a,(hl)
          or a
          jr z,mp_not
          dec (hl)
mp_not:   ld hl,mus_tick
          dec (hl)
          ret nz
          ld (hl),6            ; 6 frames por semicolcheia = 125 BPM

          ld hl,(mus_step)     ; --- passo novo ---
          ld a,l
          and 15
          ld c,a               ; C = posicao dentro do compasso
          push bc
          srl h
          rr l
          srl h
          rr l
          srl h
          rr l
          srl h
          rr l                 ; HL = compasso (0..31)
          ld de,mus_seq
          add hl,de
          ld a,(hl)            ; A = acorde
          pop bc
          ld b,a

          bit 0,c              ; baixo: so' nas colcheias (posicoes pares)
          jr nz,mp_arp
          ld a,b               ; indice = acorde*8 + posicao/2
          add a,a
          add a,a
          add a,a
          srl c
          add a,c
          sla c                ; repor C
          ld l,a
          ld h,0
          ld de,mus_bass
          add hl,de
          ld a,(hl)
          push bc
          ld c,0               ; registos 0/1 = canal A
          call ay_note
          pop bc
          ld a,14
          ld (mus_va),a

mp_arp:   ld a,b               ; arpejo: indice = acorde*4 + (posicao & 3)
          add a,a
          add a,a
          ld e,a
          ld a,c
          and 3
          add a,e
          ld l,a
          ld h,0
          ld de,mus_arp
          add hl,de
          ld a,(hl)
          push bc
          ld c,2               ; registos 2/3 = canal B
          call ay_note
          pop bc
          ld a,10
          ld (mus_vb),a

          ld hl,(mus_step)     ; melodia: uma entrada por semicolcheia
          ld de,mus_mel
          add hl,de
          ld a,(hl)
          cp 255
          jr z,mp_next         ; 255 = manter a nota
          push af
          ld c,4               ; registos 4/5 = canal C
          call ay_note
          pop af
          or a
          ld a,0
          jr z,mp_setc
          ld a,15
mp_setc:  ld (mus_vc),a

mp_next:  ld hl,(mus_step)
          inc hl
          ld de,512
          or a
          sbc hl,de
          jr nc,mp_wrap
          add hl,de
mp_wrap:  ld (mus_step),hl
          ret

; --- decaimento dos volumes; o blip sobrepoe-se ao canal C ---
mus_decay: ld hl,mus_va
          ld a,(hl)
          cp 9
          jr c,md_a
          dec (hl)
md_a:     ld a,8
          ld e,(hl)
          call ay_out
          ld hl,mus_vb
          ld a,(hl)
          cp 6
          jr c,md_b
          dec (hl)
md_b:     ld a,9
          ld e,(hl)
          call ay_out
          ld hl,mus_vc
          ld a,(hl)
          cp 10
          jr c,md_c
          dec (hl)
md_c:     ld hl,mus_vc         ; volume normal do canal C (a melodia)
          ld a,10
          ld e,(hl)
          call ay_out
          ld a,(blipc)         ; o blip vai por cima do ARPEJO, nao da melodia:
          or a                 ; perder 160ms de arpejo nao se nota, perder a
          ret z                ; melodia notava-se logo
          jp blip_set

; --- efeito de ultrapassagem: no AY e' um blip limpo de 200ms que nao custa
;     frames nenhuns. No beeper era meio milissegundo e nao se ouvia ---
ay_pass:  ld a,(is128k)
          or a
          ret z
          ld a,8
          ld (blipc),a
          ret
; ================= MUSICA (AY, 128K) =================
; 32 compassos A-A'-B-A'', 125 BPM (6 frames por semicolcheia).
; O baixo e o arpejo sao padroes por acorde; so' a melodia vai passo a
; passo. 0 = silencio, 255 = manter a nota anterior.
; periodos do AY (relogio 1773400 Hz), indice 1..N
notetab:
          dw 1008,673,504,424,336,1270,847,635
          dw 566,283,1131,755,449,377,1345,898
          dw 317,252,212,168,189,224,159,141
          dw 126,112
; sequencia de acordes, um por compasso
mus_seq:
          db 0,1,2,3,0,1,3,3,0,1,2,3,0,1,3,3
          db 1,3,4,0,1,3,2,3,0,1,2,3,0,1,3,3
; padroes do baixo: 8 colcheias por acorde
mus_bass:
          db 1,1,2,1,1,1,2,1
          db 6,6,7,6,6,6,7,6
          db 7,7,9,7,7,7,9,7
          db 11,11,12,11,11,11,12,11
          db 15,15,16,15,15,15,16,15
          db 12,12,3,12,12,12,3,12
; padroes do arpejo: 4 semicolcheias por acorde
mus_arp:
          db 3,4,5,4
          db 8,3,4,3
          db 4,5,10,5
          db 9,13,14,13
          db 2,9,13,9
          db 14,17,18,17
; melodia, uma entrada por semicolcheia
mus_mel:
          db 18,255,19,255,20,255,255,255,21,255,19,255,22,255,255,255
          db 18,255,19,255,23,255,255,255,20,255,21,255,19,255,255,255
          db 10,255,19,255,20,255,255,255,24,255,20,255,19,255,255,255
          db 21,255,22,255,10,255,255,255,18,255,22,255,21,255,255,255
          db 18,255,19,255,20,255,255,255,21,255,19,255,22,255,255,255
          db 18,255,19,255,23,255,255,255,20,255,21,255,19,255,255,255
          db 21,255,255,255,20,255,255,255,24,255,255,255,23,255,20,255
          db 21,255,255,255,255,255,0,255,255,255,255,255,255,255,255,255
          db 20,255,21,255,19,255,255,255,22,255,19,255,20,255,255,255
          db 23,255,20,255,21,255,255,255,19,255,18,255,19,255,255,255
          db 20,255,24,255,25,255,255,255,24,255,20,255,24,255,255,255
          db 23,255,21,255,22,255,255,255,21,255,23,255,25,255,255,255
          db 25,255,24,255,20,255,255,255,21,255,19,255,22,255,255,255
          db 18,255,19,255,23,255,255,255,20,255,21,255,19,255,255,255
          db 22,255,255,255,21,255,255,255,24,255,255,255,23,255,21,255
          db 20,255,255,255,255,255,0,255,255,255,255,255,255,255,255,255
          db 19,255,255,255,21,255,255,255,23,255,255,255,255,255,255,255
          db 21,255,255,255,20,255,255,255,24,255,255,255,255,255,255,255
          db 20,255,255,255,21,255,255,255,22,255,255,255,255,255,255,255
          db 19,255,255,255,22,255,255,255,18,255,255,255,255,255,255,255
          db 19,255,255,255,23,255,255,255,25,255,255,255,255,255,255,255
          db 22,255,255,255,21,255,255,255,24,255,255,255,255,255,255,255
          db 20,255,255,255,24,255,255,255,20,255,255,255,19,255,255,255
          db 21,255,255,255,255,255,255,255,0,255,255,255,255,255,255,255
          db 18,255,19,255,20,255,255,255,21,255,19,255,22,255,255,255
          db 18,255,19,255,23,255,255,255,20,255,21,255,19,255,255,255
          db 10,255,19,255,20,255,255,255,24,255,20,255,19,255,255,255
          db 21,255,22,255,10,255,255,255,18,255,22,255,21,255,255,255
          db 18,255,19,255,20,255,255,255,21,255,19,255,22,255,255,255
          db 18,255,19,255,23,255,255,255,20,255,21,255,19,255,255,255
          db 21,255,20,255,24,255,25,255,26,255,255,255,25,255,255,255
          db 24,255,255,255,20,255,255,255,21,255,255,255,0,255,255,255

; ================= COMANDOS, JINGLE, BARRA E DIFICULDADE =================
; Tudo o que se segue ficou aqui de proposito: o espaco antes das tabelas
; alinhadas em 0x8800 esta' contado ao byte e ja' partiu o jogo em silencio
; quatro vezes. Aqui em baixo ha' folga ate' ao LOGOBUF.

; --- leitura de comandos, normalizada: devolve em A os bits ACTIVOS A 1,
;     bit0 = direita, bit1 = esquerda, bit2 = acelerador, bit3 = travao.
;     O resto do jogo deixa de saber de onde veio o comando. ---
rd_ctl:   ld a,(ctrl)
          or a
          jr nz,rc_joy
          ld bc,0xDFFE         ; O e P
          in a,(c)
          cpl
          and 3                ; bit0 = P (direita), bit1 = O (esquerda)
          ld e,a
          ld bc,0xFBFE         ; Q = acelerador
          in a,(c)
          cpl
          and 1
          add a,a
          add a,a              ; -> bit2
          or e
          ld e,a
          ld bc,0xFDFE         ; A = travao
          in a,(c)
          cpl
          and 1
          add a,a
          add a,a
          add a,a              ; -> bit3
          or e
          ret
; Kempston na porta 0x1F com o byte alto a zero (a interface so' descodifica
; o A5). Os bits ja' vem activos a 1: 0 direita, 1 esquerda, 2 baixo, 3 cima,
; 4 fogo. Cima ou fogo aceleram, baixo trava.
rc_joy:   ld bc,0x001F
          in a,(c)
          ld e,a
          and 3                ; esquerda/direita ja' estao nos bits certos
          ld d,a
          ld a,e
          and 0x18             ; cima ou fogo
          jr z,rc_ng
          ld a,4
rc_ng:    or d
          ld d,a
          ld a,e
          and 4                ; baixo
          add a,a              ; -> bit3
          or d
          ret

; --- jingle de abertura: as quatro notas do Icarus, do-mi-sol-do a subir,
;     com sol-do de remate. Toca no menu, que corre em di: a afinacao nao
;     oscila e as esperas por contagem sao fiaveis. ---
jingle:   ld a,(musopt)        ; desligar a musica no menu cala tambem o jingle
          or a
          ret z
          ld a,(is128k)
          or a
          jr nz,jing_ay
          ld hl,jing_b         ; 48K: beeper, HL = meio-periodo, DE = meias-ondas
          ld b,6
jb_l:     push bc
          ld e,(hl)
          inc hl
          ld d,(hl)
          inc hl
          ld c,(hl)
          inc hl
          ld b,(hl)
          inc hl
          push hl
          ex de,hl             ; HL = meio-periodo (o ponteiro ja' foi guardado)
          ld e,c
          ld d,b               ; DE = numero de meias-ondas
          call beep_tone
          pop hl
          pop bc
          djnz jb_l
          ret
jing_ay:  ld a,7               ; 128K: canal A do AY, so' tom
          ld e,0x3E
          call ay_out
          ld a,8
          ld e,13
          call ay_out
          ld hl,jing_a
          ld b,6
ja_l:     push bc
          xor a                ; registo 0: byte baixo do periodo
          ld e,(hl)
          inc hl
          call ay_out
          ld a,1               ; registo 1: byte alto
          ld e,(hl)
          inc hl
          call ay_out
          ld e,(hl)            ; espera: 26 T por volta, ~134 voltas por ms
          inc hl
          ld d,(hl)
          inc hl
          push hl
          ex de,hl
ja_w:     dec hl
          ld a,h
          or l
          jr nz,ja_w
          pop hl
          pop bc
          djnz ja_l
          jp ay_silence
; do4 mi4 sol4 do5 a 0,15s cada, depois sol4 curto e do5 sustido
jing_b:   dw 254,78
          dw 201,99
          dw 168,118
          dw 125,157
          dw 168,94
          dw 125,304
jing_a:   dw 424,20200
          dw 336,20200
          dw 283,20200
          dw 212,20200
          dw 283,16150
          dw 212,39000

; --- varre o teclado todo e devolve em A o ASCII da tecla premida (0 se nao
;     houver nenhuma com significado). ENTER e SPACE dao 13, a tecla 0 da' 8
;     (apagar). ---
kb_scan:  ld hl,kbtab
          ld d,8               ; oito meias-linhas
kbs_row:  ld c,0xFE
          ld b,(hl)            ; byte alto da porta
          inc hl
          in a,(c)
          cpl
          and 31               ; activo a 1
          jr z,kbs_nx
          ld e,a
          push hl
          ld b,5               ; o B ja' nao e' preciso: a porta ja' foi lida
kbs_b:    srl e                ; percorre os cinco bits e fica-se pela primeira
          jr nc,kbs_bn         ; tecla COM codigo. Parar no primeiro bit premido
          ld a,(hl)            ; perdia o X quando vinha com o CAPS SHIFT: sao
          or a                 ; da mesma meia-linha e o CAPS, que nao tem
          jr nz,kbs_hit        ; codigo, aparece primeiro
kbs_bn:   inc hl
          djnz kbs_b
          pop hl
          jr kbs_nx
kbs_hit:  pop hl
          ret
kbs_nx:   inc hl               ; salta os cinco codigos desta meia-linha
          inc hl
          inc hl
          inc hl
          inc hl
          dec d
          jr nz,kbs_row
          xor a
          ret
kbtab:    db 0xFE,0,"ZXCV"
          db 0xFD,"ASDFG"
          db 0xFB,"QWERT"
          db 0xF7,0,0,0,0,0
          db 0xEF,8,0,0,0,0        ; a tecla 0 apaga a letra anterior
          db 0xDF,"POIUY"
          db 0xBF,13,"LKJH"
          db 0x7F,13,0,"MNB"       ; SPACE confirma tal como o ENTER
; --- espera que se solte tudo e devolve a proxima tecla com significado ---
kb_get:   call kb_scan
          or a
          jr nz,kb_get
kbg_w:    call kb_scan
          or a
          jr z,kbg_w
          ret

; --- extremos da barra de distancia: um traco vertical de cada lado, com
;     START e END por baixo. Os tracos ficam nas colunas 3 e 28, mesmo fora
;     das 4..27 que o hud_bardraw reescreve a cada frame - por dentro eram
;     apagados logo no frame seguinte. ---
bar_ends: ld hl,0x5183         ; traco esquerdo: coluna 3, y=161..167
          ld d,7
be_l:     ld (hl),0x01
          inc h
          dec d
          jr nz,be_l
          ld hl,0x519C         ; traco direito: coluna 28
          ld d,7
be_r:     ld (hl),0x80
          inc h
          dec d
          jr nz,be_r
          ld hl,0x5A83         ; atributos dos dois tracos, na linha 20
          ld (hl),BARATTR
          ld hl,0x5A9C
          ld (hl),BARATTR
          ld hl,0x5AA0         ; START: linha 21, colunas 0..4
          ld b,5
be_a1:    ld (hl),BARATTR
          inc hl
          djnz be_a1
          ld hl,0x5ABB         ; END: linha 21, colunas 27..29. Nao pode comecar
          ld b,3               ; antes da 27: o pos_clear apaga as colunas 19 a
be_a2:    ld (hl),BARATTR      ; 26 (os antigos digitos dos metros) depois de
          inc hl               ; nos, e levava o E e o N a' frente
          djnz be_a2
          ld hl,t_start
          ld bc,0x1500
          call prstr
          ld hl,t_end
          ld bc,0x151B
          jp prstr
t_start:  db "START",0
t_end:    db "END",0

; ---------------- DIFICULDADE ----------------
; Tres travoes, todos por cima do mesmo motor:
;  - quantos adversarios nascem por troco. E' o principal: sao as unicas
;    ultrapassagens possiveis e sao precisas 6 em cada troco, por isso com
;    poucos adversarios um despiste custa mesmo a corrida
;  - quao denso e' o trafego, que e' o que obriga a guiar em vez de so'
;    manter o acelerador carregado
;  - quanto tempo se perde num despiste, e quanto da' o relogio
diff:     db 0                 ; 0 = NORMAL, 1 = EASY, 2 = HARD. O NORMAL fica
                                 ; no indice 0 para ser o que aparece de
                                 ; inicio; as tabelas abaixo seguem esta ordem
ctrl:     db 0                 ; 0 = teclas, 1 = Kempston
jingf:    db 0                 ; 1 = tocar o jingle ao desenhar o menu
crasht:   db CRASHT            ; frames de despiste, ja' com a dificuldade
dgapo:    db 65                ; metros base entre adversarios
dgapt:    db 12                ; metros base entre carros de trafego
; NORMAL, EASY, HARD - por esta ordem. Medido por troco de 1100m, com as 6
; ultrapassagens que cada troco exige: 8,9 adversarios no NORMAL, 11 no EASY,
; 6,9 no HARD. Tecto: acima de ~180m de espacamento nem nascem adversarios
; que cheguem e o troco ficaria impossivel de ganhar.
dtabo:    db 120,90,145        ; metros entre adversarios
dtabt:    db 9,12,7            ; metros entre carros de transito
dtabc:    db CRASHT+10,CRASHT,CRASHT+20

diff_apply: ld a,(diff)
          cp 3                 ; defensivo: um valor estranho volta a EASY
          jr c,da_ok
          xor a
          ld (diff),a
da_ok:    ld e,a
          ld d,0
          ld hl,dtabo
          add hl,de
          ld a,(hl)
          ld (dgapo),a
          ld hl,dtabt
          add hl,de
          ld a,(hl)
          ld (dgapt),a
          ld hl,dtabc
          add hl,de
          ld a,(hl)
          ld (crasht),a
          ret

; --- HL = tabela de tempos da dificuldade corrente (10 bytes por tabela) ---
rt_base:  ld a,(diff)
          add a,a              ; x2
          ld e,a
          add a,a
          add a,a              ; x8
          add a,e              ; x10
          ld e,a
          ld d,0
          ld hl,racetime
          add hl,de
          ret
; BCD: os dois digitos no primeiro byte, as centenas no segundo.
; Minimos medidos, a fundo: 70,4s no 1o troco, 58,7s no 2o e 50,3s nos tres
; ultimos. A folga que cada linha deixa e' o que separa as dificuldades - um
; despiste custa ~2s no EASY e ~2,6s no HARD.
;                                                       folga por troco
racetime: db 0x80,0x00, 0x64,0x00, 0x58,0x00, 0x58,0x00, 0x62,0x00  ; NORMAL  9,6  5,3  7,7  7,7 11,7
          db 0x88,0x00, 0x70,0x00, 0x64,0x00, 0x64,0x00, 0x70,0x00  ; EASY   17,6 11,3 13,7 13,7 19,7
          db 0x76,0x00, 0x62,0x00, 0x56,0x00, 0x56,0x00, 0x59,0x00  ; HARD    5,6  3,3  5,7  5,7  8,7


; --- carro do slot 1: enquanto houver lugares a ganhar no troco e' um
;     adversario; esgotada a quota (racepos ja' chegou ao posmin) os que
;     nascem passam a ser transito, com o carro do transito. Antes disto
;     continuavam a aparecer adversarios que ja' nao davam lugar nenhum -
;     prometiam uma ultrapassagem que nao contava ---
ospr1:    dw advbox_m
opp_kind: ld a,(arclvl)
          dec a
          ld e,a
          ld d,0
          ld hl,posmin
          add hl,de
          ld a,(racepos)
          cp (hl)
          jr z,ok_traf         ; racepos == posmin: quota esgotada
          jr c,ok_traf         ; racepos < posmin: idem (nao devia acontecer)
          ld hl,advbox_m
          ld (ospr1),hl
          ld a,1               ; conta como adversario: leva a cor do adversario
          ld (oisadv),a
          ret
ok_traf:  call traf_pick       ; passa a ser transito: sorteia o carro
          ld (ospr1),hl
          xor a
          ld (oisadv),a
          ret

; --- sorteia um dos tres carros de transito e devolve a base em HL ---
traf_pick: call rnd
          and 3
          cp 3
          jr nz,tp_ok
          xor a                ; 3 nao existe: cai no primeiro
tp_ok:    add a,a
          ld e,a
          ld d,0
          ld hl,traftab
          add hl,de
          ld a,(hl)
          inc hl
          ld h,(hl)
          ld l,a
          ret
traftab:  dw advbox_v, advbox_v2, advbox_v3

; --- com a musica desligada o canal B do AY fica so' para o blip da
;     ultrapassagem: desligar a musica nao deve tirar os efeitos ---
musopt:   db 1                 ; 1 = musica ligada (so' faz diferenca em 128K)
blip_only: ld hl,blipc
          ld a,(hl)
          or a
          ret z
          dec (hl)
          ld a,(hl)
          or a
          jr z,bo_off
          jp blip_set
bo_off:   ld a,9               ; acabou o blip: cala o canal
          ld e,0
          jp ay_out


; ================= COR POR CARRO =================
; Os adversarios sao desenhados a branco porque herdam o atributo do
; alcatrao. Aqui pintam-se as celulas que cada carro ocupa com a cor dele e
; repoem-se as do frame anterior. Repor com uma constante e' seguro porque os
; adversarios andam SEMPRE dentro da estrada - o ou_x1/ou_x2 trata disso - e
; o alcatrao e' sempre LEVATTR. Atributos nao correm atras do feixe: mudam a
; cor da celula, nunca a forma.
ATTRADV   equ 0x46             ; adversario: tinta amarela brilhante
ATTRTRA   equ 0x45             ; transito: tinta ciano brilhante
ospr2:    dw advbox_v          ; desenho sorteado para o slot 2
oisadv:   db 1                 ; 1 = o slot 1 conta como adversario
ocell1:   db 0,0,0,0           ; coluna, nr colunas, linha, nr linhas
ocell2:   db 0,0,0,0

; --- A = cor, B = linha, C = coluna, D = nr de linhas, E = nr de colunas ---
att_fill: ld l,b
          ld h,0
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl
          add hl,hl            ; HL = linha*32
          ld b,0
          add hl,bc            ; + coluna
          ld bc,0x5800
          add hl,bc
af_row:   push hl
          ld b,e
af_col:   ld (hl),a
          inc hl
          djnz af_col
          pop hl
          ld bc,32
          add hl,bc
          dec d
          jr nz,af_row
          ret

; --- apaga o rectangulo do frame anterior guardado em IX ---
catt_clr: ld a,(ix+1)
          or a
          ret z
          ld b,(ix+2)
          ld c,(ix+0)
          ld d,(ix+3)
          ld e,(ix+1)
          ld a,LEVATTR
          call att_fill
          ld (ix+1),0
          ret

; --- pinta o carro: IX = bloco, A = cor, B = x, C = par de cima,
;     D = par de baixo (exclusivo).
;     O rectangulo novo calcula-se ANTES de limpar o antigo: na maioria dos
;     frames o carro nao mudou de celula e nao ha' nada a limpar. Limpar
;     sempre custava o dobro das escritas por nada. ---
cnew:     db 0,0,0,0
catt_pnt: push af
          ld a,b               ; colunas: do (x+3)>>3 ao (x+12)>>3
          add a,3
          rrca
          rrca
          rrca
          and 31
          ld (cnew+0),a
          ld l,a
          ld a,b
          add a,12
          rrca
          rrca
          rrca
          and 31
          sub l
          inc a                ; nr de colunas (2 ou 3)
          cp 4                 ; rede de seguranca: se a conta transbordar (x
          jr c,cp_nc           ; alto faz (x+12) dar a volta), isto seria um
          ld a,3               ; numero enorme e pintava meio ecra
cp_nc:    ld (cnew+1),a
          ld a,c               ; linhas: par>>2 ate' (parbaixo-1)>>2
          srl a
          srl a
          ld (cnew+2),a
          ld e,a
          ld a,d
          dec a
          srl a
          srl a
          sub e
          inc a
          cp 4                 ; idem para as linhas
          jr c,cp_nr
          ld a,3
cp_nr:    ld (cnew+3),a
          ld hl,cnew           ; igual ao do frame anterior?
          ld a,(hl)
          cp (ix+0)
          jr nz,cp_move
          inc hl
          ld a,(hl)
          cp (ix+1)
          jr nz,cp_move
          inc hl
          ld a,(hl)
          cp (ix+2)
          jr nz,cp_move
          inc hl
          ld a,(hl)
          cp (ix+3)
          jr z,cp_same         ; mesmas celulas: so' repintar
cp_move:  call catt_clr        ; mudou de celula: limpar as antigas
cp_same:  ld a,(cnew+0)        ; guardar o rectangulo novo
          ld (ix+0),a
          ld a,(cnew+1)
          ld (ix+1),a
          ld a,(cnew+2)
          ld (ix+2),a
          ld a,(cnew+3)
          ld (ix+3),a
          ld b,(ix+2)
          ld c,(ix+0)
          ld d,(ix+3)
          ld e,(ix+1)
          pop af
          jp att_fill

; --- os dois slots, uma vez por frame ---
car_attr: ld ix,ocell1
          ld a,(oact)
          or a
          jr z,ca_off1
          ld a,(oy+1)          ; so' quando esta' mesmo dentro da janela
          cp VROW0*4
          jr c,ca_off1
          ld b,a
          ld a,(oybot)
          cp b
          jr c,ca_off1
          ld c,b
          ld d,a
          ld a,(ox)
          ld b,a
          ld a,(oisadv)
          or a
          ld a,ATTRTRA
          jr z,ca_c1
          ld a,ATTRADV
ca_c1:    call catt_pnt
          jr ca_s2
ca_off1:  call catt_clr        ; saiu de cena: apagar o que ficou
ca_s2:    ld ix,ocell2
          ld a,(oact2)
          or a
          jr z,ca_off2
          ld a,(oy2+1)
          cp VROW0*4
          jr c,ca_off2
          ld b,a
          ld a,(oybot2)
          cp b
          jr c,ca_off2
          ld c,b
          ld d,a
          ld a,(ox2)
          ld b,a
          ld a,ATTRTRA
          jp catt_pnt
ca_off2:  jp catt_clr

; --- blip da ultrapassagem, no canal B. Entra com A = blipc (1..8), que vai
;     a descer, por isso a altura sobe ao longo do apito.
;     Periodo 240 a 135, ou seja 460 a 820 Hz, a volume 15. Cheguei a baixa-lo
;     para 205-336 Hz mas o agudo era o que se queria: o problema era ele nao
;     parar, nao a altura. ---
blip_set: add a,a              ; 2 bytes por entrada
          ld e,a
          ld d,0
          ld hl,bliptab
          add hl,de
          ld a,2               ; canal B, byte baixo do periodo
          ld e,(hl)
          call ay_out
          inc hl
          ld a,3               ; byte alto
          ld e,(hl)
          call ay_out
          ld a,9               ; volume do canal B
          ld e,15
          jp ay_out
bliptab:  dw 0,135,150,165,180,195,210,225,240

