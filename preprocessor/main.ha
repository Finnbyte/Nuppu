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

fn pass() void = {
	return void;
};

fn unimplemented(msg: str = "TODO") never = {
	fmt::fatalf("NOT YET IMPLEMENTED: {}", msg);
};

fn shift_args(args_pointer: *[]str) (str | void) = {
	if (len(*args_pointer) < 1) {
		return void;
	};
	const temp = args_pointer[0];
	static delete(args_pointer[0]);
	return temp;
};

export fn read_file_contents_str(file_path: (str | *path::buffer), include_null_terminator: bool = true) str = {
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

export fn read_file_contents(file_path: (str | *path::buffer), include_null_terminator: bool = true) []str = {
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
	return strings::split(strings::fromutf8(buf)!, "\n")!;
};



fn usage(exitCode: int = 0) never = {
	fmt::println("nuppupp - Preprocessor for .nup Nuppulang source files")!;
	fmt::println("usage: nuppupp <file path>")!;
	os::exit(exitCode);
};

fn spawn_error(msg: str) never = {
	fmt::println("error:", msg)!;
	os::exit(1);
};

export fn main() void = {
	const args = os::args[0..len(os::args)];
	const executable_name = shift_args(&args);

	const input_file_path_str = match (shift_args(&args)) {
	case let s: str => yield s;
	case void => 
		fmt::println("Missing input file.\n")!;
		usage(1);
	};

	let preprocessor_imports: []str = [];
	let preprocessor_lines = 0;

	// Read actual file contents of .nup source file
	const nup_file_contents = read_file_contents(input_file_path_str);

	for (strings::hasprefix(nup_file_contents[0], "#")) {
		const line = nup_file_contents[0];
		const tokenizer = strings::tokenize(line, " ");
		const keyword = strings::next_token(&tokenizer) as str;
		const value = strings::replace(strings::next_token(&tokenizer) as str, "\"", "")!;
		preprocessor_lines += 1;
		append(preprocessor_imports, value)!;

		// Remove line
		delete(nup_file_contents[0]);
	};

	// Nothing to do since no lines to preprocess, print current file contents
	if (preprocessor_lines < 1) {
		const result = strings::join("\n", nup_file_contents...)!;
		fmt::println(result)!;
		return;
	};

	for (const import .. preprocessor_imports) {
		let path: path::buffer = @undefined;
		const is_global = !strings::hasprefix(import, ".") && !path::abs(&path);

		if (is_global) {
			path = path::init("/usr/local/share/nuppu/", strings::concat(import, ".nup")!)!;
		} else {
			const og = path::init(input_file_path_str)!;
			path = path::init(path::dirname(input_file_path_str), import)!;
		};

		const imported_file_contents = read_file_contents_str(&path);
		insert(nup_file_contents[0], imported_file_contents)!;

	};

	const result = strings::join("\n", nup_file_contents...)!;
	fmt::println(result)!;
};

