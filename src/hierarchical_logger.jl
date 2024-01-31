"""
    to_key(input, dlm) -> Vector{SubString{String}}

Converts `input` to a `Vector{SubString{String}}` by splitting its `string` representation on the occurences of the delimiter(s) `dlm`.  `dlm`` can be any of the formats allowed by `findnext`'s first argument (i.e. as a string, regular expression or a function), or as a
single character or collection of characters.

If `dlm` is omitted, it defaults to the character `'.'`
"""
to_key(key, dlm) = to_key(string(key), dlm)
to_key(key) = to_key(key, '.')

to_key(key::KeyType, _) = key

function to_key(key::String, dlm)
    isempty(key) && return SubString{String}[]
    return split(key, dlm)
end

function to_key(_module::Module, dlm)
    name = fullname(_module)
    if first(name) == :Main && length(name) > 1
        str = join(name[2:end], dlm)
    else
        str = join(name, dlm)
    end
    return to_key(str, dlm)
end


"""
    HierarchicalLogger{T<:AbstractLogger} <: AbstractLogger

An `AbstractLogger` consisting of one or more child loggers of type `T` with associated names of the form

```julia
    key₁.key₂.key₃. ... .keyₙ
```

Given `H::HierarchicalLogger`, the parent of logger `L` with label `key₁.key₂. ... .keyⱼ` is the logger `P ∈ H` sharing the longest prefix with `L`, i.e., the label for `P` is `key₁.key₂. ... .keyᵢ` for `i < j` maximal in `H`. 

This collection always contains a logger at the root with an empty label. 
"""
struct HierarchicalLogger{T <: AbstractLogger} <: AbstractLogger 
    loggers::Trie{SubString{String}, MutableLogLevelLogger{T}}
    delimiter::Char
    propagate_messages::PropagateToChildren.Mode
    min_logging_level::MutableLogLevel
    current_logging_level::MutableLogLevel
end

function Base.show(io::IO, ::MIME"text/plain", h::HierarchicalLogger)
    print(io, "HierarchicalLogger - current log level $(h.current_logging_level) ")
end
Base.show(io::IO, h::HierarchicalLogger) = show(io, MIME("text/plain"), h)

"""
    insert_logger!(loggers::HierarchicalLogger, key, logger, [level=min_enabled_level(logger)]) 

Adds `logger` with associated `key` to `loggers`, if it does not exist.

Throws an `ArgumentException` if there is an existing logger in `loggers` with `key`
"""
function insert_logger!(h::HierarchicalLogger, key::Vector{SubString{String}}, logger, current_log_level::LogLevel=min_enabled_level(logger); inherit_parent_level::Bool=true) 
    haskey(h, key) && error("HierarchicalLogger already has a logger with name $(join(key, h.delimiter))")
    
    current_log_level = max(h.min_logging_level[], current_log_level)
    ref_logger = MutableLogLevelLogger(logger, current_log_level, join(key, h.delimiter))
    if !isempty(h.loggers)
        parent = h[key]
        if inherit_parent_level
            min_enabled_level!(ref_logger, min_enabled_level(parent))
        end
    else 
        # Adding root node
        h.current_logging_level[] = current_log_level
    end
    h.current_logging_level[] = min(h.current_logging_level[], min_enabled_level(ref_logger))
    return h.loggers[key] = ref_logger
end

insert_logger!(h::HierarchicalLogger, key, logger, current_log_level::LogLevel=min_enabled_level(logger)) = insert_logger!(h, to_key(h, key), logger, current_log_level)


"""
    set_logger!(loggers, key, logger)

Sets the logger associated with `key` in `loggers` to `logger`. 

If there is an existing value associated with `key` in `loggers`, it is overwritten. The new level of `key` is set to the maximum of the previous log level associated to `key` and the current level for `logger`.
"""
function set_logger!(h::HierarchicalLogger, key::Vector{SubString{String}}, logger)
    if haskey(h, key)
        existing_logger = h[key]
        new_level = max(min_enabled_level(existing_logger), min_enabled_level(logger))
        return h.loggers[key] = MutableLogLevelLogger(logger, new_level, join(key, h.delimiter))
    else
        return insert_logger!(h, key, logger)
    end
end
set_logger!(h, key, logger) = set_logger!(h, to_key(h, key), logger)

"""
    HierarchicalLogger(root_logger; [propagate] [, delimiter] [, min_logging_level])

Constructs a `HierarchicalLogger` with `root_logger` at its root.

# Arguments 
- `root_logger::AbstractLogger`: Logger associated with the root node
- `propagate::PropagateToChildren.Mode=PropagateToChildren.None`: Determines how messages send to a node are propagated to its children
- `delimiter::Char='.'`: Parent-child delimiter in the string representation of a node
- `min_logging_level::LogLevel=All`: Sets the initial minimum logging level for all loggers
"""
function HierarchicalLogger(root_logger::AbstractLogger; propagate::PropagateToChildren.Mode=PropagateToChildren.None, min_logging_level::Union{NamedLogLevel, LogLevel}=All, delimiter::Char='.') 
    loggers = Trie{SubString{String}, MutableLogLevelLogger{typeof(root_logger)}}()
    min_level = MutableLogLevel(min_logging_level)
    current_level = MutableLogLevel(min_level[])
    h = HierarchicalLogger(loggers, delimiter, propagate, min_level, current_level)
    insert_logger!(h, ROOT_LOGGER_KEY, root_logger)
    return h
end

function Base.empty!(h::HierarchicalLogger)
    root_logger = h[ROOT_LOGGER_KEY].base_logger
    empty!(h.loggers)
    insert_logger!(h, ROOT_LOGGER_KEY, root_logger)
    return nothing
end

"""
    closest_registered_logger(h::HierarchicalLogger{T}, key) -> T

If `haskey(h, key)`, returns the logger associated with `key`.

Otherwise, returns the logger `L ∈ h` whose asssociated key `K` satisfies `startswith(key, K)` and the key of `L` is of maximal length among all such loggers in `h`.
"""
function closest_registered_logger(h::HierarchicalLogger, key::KeyType=ROOT_LOGGER_KEY)
    st = subtry(h.loggers, key)
    return st.value
end

to_key(h::HierarchicalLogger, key) = to_key(key, h.delimiter)

Base.keys(h::HierarchicalLogger) = keys(h.loggers)

Base.haskey(h::HierarchicalLogger, key) = haskey(h.loggers, to_key(h, key))

Base.getindex(h::HierarchicalLogger, key) = closest_registered_logger(h, to_key(h, key))

function all_children(h::HierarchicalLogger, key; max_depth::Int=typemax(Int))::Vector{KeyType} 
    ref_key = to_key(h, key)
    return [ child for child in keys_with_prefix(h.loggers, ref_key; max_depth) if !(isequal(child, ref_key))]
end

direct_children(h::HierarchicalLogger, key) = all_children(h, key; max_depth=1)

"""
    min_enabled_level!(h::HierarchicalLogger, key, level; [force=true], [recurse=true]) -> LogLevel

Recursively sets the level of logger `L` associated with `key` in `h`. 

If `haskey(h, key)`, sets the logging level of `L` (and, if `recurse == true`, the level of all of its children) to `level`. If the current logging level of `L` is greater than `level`, this method will not change the existing level if `force == false`.

If `haskey(h, key) == false`, a logger is added to `key` (with base logger `underlying_logger(closest_logger(h, key))`)

Returns the new `LogLevel` associated with `key`
"""
function min_enabled_level!(h::HierarchicalLogger, key::KeyType, level; force::Bool=false, recurse::Bool=true)
    ref_level = max(log_level(level), h.min_logging_level[])
    logger = h[key]
    if !haskey(h, key)
        logger = insert_logger!(h, key, underlying_logger(logger); inherit_parent_level=false)
    end
    
    current_log_level = Logging.min_enabled_level(logger)

    if haskey(h, key) && (current_log_level < ref_level || force)
        current_log_level = min_enabled_level!(logger, ref_level)
        if key == ROOT_LOGGER_KEY
            h.current_logging_level[] = ref_level
        end
    end
    if recurse
        global_log_level = min(h.current_logging_level[], current_log_level)

        for child_key in all_children(h, key)
            child_level = min_enabled_level!(h, child_key, ref_level; force, recurse=false)
            global_log_level = min(global_log_level, child_level)
        end
        h.current_logging_level[] = global_log_level
    end
    return current_log_level
end

min_enabled_level!(h::HierarchicalLogger, key, level; kwargs...) = min_enabled_level!(h, to_key(h, key), level; kwargs...)

"""
    min_enabled_level!(h::HierarchicalLogger, level; [force], [recurse]) -> LogLevel

    Sets the logging level of the root logger in `h` to `level`. Any messages the root logger receives below `level` will be discarded and not logged.

    Returns the minimum `LogLevel` over all loggers in `h`.
"""
min_enabled_level!(h::HierarchicalLogger, level; kwargs...) = min_enabled_level!(h, ROOT_LOGGER_KEY, level; kwargs...)

# Stdlib Logging
Logging.min_enabled_level(h::HierarchicalLogger) = h.current_logging_level[]

"""
    Logging.min_enabled_level(h::HierarchicalLogger, key) -> LogLevel

Returns the minimum enabled level for the `key` in `h` (i.e., the level below which all messages are filtered)

If `!haskey(h, key)`, returns the 
"""
Logging.min_enabled_level(h::HierarchicalLogger, key) = min_enabled_level(h[key])

Logging.shouldlog(h::HierarchicalLogger, level, _module, args...) = shouldlog(h[_module], level, _module, args...)
Logging.shouldlog(h::HierarchicalLogger, level::Symbol, args...) = shouldlog(h, NamedLogLevel(level), args...)

Logging.catch_exceptions(logger::HierarchicalLogger) = catch_exceptions(logger[ROOT_LOGGER_KEY])

function Logging.handle_message(h::HierarchicalLogger, level, message, _module, args...; kwargs...)
    @nospecialize
    logger = h[_module]
    handle_message(logger, level, message, _module, args...; kwargs...)
    
    if h.propagate_messages == PropagateToChildren.AllChildren
        ref_children = all_children(h, _module)
    elseif h.propagate_messages == PropagateToChildren.DirectChildren
        ref_children = direct_children(h, _module)
    else
        ref_children = Vector{KeyType}()
    end
    for child_key in ref_children
        child_logger = h[child_key]
        if shouldlog(child_logger, level, _module, args...)
            handle_message(child_logger, level, message, _module, args...; kwargs...)
        end
    end

    return nothing
end
