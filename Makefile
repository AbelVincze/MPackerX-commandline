arm:
	g++-10 main.cpp -o mpackerx -I -Wall -Os -flto -no-pie
	strip mpackerx
	cp mpackerx ~/bin/mpackerx

as:
	g++-10  -S main.cpp -I -Wall -Os -ffunction-sections -fdata-sections -flto


x86:
	g++-10 -c main.cpp  -march=x86 -I -Wall -Os -ffunction-sections -fdata-sections -flto
	g++-10 -o mpackerx86 main.o
	strip mpackerx86
	
debug:
	g++-10  main.cpp -o mpackerx_debug -I -Wall -g -v

clean:
	rm -rf mpackerx_debug.dSYM mpackerx mpackerx86 main.o mpackerx_debug main.s


