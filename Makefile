all:
	make -C compiler && cp ./compiler/nuppuc .
	make -C preprocessor && cp ./preprocessor/nuppupp .

