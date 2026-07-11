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

fn qbe_write(file: io::file, s: str) (void | io::error) = {
	io::write(file, strings::toutf8(s))!;
};

fn qbe_compile(intermediary_file_path: str, output_executable_basename: str) (void | nomem | os::exec::error) = {
	const assembly_file_path = strings::concat(output_executable_basename, ".s")?;

	const cmd = exec::cmd("qbe", "-o", assembly_file_path, intermediary_file_path)?;
	const proc = exec::start(&cmd)?;
	const status = exec::wait(&proc)?;

	const cmd2 = exec::cmd("cc", "-o", output_executable_basename, assembly_file_path)?;
	const proc2 = exec::start(&cmd2)?;
	const status2 = exec::wait(&proc2)?;

	// remove .s file because it confuses hare's internal compiler
	os::remove(assembly_file_path)?;
};

fn shift_args(args_pointer: *[]str) (str | void) = {
	if (len(*args_pointer) < 1) {
		return void;
	};
	const temp = args_pointer[0];
	static delete(args_pointer[0]);
	return temp;
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

	qbe_write(intermediary_output_file, "data $fmt = { b \"res: %d\\n\", b 0 }\n")!;
	qbe_write(intermediary_output_file, "export function w $main() {\n")!;
	qbe_write(intermediary_output_file, "@start\n")!;
	qbe_write(intermediary_output_file, "%r =w add 1, 2\n")!;
	qbe_write(intermediary_output_file, "call $printf(l $fmt, w %r)\n")!;
	qbe_write(intermediary_output_file, "ret 0\n")!;
	qbe_write(intermediary_output_file, "}\n")!;

	qbe_compile(intermediary_output_file_path, filename)!;

};
