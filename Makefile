hello:
	g++-10  main.cpp -o mpackerx -I -Wall -Os -ffunction-sections -fdata-sections -flto
	strip mpackerx
	cp mpackerx ~/bin/mpackerx

win:
	g++-10  main.cpp -o mpackerx.exe -I -Wall -Os -ffunction-sections -fdata-sections -flto
	strip mpackerx.exe
	
debug:
	g++-10  main.cpp -o mpackerx_debug -I -Wall


