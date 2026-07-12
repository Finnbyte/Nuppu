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

type VariableDeclarationToken = struct {
	name: str,
	value: str
};

type FuncallToken = struct {
	name: str,
	arg: str
};

type token = (VariableDeclarationToken | FuncallToken);

type tokenizer = struct {
	tokens: []token,
	buffer: []rune
};

fn qbe_write(file: io::file, s: str) (void | io::error) = {
	io::write(file, strings::toutf8(s))!;
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

fn init_tokenizer(raw_content: str) tokenizer  = {
	return tokenizer {
		tokens = [],
		buffer = strings::torunes(raw_content)!
	};
};

fn next(tokenizer: *tokenizer) void = {
	delete(tokenizer.buffer[0]);
};

fn next_expect(tokenizer: *tokenizer, expected_ch: rune) void = {
	if (expected_ch != tokenizer.buffer[0]) {
		const actual_ch = tokenizer.buffer[0];
		fmt::printfln("Expected '{}', got '{}'", expected_ch, actual_ch)!;
	} else {
		delete(tokenizer.buffer[0]);
	};
};

fn next_till_whitespace(tokenizer: *tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0] != ' ' && tokenizer.buffer[0] != '\n') {
		const c: rune = tokenizer.buffer[0];
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn tokenizer_parse_funcall(tokenizer: *tokenizer) void = {
	fmt::println("parse funcall")!;
	next(tokenizer);
};

fn tokenizer_parse_variable_declaration(tokenizer: *tokenizer) void = {
	fmt::println("parse decl")!;

	next_expect(tokenizer, ' ');

	const identifier = next_till_whitespace(tokenizer);

	next_expect(tokenizer, ' ');
	next_expect(tokenizer, '=');
	next_expect(tokenizer, ' ');

	const value = next_till_whitespace(tokenizer);

	append(tokenizer.tokens, VariableDeclarationToken {
		name = identifier,
		value = value
	})!;

	fmt::printfln("{}, {}", identifier, value)!;
};

fn tokenizer_parse_statement(tokenizer: *tokenizer) void = {
	const keyword = next_till_whitespace(tokenizer);

	if (keyword == "echo") {
		tokenizer_parse_funcall(tokenizer);
	} else if (keyword == "let") {
		tokenizer_parse_variable_declaration(tokenizer);
	};
};

fn print_current_tokenizer_buffer(tokenizer: tokenizer) void = {
	for (const ch .. tokenizer.buffer) {
		fmt::println(ch)!;
	};
};

fn print_tokenizer_tokenized_tokens(tokenizer: tokenizer) void = {
	for (const token .. tokenizer.tokens) {
		fmt::printfln("name: {}, value: {}", (token as VariableDeclarationToken).name, (token as VariableDeclarationToken).value)!;
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

	print_current_tokenizer_buffer(tokenizer);
	print_tokenizer_tokenized_tokens(tokenizer);

	qbe_write(intermediary_output_file, "data $fmt = { b \"%d\\n\", b 0 }\n")!;
	qbe_write(intermediary_output_file, "export function w $main() {\n")!;
	qbe_write(intermediary_output_file, "@start\n")!;

	for (const token .. tokenizer.tokens) {
		if (token is VariableDeclarationToken) {
			qbe_writef(intermediary_output_file, "%r =w copy {}\n", (token as VariableDeclarationToken).value)!;
			qbe_write(intermediary_output_file, "call $printf(l $fmt, w %r)\n")!;
		};
	};
	qbe_write(intermediary_output_file, "ret 0\n")!;
	qbe_write(intermediary_output_file, "}\n")!;

	fmt::println(read_file_contents(intermediary_output_file_path))!;

	qbe_compile(intermediary_output_file_path, filename)!;

};
