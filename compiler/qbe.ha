
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

fn clone_qbe_variable(variable: Qbe_Variable) Qbe_Variable = {
	const var = Qbe_Variable {
		reg = Qbe_Identifier {
			reg= strings::dup(variable.reg.reg)!,
			kind= variable.reg.kind,
			index= variable.reg.index
		},
		src_variable= if (variable.src_variable is str) strings::dup(variable.src_variable as str)! else void,
		value = clone_expression(variable.value),
		kind= variable.kind,
		text= if (variable.text is str) strings::dup(variable.text as str)! else void,
		is_emitted= variable.is_emitted
	};
	return var;
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

const registers: []str = ["%a", "%b", "%c", "%d", "%e", "%f", "%g", "%h", "%i", "%j", "%k", "%l", "%m", "%n", "%o", "%p", "%q", "%r", "%s", "%t", "%u", "%v", "%w", "%x", "%y", "%z"];
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

fn qbe_define_variable(qbe: *Qbe, token: VariableToken) str = {
	const datum = qbe_define_datum(qbe, token.value, token.name);
	qbe_write_datum(qbe, datum);
	return "";
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

fn qbe_define_funcall_args(qbe: *Qbe, arguments: *ExprTree) str = {
	const call_args: []str = [];
	if (arguments.head != null) {
		let node = ll_head(arguments: *LinkedList);
		for (node != null) {
			const value = (node.value: *ExprTreeNode).value;
			match (value) {
			case let arg: *Expression =>
				switch (arg.kind) {
				case ExpressionKind::INT =>
					const integer = qbe_define_literal_integer(qbe, arg.value);
					qbe_write(qbe, (integer.text as str))!;
					append(call_args, format("l {}", qbe_show_reg(integer.reg)))!;
				case ExpressionKind::STR =>
					const label = qbe_get_data_label();
					const data = qbe_define_literal_str(qbe, label, arg);
					qbe_write_noindent(qbe, (data.text as str), Qbe_WritePositionKind::PREPEND)!;
					append(call_args, format("l {}", data.reg.reg))!;
				};

			case let arg: *FunctionExpression => unimplemented("FUNCTION EXPR NOT IMPLEMENTED");
			case let arg: *VariableExpression => 
				const result = qbe_scope_find_var_by_src_var(qbe, arg.name);
				match (result) {
				case let var: Qbe_Variable => append(call_args, format("l {}", qbe_show_reg(var.reg)))!;
				case void => fmt::fatal("Could not find variable");
				};
			};

			if (node.next == null) break;
			node = node.next: *LinkedListNode;
		};
	};

	const result =  join(call_args, ", ");
	return result;
};

fn qbe_define_funcall(qbe: *Qbe, token: FuncallToken) str = {
	let text: str = @undefined;

	// handle recursive fun call
	if (token.name == qbe.scope.id) {
		unimplemented("Recursive call");
	};

	// No args
	if (ll_len(token.arguments: *LinkedList) == 0) {
		text = format("call ${}()\n", token.name);
		return text;
	};

	const arguments = qbe_define_funcall_args(qbe, token.arguments);

	text = format("call ${}({})\n", token.name, arguments);
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
	const scope = qbe.scope;
	let out: []str = [];
	const reg = qbe_get_reg_label(true);
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

	qbe_scope_add_variable(qbe, var);

	return var;
};

fn qbe_write_variable(qbe: *Qbe, token: VariableToken) void = {
	const datum = qbe_define_datum(qbe, token.value, token.name);
	qbe_write_datum(qbe, datum);
};

fn qbe_define_datum(qbe: *Qbe, expr: AnyExpression, src_identifier: (str | void) = void) Qbe_Variable = {
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
		if (kind == VariableKind::INT) {
			const integer = qbe_define_literal_integer(qbe, value, src_identifier);
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
		const reg = qbe_get_reg_label();
		const text = indent(format("{} =l call ${}({})", qbe_show_reg(reg), expr.name, qbe_define_funcall_args(qbe, expr.arguments)), qbe.indent_level);
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
		qbe_scope_add_variable(qbe, var);
		return var;
	case let expr: *VariableExpression => 
		const result = qbe_scope_find_var_by_src_var(qbe, expr.name);
		match (result) {
		case let var: Qbe_Variable => 
			const identifier = qbe_get_reg_label();
			const text = indent(format("{} =l copy {}", qbe_show_reg(identifier), qbe_show_reg(var.reg)), qbe.indent_level);
			const new_var = Qbe_Variable {
				reg = identifier,
				src_variable = src_identifier,
				value = var.value,
				kind = var.kind,
				text = text,
				is_emitted = false
			};
			qbe_scope_add_variable(qbe, new_var);
			return new_var;
		case void => fmt::fatal("COULD NOT FIND RESULT IN DEFINE DATUM");
		};
	case => fmt::fatal("Incorrect expr type encountered while writing datum",);
	};
};

fn qbe_define_literal_integer(qbe: *Qbe, data: []u8, src_identifier: (str | void) = void) Qbe_Variable = {
	const reg = qbe_get_reg_label();
	const text = format("{} =l copy {}\n", qbe_show_reg(reg), strings::fromutf8_unsafe(data));

	const var = Qbe_Variable {
		reg = reg,
		src_variable = src_identifier,
		kind = ExpressionKind::INT,
		value = alloc(Expression {
			value = data,
			value_size = 8,
			kind = ExpressionKind::INT,
		})!,
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
			if (variable.src_variable is str && (variable.src_variable as str) == src_var_to_find) {
				return variable;
			};
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
	if (ll_len(token.arguments: *LinkedList) == 0) {
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
	const scope = qbe.scopes[len(qbe.scopes) - 1];
	append(scope.variables, clone_qbe_variable(variable))!;
};

fn qbe_add_global_data(qbe: *Qbe, variable: Qbe_Variable) void = {
	const scope = qbe.scopes[0];
	append(scope.variables, clone_qbe_variable(variable))!;
};

fn qbe_scope_push(qbe: *Qbe, scope_id: str, scope_kind: Qbe_ScopeKind) void = {
	// TODO: push current scope items into new scope.
	// this means to treat the scope as a sort-of *stack*.
	
	const new_scope: *Qbe_Scope = alloc(Qbe_Scope {
		id = scope_id,
		kind = scope_kind,
		variables = []
	})!;

	append(qbe.scopes, new_scope)!;
	qbe.scope = new_scope;
};

fn qbe_scope_pop(qbe: *Qbe) void = {
	assert(len(qbe.scopes) > 1);
	delete(qbe.scopes[len(qbe.scopes) - 1]);
	qbe.scope = qbe.scopes[len(qbe.scopes) - 1];
};

fn qbe_scope_update_var(qbe: *Qbe, new_var: Qbe_Variable) void = {
	for (let i = 0z; i < len(qbe.scope.variables) - 1; i += 1) {
		const var = qbe.scope.variables[i];
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
		qbe_write(qbe, format("function w ${}({}) {{", token.name, qbe_define_function_parameters(qbe, *token.proc)))!;
	};

	qbe_write(qbe, "@start")!;
	qbe_write(qbe, format("@this"))!;
	qbe_set_indent(qbe, 4);
	qbe_write_block(qbe, *token.body);
	qbe_set_indent(qbe, 0);
	qbe_write(qbe, "}")!;
	qbe_scope_pop(qbe);
};

fn qbe_write_block(qbe: *Qbe, token: BlockToken) void = {
	for (const token .. token.tokens) {
		if (token is *ReturnToken) {
			const datum = qbe_define_datum(qbe, (token as *ReturnToken).value);
			qbe_write_datum(qbe, datum);
			qbe_write(qbe, format("ret {}", qbe_show_reg(datum.reg)))!;
		};
		if (token is *FuncallToken) {
			qbe_write_funcall(qbe, *(token as *FuncallToken));
		} else if (token is *VariableToken) {
			qbe_write_variable(qbe, *(token as *VariableToken));
		} else if (token is *IfToken) {
			qbe_write_if(qbe, *(token as *IfToken));
		};
	};

	// if (qbe.scope.kind == Qbe_ScopeKind::FUN) {
	// 	qbe_write(qbe, "@end")!;
	// };
};

fn qbe_write_datum(qbe: *Qbe, datum: Qbe_Variable) void = {
	if (!datum.is_emitted && datum.text is str) {
		// Prepend for data strings, append for all else
		if (datum.reg.kind == Qbe_IdentifierKind::DATA) {
			qbe_write_noindent(qbe, datum.text as str, Qbe_WritePositionKind::PREPEND)!;
		} else {
			qbe_write_noindent(qbe, datum.text as str, Qbe_WritePositionKind::APPEND)!;
		};
		datum.is_emitted = true;
	};
};

fn qbe_write_if(qbe: *Qbe, token: IfToken) void = {
	let node = token.tree.head;
	for (node != null) {
		const expr1 = (node as *IfCondNode).expr1;
		const expr2 = (node as *IfCondNode).expr2;
		const cmp = (node as *IfCondNode).cmp;
		const expr1alloc = qbe_define_datum(qbe, expr1);
		const expr2alloc = qbe_define_datum(qbe, expr2);
		qbe_write(qbe, "# if's datums")!;
		qbe_write_datum(qbe, expr1alloc);
		qbe_write_datum(qbe, expr2alloc);
		qbe_write(qbe, "# end")!;
		switch (cmp) {
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
		case "!=" =>
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
		case => unimplemented("GTE, LTE, GT, LT");
		};
		const curr_ifi = ifi;
		ifi += 1;
		qbe_write(qbe, format("jnz %eql, @if{}t, @if{}f", curr_ifi, curr_ifi))!;
		qbe_write_noindent(qbe, format("@if{}t", curr_ifi))!;
		qbe_scope_push(qbe, "if", Qbe_ScopeKind::IF);
		qbe_write_block(qbe, *token.body);
		qbe_scope_pop(qbe);
		qbe_write_noindent(qbe, format("@if{}f", curr_ifi))!;
		node = (node as *IfCondNode).next;
	};


};

