/* disasm: the assembly text of every instruction word. */
#ifndef TARA_DISASM_H
#define TARA_DISASM_H

/* Print "WWWW TEXT" for every 16-bit word, 0000 to ffff in order. Returns the exit status. */
int disassemble_all(void);

#endif
