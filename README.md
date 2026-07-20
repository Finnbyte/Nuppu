# Nuppu Programming Language

## About

Nuppu is an (very) experimental and basic programming language I'll attempt to build as an experiment since I've recently been enchanted on how compilers work.

It currently contains two "versions". a very, very, very basic interpreter that does succesfully parse and execute a simple scripting language syntax, and (the main focus) a Hare-based compiler.

The legacy interpreter was a quick prototype to mock-up a basic tokenizer/parser. Using that gives more leeway to build a more robust tokenizer using Hare.

## Example

Here is a snippet of that highlights currently working features. It is a simple algorithm to produce first 10 numbers of the fibonacci sequence. I haven't had time to implement imperative loops yet, so recursion and base-cases are friend.

```
fun fib(a: int, b: int, i: int) is
   if i == 10 do
      return
   end
   let a1: int = b
   let b1: int = add(a, b)
   i = add(i, 1)
   printf("%d\n", a)
   fib(a1, b1, i)
   return
end

fun main() is
   fib(0, 1, 0)
   return
end
```
