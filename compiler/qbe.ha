
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

let ifi = 0;
let whilei = 0;

fn clone_qbe_variable(variable: Qbe_Variable) Qbe_Variable = {
	const var = Qbe_Variable {
		reg = clone_qbe_reg(variable.reg),
		src_variable= if (variable.src_variable is str) strings::dup(variable.src_variable as str)! else void,
		value = clone_expression(variable.value),
		kind= variable.kind,
		text= if (variable.text is str) strings::dup(variable.text as str)! else void,
		is_emitted= variable.is_emitted
	};
	return var;
};

fn clone_qbe_reg(reg: Qbe_Identifier) Qbe_Identifier = {
	const reg = Qbe_Identifier {
		reg = strings::dup(reg.reg)!,
		kind = reg.kind,
		index = reg.index
	};
	return reg;
};

type Qbe_Identifier = struct {
	reg: str,
	kind: Qbe_IdentifierKind,
	index: (int | void)
};

type Qbe_Variable = struct {
	reg: Qbe_Identifier,
	src_variable: (str | void),
	value: (*Expression | void),
	kind: ExpressionKind,
	text: (str | void),
	is_emitted: bool
};

type Qbe_Literal = struct {
	kind: ExpressionKind,
	text: str,
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

fn get_datum_kind(datum: (Qbe_Variable | Qbe_Literal)) ExpressionKind = {
	return match (datum) {
	case let variable: Qbe_Variable => yield variable.kind;
	case let literal: Qbe_Literal => yield literal.kind;
	};
};

fn get_datum_text(datum: (Qbe_Variable | Qbe_Literal)) (str | void) = {
	return match (datum) {
	case let variable: Qbe_Variable => yield variable.text;
	case let literal: Qbe_Literal => yield literal.text;
	};
};

fn get_variable_reg(qbe: *Qbe, variable_identifier: str) Qbe_Identifier = {
	const scope = qbe.scope;
	if (len(scope.variables) == 0) fmt::fatal("Could not find reg");
	for (let i: size = len(scope.variables) - 1; i >= 0; i -= 1 ) {
		// found variable
		const variable = scope.variables[i];
		if (variable.src_variable is str && (variable.src_variable as str) == variable_identifier) {
			return variable.reg;
		};
	};
	fmt::fatal("Could not find reg");
};

const registers: []str = ["%a", "%b", "%c", "%d", "%e", "%f", "%g", "%h", "%i", "%j", "%k", "%l", "%m", "%n", "%o", "%p", "%q", "%r", "%s", "%t", "%u", "%v", "%w", "%x", "%y", "%z", "%aa", "%bb", "%cc", "%dd", "%ee", "%ff", "%gg", "%hh", "%ii", "%jj"];
const datums: []str = ["$a", "$b", "$c", "$d", "$e", "$f", "$g", "$h", "$i", "$j", "$k", "$l", "$m", "$n", "$o", "$p", "$q", "$r", "$s", "$t", "$u", "$v", "$w", "$x", "$y", "$z"];

type Qbe_Integer = struct {
	reg: Qbe_Identifier,
	data: []u8,
	text: str
};

type Qbe_Blit = struct {
	reg: Qbe_Identifier,
	text: str
};

type Qbe_VariableDataKind = ExpressionKind;
type Qbe_IdentifierKind = enum {
	REG,
	DATA
};

type Qbe_WritePositionKind = enum {
	PREPEND,
	APPEND
};

type Qbe = struct {
	write_seq: ([]str | void),
	indent_level: size,
	context: str,
	buffer: []str,
	scopes: []*Qbe_Scope,
	scope: *Qbe_Scope
};

type Qbe_WritePosition = (int | Qbe_WritePositionKind);

fn gen_id() str = {
	return uuid::encodestr(uuid::generate());
};

fn qbe_initialize(base_file_path: str) Qbe = {
	const base_contents = read_file_contents(base_file_path, false);
	const lines = strings::split(base_contents, "\n")!;

	const initial_scope = alloc(Qbe_Scope {
		id = "global",
		kind = Qbe_ScopeKind::GLOBAL,
		variables = []
	})!;

	const qbe = Qbe {
		write_seq = void,
		context = "",
		indent_level = 0,
		buffer = [],
		scopes = [],
		scope = initial_scope
	};

	// Set initial scope data
	append(qbe.scopes, initial_scope)!;

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

fn qbe_get_reg_label(is_array: bool = false, identifier: (str | void) = void) Qbe_Identifier = {
	let reg: str = @undefined;
	if (identifier is str) {
		if (is_array) {
			reg = format("%.A_{}", identifier as str);
			reg = ascii::strupper(reg)!;
		} else {
			reg = format("%{}", identifier as str);
		};
	} else {

		reg = registers[0];
		static delete(registers[0]);
		if (is_array) {
			reg = ascii::strupper(reg)!;
		};
	};

	return Qbe_Identifier {
		reg = reg,
		kind = Qbe_IdentifierKind::REG,
		index = if (is_array) 0 else void
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

fn qbe_write_seq_begin(qbe: *Qbe) void = {
	qbe.write_seq = [];
	return;
};

fn qbe_write_seq_finish(qbe: *Qbe, write_to_buffer: bool = true) str = {
	assert(qbe.write_seq is []str);

	const write_seq = qbe.write_seq as []str;
	for (const s .. write_seq) {
		fmt::println(s)!;
	};
	const write_seq_output = strings::dup(join(write_seq))!;
	fmt::println("seq out", write_seq_output)!;
	qbe.write_seq = void;

	if (write_to_buffer) qbe_write(qbe, write_seq_output)!;

	return write_seq_output;
};

fn qbe_write(qbe: *Qbe, s: str, position: Qbe_WritePosition = Qbe_WritePositionKind::APPEND) (void | nomem) = {
	const is_seq_in_progress = qbe.write_seq is []str;

	if (!strings::hassuffix(s, "\n") && !is_seq_in_progress) {
		s = strings::concat(s, "\n")!;
	};

	if (qbe.indent_level > 0 && !is_seq_in_progress) {
		s = strings::lpad(s, ' ', len(s) + qbe.indent_level)?;
	};

	if (is_seq_in_progress) {
		const write_seq = qbe.write_seq as []str;
		fmt::println("append to write seq: ", s)!;
		append(write_seq, s)!;
		qbe.write_seq = write_seq;
		fmt::println(len(qbe.write_seq: []str))!;
		fmt::println(len(write_seq: []str))!;
		return;
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
	const is_seq_in_progress = qbe.write_seq is []str;

	if (!strings::hassuffix(s, "\n") && !is_seq_in_progress) {
		s = strings::concat(s, "\n")!;
	};

	if (is_seq_in_progress) {
		const write_seq = qbe.write_seq as []str;
		fmt::println("append to write seq: ", s)!;
		append(write_seq, s)!;
		qbe.write_seq = write_seq;
		fmt::println(len(qbe.write_seq: []str))!;
		fmt::println(len(write_seq: []str))!;
		return;
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

fn qbe_compile(intermediary_file_path: str, output_file_path: str, remove_assembly_file: bool = true) (void | nomem | os::exec::error) = {
	const assembly_file_path = strings::concat(output_file_path, ".s")?;

	const cmd = exec::cmd("qbe", "-o", assembly_file_path, intermediary_file_path)?;
	const proc = exec::start(&cmd)?;
	const status = exec::wait(&proc)?;

	const cmd2 = exec::cmd("cc", "-o", output_file_path, assembly_file_path)?;
	const proc2 = exec::start(&cmd2)?;
	const status2 = exec::wait(&proc2)?;

	if (remove_assembly_file) {
		// remove .s file because it confuses hare's internal compiler
		os::remove(assembly_file_path)?;
	};
};

fn qbe_commit(qbe: Qbe, file: io::file) void = {
	const bytes: []u8 = [];
	for (const line .. qbe.buffer) {
		for (const byte .. strings::toutf8(line)) {
			append(bytes, byte)!;
		};
	};
	io::write(file, bytes)!;
};

fn qbe_define_literal_str(qbe: *Qbe, name: str, expression: *Expression, src_identifier: (str | void) = void) Qbe_Variable = {
	const found = qbe_globals_find_var_by_val(qbe, expression.value);

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
		src_variable = src_identifier,
		value = expression,
		text = result,
		is_emitted = false
	};

	qbe_add_global_data(qbe, var);

	return var;
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
	fmt::println("def alloc")!;
	const scope = qbe.scope;
	let out: []str = [];
	const reg = qbe_get_reg_label(true, data_identifier);
	append(out, format("{} =l call $malloc(w {})", qbe_show_reg(reg), figure_malloc_size(data_sz, data_kind)))!;
	if (data_sz > 1 && data_kind == Qbe_VariableDataKind::STR && !(data_identifier is void)) {
		append(out, format("storel {}, {}", data[0], qbe_show_reg(reg)))!;
		for (let i: size = 1; i < data_sz; i += 1) {
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
		value = alloc(Expression {
			kind = data_kind,
			value = data,
			value_size = data_sz
		})!,
		text = text,
		is_emitted = false
	};

	return var;
};

fn qbe_write_variable(qbe: *Qbe, token: VariableToken) void = {
	// const datum = match (token.value) {
	// 	case let expr: *Expression => yield qbe_define_datum(qbe, token.value);	
	// 	case let expr: *VariableExpression => yield qbe_define_datum(qbe, token.value, token.name);	
	// 	case let expr: *FunctionExpression => yield qbe_define_datum(qbe, token.value, token.name);	
	// };
	const datum = qbe_define_datum(qbe, token.value, token.name);
	const reg = qbe_get_reg_label(false, token.name);
	if (datum is Qbe_Literal) {
		(datum: Qbe_Literal).text = format("{} ={}", qbe_show_reg(reg), get_datum_text(datum));
	};
	const var = Qbe_Variable {
		reg = reg,
		kind = get_datum_kind(datum),
		src_variable = token.name,
		value = void,
		text = get_datum_text(datum),
		is_emitted = false
	};

	qbe_write_datum(qbe, datum);
};

fn qbe_define_datum(qbe: *Qbe, expr: AnyExpression, src_identifier: (str | void) = void) (Qbe_Variable | Qbe_Literal) = {
	match (expr) {
	case let expr: *Expression => 
		const value = expr.value;
		const value_size = expr.value_size;
		const kind = expr.kind;

		// "Weird" case first: is it a parameter?
		// if (value_size == -1) {
		// 	fmt::println("Value size is 1")!;
		// };

		// Easy case first: is it a literal integer?
		fmt::println(src_identifier)!;
		if (kind == VariableKind::INT) {
			const integer = qbe_define_literal_integer(qbe, value);
			return integer;
		};

		// Other easy case: is it literal string?
		if (kind == VariableKind::STR) {
			const data = qbe_define_literal_str(qbe, qbe_get_data_label(), expr, src_identifier);
			return data;
		};

		const allocation = qbe_define_allocation(qbe, value_size, value, kind, src_identifier);
		return allocation;
	case let expr: *FunctionExpression => 
		// fmt::println("triyng to find", src_identifier)!;
		// const reg = match (src_identifier) {
		// case let identifier: str => yield match(qbe_scope_find_var_by_src_var(qbe, identifier)) {
		// 	case let var: Qbe_Variable => yield var.reg;
		// 	case void => yield qbe_get_reg_label(false, src_identifier);
		// };
		// case void => yield qbe_get_reg_label(false, src_identifier);
		// };
		const reg = qbe_get_reg_label(false, src_identifier);
		qbe_write_seq_begin(qbe);
		fmt::println("eka", qbe.write_seq is []str)!;
		qbe_write(qbe, format("{} =l ", qbe_show_reg(reg)))!;
		fmt::println("toka", qbe.write_seq is []str)!;
		qbe_write_funcall(qbe, expr.name, expr.arguments);
		fmt::println("kolmas", qbe.write_seq is []str)!;
		const text = qbe_write_seq_finish(qbe, false);
		fmt::println("text that shi", text)!;
		const var = Qbe_Variable {
			reg = reg,
			src_variable = src_identifier,
			kind = ExpressionKind::INT,
			value = void,
			// must recursively expand args tho... since qbe doesn't
			// support inline calls
			text = text,
			is_emitted = false
		};

		return var;
	case let expr: *VariableExpression => 
		match (expr.reference) {
		// is parameter
		case let parameter: ParameterToken =>
			const reg = qbe_get_reg_label(false, src_identifier);
			const src_reg = qbe_get_reg_label(false, expr.name);
			const text = indent(format("{} =l copy {}", qbe_show_reg(reg), qbe_show_reg(src_reg)), qbe.indent_level);
			const new_var = Qbe_Variable {
				reg = reg,
				src_variable = src_identifier,
				value = void,
				kind = parameter.kind,
				text = text,
				is_emitted = false 
			};
			return new_var;
		case let expr: AnyExpression =>
			const result = qbe_define_datum(qbe, expr, src_identifier);
			fmt::println(expression_to_str(expr))!;
			fmt::println(get_datum_text(result))!;
			return result;
			// fmt::println(expression_to_str(expr))!;
			// const reg = qbe_get_reg_label(false, src_identifier);
			// const src_reg = qbe_get_reg_label(false);
			// const text = indent(format("{} =l copy {}", qbe_show_reg(reg), qbe_show_reg(src_reg)), qbe.indent_level);
			// const new_var = Qbe_Variable {
			// 	reg = reg,
			// 	src_variable = src_identifier,
			// 	value = expr.value,
			// 	kind = expr.kind,
			// 	text = text,
			// 	is_emitted = false 
			// };
			// return new_var;

		};
	case let expr: *ArrayExpression =>
		const reg = qbe_get_reg_label(true, src_identifier);

		const output: []str = [];
		
		const elem_count = ll_len(expr.values: *LinkedList);
		append(output, format("{} =l alloc8 {}", qbe_show_reg(reg), elem_count * 8))!;

		let node = ll_head(expr.values: *LinkedList);
		if (node != null) {
			const value = (node.value: *ExprTreeNode).value;
			// add first value
			append(output, format("storel {}, {}", expression_to_str(value), qbe_show_reg(reg)))!;
			node = node.next: *LinkedListNode;

			// fmt::println("Len of tree for arr expr:", ll_len(expr.values: *LinkedList))!;
			for (node != null) {
				const value = (node.value: *ExprTreeNode).value;
				const new_index = (reg.index as int) + 1;
				const og_reg_text = qbe_show_reg(reg);
				reg.index = new_index;
				const new_reg_text = qbe_show_reg(reg);
				append(output, format("{} =l add {}, 8", new_reg_text, og_reg_text))!;
				append(output, format("storel {}, {}", expression_to_str(value), qbe_show_reg(reg)))!;

				node = node.next: *LinkedListNode;
			};

			// add null pointer
			const next_reg = clone_qbe_reg(reg);
			next_reg.index = (next_reg.index as int) + 1;
			append(output, format("{} =l add {}, 8",  qbe_show_reg(next_reg), qbe_show_reg(reg)))!;
			append(output, format("storeb {}, {}", "0", qbe_show_reg(next_reg)))!;

			// reset index to array beginning
			reg.index = 0;

		};
		const text = join(output, "\n");

		const var = Qbe_Variable {
			reg = reg,
			src_variable = src_identifier,
			kind = ExpressionKind::INT,
			value = void,
			// must recursively expand args tho... since qbe doesn't
			// support inline calls
			text = text,
			is_emitted = false
		};

		return var;
		// for (node != null) {
		// 	const expr1 = (node as *IfCondNode).expr1;
		// 	const expr2 = (node as *IfCondNode).expr2;
		// 	const cmp = (node as *IfCondNode).cmp;
		// 	const expr1alloc = qbe_define_datum(qbe, expr1);
		// 	const expr2alloc = qbe_define_datum(qbe, expr2);
		// 	qbe_write(qbe, "# if's datums")!;
		// 	qbe_write_datum(qbe, expr1alloc);
		// 	qbe_write_datum(qbe, expr2alloc);
		// 	qbe_write(qbe, "# end")!;

		// 	let cmpreg1: Qbe_Identifier = @undefined;
		// 	let cmpreg2: Qbe_Identifier = @undefined;

		// 	if (expr1alloc.kind != expr2alloc.kind) {
		// 		fmt::fatal("TYPE_ERROR: cannot compare different data types");
	case => fmt::fatal("Incorrect expr type encountered while writing datum",);
	};
};

fn qbe_define_literal_integer(qbe: *Qbe, data: []u8) Qbe_Literal = {
	const text = format("l {}", strings::fromutf8_unsafe(data));

	return Qbe_Literal {
		text = text,
		kind = ExpressionKind::INT
	};
};

fn qbe_regs_are_equal(reg1: Qbe_Identifier, reg2: Qbe_Identifier) bool = {
	return qbe_show_reg(reg1) == qbe_show_reg(reg2);
};

fn qbe_scope_find_var_by_reg(qbe: *Qbe, reg_to_find: Qbe_Identifier) (Qbe_Variable | void)  = {
	for (const scope .. qbe.scopes) {
		if (len(scope.variables) < 1) continue;
		for (let i = len(scope.variables) - 1; i >= 0 && i < len(scope.variables); i -= 1) {
			const variable = scope.variables[i];
			if (qbe_regs_are_equal(variable.reg, reg_to_find)) {
				return variable;
			};
		};
	};

	return void;
};

fn qbe_globals_find_var_by_val(qbe: *Qbe, value_to_find: []u8) (Qbe_Variable | void)  = {
	for (const scope .. qbe.scopes) {
		if (len(scope.variables) < 1) continue;
		for (let i = len(scope.variables) - 1; i >= 0 && i < len(scope.variables); i -= 1) {
			const variable = scope.variables[i];
			if (variable.value is void) continue;
			const expr: *Expression = (variable.value as *Expression);
			const value = expr.value;
			const as_str = strings::fromutf8_unsafe(value); 
			if (as_str == "") continue;
			if (len(value) >= 0 && len(value_to_find) >= 0 && len(value) < len(value_to_find) || len(value) > len(value_to_find)) continue;
			let found = false;
			for (let i = 0z; i < len(value_to_find) - 1; i += 1) {
				if (value_to_find[i] != value[i]) {
					found = false;

				};
			};
			if (found) {
				return variable;
			};
		};
	};
	return void;
};

fn qbe_scope_find_var_by_src_var(qbe: *Qbe, src_var_to_find: str) (Qbe_Variable | void) = {
	for (const scope .. qbe.scopes) {
		if (len(scope.variables) < 1) continue;
		for (let i = len(scope.variables) - 1; i >= 0 && i < len(scope.variables); i -= 1) {
			const variable = scope.variables[i];
			fmt::println("iterated:", variable.src_variable, src_var_to_find)!;
			if (variable.src_variable is str && (variable.src_variable as str) == src_var_to_find) {
				return variable;
			};
		};
	};
	return void;
};

fn qbe_write_funcall(qbe: *Qbe, name: str, arguments: *ExprTree) void = {
	// handle recursive fun call
	// if (token.name == qbe.scope.id) {
	// 	qbe_write(qbe, "call $lol(l %b0)")!;
	// 	return;
	// };

	// No args
	if (ll_len(arguments: *LinkedList) == 0) {
		qbe_write(qbe, format("call ${}()\n", name))!;
		return;
	};

	const call_args: []str = [];
	if (arguments.head != null) {
		let node = ll_head(arguments: *LinkedList);
		for (node != null) {
			const value = (node.value: *ExprTreeNode).value;
			match (value) {
			case let arg: *Expression =>
				switch (arg.kind) {
				case ExpressionKind::INT =>
					// const integer = qbe_define_literal_integer(qbe, arg.value);
					append(call_args, format("l {}", expression_to_str(arg)))!;
				case ExpressionKind::STR =>
					const label = qbe_get_data_label();
					const data = qbe_define_literal_str(qbe, label, arg);
					qbe_write_noindent(qbe, (data.text as str), Qbe_WritePositionKind::PREPEND)!;
					append(call_args, format("l {}", data.reg.reg))!;
				};

			case let arg: *FunctionExpression => 
				const datum = qbe_define_datum(qbe, arg, arg.name);
				qbe_write_datum(qbe, datum);
				match (datum) {
				case let datum: Qbe_Variable => append(call_args, format("l {}", qbe_show_reg(datum.reg)))!;
				case => pass();
				};
				
			case let arg: *VariableExpression => 
				match (arg.reference) {
				case let expr: *ArrayExpression =>
					append(call_args, format("l %.A_{}0", ascii::strupper(arg.name)!))!;
				case =>
					append(call_args, format("l %{}", arg.name))!;
				};
			};

			if (node.next == null) break;
			node = node.next: *LinkedListNode;
		};
	};

	const result =  join(call_args, ", ");

	qbe_write(qbe, format("call ${}({})\n", name, result))!;
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
	};

	return join(out, ", ");
};

fn qbe_add_global_data(qbe: *Qbe, variable: Qbe_Variable) void = {
	const scope = qbe.scopes[0];
	append(scope.variables, clone_qbe_variable(variable))!;
};

fn qbe_write_function(qbe: *Qbe, token: FunDefToken) void = {
	const parameters = token.proc.parameters;

	// Write nested functions beforehand
	for (const token .. token.body.tokens[1..]) {
		match (token) {
		case let token: *FunDefToken =>
			fmt::println(token.name)!;
			qbe_write_function(qbe, *token);
		case => pass();
		};
		fmt::println(1)!;
	};

	if (token.name == "main") {
		qbe_write(qbe, "export function w $main() {")!;
	} else {
		qbe_write(qbe, format("function l ${}({}) {{", token.name, qbe_define_function_parameters(qbe, *token.proc)))!;
	};

	qbe_write(qbe, "@start")!;
	qbe_set_indent(qbe, 4);
	qbe_write_block(qbe, *token.body);
	qbe_set_indent(qbe, 0);
	qbe_write(qbe, "}")!;
};

fn qbe_write_block(qbe: *Qbe, token: BlockToken) void = {
	for (const token .. token.tokens[1..]) {
		match (token) { 
		case let token: *ReturnToken =>
			const value = token.value;
			match (value) {
			case let expr: *Expression => qbe_write(qbe, format("ret {}", expression_to_str(expr)))!;
			case let expr: *VariableExpression => qbe_write(qbe, format("ret %{}", expr.name))!;
			case let expr: *FunctionExpression => 
				const datum = qbe_define_datum(qbe, value);
				const result = qbe_write_datum(qbe, datum);
				qbe_write(qbe, format("ret {}", result))!;
			};
		case let token: *FuncallToken =>
			qbe_write_funcall(qbe, token.name, token.arguments);
		case let token: *VariableToken =>
			qbe_write_variable(qbe, *token);
		case let token: *IfToken =>
			qbe_write_if(qbe, *token);
		case let token: *LabelToken =>
			qbe_write(qbe, format("@{}", token.name))!;
		case let token: *WhileToken =>
			qbe_write_while(qbe, *token);
		case let token: *GoToken =>
			qbe_write(qbe, format("jmp @{}", token.label))!;
		};
	};

	// if (qbe.scope.kind == Qbe_ScopeKind::FUN) {
	// 	qbe_write(qbe, "@end")!;
	// };
};

fn qbe_write_datum(qbe: *Qbe, datum: (Qbe_Variable | Qbe_Literal), do_copy: bool = true) str = {
	match (datum) {
	case let d: Qbe_Literal => fmt::println("lit")!;
	case let d: Qbe_Variable => fmt::println("var")!;
	};
	// Handle literals
	if (datum is Qbe_Literal) {
		const literal = datum as Qbe_Literal;
		if (do_copy == true) {
			qbe_write_noindent(qbe, strings::replace(literal.text, "=l ", "=l copy ")!, Qbe_WritePositionKind::APPEND)!;
			return format("copy {}", strings::sub(literal.text, 2));
		} else {
			qbe_write_noindent(qbe, literal.text, Qbe_WritePositionKind::APPEND)!;
			return format("{}", strings::sub(literal.text, 2));
		};
	};

	const datum = datum as Qbe_Variable;
	// Handle full-blown datums
	if (!datum.is_emitted && datum.text is str) {
		// Prepend for data strings, append for all else
		if (datum.reg.kind == Qbe_IdentifierKind::DATA) {
			qbe_write_noindent(qbe, datum.text as str, Qbe_WritePositionKind::PREPEND)!;
		} else {
			qbe_write_noindent(qbe, datum.text as str, Qbe_WritePositionKind::APPEND)!;
		};

		return qbe_show_reg(datum.reg);
	};


	return datum.text as str;
};

fn qbe_write_while(qbe: *Qbe, token: IfToken) void = {
	let node = ll_value(ll_first(token.tree: *LinkedList): *LinkedListNode): nullable *IfCondNode;
	for (node != null) {
		const expr1 = (node as *IfCondNode).expr1;
		const expr2 = (node as *IfCondNode).expr2;
		const cmp = (node as *IfCondNode).cmp;
		fmt::println("tf?", expression_to_str(expr1))!;
		fmt::println("tf2?", expression_to_str(expr2))!;
		qbe_write(qbe, "# while's datums")!;
		const expr1alloc = qbe_define_datum(qbe, expr1);
		const expr2alloc = qbe_define_datum(qbe, expr2);
		const cmp1text = qbe_write_datum(qbe, expr1alloc, false);
		const cmp2text = qbe_write_datum(qbe, expr2alloc, false);

		if (get_datum_kind(expr1alloc) != get_datum_kind(expr2alloc)) {
			fmt::fatal("TYPE_ERROR: cannot compare different data types");
		};

		// Guaranteed to be same after ^
		const data_kind = get_datum_kind(expr1alloc);

		const curr_whilei = whilei;
		whilei += 1;
		qbe_write_noindent(qbe, format("@while{}", curr_whilei))!;
		switch (cmp) {
		case "==" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR =>
				qbe_write(qbe, format("%eql  =l call $strcmp(l {}, l {})", cmp1text, cmp2text))!;
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l ceql {}, {}", cmp1text, cmp2text))!;
			};
		case "!=" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR =>
				qbe_write(qbe, format("%eql =l call $strcmp(l {}, l {})", cmp1text, cmp2text))!;
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l cnel {}, {}", cmp1text, cmp2text))!;
			};
		case "<" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by LT", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l cslel {}, {}", cmp1text, cmp2text))!;
			};
		case "<=" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by LTE", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l csltl {}, {}", cmp1text, cmp2text))!;
			};
		case ">" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by GT", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l csgel {}, {}", cmp1text, cmp2text))!;
			};
		case ">=" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by GTE", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l csgtl {}, {}", cmp1text, cmp2text))!;
			};
		case => panic(format("Unsupported operator: {}", cmp))!;
		};
		qbe_write_block(qbe, *token.body);
		qbe_write(qbe, format("jnz %eql, @while{}, @endwhile{}", curr_whilei, curr_whilei))!;
		qbe_write_noindent(qbe, format("@endwhile{}", curr_whilei))!;
		node = (node as *IfCondNode).next;
	};
};

fn qbe_write_if(qbe: *Qbe, token: IfToken) void = {
	let node = ll_value(ll_first(token.tree: *LinkedList): *LinkedListNode): nullable *IfCondNode;
	for (node != null) {
		const expr1 = (node as *IfCondNode).expr1;
		const expr2 = (node as *IfCondNode).expr2;
		const cmp = (node as *IfCondNode).cmp;
		const expr1alloc = qbe_define_datum(qbe, expr1);
		const expr2alloc = qbe_define_datum(qbe, expr2);
		qbe_write(qbe, "# if's datums")!;
		const cmp1text = qbe_write_datum(qbe, expr1alloc, false);
		const cmp2text = qbe_write_datum(qbe, expr2alloc, false);
		qbe_write(qbe, "# end")!;

		if (get_datum_kind(expr1alloc) != get_datum_kind(expr2alloc)) {
			fmt::fatal("TYPE_ERROR: cannot compare different data types");
		};

		// Guaranteed to be same after ^
		const data_kind = get_datum_kind(expr1alloc);

		switch (cmp) {
		case "==" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR =>
				qbe_write(qbe, format("%eql  =l call $strcmp(l {}, l {})", cmp1text, cmp2text))!;
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l ceql {}, {}", cmp1text, cmp2text))!;
			};
		case "!=" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR =>
				qbe_write(qbe, format("%eql =l call $strcmp(l {}, l {})", cmp1text, cmp2text))!;
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l cnel {}, {}", cmp1text, cmp2text))!;
			};
		case "<" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by LT", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l cslel {}, {}", cmp1text, cmp2text))!;
			};
		case "<=" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by LTE", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l csltl {}, {}", cmp1text, cmp2text))!;
			};
		case ">" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by GT", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l csgel {}, {}", cmp1text, cmp2text))!;
			};
		case ">=" =>
			switch (data_kind) {
			case Qbe_VariableDataKind::STR => fmt::fatalf("line {}: Cannot compare strings by GTE", linenum());
			case Qbe_VariableDataKind::INT =>
				qbe_write(qbe, format("%eql =l csgtl {}, {}", cmp1text, cmp2text))!;
			};
		case => panic(format("Unsupported operator: {}", cmp))!;
		};
		const curr_ifi = ifi;
		ifi += 1;
		qbe_write(qbe, format("jnz %eql, @if{}t, @if{}f", curr_ifi, curr_ifi))!;
		qbe_write_noindent(qbe, format("@if{}t", curr_ifi))!;
		fmt::println(display_token_tree((*token.body).tokens))!;
		qbe_write_block(qbe, *token.body);
		qbe_write_noindent(qbe, format("@if{}f", curr_ifi))!;
		node = (node as *IfCondNode).next;
	};


};

