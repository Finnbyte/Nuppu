// Important conventions (may not yet be fully fulfilled):
// Strings in qbe MUST be uppercase and, when given as parameters, have 0 to signify being an array
//
// ExprTree = {
//     left: ExprTree | ExprNode
//     right: ExprTree | ExprNode
// }

use path;
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

const BASE_QBE_FILE_PATH = "/usr/local/share/nuppu/base.qbe";

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

export fn read_file_contents(file_path: (str | *path::buffer), include_null_terminator: bool = true) str = {
	const str_file_path = match (file_path) {
	case let s: str => yield s;
	case let p: *path::buffer => yield path::string(p);
	};
	const file = match(os::open(str_file_path)) {
	case let file: io::file => yield file;
	case let err: fs::error => spawn_error(fs::strerror(err));
	};
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

fn usage(exitCode: int = 0) never = {
	fmt::println("nuppuc - compiler for the Nuppu programming language")!;
	fmt::println("usage: nuppuc <file path>")!;
	os::exit(exitCode);
};

fn spawn_error(msg: str) never = {
	fmt::println("error:", msg)!;
	os::exit(1);
};

export fn main() void = {
	// INFO: Example for iterating expression tree:
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

	const args = os::args[0..len(os::args)];
	const executable_name = shift_args(&args);

	let output_file_path_flag: (str | void) = void;
	let input_file_path_str: str = @undefined;
	let input_file_path: path::buffer = @undefined;
	let enable_execute_flag: bool = false;
	let enable_debug_flag: bool = false;

	// Parse all other args except positional input file path
	for (len(args) > 1) {
		match (shift_args(&args)) {
		case let arg: str =>
			if (arg == "-h" || arg == "--help") usage();
			if (arg == "-x") enable_execute_flag = true;
			if (arg == "-d") enable_debug_flag = true;
			if (arg == "-o" || arg == "--output") {
				output_file_path_flag = match(shift_args(&args)) {
				case let s: str => yield s;
				case void =>
					fmt::println("Missing output file path from -o flag.\n")!;
					usage(1);

				};
			};
		case void =>
			yield void;
		};
	};

	input_file_path_str = match (shift_args(&args)) {
	case let s: str => yield s;
	case void => 
		fmt::println("Missing input file.\n")!;
		usage(1);
	};

	fmt::println("HALOO", input_file_path_str)!;
	const paths = compute_required_filepaths(input_file_path_str, output_file_path_flag);

	const intermediary_output_file = match (os::create(paths.intermediary_output_file_path, fs::mode::USER_RW)) {
	case let file: io::file => yield file;
	case let err: fs::error =>
		spawn_error(fs::strerror(err));
	};

	// Read actual file contents of .nup source file
	const nup_file_contents = read_file_contents(paths.input_file_path_str);

	// Lex the buffer, saving the lexed symbols into the Lexer
	const lexer = init_lexer(nup_file_contents);
	defer free(lexer);
	lexer_lex_buffer(lexer);

	// Initialize the tokenizer based on the lexer's accumulated output data buffer
	globalTokenizer = init_tokenizer(*lexer);

	// Parse globally
	tokenizer_parse_buffer(&globalTokenizer);

	if (enable_debug_flag) {
		// Show tokenizer table for debugging
		print_tokenizer_table(globalTokenizer);
	};

	// Initialize qbe struct and prefill the buffer with base utilities and functions
	const qbe = qbe_initialize(BASE_QBE_FILE_PATH);

	// Emit each token
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
	qbe_compile(
		paths.intermediary_output_file_path, 
		paths.output_file_path_str)!;

	if (enable_execute_flag) {
		fmt::println(run_executable_and_capture_stdout(paths.output_file_path_str)!)!;
	};

};
