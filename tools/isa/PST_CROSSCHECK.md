# pst.c <-> generated inventory opcode cross-check

Three-way agreement check: verified sim decoder (generated table) vs MWC's
own Z8001 assembler opcode table `cmd/as/z8001/pst.c`. A pst.c base must
appear among the inventory's `base` values for that mnemonic (the assembler
ORs the addressing hi-nibble 0x80/0x40 at assemble time).

- mnemonics in pst.c (instructions): **225**
- mnemonics in generated inventory: **160**
- **matched: 155**  ·  **mismatched: 0**  ·  special(placeholder): 2  ·  pst-only: 68  ·  inventory-only: 3

## Special (pst base = 0x0000 placeholder; opcode built in machine.c)

| mnemonic | pst fmt | inventory bases |
|---|---|---|
| ADDB | S_RSRC | `0x0000`, `0x4000`, `0x8000` |
| LDM | S_LDM | `0x1C01`, `0x1C09`, `0x5C01`, `0x5C09` |

## Matched (pst base found in inventory; form = bit machine.c ORs in)

| mnemonic | pst base | inv base | form | pst fmt (-> optab OF_*) |
|---|---|---|---|---|
| ADC | `0xB500` | `0xB500` | exact | S_RR |
| ADCB | `0xB400` | `0xB400` | exact | S_RR |
| ADD | `0x0100` | `0x0100` | exact | S_RSRC |
| ADDL | `0x1600` | `0x1600` | exact | S_RSRC |
| AND | `0x0700` | `0x0700` | exact | S_RSRC |
| ANDB | `0x0600` | `0x0600` | exact | S_RSRC |
| BIT | `0x2700` | `0x2700` | exact | S_BIT |
| BITB | `0x2600` | `0x2600` | exact | S_BIT |
| CALL | `0x1F00` | `0x1F00` | exact | S_CALL |
| CALR | `0xD000` | `0xD000` | exact | S_CALR |
| CLR | `0x0D08` | `0x0D08` | exact | S_CLR |
| CLRB | `0x0C08` | `0x0C08` | exact | S_CLR |
| COM | `0x0D00` | `0x0D00` | exact | S_CLR |
| COMB | `0x0C00` | `0x0C00` | exact | S_CLR |
| COMFLG | `0x8D05` | `0x8D05` | exact | S_FLG |
| CP | `0x0B00` | `0x0B00` | exact | S_CP |
| CPB | `0x0A00` | `0x0A00` | exact | S_CP |
| CPD | `0xBB08` | `0xBB08` | exact | S_CPD |
| CPDB | `0xBA08` | `0xBA08` | exact | S_CPD |
| CPDR | `0xBB0C` | `0xBB0C` | exact | S_CPD |
| CPDRB | `0xBA0C` | `0xBA0C` | exact | S_CPD |
| CPI | `0xBB00` | `0xBB00` | exact | S_CPD |
| CPIB | `0xBA00` | `0xBA00` | exact | S_CPD |
| CPIR | `0xBB04` | `0xBB04` | exact | S_CPD |
| CPIRB | `0xBA04` | `0xBA04` | exact | S_CPD |
| CPL | `0x1000` | `0x1000` | exact | S_CP |
| CPSD | `0xBB0A` | `0xBB0A` | exact | S_CPS |
| CPSDB | `0xBA0A` | `0xBA0A` | exact | S_CPS |
| CPSDR | `0xBB0E` | `0xBB0E` | exact | S_CPS |
| CPSDRB | `0xBA0E` | `0xBA0E` | exact | S_CPS |
| CPSI | `0xBB02` | `0xBB02` | exact | S_CPS |
| CPSIB | `0xBA02` | `0xBA02` | exact | S_CPS |
| CPSIR | `0xBB06` | `0xBB06` | exact | S_CPS |
| CPSIRB | `0xBA06` | `0xBA06` | exact | S_CPS |
| DAB | `0xB000` | `0xB000` | exact | S_R |
| DEC | `0x2B00` | `0x2B00` | exact | S_DEC |
| DECB | `0x2A00` | `0x2A00` | exact | S_DEC |
| DI | `0x7C03` | `0x7C03` | exact | S_DI |
| DIV | `0x1B00` | `0x1B00` | exact | S_RSRC |
| DIVL | `0x1A00` | `0x1A00` | exact | S_RSRC |
| DJNZ | `0xF080` | `0xF080` | exact | S_DJNZ |
| EI | `0x7C07` | `0x7C07` | exact | S_DI |
| EX | `0x2D00` | `0x2D00` | exact | S_EX |
| EXB | `0x2C00` | `0x2C00` | exact | S_EX |
| EXTS | `0xB10A` | `0xB10A` | exact | S_R |
| EXTSB | `0xB100` | `0xB100` | exact | S_R |
| EXTSL | `0xB107` | `0xB107` | exact | S_R |
| HALT | `0x7A00` | `0x7A00` | exact | S_HALT |
| IN | `0x3D00` | `0x3D00` | exact | S_IN |
| INB | `0x3C00` | `0x3C00` | exact | S_IN |
| INC | `0x2900` | `0x2900` | exact | S_DEC |
| INCB | `0x2800` | `0x2800` | exact | S_DEC |
| INDR | `0x3B08` | `0x3B08` | exact | S_INDR |
| INIR | `0x3B00` | `0x3B00` | exact | S_INDR |
| INIRB | `0x3A00` | `0x3A00` | exact | S_INDR |
| IRET | `0x7B00` | `0x7B00` | exact | S_HALT |
| JP | `0x1E00` | `0x1E00` | exact | S_JP |
| JR | `0xE000` | `0xE000` | exact | S_JR |
| LD | `0x2100` | `0x2100` | exact | S_LD |
| LDA | `0x3400` | `0x3400` | exact | S_LDA |
| LDAR | `0x3400` | `0x3400` | exact | S_LDAR |
| LDB | `0x2000` | `0x2000` | exact | S_LD |
| LDCTL | `0x7D00` | `0x7D00` | exact | S_CTL |
| LDDR | `0xBB09` | `0xBB09` | exact | S_INDR |
| LDDRB | `0xBA09` | `0xBA09` | exact | S_INDR |
| LDIR | `0xBB01` | `0xBB01` | exact | S_INDR |
| LDIRB | `0xBA01` | `0xBA01` | exact | S_INDR |
| LDK | `0xBD00` | `0xBD00` | exact | S_LDK |
| LDL | `0x1400` | `0x1400` | exact | S_LD |
| LDPS | `0x3900` | `0x3900` | exact | S_CALL |
| MBIT | `0x7B0A` | `0x7B0A` | exact | S_HALT |
| MREQ | `0x7B0D` | `0x7B0D` | exact | S_R |
| MRES | `0x7B09` | `0x7B09` | exact | S_HALT |
| MSET | `0x7B08` | `0x7B08` | exact | S_HALT |
| MULT | `0x1900` | `0x1900` | exact | S_RSRC |
| MULTL | `0x1800` | `0x1800` | exact | S_RSRC |
| NEG | `0x0D02` | `0x0D02` | exact | S_CLR |
| NEGB | `0x0C02` | `0x0C02` | exact | S_CLR |
| NOP | `0x8D07` | `0x8D07` | exact | S_HALT |
| OR | `0x0500` | `0x0500` | exact | S_RSRC |
| ORB | `0x0400` | `0x0400` | exact | S_RSRC |
| OTDR | `0x3B0A` | `0x3B0A` | exact | S_INDR |
| OTDRB | `0x3A0A` | `0x3A0A` | exact | S_INDR |
| OTIR | `0x3B02` | `0x3B02` | exact | S_INDR |
| OTIRB | `0x3A02` | `0x3A02` | exact | S_INDR |
| OUT | `0x3F00` | `0x3F00` | exact | S_OUT |
| OUTB | `0x3E00` | `0x3E00` | exact | S_OUT |
| POP | `0x1700` | `0x1700` | exact | S_POP |
| POPL | `0x1500` | `0x1500` | exact | S_POP |
| PUSH | `0x1300` | `0x1300` | exact | S_PUSH |
| PUSHL | `0x1100` | `0x1100` | exact | S_PUSH |
| RES | `0x2300` | `0x2300` | exact | S_BIT |
| RESB | `0x2200` | `0x2200` | exact | S_BIT |
| RESFLG | `0x8D03` | `0x8D03` | exact | S_FLG |
| RET | `0x9E00` | `0x9E00` | exact | S_RET |
| RL | `0xB300` | `0xB300` | exact | S_RL |
| RLB | `0xB200` | `0xB200` | exact | S_RL |
| RLC | `0xB308` | `0xB308` | exact | S_RL |
| RLCB | `0xB208` | `0xB208` | exact | S_RL |
| RLDB | `0xBE00` | `0xBE00` | exact | S_RR |
| RR | `0xB304` | `0xB304` | exact | S_RL |
| RRB | `0xB204` | `0xB204` | exact | S_RL |
| RRC | `0xB30C` | `0xB30C` | exact | S_RL |
| RRCB | `0xB20C` | `0xB20C` | exact | S_RL |
| RRDB | `0xBC00` | `0xBC00` | exact | S_RR |
| SBC | `0xB700` | `0xB700` | exact | S_RR |
| SBCB | `0xB600` | `0xB600` | exact | S_RR |
| SC | `0x7F00` | `0x7F00` | exact | S_SC |
| SDA | `0x330B` | `0xB30B` | +reg(0x80) | S_SDA |
| SDAB | `0x320B` | `0xB20B` | +reg(0x80) | S_SDA |
| SDAL | `0x330F` | `0xB30F` | +reg(0x80) | S_SDA |
| SDL | `0x3303` | `0xB303` | +reg(0x80) | S_SDA |
| SDLB | `0x3203` | `0xB203` | +reg(0x80) | S_SDA |
| SDLL | `0x3307` | `0xB307` | +reg(0x80) | S_SDA |
| SET | `0x2500` | `0x2500` | exact | S_BIT |
| SETB | `0x2400` | `0x2400` | exact | S_BIT |
| SETFLG | `0x8D01` | `0x8D01` | exact | S_FLG |
| SIN | `0x3B05` | `0x3B05` | exact | S_SIN |
| SINB | `0x3A05` | `0x3A05` | exact | S_SIN |
| SINDR | `0x3B09` | `0x3B09` | exact | S_INDR |
| SINDRB | `0x3A09` | `0x3A09` | exact | S_INDR |
| SINIR | `0x3B01` | `0x3B01` | exact | S_INDR |
| SINIRB | `0x3A01` | `0x3A01` | exact | S_INDR |
| SLA | `0xB309` | `0xB309` | exact | S_SLA |
| SLAB | `0xB209` | `0xB209` | exact | S_SLA |
| SLAL | `0xB30D` | `0xB30D` | exact | S_SLA |
| SLL | `0xB301` | `0xB301` | exact | S_SLA |
| SLLB | `0xB201` | `0xB201` | exact | S_SLA |
| SLLL | `0xB305` | `0xB305` | exact | S_SLA |
| SOTDR | `0x3B0B` | `0x3B0B` | exact | S_INDR |
| SOTDRB | `0x3A0B` | `0x3A0B` | exact | S_INDR |
| SOTIR | `0x3B03` | `0x3B03` | exact | S_INDR |
| SOTIRB | `0x3A03` | `0x3A03` | exact | S_INDR |
| SOUT | `0x3B07` | `0x3B07` | exact | S_SOUT |
| SOUTB | `0x3A07` | `0x3A07` | exact | S_SOUT |
| SUB | `0x0300` | `0x0300` | exact | S_RSRC |
| SUBB | `0x0200` | `0x0200` | exact | S_RSRC |
| SUBL | `0x1200` | `0x1200` | exact | S_RSRC |
| TCC | `0xAF00` | `0xAF00` | exact | S_TCC |
| TCCB | `0xAE00` | `0xAE00` | exact | S_TCC |
| TEST | `0x0D04` | `0x0D04` | exact | S_CLR |
| TESTB | `0x0C04` | `0x0C04` | exact | S_CLR |
| TESTL | `0x1C08` | `0x1C08` | exact | S_CLR |
| TRDB | `0xB808` | `0xB808` | exact | S_TRT |
| TRDRB | `0xB80C` | `0xB80C` | exact | S_TRT |
| TRIB | `0xB800` | `0xB800` | exact | S_TRT |
| TRIRB | `0xB804` | `0xB804` | exact | S_TRT |
| TRTDB | `0xB80A` | `0xB80A` | exact | S_TRT |
| TRTDRB | `0xB80E` | `0xB80E` | exact | S_TRTR |
| TRTIB | `0xB802` | `0xB802` | exact | S_TRT |
| TRTIRB | `0xB806` | `0xB806` | exact | S_TRTR |
| TSET | `0x0D06` | `0x0D06` | exact | S_CLR |
| TSETB | `0x0C06` | `0x0C06` | exact | S_CLR |
| XOR | `0x0900` | `0x0900` | exact | S_RSRC |
| XORB | `0x0800` | `0x0800` | exact | S_RSRC |

## pst.c-only (assembler mnemonics not in the codegen inventory)

Mostly privileged/IO/block ops the C codegen never emits.

`C`, `DBJNZ`, `EQ`, `FCW`, `FLAGS`, `GE`, `GT`, `IND`, `INDB`, `INDBR`, `INI`, `INIB`, `LDCTLB`, `LDD`, `LDDB`, `LDI`, `LDIB`, `LDR`, `LDRB`, `LDRL`, `LE`, `LT`, `MI`, `NC`, `NE`, `NOV`, `NSP`, `NSPOFF`, `NSPSEG`, `NVI`, `NZ`, `OUTD`, `OUTDB`, `OUTI`, `OUTIB`, `OV`, `P`, `PE`, `PL`, `PO`, `PSAP`, `PSAPOFF`, `PSAPSEG`, `REFRESH`, `S`, `SIND`, `SINDB`, `SINI`, `SINIB`, `SOUTD`, `SOUTDB`, `SOUTI`, `SOUTIB`, `SRA`, `SRAB`, `SRAL`, `SRL`, `SRLB`, `SRLL`, `SYS`, `UGE`, `UGT`, `ULE`, `ULT`, `UN`, `V`, `VI`, `Z`

## inventory-only (decoder mnemonics not named in pst.c)

`EPU`, `ILLEGAL`, `INDRB`
