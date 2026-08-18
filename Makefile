all:
	make -C compiler && cp ./compiler/nuppuc .
	make -C preprocessor && cp ./preprocessor/nuppupp .

clean:
	rm ./nuppupp ./nuppuc

install:
	mkdir -p /usr/local/bin /usr/local/share
	install -m5 nuppu /usr/local/bin/nuppu
	install -m5 nuppuc /usr/local/bin/nuppuc
	install -m5 nuppupp /usr/local/bin/nuppupp
	install -m5 ./compiler/base.qbe /usr/local/share/nuppu
	install -m5 ./stdlib/stdlib.nup /usr/local/share/nuppu/

