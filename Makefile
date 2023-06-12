arm:
	g++-12 main.cpp -o mpackerx -I -Wall -Os -flto -no-pie
	cp mpackerx ~/bin/mpackerx

as:
	g++-12  -S main.cpp -I -Wall -Os -ffunction-sections -fdata-sections -flto

wasm:
	#emcc main.cpp -o test.js -O3 -s WASM=1 -s EXPORTED_FUNCTIONS=_mpack -s EXPORTED_RUNTIME_METHODS=ccall,cwrap
	emcc main.cpp -o test.js -O3 -s WASM=1 -s MODULARIZE -s EXPORTED_RUNTIME_METHODS=ccall

x86:
	g++-12 -c main.cpp  -march=x86 -I -Wall -Os -ffunction-sections -fdata-sections -flto
	g++-12 -o mpackerx86 main.o
	strip mpackerx86
	
debug:
	g++-12  main.cpp -o mpackerx_debug -I -Wall -g -v

clean:
	rm -rf mpackerx_debug.dSYM mpackerx mpackerx86 main.o mpackerx_debug main.s


