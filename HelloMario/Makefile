all:
	# Assemble
	ca65 hellomario.asm -o hellomario.o --debug-info
	# Link
	ld65 hellomario.o -o hellomario.nes -t nes --dbgfile hellomario.dbg
