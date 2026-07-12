# Nuppu Programming Language

## About

Nuppu is an (very) experimental and basic programming language I'll attempt to build as an experiment since I've recently been enchanted on how compilers work.

It currently contains two "versions". a very, very, very basic interpreter that does succesfully parse and execute a simple scripting language syntax, and (the main focus) a Hare-based compiler.

The legacy interpreter was a quick prototype to mock-up a basic tokenizer/parser. Using that gives more leeway to build a more robust tokenizer using Hare.

## Syntax example

Here is a snippet of the currently supported syntax:

```
let x = 10
let y = "Hello World"
y = "Hello World: Electric Boogaloo"
echo x
echo 50
toupper y
tolower "I Shall Be Lowercase"
```
