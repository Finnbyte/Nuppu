use types;
use rt;
use fmt;
use uuid;
use errors;
use math;
use fs;
use strconv;
use ascii;
use io;
use os::exec; 
use time;
use time::date;
use regex;
use strings;
use os;

type LexKind = enum {
	CHAR,
	COMMA,
	PAREN_OPEN,
	PAREN_CLOSE,
	COLON,
	EXCLAMATION,
	WHITESPACE,
	NEWLINE,
	DIGIT,
	NULLTERM,
	EQUALS,
	SINGLE_QUOTE,
	QUOTE
};

type LexSymbol = struct {
	kind: LexKind,
	value: rune
};

type Lexer = struct {
	symbols: []LexSymbol,
	buffer: []rune
};

fn next_lexer(lexer: *Lexer) LexSymbol = {
	const ch = lexer.buffer[0];
	delete(lexer.buffer[0]);
	const symbol = LexSymbol {
		value = ch,
		kind = rune_to_lexkind(ch)
	};
	append(lexer.symbols, symbol)!;
	return symbol;
};


fn rune_to_lexkind(ch: rune) LexKind = {
	switch (ch) {
	case '(' => return LexKind::PAREN_OPEN;
	case ')' => return LexKind::PAREN_CLOSE;
	case ',' => return LexKind::COMMA;
	case ' ' => return LexKind::WHITESPACE;
	case '!' => return LexKind::EXCLAMATION;
	case '\n' => return LexKind::NEWLINE;
	case ':' => return LexKind::COLON;
	case '\0' => return LexKind::NULLTERM;
	case '=' => return LexKind::EQUALS;
	case '\"' => return LexKind::QUOTE;
	case '\'' => return LexKind::SINGLE_QUOTE;
	case => 
		if (ascii::isdigit(ch)) {
			return LexKind::DIGIT;
		};
		if (ascii::isprint(ch)) {
			return LexKind::CHAR;
		};
		if (ascii::isblank(ch)) {
			return LexKind::WHITESPACE;
		};
		fmt::fatal(format("LEX_ERROR: Could not map \"{}\" to a lexkind.", ch));
	};

};

fn lexer_lex_buffer(lexer: *Lexer) void = {
	for (len(lexer.buffer) > 0) {
		const symbol = next_lexer(lexer);
		fmt::println(symbol.value)!;
	};
};

fn lexkind_to_rune(kind: LexKind) str = {
	switch (kind) {
	case LexKind::CHAR => return "CHAR";
	case LexKind::COMMA => return "COMMA";
	case LexKind::PAREN_OPEN => return "PAREN_OPEN";
	case LexKind::PAREN_CLOSE => return "PAREN_CLOSE";
	case LexKind::WHITESPACE => return "WHITESPACE";
	case LexKind::NEWLINE => return "NEWLINE";
	case LexKind::DIGIT => return "DIGIT";
	case LexKind::NULLTERM => return "NULLTERM";
	case LexKind::EQUALS => return "EQUALS";
	case LexKind::SINGLE_QUOTE => return "SINGLE_QUOTE";
	case LexKind::COLON => return "COLON";
	case LexKind::QUOTE => return "QUOTE";
	case LexKind::EXCLAMATION => return "EXCLAMATION";
	case => return "UNRECOGNIZED?";
	};
};

fn print_lexed_symbols(lexer: Lexer) void = {
	for (const symbol .. lexer.symbols) {
		fmt::printfln("kind: {}, value: {}", lexkind_to_rune(symbol.kind), symbol.value)!;
	};
};

fn get_lexed_runes(lexer_symbols: []LexSymbol, start: size = 0z, end: size = -1z) []rune = {
	if (end < 0) end = len(lexer_symbols) - 1z;
	const symbols = lexer_symbols[start..end];
	const result: []rune = [];
	let i = 0;
	for (const symbol .. symbols) {
		append(result, symbol.value)!;
	};
	return result;
};

