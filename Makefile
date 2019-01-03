hello:
	g++  main.cpp -o mpackerx -I -Wall -Os -ffunction-sections -fdata-sections -flto
	strip mpackerx
	cp mpackerx ~/bin/mpackerx

debug:
	g++  main.cpp -o mpackerx_debug -I -Wall


