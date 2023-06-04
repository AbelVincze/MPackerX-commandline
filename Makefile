arm:
	g++-11 main.cpp -o mpackerx -I -Wall -Os -flto -no-pie
	cp mpackerx ~/bin/mpackerx

as:
	g++-11  -S main.cpp -I -Wall -Os -ffunction-sections -fdata-sections -flto


x86:
	g++-11 -c main.cpp  -march=x86 -I -Wall -Os -ffunction-sections -fdata-sections -flto
	g++-11 -o mpackerx86 main.o
	strip mpackerx86
	
debug:
	g++-11  main.cpp -o mpackerx_debug -I -Wall -g -v

clean:
	rm -rf mpackerx_debug.dSYM mpackerx mpackerx86 main.o mpackerx_debug main.s


