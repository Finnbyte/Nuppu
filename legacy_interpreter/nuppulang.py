import sys
import time

is_debug = False

def shift(lst: list):
    return lst.pop(0)

def shift_till(lst: list, char: str | list[str]):
    if isinstance(char, str):
        char = [char]
    dropped = []
    while len(lst) > 1:
        dropped.append(lst.pop(0))
        if lst[0] in char:
            return dropped

def debug(*args):
    if is_debug:
        print(*args)

class VariableDeclaration:
    kind: str = "VariableDeclaration"
    name: str
    value: any
    def __init__(self):
        pass

class VariableAssignment:
    kind: str = "VariableAssignment"
    name: str
    value: any
    def __init__(self):
        pass

class FunctionCall:
    kind: str = "FunctionCall"
    name: str
    arg: any
    def __init__(self, name: str | None = None):
        self.name = name

class EndOfStatement:
    kind: str = "Nil"
    def __init__(self):
        pass

class Expression:
    kind: str = "Expression"
    value: any
    def __init__(self, value: any):
        self.value = value
        pass

class Tokenizer:
    _content_buffer = []
    _tokens = []
    _reserved_keywords = ["let", "if"]
    _builtins = ["echo", "toupper", "tolower"]
    _current_line = 1
    _cursor = 0

    def last_token(self):
        if len(self._tokens) < 1:
            return None
        return self._tokens[-1]

    def _consume(self):
        token = shift(self._content_buffer)
        return token

    def _consume_till_whitespace(self):
        return ''.join(shift_till(self._content_buffer, [" ", "\n"]))

    def _consume_till_char(self, char):
        return ''.join(shift_till(self._content_buffer, char))

    def _peek_next(self):
        return self._content_buffer[0] if not self.is_done() else None

    def get_tokenized_tokens(self):
        return self._tokens

    def __init__(self, content: str):
        self._content_buffer = list(content)

    def is_done(self):
        return len(self._content_buffer) < 1

    def _spawn_tokenizer_error(self, line: int, msg: str):
        debug(f"{line}: {msg}", file=sys.stderr)
        sys.exit(1)

    def find_variable_token_by_name(self, name: str):
        found = [token for token in self._tokens if (token.kind == "VariableDeclaration" or token.kind == "VariableAssignment") and token.name == name]
        return found[-1] if len(found) > 0 else None

    def move_tokenizer_cursor(new_index: int):
        self._cursor = new_index

    def parse_expression(self, expression: str):
        expr = list(expression)
        debug(expr, expression)
        expression = ''.join(expr)
        if expr[0] == '\"':
            # remove quotations
            expression = expression[1:-1]
            debug("parse_expression: string:", expression)
            return Expression(expression)
        elif expression.isnumeric():
            debug("parse_expression: integer:", expression)
            return Expression(int(expression))
        else:
            variable = self.find_variable_token_by_name(expression)
            debug("parse_expression: variable:", variable.name, variable.value)
            return Expression(variable.value.value)

    def parse_funcall(self, funccall: FunctionCall):
        debug("parse_funcall")
        value = self._consume_till_char("\n")
        debug("funccall value", value)
        expression = self.parse_expression(value)
        funccall.arg = expression
        self._tokens.append(funccall)
        self._tokens.append(EndOfStatement())

    def parse_variable_assignment(self, assignment: VariableAssignment):
        self._consume()
        self._consume()
        assignment.value = self.parse_expression(self._consume_till_char('\n'))
        debug("value for assignment is", assignment.value)
        debug(assignment.name, assignment.value)
        self._tokens.append(assignment)
        self._tokens.append(EndOfStatement())

    def parse_variable_declaration(self, declaration: VariableDeclaration):
        name = self._consume_till_whitespace()
        debug("helo", name)
        if name in self._reserved_keywords:
            self._spawn_tokenizer_error(self._current_line, "Cannot use \"let\" as variable name")
        declaration.name = name
        debug(self._content_buffer)
        self._consume()
        if self._peek_next() != "=":
            self._spawn_tokenizer_error(self._current_line, "Could not find equals sign")
        self._consume()
        self._consume()
        declaration.value = self.parse_expression(self._consume_till_char('\n'))
        self._tokens.append(declaration)
        self._tokens.append(EndOfStatement())

    def parse_next_statement(self):
        if self.is_done():
            return
        debug(self._content_buffer)

        while True:
            debug("next peek", self._peek_next(), self._peek_next() == None)
            debug("buffer", self._content_buffer)
            if self._peek_next() == '\n' or self._peek_next() == None:
                debug("Breaking")
                break
            token_characters = shift_till(self._content_buffer, " ")
            debug("buffer post shift", self._content_buffer)
            token = ''.join(token_characters)
            debug("token", token, token_characters)

            self._consume()

            # starts tokenizing new statement
            match token:
                case "let":
                    variable_declaration = VariableDeclaration()
                    self.parse_variable_declaration(variable_declaration)
                case _:
                    debug("Else")
                    # function call
                    if token in self._builtins:
                        self.parse_funcall(FunctionCall(token))

                    # variable assignment
                    if self._peek_next() == "=":
                        variable_assignment = VariableAssignment()
                        variable_assignment.name = token
                        self.parse_variable_assignment(variable_assignment)
                    pass

            self._current_line += 1
        self._consume()


def read_input_file(path: str):
    with open(path, "r") as f:
        return f.read()

def run_interpreter(tokenizer: Tokenizer):
    tokens = tokenizer.get_tokenized_tokens()
    variables = {}
    for token in tokens:
        if isinstance(token, VariableDeclaration):
            variables[token.name] = token.value
        if isinstance(token, VariableAssignment):
            variables[token.name] = token.value
        if isinstance(token, FunctionCall):
            match token.name:
                case "echo":
                    print(token.arg.value)
                case "tolower":
                    print(token.arg.value.lower())
                case "toupper":
                    print(token.arg.value.upper())



def main():
    executable_name = shift(sys.argv)

    if len(sys.argv) < 1:
        print("Provide input file")
        sys.exit(1)

    input_file = shift(sys.argv)
    input_file_contents = read_input_file(input_file)

    tokenizer = Tokenizer(input_file_contents)

    while not tokenizer.is_done():
        tokenizer.parse_next_statement()

    run_interpreter(tokenizer)

if __name__ == "__main__":
    main()
