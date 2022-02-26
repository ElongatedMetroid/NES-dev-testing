all:
	# Assemble
	ca65 helloworld.asm -o helloworld.o --debug-info
	# Link
	ld65 helloworld.o -o helloworld.nes -t nes --dbgfile helloworld.dbg
