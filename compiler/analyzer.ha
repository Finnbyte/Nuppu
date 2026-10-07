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

type AnalyzerState = struct {
	variables: []*Variable,
	functions: []*Function
};

let analyzer_state = AnalyzerState {
	variables = [],
	functions = []
};

fn analyzer_variable_exists(name: str) nullable *Variable = {
	return null;
};

fn analyzer_function_exists(name: str) *Function = {
	for (const fun .. analyzer_state.functions) {
		if (fun.name.name == name) return fun;
	};
	fmt::fatal("Could not find function");
};

type ValueType = enum {
	INT,
	STR,
	NONE
};

type Identifier = struct {
	name: str
};

fn as_identifier(name: str) Identifier = {
	return Identifier {
		name = name
	};
};

fn create_identifier(name: str) *Identifier = {
	return alloc(Identifier {
		name = name
	})!;
};

type FunctionParameter = struct {
	name: *Identifier,
	value_type: ValueType
};

fn create_function_parameter(name: str, value_type: ValueType) *FunctionParameter = {
	return alloc(FunctionParameter {
		name = create_identifier(name),
		value_type = value_type
	})!;
};

type LiteralValue = struct {
	value: []u8,
	value_type: ValueType
};

type FunctionExpressionValue = struct {
	function: (*Function | *BuiltinFunction)
};

type ValueLike = (*LiteralValue | *Variable | *FunctionExpressionValue);

type Variable = struct {
	name: *Identifier,
	value: ValueLike
};

fn create_variable(name: str, value: ValueLike) *Variable = {
	return alloc(Variable {
		name = create_identifier(name),
		value = value
	})!;
};

type Function = struct {
	name: *Identifier,
	parameters: []*FunctionParameter,
	body: AST,
	return_type: ValueType,
	literal_return_value: (ValueLike | void)
};

type BuiltinFunction = struct {
	name: *Identifier
};

fn create_function(name: str, parameters: []*FunctionParameter, body: AST, return_type: ValueType) *Function = {
	return alloc(Function {
		name = create_identifier(name),
		parameters = parameters, 
		body = body, 
		return_type = return_type,
		literal_return_value = void
		
	})!;
};

type FunctionCall = struct {
	function: *Function,
	arguments: *ValueLike

};

// AST types
type ASTNode = (*Function | *Variable | *FunctionCall);
type AST = []ASTNode;

fn ast_new() AST = {
	return [];
};

fn ast_push(tree: *AST, node: ASTNode) void = {
	append(tree, node)!;
};

fn expressionkind_to_valuetype(kind: (ExpressionKind | NoneType)) ValueType = {
	if (kind is NoneType) return ValueType::NONE;
	switch (kind as ExpressionKind) {
	case ExpressionKind::INT => return ValueType::INT;
	case ExpressionKind::STR => return ValueType::STR;
	};
};

fn expression_to_valuelike(expression: AnyExpression) ValueLike = {
	match (expression) {
	case let expr: *Expression =>
		return alloc(LiteralValue {
			value = expr.value,
			value_type = expressionkind_to_valuetype(expr.kind)
		})!;
	case let expr: *VariableExpression =>
		const found_var = analyzer_variable_exists(expr.var as str);
		return found_var: *Variable;
	case let expr: *FunctionExpression =>
		if (strings::hasprefix(expr.name, "__")) {
			return alloc(FunctionExpressionValue {
				function = alloc(BuiltinFunction {
					name = create_identifier(expr.name)
				})!
			})!;
		};
		const found_fun = analyzer_function_exists(expr.name);
		assert(found_fun != null);
		return alloc(FunctionExpressionValue {
			function = found_fun
		})!;
	};
};

fn show_valuetype(value_type: ValueType) str = {
	return switch(value_type) {
	case ValueType::STR => yield "str";
	case ValueType::INT => yield "int";
	case ValueType::NONE => yield "none";
	};
};

fn analyze(tokens: []Token) AST = {
	const ast = ast_new();

	// Analyze only fun def tokens first
	display_token_tree(tokens);
	for (const token .. tokens) {
		match (token) {
		case let fun: *FunDefToken =>
			const function = create_function(fun.name, [], [], expressionkind_to_valuetype(fun.return_type));
			append(analyzer_state.functions, function)!;
			function.body = analyze(fun.body.tokens);
			ast_push(&ast, function);
		case let var: *VariableToken =>
			const value = expression_to_valuelike(var.value);
			const variable = create_variable(var.name, value);
			ast_push(&ast, variable);
		case let var: *ReturnToken =>
			fmt::println("Saw return token")!;
		case let var: *FuncallToken =>
			fmt::println("Saw funcall token")!;
		case let var: *LabelToken =>
			fmt::println("Saw label token")!;
		case let var: *IfToken =>
			fmt::println("Saw if token")!;
		case let var: *GoToken =>
			fmt::println("Saw go token")!;
		case => unimplemented(format("TOKEN: {}", token_to_tokenkind(token)));
		};
	};

	for (const node .. ast) {
		match (node) {
		case let x: *Function => fmt::println("here we go", x.name.name,  show_valuetype(x.return_type))!;
		case => pass();
		};
	};

	return ast;
};
