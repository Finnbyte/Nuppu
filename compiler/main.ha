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
	PAREN_OPEN,
	PAREN_CLOSE,
	WHITESPACE,
	NEWLINE,
	DIGIT,
	NULLTERM,
	EQUALS,
	SINGLE_QUOTE,
	QUOTE
};

fn lexkind_to_rune(kind: LexKind) str = {
	switch (kind) {
		case LexKind::CHAR => return "CHAR";
		case LexKind::PAREN_OPEN => return "PAREN_OPEN";
		case LexKind::PAREN_CLOSE => return "PAREN_CLOSE";
		case LexKind::WHITESPACE => return "WHITESPACE";
		case LexKind::NEWLINE => return "NEWLINE";
		case LexKind::DIGIT => return "DIGIT";
		case LexKind::NULLTERM => return "NULLTERM";
		case LexKind::EQUALS => return "EQUALS";
		case LexKind::SINGLE_QUOTE => return "SINGLE_QUOTE";
		case LexKind::QUOTE => return "QUOTE";
	};
};

fn token_to_tokenkind(token: Token) str = {
	match (token) {
	case VariableToken => return "VariableToken";
	case IfToken => return "IfToken";
	case FuncallToken => return "FuncallToken";
	case FunDefToken => return "FunDefToken";
	};
};

fn rune_to_lexkind(ch: rune) LexKind = {
	switch (ch) {
	case '(' => return LexKind::PAREN_OPEN;
	case ')' => return LexKind::PAREN_CLOSE;
	case ' ' => return LexKind::WHITESPACE;
	case '\n' => return LexKind::NEWLINE;
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

type LexSymbol = struct {
	kind: LexKind,
	value: rune
};

type Expression = struct {
	kind: ExpressionKind,
	var: (str | void),
	value: []u8,
	value_size: size
};

type FuncallToken = struct {
	name: str,
	// Argument's expression value
	value: Expression
};

type BlockToken = struct {
	kind: BlockKind,
	id: str,
	tokens: []Token
};

type FunDefToken = struct {
	name: str,
	proc: FunDefProcToken,
	body: BlockToken
};

type FunDefProcToken = struct {
	name: str,
};

type IfToken = struct {
	expr1: Expression,
	expr2: Expression,
	cmp: str,
	body: BlockToken
};

type Token = (VariableToken | FuncallToken | IfToken | FunDefToken);

type VariableToken = struct {
	kind: VariableKind,
	name: str,
	value: Expression
};

type Tokenizer = struct {
	block: (BlockToken | void),
	tokens: []Token,
	buffer: []LexSymbol,
	linenum: int,

};

fn get_variable_reg(qbe: Qbe, variable_identifier: str) str = {
	fmt::println("to find", variable_identifier)!;
	for (let i: size = len(qbe.variables) - 1; i >= 0; i -= 1 ) {
		// found variable
		const (identifier, reg) = qbe.variables[i];
		fmt::printfln("Identifier: {}, reg: {} (searching for {}", identifier, reg, variable_identifier)!;
		if (identifier == variable_identifier) {
			fmt::printfln("found!")!;
			return reg;
		};
	};
	fmt::printfln("didn't find!")!;
	return "";
};

const ALIGNMENT: size = 4;

const builtins = ["echo", "tolower", "toupper"];

const globalTokenizer: Tokenizer = @undefined;

const registers: []str = ["%a", "%b", "%c", "%d", "%e", "%f", "%g", "%h", "%i", "%j", "%k", "%l", "%m", "%n", "%o", "%p", "%q", "%r", "%s", "%t", "%u", "%v", "%w", "%x", "%y", "%z"];
const datums: []str = ["$a", "$b", "$c", "$d", "$e", "$f", "$g", "$h", "$i", "$j", "$k", "$l", "$m", "$n", "$o", "$p", "$q", "$r", "$s", "$t", "$u", "$v", "$w", "$x", "$y", "$z"];

type BlockKind = enum {
	IF,
	FUN
};

type ExpressionKind = enum {
	INT,
	STR
};

type Qbe_Allocation = struct {
	name: str,
	data_sz: size,
	data: []u8,
	data_kind: Qbe_AllocationDataKind,
	text: str
};

type Qbe_Integer = struct {
	name: str,
	data: []u8,
	text: str
};

type Qbe_Blit = struct {
	name: str,
	text: str
};

fn pass() void = {
	return void;
};

fn unimplemented() void = {
	fmt::fatal("Not yet implemented");
};

type invalidexpression = !void;

type VariableKind = ExpressionKind;

type Qbe_AllocationDataKind = ExpressionKind;
type Lexer = struct {
	symbols: []LexSymbol,
	buffer: []rune
};

type Qbe_WritePositionKind = enum {
	PREPEND,
	APPEND
};

type Qbe = struct {
	indent_level: size,
	buffer: []str,
	variables: [](str, str)
};

type Qbe_WritePosition = (int | Qbe_WritePositionKind);

fn gen_id() str = {
	return uuid::encodestr(uuid::generate());
};

fn qbe_initialize(base_file_path: str) Qbe = {
	const base_contents = read_file_contents(base_file_path, false);
	const lines = strings::split(base_contents, "\n")!;
	const qbe = Qbe {
		indent_level = 0,
		buffer = [],
		variables = []
	};
	for (const line .. lines) {
		qbe_write(&qbe, line)!;
	};
	return qbe;
};

fn qbe_get_reg_label(uppercase: bool = false) str = {
	const reg = registers[0];
	static delete(registers[0]);
	switch (uppercase) {
	case true => return ascii::strupper(reg)!;
	case false => return reg;
	};
};

fn qbe_get_loaded_reg_label(label: str, uppercase: bool = false) str = {
	if (uppercase) label = ascii::strupper(label)!;
	if (!uppercase) label = ascii::strlower(label)!;
	return format("{}L", label);
};

fn qbe_get_data_label() str = {
	const datum = datums[0];
	static delete(datums[0]);
	return datum;
};

fn qbe_set_indent(qbe: *Qbe, indent_level: size) void = {
	qbe.indent_level = indent_level;
};

fn qbe_write(qbe: *Qbe, s: str, position: Qbe_WritePosition = Qbe_WritePositionKind::APPEND) (void | nomem) = {
	if (!strings::hassuffix(s, "\n")) {
		s = strings::concat(s, "\n")!;
	};

	if (qbe.indent_level > 0) {
		s = strings::lpad(s, ' ', len(s) + qbe.indent_level)?;
	};

	if (position is int) {
		insert(qbe.buffer[position as int], s)?;
	} else {
		switch (position as Qbe_WritePositionKind) {
		case Qbe_WritePositionKind::PREPEND =>
			insert(qbe.buffer[0], s)?;
		case Qbe_WritePositionKind::APPEND =>
			append(qbe.buffer, s)?;
		};
	};
};

fn qbe_write_noindent(qbe: *Qbe, s: str, position: Qbe_WritePosition = Qbe_WritePositionKind::APPEND) (void | nomem) = {
	if (!strings::hassuffix(s, "\n")) {
		s = strings::concat(s, "\n")!;
	};

	if (position is int) {
		insert(qbe.buffer[position as int], s)?;
	} else {
		switch (position as Qbe_WritePositionKind) {
		case Qbe_WritePositionKind::PREPEND =>
			insert(qbe.buffer[0], s)?;
		case Qbe_WritePositionKind::APPEND =>
			append(qbe.buffer, s)?;
		};
	};
};

// fn qbe_writef(file: io::file, format: str, args: fmt::field...) (void | io::error) = {
// 	const s = fmt::asprintf(format, args...)!;
// 	io::write(file, strings::toutf8(s))!;
// };

fn qbe_compile(intermediary_file_path: str, output_executable_basename: str, remove_assembly_file: bool = true) (void | nomem | os::exec::error) = {
	const assembly_file_path = strings::concat(output_executable_basename, ".s")?;

	const cmd = exec::cmd("qbe", "-o", assembly_file_path, intermediary_file_path)?;
	const proc = exec::start(&cmd)?;
	const status = exec::wait(&proc)?;

	const cmd2 = exec::cmd("cc", "-o", output_executable_basename, assembly_file_path)?;
	const proc2 = exec::start(&cmd2)?;
	const status2 = exec::wait(&proc2)?;

	if (remove_assembly_file) {
		// remove .s file because it confuses hare's internal compiler
		os::remove(assembly_file_path)?;
	};
};

fn run_executable_and_capture_stdout(executable: str) (nomem | os::exec::error | str) = { 
	const cmd = exec::cmd(executable)?;

        const (read, write) = exec::pipe();
        exec::addfile(&cmd, os::stdout_file, write)?;

        const proc = exec::start(&cmd)?;
        io::close(write)?;
  
        const data: []u8 = io::drain(read)?;
        io::close(read)?;
        exec::wait(&proc)?;

	return strings::fromutf8_unsafe(data);
};


fn shift_args(args_pointer: *[]str) (str | void) = {
	if (len(*args_pointer) < 1) {
		return void;
	};
	const temp = args_pointer[0];
	static delete(args_pointer[0]);
	return temp;
};

export fn read_file_contents(file_path: str, include_null_terminator: bool = true) str = {
	const file = os::open(file_path)!;
	const stat = os::fstat(file)!;
	let buf_sz = stat.sz;
	if (include_null_terminator) buf_sz += 1;
	const buf: []u8 = alloc([0...], buf_sz)!;
	io::read(file, buf)!;
	defer io::close(file)!;
	return strings::fromutf8(buf)!;
};

fn valid_integer(s: str) bool = {
	for (const ch .. strings::torunes(s)!) {
		if (!ascii::isdigit(ch)) return false;
	};
	return true;
};

fn init_tokenizer(lexer: Lexer) Tokenizer = {
	return Tokenizer {
		tokens = [],
		buffer = lexer.symbols,
		linenum = 1,
		block = void
	};
};

fn peek_next(tokenizer: *Tokenizer) LexSymbol = {
	return tokenizer.buffer[0];
};

fn next(tokenizer: *Tokenizer) LexSymbol = {
	const symbol = tokenizer.buffer[0];
	delete(tokenizer.buffer[0]);
	return symbol;
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

fn next_expect_lexer(lexer: *Lexer, expected_ch: rune) void = {
	if (expected_ch != lexer.buffer[0]) {
		const actual_ch = lexer.buffer[0];
		fmt::fatalf("{}: Expected '{}', got '{}'", 6969, expected_ch, actual_ch);
	} else {
		delete(lexer.buffer[0]);
	};
};

fn next_expect(tokenizer: *Tokenizer, expected_kind: LexKind, index: size = 0) void = {
	if (expected_kind != tokenizer.buffer[index].kind) {
		const actual_kind = tokenizer.buffer[index].kind;
		fmt::fatalf("{}: Expected '{}', got '{}'", tokenizer.linenum, lexkind_to_rune(expected_kind), lexkind_to_rune(actual_kind));
	} else {
		delete(tokenizer.buffer[0]);
	};
};


fn next_expect_rune(tokenizer: *Tokenizer, expected_rune: rune, index: size = 0) void = {
	if (expected_rune != tokenizer.buffer[index].value) {
		const actual_rune = tokenizer.buffer[index].value;
		fmt::fatalf("{}: Expected '{}', got '{}'", tokenizer.linenum, expected_rune, actual_rune);
	} else {
		delete(tokenizer.buffer[0]);
	};
};

fn next_till_whitespace(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].value != ' ' && tokenizer.buffer[0].value != '\n') {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_char(tokenizer: *Tokenizer, char: rune) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].value != char) {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_nonchar_or_nondigit(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].kind == LexKind::CHAR || tokenizer.buffer[0].kind == LexKind::DIGIT) {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_kind(tokenizer: *Tokenizer, kinds: LexKind...) str = {
	const x: str = if (kinds[0] == LexKind::CHAR) " " else "lol";
	const buf: []rune = [];
	for (len(tokenizer.buffer) > 0) {
		let should_break = false;
		for (const kind .. kinds) {
			if (tokenizer.buffer[0].kind == kind) {
				should_break = true;
			};
		};
		if (should_break) break;
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_nonchar(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].kind == LexKind::CHAR) {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn tokenizer_parse_funcall(tokenizer: *Tokenizer, func_name: str) void = {
	fmt::println("HELLO?")!;
	next_expect(tokenizer, LexKind::PAREN_OPEN);

	fmt::println("Next:", peek_next(tokenizer).value)!;

	const value = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

	next_expect(tokenizer, LexKind::PAREN_CLOSE);
	fmt::println("helo bro?", value.value_size)!;

	append(tokenizer.tokens, FuncallToken {
		name = func_name,
		value = value
	})!;
};

fn token_is_variable(token: Token) bool = {
	
	return false;
};

fn tokenizer_find_variable_value(tokenizer: *Tokenizer, variable_identifier: str) (void | Expression) = {
	for (let i = len(tokenizer.tokens) - 1; i >= 0; i -= 1) {
		fmt::println(i)!;
		const token = tokenizer.tokens[i];
		if (token is VariableToken) {
			fmt::println((token as VariableToken).name, variable_identifier)!;
			if  ((token as VariableToken).name == variable_identifier) {
				return (token as VariableToken).value;
			};
		};
	};
	return void;
};

fn tokenizer_parse_expression(tokenizer: *Tokenizer) (Expression | invalidexpression) = {
	// is it string literal?
	if (peek_next(tokenizer).kind == LexKind::QUOTE) {
		next(tokenizer);
		const value = next_till_kind(tokenizer, LexKind::QUOTE);
		fmt::println("parse_expression - raw value:", value)!;
		next(tokenizer);
		return Expression {
			kind = ExpressionKind::STR,
			value = strings::toutf8(value),
			value_size = len(value),
			var = void
		};
	};

	// is it a number literal?
	const raw_value = next_till_nonchar_or_nondigit(tokenizer);
	if (valid_integer(raw_value)) {
		return Expression {
			kind = ExpressionKind::INT,
			value = strings::toutf8(raw_value),
			value_size = len(raw_value) * 8,
			var = void
		};
	};

	// is it variable?
	if (tokenizer_is_valid_variable(raw_value)) {
		fmt::println("parse_expression - is variable")!;
		const identifier = raw_value;
		const identifier_value = tokenizer_find_variable_value(tokenizer, identifier);
		if (identifier_value is void) {
			fmt::fatal("Error parsing identifier");
		};
		return Expression {
			kind = (identifier_value as Expression).kind,
			value = (identifier_value as Expression).value,
			value_size = len((identifier_value as Expression).value) * 8,
			var = identifier
		};
	};

	return invalidexpression;

};

fn tokenizer_is_valid_variable(identifier: str) bool = {
	const is_valid_variable = ascii::isalpha(strings::torunes(identifier)![0]);
	return is_valid_variable;
};

fn tokenizer_parse_variable_declaration(tokenizer: *Tokenizer) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);

	const identifier = next_till_nonchar(tokenizer);
	fmt::println("Identifier:", identifier)!;

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	next_expect(tokenizer, LexKind::EQUALS);

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	fmt::println("tf is next?", peek_next(tokenizer).value)!;

	const value = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

	append(tokenizer.tokens, VariableToken {
		name = identifier,
		value = value,
		kind = value.kind
	})!;

	fmt::printfln("{}, {}", identifier, strings::fromutf8(value.value)!)!;
};

// Returns whether there are still statements to be tokenized in the source file buffer.
fn tokenizer_has_next_statement(tokenizer: Tokenizer) bool = {
	let newlines_found = 0;
	let i: size = 0;
	for (newlines_found <= 1 && i < len(tokenizer.buffer)) {
		if (tokenizer.buffer[i].value == '\n') newlines_found += 1;
		i += 1;
	};
	return newlines_found >= 1;
};

fn tokenizer_parse_variable_assign(tokenizer: *Tokenizer, identifier: str) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);
	next_expect(tokenizer, LexKind::EQUALS);
	next_expect(tokenizer, LexKind::WHITESPACE);

	const value = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

	fmt::printfln("{}, {}", identifier, strings::fromutf8(value.value)!)!;
	append(tokenizer.tokens, VariableToken {
		name = identifier,
		value = value,
		kind = value.kind
	})!;
};

fn tokenizer_is_valid_builtin(keyword: str) bool = {
	for (const builtin .. builtins) {
		if (keyword == builtin) return true;
	};
	return false;
};

fn next_till_keyword(tokenizer: *Tokenizer, keyword: str) (str | void) = {
	const buf: []rune = [];
	const buffer = tokenizer.buffer;
	const keyword_runes = strings::torunes(keyword)!;
	let index = 0z;
	for (index < (len(buffer) - len(keyword))) {
		append(buf, next(tokenizer).value)!;

		// has even chance of containing the keyword
		if (len(buf) >= len(keyword)) {
			let keyword_i = len(keyword) - 1;
			let matches = true;
			for (let i: size = len(buf) - 1; i > len(buf) - len(keyword); i -= 1) {
				fmt::println("ayo", buf[i], keyword_runes[keyword_i])!;
				if (buf[i] != keyword_runes[keyword_i]) {
					matches = false;
					break;
				};
				keyword_i -= 1;
				if (matches) {
					return strings::fromrunes(buf)!;
				};
			};
		};
		};
		};

fn print_lexed_symbols(lexer: Lexer) void = {
	for (const symbol .. lexer.symbols) {
		fmt::printfln("kind: {}, value: {}", lexkind_to_rune(symbol.kind), symbol.value)!;
	};
};

fn lexer_lex_buffer(lexer: *Lexer) void = {
	for (len(lexer.buffer) > 0) {
		const symbol = next_lexer(lexer);
		fmt::println(symbol.value)!;
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

fn initiate_block_token(kind: BlockKind, is_main_fun: bool = false) BlockToken = {
	return BlockToken {
		id = if (is_main_fun) "main" else gen_id(),
		kind = kind,
		tokens = []
	};
};

fn init_blockwise_tokenizer(symbols: []LexSymbol, block: BlockToken) Tokenizer = {
	return Tokenizer {
		tokens = [],
		buffer = symbols[0..],
		linenum = 1,
		block = block
	};
};

fn tokenizer_parse_if(tokenizer: *Tokenizer) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);

	const expr1 = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	next_expect(tokenizer, LexKind::EQUALS);
	next_expect(tokenizer, LexKind::EQUALS);

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	const expr2 = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

	next_expect(tokenizer, LexKind::WHITESPACE);

	fmt::println("helo if")!;

	// do...
	next_expect_rune(tokenizer, 'd');
	next_expect_rune(tokenizer, 'o');

	const block = initiate_block_token(BlockKind::IF);
	const blockTokenizer = init_blockwise_tokenizer(tokenizer.buffer, block);
	fmt::println("parse if - parse block")!;
	tokenizer_parse_block(&blockTokenizer);

	block.tokens = blockTokenizer.tokens;

	append(tokenizer.tokens, IfToken {
		expr1 = expr1,
		expr2 = expr2,
		body = block,
		cmp = "=="
	})!;
};

fn tokenizer_parse_fun(tokenizer: *Tokenizer) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);

	const fun_name = next_till_nonchar_or_nondigit(tokenizer);

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_OPEN);
	next_expect(tokenizer, LexKind::PAREN_CLOSE);

	next_expect(tokenizer, LexKind::WHITESPACE);

	next_expect_rune(tokenizer, 'i');
	next_expect_rune(tokenizer, 's');

	next_expect(tokenizer, LexKind::NEWLINE);

	fmt::println("helo fun")!;

	const block = initiate_block_token(BlockKind::FUN, fun_name == "main");

	const blockTokenizer = init_blockwise_tokenizer(tokenizer.buffer, block);

	fmt::println("parse if - parse block")!;
	tokenizer_parse_block(&blockTokenizer);

	for (const token .. blockTokenizer.tokens) {
		fmt::println(token_to_tokenkind(token))!;
	};

	fmt::println("count", len(blockTokenizer.buffer))!;
	fmt::println("count", len(blockTokenizer.tokens))!;
	block.tokens = blockTokenizer.tokens;
	
	append(tokenizer.tokens, FunDefToken {
		name = fun_name,
		proc = FunDefProcToken {
			name = fun_name
		},
		body = block
	})!;

	fmt::println("we exit here")!;
};

fn tokenizer_parse_block(tokenizer: *Tokenizer) void = {
	const is_blockwise_tokenizer = !(tokenizer.block is void);
	const symbols = tokenizer.buffer;
	const symbols_count = len(tokenizer.buffer);
	for (tokenizer_has_next_statement(*tokenizer)) {
		if (tokenizer.block is BlockToken) {
			fmt::println("TOKENIZING FOR BLOCK TOKEN !", (tokenizer.block as BlockToken).id)!;
		};
for (const token .. tokenizer.tokens) {
		fmt::printfln(token_to_tokenkind(token))!;
	};

		fmt::println("pre: ", peek_next(tokenizer).value)!;
		const keyword = next_till_nonchar(tokenizer);
		fmt::println("post: ", peek_next(tokenizer).value)!;
		if (len(keyword) == 0) next(tokenizer);
		fmt::printfln("täs keyword: \"{}\"", keyword)!;

		// end closes block
		if (keyword == "end") {
			fmt::println("Close block")!;
			// stop iterating buffer when scope ends
			if (is_blockwise_tokenizer) {
				fmt::println("stop iterating")!;
				return;
			};

			// having end in a non-scoped context is disallowed
			fmt::fatalf("TOKENIZER_ERROR: {}: illegal \"end\" in non-scoped code", globalTokenizer.linenum);
		};

		// Check keyword
		if (tokenizer_is_valid_builtin(keyword)) {
			tokenizer_parse_funcall(tokenizer, keyword);
		} else if (keyword == "fun") {
			tokenizer_parse_fun(tokenizer);
		} else if (keyword == "let") {
			tokenizer_parse_variable_declaration(tokenizer);
		} else if (keyword == "if") {
			tokenizer_parse_if(tokenizer);
		} else if (keyword != "") {
			if (tokenizer_is_valid_variable(keyword) && !(tokenizer_find_variable_value(tokenizer, keyword) is void)) {
				tokenizer_parse_variable_assign(tokenizer, keyword);
			};
		};

		// increment internal linenum counter if was new line
		if (peek_next(tokenizer).kind == LexKind::NEWLINE) {
			tokenizer.linenum += 1;
			globalTokenizer.linenum += 1;
		};
	};

	fmt::println("Hello?")!;
	// could not find end before buffer ran out
	if (is_blockwise_tokenizer && (tokenizer.block as BlockToken).id != "main") {
		fmt::fatalf("TOKENIZER_ERROR: {}: could not find end to the block. Id: {}", globalTokenizer.linenum, (tokenizer.block as BlockToken).id);
	};
};

//fn tokenizer_parse_statement(tokenizer: *Tokenizer) void = {
//	const symbol = next(lexer);
//	const keyword = next_till_whitespace(tokenizer);
//	fmt::println("next:", tokenizer.buffer[0])!;
//	fmt::println("keyword:", keyword)!;
//	if (strings::trim(keyword) == "") {
//		next(tokenizer);
//		return;
//	};
//
//	if (tokenizer_is_valid_builtin(keyword)) {
//		tokenizer_parse_funcall(tokenizer, keyword);
//	} else if (keyword == "let") {
//		tokenizer_parse_variable_declaration(tokenizer);
//	} else {
//		if (tokenizer_is_valid_variable(keyword) && !(tokenizer_find_variable_value(tokenizer, keyword) is void)) {
//			tokenizer_parse_variable_assign(tokenizer, keyword);
//		};
//	};
//
//	tokenizer.linenum += 1;
//	next(tokenizer);
//};

// fn qbe_define_variable(token: VariableToken) str = {
// 	switch (token.kind) {
// 	case VariableKind::INT =>
// 		fmt::println("int")!;
// 	case VariableKind::STR =>
// 		fmt::println("str")!;
// 	};
// 	if (token.kind == VariableKind::INT) {
// 		const reg = qbe_get_reg_label();
// 		return strings::concat(
// 			fmt::asprintf("{} =w copy {}", reg, strings::fromutf8(token.value.value)!)!
// 		)!;
// 	};
// 	return "";
// };

fn qbe_commit(qbe: Qbe, file: io::file) void = {
	const bytes: []u8 = [];
	for (const line .. qbe.buffer) {
		for (const byte .. strings::toutf8(line)) {
			append(bytes, byte)!;
		};
	};
	io::write(file, bytes)!;
};

fn qbe_define_data(data_label: str, expression: Expression) str = {
	const value = strings::fromutf8_unsafe(expression.value);
	switch (expression.kind) {
	case ExpressionKind::INT =>
		return fmt::asprintf("data {} = {{ w {} }}\n", data_label, value)!;
	case ExpressionKind::STR =>
		return fmt::asprintf("data {} = {{ b \"{}\" }}\n", data_label, value)!;
	};
};

// shorthand to fmt::asprintf that automatically crashes program if fails.
fn format(fmt: str, args: fmt::field...) str = {
	return strings::concat(fmt::asprintf(fmt, args...)!)!;
};

// shorthand to strings::join that automatically crashes program if fails.
fn join(strs: []str, delim: str = "") str = {
	return strings::join(delim, strs...)!;
};

fn qbe_define_expression(data_label: str, expression: Expression) str = {
	const value = strings::fromutf8_unsafe(expression.value);
	switch (expression.kind) {
	case ExpressionKind::INT =>
		return fmt::asprintf("w {}", data_label)!;
	case ExpressionKind::STR =>
		return fmt::asprintf("l {}", data_label)!;
	};
};

fn qbe_define_funcall(name: str, args: str) str = {
	return strings::concat("call ", name, "(", args, ")", "\n")!;
};

// fn qbe_define_store(reg: str, data_sz: size, data: []u8, data_kind: Qbe_AllocationDataKind) str = {
// 	const elems = data_sz / ALIGNMENT;
// 	if (elems == 1 && data_kind = Qbe_AllocationDataKind::INT) {
// 		append(out, format("storel {}, ,", reg))!;
// 	} else if (elems > 1 && data_kind = Qbe_AllocationDataKind::STR) {
// 		append(out, format("storel {}, ,", reg))!;
// 	};
// };
//
//

fn itoa(num: (size | int)) str = {
	return format("{}", num);
};

fn figure_malloc_size(data_sz: size, data_kind: Qbe_AllocationDataKind) str = {
	switch (data_kind) {
	case Qbe_AllocationDataKind::STR =>
		return itoa(data_sz * 2);
	case Qbe_AllocationDataKind::INT =>
		return "8";
	};
};

fn indent(s: str, indent_level: size) str = {
	if (indent_level > 0) {
		s = strings::lpad(s, ' ', len(s) + indent_level)!;
	};
	return s;
};

fn indent_buf(buf: []str, indent_level: size) void = {
	if (indent_level > 0) {
		for (let i = 0z; i < len(buf); i += 1) {
			buf[i] = indent(buf[i], indent_level);
		};
	};
};


fn qbe_define_allocation(qbe: *Qbe, data_sz: size, data: []u8, data_kind: Qbe_AllocationDataKind, data_identifier: (str | void) = void) Qbe_Allocation = {
	let out: []str = [];
	const reg = qbe_get_reg_label(true);
	append(out, format("{}0 =l alloc8 {}", reg, figure_malloc_size(data_sz, data_kind)))!;
	if (data_sz > 1 && data_kind == Qbe_AllocationDataKind::STR) {
		append(out, format("storel {}, {}0", data[0], reg))!;
		for (let i: size = 1; i < data_sz; i += 1) {
			const byte = data[i];
			const element_reg = format("{}{}", reg, i);
			append(out, format("{} =l add {}{}, 1", element_reg, reg, i-1))!;
			append(out, format("storew {}, {}", byte, element_reg))!;
		};
	} else {
		append(out, format("storel {}, {}0", strings::fromutf8_unsafe(data), reg))!;
	};

	if (data_identifier is str) {
		append(qbe.variables, (data_identifier as str, reg))!;
	};

	// separate allocations for cleaner .ssa content
	append(out, "\n")!;
	indent_buf(out, qbe.indent_level);

	const text = join(out, "\n");
	fmt::println("alloacrtion text:", text)!;

	return Qbe_Allocation {
		name = reg,
		data_sz = data_sz,
		data = data,
		data_kind = data_kind,
		text = text
	};
};

fn qbe_define_literal_integer(data: []u8) Qbe_Integer = {
	const reg = qbe_get_reg_label();
	const text = format("{} =l copy {}\n", reg, strings::fromutf8_unsafe(data));
	return Qbe_Integer {
		name = reg,
		data = data,
		text = text
	};
};

fn qbe_define_blit(qbe: *Qbe, src_reg: str, bytes_amount: size) Qbe_Blit = {
	const dest_reg = qbe_get_reg_label(true);
	const out: []str = [];

	append(out, format("{}0 =l alloc8 {}", dest_reg, bytes_amount))!;
	append(out, format("blit {}0, {}0, {}", src_reg, dest_reg, bytes_amount))!;
	indent_buf(out, qbe.indent_level);

	return Qbe_Blit {
		name = dest_reg,
		text = join(out, "\n")

	};
};

fn qbe_write_funcall(qbe: *Qbe, token: FuncallToken) void = {
	switch (token.name) {
	case "echo" =>
		// write different printf depending of if echoing a variable
		if (token.value.var is str) {
			const var = token.value.var as str;
			const reg = get_variable_reg(*qbe, var);
			if (token.value.kind == ExpressionKind::INT) {
				const blit = qbe_define_blit(qbe, reg, token.value.value_size);
				qbe_write_noindent(qbe, blit.text)!;
				qbe_write(qbe, format("{} =l call $___itoa(l {}0)\n", blit.name, blit.name))!;
				qbe_write(qbe, format("call $__echo_str(l {})\n", blit.name))!;
			} else if (token.value.kind == ExpressionKind::STR) {
				qbe_write(qbe, format("call $__echo_str(l {}0)\n", reg))!;
			};
		} else {
			if (token.value.kind == ExpressionKind::INT) {
				const integer = qbe_define_literal_integer(token.value.value);
				qbe_write(qbe, integer.text)!;
				qbe_write(qbe, format("call $__echo_int(l {})\n", integer.name))!;

			} else if (token.value.kind == ExpressionKind::STR) {
				fmt::println("alloca")!;
				const allocation = qbe_define_allocation(qbe, token.value.value_size, token.value.value, token.value.kind);
				qbe_write_noindent(qbe, allocation.text)!;
				qbe_write(qbe, format("call $__echo_str(l {}0)\n", allocation.name))!;
			};
		};
	case => 
		return;

	};
};

fn qbe_write_function(qbe: *Qbe, token: FunDefToken) void = {
	if (token.name == "main") {
		qbe_write(qbe, "export function w $main() {")!;
	} else {
		qbe_write(qbe, format("function w $%s() {", token.name))!;
	};
	qbe_write(qbe, "@start")!;
	qbe_set_indent(qbe, 4);
	for (const token .. token.body.tokens) {
		fmt::println("täsä", token_to_tokenkind(token))!;
		// if (token is FunDefToken) {
		// 	qbe_write_function(qbe, token as FunDefToken);
		// } 
		if (token is FuncallToken) {
			qbe_write_funcall(qbe, token as FuncallToken);
		} else if (token is VariableToken) {
			qbe_write_variable(qbe, token as VariableToken);
		} else if (token is IfToken) {
			fmt::println("if token")!;
			qbe_write_if(qbe, token as IfToken);
		};
	};
	qbe_write(qbe, "ret 0")!;
	qbe_set_indent(qbe, 0);
	qbe_write(qbe, "}")!;
};

fn qbe_write_variable(qbe: *Qbe, token: VariableToken) void = {
	const allocation = qbe_define_allocation(qbe, token.value.value_size, token.value.value, token.value.kind, token.name);
	qbe_write_noindent(qbe, allocation.text)!;
};

fn qbe_write_block(qbe: *Qbe, token: BlockToken) void = {
	for (const token .. token.tokens) {
		if (token is FuncallToken) {
			qbe_write_funcall(qbe, token as FuncallToken);
		} else if (token is VariableToken) {
			qbe_write_variable(qbe, token as VariableToken);
		} else if (token is IfToken) {
			fmt::println("if token")!;
			qbe_write_if(qbe, token as IfToken);
		};
	};
};

fn qbe_write_if(qbe: *Qbe, token: IfToken) void = {
	const expr1alloc = qbe_define_allocation(qbe, token.expr1.value_size, token.expr1.value, token.expr1.kind);
	const expr2alloc = qbe_define_allocation(qbe, token.expr2.value_size, token.expr2.value, token.expr2.kind);
	qbe_write_noindent(qbe, expr1alloc.text)!;
	qbe_write_noindent(qbe, expr2alloc.text)!;
	switch (token.cmp) {
	case "==" =>
		let cmpreg1 = "";
		let cmpreg2 = "";

		if (expr1alloc.data_kind == Qbe_AllocationDataKind::INT) {
			cmpreg1 = qbe_get_loaded_reg_label(expr1alloc.name, true);
			qbe_write(qbe, format("{} =l loadl {}0", cmpreg1, expr1alloc.name))!;
		} else {
			cmpreg1= format("{}0", expr1alloc.name);
		};

		if (expr2alloc.data_kind == Qbe_AllocationDataKind::INT) {
			cmpreg2 = qbe_get_loaded_reg_label(expr2alloc.name, true);
			qbe_write(qbe, format("{} =l loadl {}0", cmpreg2, expr2alloc.name))!;
		} else {
			cmpreg2 = format("{}0", expr2alloc.name);
		};
		
		qbe_write(qbe, format("%eql =l ceql {}, {}", cmpreg1, cmpreg2))!;
	case =>
		unimplemented();
	};
	qbe_write(qbe, format("jnz %eql, @ifstart, @ifend"))!;
	qbe_write_noindent(qbe, "@ifstart")!;
	qbe_write_block(qbe, token.body);
	qbe_write_noindent(qbe, "@ifend")!;
};

export fn main() void = {
	const args = os::args[0..len(os::args)];
	const executable_name = shift_args(&args);
	const input_file = shift_args(&args);
	if (input_file is void) {
		fmt::println("No input file provided. Exiting")!;
		os::exit(1);
	};

	// flags
	let enable_execute_flag = false;
	for (len(args) > 0) {
		match (shift_args(&args)) {
		case let arg: str =>
			if (arg == "-x") enable_execute_flag = true;
		case void =>
			yield void;
		};
	};

	const (filename, extension) = strings::rcut(input_file as str, ".");
	if (extension != "nup") {
		fmt::println("Incorrect input file extension. Expecting '.nup'. Exiting")!;
	};

	const intermediary_output_file_path = strings::concat("./", filename, ".ssa")!;
	const intermediary_output_file = os::create(intermediary_output_file_path, fs::mode::USER_RW)!;

	const nup_file_contents = read_file_contents(input_file as str);

	const lexer = Lexer {
		symbols = [],
		buffer = strings::torunes(strings::trim(nup_file_contents))!,
	};
	
	// Lex the buffer, saving the lexed symbols into the Lexer
	lexer_lex_buffer(&lexer);
	print_lexed_symbols(lexer); // debug

	// Initialize the tokenizer based on the lexer's accumulated output data buffer
	globalTokenizer = init_tokenizer(lexer);

	// Parse globally
	tokenizer_parse_block(&globalTokenizer);

	// Initialize qbe struct and prefill the buffer with base utilities and
	// functions
	const qbe = qbe_initialize("./base.qbe");

	for (const token .. globalTokenizer.tokens) {
		if (token is FunDefToken) {
			qbe_write_function(&qbe, token as FunDefToken);
		};
		// else if (token is FuncallToken) {
		// 	qbe_write_funcall(&qbe, token as FuncallToken);
		// } else if (token is VariableToken) {
		// 	qbe_write_variable(&qbe, token as VariableToken);
		// } else if (token is IfToken) {
		// 	qbe_write_if(&qbe, token as IfToken);
		// };
	};

	qbe_commit(qbe, intermediary_output_file);
	qbe_compile(intermediary_output_file_path, filename)!;

	if (enable_execute_flag) {
		fmt::println("\nOutput:")!;
		fmt::println(run_executable_and_capture_stdout(filename)!)!;
	};

};
