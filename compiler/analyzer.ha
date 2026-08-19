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

type ValueType = enum {
	INT,
	STR,
	NONE
};

type Identifier = struct {
	name: str
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

type Value = struct {
	value: str,
	value_type: ValueType
};

type Variable = struct {
	name: *Identifier,
	value: *Value
};

type ValueLike = (Value | Variable);

type Function = struct {
	name: *Identifier,
	parameters: []*FunctionParameter,
	body: AST,
	return_type: ValueType
};

fn create_function(name: str, parameters: []*FunctionParameter, body: AST, return_type: ValueType) *Function = {
	return alloc(Function {
		name = create_identifier(name),
		parameters = parameters, body = body, return_type = return_type
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
	return alloc([]: []ASTNode, 1024)!;
};

fn ast_push(tree: *AST, node: ASTNode) void = {
	append(tree, node)!;
};

fn expressionkind_to_valuetype(kind: ExpressionKind) {
	switch (kind) {
	case ExpressionKind::INT => return ValueType::INT;
	case ExpressionKind::STR => return ValueType::STR;
	};
};

fn analyze(tokenizer: *Tokenizer) void = {
	const ast = ast_new();

	// Analyze only fun def tokens first
	for (const token .. tokenizer.tokens) {
		match (token) {
		case let fun: *FunDefToken =>
			const function = create_function(fun.name, [], [], ValueType::INT);
			ast_push(&ast, function);
		};
	};

	for (const node .. ast) {
		match (node) {
		case let x: *Function => fmt::println("here we go", x.name.name)!;
		case => pass();
		};
	};
};
