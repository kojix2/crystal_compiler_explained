# How the Crystal Compiler Works

> **Target audience:** Developers who already understand Crystal’s type system and general compiler theory (lexing, parsing, type inference, code generation), and want to contribute to Crystal compiler internals.  
> **Goal:** Be able to read and modify code under `src/compiler/crystal/` on your own.

---

## Table of Contents

1. [Overall Architecture](#1-overall-architecture)
2. [Directory Structure Reference](#2-directory-structure-reference)
3. [AST Node System](#3-ast-node-system)
4. [Type Hierarchy](#4-type-hierarchy)
5. [Crystal::Program — The Central Database of Compilation](#5-crystalprogram--the-central-database-of-compilation)
6. [Lexing and Parsing](#6-lexing-and-parsing)
7. [The `require` System](#7-the-require-system)
8. [All Semantic Analysis Passes](#8-all-semantic-analysis-passes)
9. [Type Inference System (Core)](#9-type-inference-system-core)
10. [Macro System](#10-macro-system)
11. [LLVM Code Generation](#11-llvm-code-generation)
12. [Contribution Guide](#12-contribution-guide)

---

## 1. Overall Architecture

The Crystal compiler is a self-hosting compiler written in Crystal itself. Compilation is broadly split into three layers: **(1) frontend (parse) → (2) middle-end (semantic analysis) → (3) backend (code generation)**.

```mermaid
flowchart TD
		SRC["📄 Source code (.cr)"]

		subgraph PARSE ["① Parse"]
				P1["Lexer tokenization"]
				/* Lines 35-39 omitted */
				P4 -.-> P3
		end

		subgraph SEM ["② Semantic  ─  Program#semantic  (semantic.cr)"]
				direction TB
				/* Lines 44-52 omitted */
				S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8
		end

		subgraph CG ["③ Codegen"]
				C1["Generate LLVM IR (module split by type)"]
				/* Lines 57-58 omitted */
				C1 --> C2
		end

		LINK["🔗 System linker cc / cl.exe"]
		BIN["⚙️ Executable binary"]

		SRC --> PARSE
		PARSE --> SEM
		SEM --> CG
		CG --> LINK --> BIN
```

The frontend entry point is the `Crystal::Compiler` class in `src/compiler/crystal/compiler.cr`. The `compile(sources)` method invokes parse, semantic analysis, and code generation in sequence.

```crystal
# compiler.cr — implementation of the parse stage
private def parse(program, sources : Array)
	@progress_tracker.stage("Parse") do
		nodes = sources.map { |source| parse(program, source).as(ASTNode) }
		/* Lines 77-81 omitted */
		program.normalize(nodes)
	end
end
```

**With the `--progress` flag (or `CRYSTAL_PROGRESS=1` env var), elapsed time for each stage is printed to stderr.** This is useful for performance work and bottleneck analysis.

---

## 2. Directory Structure Reference

### `src/compiler/crystal/` — Compiler core

| Path                  | Responsibility                                                                  |
| --------------------- | ------------------------------------------------------------------------------- |
| `compiler.cr`         | `Crystal::Compiler` class. Orchestrates the full compilation pipeline           |
| `program.cr`          | `Crystal::Program` class. Central DB for types, methods, require cache, etc.    |
| `types.cr`            | Entire type system definitions (~3600 lines). Inheritance tree rooted at `Type` |
| `semantic.cr`         | Defines and invokes all semantic passes                                         |
| `crystal_path.cr`     | Filesystem path resolution for `require`                                        |
| `formatter.cr`        | `crystal format` code formatter                                                 |
| `progress_tracker.cr` | Compilation stage progress and timing                                           |

### `syntax/` — Lexing and parsing

| File                     | Responsibility                                                |
| ------------------------ | ------------------------------------------------------------- |
| `syntax/lexer.cr`        | Lexer (~2980 lines). Converts source text into `Token`s       |
| `syntax/token.cr`        | Definitions of all token kinds and keywords                   |
| `syntax/parser.cr`       | Recursive descent parser (~6500 lines). Inherits from `Lexer` |
| `syntax/ast.cr`          | All AST node classes (~2500 lines)                            |
| `syntax/visitor.cr`      | Visitor pattern base class                                    |
| `syntax/transformer.cr`  | Transformer base class for tree-to-tree conversion            |
| `syntax/location.cr`     | Source position value object (file, line, column)             |
| `syntax/to_s.cr`         | Converts AST nodes back into Crystal source text              |
| `syntax/virtual_file.cr` | Virtual source file management after macro expansion          |

### `semantic/` — Semantic analysis

| File                                     | Responsibility                                                          |
| ---------------------------------------- | ----------------------------------------------------------------------- |
| `semantic/top_level_visitor.cr`          | Pass 1: declaration handling for class/module/def/macro                 |
| `semantic/main_visitor.cr`               | Main pass: core type inference (~3700 lines)                            |
| `semantic/semantic_visitor.cr`           | Shared base class for the two visitors above; also handles `require`    |
| `semantic/bindings.cr`                   | Type dependency graph for AST nodes. Uses `SmallNodeList` observers     |
| `semantic/call.cr`                       | `Call#recalculate` — core call-site type inference                      |
| `semantic/method_lookup.cr`              | Overload resolution                                                     |
| `semantic/type_merge.cr`                 | Union synthesis algorithm for multiple types                            |
| `semantic/restrictions.cr`               | Evaluates type restrictions like `def foo(x : Int32)`                   |
| `semantic/filters.cr`                    | Control-flow narrowing via `is_a?`, `nil?`, etc.                        |
| `semantic/cleanup_transformer.cr`        | Dead code elimination and AST post-processing                           |
| `semantic/type_declaration_processor.cr` | Handles type declarations like `@x : Int32`                             |
| `semantic/abstract_def_checker.cr`       | Verifies implementations of abstract methods                            |
| `semantic/recursive_struct_checker.cr`   | Detects recursive structs (required because codegen cannot handle them) |
| `semantic/literal_expander.cr`           | Expands literals like `[1, 2, 3]` into method calls                     |
| `semantic/exhaustiveness_checker.cr`     | Exhaustiveness checks for `case/in`                                     |

### `codegen/` — LLVM code generation

| File                    | Responsibility                                                       |
| ----------------------- | -------------------------------------------------------------------- |
| `codegen/codegen.cr`    | Defines `CodeGenVisitor` (~2630 lines)                               |
| `codegen/llvm_typer.cr` | Crystal type → LLVM type mapping table                               |
| `codegen/llvm_id.cr`    | Assigns `type_id` integers to types                                  |
| `codegen/call.cr`       | LLVM IR generation for method calls                                  |
| `codegen/primitives.cr` | Converts primitives (integer ops etc.) directly to LLVM instructions |
| `codegen/unions.cr`     | Generates tagged-union memory layout for union types                 |
| `codegen/cast.cr`       | Generates type cast instructions                                     |
| `codegen/debug.cr`      | Generates DWARF debug info                                           |
| `codegen/exception.cr`  | LLVM implementation of `rescue/ensure` (`landingpad`)                |
| `codegen/target.cr`     | Target architecture/OS configuration                                 |
| `codegen/abi/`          | ABI implementations: `x86_64`, `aarch64`, `arm`, `wasm32`, etc.      |

### `macros/` — Macro system

| File                    | Responsibility                                                     |
| ----------------------- | ------------------------------------------------------------------ |
| `macros/interpreter.cr` | `MacroInterpreter < Visitor` — interpreted execution of macro code |
| `macros/macros.cr`      | Core macro expansion logic                                         |
| `macros/methods.cr`     | Macro methods (`.stringify`, `.instance_vars`, etc.)               |
| `macros/types.cr`       | Access to type information from within macros                      |

---

## 3. AST Node System

### `Crystal::ASTNode` — Base class of all nodes

Defined in `syntax/ast.cr`. Every AST node inherits from this abstract class.

```crystal
abstract class ASTNode
	property location : Location?       # node start position
	property end_location : Location?   # node end position

	def clone   # deep copy (heavily used in macro expansion)
		clone = clone_without_location
		/* Lines 178-181 omitted */
		clone
	end
end
```

After semantic analysis, `semantic/bindings.cr` adds the following:

```crystal
class ASTNode
	getter dependencies : SmallNodeList = SmallNodeList.new  # dependency nodes
	# @observers is private; access via add_observer/notify_observers
	@type : Type?  # set after semantic analysis
end
```

### ASTNode class diagram

```mermaid
classDiagram
		class ASTNode {
				<<abstract>>
				/* Lines 202-209 omitted */
				+notify_observers() void
		}
		class Expressions {
				+expressions : Array~ASTNode~
				+keyword : Keyword
		}
		class Nop
		class Var {
				+name : String
		}
		class Call {
				+obj : ASTNode?
				/* Lines 221-223 omitted */
				+block : Block?
		}
		class Def {
				/* Lines 226-270 omitted */
		ControlExpression <|-- Next
```

### Visitor and Transformer

**`Visitor`** (`syntax/visitor.cr`) is the read-only tree traversal pattern. Implement `visit(node : NodeType)` to process nodes. Most semantic passes inherit from `Visitor`.

**`Transformer`** (`syntax/transformer.cr`) is the pattern that returns transformed nodes. `transform(node : NodeType)` receives a node and returns its transformed replacement. `CleanupTransformer`, etc., use this.

### Dual nature of `ASTNode`

`ASTNode` serves both as a **syntax node** and a **typed node**, but those roles are separated in time.

```
After parse (untyped state):
	ASTNode
	/* Lines 288-290 omitted */
	└── @dependencies = []     # dependency graph still empty

After semantic analysis (typed state):
	ASTNode
	/* Lines 294-297 omitted */
	└── @observers = [...]      # nodes observing this node's type changes
```

### Special role of `Expressions`

`Expressions` in `syntax/ast.cr` is the only node representing a Crystal “list of statements” (block), and it underpins most other nodes.

```crystal
class Expressions < ASTNode
	enum Keyword
		/* Lines 307-313 omitted */
	property keyword : Keyword = Keyword::None
```

**`Expressions.from` factory method** is used throughout the compiler:

```crystal
# empty array -> Nop.new (do-nothing node)
# one element -> return it directly (do NOT wrap in Expressions)
# two or more elements -> Expressions.new
def self.from(obj : Array)
	case obj.size
	/* Lines 324-327 omitted */
	end
end
```

Why this matters: in ASTs after `require` expansion, `Expressions.from` avoids creating unnecessary wrappers for single-file cases. This improves performance and simplifies downstream visitors.

### `MainVisitor#visit(node : Expressions)` behavior

In `Expressions` visit, **only the last expression carries the resulting type; preceding expressions are evaluated only for side effects**:

```crystal
def visit(node : Expressions)
	exp_count = node.expressions.size
	/* Lines 340-352 omitted */
	false
end
```

`ignoring_type_filters` is a mechanism to prevent type-filter side effects (`is_a?`, etc.) from leaking from intermediate expressions.

### `FileNode` — File boundary node

When `require` is expanded, `FileNode`s are inserted into `Expressions`. `FileNode` stores filename information, and when visited by `MainVisitor`, it **switches `@vars` and `@meta_vars` to file-local scopes**:

```crystal
def visit(node : FileNode)
	old_vars = @vars
	/* Lines 365-377 omitted */
	false
end
```

This prevents top-level variables from one file leaking into others. `program.file_module(filename)` looks up `Program#file_modules`, allowing reuse of the same `FileModule` even when the file is visited multiple times.

### Major ASTNode subclass categories

| Category             | Representative nodes                                             | Characteristic                                                           |
| -------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Literals**         | `NumberLiteral`, `StringLiteral`, `BoolLiteral`, `SymbolLiteral` | Type is fixed immediately after parse via `set_type`                     |
| **References**       | `Var`, `InstanceVar`, `ClassVar`, `Global`, `Path`               | Linked into dependency graph via `bind_to`                               |
| **Calls**            | `Call`                                                           | `recalculate` repeatedly infers call types via observer mechanism        |
| **Control flow**     | `If`, `While`, `Return`, `Yield`, `Block`                        | Node type is determined by merging child types                           |
| **Declarations**     | `Def`, `ClassDef`, `ModuleDef`, `MacroDef`                       | Return no meaningful value (`Nil` type); mutate `Program` as side effect |
| **Type annotations** | `TypeDeclaration`, `UninitializedVar`                            | Set `freeze_type` to lock variable type                                  |
| **Conversions**      | `Cast (as)`, `IsA (is_a?)`, `NilableCast (as?)`                  | Generate type filters and conversion nodes                               |

### Basic call contract

Protocol defined in `syntax/visitor.cr`:

```crystal
class Visitor
	def visit_any(node) = true   # common pre-hook for all nodes (default: continue)
	def end_visit(node) = nil    # post-hook (default: no-op)
end

class ASTNode
	def accept(visitor)
		/* Lines 409-420 omitted */
	end
end
```

When `visit` returns `false`, **child traversal is stopped**. Most semantic `visit` methods manually `accept` children and then return `false`, preventing double traversal by default `accept_children`.

Example `Expressions#accept_children`:

```crystal
class Expressions < ASTNode
	def accept_children(visitor)
		/* Lines 431-432 omitted */
	end
end
```

Declaration nodes like `Def` return `false` in `TopLevelVisitor` to stop walking method bodies. Bodies are traversed only in `MainVisitor`.

### Cross-cutting logic via `visit_any`

`MainVisitor#visit_any`:

```crystal
def visit_any(node)
	@unreachable = false   # reset unreachable flag when entering any node
	super
end
```

`@unreachable` becomes `true` after `NoReturn` expressions (`raise`, `return`, etc.) and is used to skip inference of subsequent expressions. Resetting it in `visit_any` ensures fresh state at each node entry.

### Transformer traversal

`Transformer` has a traversal mechanism independent from `Visitor`. `ASTNode#transform(transformer)` transforms and returns a new node:

```crystal
class ASTNode
	def transform(transformer)
		/* Lines 458-465 omitted */
	end
end
```

Example in `CleanupTransformer`: if an `If` node is proven to always execute only its `then` branch (for example, because `else` is `NoReturn`), it returns the `then` content to replace the `If` node.

---

## 4. Type Hierarchy

`types.cr` (~3600 lines) implements the entire type system. A condensed inheritance tree:

```
Type (abstract)
├── NoReturnType            # type of expressions that never return a value (raise, exit, etc.)
├── VoidType                # C-like void
├── NilType                 # type of nil
├── BoolType
├── IntegerType
│   ├── Int8Type, Int16Type, Int32Type, Int64Type, Int128Type
│   └── UInt8Type, UInt16Type, UInt32Type, UInt64Type, UInt128Type
├── FloatType
│   ├── Float32Type
│   └── Float64Type
├── NamedType               # base for named types
│   ├── ModuleType
│   │   ├── NonGenericModuleType   ← Program inherits from this
│   │   └── GenericModuleType      (e.g. Comparable(T))
│   ├── ClassType
│   │   ├── NonGenericClassType    (e.g. String, IO)
│   │   └── GenericClassType       (e.g. Array(T), Hash(K,V))
│   ├── StructType
│   │   ├── NonGenericStructType
│   │   └── GenericStructType      (e.g. Tuple(T*))
│   ├── EnumType
│   ├── LibType                    # `lib Foo` block
│   └── AliasType                  # `alias Foo = Bar`
├── UnionType               # A | B. Cached in Program#unions
├── PointerInstanceType     # instance-side type for Pointer(T)
├── ProcInstanceType        # instance-side type for Proc(A, B, R)
└── VirtualType             # virtual dispatch type for abstract classes
```

### Type class diagram

```mermaid
classDiagram
		class Type {
				/* Lines 513-576 omitted */
		NonGenericModuleType <|-- Program
```

**`VirtualType`** is especially important. If `abstract class Animal` has subclasses `Dog` and `Cat`, a variable typed as `Animal` is represented as `VirtualType(Animal)`. In codegen, it is lowered into a tagged union (similar to regular union representation) to enable virtual dispatch.

> **📊 Cross-language comparison: Union and Nil safety**
>
> **Union implementation:**
>
> | Language | Model | Runtime representation | Safety |
> |---|---|---|---|
> | **Crystal** | Flat union (`A \| B \| C`, singleton per same composition) | `{type_id: i32, data: union}` tagged union | ◎ Full case analysis at compile time |
> | Rust | Algebraic data type (`enum`, named variants) | Tagged union (size aligned to max variant) | ◎ Exhaustive `match` required |
> | TypeScript | Structural union (`A \| B`) | No runtime tag (duck typing) | △ Relies on type guards |
> | Haskell | ADT (`data Either a b = Left a \| Right b`) | Heap pointer with tag | ◎ Exhaustive cases required |
> | C | `union` (untagged) | Raw shared memory | ✗ Manual management, unsafe |
>
> **Nil safety implementation:**
>
> | Language | Model | Syntax | Nature of nil |
> |---|---|---|---|
> | **Crystal** | `Nil` is just a type (`String \| Nil`) | `String?` is syntax sugar | Unified with union types |
> | Rust | `Option<T>` (`Some(T) \| None`) | `Option<String>` | Special case of ADT |
> | Swift | `Optional<T>` | `String?` | Special case of ADT |
> | Kotlin | Nullable type (`String?`) | `String?` | Built into type system as separate axis |
> | Java (<=10) | `null` exists on all reference types | none | Outside type system (unsafe) |
>
> Crystal’s biggest distinction is that **nil is not special-cased at all**. `String?` is only syntax sugar for `String | Nil`, and `Nil` is an ordinary `NilType` class. Since nil safety is provided by the same union machinery, no wrapper like `Option<T>` is needed.

---

## 5. `Crystal::Program` — The Central Database of Compilation

`Crystal::Program` in `program.cr` inherits from `NonGenericModuleType` and stores all global state related to the compilation as a whole.

```crystal
class Program < NonGenericModuleType
	# all symbols appearing in the program (:foo, :bar, etc.)
	/* Lines 614-630 omitted */
	getter splat_expansions : Hash(Def, Array(Type))
end
```

### Program class diagram

```mermaid
classDiagram
		class Type {
				/* Lines 639-676 omitted */
		Program --> "*" Type : types[]
```

Because `Program` is also the top-level module type, built-in types like `Int32` and `String` are stored as `NamedType`s under `Program`. You can look up types via `program.types["String"]`.

---

## 6. Lexing and Parsing

### Lexer

`Crystal::Lexer` in `syntax/lexer.cr` scans source text with `Char::Reader` in Unicode units and produces `Token` objects. **It is a pull model: the parser calls `next_token` on demand**, so token streams are not generated all at once.

Important state flags:

| Flag                      | Meaning                                                |
| ------------------------- | ------------------------------------------------------ |
| `slash_is_regex`          | Parse `/` as regex literal start instead of division   |
| `doc_enabled`             | Store doc comments beginning with `#` into `Token#doc` |
| `wants_def_or_macro_name` | After `def`/`macro`, accept reserved words as names    |

### Parser (recursive descent)

`Crystal::Parser` in `syntax/parser.cr` directly inherits from `Lexer` and consumes tokens through method calls in a classic recursive-descent style (~6500 lines).

```crystal
class Parser < Lexer
	enum ParseMode
		/* Lines 704-708 omitted */
	end
```

**Variable scope management is the core for identifier/call disambiguation.** `@var_scopes : Array(Set(String))` stores variable-name sets as a stack. When an identifier is read, if its name exists in the current scope set, it is parsed as a variable reference; otherwise as a zero-arg method call.

```
foo   # if "foo" exists in @var_scopes -> Var.new("foo")
foo   # if "foo" does not exist in @var_scopes -> Call.new(nil, "foo", [])
```

Entry flow is `parse` → `parse_expressions` → `parse_XXX` methods. Output is an `ASTNode` tree.

> **📊 Cross-language comparison: Lexer/Parser implementation style**
>
> | Language | Lexer | Parser | Notes |
> |---|---|---|---|
> | **Crystal** | Handwritten DFA (`case current_char`) | Handwritten recursive descent | Context-sensitive decisions via `@var_scopes` stack |
> | Rust | Handwritten DFA | Handwritten recursive descent | Resolves contextual `<` ambiguity by surrounding context |
> | Go | Handwritten DFA | Handwritten recursive descent | Minimal context dependence due to simple grammar |
> | Clang | Handwritten DFA | Handwritten recursive descent | Handles C/C++ context-dependent syntax via scope analysis |
> | Ruby (<=3.1) | flex (lexer generator) | Yacc/Bison (LR(1)) | Declarative grammar but harder error messages |
> | Ruby (3.2+) | Handwritten | LRAMA (LR, custom) | Migrated from Yacc to custom LR generator |
> | Python (3.9+) | Handwritten | PEG/Packrat (pegen) | Uses memoization for backtracking |
> | GHC (Haskell) | Alex (flex-like) | Happy (LALR) | Symbol-heavy ambiguity managed at grammar level |
>
> Crystal’s core reason for choosing handwritten recursive descent is **context sensitivity**. Whether `foo` is a variable or method call requires `@var_scopes`. Whether `{` starts a block or hash literal depends on call context. These are difficult to express naturally in declarative LR/PEG grammars, while handwritten code can directly control them through `ParseMode` and flags like `@stop_on_do`.

---

## 7. The `require` System

### File lookup: `CrystalPath`

`Crystal::CrystalPath` in `crystal_path.cr` resolves `require "foo"`.

Search path priority:

1. **`CRYSTAL_PATH` environment variable** — `:`-separated directory list
2. **`Crystal::Config.path`** — path embedded at compiler build time  
3. **`lib/`** — libraries installed by shards

**`$ORIGIN` expansion:** For install portability, a special indirection `$ORIGIN` is used to reference stdlib relative to the compiler binary location.

`require "./foo"` resolves relative to current file. `require "foo"` uses path search.

### Duplicate-prevention for `require`

Handled by `visit(node : Require)` in `semantic/semantic_visitor.cr`:

```crystal
def visit(node : Require)
	filenames = @program.find_in_path(node.string, relative_to_filename)
/* Lines 760-768 omitted */
	end
end
```

`Program#requires` is a `Set(String)` of absolute paths, so requiring the same file multiple times still processes it only once.

### Prelude bootstrap

`Compiler#parse` inserts `Require.new("prelude")` at the beginning of all source inputs. `prelude` points to `src/prelude.cr`, which then recursively requires `object.cr`, `value.cr`, `int.cr`, `string.cr`, `array.cr`, etc., defining all built-in Crystal types.

---

## 8. All Semantic Analysis Passes

`Program#semantic` in `semantic.cr` runs all passes in sequence. Each stage is wrapped with `@progress_tracker.stage("Semantic (xxx)") { ... }`.

```crystal
def semantic(node : ASTNode, cleanup = true, ...) : ASTNode
	node, processor = top_level_semantic(node)         # passes 1–5
/* Lines 787-807 omitted */
	result
end
```

Early passes invoked from `top_level_semantic`:

```crystal
def top_level_semantic(node, ...)
	# pass 1: TopLevelVisitor — register class/def/macro/alias/include declarations
	/* Lines 816-838 omitted */
	end
end
```

### Responsibility of each pass

| Pass                   | Class                            | Summary                                                                                 |
| ---------------------- | -------------------------------- | --------------------------------------------------------------------------------------- |
| top level              | `TopLevelVisitor`                | Processes only declarations of class/module/def/macro; does not instantiate types       |
| new                    | `define_new_methods`             | Auto-generates `self.new(...)` for each `initialize` overload                           |
| type declarations      | `TypeDeclarationProcessor`       | Collects explicit type declarations (`@x : Int32`) and sets freeze type (`freeze_type`) |
| abstract def check     | `AbstractDefChecker`             | Verifies every concrete class implements abstract methods                               |
| restrictions augmenter | `RestrictionsAugmenter`          | Adds implicit type restrictions to overload candidates for faster dispatch              |
| ivars initializers     | `InstanceVarsInitializerVisitor` | Associates instance var initializers (`@x = 1`) with class type info                    |
| cvars initializers     | `ClassVarsInitializerVisitor`    | Resolves global initialization order for class vars (`@@x = 1`)                         |
| main                   | `MainVisitor`                    | **Core type inference**; types all expressions and instantiates methods                 |
| cleanup                | `CleanupTransformer`             | Removes branches reduced to `NoReturn`, expands single-type unions                      |
| recursive struct       | `RecursiveStructChecker`         | Detects recursive structs with infinite size                                            |

### Full pipeline chain

```
Crystal::Compiler#compile
│
├─ parse(sources)
│   └─ Parser#parse → ASTNode
│       └─ Lexer#next_token (pull model)
│
└─ Program#semantic(node)
		│
		/* Lines 870-917 omitted */
		└─ RecursiveStructChecker#run                [pass 10]
```

### Recursive parsing during `require`

When a `require` node is reached, **`SemanticVisitor` (base of `TopLevelVisitor` and `MainVisitor`) immediately reads/parses/traverses that file**. This is not lazy; it is immediate expansion.

`semantic/semantic_visitor.cr`:

```crystal
def visit(node : Require)
	# ... skip if already expanded
	/* Lines 929-948 omitted */
	false
end

private def require_file(node : Require, filename : String)
	parser = @program.new_parser(File.read(filename))  # <- create Lexer + Parser
	/* Lines 953-961 omitted */
	FileNode.new(parsed_nodes, filename)  # <- wrap and return as FileNode
end
```

Because parse + traverse happens inside the current visitor stack frame, `require` behaves effectively as inline expansion. On error, nested messages such as “while requiring ...” are shown.

### All places where `MainVisitor` creates another `MainVisitor`

| Location             | Constructor call                                                     | Purpose                                                                     |
| -------------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Method instantiation | `MainVisitor.new(program, vars, typed_def)`                          | Type inference for method body; `typed_def` tracks current method           |
| Block                | `MainVisitor.new(program, before_block_vars, @typed_def, meta_vars)` | Block-local scope so block params don't overwrite outer vars                |
| Constant             | `MainVisitor.new(@program, meta_vars, const_def)`                    | Type inference for const initializer; managed with `inside_constant = true` |
| Closure              | `MainVisitor.new(program, fun_vars, node.def, meta_vars)`            | Body of function literals (`-> { }`, etc.)                                  |
| Interpreter          | `MainVisitor.new(from_main_visitor: @main_visitor)`                  | REPL session continuation; inherits `vars` / `meta_vars`                    |

Each new `MainVisitor` has its own `vars` map, but shares the same `Program`. Therefore, observers attached by different visitors still propagate through the same graph via `notify_observers`.

### Data written by `TopLevelVisitor`

Main writes to `Program` (and each `NamedType`):

```crystal
# ① create class/struct/module
type = NonGenericClassType.new(@program, scope, name, superclass, false)
scope.types[name] = type                   # register in Program#types

# ② register method definition
def visit(node : Def)
	node.owner = @current_type
	/* Lines 993-996 omitted */
	false   # <- do not enter body
end

# ③ register macro
def visit(node : MacroDef)
	@current_type.add_macro(node)
	/* Lines 1002-1003 omitted */
	false
end

# ④ process include/extend
def visit(node : Include)
	included_module = lookup_type(node.name)
	/* Lines 1009-1010 omitted */
	# added to @current_type.parents
end
```

`add_def` overload management (`types.cr`):

```crystal
def add_def(a_def)
	a_def.owner = self
	/* Lines 1019-1034 omitted */
	list << item   # least strict -> append at tail
end
```

`defs` is `Hash(String, Array(DefWithMetadata))`, an overload list indexed by method name. `DefWithMetadata` wraps a `Def` node plus restriction metadata (strictness of arg constraints).

### Data written by `TypeDeclarationProcessor`

```crystal
# process @x : Int32 -> set freeze_type on ivar
ivar = type.lookup_instance_var(name)
ivar.freeze_type = declared_type    # assignment of other types becomes error

# @@x : Int32 -> class var
class_var = type.lookup_class_var(name)
class_var.freeze_type = declared_type
```

When `freeze_type` is set, `ASTNode#set_type` enforces the constraint and raises `FrozenTypeException` on mismatch.

### Data written by `MainVisitor`

`MainVisitor` types every `ASTNode`, but writes to `Program` itself mostly at these points:

| Destination                          | Code                                         | Timing                        |
| ------------------------------------ | -------------------------------------------- | ----------------------------- |
| `Node#type`                          | `node.set_type(t)` / `node.bind_to(other)`   | During each node visit        |
| `Def#vars` (`typed_def.vars`)        | `meta_vars = typed_def.vars = MetaVars.new`  | During method instantiation   |
| `Program#vars`                       | `@meta_vars = @program.vars` (for top-level) | On initialization             |
| `FileModule#vars`                    | `@meta_vars = file_module.vars`              | During `FileNode` visit       |
| `Program#const_initializers`         | `program.const_initializers << type`         | During const visits           |
| `DefInstanceContainer#def_instances` | `type.add_def_instance(key, typed_def)`      | Cache on method instantiation |
| Symbol table                         | `@program.symbols << symbol_name`            | During `:foo` literal visit   |

### `DefInstanceContainer` — method-instantiation cache

To avoid repeatedly inferring the same method for the same argument type combination, `DefInstanceContainer` in `types.cr` provides a cache:

```crystal
# cache key: (original Def object id, arg type array, block type, named arg types)
record DefInstanceKey,
	def_object_id : UInt64,
	/* Lines 1076-1078 omitted */
	named_args : Array(NamedArgumentType)?

module DefInstanceContainer
	getter(def_instances) { {} of DefInstanceKey => Def }
/* Lines 1082-1089 omitted */
	end
end
```

A typed `Def` is a **clone of the original `Def` node** with type info added (and generic params substituted with concrete types when needed). Same signature → same typed `Def` reused, so even 1000 calls to `main` infer only once.

### `SemanticVisitor#current_type` — type context stack

`SemanticVisitor` has `@current_type : ModuleType` to track current class/module context during traversal:

```crystal
abstract class SemanticVisitor < Visitor
	property current_type : ModuleType  # initial value is Program itself
/* Lines 1102-1108 omitted */
	end
end
```

`visit(ClassDef)` enters via `pushing_type(node.resolved_type)`, so inner `def`/`include` declarations are registered against the correct class as `@current_type`.

---

## 9. Type Inference System (Core)

### Dependency graph and type propagation

Crystal’s inference works like **Andersen-style data-flow propagation** over a dependency graph.

Each `ASTNode` is extended in `semantic/bindings.cr` and becomes a node in the dependency graph:

```crystal
struct SmallNodeList
	# stores first two elements inline; additional ones in @tail Array
	/* Lines 1127-1132 omitted */
	...
end

class ASTNode
	getter dependencies : SmallNodeList  # nodes this node depends on
	/* Lines 1137-1138 omitted */
	@type : Type?
end
```

Propagation mechanism:

1. **`bind_to(node)`** — sets both `self.dependencies << node` and `node.observers << self`  
2. **`type=`** — when `@type` changes, calls `notify_observers`  
3. **`notify_observers`** — recursively calls each observer’s `update_type`, cascading changes

```crystal
def type=(type)
	return if @type.same?(type) || (!type && !@type)
	/* Lines 1151-1153 omitted */
	@type
end

def bind_to(node : ASTNode) : Nil
	bind(node) do
		/* Lines 1158-1160 omitted */
	end
end
```

### Dual tracking: `vars` and `meta_vars`

`MainVisitor` tracks variable types in **two dictionaries**:

```crystal
class MainVisitor < SemanticVisitor
	# vars: variable type at current execution point (single/concrete)
	/* Lines 1171-1176 omitted */
	getter meta_vars : MetaVars
end
```

`vars` is snapshotted across control flow (`if`/`while`/`rescue`, etc.) and merged after branching. `meta_vars` accumulates across the entire method and becomes final local declaration types.

**Control-flow narrowing (type narrowing)**  
Implemented in `semantic/filters.cr`. In `if x.is_a?(Int32)`, `x` is narrowed to `Int32` in then-branch and to “original minus Int32” in else-branch. This is done by storing `TypeFilter` in `vars[name].filter`, then applying it in `MainVisitor#visit(Var)`.

### `Call#recalculate` — core of call-site inference

In `semantic/call.cr`, `recalculate` is rerun whenever callee type changes. It is automatically triggered by observer propagation in the dependency graph.

```crystal
def recalculate
	obj = @obj
	/* Lines 1192-1210 omitted */
	# -> bind_to return value node to establish type propagation
end
```

### `type_merge` — union synthesis

`semantic/type_merge.cr` merges multiple types into unions. Two-type merge is optimized because it is the most frequent case:

```crystal
def type_merge(first : Type?, second : Type?) : Type?
	return first if first == second   # same type -> return either
	/* Lines 1221-1227 omitted */
	combined_union_of compact_types({first, second})
end

def compact_types(objects, &) : Array(Type)
	all_types = Array(Type).new(objects.size)
	/* Lines 1232-1235 omitted */
	all_types
end
```

`add_type` recursively flattens `UnionType`, so `(A | B) | C` normalizes to `A | B | C`. `Program#unions` caches unions so identical compositions are represented by a single object.

> **📊 Cross-language comparison: type inference strategy**
>
> | Language | Strategy | Annotation at function boundary | Global inference |
> |---|---|---|---|
> | **Crystal** | Data-flow propagation (observer pattern) | Unnecessary (return types inferred too) | ◎ Yes |
> | Haskell / ML | Hindley–Milner (constraint unification) | Unnecessary | ◎ Yes |
> | Rust | Bidirectional local inference | Required (function signatures explicit) | △ Mostly intra-function |
> | TypeScript | Bidirectional + structural typing | Optional (falls back to `any`) | △ Limited |
> | Go | Declaration-time only (`:=`) | Required | ✗ Almost none |
> | Java / C# | Local vars only (`var`/local) | Required | ✗ None |
>
> Crystal does not use an HM-style global constraint solver; instead, it uses **observer-based propagation over AST dependency graph nodes**. If return type of `foo()` changes later, type of `x` in `x = foo()` is automatically recalculated.

---

## 10. Macro System

### Concept

Crystal macros are expanded **at AST level** during compilation. They are not runtime metaprogramming. Macro calls are detected by `TopLevelVisitor` or `MainVisitor`, then evaluated by `MacroInterpreter`.

### Behavior of `MacroInterpreter`

`MacroInterpreter < Visitor` in `macros/interpreter.cr` is a VM that interprets macro AST. It does not compile to machine code; instead, it visits AST directly and writes output text into `@str : IO::Memory`.

Expansion flow:

```
① TopLevelVisitor detects macro call `Call`
② Create MacroInterpreter.new(macro_def, call_args)
	 - bind arguments into @vars : Hash(String, ASTNode)
③ Evaluate macro_def.body via visitor.visit()
	 - {{ var }}  -> fetch from @vars and .to_s
	 /* Lines 1274-1275 omitted */
	 - {% for x in items %} -> expand loop over items
④ Re-parse @str contents as Crystal source -> get ASTNode
⑤ Insert resulting ASTNode at original macro call site
⑥ Record expanded source in VirtualFile (for error line mapping)
```

### Macro methods (introspection)

`macros/methods.cr` implements special methods callable inside macros:

| Macro method              | Return value                  | Notes                                |
| ------------------------- | ----------------------------- | ------------------------------------ |
| `@type.instance_vars`     | `ArrayLiteral`                | names/types of all instance vars     |
| `@type.methods`           | `ArrayLiteral`                | all method definitions               |
| `@type.subclasses`        | `ArrayLiteral`                | direct subclasses                    |
| `@type.ancestors`         | `ArrayLiteral`                | ancestor types                       |
| `@type.has_method?(:foo)` | `BoolLiteral`                 | method existence check               |
| `system("cmd")`           | `StringLiteral`               | run shell command at compile time    |
| `run("path.cr", args)`    | `StringLiteral`               | compile+run external Crystal program |
| `env("VAR")`              | `StringLiteral or NilLiteral` | read environment variable            |

`@type` is the type at macro expansion site context. Inside instance methods, it refers to receiver type; inside class methods, class type.

> **📊 Cross-language comparison: macro systems**
>
> | Language | Model | Execution timing | Input/Output |
> |---|---|---|---|
> | **Crystal** | AST macro (interpreted by `MacroInterpreter`) | Semantic phase (type info accessible) | Crystal source string → reparse |
> | Rust | `macro_rules!` + proc macro | After parse, before typing (proc macro is pre-type) | TokenStream → TokenStream |
> | C | Text substitution preprocessor | Before parse | Text → Text (no type info) |
> | Lisp / Clojure | Homoiconic macro (code=data) | After read, before eval | S-expression → S-expression |
> | Nim | Typed AST macros | Semantic phase | Typed AST → Typed AST |
> | Haskell | Template Haskell | After type checking | AST construction in Q monad |
>
> Crystal’s standout point is **type-info access plus string-based output**. You can inspect semantic info via `@type.instance_vars`, `@type.methods`, `@type.subclasses` while generating code. Output is Crystal **source text**, reparsed and re-analyzed, unlike systems that directly construct AST/token structures.

---

## 11. LLVM Code Generation

### `CodeGenVisitor`

`CodeGenVisitor` in `codegen/codegen.cr` inherits from `Visitor` and transforms typed AST into LLVM IR.

Runtime functions expected by compiler (implemented in `libcrystal`):

```crystal
MAIN_NAME              = "__crystal_main"        # generated entry point
RAISE_NAME             = "__crystal_raise"       # throw exception
RAISE_OVERFLOW_NAME    = "__crystal_raise_overflow"
RAISE_CAST_FAILED_NAME = "__crystal_raise_cast_failed"  # as! failure
MALLOC_NAME            = "__crystal_malloc64"    # GC heap allocation
MALLOC_ATOMIC_NAME     = "__crystal_malloc_atomic64"     # for non-pointer data
REALLOC_NAME           = "__crystal_realloc64"
ONCE_INIT              = "__crystal_once_init"   # class var once-initialization
```

### Multi-module compilation

By default, Crystal generates separate `LLVM::Module`s per type and compiles in parallel (up to 8 threads). With `--release` or `--single-module`, all code is merged into one `LLVM::Module` to benefit from LTO.

### `LLVMTyper` — Crystal type → LLVM type mapping

`LLVMTyper` in `codegen/llvm_typer.cr` performs type lowering.

**`String` layout:**

```crystal
def llvm_string_type(bytesize)
	@llvm_context.struct [
		/* Lines 1345-1349 omitted */
	]
end
```

**`Proc` layout:** two-element tuple of closure data and function pointer

```crystal
def proc_type
	@llvm_context.struct [
		/* Lines 1358-1360 omitted */
	], "->"
end
```

**`Nil` layout:** empty struct (zero bytes)

```crystal
def nil_type
	@llvm_context.struct([] of LLVM::Type, "Nil")
end
```

**Handling recursive types:** `@wants_size_cache` and `@wants_size_struct_cache` prevent infinite recursion during size computation. For example, while sizing struct `Foo` containing `Pointer(Int32 | Foo)`, pointer size is approximated as machine word size during union sizing.

### Union memory layout

Implemented in `codegen/unions.cr` as tagged union:

```
{ i32 type_id, [N x i8] data }
```

- `type_id`: integer tag indicating which concrete type is stored (`LLVMTyper#type_id` assigns per type)
- `data`: byte storage sized to max of all member types

Dispatch reads `type_id`, branches, bitcasts to concrete type, then loads. `VirtualType` uses the same representation.

### Primitive operations

`codegen/primitives.cr` directly lowers integer/floating-point ops and pointer ops into LLVM instructions. For example, `Int32#+` becomes LLVM `add nsw i32` (`nsw` allows UB on signed overflow to help optimization).

### ABI implementations

`codegen/abi/` contains C calling convention logic for each target. With Crystal `lib` interop, argument and return register placement differs per architecture; this is handled by ABI layer.

| File               | Target                                  |
| ------------------ | --------------------------------------- |
| `abi/x86_64.cr`    | Linux/macOS x86-64 (System V AMD64 ABI) |
| `abi/x86_win64.cr` | Windows x86-64 (Microsoft x64 ABI)      |
| `abi/aarch64.cr`   | ARM64 (AARCH64 Procedure Call Standard) |
| `abi/arm.cr`       | ARM 32-bit                              |
| `abi/wasm32.cr`    | WebAssembly 32-bit                      |
| `abi/avr.cr`       | AVR microcontrollers                    |

### Splitting unit

Default mode (without `--single-module`) splits **by type** into LLVM modules. `CodeGenVisitor#type_module(type)` controls mapping:

```crystal
def type_module(type)
	return @main_module_info if @single_module   # all-in-one with --single-module
/* Lines 1413-1431 omitted */
	end
end
```

**`@modules : Hash(String, ModuleInfo)`** stores all modules keyed by type name string (empty string key = main module).

**`@types_to_modules : Hash(Type, ModuleInfo)`** caches type-object to module mapping, ensuring repeated `type_module` calls for the same type return the same `ModuleInfo`.

### `ModuleInfo` contents

```crystal
record ModuleInfo,
	mod : LLVM::Module,           # LLVM module body
	/* Lines 1444-1445 omitted */
	builder : CrystalLLVMBuilder  # LLVM IR builder
```

Each module has its **own `LLVM::Context`**. This is crucial for parallel safety because LLVM contexts are not thread-safe.

### Parallel compile and bitcode relay

```
On main thread:
	each type -> CodeGenVisitor.visit() -> LLVM::Module (in memory)

In parallel (n_threads workers / processes):
	each CompilationUnit:
```

**LLVM IR generation is single-threaded** (shared global LLVM context), while **optimization and object emission are parallelized**.

Implementation differs between `--preview_mt` (thread model) and normal (fork model):

```crystal
private def parallel_codegen(units, n_threads)
	{% if flag?(:preview_mt) %}
		/* Lines 1471-1478 omitted */
	{% end %}
end
```

In `fork_codegen`, child processes run in isolated address spaces, avoiding LLVM context conflicts. In `mt_codegen`, `unit.generate_bitcode` runs single-threaded (shared context), then units are sent via channel and each worker runs `unit.compile(isolate_context: true)` after reparse into isolated context.

### File cache and incremental compile

Compilation outputs are cached under `CacheDir.instance.directory_for(sources)`. Each `CompilationUnit` caches both `.bc` (bitcode) and `.o` files, and **reuses `.o` for unchanged type modules**:

```
Output cache layout:
~/.cache/crystal/<hash>/
├── String.bc                 # bitcode for String type
├── String.o                  # object file for String type
├── Array(Int32).bc
├── Array(Int32).o
├── (main).bc                 # top-level code
├── (main).o
└── bc_flags                  # compiler-flag cache key
```

`bc_flags_changed?` detects compiler flag changes (target, opt level, etc.) and triggers full rebuild if changed. Even with same flags, if `.bc` hash differs, only affected modules are recompiled.

> **📊 Cross-language comparison: parallelization unit**
>
> | Language | Parallelization unit | Invalidation scope when unit changes | Cache granularity |
> |---|---|---|---|
> | **Crystal** | **Type** (`String`, `Array(Int32)`, etc.) | Only `.o` files with methods on that type | Per-type `.bc` / `.o` |
> | Rust | Crate (`Cargo.toml` unit) | Entire crate recompiles | Per-crate `.rlib` |
> | Go | Package (directory unit) | Entire package recompiles | Per-package `.a` |
> | C / C++ | Translation unit (`.c` / `.cpp`) | That file only (headers can propagate broadly) | Object file |
> | Swift | Module + file | Module-wide (under WMO) | Per-module |
> | Java / Kotlin | Class file (`.class`) | Dependency chain may propagate | `.class` file |
>
> Crystal’s **type-level** unit is unique among mainstream languages. Adding a method on `String` does not require recompiling `Array(Int32).o` if unchanged.

### End-to-end transform flow in `CodeGenVisitor`

`CodeGenVisitor` in `codegen/codegen.cr` converts **typed AST** to LLVM IR. Since semantic analysis already fixed all node types, codegen mostly reads type metadata.

```mermaid
flowchart TD
		A["Typed ASTNode tree"]
		/* Lines 1523-1525 omitted */
		D["visit(Assign)
store instruction"]
		E["visit(If)
br + phi"]
		F["visit(Call)
codegen_call"]
		G["visit(While)
loop basic blocks"]
		H["visit(NumberLiteral)
LLVM::Value constant"]
		I["inside codegen_call"]
		/* Lines 1536-1537 omitted */
		K["visit_primitive
primitive instructions
(add nsw, fadd, etc.)"]
		L["codegen_dispatch
type_id switch
virtual dispatch"]
		M["normal call instruction
single concrete type"]
		N["LLVM::Module
(split by type)"]

		/* Lines 1548-1554 omitted */
		D & E & G & H & K & L & M --> N
```

For each visited node, the resulting value is set into `@last : LLVM::Value`; parent generation reads from `@last`.

### LLVM IR examples for major nodes

#### `Assign` → `store`

```crystal
# Crystal: x = 42
# ↓
def visit(node : Assign)
	target, value = node.target, node.value
	/* Lines 1568-1571 omitted */
	store val, ptr                       # LLVM store
end
```

Generated IR:
```llvm
%x = alloca i32
store i32 42, i32* %x
```

#### `If` → `br` + `phi`

```crystal
# Crystal: y = x > 0 ? x : -x
# ↓
def visit(node : If)
	node.cond.accept self
	/* Lines 1588-1606 omitted */
	@last = phi(llvm_type(node.type), {then_val => then_block, else_val => else_block})
end
```

#### `While` → loop basic blocks

```llvm
; Crystal: while i < 10; i += 1; end
entry:
	br label %while_cond

while_cond:
	%cmp = icmp slt i32 %i, 10
	br i1 %cmp, label %while_body, label %while_exit

while_body:
	; body for i += 1
	br label %while_cond

while_exit:
	; following code
```

`While` creates `while_cond`, `while_body`, and `while_exit`, connected by `cond_br`/`br`.

### Virtual dispatch generation (`VirtualType` / `Union`)

Handled by `codegen_dispatch` in `codegen/call.cr`. When receiver is `VirtualType` or `UnionType`, it emits LLVM `switch` over `type_id`:

```
; call meow on Animal (VirtualType)
%type_id = getelementptr %Animal, %Animal* %recv, i32 0, i32 0
%tid = load i32, i32* %type_id
switch i32 %tid, label %dispatch_fail [
	i32 1, label %call_Dog_meow
	i32 2, label %call_Cat_meow
]

call_Dog_meow:
	call void @"*Dog#meow<Dog>"(%Dog* %recv_cast)
	br label %join
call_Cat_meow:
	call void @"*Cat#meow<Cat>"(%Cat* %recv_cast)
	br label %join
```

If type is concrete (or only one overload match), switch is skipped and a direct `call` is emitted.

### Closures and Proc literals

Proc literals (`-> { }`, method refs) are handled in `visit(node : ProcLiteral)` of `codegen/codegen.cr`.

**Memory layout:** Proc is two-word struct `{void* closure_data, void* func_ptr}` (`LLVMTyper#proc_type`).

```
┌───────────────────┬──────────────────┐
│ closure_data ptr  │  func_ptr        │
│ (8 bytes)         │  (8 bytes)       │
└───────────────────┴──────────────────┘
```

**Closure data heap allocation:** if captures exist, codegen allocates closure struct with `__crystal_malloc64` and copies captured values:

```llvm
; closure generation for -> { puts x } (captures x)
%closure = call i8* @__crystal_malloc64(i64 8)      ; space for x
%x_slot  = getelementptr i8, i8* %closure, i64 0    ; x field in closure
store i64 %x_val, i64* %x_slot                      ; copy current value

%proc.0 = insertvalue { i8*, i8* } undef, i8* %closure, 0
%proc.1 = insertvalue { i8*, i8* } %proc.0, i8* @"~closure_0", 1
; -> { closure_data=..., func_ptr=@~closure_0 }
```

**Closure call:** on `proc.call(args)`, extract function pointer and pass closure data as implicit first argument:

```llvm
%fp  = extractvalue { i8*, i8* } %proc, 1    ; function pointer
%env = extractvalue { i8*, i8* } %proc, 0    ; closure data
call i32 %fp(i8* %env, ...)                   ; insert env as first arg
```

For capture-free procs, `closure_data` is just `null`; layout stays the same.

---

## 12. Contribution Guide

### Quick file map by task

| What you want to do                 | Main files to edit                                                                              |
| ----------------------------------- | ----------------------------------------------------------------------------------------------- |
| Add a new keyword                   | `syntax/token.cr` → `syntax/lexer.cr` → `syntax/parser.cr`                                      |
| Add new syntax/AST node             | `syntax/ast.cr` (node def) → `syntax/visitor.cr` (add visit method) → implement in each visitor |
| Change type-check rule              | `semantic/main_visitor.cr` (`visit(NodeType)` methods)                                          |
| Change overload resolution          | `semantic/method_lookup.cr`, `semantic/restrictions.cr`                                         |
| Add new builtin primitive op        | `codegen/primitives.cr` (`visit_primitive`)                                                     |
| Add macro method                    | `macros/methods.cr`                                                                             |
| Add compiler option                 | `compiler.cr` (property) → `command/compile.cr` (OptionParser)                                  |
| Change type internal representation | update both `types.cr` and `codegen/llvm_typer.cr`                                              |
| Add architecture support            | new file under `codegen/abi/` → register in `codegen/target.cr`                                 |
| Improve error message               | locate raise site with grep and edit in-place                                                   |

### Spec layout and execution

Tests under `spec/compiler/` mirror `src/compiler/crystal/` structure:

```
spec/compiler/
├── spec_helper.cr       # shared helpers (assert_type, assert_error, etc.)
├── lexer/               # tokenization unit tests
├── parser/              # AST structure checks
├── semantic/            # type inference and type error checks
├── codegen/             # runtime result checks of generated code
├── macro/               # macro expansion checks
├── normalize/           # AST normalization tests
└── formatter/           # formatter tests
```

**Commands:**

```sh
# all compiler specs (slow)
make spec/compiler

# specific file only
bin/crystal spec spec/compiler/semantic/proc_spec.cr

# specific test case by name filter
bin/crystal spec spec/compiler/semantic/ -e "proc type"

# show per-stage timings with --progress
CRYSTAL_PROGRESS=1 bin/crystal build src/compiler/crystal.cr
```

`assert_type("x = 1")` in `spec_helper.cr` checks inferred expression type. `assert_error("...", "message")` checks compiler error messages. Small focused specs using these helpers are expected in pull requests.

### Debugging tips

- **`--no-codegen`** — skip codegen and run only type checking; fast for semantic debugging  
- **`--debug`** — build with debug symbols; use `gdb`/`lldb` `bt` for readable stack traces  
- **`--dump-ll`** — save generated LLVM IR as `.ll` files in cache directory for inspection  
- **`node.to_s`** / **`node.inspect`** — dump AST nodes in human-readable form during semantic debugging

---

## Summary

The Crystal compiler is powered by tightly integrated layers:

1. **Lexer/Parser** — a 6500-line handwritten recursive-descent parser resolving ambiguity with variable-scope stack and `ParseMode`.
2. **Program** — shared object centralizing types, methods, require cache, etc.
3. **Semantic (multi-stage)** — declaration collection → type declaration processing → type inference → cleanup. Inference propagates through dependency graph with observer pattern.
4. **MacroInterpreter** — VM that directly interprets AST for compile-time code generation.
5. **CodeGenVisitor + LLVMTyper** — converts typed AST to LLVM IR. Unions use tagged representation `{type_id, data}`; procs use closure-pointer pairs.
6. **accept/visit protocol** — foundation of all visitors/transformers. Returning `false` from `visit` controls child traversal; `require` is immediate inline parse+walk in current semantic stack frame.
7. **Type-data mutation flow** — `TopLevelVisitor` builds `Program#types`, `Type#defs`, `Type#macros`; `MainVisitor` fills each `ASTNode#type` and `Def#vars` to form complete typed AST needed by codegen.
8. **Parallel compilation** — type-level LLVM module splitting plus `.o` cache enables true incremental recompilation of only changed types.
