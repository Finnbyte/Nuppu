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

type PPImportToken = struct { 
	value: str
};

type ReturnToken = struct {
	value: AnyExpression
};

type FuncallToken = struct {
	name: str,
	arguments: *ExprTree,
};

type BlockToken = struct {
	kind: BlockKind,
	id: str,
	tokens: []Token
};

type LabelToken = struct {
	name: str
};

type GoToken = struct {
	label: str
};

type invalidexpression = !void;

type VariableKind = ExpressionKind;

type ParameterToken = struct {
	name: str,
	kind: ExpressionKind
};

type FunDefToken = struct {
	name: str,
	return_type: (ExpressionKind | NoneType),
	proc: *FunDefProcToken,
	body: *BlockToken
};

type FunDefProcToken = struct {
	name: str,
	parameters: []ParameterToken
};

type IfToken = struct {
	tree: *CondTree,
	body: *BlockToken
};

type Token = (*VariableToken | *FuncallToken | *IfToken | *FunDefToken | *ReturnToken | *LabelToken | *GoToken);

type VariableToken = struct {
	kind: VariableKind,
	name: str,
	value: AnyExpression
};

type Tokenizer = struct {
	block: (*BlockToken | void),
	tokens: []Token,
	buffer: []LexSymbol,
	linenum: int,
};

type BlockKind = enum {
	IF,
	FUN
};

type NoneType = void;

type ExpressionKind = enum {
	INT,
	STR
};

fn valid_integer(s: str) bool = {
	for (const ch .. strings::torunes(s)!) {
		if (!ascii::isdigit(ch)) return false;
	};
	return true;
};

fn expressionkind_to_str(kind: ExpressionKind) str = {
	return switch (kind) {
	case ExpressionKind::INT => yield "INT";
	case ExpressionKind::STR => yield "STR";
	};
};

fn expression_to_str(anyexpr: AnyExpression) str = {
	return match (anyexpr) {
	case let expr: *Expression =>
		yield switch (expr.kind) {
		case ExpressionKind::STR => yield format("\"{}\"", strings::fromutf8_unsafe(expr.value));
		case ExpressionKind::INT => yield strings::fromutf8_unsafe(expr.value);
		};
	case let expr: *VariableExpression => yield expr.name;
	case let expr: *FunctionExpression =>
		const args: []str = [];
		if (ll_empty(expr.arguments: *LinkedList)) yield "()";
		const node = ll_first(expr.arguments: *LinkedList);
		for (node != null) {
			const exprNode = (node: *LinkedListNode).value: *ExprTreeNode;
			append(args, expression_to_str(exprNode.value))!;
			node = (node: *LinkedListNode).next;
		};
		yield format("{}({})", expr.name, join(args, ", "));
	case => fmt::fatal("Unknown expression");
	};
};



fn init_tokenizer(lexer: Lexer) Tokenizer = {
	return Tokenizer {
		tokens = [],
		buffer = lexer.symbols,
		linenum = 1,
		block = void
	};
};

fn token_to_tokenkind(token: Token) str = {
	match (token) {
	case *VariableToken => return "VariableToken";
	case *IfToken => return "IfToken";
	case *FuncallToken => return "FuncallToken";
	case *FunDefToken => return "FunDefToken";
	case *ReturnToken => return "ReturnToken";
	case *LabelToken => return "LabelToken";
	case *GoToken => return "GoToken";
	};
};

fn clone_expression(expression: (*Expression | void)) (*Expression | void) = {
	match (expression) {
	case let expression: *Expression =>
		let value: []u8 = @undefined;
		if (expression.value_size <= 0) {
			const value: []u8 = alloc([], 0)!;
		} else {
			const value: []u8 = alloc([0...], expression.value_size)!;
			let idx = 0;
			if (expression.value_size > 0) {
				for (const byte .. expression.value) {
					value[idx] = byte;
					idx += 1;
				};
			};
		};

		return alloc(Expression {
			value = value,
			value_size = expression.value_size,
			kind = expression.kind
		})!;
	case void => return void;
	};

};

type ExprTreeNode = struct {
	value: AnyExpression,
	next: nullable *ExprTreeNode
};

type ExprTree = struct {
	head: nullable *ExprTreeNode
};

type Expression = struct {
	kind: ExpressionKind,
	value: []u8,
	value_size: size
};

type FunctionExpression = struct {
	name: str,
	var: (str | void),
	arguments: *ExprTree
};

type IfCondNode = struct {
	expr1: AnyExpression,
	expr2: AnyExpression,
	cmp: str,
	next: nullable *IfCondNode,
	next_type: nullable *str
};

type CondTree = struct {
	head: nullable *IfCondNode,
};

type VariableExpression = struct {
	name: str,
	var: (str | void)
};

type AnyExpression = (*Expression | *VariableExpression | *FunctionExpression);

fn peek_next(tokenizer: *Tokenizer) LexSymbol = {
	return tokenizer.buffer[0];
};

fn next(tokenizer: *Tokenizer) LexSymbol = {
	const symbol = tokenizer.buffer[0];
	delete(tokenizer.buffer[0]);
	return symbol;
};

fn initiate_block_token(kind: BlockKind, fun_name: (str | void) = void) *BlockToken = {
	let id: str = @undefined;

	if (kind == BlockKind::FUN) {
		assert(!(fun_name is void));
		id = fun_name as str;
	} else if (kind == BlockKind::IF) {
		id = gen_id();
	};

	return alloc(BlockToken {
		id = id,
		kind = kind,
		tokens = []
	})!;
};

fn init_blockwise_tokenizer(symbols: []LexSymbol, block: *BlockToken) Tokenizer = {
	const symbols_clone: []LexSymbol = [];
	for (const symbol .. symbols) {
		append(symbols_clone, symbol)!;
	};
	return Tokenizer {
		tokens = [],
		buffer = symbols_clone,
		linenum = 1,
		block = block
	};
};

fn tokenizer_parse_if_node(tokenizer: *Tokenizer) *IfCondNode = {
	let cmp: str = @undefined;
	let expr1: AnyExpression = @undefined;
	let expr2: AnyExpression = @undefined;

	expr1 = tokenizer_parse_expression(tokenizer);

	fmt::println("expr1", expression_to_str(expr1))!;
	fmt::println("next", peek_next(tokenizer).value)!;

	skip_empty(tokenizer);

	// Supports == and !=
	const kind_of_next = peek_next(tokenizer).kind;
	if (kind_of_next == LexKind::EQUALS) {
		next(tokenizer);
		next_expect(tokenizer, LexKind::EQUALS);
		fmt::println("this 1")!;
		cmp = "==";
	} else if (kind_of_next == LexKind::EXCLAMATION) {
		next(tokenizer);
		next_expect(tokenizer, LexKind::EQUALS);
		fmt::println("this 2")!;
		cmp = "!=";
	} else if (kind_of_next == LexKind::LESS) {
		next(tokenizer);
		switch (peek_next(tokenizer).kind) {
		case LexKind::EQUALS =>
			next(tokenizer);
			cmp = "<=";
		case => cmp = "<";
		};
	} else if (kind_of_next == LexKind::GREATER) {
		next(tokenizer);
		switch (peek_next(tokenizer).kind) {
		case LexKind::EQUALS =>
			next(tokenizer);
			cmp = ">=";
		case => cmp = ">";
		};
	};

	skip_empty(tokenizer);

	expr2 = tokenizer_parse_expression(tokenizer);

	fmt::println("expr2", expression_to_str(expr2))!;
	const node = alloc(IfCondNode {
		expr1 = expr1,
		expr2 = expr2,
		cmp = cmp,
		next = null,
		next_type = null
	})!;

	skip_empty(tokenizer);

	return node;
};

fn tokenizer_parse_if(tokenizer: *Tokenizer) void = {
	const tree = alloc(CondTree {
		head = null
	})!;

	// after "if"
	next_expect(tokenizer, LexKind::WHITESPACE);
	skip_empty(tokenizer);

	let keyword = "";
	for (keyword != "do") {
		fmt::printfln("kw '{}'", keyword)!;

		const node = tokenizer_parse_if_node(tokenizer);
		ll_push(tree: *LinkedList, node);

		skip_empty(tokenizer);

		keyword = next_till_nonchar(tokenizer);
		fmt::println("keyword", keyword)!;

		switch (keyword) {
		case "and" =>
			node.next_type = &"and";
			for (let i = 0; i < 2; i+=1) next(tokenizer);
			next_expect(tokenizer, LexKind::WHITESPACE);
		case "or" => 
			node.next_type = &"or";
			for (let i = 0; i < 1; i+=1) next(tokenizer);
			next_expect(tokenizer, LexKind::WHITESPACE);
		case "do" => break;
		case => 
			fmt::println("what is it", peek_next(tokenizer).value)!;
			if (peek_next(tokenizer).kind == LexKind::WHITESPACE) {
				skip_empty(tokenizer);
				fmt::println(peek_next(tokenizer).value)!;
			} else {
				next(tokenizer);
				fmt::println(peek_next(tokenizer).value)!;
			};
		};
	};

	fmt::println("hmm", expression_to_str(((tree.head: *LinkedListNode).value: *IfCondNode).expr1))!;

	const block = initiate_block_token(BlockKind::IF);
	const blockwise_tokenizer = init_blockwise_tokenizer(tokenizer.buffer, block);
	tokenizer_parse_block(&blockwise_tokenizer);
	block.tokens = blockwise_tokenizer.tokens;
	tokenizer.buffer = blockwise_tokenizer.buffer;

	append(tokenizer.tokens, alloc(IfToken {
		tree = tree,
		body = block
	})!)!;

	// Go ahead to avoid retokenizing from nested if tokenizer
	for (let i = 0z; i < 4; i+= 1) {
		next(tokenizer);
	};
};

fn tokenizer_parse_fun_parameters(tokenizer: *Tokenizer) []ParameterToken = {
	const parameters: []ParameterToken = alloc([], size(ParameterToken))!;

	const parameters_lst = strings::split(next_till_kind(tokenizer, LexKind::PAREN_CLOSE), ",")!;
	for (const param .. parameters_lst)  {
		const splitted_param = strings::split(param, ":")!;
		assert(len(splitted_param) == 2);
		const param_name = strings::trim(splitted_param[0]);
		const param_type = strings::trim(splitted_param[1]);

		const kind = switch (param_type) {
		case "int" => yield ExpressionKind::INT;
		case => yield ExpressionKind::STR;
		};

		append(parameters, ParameterToken {
			name = param_name,
			kind = kind
		})!;
	};
	return parameters;
};

// Skips `LexKind::WHITESPACE` characters in the tokenizer.
// Returns how many were skipped.
fn skip_empty(tokenizer: *Tokenizer) size = {
	let skip_count = 0z;
	for (peek_next(tokenizer).kind == LexKind::WHITESPACE) {
		next(tokenizer);
		skip_count += 1;
	};
	return skip_count;
};

fn tokenizer_parse_type(tokenizer: *Tokenizer) (ExpressionKind | NoneType) = {
	switch (next_till_nonchar(tokenizer)) {
	case "int" => return ExpressionKind::INT;
	case "str" => return ExpressionKind::STR;
	case "none" => return NoneType;
	case => fmt::fatalf("UNRECOGNIZED TYPE");
	};
};

fn tokenizer_parse_fun(tokenizer: *Tokenizer) void = {
	const fun_name = next_till_nonchar_or_nondigit(tokenizer);

	if (peek_next(tokenizer).kind == LexKind::WHITESPACE) next(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_OPEN);

	const parameters = tokenizer_parse_fun_parameters(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_CLOSE);

	skip_empty(tokenizer);

	if (peek_next(tokenizer).value != '-') {
		fmt::fatalf("TOKENIZER_ERROR: function \"{}\" is lacking a return type!", fun_name);
	};
	next(tokenizer);
	if (peek_next(tokenizer).value != '>') {
		fmt::fatalf("TOKENIZER_ERROR: function \"{}\" is lacking a return type!", fun_name);
	};
	next(tokenizer);
	skip_empty(tokenizer);

	const return_type = tokenizer_parse_type(tokenizer);
	next_expect(tokenizer, LexKind::WHITESPACE);

	next_expect_rune(tokenizer, 'i');
	next_expect_rune(tokenizer, 's');

	next_expect(tokenizer, LexKind::NEWLINE);
	incr_linenum();

	const block = initiate_block_token(BlockKind::FUN, fun_name);
	const blockwise_tokenizer = init_blockwise_tokenizer(tokenizer.buffer, block);

	const fundef_token = alloc(FunDefToken {
		name = fun_name,
		return_type = return_type,
		proc = alloc(FunDefProcToken {
			name = fun_name,
			parameters = parameters
		})!,
		body = block
	})!;

	append(blockwise_tokenizer.tokens, fundef_token)!;

	tokenizer_parse_block(&blockwise_tokenizer);

	block.tokens = blockwise_tokenizer.tokens;

	append(tokenizer.tokens, fundef_token)!;

	tokenizer.buffer = blockwise_tokenizer.buffer;

	// Go ahead to avoid retokenizing from nested if tokenizer
	for (let i = 0z; i < 4; i+= 1) {
		next(tokenizer);
	};
};

fn tokenizer_parse_buffer(tokenizer: *Tokenizer) void = {
	for (tokenizer_has_next_statement(*tokenizer)) {
		const keyword = next_till_nonchar(tokenizer);
		if (len(keyword) == 0) next(tokenizer);

		// only allow function definitions for now
		if (keyword == "fun") {
			skip_empty(tokenizer);
			tokenizer_parse_fun(tokenizer);
		};
	};
};

fn tokenizer_parse_variable_declaration_or_assign(tokenizer: *Tokenizer, identifier: str) void = {
	if (!tokenizer_is_valid_variable(identifier)) {
		fmt::fatalf("TOKENIZER_ERROR: invalid identifier name given: \"{}\"", identifier);
	};

	let explicit_value_type: (ExpressionKind | NoneType | void) = void;
	fmt::println(identifier)!;
	if (peek_next(tokenizer).kind == LexKind::COLON) {
		next(tokenizer);
		skip_empty(tokenizer);

		explicit_value_type = tokenizer_parse_type(tokenizer);
	};

	skip_empty(tokenizer);

	switch (peek_next(tokenizer).kind) {
	case LexKind::COLON => 
		next(tokenizer);
		next_expect(tokenizer, LexKind::EQUALS);
		skip_empty(tokenizer);

		const value = tokenizer_parse_expression(tokenizer);
		const value_type = match (explicit_value_type) {
		case let expr: ExpressionKind => yield expr;
		case void => yield find_return_type(tokenizer, value);
		};

		append(tokenizer.tokens, alloc(VariableToken {
			name = identifier,
			value = value,
			kind = value_type
		})!)!;

	case LexKind::EQUALS => 
		next(tokenizer);
		skip_empty(tokenizer);
		const value = tokenizer_parse_expression(tokenizer);

		let kind: VariableKind = @undefined;
		for (const token .. tokenizer.tokens) {
			if (token is *VariableToken) {
				const var = token as *VariableToken;
				if (var.name == identifier) {
					kind = var.kind;
				};
			};
		};

		append(tokenizer.tokens, alloc(VariableToken {
			name = identifier,
			value = value,
			kind = kind
		})!)!;
	case => fmt::fatalf("line {}: TOKENIZER_ERROR: invalid statement", linenum());
	};
};

fn tokenizer_parse_block(tokenizer: *Tokenizer) void = {
	const is_blockwise_tokenizer = !(tokenizer.block is void);
	const symbols = tokenizer.buffer;
	const symbols_count = len(tokenizer.buffer);
	for (!tokenizer_should_stop(tokenizer)) {
		// could not find end before buffer ran out
		if (len(tokenizer.buffer) < 3) {
			fmt::fatalf("TOKENIZER_ERROR: {}: could not find end to the block. Id: {}", globalTokenizer.linenum, (tokenizer.block as *BlockToken).id);
		};

		// label
		if (peek_next(tokenizer).kind == LexKind::COLON) {
			next(tokenizer);
			const name = next_till_nonchar_or_nondigit(tokenizer);
			append(tokenizer.tokens, alloc(LabelToken { name = name })!)!;
			next(tokenizer);
		};

		const keyword = next_till_nonchar_or_nondigit(tokenizer);
		if (len(keyword) == 0) next(tokenizer);

		// end closes block
		if (keyword == "end") {
			// stop iterating buffer when scope ends
			if (is_blockwise_tokenizer) return;

			// having end in a non-scoped context is disallowed
			fmt::fatalf("TOKENIZER_ERROR: {}: illegal \"end\" in non-scoped code", globalTokenizer.linenum);
		};

		fmt::println(keyword)!;

		// Check keyword
		if (peek_next(tokenizer).kind == LexKind::PAREN_OPEN) {
			tokenizer_parse_funcall(tokenizer, keyword);
		} else if (keyword == "go") {
			next_expect(tokenizer, LexKind::WHITESPACE);
			const label_name = next_till_nonchar_or_nondigit(tokenizer);
			append(tokenizer.tokens, alloc(GoToken { label = label_name })!)!;
		} else if (keyword == "fun") {
			skip_empty(tokenizer);
			tokenizer_parse_fun(tokenizer);
		} else if (keyword == "if") {
			tokenizer_parse_if(tokenizer);
		} else if (keyword == "return") {
			skip_empty(tokenizer);
			// Return with nothing after it => void
			if (peek_next(tokenizer).kind == LexKind::NEWLINE) {
				append(tokenizer.tokens, alloc(ReturnToken { value = create_expr(strings::toutf8("0"), ExpressionKind::INT) })!)!;
			} else {
				const value = tokenizer_parse_expression(tokenizer);
				append(tokenizer.tokens, alloc(ReturnToken { value = value })!)!;
			};
		} else if (keyword != "") {
			tokenizer_parse_variable_declaration_or_assign(tokenizer, keyword);
		};

		// increment internal linenum counter if was new line
		if (peek_next(tokenizer).kind == LexKind::NEWLINE) incr_linenum();
	};

	if (len(tokenizer.buffer) < 3) {
		fmt::fatalf("TOKENIZER_ERROR: {}: could not find end to the block. Id: {}", globalTokenizer.linenum, (tokenizer.block as *BlockToken).id);
	};
};

fn next_expect(tokenizer: *Tokenizer, expected_kind: LexKind, index: size = 0) void = {
	if (expected_kind != tokenizer.buffer[index].kind) {
		const actual_kind = tokenizer.buffer[index].kind;
		panic(format("{}: Expected '{}', got '{}'", linenum(), lexkind_to_rune(expected_kind), lexkind_to_rune(actual_kind)))!;
	} else {
		delete(tokenizer.buffer[0]);
	};
};


fn next_expect_rune(tokenizer: *Tokenizer, expected_rune: rune, index: size = 0) void = {
	if (expected_rune != tokenizer.buffer[index].value) {
		const actual_rune = tokenizer.buffer[index].value;
		fmt::fatalf("{}: Expected '{}', got '{}'", tokenizer.linenum, expected_rune, actual_rune);
	} else {
		delete(tokenizer.buffer[0]);
	};
};

fn next_till_whitespace(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].value != ' ' && tokenizer.buffer[0].value != '\n') {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_char(tokenizer: *Tokenizer, char: rune) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].value != char) {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_nonchar_or_nondigit(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].kind == LexKind::CHAR || tokenizer.buffer[0].kind == LexKind::DIGIT) {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;

};

fn incr_linenum() void = {
	globalTokenizer.linenum += 1;
};

fn next_till_kind(tokenizer: *Tokenizer, kinds: LexKind...) str = {
	const buf: []rune = [];
	for (len(tokenizer.buffer) > 0) {
		let should_break = false;
		for (const kind .. kinds) {
			if (tokenizer.buffer[0].kind == kind) {
				should_break = true;
			};
		};
		if (should_break) break;
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn next_till_nonchar(tokenizer: *Tokenizer) str = {
	const buf: []rune = [];
	for (tokenizer.buffer[0].kind == LexKind::CHAR) {
		const c: rune = tokenizer.buffer[0].value;
		append(buf, c)!;
		delete(tokenizer.buffer[0]);
	};
	return strings::fromrunes(buf)!;
};

fn create_expr_tree() *ExprTree = {
	const tree = alloc(ExprTree {
		head = null
	})!;
	return tree;
};

fn create_expr(value: []u8, kind: ExpressionKind) *Expression = {
	const value_size: size = switch (kind) {
	case ExpressionKind::INT => yield 8z;
	case ExpressionKind::STR => yield len(value) * 2;
	};
	const expr = alloc(Expression {
		kind = kind,
		value = value,
		value_size = value_size
	})!;
	return expr;
};

fn create_expr_node(value: AnyExpression) *ExprTreeNode = {
	return alloc(ExprTreeNode {
		value = value,
		next = null
	})!;
};

fn tokenizer_append_token(tokenizer: *Tokenizer, token: *Token) void = {
	pass();
};

fn tokenizer_parse_funcall_args(tokenizer: *Tokenizer) *ExprTree = {
	const tree = create_expr_tree();

	for (peek_next(tokenizer).kind != LexKind::PAREN_CLOSE) {
		const value = tokenizer_parse_expression(tokenizer);
		ll_push(tree: *LinkedList, create_expr_node(value));

		if (peek_next(tokenizer).kind == LexKind::COMMA) {
			next(tokenizer);
			skip_empty(tokenizer);
		};
	};

	return tree;
};

fn tokenizer_parse_funcall(tokenizer: *Tokenizer, func_name: str) void = {
	next_expect(tokenizer, LexKind::PAREN_OPEN);

	const arguments = tokenizer_parse_funcall_args(tokenizer);

	next_expect(tokenizer, LexKind::PAREN_CLOSE);

	append(tokenizer.tokens, alloc(FuncallToken {
		name = func_name,
		arguments = arguments,
	})!)!;
};

fn tokenizer_parse_expression(tokenizer: *Tokenizer) (*Expression | *VariableExpression | *FunctionExpression) = {
	// is it string literal?
	if (peek_next(tokenizer).kind == LexKind::QUOTE) {
		next(tokenizer);
		const value = next_till_kind(tokenizer, LexKind::QUOTE);
		next(tokenizer);
		return alloc(Expression {
			kind = ExpressionKind::STR,
			value = strings::toutf8(value),
			value_size = len(value),
		})!;
	};

	const raw_value = next_till_nonchar_or_nondigit(tokenizer);

	// is it a number literal?
	if (valid_integer(raw_value)) {
		return alloc(Expression {
			kind = ExpressionKind::INT,
			value = strings::toutf8(raw_value),
			value_size = 8,
		})!;
	};

	// is it variable?
	if (tokenizer_is_valid_variable(raw_value) && peek_next(tokenizer).kind != LexKind::PAREN_OPEN) {
		const identifier = raw_value;
		return alloc(VariableExpression {
			name = identifier,
			var = identifier
		})!;
	};

	// is it function call expression?
	if (tokenizer_is_valid_variable(raw_value) && peek_next(tokenizer).kind == LexKind::PAREN_OPEN) {
		next(tokenizer);
		const argument_tree = create_expr_tree();
		const function_expression = alloc(FunctionExpression {
			name = raw_value,
			arguments = argument_tree,
			var = void
		})!;

		for (peek_next(tokenizer).kind != LexKind::PAREN_CLOSE) {
			if (peek_next(tokenizer).kind == LexKind::COMMA) next(tokenizer);
			skip_empty(tokenizer);
			const value = tokenizer_parse_expression(tokenizer);
			ll_push(function_expression.arguments: *LinkedList, create_expr_node(value));
		};

		// Go next from PAREN_CLOSE
		next(tokenizer);

		return function_expression;
	};

	return fmt::fatal("Invalid expression");

};

fn linenum() int = {
	return globalTokenizer.linenum;
};

fn tokenizer_is_valid_variable(identifier: str) bool = {
	const identifier_runes = strings::torunes(identifier)!;
	const is_valid_variable = identifier_runes[0] == '_' || ascii::isalpha(identifier_runes[0]);
	fmt::println("is valid", is_valid_variable, identifier)!;
	return is_valid_variable;
};

fn find_return_type(tokenizer: *Tokenizer, some_expr: AnyExpression) ExpressionKind = {
	match (some_expr) {
	case let expression: *Expression =>
		return expression.kind;
	case let variable_expression: *VariableExpression =>
		const tokens = tokenizer.tokens;
		let kind: (ExpressionKind | void) = void;
		for (const token .. tokens) {
			match (token) {
			case let x: *VariableToken => 
				fmt::println("löyty", x.name)!;
				kind = x.kind;
			case let x: *FunDefToken => 
				const parameters = x.proc.parameters;
				for (const param .. parameters) {
					if (param.name == variable_expression.name) {
						kind = param.kind;
					};
				};
			case => pass();
			};
		};
		match (kind) {
		case let kind: ExpressionKind => return kind;
		case void => fmt::fatalf("Could not find variable \"{}\"", variable_expression.name);
		};
	};
};

// Returns whether there are still statements to be tokenized in the source file buffer.
fn tokenizer_has_next_statement(tokenizer: Tokenizer) bool = {
	let newlines_found = 0;
	let i: size = 0;
	for (newlines_found <= 1 && i < len(tokenizer.buffer)) {
		if (tokenizer.buffer[i].value == '\n') newlines_found += 1;
		i += 1;
	};
	return newlines_found >= 1;
};

fn tokenizer_should_stop(tokenizer: *Tokenizer) bool = {
	assert(!(tokenizer.block is void));
	const keyword = "end";
	if (len(tokenizer.buffer) <= 0 || len(tokenizer.buffer) <= len(keyword)) return true;
	const keyword_runes = strings::torunes(keyword)!;
	const block = tokenizer.block as *BlockToken;

	let found_end = true;
	for (let i: size = 0; i < len(keyword); i += 1) {
		if (tokenizer.buffer[i].value != keyword_runes[i]) {
			found_end = false;
		};
	};

	return found_end;
};

fn display_token_tree(tokens: []Token, indent: int=0) void = {
	for (const some_token .. tokens) {
		match (some_token) {
		case let token: *FunDefToken =>
			fmt::printf("FUN {} ::= (", token.name)!;
			for (const param .. token.proc.parameters) {
				fmt::printf("{}: {}", param.name, expressionkind_to_str(param.kind))!;
			};
			fmt::print(") IS")!;
			fmt::println()!;
			fmt::println("hello", len(token.body.tokens))!;
			display_token_tree(token.body.tokens[1..], 4);
			fmt::println("END\n")!;
		case let token: *FuncallToken =>
			const args: []str = [];
			const tree = token.arguments; 
			if (!ll_empty(tree: *LinkedList)) {
				const node = ll_first(tree: *LinkedList);
				for (node != null) {
					const exprNode = (node: *LinkedListNode).value: *ExprTreeNode;
					append(args, expression_to_str(exprNode.value))!;
					node = (node: *LinkedListNode).next;
				};
			};

			fmt::printfln("{}({})", token.name, join(args, ", "))!;
		case let token: *VariableToken =>
			fmt::printfln("{} ::= {}", token.name, expression_to_str(token.value))!;
		case let token: *IfToken =>
			fmt::print("IF ")!;
			let node = ll_value(ll_first(token.tree: *LinkedList)): nullable *IfCondNode;
			for (node != null) {
				const actual_node = node: *IfCondNode;
				fmt::print(expression_to_str(actual_node.expr1))!;
				fmt::print(actual_node.cmp)!;
				fmt::print(expression_to_str(actual_node.expr2))!;
				fmt::print(" DO")!;
				node = actual_node.next;
			};
			fmt::println()!;
			display_token_tree(token.body.tokens[1..], 0);
			fmt::println("END")!;
		case let token: *ReturnToken =>
			fmt::printfln("RETURN {}", expression_to_str(token.value))!;
		case let token: *LabelToken =>
			fmt::printfln("LABEL {}", token.name)!;
		case let token: *GoToken =>
			fmt::printfln("GO @{}", token.label)!;
		};
	};

};

fn print_tokenizer_table(tokenizer: (Tokenizer | void)) void = {
	tokenizer = match (tokenizer) {
	case let tokenizer: Tokenizer => yield tokenizer;
	case void => yield globalTokenizer;
	};

	const tokens = (tokenizer as Tokenizer).tokens;
	display_token_tree(tokens);
};


fn next_till_keyword(tokenizer: *Tokenizer, keyword: str) (str | void) = {
	const buf: []rune = [];
	const buffer = tokenizer.buffer;
	const keyword_runes = strings::torunes(keyword)!;
	let index = 0z;
	for (index < (len(buffer) - len(keyword))) {
		append(buf, next(tokenizer).value)!;

		// has even chance of containing the keyword
		if (len(buf) >= len(keyword)) {
			let keyword_i = len(keyword) - 1;
			let matches = true;
			for (let i: size = len(buf) - 1; i > len(buf) - len(keyword); i -= 1) {
				if (buf[i] != keyword_runes[keyword_i]) {
					matches = false;
					break;
				};
				keyword_i -= 1;
				if (matches) {
					return strings::fromrunes(buf)!;
				};
			};
		};
	};
};

