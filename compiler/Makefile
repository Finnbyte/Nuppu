nuppuc: main.ha
	hare build -o nuppuc .

clean:
	rm nuppuc *.ssa

install:
	mkdir -p /usr/local/share/nuppu
	install -m5 nuppuc /usr/local/bin/nuppuc
	install -m5 ./base.qbe /usr/local/share/nuppu
