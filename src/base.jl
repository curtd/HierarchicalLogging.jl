"""
    PropagateToChildren.Mode 

When a message is received by a `logger`, determines how it will be propagted to its children

- `PropagateToChildren.AllChildren`: Propagate message to all children of `logger`
- `PropagateToChildren.DirectChildren`: Propagate message to direct children only (e.g., if a message is received by logger "A.B", it will be forwarded to "A.B.C" (if present) but not "A.B.C.D")
- `PropagateToChildren.None`: Do not propagate message to child loggers
"""
module PropagateToChildren 
    @enum Mode AllChildren DirectChildren None
end

import .PropagateToChildren

const KeyType = Vector{SubString{String}}

"""
    ROOT_LOGGER_KEY

Logger key to which all other loggers are children
"""
const ROOT_LOGGER_KEY = KeyType()

"""
    MutableLogLevel

A type representing a `LogLevel` that can be modified in-place
"""
mutable struct MutableLogLevel 
    log_level::LogLevel
end

Base.setindex!(m::MutableLogLevel, level::LogLevel) = m.log_level = level
Base.getindex(m::MutableLogLevel) = m.log_level
Base.:(==)(x::MutableLogLevel, y::MutableLogLevel) = x.log_level == y.log_level

"""
    MutableLogLevel{T<:AbstractLogger} <: AbstractLogger

A type associating a log level and name with an underlying `logger::AbstractLogger`
"""
struct MutableLogLevelLogger{T} <: AbstractLogger
    base_logger::T
    min_log_level::MutableLogLevel
    name::String
end

"""
    MutableLogLevelLogger(base_logger::AbstractLogger,        initial_log_level::LogLevel, name::String) 

Returns a `MutableLogLevelLogger` with `initial_log_level` and `name`
"""
MutableLogLevelLogger(base_logger::AbstractLogger, initial_log_level::LogLevel, name::String) = MutableLogLevelLogger{typeof(base_logger)}(base_logger, MutableLogLevel(initial_log_level), name)

Base.:(==)(x::MutableLogLevelLogger, y::MutableLogLevelLogger) = x.base_logger == y.base_logger && x.min_log_level == y.min_log_level && x.name == y.name

function Base.show(io::IO, mime::MIME"text/plain", logger::MutableLogLevelLogger)
    print(io, "MutableLogLevelLogger")
    if !isempty(logger.name)
        print(io, " - ", logger.name)
    end
    println(io, " - Min. Level - ", min_enabled_level(logger))

    print(io, "Base Logger: ")
    show(io, mime, underlying_logger(logger))
end

Base.show(io::IO, logger::MutableLogLevelLogger) = show(io, MIME("text/plain"), logger)

"""
    underlying_logger(logger::MutableLogLevel{T}) -> T

Returns the underlying logging object associated with `logger`
"""
underlying_logger(l::MutableLogLevelLogger) = l.base_logger

"""
    min_enabled_level!(logger::MutableLogLevelLogger, level) -> LogLevel 

Sets minimum enabled level for `logger` to `level`. e.g., the low level below or equal to which all messages are filtered.
"""
min_enabled_level!(logger::MutableLogLevelLogger, level) = setindex!(logger.min_log_level, log_level(level))

Logging.min_enabled_level(logger::MutableLogLevelLogger) = max(logger.min_log_level[], min_enabled_level(underlying_logger(logger)))

function Logging.shouldlog(logger::MutableLogLevelLogger, level, args...) 
    return log_level(level) ≥ logger.min_log_level[] && shouldlog(underlying_logger(logger), level, args...)
end

Logging.handle_message(logger::MutableLogLevelLogger, args...; kwargs...) = handle_message(underlying_logger(logger), args...; kwargs...)

Logging.catch_exceptions(logger::MutableLogLevelLogger) = catch_exceptions(underlying_logger(logger))
