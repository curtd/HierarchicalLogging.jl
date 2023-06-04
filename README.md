# HierarchicalLogging

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://curtd.github.io/HierarchicalLogging.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://curtd.github.io/HierarchicalLogging.jl/dev/)
[![Build Status](https://github.com/curtd/HierarchicalLogging.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/curtd/HierarchicalLogging.jl/actions/workflows/CI.yml?query=branch%3Amain)

`HierarchicalLogging` defines the `HierarchicalLogger` type, a [`Base.Logging`](https://docs.julialang.org/en/v1/stdlib/Logging/)-compatible logger which can be used to associate a collection of loggers to hierarchically-related objects. E.g., each node `N` is associated with a `.`-delimited key 

```julia
key(N) = key₁.key₂. ... .keyₙ
```

and a node `P` is the parent of node `C` if `startswith(label(C), label(P))`. 

The prototypical example is the `module` -> `submodule` relationship in Julia, but you might have your own hierarchically-related objects that you'd like to associate a logger with.

Each node has an associated `LogLevel` which can be set via `min_enabled_level!(logger, key, level)`, which also recursively sets the level of all children of the node with `key`. This can be helpful for loggers tied to specific submodules which are particularly noisy. 

Example:
```julia 
using HierarchicalLogging, Logging

module A
    module B
       module C
       end
    end
end
module A1
    module B1
    end
end
module A2 
end
# Logger attached to the root has the lowest possible logging level 
h = HierarchicalLogger(ConsoleLogger(All))
global_logger(h)
insert_logger!(h, A.B, ConsoleLogger(Warn))
insert_logger!(h, A1, ConsoleLogger(Debug))
@info "Hey" _module=A.B.C _file=nothing _line=1
@warn "Uhoh" _module=A.B.C _file=nothing _line=1
# A was never registered to h, so it will use the root logger to log
@debug "In A" _module=A _file=nothing _line=1
```

Output: 
```
[ Info: Hey
┌ Warning: Uhoh
└ @ Main.A.B.C
┌ Debug: In A
└ @ Main.A
```

```julia
# A wasn't registered before, this will create a copy tied to A with its own log level + set its children to level Error 
min_enabled_level!(h, A, Error)
@warn "This will be ignored" _module=A.B.C _file=nothing _line=1
@error "This won't" _module=A.B _file=nothing _line=1
min_enabled_level!(h, A, Off)
@error "Can't see this" _module=A.B _file=nothing _line=1
@error "This will still show" _module=A2 _file=nothing _line=1
```

Output:
```
┌ Error: This won't
└ @ Main.A.B
┌ Error: This will still show
└ @ Main.A2
```

Inspired by [`Memento`](https://github.com/invenia/Memento.jl)