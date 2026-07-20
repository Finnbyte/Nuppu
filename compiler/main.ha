// Important conventions (may not yet be fully fulfilled):
// Strings in qbe MUST be uppercase and, when given as parameters, have 0 to signify being an array
//
// ExprTree = {
//     left: ExprTree | ExprNode
//     right: ExprTree | ExprNode
// }

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
	case => return "UNRECOGNIZED?";
	};
};

fn token_to_tokenkind(token: Token) str = {
	match (token) {
	case VariableToken => return "VariableToken";
	case IfToken => return "IfToken";
	case FuncallToken => return "FuncallToken";
	case FunDefToken => return "FunDefToken";
	case ReservedKeywordToken => return "ReservedKeywordToken";
	};
};

fn rune_to_lexkind(ch: rune) LexKind = {
	switch (ch) {
	case '(' => return LexKind::PAREN_OPEN;
	case ')' => return LexKind::PAREN_CLOSE;
	case ',' => return LexKind::COMMA;
	case ' ' => return LexKind::WHITESPACE;
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

type LexSymbol = struct {
	kind: LexKind,
	value: rune
};

type Expression = struct {
	kind: ExpressionKind,
	value: []u8,
	value_size: size
};

type FunctionExpression = struct {
	name: str,
	var: (str | void),
	arguments: []AnyExpression
};

type VariableExpression = struct {
	name: str,
	var: (str | void)
};

type AnyExpression = (Expression | VariableExpression | FunctionExpression);

type Qbe_Identifier = struct {
	reg: str,
	kind: Qbe_IdentifierKind,
	index: (int | void)
};

type Qbe_Variable = struct {
	reg: Qbe_Identifier,
	src_variable: (str | void),
	value: (Expression | void),
	kind: ExpressionKind,
	text: (str | void),
	is_emitted: bool
};

type Qbe_ScopeKind = enum {
	FUN,
	IF,
	GLOBAL
};

type Qbe_Scope = struct {
	id: str,
	kind: Qbe_ScopeKind,
	variables: []Qbe_Variable
};

type ReservedKeywordToken = enum {
	RETURN
};

type FuncallToken = struct {
	name: str,
	arguments: []AnyExpression,
};

type BlockToken = struct {
	kind: BlockKind,
	id: str,
	tokens: []Token
};

type ParameterToken = struct {
	name: str,
	kind: ExpressionKind
};

type FunDefToken = struct {
	name: str,
	proc: FunDefProcToken,
	body: BlockToken
};

type FunDefProcToken = struct {
	name: str,
	parameters: []ParameterToken
};

type IfToken = struct {
	expr1: AnyExpression,
	expr2: AnyExpression,
	cmp: str,
	body: BlockToken
};

type Token = (VariableToken | FuncallToken | IfToken | FunDefToken | ReservedKeywordToken);

type VariableToken = struct {
	kind: VariableKind,
	name: str,
	value: AnyExpression
};

type Tokenizer = struct {
	block: (BlockToken | void),
	tokens: []Token,
	buffer: []LexSymbol,
	linenum: int,

};

fn get_variable_reg(qbe: *Qbe, variable_identifier: str) Qbe_Identifier = {
	fmt::println("to find", variable_identifier)!;
	const scope = qbe.scope;
	fmt::println(len(scope.variables))!;
	if (len(scope.variables) == 0) fmt::fatal("Could not find reg");
	for (let i: size = len(scope.variables) - 1; i >= 0; i -= 1 ) {
		fmt::println("lol", i)!;
		// found variable
		const variable = scope.variables[i];
		fmt::printfln("Identifier: {}, reg: {} (searching for {}", variable.src_variable, variable.reg.reg, variable_identifier)!;
		if (variable.src_variable is str && (variable.src_variable as str) == variable_identifier) {
			fmt::printfln("found!")!;
			return variable.reg;
		};
	};
	fmt::fatal("Could not find reg");
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

type Qbe_Integer = struct {
	reg: Qbe_Identifier,
	data: []u8,
	text: str
};

type Qbe_Blit = struct {
	reg: Qbe_Identifier,
	text: str
};

fn pass() void = {
	return void;
};

fn unimplemented(msg: str = "TODO") never = {
	fmt::fatalf("NOT YET IMPLEMENTED: {}", msg);
};

type invalidexpression = !void;

type VariableKind = ExpressionKind;

type Qbe_VariableDataKind = ExpressionKind;
type Qbe_IdentifierKind = enum {
	REG,
	DATA
};

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
	context: str,
	buffer: []str,
	scopes: []Qbe_Scope,
	scope: Qbe_Scope,
	datas: []Qbe_Variable
};

type Qbe_WritePosition = (int | Qbe_WritePositionKind);

fn gen_id() str = {
	return uuid::encodestr(uuid::generate());
};

fn qbe_initialize(base_file_path: str) Qbe = {
	const base_contents = read_file_contents(base_file_path, false);
	const lines = strings::split(base_contents, "\n")!;
	const initial_scope = Qbe_Scope {
			id = "global",
			kind = Qbe_ScopeKind::GLOBAL,
			variables = []
		};
	const qbe = Qbe {
		context = "",
		indent_level = 0,
		buffer = [],
		datas = [],
		scopes = [],
		scope = initial_scope
	};

	// Set initial scope data
	append(qbe.scopes, initial_scope)!;
	qbe.scope = initial_scope;

	for (const line .. lines) {
		qbe_write(&qbe, line)!;
	};
	return qbe;
};

fn qbe_inc_reg(reg: *Qbe_Identifier, count: int) void = {
	assert(reg.index is int);
	match (reg.index) {
	case let index: int => reg.index = index + 1;
	case => pass();
	};

};

fn qbe_show_reg(reg: Qbe_Identifier) str = {
	return format("{}{}", reg.reg, if (reg.index is int) reg.index else "");
};

fn qbe_get_reg_label(is_array: bool = false) Qbe_Identifier = {
	let reg = registers[0];
	static delete(registers[0]);
	switch (is_array) {
	case true => reg = format("{}0", ascii::strupper(reg)!);
	case false => reg = reg;
	};
	return Qbe_Identifier {
		reg = reg,
		kind = Qbe_IdentifierKind::REG,
		index = 0
	};

};

fn qbe_get_loaded_reg_label(label: str, uppercase: bool = false) Qbe_Identifier = {
	if (uppercase) label = ascii::strupper(label)!;
	if (!uppercase) label = ascii::strlower(label)!;

	return Qbe_Identifier {
		reg = format("{}L", label),
		index = void,
		kind = Qbe_IdentifierKind::REG
	};
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

fn tokenizer_parse_funcall_args(tokenizer: *Tokenizer) []AnyExpression = {
	const expressions: []AnyExpression = alloc([], size(Expression))!;

	for (peek_next(tokenizer).kind != LexKind::PAREN_CLOSE) {
		const value = match (tokenizer_parse_expression(tokenizer)) {
		case let expression: Expression => 
			yield expression;
		case let expression: VariableExpression => 
			yield expression;
		case let expression: FunctionExpression => 
			yield expression;
		case invalidexpression => 
			fmt::fatal("Invalid expression encountered");
		};

		append(expressions, value)!;

		if (peek_next(tokenizer).kind == LexKind::COMMA) {
			next(tokenizer);
			skip_empty(tokenizer);
		};
	};

	return expressions;
};

fn tokenizer_parse_funcall(tokenizer: *Tokenizer, func_name: str) void = {
	fmt::println("HELLO?")!;
	next_expect(tokenizer, LexKind::PAREN_OPEN);

	fmt::println("Next:", peek_next(tokenizer).value)!;

	const arguments = tokenizer_parse_funcall_args(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_CLOSE);

	append(tokenizer.tokens, FuncallToken {
		name = func_name,
		arguments = arguments,
	})!;
};

fn token_is_variable(token: Token) bool = {

	return false;
};

fn print_tokenizer_id(tokenizer: Tokenizer) void = {
	if (tokenizer.block is void) {
		fmt::println("Global Tokenizer")!;
	} else {
		fmt::println((tokenizer.block as BlockToken).id)!;
	};
};

// fn tokenizer_find_variable_value(tokenizer: *Tokenizer, variable_identifier: str) (void | Expression) = {
// 	fmt::println("tokenizer_find_variable_value called with keyword:", variable_identifier)!;
// 	if (len(tokenizer.tokens) < 1) {
// 		fmt::fatalf("Could not find variable value for '{}'", variable_identifier);
// 	};
// 	fmt::println(len(tokenizer.tokens))!;
// 	for (let i = len(tokenizer.tokens) - 1; i >= 0; i -= 1) {
// 		print_tokenizer_id(*tokenizer);
// 		fmt::println(len(tokenizer.tokens))!;
// 		const token = tokenizer.tokens[i];
// 		if (token is VariableToken) {
// 			fmt::println((token as VariableToken).name, variable_identifier)!;
// 			if  ((token as VariableToken).name == variable_identifier) {
// 				return (token as VariableToken).value;
// 			};
// 		};
// 		if (token is FunDefToken) {
// 			const proc = (token as FunDefToken).proc;
// 			for (const param .. proc.parameters) {
// 				fmt::println("ON FUN DEF MATCH")!;
// 				if  (param.name == variable_identifier) {
// 					return Expression {
// 						kind = param.kind,
// 						value = [],
// 						value_size = 69420,
// 						var = param.name
// 					};
// 				};
// 			};
// 
// 		};
// 	};
// 	return void;
// };

fn tokenizer_parse_expression(tokenizer: *Tokenizer) (Expression | VariableExpression | FunctionExpression | invalidexpression) = {
	fmt::println(lexkind_to_rune(peek_next(tokenizer).kind))!;
	fmt::println("parsing expr:", peek_next(tokenizer).value)!;
	// is it string literal?
	if (peek_next(tokenizer).kind == LexKind::QUOTE) {
		next(tokenizer);
		const value = next_till_kind(tokenizer, LexKind::QUOTE);
		fmt::println("parse_expression - raw value:", value, "is sized", len(value))!;
		next(tokenizer);
		return Expression {
			kind = ExpressionKind::STR,
			value = strings::toutf8(value),
			value_size = len(value),
		};
	};

	const raw_value = next_till_nonchar_or_nondigit(tokenizer);

	// is it a number literal?
	if (valid_integer(raw_value)) {
		fmt::println("parse_expr - is int")!;
		return Expression {
			kind = ExpressionKind::INT,
			value = strings::toutf8(raw_value),
			value_size = len(raw_value),
		};
	};

	// is it variable?
	if (tokenizer_is_valid_variable(raw_value) && peek_next(tokenizer).kind != LexKind::PAREN_OPEN) {
		fmt::println("parse_expression - is variable")!;
		const identifier = raw_value;
		return VariableExpression {
			name = identifier,
			var = identifier
		};
	};

	// is it function call expression?
	if (tokenizer_is_valid_variable(raw_value) && peek_next(tokenizer).kind == LexKind::PAREN_OPEN) {
		next(tokenizer);
		const function_expression = FunctionExpression {
			name = raw_value,
			arguments = [],
			var = void
		};

		const arguments: []AnyExpression = [];
		for (peek_next(tokenizer).kind != LexKind::PAREN_CLOSE) {
			if (peek_next(tokenizer).kind == LexKind::COMMA) next(tokenizer);
			skip_empty(tokenizer);
			match (tokenizer_parse_expression(tokenizer)) {
			case let x: Expression => append(arguments, x)!;
			case let x: VariableExpression => append(arguments, x)!;
			case let x: FunctionExpression => append(arguments, x)!;
			case invalidexpression => fmt::fatal("Invalid expr");
			};
		};

		fmt::printfln("{}: {}", function_expression.name, len(arguments))!;
		function_expression.arguments = arguments;
		return function_expression;
	};

	return invalidexpression;

};

fn tokenizer_is_valid_variable(identifier: str) bool = {
	const is_valid_variable = ascii::isalpha(strings::torunes(identifier)![0]);
	return is_valid_variable;
};

fn tokenizer_parse_variable_declaration(tokenizer: *Tokenizer) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);

	const identifier = next_till_nonchar_or_nondigit(tokenizer);
	fmt::println("Identifier:", identifier)!;
	if (!tokenizer_is_valid_variable(identifier)) {
		fmt::fatalf("TOKENIZER_ERROR: invalid variable name '{}'", identifier);
	};
	next_expect(tokenizer, LexKind::COLON);
	skip_empty(tokenizer);
	const var_type = switch (next_till_nonchar_or_nondigit(tokenizer)) {
	case "int" => yield VariableKind::INT;
	case "str" => yield VariableKind::STR;
	case => fmt::fatal("invalid type");
	};

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	next_expect(tokenizer, LexKind::EQUALS);

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	fmt::println("tf is next?", peek_next(tokenizer).value)!;

	const value = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case let expression: VariableExpression => 
		yield expression;
	case let expression: FunctionExpression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

	append(tokenizer.tokens, VariableToken {
		name = identifier,
		value = value,
		kind = var_type
	})!;
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

fn tokenizer_should_stop(tokenizer: *Tokenizer) bool = {
	assert(!(tokenizer.block is void));
	fmt::printfln("Considering if {} should stop.", (tokenizer.block as BlockToken).id)!;
	const keyword = "end";
	if (len(tokenizer.buffer) <= 0 || len(tokenizer.buffer) <= len(keyword)) return true;
	const keyword_runes = strings::torunes(keyword)!;
	const block = tokenizer.block as BlockToken;

	let found_end = true;
	for (let i: size = 0; i < len(keyword); i += 1) {
		if (tokenizer.buffer[i].value != keyword_runes[i]) {
			found_end = false;
		};
	};

	return found_end;
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

fn initiate_block_token(kind: BlockKind, fun_name: (str | void) = void) BlockToken = {
	let id: str = @undefined;

	if (kind == BlockKind::FUN) {
		assert(!(fun_name is void));
		id = fun_name as str;
	} else if (kind == BlockKind::IF) {
		id = gen_id();
	};

	return BlockToken {
		id = id,
		kind = kind,
		tokens = []
	};
};

fn init_blockwise_tokenizer(symbols: []LexSymbol, block: BlockToken) Tokenizer = {
	const symbols_clone: []LexSymbol = [];
	for (const symbol .. symbols) {
		append(symbols_clone, symbol)!;
	};
	return Tokenizer {
		tokens = [],
		buffer = symbols_clone,
		linenum = 1,
		block = block
	};
};

fn tokenizer_parse_if(tokenizer: *Tokenizer) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);

	const expr1 = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case let expression: VariableExpression => 
		yield expression;
	case let expression: FunctionExpression => 
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
	const blockwise_tokenizer = init_blockwise_tokenizer(tokenizer.buffer, block);
	fmt::println("parse if - parse block")!;
	tokenizer_parse_block(&blockwise_tokenizer);

	block.tokens = blockwise_tokenizer.tokens;

	append(tokenizer.tokens, IfToken {
		expr1 = expr1,
		expr2 = expr2,
		body = block,
		cmp = "=="
	})!;

	tokenizer.buffer = blockwise_tokenizer.buffer;
	// Go ahead to avoid retokenizing from nested if tokenizer
	for (let i = 0z; i < 4; i+= 1) {
		next(tokenizer);
	};
};

fn tokenizer_parse_fun_parameters(tokenizer: *Tokenizer) []ParameterToken = {
	const parameters: []ParameterToken = alloc([], size(ParameterToken))!;

	const parameters_lst = strings::split(next_till_kind(tokenizer, LexKind::PAREN_CLOSE), ",")!;
	for (const param .. parameters_lst)  {
		const splitted_param = strings::split(param, ":")!;
		assert(len(splitted_param) == 2);
		const param_name = strings::trim(splitted_param[0]);
		const param_type = strings::trim(splitted_param[1]);
		fmt::println("hey", param_type)!;
		const kind = switch (param_type) {
		case "int" => yield ExpressionKind::INT;
		case => yield ExpressionKind::STR;
		};
		append(parameters, ParameterToken {
			name = param_name,
			kind = kind
		})!;
	};
	return parameters;
};

// Skips `LexKind::WHITESPACE` characters in the tokenizer.
// Returns how many were skipped.
fn skip_empty(tokenizer: *Tokenizer) size = {
	let skip_count = 0z;
	for (peek_next(tokenizer).kind == LexKind::WHITESPACE) {
		next(tokenizer);
		skip_count += 1;
	};
	return skip_count;
};


fn tokenizer_parse_fun(tokenizer: *Tokenizer) void = {
	next_expect(tokenizer, LexKind::WHITESPACE);

	const fun_name = next_till_nonchar_or_nondigit(tokenizer);

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_OPEN);

	const parameters = tokenizer_parse_fun_parameters(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_CLOSE);

	next_expect(tokenizer, LexKind::WHITESPACE);

	next_expect_rune(tokenizer, 'i');
	next_expect_rune(tokenizer, 's');

	next_expect(tokenizer, LexKind::NEWLINE);

	fmt::println("helo fun")!;

	const block = initiate_block_token(BlockKind::FUN, fun_name);
	const blockwise_tokenizer = init_blockwise_tokenizer(tokenizer.buffer, block);

	append(blockwise_tokenizer.tokens, FunDefToken {
		name = fun_name,
		proc = FunDefProcToken {
			name = fun_name,
			parameters = parameters
		},
		body = block
	})!;

	fmt::println("parse fun - parse block")!;
	tokenizer_parse_block(&blockwise_tokenizer);

	for (const token .. blockwise_tokenizer.tokens) {
		fmt::println(token_to_tokenkind(token))!;
	};

	fmt::println("count", len(blockwise_tokenizer.buffer))!;
	fmt::println("count", len(blockwise_tokenizer.tokens))!;
	block.tokens = blockwise_tokenizer.tokens;

	append(tokenizer.tokens, FunDefToken {
		name = fun_name,
		proc = FunDefProcToken {
			name = fun_name,
			parameters = parameters
		},
		body = block
	})!;

	tokenizer.buffer = blockwise_tokenizer.buffer;


	fmt::println("we exit here")!;

	// Go ahead to avoid retokenizing from nested if tokenizer
	for (let i = 0z; i < 4; i+= 1) {
		next(tokenizer);
	};
};

fn tokenizer_parse_buffer(tokenizer: *Tokenizer) void = {
	for (tokenizer_has_next_statement(*tokenizer)) {
		const keyword = next_till_nonchar(tokenizer);
		if (len(keyword) == 0) next(tokenizer);

		// only allow function definitions for now
		if (keyword == "fun") {
			tokenizer_parse_fun(tokenizer);
		};
		// if (tokenizer_is_valid_builtin(keyword)) {
		// 	tokenizer_parse_funcall(tokenizer, keyword);
		// } else 
		// } else if (keyword == "let") {
		// 	tokenizer_parse_variable_declaration(tokenizer);
		// } else if (keyword == "if") {
		// 	tokenizer_parse_if(tokenizer);
		// } else if (keyword != "") {
		// 	if (tokenizer_is_valid_variable(keyword) && !(tokenizer_find_variable_value(tokenizer, keyword) is void)) {
		// 		tokenizer_parse_variable_assign(tokenizer, keyword);
		// 	};
		// };
};
};

fn tokenizer_parse_block(tokenizer: *Tokenizer) void = {
	const is_blockwise_tokenizer = !(tokenizer.block is void);
	const symbols = tokenizer.buffer;
	const symbols_count = len(tokenizer.buffer);
	for (!tokenizer_should_stop(tokenizer)) {
		// could not find end before buffer ran out
		if (len(tokenizer.buffer) < 3) {
			fmt::fatalf("TOKENIZER_ERROR: {}: could not find end to the block. Id: {}", globalTokenizer.linenum, (tokenizer.block as BlockToken).id);
		};
		fmt::println("TOKENIZING FOR BLOCK TOKEN !", (tokenizer.block as BlockToken).id)!;

		fmt::println("pre: ", peek_next(tokenizer).value)!;
		const keyword = next_till_nonchar_or_nondigit(tokenizer);
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
		if (peek_next(tokenizer).kind == LexKind::PAREN_OPEN) {
			tokenizer_parse_funcall(tokenizer, keyword);
		} else if (keyword == "fun") {
			tokenizer_parse_fun(tokenizer);
		} else if (keyword == "let") {
			tokenizer_parse_variable_declaration(tokenizer);
		} else if (keyword == "if") {
			tokenizer_parse_if(tokenizer);
		} else if (keyword == "return") {
			append(tokenizer.tokens, ReservedKeywordToken::RETURN)!;
		} else if (keyword != "") {
			if (tokenizer_is_valid_variable(keyword)) {
				skip_empty(tokenizer);
				next_expect(tokenizer, LexKind::EQUALS);
				tokenizer_parse_variable_assign(tokenizer, keyword);
			};
		};

		// increment internal linenum counter if was new line
		if (peek_next(tokenizer).kind == LexKind::NEWLINE) {
			tokenizer.linenum += 1;
			globalTokenizer.linenum += 1;
		};
	};

	fmt::println("buf length:", len(tokenizer.buffer))!;
	fmt::println(lexkind_to_rune(tokenizer.buffer[0].kind))!;
	fmt::println("Hello?")!;
	if (len(tokenizer.buffer) < 3) {
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

fn qbe_define_data(qbe: *Qbe, name: str, expression: Expression) Qbe_Variable = {
	fmt::println("name:", name)!;
	const found = qbe_globals_find_var_by_val(qbe, expression.value);
	if (!(found is void)) fmt::println("found:", (found as Qbe_Variable).text)!;

	const value = strings::fromutf8_unsafe(expression.value);
	let result = "";
	switch (expression.kind) {
	case ExpressionKind::INT =>
		result = format("data {} = {{ w {} }}\n", name, value);
	case ExpressionKind::STR =>
		result = format("data {} = {{ b \"{}\", b 0 }}\n", name, value);
	};

	const var = Qbe_Variable {
		reg = Qbe_Identifier {
			reg = name,
			kind = Qbe_IdentifierKind::DATA,
			index = void

		},
		kind = expression.kind,
		src_variable = void,
		value = expression,
		text = result,
		is_emitted = false
	};

	qbe_add_global_data(qbe, var);

	return var;
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

fn qbe_define_funcall_args(qbe: *Qbe, arguments: []AnyExpression) str = {
	const call_args: []str = [];
	for (const arg .. arguments) {
		match (arg) {
		case let arg: Expression =>
			fmt::println("arg is plain expr, value:", strings::fromutf8_unsafe(arg.value))!;
			switch (arg.kind) {
			case ExpressionKind::INT =>
				const integer = qbe_define_literal_integer(qbe, arg.value);
				fmt::println("WRITING INTEGER")!;
				qbe_write(qbe, (integer.text as str))!;
				append(call_args, format("l {}", qbe_show_reg(integer.reg)))!;
			case ExpressionKind::STR =>
				const label = qbe_get_data_label();
				const data = qbe_define_data(qbe, label, arg);
				qbe_write_noindent(qbe, (data.text as str), Qbe_WritePositionKind::PREPEND)!;
				append(call_args, format("l {}", data.reg.reg))!;
			};

		case let arg: FunctionExpression => unimplemented("FUNCTION EXPR NOT IMPLEMENTED");
		case let arg: VariableExpression => 
			fmt::println("arg", arg.name)!;
			const result = qbe_scope_find_var_by_src_var(qbe, arg.name);
			match (result) {
			case let var: Qbe_Variable => append(call_args, format("l {}", qbe_show_reg(var.reg)))!;
			case void => fmt::fatalf("Could not find variable: {}", arg.name);
			};
		};
	};

	const result =  join(call_args, ", ");
	fmt::println("result", result)!;
	return result;
};

fn qbe_define_funcall(qbe: *Qbe, token: FuncallToken) str = {
	let text: str = @undefined;

		fmt::println("HEIIIII")!;
	// handle recursive fun call
	if (token.name == qbe.scope.id) {
		unimplemented("Recursive call");
	};

	// No args
	if (len(token.arguments) == 0) {
		text = format("call ${}()\n", token.name);
		return text;
	};

	const argumnts = qbe_define_funcall_args(qbe, token.arguments);

	text = format("call ${}({})\n", token.name, argumnts);
	return text;

};

// fn qbe_define_store(reg: str, data_sz: size, data: []u8, data_kind: Qbe_VariableDataKind) str = {
// 	const elems = data_sz / ALIGNMENT;
// 	if (elems == 1 && data_kind = Qbe_VariableDataKind::INT) {
// 		append(out, format("storel {}, ,", reg))!;
// 	} else if (elems > 1 && data_kind = Qbe_VariableDataKind::STR) {
// 		append(out, format("storel {}, ,", reg))!;
// 	};
// };
//
//

fn itoa(num: (size | int)) str = {
	return format("{}", num);
};

fn figure_malloc_size(data_sz: size, data_kind: Qbe_VariableDataKind) str = {
	switch (data_kind) {
	case Qbe_VariableDataKind::STR =>
		return itoa(data_sz * 2);
	case Qbe_VariableDataKind::INT =>
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


fn qbe_define_allocation(qbe: *Qbe, data_sz: size, data: []u8, data_kind: Qbe_VariableDataKind, data_identifier: (str | void) = void) Qbe_Variable = {
	// Emit as global data if non-identifier string
	if (data_kind == Qbe_VariableDataKind::STR && data_identifier is void) {
		const data = qbe_define_data(qbe, qbe_get_data_label(), Expression {
			kind = data_kind,
			value = data,
			value_size = data_sz,
		});

		return Qbe_Variable {
			reg = data.reg,
			kind = (data.value as Expression).kind,
			value = (data.value as Expression),
			src_variable = data_identifier,
			text = (data.text as str),
			is_emitted = false
		};
	};

	const scope = qbe.scope;
	let out: []str = [];
	fmt::println(data_sz, strings::fromutf8_unsafe(data))!;
	const reg = qbe_get_reg_label(true);
	append(out, format("{} =l call $malloc(w {})", qbe_show_reg(reg), figure_malloc_size(data_sz, data_kind)))!;
	if (data_sz > 1 && data_kind == Qbe_VariableDataKind::STR && !(data_identifier is void)) {
		append(out, format("storel {}, {}", data[0], qbe_show_reg(reg)))!;
		for (let i: size = 1; i < data_sz; i += 1) {
			fmt::println(i)!;
			const byte = data[i];
			const previous_reg = qbe_show_reg(reg);
			qbe_inc_reg(&reg, 1);
			const new_reg = qbe_show_reg(reg);
			append(out, format("{} =l add {}, 1", new_reg, previous_reg))!;
			append(out, format("storew {}, {}", byte, new_reg))!;
		};
	} else {
		append(out, format("storel {}, {}", strings::fromutf8_unsafe(data), qbe_show_reg(reg)))!;
	};

	// separate allocations for cleaner .ssa content
	append(out, "\n")!;
	indent_buf(out, qbe.indent_level);

	const text = join(out, "\n");

	const var = Qbe_Variable {
		reg = reg,
		kind = data_kind,
		src_variable = data_identifier,
		value = Expression {
			kind = data_kind,
			value = data,
			value_size = data_sz
		},
		text = text,
		is_emitted = false
	};

	qbe_scope_add_variable(qbe, var);

	return var;
};

fn qbe_write_variable(qbe: *Qbe, token: VariableToken) void = {
	const datum = qbe_define_datum(qbe, token.value);
	datum.src_variable = token.name;
	qbe_scope_add_variable(qbe, datum);
	qbe_write_datum(qbe, datum);
};

fn qbe_define_datum(qbe: *Qbe, expr: AnyExpression) Qbe_Variable = {
	fmt::println("defining datum")!;
	match (expr) {
	case let expr: Expression => 
		fmt::println("datum is primitive")!;
		const value = expr.value;
		const value_size = expr.value_size;
		const kind = expr.kind;

		// "Weird" case first: is it a parameter?
		if (value_size == -1) {
			fmt::println("Value size is 1")!;

		};

		// Easy case first: is it a literal integer?
		if (kind == VariableKind::INT) {
			const integer = qbe_define_literal_integer(qbe, value);
			return integer;
		};

		const allocation = qbe_define_allocation(qbe, value_size, value, kind);
		return allocation;
	case let expr: FunctionExpression => 
		fmt::println("datum is function")!;
		const reg = qbe_get_reg_label();
		const var = Qbe_Variable {
			reg = reg,
			src_variable = void,
			kind = ExpressionKind::INT,
			value = void,
			// must recursively expand args tho... since qbe doesn't
			// support inline calls
			text = format("{} =l call ${}({})", qbe_show_reg(reg), expr.name, qbe_define_funcall_args(qbe, expr.arguments)),
			is_emitted = false
		};
		qbe_scope_add_variable(qbe, var);
		return var;
	case let expr: VariableExpression => 
		fmt::println("datum is variable")!;
		const result = qbe_scope_find_var_by_src_var(qbe, expr.name);
		fmt::println("found variable result")!;
		match (result) {
		case let var: Qbe_Variable => return var;
		case void => fmt::fatal("COULD NOT FIND RESULT IN DEFINE DATUM");
		};
	case => fmt::fatal("Incorrect expr type encountered while writing datum");
	};
};

fn qbe_define_literal_integer(qbe: *Qbe, data: []u8) Qbe_Variable = {
	const reg = qbe_get_reg_label();
	const text = format("{} =l copy {}\n", qbe_show_reg(reg), strings::fromutf8_unsafe(data));

	const var = Qbe_Variable {
		reg = reg,
		src_variable = void,
		kind = ExpressionKind::INT,
		value = Expression {
			value = data,
			value_size = 8,
			kind = ExpressionKind::INT,
		},
		text = text,
		is_emitted = false
	};

	qbe_scope_add_variable(qbe, var);

	return var;
};

fn qbe_define_blit(qbe: *Qbe, src_reg: Qbe_Identifier, bytes_amount: size) Qbe_Blit = {
	const dest_reg = qbe_get_reg_label(true);
	const dest_reg_str = qbe_show_reg(dest_reg);
	const src_reg_str = qbe_show_reg(src_reg);
	const out: []str = [];

	append(out, format("{} =l alloc8 {}", dest_reg_str, bytes_amount))!;

	const var = qbe_scope_find_var_by_reg(qbe, src_reg);
	if (var is void) {
		fmt::fatal("COULD NOT FIND VARIABLE");
	};

	if ((var as Qbe_Variable).kind == ExpressionKind::INT) {
		append(out, format("storel {}, {}", src_reg_str, dest_reg_str))!;
	} else {
		append(out, format("blit {}, {}, {}", src_reg_str, dest_reg_str, bytes_amount))!;
	};

	indent_buf(out, qbe.indent_level);

	return Qbe_Blit {
		reg = dest_reg,
		text = join(out, "\n")

	};
};

fn qbe_regs_are_equal(reg1: Qbe_Identifier, reg2: Qbe_Identifier) bool = {
	return qbe_show_reg(reg1) == qbe_show_reg(reg2);
};

fn qbe_scope_find_var_by_reg(qbe: *Qbe, reg_to_find: Qbe_Identifier) (Qbe_Variable | void)  = {
	for (const variable .. qbe.scope.variables) {
		if (qbe_regs_are_equal(variable.reg, reg_to_find)) {
			return variable;
		};
	};
	return void;
};

fn qbe_globals_find_var_by_val(qbe: *Qbe, value_to_find: []u8) (Qbe_Variable | void)  = {
	fmt::println(len(qbe.datas))!;
	for (const variable .. qbe.datas) {
		if (variable.value is void) continue;
		const expr: Expression = (variable.value as Expression);
		const value = expr.value;
		const as_str = strings::fromutf8_unsafe(value); 
		if (as_str == "") continue;
		if (len(value) >= 0 && len(value_to_find) >= 0 && len(value) < len(value_to_find) || len(value) > len(value_to_find)) continue;
		let found = false;
		for (let i = 0z; i < len(value_to_find) - 1; i += 1) {
			fmt::println("Arg", value_to_find[i], variable.reg.reg)!;
			if (value_to_find[i] != value[i]) {
				found = false;

			};
		};
		if (found) {
			return variable;
		};
	};
	return void;
};

fn qbe_scope_find_var_by_src_var(qbe: *Qbe, src_var_to_find: str) (Qbe_Variable | void) = {
	fmt::println(len(qbe.scope.variables))!;
	for (const variable .. qbe.scope.variables) {
		fmt::println("yo gng", variable.src_variable)!;
		if (variable.src_variable is str && (variable.src_variable as str) == src_var_to_find) {
			return variable;
		};
	};
	return void;
};

fn qbe_write_funcall(qbe: *Qbe, token: FuncallToken) void = {
	// handle recursive fun call
	// if (token.name == qbe.scope.id) {
	// 	qbe_write(qbe, "call $lol(l %b0)")!;
	// 	return;
	// };

	// No args
	if (len(token.arguments) == 0) {
		qbe_write(qbe, format("call ${}()\n", token.name))!;
		return;
	};

	const arguments = qbe_define_funcall_args(qbe, token.arguments);

	qbe_write(qbe, format("call ${}({})\n", token.name, arguments))!;
};

fn qbe_define_function_parameters(qbe: *Qbe, proc: FunDefProcToken) str = {
	const out: []str = [];
	for (const arg .. proc.parameters) {
		const identifier = Qbe_Identifier {
			reg = format("%{}", arg.name),
			kind = Qbe_IdentifierKind::REG,
			index = void
		};
		// FEAT: make uppercase for strings
		append(out, format("l {}", identifier.reg))!;
		fmt::println("HERE DEFINING ARG TO SCOPE", qbe.scope.id)!;
		qbe_scope_add_variable(qbe, Qbe_Variable {
			kind = arg.kind,
			reg = identifier,
			src_variable = arg.name,
			value = void,
			text = format("l {}", qbe_show_reg(identifier)),
			is_emitted = true
		});
	};

	return join(out, ", ");
};

fn qbe_scope_add_variable(qbe: *Qbe, variable: Qbe_Variable) void = {
	// assert(variable.src_variable is str);
	append(qbe.scopes[len(qbe.scopes) - 1].variables, variable)!;
	qbe.scope = qbe.scopes[len(qbe.scopes) - 1];
	fmt::printfln("adding {} to {}", variable.src_variable, qbe.scopes[len(qbe.scopes) - 1].id)!;
};

fn qbe_add_global_data(qbe: *Qbe, variable: Qbe_Variable) void = {
	append(qbe.datas, variable)!;
};

fn qbe_scope_push(qbe: *Qbe, scope_id: str, scope_kind: Qbe_ScopeKind) void = {
	// TODO: push current scope items into new scope.
	// this means to treat the scope as a sort-of *stack*.
	
	fmt::println("push to scope", scope_id)!;
	const variables: []Qbe_Variable = [];

	if (len(qbe.scopes) == 1) {
		for (const data .. qbe.datas) {
			append(variables, data)!;
		};
	};

	for (const scope .. qbe.scopes[1..]) {
		fmt::println("here!", scope.id)!;
		for (const var .. scope.variables) {
			fmt::println("here 2", var.src_variable)!;
			append(variables, var)!;
		};
	};

	const new_scope = Qbe_Scope {
		id = scope_id,
		kind = scope_kind,
		variables = variables
	};

	append(qbe.scopes, new_scope)!;

	qbe.scope = new_scope;
};

fn qbe_scope_pop(qbe: *Qbe) void = {
	delete(qbe.scopes[len(qbe.scopes) - 1]);
	qbe.scope = qbe.scopes[len(qbe.scopes) - 1];
};

fn qbe_scope_update_var(qbe: *Qbe, new_var: Qbe_Variable) void = {
	for (let i = 0z; i < len(qbe.scope.variables) - 1; i += 1) {
		const var = qbe.scope.variables[i];
		fmt::println(qbe_show_reg(var.reg), qbe_show_reg(new_var.reg))!;
		fmt::println(qbe_regs_are_equal(var.reg, new_var.reg))!;
		if (qbe_regs_are_equal(var.reg, new_var.reg)) {
			qbe.scope.variables[i] = new_var;
			return;
		};
	};
};

fn qbe_write_function(qbe: *Qbe, token: FunDefToken) void = {
	qbe_scope_push(qbe, token.name, Qbe_ScopeKind::FUN);

	if (token.name == "main") {
		qbe_write(qbe, "export function w $main() {")!;
	} else {
		qbe_write(qbe, format("function w ${}({}) {{", token.name, qbe_define_function_parameters(qbe, token.proc)))!;
	};

	qbe_write(qbe, "@start")!;
	qbe_write(qbe, format("@this"))!;
	qbe_set_indent(qbe, 4);
	qbe_write_block(qbe, token.body);
	qbe_set_indent(qbe, 0);
	qbe_write(qbe, "}")!;
	qbe_scope_pop(qbe);
};

fn qbe_write_block(qbe: *Qbe, token: BlockToken) void = {
	for (const token .. token.tokens) {
		if (token is ReservedKeywordToken) {
			switch (token as ReservedKeywordToken) {
			case ReservedKeywordToken::RETURN => 
				qbe_write(qbe, "ret 0")!;
			};
		};
		if (token is FuncallToken) {
			qbe_write_funcall(qbe, token as FuncallToken);
		} else if (token is VariableToken) {
			qbe_write_variable(qbe, token as VariableToken);
		} else if (token is IfToken) {
			fmt::println("if token")!;
			qbe_write_if(qbe, token as IfToken);
		};
	};

	// if (qbe.scope.kind == Qbe_ScopeKind::FUN) {
	// 	qbe_write(qbe, "@end")!;
	// };
};

fn qbe_write_datum(qbe: *Qbe, datum: Qbe_Variable) void = {
	if (!datum.is_emitted) {
		// Prepend for data strings, append for all else
		if (datum.reg.kind == Qbe_IdentifierKind::DATA && datum.text is str) {
			qbe_write_noindent(qbe, datum.text as str, Qbe_WritePositionKind::PREPEND)!;
		} else {
			qbe_write_noindent(qbe, datum.text as str, Qbe_WritePositionKind::APPEND)!;
		};
		datum.is_emitted = true;
	};
	qbe_scope_update_var(qbe, datum);
};

fn qbe_write_if(qbe: *Qbe, token: IfToken) void = {
	const expr1alloc = qbe_define_datum(qbe, token.expr1);
	const expr2alloc = qbe_define_datum(qbe, token.expr2);
	qbe_write(qbe, "# if's datums")!;
	qbe_write_datum(qbe, expr1alloc);
	qbe_write_datum(qbe, expr2alloc);
	qbe_write(qbe, "# end")!;
	switch (token.cmp) {
	case "==" =>
		let cmpreg1: Qbe_Identifier = @undefined;
		let cmpreg2: Qbe_Identifier = @undefined;

		if (expr1alloc.kind != expr2alloc.kind) {
			fmt::fatal("TYPE_ERROR: cannot compare different data types");
		};

		// Guaranteed to be same after ^
		const data_kind = expr1alloc.kind;

		switch (data_kind) {
		case Qbe_VariableDataKind::STR =>
		 	cmpreg1 = expr1alloc.reg;
		 	cmpreg2 = expr2alloc.reg;
		 	qbe_write(qbe, format("%eql  =l call $strcmp(l {}, l {})", qbe_show_reg(cmpreg1), qbe_show_reg(cmpreg2)))!;
		case Qbe_VariableDataKind::INT =>
		 	cmpreg1 = expr1alloc.reg;
		 	cmpreg2 = expr2alloc.reg;
			qbe_write(qbe, format("%eql =l ceql {}, {}", qbe_show_reg(cmpreg1), qbe_show_reg(cmpreg2)))!;
		};
	case =>
		unimplemented("1611");
	};
	qbe_write(qbe, format("jnz %eql, @ifstart, @ifend"))!;
	qbe_write_noindent(qbe, "@ifstart")!;
	qbe_scope_push(qbe, "if", Qbe_ScopeKind::IF);
	qbe_write_block(qbe, token.body);
	qbe_scope_pop(qbe);
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
	tokenizer_parse_buffer(&globalTokenizer);

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
