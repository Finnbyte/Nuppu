// Important conventions (may not yet be fully fulfilled):
// Strings in qbe MUST be uppercase and, when given as parameters, have 0 to signify being an array
//
// ExprTree = {
//     left: ExprTree | ExprNode
//     right: ExprTree | ExprNode
// }

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

const ALIGNMENT: size = 4;

const globalTokenizer: Tokenizer = @undefined;

fn itoa(num: (size | int)) str = {
	return format("{}", num);
};


fn pass() void = {
	return void;
};

fn unimplemented(msg: str = "TODO") never = {
	fmt::fatalf("NOT YET IMPLEMENTED: {}", msg);
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


type panicerror = !void;

fn panic(msg: str) (panicerror | void) = {
	fmt::println(msg)!;
	return panicerror;
};

// shorthand to fmt::asprintf that automatically crashes program if fails.
fn format(fmt: str, args: fmt::field...) str = {
	return strings::concat(fmt::asprintf(fmt, args...)!)!;
};

// shorthand to strings::join that automatically crashes program if fails.
fn join(strs: []str, delim: str = "") str = {
	return strings::join(delim, strs...)!;
};

export fn main() void = {
	const args = os::args[0..len(os::args)];
	const executable_name = shift_args(&args);
	const input_file = shift_args(&args);
	if (input_file is void) {
		os::exit(1);
	};

	// INFO: Example:
	// const tree = create_expr_tree();
	// const node = create_expr_node(alloc(Expression {
	// 	value = [65, 66, 67],
	// 	value_size = 8,
	// 	kind = ExpressionKind::INT
	// })!);
	// ll_push(tree: *LinkedList, node);
	// const value = (ll_head(tree: *LinkedList): *LinkedListNode).value;
	// const expr = value: *ExprTreeNode;
	// match (expr.value) {
	// case let x: *Expression => fmt::println(strings::fromutf8_unsafe(x.value))!;
	// };

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

	print_tokenizer_table(globalTokenizer);

	// Initialize qbe struct and prefill the buffer with base utilities and
	// functions
	const qbe = qbe_initialize("./base.qbe");

	for (const token .. globalTokenizer.tokens) {
		if (token is *FunDefToken) {
			qbe_write_function(&qbe, *(token as *FunDefToken));
		} else if (token is *VariableToken) {
			qbe_write_variable(&qbe, *(token as *VariableToken));
		} else {
			fmt::fatalf("Incompatible token in global scope at line {}: {}", linenum(), token_to_tokenkind(token));
		};
	};

	qbe_commit(qbe, intermediary_output_file);
	qbe_compile(intermediary_output_file_path, filename)!;

	if (enable_execute_flag) {
		fmt::println("\nOutput:")!;
		fmt::println(run_executable_and_capture_stdout(filename)!)!;
	};

};
