use fmt;
use errors;
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

const registers: []str = ["%a", "%b", "%c", "%d", "%e", "%f", "%g", "%h", "%i", "%j", "%k", "%l", "%m", "%n", "%o", "%p", "%q", "%r", "%s", "%t", "%u", "%v", "%w", "%x", "%y", "%z"];
const datums: []str = ["$a", "$b", "$c", "$d", "$e", "$f", "$g", "$h", "$i", "$j", "$k", "$l", "$m", "$n", "$o", "$p", "$q", "$r", "$s", "$t", "$u", "$v", "$w", "$x", "$y", "$z"];

type ExpressionKind = enum {
	INT,
	STR
};

type invalidexpression = !void;

type VariableKind = ExpressionKind;

type Expression = struct {
	kind: ExpressionKind,
	value: []u8,
	value_size: size
};

type FuncallToken = struct {
	name: str,
	// Argument's expression value
	value: Expression
};

type Token = (VariableToken | FuncallToken);

type VariableToken = struct {
	kind: VariableKind,
	name: str,
	value: Expression
};

type Tokenizer = struct {
	tokens: []Token,
	buffer: []rune
};

type Qbe_WritePositionKind = enum {
	PREPEND,
	APPEND
};

type Qbe = struct {
	buffer: []str
};

type Qbe_WritePosition = (int | Qbe_WritePositionKind);

fn qbe_get_reg_label() str = {
	const reg = registers[0];
	static delete(registers[0]);
	return reg;
};

fn qbe_get_data_label() str = {
	const datum = datums[0];
	static delete(datums[0]);
	return datum;
};



fn qbe_write(qbe: *Qbe, s: str, position: Qbe_WritePosition = Qbe_WritePositionKind::APPEND) (void | nomem) = {
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

fn qbe_writef(file: io::file, format: str, args: fmt::field...) (void | io::error) = {
	const s = fmt::asprintf(format, args...)!;
	io::write(file, strings::toutf8(s))!;
};

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

fn shift_args(args_pointer: *[]str) (str | void) = {
	if (len(*args_pointer) < 1) {
		return void;
	};
	const temp = args_pointer[0];
	static delete(args_pointer[0]);
	return temp;
};

export fn read_file_contents(file_path: str) str = {
	const file = os::open(file_path)!;
	const buf: []u8 = alloc([0...], 120)!;
	io::read(file, buf)!;
	return strings::fromutf8(buf)!;
};

fn init_tokenizer(raw_content: str) Tokenizer = {
	return Tokenizer {
		tokens = [],
		buffer = strings::torunes(raw_content)!
	};
};

fn next(tokenizer: *Tokenizer) void = {
	delete(tokenizer.buffer[0]);
};

fn next_expect(tokenizer: *Tokenizer, expected_ch: rune) void = {
	if (expected_ch != tokenizer.buffer[0]) {
		const actual_ch = tokenizer.buffer[0];
		fmt::printfln("Expected '{}', got '{}'", expected_ch, actual_ch)!;
	} else {
		delete(tokenizer.buffer[0]);
	};
};

fn next_till_whitespace(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0] != ' ' && tokenizer.buffer[0] != '\n') {
		const c: rune = tokenizer.buffer[0];
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_char(tokenizer: *Tokenizer, char: rune) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0] != char) {
		const c: rune = tokenizer.buffer[0];
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};



fn tokenizer_parse_funcall(tokenizer: *Tokenizer, func_name: str) void = {
	next_expect(tokenizer, ' ');

	const value = match (tokenizer_parse_expression(tokenizer)) {
	case let expression: Expression => 
		yield expression;
	case invalidexpression => 
		fmt::fatal("Invalid expression encountered");
	};

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
		const token = tokenizer.tokens[i];
		if (token is VariableToken) {
			fmt::println((token as VariableToken).name)!;
			if  ((token as VariableToken).name == variable_identifier) {
				return (token as VariableToken).value;
			};
		};
	};
	return void;
};

fn tokenizer_parse_expression(tokenizer: *Tokenizer) (Expression | invalidexpression) = {
	const raw_value = next_till_char(tokenizer, '\n');
	const raw_value_runes = strings::torunes(raw_value)!;

	// is it string literal?
	if (raw_value_runes[0] == '\"' || raw_value_runes[0] == '\'') {
		const runes_without_quotes = raw_value_runes[1..len(raw_value_runes)-1];
		const value = strings::toutf8(strings::fromrunes(runes_without_quotes)!);
		return Expression {
			kind = ExpressionKind::STR,
			value = value,
			value_size = len(value) * 8
		};
	};
	
	// is it variable or number?
	let is_valid_variable = ascii::isalpha(raw_value_runes[0]);
	if (is_valid_variable) {
		const identifier = raw_value;
		const identifier_value = tokenizer_find_variable_value(tokenizer, identifier);
		if (identifier_value is void) {
			fmt::fatal("Error parsing identifier");
		};
		return Expression {
			kind = (identifier_value as Expression).kind,
			value = (identifier_value as Expression).value,
			value_size = len((identifier_value as Expression).value) * 8
		};
	};

	return Expression {
		kind = ExpressionKind::STR,
		value = strings::toutf8(raw_value),
		value_size = len(raw_value) * 8
	};
};

fn tokenizer_parse_variable_declaration(tokenizer: *Tokenizer) void = {
	fmt::println("parse decl")!;

	next_expect(tokenizer, ' ');

	const identifier = next_till_whitespace(tokenizer);

	next_expect(tokenizer, ' ');
	next_expect(tokenizer, '=');
	next_expect(tokenizer, ' ');

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

fn tokenizer_parse_statement(tokenizer: *Tokenizer) void = {
	const keyword = next_till_whitespace(tokenizer);
	fmt::println("kw", keyword)!;

	if (keyword == "echo") {
		tokenizer_parse_funcall(tokenizer, keyword);
	} else if (keyword == "let") {
		tokenizer_parse_variable_declaration(tokenizer);
	} else {
		return;
	};

	next(tokenizer);
};

fn print_current_tokenizer_buffer(tokenizer: Tokenizer) void = {
	for (const ch .. tokenizer.buffer) {
		fmt::println(ch)!;
	};
};

fn print_tokenizer_tokenized_tokens(tokenizer: Tokenizer) void = {
	for (const token .. tokenizer.tokens) {
		fmt::printfln("")!;
	};
};

fn qbe_define_variable(token: VariableToken) str = {
	if (token.kind == VariableKind::INT) {
		for (const u .. token.value.value) {
			fmt::println(u)!;
		};
		const reg = qbe_get_reg_label();
		return strings::concat(
			fmt::asprintf("{} =w copy {}\n", reg, strings::fromutf8(token.value.value)!)!
		)!;
	};
	return "";
};
fn qbe_commit(qbe: Qbe, file: io::file) void = {
	for (const line .. qbe.buffer) {
		fmt::print(line)!;
	};
	const bytes: []u8 = [];
	for (const line .. qbe.buffer) {
		for (const byte .. strings::toutf8(line)) {
			append(bytes, byte)!;
		};
	};
	io::write(file, bytes)!;
};

fn qbe_define_data(data_label: str, data: str) str = {
	return fmt::asprintf("data {} = {}", data_label, data)!;
};

fn qbe_define_funcall(name: str, args: str) str = {
	return strings::concat("call ", name, "(", args, ")", "\n")!;
};

fn qbe_write_funcall(qbe: *Qbe, token: FuncallToken) void = {
	switch (token.name) {
	case "echo" =>
		const label = qbe_get_data_label();
		qbe_write(
			qbe, 
			qbe_define_data(label, fmt::asprintf("{{ b \"{}\\n\", b 0 }}\n", strings::fromutf8_unsafe(token.value.value))!), 
			Qbe_WritePositionKind::PREPEND)!;
		qbe_write(
			qbe, 
			qbe_define_funcall("$printf", strings::concat("l ", label)!))!;
	case => 
		return;

	};
};

export fn main() void = {
	const args = os::args[0..len(os::args)];
	const executable_name = shift_args(&args);
	const input_file = shift_args(&args);
	if (input_file is void) {
		fmt::println("No input file provided. Exiting")!;
		os::exit(1);
	};

	const (filename, extension) = strings::rcut(input_file as str, ".");
	if (extension != "nup") {
		fmt::println("Incorrect input file extension. Expecting '.nup'. Exiting")!;
	};

	const intermediary_output_file_path = strings::concat("./", filename, ".ssa")!;
	const intermediary_output_file = os::create(intermediary_output_file_path, fs::mode::USER_RW)!;

	const nup_file_contents = read_file_contents(input_file as str);

	const tokenizer = init_tokenizer(nup_file_contents);
	
	print_current_tokenizer_buffer(tokenizer);

	tokenizer_parse_statement(&tokenizer);
	tokenizer_parse_statement(&tokenizer);
	tokenizer_parse_statement(&tokenizer);
	tokenizer_parse_statement(&tokenizer);

	print_current_tokenizer_buffer(tokenizer);
	print_tokenizer_tokenized_tokens(tokenizer);

	const qbe = Qbe {
		buffer = [],
	};

	qbe_write(&qbe, "export function w $main() {\n")!;
	qbe_write(&qbe, "@start\n")!;

	for (const token .. tokenizer.tokens) {
		if (token is FuncallToken) {
			qbe_write_funcall(&qbe, token as FuncallToken);
		} else if (token is VariableToken) {
			qbe_write(&qbe, qbe_define_variable(token as VariableToken))!;
		};
	};
	qbe_write(&qbe, "ret 0\n")!;
	qbe_write(&qbe, "}\n")!;

	fmt::println(read_file_contents(intermediary_output_file_path))!;

	qbe_commit(qbe, intermediary_output_file);
	qbe_compile(intermediary_output_file_path, filename)!;

};
