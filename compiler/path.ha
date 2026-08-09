use path;
use fmt;
use strings;

fn trimext(path: *path::buffer) str = {
	const filepath_str = path::peek(path);
	const (filename, extension) = strings::rcut(filepath_str as str, ".");
	return filename;
};

fn decide_real_output_file_path(input_file_path: path::buffer, output_file_path_flag: (str | void)) path::buffer = {
	let result_path = path::init()!;
	match (output_file_path_flag) {
	case let p: str =>
		path::push(&result_path, p)!;
	case void => 
		const filename_with_ext = path::peek(&input_file_path) as str;
		const (filepath_without_ext, _) = strings::rcut(filename_with_ext, ".");

		path::push(&result_path, "./")!;
		path::push(&result_path, filepath_without_ext)!;
	};
	return result_path;
};

fn ensure_ext(file_path: path::buffer, ext: str) void = {
	const extension = path::peek_ext(&file_path);
	if (extension is void || (extension is str && (extension as str) != ext)) {
		fmt::println("Incorrect input file extension. Expecting '.nup'.\n")!;
		usage(1);
	};
};

type FilePathData = struct {
	input_file_path: *path::buffer,
	input_file_path_str: str,
	output_file_path: *path::buffer,
	output_file_path_str: str,
	intermediary_output_file_path: str,
};

fn compute_required_filepaths(input_file_path_str: str, output_file_path_flag: (str | void)) FilePathData = {
	const input_file_path = path::init(input_file_path_str)!;
	ensure_ext(input_file_path, "nup"); // ext needs to be .nup

	// Compute real output file path
	const output_file_path = decide_real_output_file_path(input_file_path, output_file_path_flag);
	const output_file_path_str = strings::dup(path::string(&output_file_path))!;

	// Compute intermediary paths
	const intermediary_output_file_path = strings::concat(output_file_path_str, ".ssa")!;

	return FilePathData {
		input_file_path = &input_file_path,
		input_file_path_str = input_file_path_str,
		output_file_path = &output_file_path,
		output_file_path_str = output_file_path_str,
		intermediary_output_file_path = intermediary_output_file_path
	};
};
