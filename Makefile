hello:
	g++  main.cpp -o mpackerx -I -Wall -Os -ffunction-sections -fdata-sections -flto
	strip mpackerx
	cp mpackerx ~/bin/mpackerx

win:
	g++  main.cpp -o mpackerx.exe -I -Wall -Os -ffunction-sections -fdata-sections -flto
	strip mpackerx.exe
	
debug:
	g++  main.cpp -o mpackerx_debug -I -Wall


